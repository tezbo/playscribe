#!/usr/bin/env python3
"""Revoke the one Development certificate this CI job created (cap kept since Terry's approval, 2026-11-06).

Automatic signing on a fresh CI runner creates a new "Apple Development: Created via API" certificate on every build
(the key dies with the runner), and the account stops at about a dozen. Run after the build, this revokes that job's
own certificate only. Apple gives no creation date, but a certificate expires one year after it is made, so the job's
start (CERT_SINCE, epoch seconds) finds it. A Mac's or a person's certificate, even one also "Created via API", and
every Distribution certificate are never touched. Until 22 Nov this revoked the oldest CI-looking certificates, which
revoked one made 3 minutes before the 18 Nov release build started (likely a Mac's) and probably sent Terry Apple's "has revoked your certificate" email.
If no certificate or more than one matches the window, it revokes nothing. Prints ids and dates only. Needs
CERT_SINCE, ASC_KEY_ID, ASC_ISSUER_ID and ASC_KEY_P8 or ASC_KEY_P8_BASE64, plus pyjwt, cryptography and requests.
"""
import base64, os, re, sys, time
from datetime import datetime
import jwt, requests

SLACK = 300  # seconds either side of the job window
API = "https://api.appstoreconnect.apple.com/v1/certificates"


def pem():
    raw = os.environ.get("ASC_KEY_P8") or base64.b64decode(os.environ["ASC_KEY_P8_BASE64"]).decode()
    body = re.sub(r"\\n|[^A-Za-z0-9+/=]", "", re.sub(r"-----[A-Z ]+-----", "", raw))
    i = body.find("MIG")
    if i >= 0:
        n = base64.b64decode(body[i:i + 4])[2] + 3
        body = body[i:i + (n + 2) // 3 * 4]
    lines = "\n".join(body[k:k + 64] for k in range(0, len(body), 64))
    return "-----BEGIN PRIVATE KEY-----\n" + lines + "\n-----END PRIVATE KEY-----\n"


def main():
    now = int(time.time())
    tok = jwt.encode({"iss": os.environ["ASC_ISSUER_ID"], "iat": now, "exp": now + 600, "aud": "appstoreconnect-v1"},
                     pem(), algorithm="ES256", headers={"kid": os.environ["ASC_KEY_ID"]})
    h = {"Authorization": "Bearer " + tok}
    r = requests.get(API + "?limit=200", headers=h)
    r.raise_for_status()
    since, now = int(os.environ["CERT_SINCE"]), int(time.time())
    year = 365 * 86400

    def made(c):  # creation time: expiry minus one year (366 days in a leap span, covered by the slack below)
        return datetime.fromisoformat(c["attributes"]["expirationDate"].replace("Z", "+00:00")).timestamp() - year

    mine = [c for c in r.json()["data"]
            if c["attributes"].get("certificateType") == "DEVELOPMENT"
            and c["attributes"].get("displayName") == "Created via API"
            and c["attributes"].get("expirationDate")
            and since - SLACK <= made(c) <= now + 86400 + SLACK]
    print(f"{len(mine)} Development certificate(s) made during this job")
    if len(mine) != 1:
        print("not exactly one: revoking nothing")
        return 0
    c = mine[0]
    d = requests.delete(f"{API}/{c['id']}", headers=h)
    print("revoke", c["id"], c["attributes"].get("expirationDate"), d.status_code)
    d.raise_for_status()
    return 0


if __name__ == "__main__":
    sys.exit(main())
