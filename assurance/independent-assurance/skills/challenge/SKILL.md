---
name: challenge
description: >
  Design, launch (with sponsor approval) and assess an unannounced behavioural challenge. Use for
  "/independent-assurance:challenge", "run a behavioural challenge", "commission a test assignment".
argument-hint: "design | launch CH-<id> | assess CH-<id>"
disable-model-invocation: true
metadata:
  version: "0.1.0"
---

# /independent-assurance:challenge

Load `assurance-charter` and `behavioural-challenge`.

| Contract | |
|---|---|
| Inputs | `design` (writes and seals a plan), `launch <id>` (needs the sponsor's approving message id), `assess <id>` |
| Outputs | Sealed plan in `50-challenges/sealed/`; response evidence and assessment in `50-challenges/evidence/<id>/`; findings; report section |
| Permissions | `design` and `assess`: read-only. `launch`: one intake message on the sponsor's behalf, only with recorded approval |
| Evidence | Plan hash in the ledger before launch; observed behaviour from system records; count of reminders |
| Done when | Every observed principle rated with evidence; team told it was a challenge after the sponsor has the report |
| Limits | At most one live challenge; at most one launch a month; assignment under one day of team work, reversible, no spend, no release |

Scheduled runs only `design` and remind the sponsor to approve; they never `launch`.
