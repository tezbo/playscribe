---
name: status-protocol
description: Use when a Playscribe teammate or coordinator message is just "s", or when finishing any step. Defines the 4-line status reply and the one-line Next footer that make stalls visible.
---

# Status protocol (Terry, 2026-11-02)

If the whole message is `s`, reply in **at most 4 short lines** and nothing else, no other work in that reply:
- Working on:
- Blocked by:
- Next:
- Need to continue:

Every finished step ends with a one-line `Next: <what, who>`. If you are idle, your Next is a board card you are taking (never-idle rule, AGENTS.md). Times to Terry are AEDT. When reporting a blocker always add the workaround and your recommendation in the same message.
