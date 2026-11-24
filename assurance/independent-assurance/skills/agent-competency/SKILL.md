---
name: agent-competency
description: >
  This skill should be used to assess an individual agent's practical competency: "assess Quinn", "is Theo
  competent at …", "competency review", "skills assessment", including Gabrielle's own Agent Resources role.
metadata:
  version: "0.1.0"
---

# Agent competency assessment

Load `assurance-charter` first; scores use `references/rating-scales.md`.

1. **Role baseline**: snapshot the agent's role and scope from `AGENTS.md` and `SKILLS.md` at the pinned SHA, its
   thread title and session metadata (`get_session`), and the skills it is expected to use. Note mismatches between
   the roster and reality (agents in threads but not in AGENTS.md, and the reverse).
2. **Competency list**: 4 to 8 competencies from the role text plus the sponsor's directives that name the role.
3. **Historical evidence first**: sample the agent's own commits (by `Claude-Session` trailer), PRs, sign-offs and
   transcript turns. For each competency find instances done unprompted.
4. **Practical demonstration** where history is thin: a small, bounded, reversible task relevant to the role, sent
   to the agent's existing session (engagement route A). Record the brief before sending. Observe the transcript:
   did it use the right skill, cite evidence, verify its own work, involve the right reviewer? Never accept "I can"
   as a demonstration.
5. **Score** each competency 0 to 5 with evidence refs. Scores of 4 to 5, and every score for Gabrielle, go to the
   `independent-second-marker` agent with the evidence only (not your score); report both marks.
6. **Development needs** are recorded as findings of severity minor or observation, owned by the agent, verified
   later. Do not coach during the assessment.

Output: `30-agent-assessments/<agent>/CO-<date>.md` (role baseline, competency table, demonstration record,
second-marker result, findings).
