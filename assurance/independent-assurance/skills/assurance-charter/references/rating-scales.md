# Rating scales

## Competency (per competency, per agent)

| Score | Label | Evidence needed |
|---|---|---|
| 0 | Not demonstrated | No observed instance, or the agent declined or failed the demonstration |
| 1 | Asserted | Agent or others say it can; no artefact |
| 2 | Assisted | Done with prompting, reminders or another agent doing key steps |
| 3 | Independent | Done unprompted and correctly at least once, with artefacts |
| 4 | Reliable | Independent on 3 or more sampled occasions, no material errors |
| 5 | Exemplary | Reliable and teaches or improves the practice for others (skill, learning, tool) |

A score of 3 or more needs historical evidence or an observed demonstration. Second marking by
`independent-second-marker` is required for any score of 4 or 5, and for any score on Gabrielle herself.

## Maturity (per dimension, team level)

Dimensions: Directive adherence; Testing and verification (incl. cloud-native Duo QA); Multidisciplinary quality
(design, CX, playtest in the loop); Leadership accountability (Coordinator, PO, leads); Organisational learning
(learnings, skills, decisions); Independent verification (implementer is not the only verifier); Sponsor
independence (reliance on Terry's intervention); Estimation and planning; Evidence and traceability; Cost discipline.

| Level | Description |
|---|---|
| 1 Initial | Ad hoc; depends on the sponsor noticing problems |
| 2 Repeatable | Practices exist in some threads; inconsistent; sponsor still corrects often |
| 3 Defined | Written rules and skills, followed in most sampled cases, evidence kept |
| 4 Managed | Measured; deviations caught by the team before the sponsor; independent verification routine |
| 5 Optimising | Team improves its own practice from evidence; sponsor intervention rare and strategic |

Cap rule: an open critical finding in a dimension caps it at 2; an open major finding caps it at 3. Never average a
capped dimension away: report the critical findings above the table and give no single overall score without the
lowest dimension next to it.

## Sponsor-intervention index

Count, over the period: sponsor messages that correct, re-direct, remind of an existing rule, or unblock work the
team could have unblocked. Divide by sponsor messages. Report the count, the ratio and three cited examples.
