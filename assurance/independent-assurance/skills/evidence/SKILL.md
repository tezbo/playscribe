---
name: evidence
description: >
  This skill should be used to collect, preserve and verify evidence for any office engagement: "collect
  evidence", "snapshot the history", "verify the evidence", "trace this finding", "check the ledger", and before
  any report is issued.
metadata:
  version: "0.2.0"
---

# Evidence: collection, preservation, integrity and provenance

Load `assurance-charter` first; detail in its `references/sources.md` and `references/evidence-standard.md`.

## Collect (incremental, risk-based)
1. Write the question, period, evidence cut-off (UTC), population and sample rule before collecting.
2. Reuse valid snapshots: check `10-historical-evidence/` and the ledger for the same source and period first.
   Collect only the delta since the last snapshot of that source.
3. Pin the repo SHA (`git fetch origin main`; unshallow once). Read git, PRs, CI runs, transcripts
   (`list_events`, kinds user/assistant/result, paged), scheduled tasks, board rows, session usage metadata.
   Large tool outputs are saved to files by the tool: grep them, do not paste them.
4. Redact secrets (record pattern and count, never the value).
5. Freeze: `oia.py snapshot --kind <kind> --source <system> --ref <SHA/run/session/url> --file <f> --note <query>`.
6. Anything an agent hands over on request is assessment-generated (`oia.py record`), labelled "provided by".
Never message agents while collecting; never trigger workflows.

## Verify
- Records: `oia.py verify` must read INTEGRITY PASS; compare the ledger head with the hash quoted in the last
  sponsor report. Failure stops reporting and is a critical finding against the office.
- Provenance per item: commit exists on origin with the claimed author, date and `Claude-Session` trailer; CI run
  head SHA and job verdict as claimed (read the job, not a message); stills come from a named run or session at a
  named SHA and show the claimed display and pose; transcript event uuid exists in period; sign-offs name the merged
  SHA and the reviewer is not the implementer.
- Traceability sample: five random report sentences → finding → working paper → record/snapshot → original
  reference. Withdraw any sentence whose chain breaks.
- Use the `evidence-provenance-auditor` agent for every critical finding.
