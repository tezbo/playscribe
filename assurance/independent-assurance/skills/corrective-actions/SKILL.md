---
name: corrective-actions
description: >
  This skill should be used to record, track and independently verify corrective actions: "track the fixes",
  "follow up findings", "has this been fixed", "is the improvement sustained", "close the finding".
metadata:
  version: "0.1.0"
---

# Corrective action tracking and verification

Load `assurance-charter` first. The findings register is `70-findings/findings.jsonl`, written only by
`oia.py finding`.

1. **Record**: every finding gets a corrective action entry in its working paper: `CA-<finding id>`, owner (role
   and agent), due date, completion test (what artefact proves the fix), sustainment test (what must still be true
   after 2 to 4 weeks, sampled fresh).
2. **Notify**: send the owner the finding and CA through the engagement route (after the sponsor has the report).
3. **Verify completion** independently: re-perform the completion test from system records. The owner's
   statement is not evidence. Record in `90-follow-up/FU-<date>/`.
4. **Verify sustainment** at the sustainment date on a fresh sample. Only then
   `oia.py finding close --id <id> --evidence <follow-up record ledger seq>`.
5. **Overdue or regressed**: report to the sponsor; a regressed critical is re-opened as a new critical finding
   referencing the old one.

Statuses in reports: Open, In progress (owner's claim), Completed – awaiting sustainment, Verified closed,
Overdue, Regressed.
