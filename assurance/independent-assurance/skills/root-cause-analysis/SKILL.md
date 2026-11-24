---
name: root-cause-analysis
description: >
  This skill should be used to find the root cause of an assurance finding or a repeated failure: "why did this
  happen", "root cause", "5 whys", "why does Terry keep having to remind them".
metadata:
  version: "0.1.0"
---

# Root cause analysis

Load `assurance-charter` first.

1. **Problem statement**: what happened, where, when, the expected behaviour, the impact, with evidence refs.
2. **Timeline** from system records (commits, runs, transcript events, messages), in UTC, before any explanation.
3. **Causal chain**: ask why at each step until you reach a cause the organisation controls (rule, skill, tooling,
   role clarity, incentive, capacity, information flow). Each link cites evidence or is marked as a hypothesis.
4. **Classify** the root cause: missing rule; rule exists but not known; known but not applied (no check);
   tooling gap; capability gap (agent cannot do it); role or ownership gap; conflicting directives; platform limit.
5. **Test the hypothesis** against other instances: does the same cause explain them? Does an instance exist where
   the cause was present and the failure did not happen (and why)?
6. **Corrective action proposal**: one or more actions that remove the cause, each with an owner by role, a
   measurable completion test and a sustainment test (`corrective-actions`). OIA proposes; the team owns the fix.

Corroborate with the `root-cause-analyst` agent for major and critical findings.
Output: a section in the finding's working paper.
