---
name: baseline
description: >
  Run the initial integrated engagement (directives, autonomous testing, multidisciplinary competency, execution efficacy and resource efficiency together) to set the baseline before any improvement. Use for
  "/independent-assurance:baseline", "establish the baseline", "baseline assurance review".
argument-hint: "[period-start YYYY-MM-DD] [period-end YYYY-MM-DD]"
disable-model-invocation: true
metadata:
  version: "0.2.0"
---

# /independent-assurance:baseline

Load `assurance-charter` first. Run only after bootstrap is HEALTHY and the sponsor has seen the limitations.

| Contract | |
|---|---|
| Inputs | Period (default: from the earliest directive in the register to now). Registry and directives register |
| Outputs | `20-working-papers/BL-<date>/` (one paper per area), findings, `60-maturity/MM-baseline-<date>.md`, report `80-reports/BL-<date>-v1.md` |
| Permissions | Read-only collection; engagement with agents only for interviews or demonstrations listed in the plan; no fixes, no team-config changes |
| Evidence | Each area cites snapshots and ledger seqs; historical and assessment-generated kept apart |
| Done when | All areas rated or marked not assessable with reason; integrity PASS; traceability sample passed; second marker done for Agent Resources; report delivered to the sponsor; lock released |
| Budget | One session; stop collecting at 25 sampled items per area; tell the sponsor what was not covered |

Steps
1. `oia.py lock acquire --name baseline --ttl-min 480`.
2. Plan: write `20-working-papers/BL-<date>/plan.md` (areas, questions, samples, seeds, demonstrations).
3. `evidence` for the period.
4. One evidence collection feeds every area (no separate audits): `directive-compliance` (the sponsor's directives
   retrieved in full), `cloud-ios-testing-assurance`, `multidisciplinary-qa`, `leadership-accountability` (incl.
   minimum effective intervention), `capability-and-competency` (check what was already demonstrated before asking;
   demonstrations only for gaps, through the courier route), `resource-efficiency` (telemetry baseline, sampled
   execution efficacy, context overhead), Agent Resources with `independent-second-marker`, and
   `organisational-maturity` (critical gates first).
4a. At least one bounded behavioural challenge through ordinary team operations (`behavioural-challenge`), launched
   only with the sponsor's approval of that specific challenge.
5. `findings-and-actions` for each critical and major finding; propose CAs (`findings-and-actions`).
6. `evidence`, then `sponsor-reporting`.
7. Release the lock. Do not share findings with the team until the sponsor has the report.
