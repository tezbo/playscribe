---
name: resource-efficiency
description: >
  This skill should be used to assess resource stewardship and execution efficacy: "token usage", "is this
  efficient", "resource efficiency audit", "execution efficacy", "context overhead", "model allocation",
  "systemic waste", "execution budget", or the resource part of a weekly review.
metadata:
  version: "0.2.0"
---

# Resource stewardship, execution efficacy and context

Load `assurance-charter` first. Efficiency is never judged apart from the verified outcome: lower consumption with
worse quality, more rework or more sponsor intervention is not an improvement.

## Telemetry (measured versus proxy)
- Measured, per session: `get_session` → `external_metadata.usage` (input, output, cache read and write tokens,
  `cost_usd`), model, effort, `claude_reply_count`, `context_usage`. `cost_usd` is an API-price equivalent, not a
  subscription charge: never report it as money spent.
- Measured, per CI run: duration, runner, conclusion (`actions_list`).
- Measured, per scheduled task: fires and last-run status (`list_triggers`).
- Paid services (for example Limrun): credits or minutes from the service's own records when reachable; else
  "unavailable".
- Proxies when telemetry is missing: repeated reads of unchanged files, duplicate investigations, retries,
  builds per merged PR, simulator sessions, agent-to-agent message count, context size at compaction.
Label every number: measured, estimate (method), proxy, or unavailable. Never invent a figure.

## Execution efficacy audit (sampled assignments)
Sample completed assignments across types (routine, substantial, investigation, defect, release, unsuccessful).
For each, answer the 12 lifecycle questions in the founding charter (outcome intended, appropriate, delivered,
evidence, resources across the full lifecycle, contributing activities, necessary coordination and verification,
avoidable work, downstream rework and sponsor intervention, alternative approach, reusable learning, effect on future
capability). Classify consumption: direct value; necessary discovery; necessary verification; necessary
coordination; capability development; avoidable overhead; preventable rework; unproductive or abandoned;
unclassified.

## Systemic waste patterns to look for
Excess context; re-reading unchanged files; parallel investigations without a verification purpose; excess
delegation and ceremonies; irrelevant disciplines; premium models for routine work; long exchanges without
decisions; planning without execution; blind retries; unnecessary builds or simulator sessions; unbounded
refinement; rediscovery; overlapping scheduled tasks; scope growth without value; work after acceptance; releasing
unverified work that causes rework. Find the root cause and owner (`findings-and-actions`).

## Context overhead
Measure standing instruction size (project instructions, CLAUDE.md, AGENTS.md, SKILLS.md, always-loaded skill
descriptions, hook-injected text) in characters and estimated tokens (chars/4, labelled estimate). Check which files
the tooling actually loads (Claude Code: CLAUDE.md and `.claude/skills`; AGENTS.md is not loaded unless referenced).

## Model allocation and automation
Check against the sponsor's rules (Sonnet default; Opus restricted). Flag repeatable mechanical work done by LLM turns
that a script or CI job could do; propose automation with its build cost.

## Budgets and experiments
Propose budgets from historical performance, not universal limits. Treat improvements as hypotheses: baseline,
bounded change, compare similar work, keep only net benefit; distinguish observed from forecast savings.
