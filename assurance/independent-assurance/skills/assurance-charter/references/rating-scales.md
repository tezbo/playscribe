# Scales, gates and measures (founding charter §18 to §19)

## One maturity scale (capabilities, competencies, dimensions)

| Level | Name | Meaning |
|---|---|---|
| 0 | Absent | No meaningful implementation |
| 1 | Acknowledged | Requirement understood or documented |
| 2 | Implemented | Capability exists but is not sufficiently demonstrated |
| 3 | Demonstrated | Successfully exercised, with verifiable evidence |
| 4 | Operational | Routinely and independently exercised |
| 5 | Embedded | Sustained, measured, independently verified and continuously improved |

Record **evidence confidence** separately: high, moderate, low, insufficient. Unavailable evidence is "insufficient"
confidence, not proof of non-compliance. Expected level for critical operational capabilities: 4, subject to verified
platform limits.

Competency uses the same scale per agent and competency. Credit only unprompted, independent execution (3 and above
need historical or observed evidence; an explanation alone is at most 1).

## Dimensions (assessed separately, never averaged into one number)
Organisational capability; leadership; product governance; quality assurance; autonomy; resource stewardship;
execution efficacy; context management; organisational learning; sponsor dependence.

## Critical gates (PASS / FAIL / BLOCKED / UNSUPPORTED / NOT TESTED, listed above any scores)
1. Genuine native cloud execution. 2. Independence from routine sponsor Mac testing. 3. Meaningful supported Duo
coverage. 4. Evidence integrity. 5. Independent multidisciplinary verification. 6. Evidence-based product acceptance.
7. Preservation of successful delivery workflows. 8. Unprompted adherence to strategic direction. 9. Persistent
organisational capabilities. 10. Material avoidable resource consumption. 11. Unauthorised expenditure.
A failed gate caps the related dimension at 2 and is reported on its own line.

## Finding severity
critical (gate failed, sponsor directive breached with harm, false assurance, unauthorised spend, secret exposure),
major, moderate, minor, observation. Recognise genuine strengths too.

## Performance measures (balanced, no composite score, no arbitrary targets)
- Effectiveness: intended outcomes achieved; work aligned with customer value; prioritisation; sponsor acceptance and
  intervention; scope avoided.
- Efficacy: share of assignments meeting verified acceptance criteria; first-pass quality; defects found and fixed;
  reliability of outputs; effectiveness of independent verification.
- Efficiency: resources per verified outcome; tokens where measured; model allocation compliance; context and
  coordination overhead; duplicate investigations; preventable rework; retries; unnecessary invocations; cloud use.
- Learning: reuse of proven skills; competency by discipline; time to enable an agent; recurrence of known mistakes;
  knowledge persistence; corrective-action effect.
- Playscribe: share of testing done autonomously in the cloud; verified Duo configuration coverage; defects found
  internally before TestFlight versus first found by the sponsor (foundBy, foundIn); Mac dependence; simulator use.
Compare like with like and account for complexity and risk. Establish baselines before targets.

## Sponsor-intervention index
Sponsor messages that correct, redirect, remind of an existing rule, or unblock what the team could have unblocked,
divided by all sponsor messages in the period. Report count, ratio and three cited examples.
