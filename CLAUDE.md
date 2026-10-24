# Playscribe

PS5-first patch notes for iPhone Duo. Read these before changing app behaviour or layout:

- `docs/ux-acceptance.md`: the UX flows and acceptance criteria. Cite its IDs (G-4, R-6…) in commits and tests.
- `docs/ps5-patch-data.md`: the PS5 data model and sourcing rules ("On PS5" = PS5 row live + official).
- `docs/api.md`: the feed the app reads.
- Apple: [Designing for iPhone Duo](https://developer.apple.com/design/human-interface-guidelines/designing-for-iphone-duo) and [Preparing your app for iPhone Duo](https://developer.apple.com/documentation/technologyoverviews/preparing-your-app-for-iphone-duo). Check Duo APIs against the installed SDK's swiftinterface, not memory.

## Rules that are easy to break

- **Tabletop: nothing tappable sits above the fold.** The upper half is a view-only stage (`allowsHitTesting(false)`); every control is in the lower half, on the trailing rail.
- No tappable element intersects an active `.division` reserved region in any pose.
- Pose comes from the container and its reserved regions (`DuoReader`), never from device or screen checks.
- No source names, URLs or credits in the UI. Verification tags are the only provenance signal.
- A PC version number is never shown as a PS5 version.
- Navigation containers sit outside every `ArrangementView`.

## iOS app (`ios/`)

```sh
cd ios
xcodegen generate                      # project.yml → Playscribe.xcodeproj (gitignored)
xcodebuild -scheme Playscribe -destination 'platform=iOS Simulator,name=iPhone Duo' test
tools/qa/shots.sh closed /tmp/shots    # QA screen set in the simulator's current pose
python3 tools/build_fixtures.py …      # regenerates bundled fixture JSON from the web prototype
```

Internal builds accept `-qaRoute <route>` at launch (`add`, `settings`, `release/<game>/<release>`,
`video/<game>/<release>`, `first-run`, `demo`, `overlay`, `simulate/<game>/<major|hotfix>`), and Settings has
Simulate update, Reset to first run and a debug overlay of tappable frames and reserved regions.
Simulated pushes: `xcrun simctl push booted co.codeconnectors.playscribe ios/tools/qa/release.apns`.
