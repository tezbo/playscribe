---
name: directive-compliance
description: >
  This skill should be used when assessing whether the team follows the sponsor's strategic directives and
  standing rules, for "directive compliance", "are they doing what Terry asked", "check adherence to the
  directive", or as a step of the baseline, weekly or audit commands.
metadata:
  version: "0.1.0"
---

# Strategic directive compliance assessment

Load `assurance-charter` first.

1. **Build the register.** Read `00-mandate/directives-register.json` (create it from the sponsor's messages if
   missing). One row per directive: id, cmsg id, date, verbatim text, owner(s) named by the sponsor, and each
   testable requirement split out (`D2.3: routine QA must not depend on the sponsor's Mac`). Include standing rules
   from `AGENTS.md` with their dated attribution ("Terry, 2026-11-06"). Snapshot the register when it changes.
2. **Define the test for each requirement** before looking at evidence: what artefact would show compliance, what
   would show breach, and what period applies. Write it in the working paper.
3. **Collect evidence** with `evidence-collection`. Prefer system-of-record artefacts: CI runs, commits, transcript
   events, board rows. Treat status posts as assertions.
4. **Rate each requirement**: COMPLIANT (evidence level 1 to 2), PARTIAL (some instances, gaps cited), NON-COMPLIANT
   (counter-evidence cited), NOT YET DUE (deadline not reached), NOT ASSESSABLE (evidence unreachable: say which and
   why). Never infer compliance from absence of complaints.
5. **Look for the quiet failures**: requirements nobody mentions any more, rules restated by the sponsor (each
   restatement is evidence the rule did not stick), and owners named by the sponsor who did not act.
6. **Raise findings** for NON-COMPLIANT and material PARTIAL rows (`oia.py finding add`), severity per the charter
   (a breached sponsor directive is critical when it causes spend, user harm or false assurance; otherwise major).

Output: `20-working-papers/<engagement>/directive-compliance.md` with the register table (requirement, test,
evidence refs, rating, finding id) and a one-paragraph conclusion.
