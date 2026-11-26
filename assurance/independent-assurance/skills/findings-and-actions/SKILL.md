---
name: findings-and-actions
description: >
  This skill should be used to raise a finding, find its root cause, set a corrective action with an
  accountable owner and acceptance criteria, and later verify the fix and its sustainment: "root cause",
  "why does this keep happening", "track the fixes", "has this been fixed", "close the finding".
metadata:
  version: "0.2.0"
---

# Findings, root cause and corrective actions

Load `assurance-charter` first. Register: `70-findings/findings.jsonl`, written only by `oia.py finding`.

## Finding
Statement (what, where, when, expected, impact), original evidence refs, severity, critical gate affected (if any),
evidence confidence, facts versus judgement.

## Root cause (major and critical findings)
1. Timeline from system records, UTC, before any explanation.
2. Causal chain; each link cites evidence or is marked HYPOTHESIS.
3. Classify: missing rule; rule not known; known but not applied (no check); tooling gap; capability gap; role or
   ownership gap; conflicting directives; incentive or structure creating waste; platform limit.
4. Test on another instance. Corroborate with the `root-cause-analyst` agent.

## Corrective action
`CA-<finding id>`: accountable owner (the product leader whose remit it is, not the office), action, measurable
completion test, sustainment test (fresh sample 2 to 4 weeks later), due date, expected resource cost versus benefit.
The office may offer capability support but does not do the fix, and suspends remediation of anything under formal
assessment until the baseline is recorded.

## Verify
Re-perform the completion test from system records; the owner's word is not evidence. At the sustainment date,
re-test on a fresh sample; only then `oia.py finding close --id <id> --evidence <ledger seq>`. Statuses: Open,
In progress (owner's claim), Completed – awaiting sustainment, Verified closed, Overdue, Regressed. A regressed
critical becomes a new critical finding citing the old one. Record checks in `90-follow-up/`.
