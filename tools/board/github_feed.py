#!/usr/bin/env python3
"""Build the sprint board's GitHub activity feed from the public repo (no credentials).

Usage: python3 tools/board/github_feed.py [--hours 48] > feed.json
Writes {"rows": [...], "syncedAt": <epoch ms>}. Rows: {id, at, by, kind, text, url}.
Sources: pull requests (opened, merged, closed), repo events (pushes to main/release/rc branches, tags, releases, comments)
and workflow runs (TestFlight, Feed, Signing check, and CI results on main/release branches).
The board page (docs/board/sprint-board.html) fetches the same endpoints live; this script
is the backfill and the fallback when the page cannot reach GitHub.
"""
import json, os, re, sys, time, urllib.request
from datetime import datetime, timezone

REPO = "tezbo/playscribe"
HOURS = int(sys.argv[sys.argv.index("--hours") + 1]) if "--hours" in sys.argv else 48
BASE = f"https://api.github.com/repos/{REPO}"
KEEP_BRANCH = re.compile(r"^(main|release/.*|rc/.*)$")


def get(path):
    req = urllib.request.Request(BASE + path, headers={"Accept": "application/vnd.github+json", "User-Agent": "playscribe-board"})
    if os.environ.get("GITHUB_TOKEN"):
        req.add_header("Authorization", "Bearer " + os.environ["GITHUB_TOKEN"])
    with urllib.request.urlopen(req, timeout=30) as r:
        return json.load(r)


def ms(iso):
    return int(datetime.fromisoformat(iso.replace("Z", "+00:00")).timestamp() * 1000)


def who(body):
    return "Team"  # every agent pushes under one account, so the PR cannot say who did the work


def merge_kind(title):
    if re.search(r"still|screenshot|capture", title, re.I):
        return "stills"
    if re.search(r"^(docs|qa|research)\b|research|test plan|write-?up|report", title, re.I):
        return "writeup"
    return "merge"


cut = (time.time() - HOURS * 3600) * 1000
rows = {}


def add(key, at, by, kind, text, url=""):
    if at >= cut:
        rows[key] = {"id": key, "at": at, "by": by, "kind": kind, "text": text[:220], "url": url}


events = []
for page in (1, 2, 3):
    try:
        events += get(f"/events?per_page=100&page={page}")
    except Exception as e:
        print("events page", page, e, file=sys.stderr)
        break
for e in events:
    t, p, at = e["type"], e.get("payload", {}), ms(e["created_at"])
    if t == "PushEvent":
        br = p.get("ref", "").replace("refs/heads/", "")
        if KEEP_BRANCH.match(br) and p.get("commits"):
            n = p.get("size", len(p["commits"]))
            first = p["commits"][-1]["message"].splitlines()[0]
            add(f"push-{e['id']}", at, "Team", "push", f"{n} commit{'s' if n != 1 else ''} to {br}: {first}")
    elif t == "CreateEvent" and p.get("ref_type") == "tag":
        add(f"tag-{p['ref']}", at, "Theo", "release", f"Tag {p['ref']} created")
    elif t == "ReleaseEvent":
        rel = p["release"]
        add(f"rel-{rel['id']}", at, "Theo", "release", f"Release {rel.get('name') or rel['tag_name']} {p['action']}", rel["html_url"])
    elif t == "IssueCommentEvent":
        i = p["issue"]
        add(f"cmt-{e['id']}", at, "Team", "comment", f"Comment on #{i['number']}: {i['title']}", p["comment"]["html_url"])

pulls = []
for page in (1, 2):
    try:
        pulls += get(f"/pulls?state=all&sort=updated&direction=desc&per_page=100&page={page}")
    except Exception as e:
        print("pulls page", page, e, file=sys.stderr)
        break
for pr in pulls:
    n, by, url = pr["number"], who(pr.get("body")), pr["html_url"]
    add(f"pr-{n}-opened", ms(pr["created_at"]), by, "pr", f"PR #{n} opened: {pr['title']}", url)
    if pr.get("merged_at"):
        add(f"pr-{n}-merged", ms(pr["merged_at"]), by, merge_kind(pr["title"]), f"PR #{n} merged: {pr['title']}", url)
    elif pr.get("closed_at"):
        add(f"pr-{n}-closed", ms(pr["closed_at"]), by, "pr", f"PR #{n} closed: {pr['title']}", url)

runs = []
for page in (1, 2, 3):
    try:
        runs += get(f"/actions/runs?per_page=100&page={page}")["workflow_runs"]
    except Exception as e:
        print("runs page", page, e, file=sys.stderr)
        break
for r in runs:
    c, n, br = r.get("conclusion"), r["name"], r["head_branch"]
    if c not in ("success", "failure"):
        continue
    special = n in ("TestFlight", "TestFlight notes", "Feed", "Signing check")
    if not special and not KEEP_BRANCH.match(br or ""):
        continue
    verb = "passed" if c == "success" else "FAILED"
    kind = "release" if n == "TestFlight" and c == "success" else "ci"
    add(f"run-{r['id']}", ms(r["updated_at"]), "CI", kind, f"{n} {verb} on {br} ({r['head_sha'][:7]})", r["html_url"])

out = sorted(rows.values(), key=lambda x: -x["at"])
json.dump({"rows": out, "syncedAt": int(time.time() * 1000)}, sys.stdout)
print(f"{len(out)} rows", file=sys.stderr)
