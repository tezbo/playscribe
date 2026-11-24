---
name: competency
description: >
  Assess one agent's practical competency, optionally with a live demonstration. Use for
  "/independent-assurance:competency <agent>", "assess <agent>'s competency".
argument-hint: "<agent name> [competency …] [--demo]"
metadata:
  version: "0.1.0"
---

# /independent-assurance:competency

Load `assurance-charter` and `agent-competency`.

| Contract | |
|---|---|
| Inputs | Agent name (must be in the registry); optional competencies; `--demo` to request a practical demonstration |
| Outputs | `30-agent-assessments/<agent>/CO-<date>.md`; demonstration record under `40-demonstrations/` if run; findings |
| Permissions | Read-only history; one engagement message to the agent's existing session for a demonstration, logged |
| Evidence | Historical instances per competency; the demonstration's brief (recorded before sending), the transcript events of the agent's response, and artefacts |
| Done when | Each competency scored 0 to 5 with evidence; second marker used where required; result to the sponsor (in the next report or directly if critical) |

If the agent is Gabrielle (Agent Resources), the `independent-second-marker` agent marks every competency and the
report shows both marks. If the agent's session cannot be reached, assess history only and mark demonstration
BLOCKED. Never substitute a role-play subagent for the real agent.
