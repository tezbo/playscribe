---
name: follow-up
description: >
  Independently verify corrective actions and whether improvements are sustained. Use for
  "/independent-assurance:follow-up", "verify the corrective actions", "check if findings were fixed".
argument-hint: "[finding id …]"
metadata:
  version: "0.1.0"
---

# /independent-assurance:follow-up

Load `assurance-charter` and `corrective-actions`.

| Contract | |
|---|---|
| Inputs | Finding ids, or default: every open finding whose CA due date or sustainment date has passed |
| Outputs | `90-follow-up/FU-<date>/` records; `finding close` events for verified-sustained items; report section |
| Permissions | Read-only; may ask an owner for the location of evidence (engagement route A) |
| Evidence | Re-performed completion and sustainment tests from system records; owner statements are recorded but not relied on |
| Done when | Each finding in scope is Verified closed, Completed – awaiting sustainment, Overdue or Regressed, with evidence |
| Budget | If nothing is due, record "nothing due" in the ledger and stop without a report |

Lock name `follow-up`. Never close a finding on the owner's word.
