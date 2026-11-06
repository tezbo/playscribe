#!/usr/bin/env python3
"""Registers the App Store Connect webhook that tells the relay about new TestFlight feedback, and pings it.
Usage: asc_webhook.py register|ping|list. The shared secret is derived from CLOUDFLARE_API_TOKEN exactly as relay/deploy.sh
does, so nothing is pasted. Prints ASC's refusals (they carry no secrets); never prints the secret."""
import hashlib, os, sys, time
import jwt, requests
from prune_certs import pem

ASC = "https://api.appstoreconnect.apple.com"
BUNDLE_ID = os.environ.get("BUNDLE_ID", "tezbo.Playscribe")
URL = os.environ.get("RELAY_URL", "https://playscribe-relay.playscribe.workers.dev") + "/v1/webhooks/asc"
NAME = "Playscribe team alerts"
EVENTS = ["BETA_FEEDBACK_SCREENSHOT_SUBMISSION_CREATED", "BETA_FEEDBACK_CRASH_SUBMISSION_CREATED"]


def session():
    now = int(time.time())
    tok = jwt.encode({"iss": os.environ["ASC_ISSUER_ID"], "iat": now, "exp": now + 1000, "aud": "appstoreconnect-v1"},
                     pem(), algorithm="ES256", headers={"kid": os.environ["ASC_KEY_ID"]})
    s = requests.Session()
    s.headers["Authorization"] = "Bearer " + tok
    return s


def show(r):
    print(r.status_code, r.text[:800])
    return r.ok


def main(mode):
    if mode not in ("register", "ping", "list", "debug"):
        print("mode must be register, ping, list or debug"); return 1
    s = session()
    app = s.get(f"{ASC}/v1/apps", params={"filter[bundleId]": BUNDLE_ID}).json()["data"][0]["id"]
    hooks = s.get(f"{ASC}/v1/apps/{app}/webhooks")
    ours = [h for h in (hooks.json().get("data", []) if hooks.ok else []) if h["attributes"].get("name") == NAME]
    if mode == "debug":
        # What Apple delivered, and the header names the relay saw on a rejected delivery (names only, never values).
        for h in ours:
            r = s.get(f"{ASC}/v1/webhooks/{h['id']}/deliveries", params={"limit": 5})
            print("deliveries:", r.status_code, r.text[:1500])
        admin = hashlib.sha256(("relay-admin:" + os.environ["CLOUDFLARE_API_TOKEN"]).encode()).hexdigest()
        print("::add-mask::" + admin)
        d = requests.get(URL.rsplit("/v1/", 1)[0] + "/admin/webhook-debug", headers={"Authorization": "Bearer " + admin})
        print("relay probe:", d.status_code, d.text[:800])
        return 0
    if mode == "list":
        print("webhooks:", [(h["id"], h["attributes"].get("enabled"), h["attributes"].get("url")) for h in ours]); return 0
    secret = hashlib.sha256(("asc-webhook:" + os.environ["CLOUDFLARE_API_TOKEN"]).encode()).hexdigest()
    print("::add-mask::" + secret)  # the repo is public and logs are readable; Apple's replies are printed below
    if mode == "register" and not ours:
        body = {"data": {"type": "webhooks", "attributes": {"enabled": True, "eventTypes": EVENTS, "name": NAME, "secret": secret, "url": URL},
                         "relationships": {"app": {"data": {"type": "apps", "id": app}}}}}
        if not show(s.post(f"{ASC}/v1/webhooks", json=body)): return 1
        ours = [h for h in s.get(f"{ASC}/v1/apps/{app}/webhooks").json()["data"] if h["attributes"].get("name") == NAME]
    if not ours:
        print("no webhook registered; run register first"); return 1
    hid = ours[0]["id"]
    print("webhook id", hid)
    if mode in ("register", "ping"):
        return 0 if show(s.post(f"{ASC}/v1/webhookPings", json={"data": {"type": "webhookPings", "relationships": {"webhook": {"data": {"type": "webhooks", "id": hid}}}}})) else 1
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1] if len(sys.argv) > 1 else "list"))
