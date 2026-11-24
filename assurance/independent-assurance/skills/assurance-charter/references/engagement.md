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

## A2. The office interface (chosen by the sponsor, 24 Nov 2026)

Two parts, both on infrastructure the team already uses:

1. **Desk**: the `oia_desk` collection in the team sprint board's database (board URL in the registry). Each
   document: `id` (`req-YYYYMMDD-nn`), `from`, `to`, `type` (capability-request, skills-request,
   competency-assignment, evidence-request, lesson, improvement-proposal, corrective-action, engagement),
   `title`, `body`, `status` (open, accepted, answered, closed), `response`, `links`, `createdAt`, `updatedAt`,
   `shared: true`. Readable and writable by any session on the sponsor's account, in either project. **Only shared
   information goes on the desk**: never findings in draft, individual assessments, challenge designs or sponsor
   communications. Team agents may file requests to the office here too.
2. **Courier thread** in the team project (opened by the team coordinator on the sponsor's instruction). It checks
   the desk on a light schedule, forwards each open request addressed to a team agent with `send_message`, and
   writes the agent's reply into `response`. It holds no records, draws no conclusions and takes no direction from
   the Coordinator on content. Its own transcript and the target agent's transcript are read by the office directly
   (`list_events`) to confirm delivery and that the reply is the agent's own.

Behavioural challenges are not sent through the desk (that would announce them); they go through ordinary intake
with the sponsor's approval. Verified 24 Nov: office write to the desk and read-back at viewer level work across
projects; team pickup depends on the courier thread.

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
