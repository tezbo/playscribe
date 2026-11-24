---
name: evidence-collection
description: >
  This skill should be used to gather and preserve historical evidence for an assurance engagement: "collect
  evidence", "snapshot the history", "preserve the record", "pull the transcripts / CI runs / commits for the
  period", or whenever another assurance skill needs source material.
metadata:
  version: "0.1.0"
---

# Historical evidence collection and preservation

Load `assurance-charter` first; follow `references/sources.md` and `references/evidence-standard.md` there.

1. **Scope**: write the question, period (UTC from/to), population and sample rule in the working paper before
   collecting anything.
2. **Pin the repo**: `git fetch --unshallow origin` (once) and `git fetch origin main`; record the `origin/main` SHA.
   All repo reads are at that SHA.
3. **Collect read-only**, into a scratch folder, one file per source and query:
   - `git log --since --until --format='%H|%aI|%an|%s%n%b'` (keep `Claude-Session` trailers: they map commits to
     agent sessions).
   - PRs in period with reviews and check verdicts (GitHub MCP read tools).
   - Workflow runs in period, with conclusions; job logs only for sampled runs.
   - Transcript events for each agent session in scope (`list_events`, kinds `user`,`assistant`,`result`, paged with
     `before_id`); large pages are saved to files by the tool: keep the file, do not paste it.
   - Scheduled tasks (`list_triggers`, `all_in_account: true`).
   - Board rows (`ArtifactData list`) for `cards`, `notes`, `activity`.
4. **Redact secrets** (API keys, tokens, private keys) and note pattern and count only.
5. **Freeze** each file: `python3 <charter>/scripts/oia.py snapshot --kind <git-log|prs|ci-runs|transcript|board|
   triggers|docs> --source <system> --ref <SHA/run/session/url> --file <path> --note "<query used>"`.
6. **Index**: add each snapshot id and ledger seq to the working paper's evidence index.

Rules: never send messages to agents while collecting (that changes behaviour); never trigger workflows; label
anything an agent hands over on request as assessment-generated ("provided by <agent> on <date>").
Completion: every source in scope is either snapshotted or listed as unreachable with the reason.
