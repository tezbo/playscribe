# Team evidence sources (read-only use)

Identifiers for the team's sessions, threads and artifacts are kept in the private records
(`01-agent-registry/roster-*.json`), not in this plugin, because the plugin source may be public.

| Source | What it proves | How OIA reads it | Write risk to avoid |
|---|---|---|---|
| Git history of the product repo | What changed, when, by which session (`Claude-Session:` trailer), with which message | `git fetch origin main` then `git log`, `git show`; unshallow first (`git fetch --unshallow`) | Never push; never commit outside an OIA branch |
| Pull requests, reviews, checks | Review and sign-off practice, CI verdicts per SHA | GitHub MCP `pull_request_read`, `list_pull_requests`, `get_commit` | No comments, reviews, merges or label changes |
| GitHub Actions runs and logs | Execution evidence: tests run, poses shot, TestFlight uploads | `actions_list`, `actions_get`, `get_job_logs`; artefacts listed, not downloaded unless needed | Never trigger `workflow_dispatch` on release, TestFlight, certs, feed or relay workflows |
| Agent session transcripts | What each agent was asked, did and said, with timestamps | `list_events` (kinds `user`, `assistant`, `result`), `get_event`, `get_session` on the registry's session ids | Never `send_message` during evidence collection (that is engagement, see `engagement.md`) |
| Team thread roster | Who exists, state of each thread | Roster snapshot in `01-agent-registry`; refresh from commit trailers and `get_session` | None |
| Scheduled tasks | Standing rhythms the team runs (for example 3-hourly reports) | `list_triggers` with `all_in_account: true` | Never update, fire or delete a team scheduled task |
| Sprint board database | Cards, estimates, moves, decision notes, activity | `ArtifactData` `list`/`query` on the board URL in the registry | No writes; the tool permits them, so take care |
| Repo docs | Rules and their dates (`AGENTS.md`, `SKILLS.md`, `docs/learnings.md`, `docs/decisions/`, `docs/ci.md`, `docs/release.md`, `CHANGELOG.md`) | Read at a named SHA | None |
| Team project files (`/mnt/project-files` of the team project) | QA stills, improvement plans, run summaries | **Not reachable from the OIA project.** Ask the owning agent for a copy, or have Terry attach it. Label copies "provided by <agent>" | — |
| TestFlight / App Store Connect | Build distribution, tester feedback | Only through the team's workflow logs (`testflight*.yml` runs); OIA holds no App Store Connect credentials | Never call App Store Connect |

## Credentials

Every agent, including OIA, runs on Terry's account and GitHub identity. There is no read-only credential for OIA
today. "Read-only" is a discipline enforced by this plugin's instructions and its records guard, not by the
platform. See `independence.md`.

## Secrets

Transcripts can contain secrets pasted by people (an API key was found in a team transcript on 2026-11-24). Redact
before snapshot and raise a finding with the location (session id, event uuid or message id), never the value.
