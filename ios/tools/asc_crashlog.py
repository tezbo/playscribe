"""Fetch one TestFlight crash log and write it encrypted, for the engineer who asked (never printed, never in the repo).

Usage (workflow_dispatch of testflight-feedback.yml with crash_id and crash_pubkey): reads
GET /v1/betaFeedbackCrashSubmissions/{id}/crashLog, encrypts the log with a fresh Fernet key, wraps that key with
the requester's RSA public key (OAEP SHA-256) and writes crashlog.enc + crashlog.key for upload as an artifact.
Only the requester's private key opens it. Logs show sizes only.
"""
import base64
import os
import sys

import requests
from cryptography.fernet import Fernet
from cryptography.hazmat.primitives import hashes, serialization
from cryptography.hazmat.primitives.asymmetric import padding

sys.path.insert(0, os.path.dirname(__file__))
from asc_feedback import ASC, asc_session  # noqa: E402


def main():
    cid, pub = os.environ.get("CRASH_ID", "").strip(), os.environ.get("CRASH_PUBKEY", "").strip()
    if not cid or not pub:
        print("::warning::CRASH_ID and CRASH_PUBKEY are required")
        return 1
    s = asc_session()
    r = s.get(f"{ASC}/v1/betaFeedbackCrashSubmissions/{cid}/crashLog", timeout=60)
    print(f"crashLog status {r.status_code}")
    if r.status_code != 200:
        return 1
    attrs = (r.json().get("data") or {}).get("attributes") or {}
    text = attrs.get("logText") or ""
    if not text and attrs.get("url"):
        text = requests.get(attrs["url"], timeout=60).text
    print(f"crash log {len(text)} chars")
    key = Fernet.generate_key()
    open("crashlog.enc", "wb").write(Fernet(key).encrypt(text.encode()))
    rsa = serialization.load_pem_public_key(pub.encode())
    wrapped = rsa.encrypt(key, padding.OAEP(mgf=padding.MGF1(hashes.SHA256()), algorithm=hashes.SHA256(), label=None))
    open("crashlog.key", "wb").write(base64.b64encode(wrapped))
    return 0


if __name__ == "__main__":
    sys.exit(main())
