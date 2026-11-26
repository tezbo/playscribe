---
name: capability-and-competency
description: >
  This skill should be used for Agent Resources work: maintaining the capability register and agent
  inventory, assessing an agent's practical competency, handling skills requests and turning proven recurring
  procedures into skills: "assess Quinn", "is Iris able to run a pose shoot", "capability register", "skills
  request", "who can do X".
metadata:
  version: "0.2.0"
---

# Capability, competency and skills

Load `assurance-charter` first. Scale and confidence: `references/rating-scales.md`.

## Capability register (organisation level)
Keep `01-agent-registry/capability-register.json` (restricted copy) and contribute the shareable part to product
registers through their PR process (Playscribe: `docs/capability-register.md`); reference, do not duplicate. Per
capability: name, applicable agents, execution procedure (skill or doc), evidence, status
(PASS/FAIL/BLOCKED/UNSUPPORTED/NOT TESTED), limitations, owner, last verified date, evidence class (proven,
documented only, no evidence). Having a skill or doc is "documented", never "proven".

## Agent inventory
Per agent: role, reporting line, session and thread, model and effort, skills, tools and permissions, operational
dependencies (the sponsor's Mac, paid services), roster mismatches.

## Competency assessment
1. Check first whether the competency was already shown (history: commits by `Claude-Session` trailer, CI runs the
   agent dispatched, transcript turns, sign-offs). Do not repeat a demonstration already on record.
2. Rate each competency 0 to 5 with evidence confidence. Credit only unprompted, independent execution.
3. Where history is insufficient, commission a bounded, reversible demonstration through the office interface
   (`references/engagement.md`). Record the brief before sending. Observe the actual behaviour in the agent's
   transcript and artefacts; an explanation of how it would do it scores at most 1.
4. Scores of 4 to 5, and every judgement on Agent Resources (the office's own past work), go to the
   `independent-second-marker` agent; report both marks.

## Skills development
A procedure that recurs and has been proven becomes a version-controlled skill via the product repo's PR process,
with a `SKILLS.md` entry. Measure its context cost (description length) and later check it is used unprompted.
Recommend tooling upgrades (Limrun, sim-use, agent-device, Appium, XCUITest, Xcode, Cowork, Claude Code) only with a
cost and benefit estimate.
