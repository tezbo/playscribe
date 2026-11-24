---
name: health
description: >
  Check that the assurance environment works: records, integrity, locks, access to evidence sources,
  scheduled tasks and access boundaries. Use for "/independent-assurance:health", "is the assurance office
  healthy", "check the assurance setup".
argument-hint: "[--boundaries]"
metadata:
  version: "0.1.0"
---

# /independent-assurance:health

Load `assurance-charter` first.

| Contract | |
|---|---|
| Inputs | Optional `--boundaries` to re-run the access-boundary tests |
| Outputs | `setup/health-<UTC stamp>.json` and a one-line verdict |
| Permissions | Read-only, plus writing the health record |
| Evidence | Command outputs captured verbatim |
| Done when | Every check is PASS, FAIL, BLOCKED or UNSUPPORTED with output; FAILs reported to the sponsor |

Checks
1. `oia.py health` (tree, ledger chain, manifests, live locks, open criticals).
2. Product repo reachable: `git ls-remote origin main` prints a SHA.
3. Transcript access: `get_session` on two registry sessions returns titles.
4. Scheduled tasks: `list_triggers` shows the OIA tasks with their enabled state and last run.
5. Plugin intact: hash of this plugin's files equals `setup/plugin-manifest.json` (if present); report drift.
6. `--boundaries`: the records guard blocks an edit to the ledger; a team-project path (`/mnt/attach/project-files`)
   is not mounted here; note results without changing anything else.
Silent when HEALTHY on a scheduled run except for the ledger entry; report only failures.
