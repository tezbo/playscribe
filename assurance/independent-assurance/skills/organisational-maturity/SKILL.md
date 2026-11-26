---
name: organisational-maturity
description: >
  This skill should be used to assess organisational maturity and performance: "maturity assessment", "how
  mature is the team", "monthly review", "critical gates", "sponsor dependence", "organisational performance".
metadata:
  version: "0.2.0"
---

# Organisational maturity and performance

Load `assurance-charter` first; scale, confidence, gates and measures are in `references/rating-scales.md`.

1. **Critical gates first.** Rate each of the 11 gates PASS/FAIL/BLOCKED/UNSUPPORTED/NOT TESTED with evidence. List
   failed gates above everything else.
2. **Dimensions.** Score each 0 to 5 with confidence and at least three cited items: the evidence that places it
   there and the gap to the next level. Apply caps from failed gates and open critical findings. No overall score.
3. **Measures.** Report the balanced measures that have data (effectiveness, efficacy, efficiency, learning,
   Playscribe-specific), each labelled measured, estimate, proxy or unavailable. Compare like with like.
4. **Trend.** Against the previous assessment, per dimension; a rise needs new evidence.
5. **Sponsor-intervention index** for the period.
6. **Learning.** New skills and lessons, and whether behaviour changed (a later unprompted use). A skill nobody
   uses does not raise maturity.
7. **Conflict.** The `independent-second-marker` agent re-scores organisational learning and capability, which the
   office helped build. Report both.
Output: `60-maturity/MM-<YYYY-MM>.md`.
