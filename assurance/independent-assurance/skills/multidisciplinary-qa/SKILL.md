---
name: multidisciplinary-qa
description: >
  This skill should be used to assess multidisciplinary product quality assurance: "are design and CX in the
  loop", "was this signed off by the right people", "product QA review", "did a playtester use it", "UX sign-off
  audit".
metadata:
  version: "0.1.0"
---

# Multidisciplinary quality assurance assessment

Load `assurance-charter` first.

1. **Expected cycle**: snapshot the sponsor's refinement cycle and the repo's sign-off rules (`AGENTS.md`,
   `review-merge-handoff` skill, `docs/ux-acceptance.md`). List each discipline's required touchpoint: product
   (outcome and acceptance), design (layout in every pose, HIG), QA (acceptance IDs, evidence), CX/playtest (real
   use), marketing where user-facing text changes, engineering review.
2. **Sample** 10 to 25 merged user-facing PRs in the period (random, seed recorded, plus any the sponsor named).
3. **Trace each**: which disciplines touched it, at which SHA, using the running app or only the diff, with what
   evidence (stills, recordings, notes), and whether the implementer was the only verifier.
4. **Usage reality**: did design and CX use the running app (transcript events showing stills opened, routes run,
   device or cloud sessions), or only read code and descriptions?
5. **Escapes**: defects found by the sponsor or testers after a discipline signed off: map each to the missed
   touchpoint.

Rate per discipline: Integrated / Partial / Absent. Output: `20-working-papers/<engagement>/multidisciplinary.md`.
Corroborate design and CX judgements with the `product-quality-assessor` agent.
