---
name: workaround-first
description: Use before sending any reply that is about to say "can't", "only", "missing", "not available", "blocked" or "needs Terry". Requires three checks for a route around the limit, then reports the route and a recommendation instead of the blocker. Applies to every agent and the coordinator.
---

# Workaround first (Terry, 2026-11-06)

A limit is never the answer; the route around it is. Before naming a limit, check all three:

1. **Can the repo, a file or a workflow carry it?** A skill in `.claude/skills/`, a line in `AGENTS.md`/`SKILLS.md`/`CLAUDE.md`, a GitHub Action, a script in `ios/tools/`, a doc in the shared folder.
2. **Can another thread or tool do it?** The Mac tester for simulator work, Theo's pipeline, another connector or MCP tool, a subagent, a scheduled `send_later`.
3. **Can we build the missing piece ourselves?** A small script, workflow, headless check or skill, then propose it (Gabrielle, or a PR).

Then reply with: the route you are taking (or proposing), your recommendation, and only the part that truly needs Terry (irreversible or money, with his plain yes). Never "can't" without an alternative; never park on Terry what the team can decide.

Example: "I only see the standard skills" became "skills live in `.claude/skills/` in the repo, so every thread gets them: PR open."
