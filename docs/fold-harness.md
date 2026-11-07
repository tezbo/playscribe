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

1. Harness: `TEST_RUNNER_HARNESS_DUMP_DIR=/tmp/h xcodebuild test -scheme Playscribe -destination 'platform=iOS Simulator,name=iPhone Duo' -only-testing:PlayscribeTests`. The suite uses Swift Testing, so `-only-testing:PlayscribeTests/FoldHarnessTests` selects 0 tests, and xcodebuild forwards only variables that start with `TEST_RUNNER_`.
2. Simulator: run `PlayscribeUITests/PoseProbeTests` in each pose (add it to `POSE_SUITES` in gate.sh); it prints `POSEPROBE {json}`.
3. `tools/qa/compare_harness.py /tmp/h book=<log> tabletop=<log> …` prints CALIBRATED or the exact differences. Copy the
   differences into `PoseCatalog.swift` (safe area, fold y) and flip `source` to `.captured`. Rerun the gate's probe after
   any Xcode or SDK change; a DIFFERS result means the harness has drifted.

## Prove it would have caught the bugs

`tools/qa/prove_harness.sh` puts each fixed bug back (`tools/qa/mutants.py`: the old toolbar group, the unbounded deck),
requires the harness to fail, then requires the clean tree to pass. Run it once on the Mac or a CI runner before trusting the harness.

## Where it runs

`FoldHarnessTests` is in the `Playscribe` scheme, so the existing PR unit job runs it (about 25 s for six poses plus the
accessibility sizes, no pose driver). The Mac gate (`gate.sh`) therefore only needs to confirm what the harness cannot:
the toolbar as UIKit draws it, the system's page split in Book and Tabletop (TT-0), and real safe areas, until calibrated.
The toolbar cause is also guarded structurally: `LibraryToolbar` gives each item its own slot and a unit test fails if two share one.

## Rules asserted (cite these IDs in commits)

G-4 nothing tappable above the Tabletop fold; TT-0 nothing crosses the fold; TB-1 each Library toolbar item has its own slot (the offscreen window cannot draw the bar, so the drawn-and-44-pt check stays on the sim);
J-5 deck at most 38% of the height (Closed, Open) or 50% (any pose but Tabletop), at default and Accessibility text sizes.

## Navigation-bar band (G-4)

Hosted offscreen, UIKit's navigation bar puts SwiftUI toolbar content in the top band (a 220 x 44 frame appeared there in Tabletop on CI; the Mac calibration of the real Duo shows none). That band belongs to the system, so its frames are printed as `[info, not asserted]` and G-4 is asserted for everything below it. The real-hinge gate keeps asserting the toolbar (TB-1) and G-4 for the whole screen.

## Limits found by the Mac calibration (55240fc)

Safe area, occlusions and the app-owned deck bound (J-5) reproduce in all six poses. Two things do not, and both come from the system's ArrangementView, which splits pages at the window's real reserved region and cannot be given one offscreen:

- Tabletop's rail came out as a horizontal row across the fold (y 335 and 393) where the Duo has a vertical column at x 619. Tabletop G-4 is therefore printed, not asserted, by the harness, and stays asserted by the real-hinge gate.
- Calibrate with the Duo simulator in its portrait scene (outer screen 466 x 678). In its landscape scene (678 x 466) the scene's own leading inset reached the system's layout and moved Closed and Open content 84 pt in (Mac, d11f9c9: rawMinX 100; rerun in portrait: 16, matching CI and the Duo). Each pose prints a `[info, diag]` line with the scene orientation, window, host origin, margins, insets and the leftmost reported frame, so a calibration run can be checked against this.
- Open portrait, Book and Tabletop (container 669 wide) still read x offsets that do not match the Duo (CI and the portrait Mac both read -28 for Open portrait and Book). The hosting window is 155 pt wide, and these poses' pages are placed by the system against that window, not against the 669 pt container, so their x positions are reported but not compared. Their sizes, safe area and the deck bound are.

The harness is evidence for app-owned geometry, not a replacement for the Duo simulator on system-owned layout.

## Scope (Quinn, #227)

The harness can fail a build on the fold, hinge, occlusion, safe-area and rail-placement checks. It never counts as a pass or a sign-off: sign-offs need real stills from the Mac gate. Known gaps against the Duo (Mac compare at 633ba89): frames 84-88 pt narrow in Closed, Open, Closed landscape and Tabletop; about 14 pt high in y; 44 pt left in Open portrait and Book. Therefore:

- Widths: the 84 to 88 pt narrowing was the tab bar's own ~84 pt counted on top of the pose's trailing inset (#360). FoldHost now leaves that inset out for Closed, Open and Book (`tabBarSuppliesTrailingInset`); Closed is verified (deck 346 pt) and asserted one-sided. Open, Book, Closed landscape, Open portrait and Tabletop widths and x are still not asserted until each is read against the Mac.
- Keep above-the-fold and hinge-band checks one-sided with a margin of at least 14 pt: fail on something clearly inside the band, never claim a pass near the edge.
- Say nothing about Tabletop's lower half (rail overflow, Previous/Next); those stay on the Mac gate.
- Open backlog item: find why the tab view draws a vertical tab bar in the offscreen host (docs/roadmap.md).

## Known gaps (Quinn, #360)

- **Book overflow cover is gross-only.** Offscreen, the system places Book's right page at x 475 (inside the 455 to 495 fold) instead of 495, so a full-width page overruns the 867 pt container by 23 pt. The G-8 overflow rule covers Book with that 23 pt allowed on top of the usual 20 pt, so it catches a gross overrun only; the Mac gate is the real Book check. Tabletop's rail is still skipped.
- **Sibling overlap (G-8).** Two tappable frames that cross without one containing the other fail in Closed, Open and Open portrait, and are printed (not asserted) in Book and Tabletop. `overlapRuleFindsCrossingFramesOnly` proves the rule fires. Baseline at a0c2422: no pairs in any pose at AX3 or AX5.
- **What the overlap and overflow rules render (blind spots).** `FoldHost.render` hosts RootView on its default route, so the asserted rules see the Library in each pose; Updates, the Add sheet and every system sheet are not covered. `GamePageOverlapProbeTests` opens the game page (`playscribe://game/kcd2`; `gamepage/<id>` is INTERNAL-only and unit builds ignore it) and prints frames and crossing pairs, unasserted. Result (28cf220 = main before #387 and #382, a26995b = main after): the game page is rendered (Open and Book 22 frames; Closed 4; Open portrait 7 to 9), but the pairs are identical before and after the fixes (Open and Book, std: `23,65 131x44 x 16,65 131x44` and `178,65 229x44 x 171,65 229x44`; AX5: `0,192 58x54 x 16,192 366x107` and `82,192 348x54 x 16,192 366x107`). So the rule does NOT see the Contents-chips-over-link-row bug (#387), and the Updates-rows-under-the-rail bug (#382) is on the Updates tab, which the probe does not open. Both stay Mac-only; the probe stays unasserted. Settings is hosted directly (`FoldHost.renderView`) for the scroll check only.
- **Tall screens scroll at AX5 (G-8).** `SheetScrollTests` hosts SettingsView directly (`FoldHost.renderView`, because a system sheet is not in the capture) and asserts it has an enabled scroll view whose content is taller than the viewport (a0c2422: Closed 678 vs 2892, Open 669 vs 1958, Open portrait 951 vs 2713). The Add sheet is not covered yet.
- **Open and Book widths are assumed, not read.** FoldHost leaves the pose's 84 pt trailing inset out for every pose that has one (the tab bar supplies it), and only Closed has been read against the Mac (deck 346 pt). Every harness still taken before #360 is 84 pt narrower than the Duo, so earlier Book left-page calibrations are stale: re-run them on the new widths before anyone trusts harness wraps.
