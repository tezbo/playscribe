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
- No source names, URLs or credits in the UI. Verification tags are the only provenance signal. V-3 in `docs/ux-acceptance.md` is the full rule and has one exception: a link row names the destination it opens by brand, from the link host ("Read full notes on Steam", "PS5 update page on PlayStation", "All patch notes on Ubisoft"); never an address.
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

Internal builds accept `-qaRoute <route>` at launch (`add`, `settings`, `quick/tip`, `quick/undo`, `quick/wishlist`, `release/<game>/<release>`,
`video/<game>/<release>`, `cover[/one|/<game>]` (front cover preview; `<game>` leads, unread), `gamepage/<game>`, `library/<playing|upcoming|upcoming-seeded>`, `first-run`, `demo`, `one-update`, `two-update`, `three-update`, `four-update`, `many-updates` (full deck, +N chip; add `/updates` to open the Updates tab, e.g. `two-update/updates`), `caught-up` (no hero), `no-notes/<game>[/untracked]` (only that game, update history hidden: the no-release hero, "No patch notes yet" or the untracked line; the game needs a past release date), `plus-demo` (PS Plus card), `plus/<1|2|3|4|5|plate|last|off>`, `alerts` / `alerts-denied` (N-1 card), `keep-current[/on]` (N-9 card; `/on` = the Settings switch on), `overlay`, `pill`, `spoiler-demo[/shown]`, `dayone/<game>` (the two-update demo plus an unread day-one patch, live and official on PS5, for that game: the Day-one patch chip beside a New update card, and the game-page line; reading it clears both, for a second-visit still), `long-title/<game>` (a PS5 update with a very long invented title), `long-word/<game>` (an update headline with a very long word, in the Updates tab), `share-card/<game>/<release>` (opens that update and writes its share card at 1080 x 1350 to Documents/share-cards/, to pull with `simctl get_app_container booted co.codeconnectors.playscribe data`), `simulate/<game>/<major|hotfix>`), and Settings has
Simulate update, Reset to first run and a debug overlay of tappable frames and reserved regions.
Simulated pushes: `xcrun simctl push booted co.codeconnectors.playscribe ios/tools/qa/release.apns`.
