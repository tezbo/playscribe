---
name: precheck-loop
description: Use whenever a cloud agent without Xcode is about to push code or open or update a Playscribe pull request. Push to a claude/* branch, read the PRECHECK PASS or FAIL verdict for the head commit, fix until PASS, only then open the PR. Prevents failed-CI emails to Terry.
---

# Precheck loop

Every red CI run emails Terry, because agent pushes run as him. Precheck (`.github/workflows/precheck.yml`) compiles the app, unit tests and UI tests (~3 min) and always ends green; the verdict is in the job name.

0. Before you branch, run `git fetch origin main` and cut from `origin/main`. Cloud sessions can hold a stale or shallow main (a branch cut from one had unrelated history, caught before merge; `docs/learnings.md` entry 1).
1. Push to your `claude/*` branch. Docs-only and workflow-only branches skip Precheck. Relay changes use the `RELAY PASS/FAIL` check (`relay-check.yml`).
2. Read the verdict for your **head commit**: the check run / job name `PRECHECK PASS` or `PRECHECK FAIL <file>:<line> <error>` (also the `precheck` commit status).
3. FAIL: fix, push, repeat. No stacked pushes, never push to a PR your last Precheck marked FAIL. A missing verdict is not a pass.
4. PASS: open the PR, then subscribe to its activity. The PR body names acceptance IDs and starts with the attribution block.
5. If a test (not compile) fails after the PR opens, it is yours at once.
6. Any workflow you write that posts status: its `curl` ends `|| true`, inputs go through `env`, never inline `${{ }}` in `run:`, always `exit 0` after setting the verdict.
