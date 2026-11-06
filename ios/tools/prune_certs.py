#!/usr/bin/env python3
"""Keep the account under Apple's certificate cap (Terry approved, 2026-11-06).

Automatic signing on a fresh CI runner creates a new "Apple Development: Created via API" certificate on every
build (the key dies with the runner), and the account stops at about a dozen. This revokes the oldest of those
CI-created Development certificates, keeping the newest KEEP. Anything else (a person's certificate, any
Distribution certificate) is never touched. Prints ids and dates only. Needs ASC_KEY_ID, ASC_ISSUER_ID and
ASC_KEY_P8 or ASC_KEY_P8_BASE64, plus pyjwt, cryptography and requests.
"""
import base64, os, re, sys, time
import jwt, requests

KEEP = int(os.environ.get("KEEP_CI_CERTS", "5"))
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
    ci = [c for c in r.json()["data"]
          if c["attributes"].get("certificateType") == "DEVELOPMENT"
          and c["attributes"].get("displayName") == "Created via API"
          and c["attributes"].get("expirationDate")]  # no date: leave it alone
    ci.sort(key=lambda c: c["attributes"]["expirationDate"])  # oldest first
    extra = ci[:max(0, len(ci) - KEEP)]
    print(f"{len(ci)} CI-created development certificates; keeping {min(KEEP, len(ci))}, revoking {len(extra)}")
    for c in extra:
        d = requests.delete(f"{API}/{c['id']}", headers=h)
        print("revoke", c["id"], c["attributes"].get("expirationDate"), d.status_code)
        d.raise_for_status()


if __name__ == "__main__":
    sys.exit(main())
