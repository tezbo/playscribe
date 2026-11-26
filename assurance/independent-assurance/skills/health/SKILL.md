---
name: health
description: >
  Check that the assurance environment works: records, integrity, locks, access to evidence sources,
  scheduled tasks and access boundaries. Use for "/independent-assurance:health", "is the assurance office
  healthy", "check the assurance setup".
argument-hint: "[--boundaries]"
disable-model-invocation: true
metadata:
  version: "0.2.0"
---

# /independent-assurance:health

Load `assurance-charter` first.

| Contract | |
|---|---|
| Inputs | Optional `--boundaries` to re-run the access-boundary tests |
| Outputs | `setup/health-<UTC stamp>/health-<UTC stamp>.json` (via `oia.py record --area setup --id health-<stamp>`) and a one-line verdict |
| Permissions | Read-only, plus writing the health record |
| Evidence | Command outputs captured verbatim |
| Done when | Every check is PASS, FAIL, BLOCKED or UNSUPPORTED with output; FAILs reported to the sponsor |

Checks
1. `oia.py health` (tree, ledger chain, manifests, live locks, open criticals).
2. Product repo reachable: `git ls-remote origin main` prints a SHA.
3. Transcript access: `get_session` on two registry sessions returns titles.
4. Scheduled tasks: `list_triggers` shows the OIA tasks with their enabled state and last run.
5. Plugin intact: `oia.py plugin-manifest --plugin <plugin root> --check` (PASS, DRIFT with changed files, or
   NOT TESTED if bootstrap never wrote the manifest).
6. `--boundaries`:
   a. Records guard: try one Write of a new file `<records root>/ledger/guard-probe.txt`; PASS only if the hook
      blocks it (the message names the independent-assurance records guard). Delete nothing.
   b. Team files not visible: the project files mount (`/mnt/project-files`, which may be a link to
      `/mnt/attach/project-files`) holds only `oia/` and OIA files; search it for team artefacts named in the
      registry (`team/`, `gamebook/`, `qa/` folders, `improvement-plans.md`). PASS if none are found.
   c. No write route into team sessions: record whether `send_message` to a registry session succeeds; the
      expected result in a separate project is a refusal (`not found`). A success means the boundary changed:
      report it.
Silent when HEALTHY on a scheduled run except for the ledger entry; report only failures.
