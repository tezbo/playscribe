---
name: audit
description: >
  Run the combined weekly organisational review, or a targeted audit (resource efficiency, execution efficacy, context, a directive, a release). Use for
  "/independent-assurance:audit", "weekly assurance review", "audit the last week", "audit <topic>".
argument-hint: "weekly | <topic> [since YYYY-MM-DD]"
disable-model-invocation: true
metadata:
  version: "0.2.0"
---

# /independent-assurance:audit

Load `assurance-charter` first.

| Contract | |
|---|---|
| Inputs | `weekly` (period = since last weekly audit's end, default 7 days) or a topic (a directive id, PR, release, agent, practice) |
| Outputs | `20-working-papers/WK-<yyyy-Www>/` or `AU-<date>-<topic>/`; new findings; report |
| Permissions | Read-only collection; no messages to agents unless a finding needs the owner's evidence (then engagement route A, logged) |
| Evidence | Snapshots for the period; every rating cites evidence |
| Done when | Each weekly area rated with evidence, findings recorded, integrity PASS, report delivered, lock released |
| Budget | Weekly: at most 15 sampled items per area; skip areas with no activity and say so |

Guard: if no baseline report exists in `80-reports/`, do not assess: run `health`, tell the sponsor the baseline is
pending, and stop.

Weekly = one combined, incremental organisational review (one run, one evidence pass, delta since the last run):
verified outcomes and development activity; directive adherence (changed or due requirements only); testing evidence
(sampled, `cloud-ios-testing-assurance`); leadership and orchestration events; agent participation and roster
changes; capability and competency changes; resource consumption and trends (`resource-efficiency`, measured where
available); corrective actions due (`follow-up` steps, `findings-and-actions`); the office's own overhead. The first
weekly run of each month goes deeper only where the evidence warrants it (anomalies, significant change, a failed
gate); otherwise it notes that no deep review was needed.

Steps: lock (`--name weekly`), collect, assess, findings, integrity, report, release lock.
