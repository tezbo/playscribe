# Fold harness: layout checks without the simulator

The 0.5.0 gate (about 17 min a pose, serial, Device Hub) caught two bugs that review and unit tests missed. The harness
renders the real `RootView` at each pose's exact container and checks the same rules in seconds, in parallel, on any
runner. It does not replace the real-hinge gate for release sign-off; it makes that gate find nothing new.

## Why the two bugs got through

| Bug | Cause | Why only the simulator showed it |
|---|---|---|
| Hero deck 727 pt in Open, screen-tall in Closed portrait (e869273) | An unsized horizontal pager takes the height it is offered; at 28 games nothing bounded it | Unit tests never lay a screen out at a pose's real size. XCUITest `app.frame` also reports portrait in landscape poses |
| Settings cog missing outside Tabletop (551d8ce) | A second `topBarPinnedTrailing` item was collapsed away by UIKit's navigation bar | The system decides this from the bar's real width and traits; no model or SwiftUI-only test sees it |

Both are *geometry rules evaluated in a real UIKit window*. Pose logic already depends only on the container size, the
reserved regions and the width size class (`DuoReader`), so those inputs can be supplied directly.

## What the harness reproduces

`FoldHost.render` hosts `RootView` in a `UIHostingController` in an offscreen `UIWindow` sized to the pose, with safe
area, size class and Dynamic Type applied as trait overrides, and the fold injected through `\.injectedRegions` (the one
seam in `DuoReader`; the app never sets it). Frames come from the app's own `tappableFrame` and `namedFrame` reporters,
the same ones the fold audit and debug overlay use.

| Faithful (same code path as the sim) | Not reproduced |
|---|---|
| Pose derivation, every `duo.*` branch, the Tabletop rail and lower-half rule | The system's own fold behaviour: reserved regions shifting with the hinge angle, animation between poses |
| Frames of every tappable control, fold crossings, above-the-fold, named containers (deck) | Hardware: camera occlusion shape, true screen scale, status bar and Dynamic Island content |
| UIKit navigation bar and toolbar item dropping (a real `UINavigationBar` at the pose's width) | Sheets/presentations that size to the screen (they size to the window here) |
| Size classes and Dynamic Type through trait overrides | Anything that needs a real scene: Duo-only APIs that read the display |

**Accuracy is a measured claim, not an assumption.** `PoseCatalog.swift` marks each pose `provisional` (read off the Mac
stills: sizes exactly, folds to about 1 pt, safe area assumed zero) until `tools/qa/compare_harness.py` proves it equal
to the simulator.

## Real fold geometry (from the 0.5.0 stills, 2a56de7)

| Pose | Container (pt) | Fold, container coordinates |
|---|---|---|
| Closed | 382 x 644 | none |
| Closed landscape | 594 x 432 | none |
| Open | 867 x 635 | none |
| Open portrait | 669 x 835 | none |
| Book | 867 x 635 | x 455 to 495 (printed by the fold audit) |
| Tabletop | 669 x 835 | y about 374 to 414 (measured from the overlay) |

The hinge is **40 pt and off-centre**. A 24 pt band centred on the container (the `qaPose` idea in #225) would put
Book's fold at 421 to 445 and Tabletop's at 405 to 429, so it could pass layouts the real fold fails.

## Calibrate (one gate run, then trust)

1. Harness: `HARNESS_DUMP_DIR=/tmp/h xcodebuild test -scheme Playscribe -destination 'platform=iOS Simulator,name=iPhone Duo' -only-testing:PlayscribeTests/FoldHarnessTests`
2. Simulator: run `PlayscribeUITests/PoseProbeTests` in each pose (add it to `POSE_SUITES` in gate.sh); it prints `POSEPROBE {json}`.
3. `tools/qa/compare_harness.py /tmp/h book=<log> tabletop=<log> …` prints CALIBRATED or the exact differences. Copy the
   differences into `PoseCatalog.swift` (safe area, fold y) and flip `source` to `.captured`. Rerun the gate's probe after
   any Xcode or SDK change; a DIFFERS result means the harness has drifted.

## Prove it would have caught the bugs

`tools/qa/prove_harness.sh` puts each fixed bug back (`tools/qa/mutants.py`: the old toolbar group, the unbounded deck),
requires the harness to fail, then requires the clean tree to pass. Run it once on the Mac or a CI runner before trusting the harness.

## Rules asserted (cite these IDs in commits)

G-4 nothing tappable above the Tabletop fold; TT-0 nothing crosses the fold; TB-1 Settings and Add drawn and at least 44 pt;
J-5 deck at most 38% of the height (Closed, Open) or 50% (any pose but Tabletop), at default and Accessibility text sizes.
