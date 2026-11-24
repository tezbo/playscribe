#!/usr/bin/env python3
"""Office of Independent Assurance records tool.

Standard library only. Every write goes through this tool so that records carry
timestamps, source references, SHA-256 hashes and a hash-chained ledger entry.

Records root resolution (first match wins):
  1. --root argument
  2. OIA_ROOT environment variable
  3. /mnt/project-files/oia  (Claude project files, cloud)
  4. /mnt/attach/project-files/oia

Subcommands
  init                         create the records tree (idempotent)
  snapshot  --kind K --source S --ref R [--file F ...] [--note N]
                               freeze historical evidence into 10-historical-evidence/
  record    --area A --id ID --file F [--source S] [--ref R]
                               register an assessment-generated artefact (copied, hashed)
  ledger    --event E --detail D [--ref R]
                               append a ledger event
  verify                       re-hash every manifest and walk the ledger chain
  lock      acquire|release|status --name N [--ttl-min M] [--owner O]
  finding   add --id F-... --severity S --title T --evidence E [--criterion C]
            close --id F-... --evidence E       (closure needs verification evidence)
  health                       structure, chain, locks and open findings summary

Exit code 0 = OK, 1 = integrity failure or refused action, 2 = usage error.
"""
import argparse
import datetime as dt
import hashlib
import json
import os
import shutil
import sys

TREE = [
    "00-mandate",
    "01-agent-registry",
    "10-historical-evidence",
    "20-working-papers",
    "30-agent-assessments",
    "40-demonstrations",
    "50-challenges/sealed",
    "50-challenges/evidence",
    "60-maturity",
    "70-findings",
    "80-reports",
    "90-follow-up",
    "ledger",
    "ops/locks",
    "setup",
]
GENESIS = "0" * 64


def now():
    return dt.datetime.now(dt.timezone.utc).replace(microsecond=0).isoformat().replace("+00:00", "Z")


def resolve_root(arg):
    if arg:
        return os.path.abspath(arg)
    if os.environ.get("OIA_ROOT"):
        return os.path.abspath(os.environ["OIA_ROOT"])
    for cand in ("/mnt/project-files", "/mnt/attach/project-files"):
        if os.path.isdir(cand):
            return os.path.join(cand, "oia")
    sys.exit("OIA root not found: pass --root or set OIA_ROOT")


def sha256_file(path):
    h = hashlib.sha256()
    with open(path, "rb") as f:
        for chunk in iter(lambda: f.read(1 << 16), b""):
            h.update(chunk)
    return h.hexdigest()


def ledger_path(root):
    return os.path.join(root, "ledger", "evidence-ledger.jsonl")


def ledger_entries(root):
    p = ledger_path(root)
    if not os.path.exists(p):
        return []
    with open(p) as f:
        return [json.loads(line) for line in f if line.strip()]


def entry_hash(entry):
    body = {k: v for k, v in entry.items() if k != "hash"}
    return hashlib.sha256(json.dumps(body, sort_keys=True, separators=(",", ":")).encode()).hexdigest()


def append_ledger(root, event, detail, ref=None, extra=None):
    entries = ledger_entries(root)
    prev = entries[-1]["hash"] if entries else GENESIS
    entry = {
        "seq": len(entries) + 1,
        "at": now(),
        "event": event,
        "detail": detail,
        "ref": ref,
        "actor": os.environ.get("OIA_ACTOR", "gabrielle-assurance"),
        "session": os.environ.get("CLAUDE_CODE_REMOTE_SESSION_ID") or os.environ.get("OIA_SESSION"),
        "prev": prev,
    }
    if extra:
        entry["extra"] = extra
    entry["hash"] = entry_hash(entry)
    with open(ledger_path(root), "a") as f:
        f.write(json.dumps(entry, sort_keys=True) + "\n")
        f.flush()
        os.fsync(f.fileno())
    return entry


def write_manifest(folder, files, meta):
    manifest = {"created": now(), **meta, "files": {}}
    for rel in files:
        manifest["files"][rel] = sha256_file(os.path.join(folder, rel))
    mpath = os.path.join(folder, "MANIFEST.json")
    with open(mpath, "w") as f:
        json.dump(manifest, f, indent=2, sort_keys=True)
    return sha256_file(mpath)


def cmd_init(root, a):
    created = []
    for d in TREE:
        p = os.path.join(root, d)
        if not os.path.isdir(p):
            os.makedirs(p, exist_ok=True)
            created.append(d)
    if not os.path.exists(ledger_path(root)):
        append_ledger(root, "init", "records tree created", extra={"tree": TREE})
    print(json.dumps({"root": root, "created": created}, indent=2))


def safe_id(s):
    return "".join(c if c.isalnum() or c in "-_." else "-" for c in s)[:80]


def cmd_snapshot(root, a):
    stamp = dt.datetime.now(dt.timezone.utc).strftime("%Y%m%dT%H%M%SZ")
    sid = f"{stamp}-{safe_id(a.kind)}"
    folder = os.path.join(root, "10-historical-evidence", sid)
    if os.path.exists(folder):
        sys.exit(f"refused: {folder} exists (historical snapshots are immutable)")
    os.makedirs(folder)
    names = []
    for f in a.file or []:
        dest = os.path.basename(f)
        shutil.copy2(f, os.path.join(folder, dest))
        names.append(dest)
    prov = {
        "class": "historical",
        "kind": a.kind,
        "source": a.source,
        "source_ref": a.ref,
        "captured_at": now(),
        "note": a.note,
        "capture_method": a.method,
    }
    with open(os.path.join(folder, "provenance.json"), "w") as f:
        json.dump(prov, f, indent=2, sort_keys=True)
    names.append("provenance.json")
    mhash = write_manifest(folder, names, {"snapshot": sid, "class": "historical"})
    for n in names:
        os.chmod(os.path.join(folder, n), 0o444)
    e = append_ledger(root, "snapshot", f"{a.kind}: {a.source}", ref=a.ref,
                      extra={"path": os.path.relpath(folder, root), "manifest_sha256": mhash})
    print(json.dumps({"snapshot": sid, "path": folder, "manifest_sha256": mhash, "ledger_seq": e["seq"]}, indent=2))


AREAS = {
    "working-paper": "20-working-papers",
    "assessment": "30-agent-assessments",
    "demonstration": "40-demonstrations",
    "challenge-sealed": "50-challenges/sealed",
    "challenge-evidence": "50-challenges/evidence",
    "maturity": "60-maturity",
    "report": "80-reports",
    "follow-up": "90-follow-up",
    "registry": "01-agent-registry",
    "mandate": "00-mandate",
    "setup": "setup",
}


def cmd_record(root, a):
    if a.area not in AREAS:
        sys.exit(f"unknown area {a.area}; one of {sorted(AREAS)}")
    folder = os.path.join(root, AREAS[a.area], safe_id(a.id))
    os.makedirs(folder, exist_ok=True)
    dest = os.path.join(folder, os.path.basename(a.file))
    if os.path.abspath(a.file) != os.path.abspath(dest):
        if os.path.exists(dest):
            sys.exit(f"refused: {dest} exists; record a new version with a new file name")
        shutil.copy2(a.file, dest)
    digest = sha256_file(dest)
    e = append_ledger(root, "record", f"{a.area}/{a.id}/{os.path.basename(dest)}", ref=a.ref,
                      extra={"class": "assessment-generated", "sha256": digest, "source": a.source,
                             "path": os.path.relpath(dest, root)})
    print(json.dumps({"path": dest, "sha256": digest, "ledger_seq": e["seq"]}, indent=2))


def cmd_ledger(root, a):
    e = append_ledger(root, a.event, a.detail, ref=a.ref)
    print(json.dumps(e, indent=2))


def cmd_verify(root, a, quiet=False):
    problems = []
    prev = GENESIS
    entries = ledger_entries(root)
    for e in entries:
        if e.get("prev") != prev:
            problems.append(f"ledger seq {e.get('seq')}: prev hash breaks the chain")
        if entry_hash(e) != e.get("hash"):
            problems.append(f"ledger seq {e.get('seq')}: entry hash mismatch (edited)")
        prev = e.get("hash")
        x = e.get("extra") or {}
        if e["event"] == "record" and x.get("path"):
            p = os.path.join(root, x["path"])
            if not os.path.exists(p):
                problems.append(f"record missing: {x['path']}")
            elif sha256_file(p) != x.get("sha256"):
                problems.append(f"record changed since ledger seq {e['seq']}: {x['path']}")
    hist = os.path.join(root, "10-historical-evidence")
    snaps = sorted(os.listdir(hist)) if os.path.isdir(hist) else []
    for s in snaps:
        m = os.path.join(hist, s, "MANIFEST.json")
        if not os.path.exists(m):
            problems.append(f"snapshot {s}: no MANIFEST.json")
            continue
        man = json.load(open(m))
        for rel, digest in man["files"].items():
            p = os.path.join(hist, s, rel)
            if not os.path.exists(p):
                problems.append(f"snapshot {s}: missing {rel}")
            elif sha256_file(p) != digest:
                problems.append(f"snapshot {s}: {rel} changed")
        logged = [e for e in entries if e["event"] == "snapshot" and (e.get("extra") or {}).get("path", "").endswith(s)]
        if not logged:
            problems.append(f"snapshot {s}: not in ledger")
        elif logged[-1]["extra"].get("manifest_sha256") != sha256_file(m):
            problems.append(f"snapshot {s}: MANIFEST.json changed after ledger entry")
    out = {"ledger_entries": len(entries), "snapshots": len(snaps), "problems": problems,
           "verdict": "INTEGRITY PASS" if not problems else "INTEGRITY FAIL"}
    if not quiet:
        print(json.dumps(out, indent=2))
    return out


def cmd_lock(root, a):
    p = os.path.join(root, "ops", "locks", safe_id(a.name) + ".json")
    if a.action == "status":
        print(open(p).read() if os.path.exists(p) else "free")
        return
    if a.action == "release":
        if os.path.exists(p):
            os.remove(p)
            append_ledger(root, "lock-release", a.name)
        print("released")
        return
    # acquire: any live lock in ops/locks blocks (one assessment at a time)
    ldir = os.path.dirname(p)
    t = dt.datetime.now(dt.timezone.utc)
    for f in os.listdir(ldir):
        lp = os.path.join(ldir, f)
        try:
            lk = json.load(open(lp))
        except Exception:
            continue
        exp = dt.datetime.fromisoformat(lk["expires"].replace("Z", "+00:00"))
        if exp > t:
            print(json.dumps({"refused": "another assessment holds a live lock", "lock": lk}, indent=2))
            sys.exit(1)
        os.remove(lp)
        append_ledger(root, "lock-expired", lk.get("name", f))
    lk = {"name": a.name, "owner": a.owner, "acquired": now(),
          "expires": (t + dt.timedelta(minutes=a.ttl_min)).replace(microsecond=0).isoformat().replace("+00:00", "Z")}
    fd = os.open(p, os.O_WRONLY | os.O_CREAT | os.O_EXCL)
    with os.fdopen(fd, "w") as f:
        json.dump(lk, f)
    append_ledger(root, "lock-acquire", a.name, extra=lk)
    print(json.dumps(lk, indent=2))


def findings_path(root):
    return os.path.join(root, "70-findings", "findings.jsonl")


def load_findings(root):
    p = findings_path(root)
    state = {}
    if os.path.exists(p):
        for line in open(p):
            if line.strip():
                ev = json.loads(line)
                state.setdefault(ev["id"], {}).update(ev)
    return state


def cmd_finding(root, a):
    p = findings_path(root)
    if a.action == "add":
        if a.id in load_findings(root):
            sys.exit(f"refused: {a.id} exists")
        if not a.evidence:
            sys.exit("refused: a finding needs --evidence (ledger seq, snapshot id or commit SHA)")
        ev = {"id": a.id, "status": "open", "severity": a.severity, "title": a.title,
              "criterion": a.criterion, "evidence": a.evidence, "raised": now()}
    else:
        f = load_findings(root).get(a.id)
        if not f:
            sys.exit(f"unknown finding {a.id}")
        if not a.evidence:
            sys.exit("refused: closure needs independent verification evidence")
        ev = {"id": a.id, "status": "verified-closed", "closure_evidence": a.evidence, "closed": now()}
    with open(p, "a") as fh:
        fh.write(json.dumps(ev, sort_keys=True) + "\n")
    append_ledger(root, f"finding-{a.action}", a.id, ref=a.evidence)
    print(json.dumps(ev, indent=2))


def cmd_health(root, a):
    missing = [d for d in TREE if not os.path.isdir(os.path.join(root, d))]
    v = cmd_verify(root, a, quiet=True)
    locks = os.listdir(os.path.join(root, "ops", "locks")) if os.path.isdir(os.path.join(root, "ops", "locks")) else []
    fs = load_findings(root)
    open_f = {k: f for k, f in fs.items() if f.get("status") == "open"}
    crit = [k for k, f in open_f.items() if f.get("severity") == "critical"]
    out = {"root": root, "missing_dirs": missing, "integrity": v["verdict"], "problems": v["problems"],
           "ledger_entries": v["ledger_entries"], "snapshots": v["snapshots"], "live_locks": locks,
           "open_findings": len(open_f), "open_critical": crit,
           "verdict": "HEALTHY" if not missing and not v["problems"] else "UNHEALTHY"}
    print(json.dumps(out, indent=2))
    if out["verdict"] != "HEALTHY":
        sys.exit(1)


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--root")
    sp = ap.add_subparsers(dest="cmd", required=True)
    sp.add_parser("init")
    s = sp.add_parser("snapshot")
    s.add_argument("--kind", required=True)
    s.add_argument("--source", required=True)
    s.add_argument("--ref", required=True, help="commit SHA, run id, session id, cmsg id, URL")
    s.add_argument("--file", action="append")
    s.add_argument("--note")
    s.add_argument("--method", default="copied by oia.py")
    r = sp.add_parser("record")
    r.add_argument("--area", required=True)
    r.add_argument("--id", required=True)
    r.add_argument("--file", required=True)
    r.add_argument("--source")
    r.add_argument("--ref")
    l = sp.add_parser("ledger")
    l.add_argument("--event", required=True)
    l.add_argument("--detail", required=True)
    l.add_argument("--ref")
    sp.add_parser("verify")
    k = sp.add_parser("lock")
    k.add_argument("action", choices=["acquire", "release", "status"])
    k.add_argument("--name", required=True)
    k.add_argument("--ttl-min", type=int, default=120)
    k.add_argument("--owner", default="gabrielle-assurance")
    f = sp.add_parser("finding")
    f.add_argument("action", choices=["add", "close"])
    f.add_argument("--id", required=True)
    f.add_argument("--severity", choices=["critical", "major", "moderate", "minor", "observation"])
    f.add_argument("--title")
    f.add_argument("--criterion")
    f.add_argument("--evidence")
    sp.add_parser("health")
    a = ap.parse_args()
    root = resolve_root(a.root)
    if a.cmd != "init" and not os.path.isdir(os.path.join(root, "ledger")):
        sys.exit(f"records not initialised at {root}; run init")
    {"init": cmd_init, "snapshot": cmd_snapshot, "record": cmd_record, "ledger": cmd_ledger,
     "verify": cmd_verify, "lock": cmd_lock, "finding": cmd_finding, "health": cmd_health}[a.cmd](root, a)
    if a.cmd == "verify":
        if cmd_verify(root, a, quiet=True)["problems"]:
            sys.exit(1)


if __name__ == "__main__":
    main()
