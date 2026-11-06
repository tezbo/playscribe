---
name: playscribe-estimate
description: Use when picking up, sizing or closing any Playscribe board card or PR, or when asked how long something will take. Produces est_work, est_wait and basis the same way for every agent, using agent-estimate's PERT three-point method, and records actual_work and actual_wait at Done. Never a guessed number; write n/e when there is no basis.
---

# Playscribe estimate

One method for every agent (Terry, 2026-11-07): nothing made up. Fields on the card: `est_work`, `est_wait`, `basis`, then `actual_work`, `actual_wait`.

## Method
1. **Scope** the card in one line and pick the task type (coding, frontend, app_dev, config, documentation, research, brainstorm).
2. **Run agent-estimate** (Terry approved installing it, 2026-11-07 (his message cmsg_0158fPo4KUquo5U1yUvNer8vT8XLJkrPTdpVzVsqmyJmGH); `pip install agent-estimate`, tested v0.10.0 engine). Command: `agent-estimate estimate --format json --type <type> "<scope>"` (flags in `../agent-estimate/SKILL.md`; add `--spec-clarity`, `--warm-context` only with a reason in `basis`). Read `tasks[0]`: `base_pert.optimistic_minutes`, `most_likely_minutes`, `pessimistic_minutes`, `expected_minutes`, then `effective_duration_minutes` (after modifiers) and `review_overhead_minutes`. `est_work` = `effective_duration_minutes` / 60 (hours). Put O, M, P, the modifiers and `estimation_category` in `basis`. Example run: config task "AX3 variant of Closed CI shots": O 10, M 20, P 35, expected 20.8 min, review overhead 15 min.
3. **No CLI (cannot install)? Do PERT by hand, same shape:** write optimistic O, most likely M, pessimistic P in hours of agent work. `est_work = (O + 4M + P) / 6`, and note the spread `(P - O) / 6`. Anchor O, M and P on comparable past cards (their `actual_work`), never on feel. State "manual PERT" in `basis`.
4. **Reliability check:** the upstream notes treat work above a model's reliability threshold as risky (sonnet_5_5 30 minutes, opus_5_5 and fable_5_1 90 minutes of friction-adjusted work; these are MINUTES while `est_work` is in HOURS, so convert before comparing: 2 h = 120 min, which is over 30). These are upstream's "local reliability policy (unmeasured)", not measured limits. If `est_work` exceeds it, split the card.
5. **`est_wait`:** hours expected waiting for stills, sign-off, Mac gate or Terry. Start from the CLI's `review_overhead_minutes` (/ 60) and add the queue waits you can cite from the board. Base it on the last similar waits on the board; QA wait is our biggest variance.
6. **`basis`:** scope line, comparable past cards with actuals, main risks, and the method used (CLI or manual PERT).
7. **No basis at all:** write `n/e` in `est_work` and `est_wait`. Do not invent a number.
8. **At Done:** write `actual_work` and `actual_wait` (same split) and one line on any gap over 2x.

Real excerpt of `agent-estimate estimate --format json --type config "Add AX3 variant of Closed CI shots to ios-ui.yml"` (engine 0.10.0), trimmed to the fields used:

```json
{
  "tasks": [
    {
      "base_pert": {
        "expected_minutes": 20.833333333333332,
        "most_likely_minutes": 20.0,
        "optimistic_minutes": 10.0,
        "pessimistic_minutes": 35.0
      },
      "effective_duration_minutes": 20.833333333333332,
      "review_overhead_minutes": 15.0,
      "estimation_category": "config",
      "modifiers": {
        "spec_clarity": 1.0,
        "warm_context": 1.0,
        "agent_fit": 1.0
      }
    }
  ]
}
```

## Install note
`pip install agent-estimate` was approved by Terry on 2026-11-07 (his message cmsg_0158fPo4KUquo5U1yUvNer8vT8XLJkrPTdpVzVsqmyJmGH, a reply to the coordinator's question about installing it). The upstream is vendored in `../agent-estimate/` (Apache-2.0, credited in `SOURCE.md`). The CLI's bundled priors come from a small set of upstream dispatches (`n=0` calibration observations applied here), so treat output as a consistent starting point, and let `actual_*` at Done be the real calibration.
