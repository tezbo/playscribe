#!/usr/bin/env python3
"""PreToolUse guard for assurance records (sessions with this plugin enabled only).

Blocks Write/Edit to:
  - any existing file under an `oia/10-historical-evidence/` folder (snapshots are immutable)
  - the ledger and findings register (append only through oia.py)
  - any existing file under `oia/80-reports/` (issued reports are never rewritten; issue a new version)
Everything else passes. This is a guard inside assurance sessions, not an access control:
other sessions, shells and people with access to the same storage are not stopped by it.
"""
import json
import os
import sys

try:
    data = json.load(sys.stdin)
except Exception:
    sys.exit(0)
ti = data.get("tool_input") or {}
path = ti.get("file_path") or ti.get("notebook_path") or ""
p = path.replace("\\", "/")
if "/oia/" not in p:
    sys.exit(0)
reason = None
if "/oia/ledger/" in p or p.endswith("/oia/70-findings/findings.jsonl"):
    reason = "the ledger and findings register are append-only; use oia.py"
elif "/oia/10-historical-evidence/" in p and os.path.exists(path):
    reason = "historical evidence snapshots are immutable; take a new snapshot"
elif "/oia/80-reports/" in p and os.path.exists(path):
    reason = "issued reports are never rewritten; issue a new version with a new file name"
if reason:
    print(f"Blocked by independent-assurance records guard: {reason} ({path})", file=sys.stderr)
    sys.exit(2)
sys.exit(0)
