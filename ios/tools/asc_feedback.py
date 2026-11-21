#!/usr/bin/env python3
"""Turn TestFlight beta feedback (screenshot and crash submissions) into GitHub issues.

One issue per submission, labelled testflight-feedback, deduplicated by a hidden marker with the submission id.
The repo is public, so an issue carries only: type, build, device, OS, locale, date and the tester's comment
(switch off with INCLUDE_COMMENT=0). Never the tester's email or name, never a screenshot or crash-log URL
(they expire and are tied to the key). Runs every 5 minutes. Logs print counts and ids only. Needs ASC_KEY_ID, ASC_ISSUER_ID and
ASC_KEY_P8 or ASC_KEY_P8_BASE64, GITHUB_TOKEN and GITHUB_REPOSITORY, plus pyjwt, cryptography and requests.

Exit code: 0 for everything except the first refused run. When App Store Connect answers 401 or 403 (the key is dead,
or its role can't read feedback or crashes) the script opens ONE issue labelled testflight-feedback-broken and exits 1,
so a reader that can't read never looks like "no feedback". While that issue stays open, later runs only warn and exit 0,
so a dead key emails once, not every 5 minutes. Close the issue after fixing the key; the next refusal opens a new one.
Network errors, missing secrets and other API errors stay warnings and exit 0.

Endpoints and attributes checked against Apple's App Store Connect OpenAPI 4.6:
GET /v1/apps?filter[bundleId], /v1/apps/{id}/betaFeedbackScreenshotSubmissions and .../betaFeedbackCrashSubmissions.
"""
import os, re, sys, time
import jwt, requests
from prune_certs import pem

ASC = "https://api.appstoreconnect.apple.com"
GH = "https://api.github.com"
LABEL = "testflight-feedback"
BROKEN_LABEL = "testflight-feedback-broken"
ASSIGNEE = os.environ.get("FEEDBACK_ASSIGNEE", "tezbo")  # assigning him is what makes GitHub Mobile push to his phone
# The TestFlight app's bundle id (the release lane overrides the project's co.codeconnectors one; docs/push-relay.md).
BUNDLE_ID = os.environ.get("BUNDLE_ID", "tezbo.Playscribe")
MIN_BUILD = int(os.environ.get("MIN_BUILD", "8"))  # backfill from 0.5.2 (8)
MAX_NEW = int(os.environ.get("MAX_NEW", "30"))
INCLUDE_COMMENT = os.environ.get("INCLUDE_COMMENT", "1") != "0"
DRY_RUN = os.environ.get("DRY_RUN", "0") == "1"
KINDS = [("betaFeedbackScreenshotSubmissions", "Screenshot feedback"), ("betaFeedbackCrashSubmissions", "Crash report")]
REFUSED = (401, 403)


class KeyRefused(Exception):
    """App Store Connect refused the key (401 or 403). The only failure that can turn the run red."""


def warn(msg):
    print(f"::warning::{msg}")


def gh_session():
    gh = requests.Session()
    gh.headers.update({"Authorization": "Bearer " + os.environ["GITHUB_TOKEN"], "Accept": "application/vnd.github+json"})
    return gh


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


def ensure_label(gh, name=LABEL, color="d93f0b", description="From TestFlight beta feedback"):
    base = f"{GH}/repos/{os.environ['GITHUB_REPOSITORY']}/labels"
    if gh.get(f"{base}/{name}", timeout=60).status_code == 404:
        gh.post(base, json={"name": name, "color": color, "description": description}, timeout=60).raise_for_status()


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
        if code in REFUSED:
            raise KeyRefused(f"App Store Connect refused the key ({code}) looking up the app")
        warn(f"Could not find the app in App Store Connect ({code}); check the key's role and the bundle id")
        return
    gh = gh_session()
    seen = existing_ids(gh)
    todo = []
    refused = []
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
            code = e.response.status_code
            if code in REFUSED:
                refused.append(f"{path} ({code})")
            warn(f"{path}: App Store Connect returned {code}; the key's role may not allow feedback")
    todo.sort(key=lambda t: t[2]["attributes"].get("createdDate") or "")
    print(f"{len(todo)} new feedback item(s); creating up to {MAX_NEW}{' (dry run)' if DRY_RUN else ''}")
    if not (DRY_RUN or not todo):
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
    if refused:
        raise KeyRefused("App Store Connect refused the key for " + ", ".join(refused))


def report_broken(reason):
    """True when this run is the first to find the refusal (it opened the issue); False when one is already open."""
    gh = gh_session()
    repo = os.environ["GITHUB_REPOSITORY"]
    r = gh.get(f"{GH}/repos/{repo}/issues", params={"labels": BROKEN_LABEL, "state": "open", "per_page": 1}, timeout=60)
    r.raise_for_status()
    if r.json():
        return False
    if DRY_RUN:
        return True
    ensure_label(gh, BROKEN_LABEL, "b60205", "TestFlight feedback reader can't read App Store Connect")
    body = (f"The TestFlight feedback reader was refused by App Store Connect: {reason}.\n\n"
            "While this stays unfixed, tester feedback and crash reports are NOT being turned into issues.\n\n"
            "Fix: check the App Store Connect API key in the repo secrets (ASC_KEY_ID, ASC_ISSUER_ID, ASC_KEY_P8). "
            "It needs the Developer role or higher. Then run the \"TestFlight feedback\" workflow with dry_run on "
            "and close this issue.\n\n"
            "Later runs warn and stay green while this issue is open.")
    gh.post(f"{GH}/repos/{repo}/issues", timeout=60,
            json={"title": "TestFlight feedback reader is refused by App Store Connect", "body": body,
                  "labels": [BROKEN_LABEL], "assignees": [ASSIGNEE]}).raise_for_status()
    return True


def run():
    # Red only on the first run that finds a refused key (401 or 403), because a reader that can't read looks the same
    # as "no feedback". Every other problem, and every later refusal while the broken issue is open, is a warning.
    try:
        main()
    except KeyRefused as e:
        try:
            first = report_broken(str(e))
        except Exception as e2:  # noqa: BLE001
            warn(f"Couldn't check or open the broken-reader issue: {type(e2).__name__}")
            first = True
        if first:
            print(f"::error::{e}; check the key's role in App Store Connect (needs Developer or higher)")
            return 1
        warn(f"{e}; the testflight-feedback-broken issue is already open")
    except Exception as e:  # noqa: BLE001
        warn(f"Feedback run stopped: {type(e).__name__}")
    return 0


if __name__ == "__main__":
    sys.exit(run())
