# CI plan: faster, and scalable

Times are estimates (AEDT is irrelevant here; these are durations) from the 80-minute Mac gate and a typical hosted
`xcode-27` run. Measure the first runs after merge and correct this table.

## Where the time goes today

| Stage | Where | Now |
|---|---|---|
| Unit tests, then UI compile (two builds, in series) | GitHub, `ios.yml` | ~14 min |
| Five-pose gate (`gate.sh`, 5 to 6 poses serial, ~17 min each with stills) | Terry's Mac, one Device Hub window | ~80 min |

The gate is slow because a pose is set by pressing Device Hub through Accessibility, which is one GUI, so poses cannot overlap
on the Mac. Hosted runners are headless, so they cannot press it either.

## Plan

| # | Change | Saves | Status |
|---|---|---|---|
| 1 | `ios.yml` runs unit tests and the UI-test compile as two parallel jobs; the compile uses a generic simulator destination (no boot) | ~5 min per PR | this PR |
| 2 | CI-only build settings: no previews, no index store, dwarf not dwarf-with-dsym, active arch only; boot the simulator while building | ~1 to 3 min per job | this PR |
| 3 | `xcodegen` installed only if missing, Homebrew auto-update and cleanup off; job timeouts so a hang costs 30 min, not 6 hours | ~1 min, hang cost | this PR |
| 4 | Gate: `STILLS=0` by default (stills only on request or for release tags). Stills are re-presses of the pose, about 15 s each, plus 4 captures per pose | ~25 min of the 80 | next, on the 0.5.0 gate.sh |
| 5 | Gate tiers: PR tier = Closed + Tabletop (the two layouts that differ most), full five poses nightly and on `v*` tags | PR gate ~80 to ~25 min | next |
| 6 | Pose without Device Hub: an internal-build launch argument `-qaPose book/tabletop/open` that feeds `DuoReader` a synthetic division. Pose-sensitive suites then run headless, in parallel (one job per pose, 6 jobs), on hosted runners; the real-fold gate stays for release only | PR gate ~80 to ~15 min, no Mac | needs Terry's call: it adds a debug hook to the layout path |
| 7 | Build once, test in shards: `build-for-testing` uploaded as an artifact, shards `test-without-building` | scales with suite size | after 6 |
| 8 | Test selection by changed paths (docs, backend: no iOS jobs; already true via path filters) | n/a | done |

## Not worth doing
- Caching DerivedData: the project has no SPM packages, and a fresh checkout changes every file's mtime, so Xcode rebuilds the
  Swift modules anyway. Revisit if packages are added.
- Parallel simulator clones on the Mac for poses: Terry's notes say the Duo sim already overloads the Mac (load 800+).
