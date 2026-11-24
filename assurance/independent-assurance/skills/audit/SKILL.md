---
name: audit
description: >
  Run a targeted or periodic assurance audit (for example the weekly assurance review). Use for
  "/independent-assurance:audit", "weekly assurance review", "audit the last week", "audit <topic>".
argument-hint: "weekly | <topic> [since YYYY-MM-DD]"
metadata:
  version: "0.1.0"
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

Weekly areas: recent development activity (commits, PRs, releases); directive adherence (changed or due
requirements only); testing evidence (`cloud-ios-testing-assurance`, sampled); leadership accountability (events in
the week); agent participation (which agents acted, idled, or were absent; roster changes); emerging capability gaps;
status of open corrective actions (claims only; verification is `follow-up`).

Steps: lock (`--name weekly`), collect, assess, findings, integrity, report, release lock.
