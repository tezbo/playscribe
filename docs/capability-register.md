# Capability register: native simulator testing and visual review

Owner: Agent Resources (Gabrielle). Initiative: cloud-native Duo QA (Terry, 24 Nov 2026), workstream 3.
Started 24 Nov 2026. Update this file whenever a capability is proven or a tool changes. Append-only for the audit table.

## Status words

- **PROVEN**: the agent ran it and left an artifact (still, log, run link, PR comment) that names the commit.
- **DOCUMENTED**: a procedure exists in the repo, but nobody has shown an agent running it. Documentation is not competency.
- **n/e**: no evidence either way. Not a zero, not a pass.
- **BLOCKED**, **UNSUPPORTED**, **NOT TESTED**: same meaning as in the engineering directive.

Competency is judged only by an agent running the procedure and posting the artifact. Reading a doc earns DOCUMENTED at most.

## What exists today (read from `origin/main` at 1faa64ae)

| Route | What it gives | Where | Limit |
|---|---|---|---|
| Fold harness stills | `RootView` rendered in an offscreen window at each pose's size, std/AX3/AX5, plus tappable-frame text. Any cloud agent can request it by pushing `.github/stills-request.txt` on a `claude/**` branch | `docs/fold-harness.md`, `harness-stills.yml` | Not the real fold: no hinge animation, no system Table Mode, no hardware |
| CI pose stills | Real simulator, `-qaPose` synthetic division, one job per pose. Request file `.github/pose-stills-request.txt` | `pose-stills.yml`, `docs/ci.md` row 6 | Pilot #485 (12 Nov): only Closed portrait reached the panel; Open/Book/Tabletop are synthetic |
| Screen diffs on PRs | Before/after/diff of changed screens, 70 stills a side, on every PR | `docs/screen-diffs.md` | Harness-based, not real fold |
| Mac gate | Real Device Hub hinge, stills, QA routes (`shots.sh`, `gate.sh`) | `docs/ci.md`, `ios/tools/qa/` | One Mac, one run at a time, about 17 min a pose; needs Terry's Mac |
| Xcode MCP | Build, test, preview, simulator taps from an agent on the Mac | `docs/xcode-mcp.md` | Needs a person's approval first; `BuildProject` never run end to end |
| Candidates under test | sim-use headless fold, Limrun `iphone-duo`, agent-device | `/mnt/project-files/qa/cloud-duo-qa/findings-2026-11-24.md` | All NOT TESTED; owner is engineering ("Build cloud-native iPhone Duo QA") |

## Audit by agent (24 Nov 2026)

Columns: **A** launch the app on a Duo simulator; **B** set a pose or hinge angle; **C** take a native still;
**D** read the accessibility tree or tappable frames; **E** judge a still against the criteria and sign; **F** run a repeatable UI test.

| Agent | A | B | C | D | E | F | Basis and gap |
|---|---|---|---|---|---|---|---|
| Theo, senior iOS engineer | n/e | n/e | DOCUMENTED | DOCUMENTED | n/e | DOCUMENTED | Cloud thread, no Xcode (`ax3-layout-check`). Owns the workflows that produce stills but has not been shown requesting and reading them. Gap: has not run a pose-stills request end to end by evidence in this audit. |
| Max, iOS engineer | n/e | n/e | DOCUMENTED | DOCUMENTED | n/e | DOCUMENTED | Cloud thread, no Xcode. Builds against harness and `precheck-loop`. Same gap as Theo. |
| Quinn, QA lead | PROVEN | DOCUMENTED | PROVEN | PROVEN | PROVEN | n/e | 24 Nov: dispatched "Duo poses (real hinge)" herself (run 45481941098, SHA 49b078de, route gamepage/dawnwalker), opened a still and tree for every pose and posted the pose lines and observations in her thread. Copy: `/mnt/project-files/qa/cloud-duo-qa/sim-use-poses-quinn-gamepage-49b078de/`. Gap: no repeatable UI test run (F). The workflow sets the poses; she chose the route, not the angles, so B stays DOCUMENTED. |
| Iris, design manager | n/e | n/e | n/e | n/e | PROVEN, with a gap | n/e | Reviews and signs stills and screen-diff images, but told Terry on 13 Nov she used no design skill on the release header. Has never launched or folded the app. Gap: judges images handed to her; cannot look for herself. |
| Ollie, Mac tester | PROVEN | PROVEN | PROVEN | DOCUMENTED | n/e | PROVEN | The only agent with a real simulator (stills at 1abc7fc, 91be6aa, c375d0f in project files). Single point of failure: one Mac, serial. |
| Nadia, product owner | n/e | n/e | n/e | n/e | n/e | n/e | Writes acceptance criteria and cards. No evidence she has looked at rendered output herself. Gap: cannot interrogate the evidence on her own. |
| Jun, CX playtester | n/e | n/e | n/e | n/e | n/e | n/e | Playtests on a real device through TestFlight (role). No simulator capability evidenced; thread idle since 19 Nov. |

Reading the table: five of seven agents cannot launch the app, fold it or shoot a still without Ollie's Mac. That is the gap
the initiative has to close. The cloud routes above are already built, so the first step is practice, not new tooling.

## Gaps and owners

| # | Gap | Owner | Action | Status | Due (AEDT) |
|---|---|---|---|---|---|
| G1 | Only Ollie can shoot real stills | Engineering (Build cloud-native iPhone Duo QA) | Prove sim-use or Limrun on a cloud runner; hand over a procedure | NOT TESTED | set by engineering |
| G2 | Nobody outside the Mac has run the CI stills routes by evidence | Agent Resources | Quinn done 24 Nov (see audit table). Iris next, then Theo, Nadia, Jun | Quinn closed; Iris open | after Iris posts |
| G3 | No team skill for simulator testing | Agent Resources | `duo-pose-shoot` written from engineering's proven procedure (PR #630) | Written; proven by Quinn's run | AX5, appearance and recording inputs to fold in once the scenarios run lands |
| G4 | Design review without design skill | Agent Resources, Iris | Iris names `design:design-critique` and `design:ux-copy` in each design reply | Asked 13 Nov; use not verified | next design reply |
| G5 | Nadia and Jun cannot see rendered output | Agent Resources, Nadia | Give each the same request-a-still exercise; Jun reads TestFlight builds on device | Open | after G2 |
| G6 | Xcode MCP approval and first `BuildProject` | Terry's Mac, Ollie | Not a cloud matter; leave until the cloud route is chosen | Parked | n/a |

## Competency checks (run, do not read)

An agent passes a check only with a posted artifact that names the commit.

1. **Harness still.** Push a request file, wait for the run, open the artifact, name one visible defect or state "none found" with the still filename.
2. **PR screen diff.** Open the screen-diff comment on a UI PR and say which screens changed and why.
3. **Real simulator still** (after G1). Launch the app on a Duo simulator through the proven cloud route, set a pose, post the still and the pose actually reached.

Results are appended to the audit table as PROVEN with the artifact link. A failed check is recorded as it happened.

## Not decided here

Tool choice (sim-use, Limrun, agent-device, Appium) belongs to engineering and waits on real runs. No spend without Terry.

## Capability portfolio (Terry, 25 Nov 2026: discovery, evaluation and enablement)

Skills, MCP servers, plugins and observability are one portfolio. Each item has one disposition and one owner. Nothing
here is installed globally or paid for without Terry. Lifecycle: discover a gap, inspect the source, benchmark with and
without, evaluate quality, tokens, time and reliability together, adopt only for the agents that need it, review or retire.

**How a skill is benchmarked.** Skill Creator (`anthropic-skills:skill-creator`, already in every cloud session) runs the
same representative tasks with and without the skill, grades each against written assertions, and reports pass rate,
tokens and time with the spread (`scripts/aggregate_benchmark.py`). Seeded-defect review tasks are the default for
review skills: real Playscribe files with known defects injected, so grading is objective. Sample size is proportionate:
three tasks, one run each, on the model the team actually uses, before anything bigger.

### Benchmarks run

| Date | Skill | Tasks | With skill | Without | Reading |
|---|---|---|---|---|---|
| 25 Nov 2026 | `swiftui-pro` 2.0.0 (vendored 12 Nov) | 3 seeded-defect reviews (GameBookView, SplashView, a new settings view), 13 defects: deprecated API, pose from `UIScreen`, Reduce Motion, GCD timers, `@ObservedObject` ownership, tap-gesture buttons, Dynamic Type. Sonnet, 1 run each | 13/13 found; 83.2k ± 3.9k tokens; 36.7 s | 13/13 found; 68.7k ± 4.9k tokens; 34.5 s | No measured quality gain on these defects; about 14.5k more tokens (+21%) per review. Ceiling effect: the defects were well known, so the test could not show a gain. Next: three harder Duo cases (resizability, reserved regions, toolbar in Tabletop) before any change to how it is used |

Observed, n = 1 per arm: treat as a first reading, not a verdict.

### Dispositions

ADOPT: use now, scoped. BENCHMARK: worth a measured trial first. ALREADY AVAILABLE: we have it; use it, don't add a
second. MONITOR: no current gap or blocked; recheck at the weekly review. REJECT: not worth its cost.

| Candidate | Disposition | Who it serves | Rationale | Owner |
|---|---|---|---|---|
| Skill Creator (Anthropic) | ALREADY AVAILABLE, ADOPT as the benchmark method | Gabrielle's office | In every cloud session; first benchmark run 25 Nov. No install needed | Gabrielle |
| Resource observability via `get_session` usage | ADOPT | Gabrielle, coordinator | Measured per-session tokens, cache and model already readable from the cloud; baseline taken 25 Nov (kept in the office's records, not here). Weekly deltas give the rate | Gabrielle |
| Claude Code OpenTelemetry | MONITOR (Terry, 25 Nov: deferred) | Gabrielle | Needs env settings on the team environments and a collector endpoint, which is a permission and possibly a cost decision. `get_session` covers per-session totals today; OTel would add per-tool and per-skill detail. Revisit only if the weekly deltas show a need | Gabrielle |
| Cowork usage analytics | MONITOR | Gabrielle | Documented for Team and Enterprise plans; the team runs as cloud Claude Code sessions, which `get_session` already covers | Gabrielle |
| GitHub MCP | ALREADY AVAILABLE | All | Every session has `mcp__github__*`, scoped to this repo. Adding the self-hosted server would duplicate it | n/a |
| Knowledge-work plugins (product, marketing, design, engineering, data, productivity) | ALREADY AVAILABLE | Nadia, Mara, Iris, Theo, Max, Gabrielle | Installed in the cloud sessions. Gap is use, not supply (see G4) | Gabrielle |
| Cowork plugin management | ALREADY AVAILABLE | Gabrielle | Used to build the office plugin (#633) | Gabrielle |
| Data analysis plugin | ALREADY AVAILABLE | Gabrielle | Use for benchmark and usage statistics | Gabrielle |
| SwiftUI Pro | ALREADY AVAILABLE, BENCHMARK further | Theo, Max | Vendored, pinned 2.0.0, read through. Costs tokens only when invoked; first benchmark shows no gain on common defects. Keep on demand, don't mandate | Gabrielle with Theo |
| swift-testing-pro, swiftui-accessibility-auditor | ALREADY AVAILABLE, BENCHMARK | Quinn, Theo, Max | Vendored; no benchmark yet | Gabrielle |
| Apple Xcode 27 agent skills and MCP | MONITOR | Theo, Max, Ollie | Ships with Xcode on the Mac; MCP needs a person's approval (`docs/xcode-mcp.md`). Check whether the skill text can be vendored for cloud agents without the Mac | Ollie, then Gabrielle |
| iPhone Duo Skills (hechen) | BENCHMARK, after source inspection | Theo, Max, Iris | Third party, not yet inspected. Overlaps `swiftui-pro` resizability and our own `five-pose-stills`, `duo-pose-shoot` | Gabrielle |
| Swift Agent Skills directory | MONITOR | Gabrielle | A directory for discovery, not a capability | Gabrielle |
| Sosumi | BENCHMARK | Theo, Max, Iris | Apple's docs pages need JavaScript, so plain fetches often fail. Hosted, read-only, no credentials; queries leave the org. Trial: repeat three past Apple-doc look-ups with and without | Gabrielle |
| Limrun MCP | BENCHMARK (engineering owns the trial) | Quinn, Jun, Iris, Nadia | Already a G1 candidate. Paid; key exposure finding open. No spend without Terry | Engineering |
| Context7 | REJECT for now | Priya | The iOS app has no package dependencies; backend use is light. Recheck if dependencies grow | Gabrielle |
| Figma MCP | REJECT for now | Iris | Figma is not our design source; the repo has no Figma references | Gabrielle |
| Playwright | ALREADY AVAILABLE | Priya, Quinn | Chromium and Playwright are preinstalled in cloud containers; a scripted check is cheaper than a browser MCP | Priya |
| App Store Connect CLI skills | MONITOR | Mara, Ollie | Release runs through fastlane and works. Consider read-only analytics later; never write access to the pipeline without Terry | Gabrielle |
| Deferred MCP tool loading (tool search) | ALREADY AVAILABLE | All | On in cloud sessions: tools load only when searched | n/a |
| Selective skill invocation | ALREADY AVAILABLE | All | Only skill descriptions are always loaded (about 1k tokens for the 15 repo skills); bodies load on use | n/a |
| Hooks for deterministic checks | BENCHMARK | Coordinator, engineers | No repo hooks today. Candidates: block pushes that skip precheck, flag a PC version string in UI text | Gabrielle |
| Bespoke Playscribe skills (spoiler class, artwork provenance, lore check) | BENCHMARK when Ezra has a task | Ezra | Specific to Playscribe; a generic plugin would not know V-3 or the spoiler rules | Gabrielle with Ezra |

### Decisions

| Date | Decision | By | Follow-through |
|---|---|---|---|
| 25 Nov 2026 | Defer Claude Code OpenTelemetry; revisit only if the weekly usage deltas show a need | Terry, on the office's recommendation | Weekly review checks the deltas |
| 25 Nov 2026 | Model allocation: Max runs on Sonnet by default, with Opus used per task when the work justifies it (the team's rule is Sonnet by default, Opus restricted) | Terry, on the office's recommendation | Sent to Max through the office desk (req-20261125-01); weekly review confirms the switch |
