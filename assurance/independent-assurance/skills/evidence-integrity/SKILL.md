---
name: evidence-integrity
description: >
  This skill should be used to verify evidence integrity and provenance: "verify the evidence", "check the
  ledger", "is this evidence genuine", "trace this finding", before issuing any report, and when an agent's
  claim must be checked against the system of record.
metadata:
  version: "0.1.0"
---

# Evidence integrity and provenance verification

Load `assurance-charter` first.

## Records integrity
1. Run `python3 <charter>/scripts/oia.py verify`. Any `INTEGRITY FAIL` stops report issue: raise a critical
   finding against OIA itself, record what changed, and tell the sponsor.
2. Compare the ledger head hash with the one quoted in the last sponsor report (`80-reports/`). A mismatch in an
   earlier entry means the chain was rebuilt: critical.

## Provenance of team evidence
For each item relied on:
- **Commit**: `git cat-file -t <sha>` exists on `origin`; author, date and `Claude-Session` trailer match the claim.
- **CI run**: run id exists, head SHA equals the claimed SHA, conclusion and the named job are as claimed; a
  "PASS" in a job name is read from the job, not from a message.
- **Screenshot or still**: produced by a named run or session at a named SHA; dimensions and display match the
  claimed pose (for Duo stills, check the display size, not the filename).
- **Transcript claim**: the event uuid exists and its timestamp is in period.
- **Sign-off**: names the exact SHA; the reviewer is not the implementer; the SHA is the one merged.

## Traceability sample
Pick five sentences from the draft report at random; follow each to finding, working paper, record or snapshot,
original reference. Record the walk in the working paper. Any broken link: withdraw or fix the sentence.

Corroborate with the `evidence-provenance-auditor` agent for every critical finding.
