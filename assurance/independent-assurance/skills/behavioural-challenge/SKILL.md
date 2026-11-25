---
name: behavioural-challenge
description: >
  This skill should be used to design, run and assess an unannounced behavioural challenge: "set the team a
  test assignment", "see if they apply the rules unprompted", "behavioural challenge", "commission a bounded
  product task".
metadata:
  version: "0.1.0"
---

# Unannounced behavioural challenges

Load `assurance-charter` first. A challenge is a real, small, bounded, useful product assignment given through the
team's normal intake, with no mention of the principles being watched.

## Design (sealed before launch)
1. Pick the principles to observe (for example: card on the board before work, decision note, estimate with basis,
   precheck before PR, second-agent verification, five-pose evidence, no PC version shown as PS5, workaround-first,
   no sponsor escalation of solvable blockers).
2. Write the assignment: genuinely useful, completable in under a day, reversible, no spend, no release, no
   production change, nothing that would mislead users if shipped.
3. Write observable pass criteria per principle and the observation window.
4. Save as `50-challenges/sealed/CH-<date>-<n>.md` with `oia.py record --area challenge-sealed`; its hash in the
   ledger proves the criteria predate the response.
5. **Authorisation**: the sponsor approves each challenge's launch (it spends team capacity and uses his name on
   intake). Record the approving cmsg id. Without it, do not launch.

## Launch
Deliver the assignment the way the sponsor normally would (the sponsor posts it, or OIA sends it to the
intake agent with the sponsor's approval quoted). Do not reveal it is a challenge until assessment ends.

## Observe and assess
Collect the response from transcripts, board, PRs and CI (`evidence`). Rate each principle: Applied
unprompted / Applied after reminder / Not applied / Not applicable, with evidence. Count reminders from anyone.

## Isolated regression challenge (only with the sponsor's explicit authorisation)
To test whether quality controls catch a known defect: put the defect on an isolated, clearly named branch that no
release, TestFlight or deployment workflow builds from, run the existing checks there, record what they caught, and
delete nothing from main or release branches. Never introduce a defect into production, release branches or
anything that triggers a deployment.

## Close
Tell the team it was a challenge and share the results (after the report to the sponsor). Never leave a challenge
change half-merged: the normal owners decide whether to keep the work.
Output: `50-challenges/evidence/CH-<…>/assessment.md`, findings, and a section in the next sponsor report.
