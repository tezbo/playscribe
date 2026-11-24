# Engaging the team's agents

Two different things, never to be confused in a report.

## A. Engaging an existing agent session (the real agent)

The team's agents are long-running Claude Code sessions (one per project thread). Each accepts cross-session
messages (`cross_session_inbound: available` in `get_session`). OIA sends a message straight to the session:

- Tool: `mcp__claude-code-remote__send_message` with `session_id` from the registry.
- Delivery is confirmed when the call returns; an answer arrives later as a new turn in the OIA session if the agent
  replies with its own `send_message` to the OIA session id. Include the OIA session id in every message.
- The Coordinator is not in the path. The message lands in the agent's own thread; the agent may still choose to tell
  the Coordinator. Record whether it did (from its transcript) as evidence of behaviour, not as a breach.
- Mark every OIA message with the header `[OIA <engagement id>]` and state: who is asking (Gabrielle, OIA, reporting
  to Terry), what is needed, the deadline, and that no change to work is requested unless stated.
- Evidence of the engagement: the send result, the target's transcript events (`list_events`) showing receipt and
  response, and any artefact produced. Record all three with `oia.py record --area demonstration`.

Use it for: interviews, practical demonstrations, behavioural challenges (when sealed and authorised), and
requests for copies of evidence held only in the team project.

**Tested 2026-11-24: refused across projects.** From the OIA project, `send_message` to a team session (both the
`session_…` and `cse_…` id forms) and a one-shot scheduled task bound to a team session both returned
`the requested resource was not found`, while `get_session` and `list_events` on the same sessions worked. Read
access crosses the project boundary; write access into team sessions does not. Until the sponsor provides a route
(see `independence.md`, "Engagement"), use route A only for sessions inside the OIA project, and for team agents use
the sponsor-approved courier route below.

Limits: a session that is archived or compacted may not hold the context the question assumes; a reply is the
agent's statement (assertion) unless it points to artefacts; Terry's own thread posts are not reachable this way.

## A2. Courier route for team agents (while cross-project messages are refused)

A thread in the team project that acts only as OIA's courier: it receives an OIA brief pasted by the sponsor or
created by the team project's coordinator on the sponsor's instruction, forwards it with `send_message` to the
named agent, and forwards replies back. It holds no records and draws no conclusions; OIA verifies every reply
against the agent's own transcript (`list_events`), which OIA can read directly. Its existence is visible to the
team Coordinator; its content is not directed by the Coordinator. Needs the sponsor's decision.

## B. Instantiating an agent from a role definition (a stand-in)

A subagent (this plugin's `agents/`) or a fresh session primed with a team member's role text is a **new agent**. It
has none of the real agent's history, memory or habits. Use it only for: independent second marking, specialist
analysis of evidence, or calibrating what a competent agent in that role would do. Never present its output as the
team member's behaviour or competency.

## C. Repository-backed assignments (asynchronous, auditable)

For work that should leave a public trail, OIA may open a GitHub issue labelled `oia` assigned to the role, or ask
the agent by message to answer in a named file on an `oia/*` branch. Only with the sponsor's agreement, because the
repository is shared with the team's normal flow and may be public.

## D. Not used

The sprint board and the Coordinator's relay are team orchestration systems. OIA reads them but does not assign
work through them, so the team's self-organisation can be observed unaltered.
