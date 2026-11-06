#!/usr/bin/env python3
"""Turn TestFlight beta feedback (screenshot and crash submissions) into GitHub issues.

One issue per submission, labelled testflight-feedback, deduplicated by a hidden marker with the submission id.
The repo is public, so an issue carries only: type, build, device, OS, locale, date and the tester's comment
(switch off with INCLUDE_COMMENT=0). Never the tester's email or name, never a screenshot or crash-log URL
(they expire and are tied to the key). Runs every 15 minutes; exits 0 always. Logs print counts and ids only. Needs ASC_KEY_ID, ASC_ISSUER_ID and
ASC_KEY_P8 or ASC_KEY_P8_BASE64, GITHUB_TOKEN and GITHUB_REPOSITORY, plus pyjwt, cryptography and requests.

Endpoints and attributes checked against Apple's App Store Connect OpenAPI 4.6:
GET /v1/apps?filter[bundleId], /v1/apps/{id}/betaFeedbackScreenshotSubmissions and .../betaFeedbackCrashSubmissions.
"""
import os, re, sys, time
import jwt, requests
from prune_certs import pem

ASC = "https://api.appstoreconnect.apple.com"
GH = "https://api.github.com"
LABEL = "testflight-feedback"
ASSIGNEE = os.environ.get("FEEDBACK_ASSIGNEE", "tezbo")  # assigning him is what makes GitHub Mobile push to his phone
BUNDLE_ID = os.environ.get("BUNDLE_ID", "co.codeconnectors.playscribe")
MIN_BUILD = int(os.environ.get("MIN_BUILD", "8"))  # backfill from 0.5.2 (8)
MAX_NEW = int(os.environ.get("MAX_NEW", "30"))
INCLUDE_COMMENT = os.environ.get("INCLUDE_COMMENT", "1") != "0"
DRY_RUN = os.environ.get("DRY_RUN", "0") == "1"
KINDS = [("betaFeedbackScreenshotSubmissions", "Screenshot feedback"), ("betaFeedbackCrashSubmissions", "Crash report")]


def warn(msg):
    print(f"::warning::{msg}")


def asc_session():
    now = int(time.time())
    tok = jwt.encode({"iss": os.environ["ASC_ISSUER_ID"], "iat": now, "exp": now + 1000, "aud": "appstoreconnect-v1"},
                     pem(), algorithm="ES256", headers={"kid": os.environ["ASC_KEY_ID"]})
    s = requests.Session()
    s.headers["Authorization"] = "Bearer " + tok
    return s


def pages(s, url, params=None):
    while url:
        r = s.get(url, params=params, timeout=60)
        r.raise_for_status()
        j = r.json()
        yield j
        url, params = (j.get("links") or {}).get("next"), None


def clean(text, limit=1500):
    text = re.sub(r"[\w.+-]+@[\w-]+(\.[\w-]+)+", "[email removed]", text or "")
    text = text.replace("@", "@​")  # never ping anyone from tester text
    text = text.replace("<!--", "").replace("-->", "")
    return text[:limit] + ("…" if len(text) > limit else "")


def existing_ids(gh):
    seen = set()
    for page in range(1, 50):
        r = gh.get(f"{GH}/repos/{os.environ['GITHUB_REPOSITORY']}/issues",
                   params={"labels": LABEL, "state": "all", "per_page": 100, "page": page}, timeout=60)
        r.raise_for_status()
        if not r.json():
            break
        for i in r.json():
            seen.update(re.findall(r"<!-- asc-feedback:(\S+) -->", i.get("body") or ""))
    return seen


def ensure_label(gh):
    base = f"{GH}/repos/{os.environ['GITHUB_REPOSITORY']}/labels"
    if gh.get(f"{base}/{LABEL}", timeout=60).status_code == 404:
        gh.post(base, json={"name": LABEL, "color": "d93f0b", "description": "From TestFlight beta feedback"},
                timeout=60).raise_for_status()


def build_info(j):
    out = {}
    for inc in j.get("included", []):
        if inc["type"] == "builds":
            out[inc["id"]] = inc["attributes"].get("version")
    return out


def main():
    for v in ("ASC_KEY_ID", "ASC_ISSUER_ID"):
        if not os.environ.get(v):
            warn(f"{v} is not set; skipping")
            return
    if not (os.environ.get("ASC_KEY_P8") or os.environ.get("ASC_KEY_P8_BASE64")):
        warn("ASC_KEY_P8 is not set; skipping")
        return
    s = asc_session()
    try:
        apps = s.get(f"{ASC}/v1/apps", params={"filter[bundleId]": BUNDLE_ID}, timeout=60)
        apps.raise_for_status()
        app_id = apps.json()["data"][0]["id"]
    except (requests.HTTPError, IndexError, KeyError) as e:
        code = getattr(getattr(e, "response", None), "status_code", "no app")
        warn(f"Could not find the app in App Store Connect ({code}); check the key's role and the bundle id")
        return
    gh = requests.Session()
    gh.headers.update({"Authorization": "Bearer " + os.environ["GITHUB_TOKEN"], "Accept": "application/vnd.github+json"})
    seen = existing_ids(gh)
    todo = []
    for path, title in KINDS:
        try:
            for j in pages(s, f"{ASC}/v1/apps/{app_id}/{path}",
                           {"sort": "createdDate", "limit": 200, "include": "build"}):
                builds = build_info(j)
                for item in j["data"]:
                    b = ((item.get("relationships") or {}).get("build") or {}).get("data")
                    num = builds.get(b["id"]) if b else None
                    if num is not None and num.isdigit() and int(num) < MIN_BUILD:
                        continue
                    if item["id"] not in seen:
                        todo.append((path, title, item, num))
        except requests.HTTPError as e:
            warn(f"{path}: App Store Connect returned {e.response.status_code}; the key's role may not allow feedback")
    todo.sort(key=lambda t: t[2]["attributes"].get("createdDate") or "")
    print(f"{len(todo)} new feedback item(s); creating up to {MAX_NEW}{' (dry run)' if DRY_RUN else ''}")
    if DRY_RUN or not todo:
        return
    ensure_label(gh)
    for path, title, item, num in todo[:MAX_NEW]:
        a = item["attributes"]
        build = f"build {num}" if num else "unknown build"
        comment = clean(a.get("comment")) if INCLUDE_COMMENT else ""
        head = (comment.splitlines()[0][:70] if comment else title)
        lines = [f"**{title}** on {build}", "",
                 f"- Device: {a.get('deviceModel', '?')}, iOS {a.get('osVersion', '?')}, locale {a.get('locale', '?')}",
                 f"- Sent: {a.get('createdDate', '?')}"]
        if path == "betaFeedbackScreenshotSubmissions":
            lines.append(f"- Screenshots: {len(a.get('screenshots') or [])} (open in App Store Connect › TestFlight › Feedback)")
        else:
            lines.append("- Crash log: open in App Store Connect › TestFlight › Crashes")
        if comment:
            lines += ["", "Tester comment:", "", "> " + comment.replace("\n", "\n> ")]
        lines += ["", f"<!-- asc-feedback:{item['id']} -->"]
        r = gh.post(f"{GH}/repos/{os.environ['GITHUB_REPOSITORY']}/issues", timeout=60,
                    json={"title": f"TestFlight: {head} ({build})", "body": "\n".join(lines), "labels": [LABEL], "assignees": [ASSIGNEE]})
        r.raise_for_status()
        print("created issue", r.json()["number"], "for", item["id"])
    if len(todo) > MAX_NEW:
        print(f"{len(todo) - MAX_NEW} more wait for the next run")


def run():
    # Always exit green: a red run emails Terry. Problems become warnings with no tester text in them.
    try:
        main()
    except Exception as e:  # noqa: BLE001
        warn(f"Feedback run stopped: {type(e).__name__}")
    return 0


if __name__ == "__main__":
    sys.exit(run())
