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
| Iris, design manager | PROVEN | PROVEN | PROVEN | PROVEN | PROVEN | n/e | 24 Nov: dispatched "Duo poses (real hinge)" herself on main 1eb4f2cc, route gamepage/dawnwalker (run 45489150050, 42 shots), read the pose lines and looked at the stills. Found a real bug (rail Back disc empty in Book and Open landscape, board card bug-landscape-rail-back-empty) and judged Quinn's Book link-frame finding as the QA overlay's tap box, not a defect. Copy: `/mnt/project-files/qa/cloud-duo-qa/duo-poses-1eb4f2c-run45489150050/`. Earlier (13 Nov): used no design skill on the release header. Gap: design skills in her replies still unverified (G4). |
| Ollie, Mac tester | PROVEN | PROVEN | PROVEN | DOCUMENTED | n/e | PROVEN | The only agent with a real simulator (stills at 1abc7fc, 91be6aa, c375d0f in project files). Single point of failure: one Mac, serial. |
| Nadia, product owner | n/e | n/e | n/e | n/e | n/e | n/e | Writes acceptance criteria and cards. No evidence she has looked at rendered output herself. Gap: cannot interrogate the evidence on her own. |
| Jun, CX playtester | n/e | n/e | n/e | n/e | n/e | n/e | Playtests on a real device through TestFlight (role). No simulator capability evidenced; thread idle since 19 Nov. |

Reading the table: five of seven agents cannot launch the app, fold it or shoot a still without Ollie's Mac. That is the gap
the initiative has to close. The cloud routes above are already built, so the first step is practice, not new tooling.

## Gaps and owners

| # | Gap | Owner | Action | Status | Due (AEDT) |
|---|---|---|---|---|---|
| G1 | Only Ollie can shoot real stills | Engineering (Build cloud-native iPhone Duo QA) | Prove sim-use or Limrun on a cloud runner; hand over a procedure | NOT TESTED | set by engineering |
| G2 | Nobody outside the Mac has run the CI stills routes by evidence | Agent Resources | Quinn and Iris done 24 Nov (see audit table). Theo, Nadia, Jun next | Quinn and Iris closed; Theo, Nadia, Jun open | after each posts |
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
