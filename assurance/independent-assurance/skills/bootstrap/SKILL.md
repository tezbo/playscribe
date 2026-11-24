---
name: bootstrap
description: >
  Set up or repair the Office of Independent Assurance environment: records tree, mandate, agent registry,
  first evidence snapshot and acceptance checks. Use for "/independent-assurance:bootstrap", "set up the
  assurance office", "initialise assurance records".
argument-hint: "[--repair]"
disable-model-invocation: true
metadata:
  version: "0.2.0"
---

# /independent-assurance:bootstrap

Load `assurance-charter` first.

| Contract | |
|---|---|
| Inputs | Optional `--repair` (re-create missing folders only). Needs: the OIA project's files mount, read access to the product repo, the sponsor's brief |
| Outputs | `oia/` tree; `00-mandate/sponsor-brief-*.md`, `directives-register.json`; `01-agent-registry/roster-<date>.json`; first snapshots; `setup/bootstrap-<date>.md` with each step's status |
| Permissions | Write only under `oia/`. Read-only on repo, transcripts, triggers, board. No messages to team agents |
| Evidence | Every registry and mandate file snapshotted with provenance; ledger entries for each |
| Done when | `oia.py health` prints HEALTHY; each setup step carries one of the five setup statuses; limitations recorded |

Steps
1. `python3 <charter>/scripts/oia.py init`.
2. Save the sponsor's mandate verbatim to `00-mandate/` (redact secrets) and snapshot it.
3. Build the directives register (`directive-compliance` step 1) and snapshot it.
4. Build the roster: map commit `Claude-Session` trailers to sessions, `get_session` each for title, state, model,
   creation date; add threads named in AGENTS.md; mark agents present in one source but not the other. Snapshot.
5. Snapshot the role definitions: `AGENTS.md`, `SKILLS.md`, `.claude/skills/*/SKILL.md` at the pinned SHA.
6. Write the plugin manifest: `oia.py plugin-manifest --plugin <plugin root> --ref <plugin commit SHA>`.
7. Run `/independent-assurance:health --boundaries` and record the result.
8. Write `setup/bootstrap-<date>.md`. Do not start the baseline: the sponsor starts it.
