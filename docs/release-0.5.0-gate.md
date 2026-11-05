# 0.5.0 release candidate: Mac gate checklist

Run on the exact SHA being signed off, in all five poses (Closed portrait, Closed landscape, Open/Flat, Book, Tabletop).
UI tests: `xcodebuild -scheme PlayscribeUI -destination 'platform=iOS Simulator,name=iPhone Duo' test`. For each row,
tap the control; stills alone do not count (J-4). Every capture also passes the fold audit (TT-0: no frame crosses the
`.division`, nothing tappable in Tabletop's upper half). The pose script must verify panel and orientation.

Fixtures: `-qaRoute demo` (Dawnwalker, KCD II, CONTROL, Wukong, Blue Prince), `first-run`, `fill-library/28`.
Routes: `library`, `updates`, `add`, `settings`, `release/<game>/<release>`, `chapter/<game>/<chapter>`, `overlay`.

| Feature | Acceptance | Simulator checks (each pose) | Test |
|---|---|---|---|
| Latest updates hero (deck) | J-1, J-2, J-5a to c | Card opens its update; leaf dots are 44 pt; "NEW UPDATE" wording; Tabletop hero is display only | `testHeroDeckCardOpensItsUpdate` |
| Catch-up card, caught-up card | J-5, A6 | Lists new, fixed, balance counts and up to 3 top changes; caught-up shows when nothing is unread; names wrap at AX5 | stills |
| Change groups, search | J-1, G-7 | New/Fixed/Balance headings with counts; PC-only only on note lines; note search groups by release | stills |
| Known issues, Following | J-2, G-7 | Follow toggles with toast "Following this issue"/"Stopped following"; "Following" list rows read Not fixed yet or Fixed in <version> | `testFollowKnownIssue` |
| News (chapter and Library strip) | J-1, J-3 | Chapter shows list, "No news yet" or Retry, never blank; strip leaves the hinge clear in Book | `testNewsChapterIsNeverBlank` |
| Upcoming and watchlist | J-1, J-6 | Picker (Tabletop: rail buttons) switches; empty copy; tapping a tile watches and opens the game; "Out this week" shows only for dates in 7 days; release-day alert at 09:00 | `testUpcomingTabAndWatchlist` |
| Similar games | J-2 | Up to 8 PS5 tiles, none already in the library; dialog offers Add to library or watchlist | stills |
| Share card | J-2 | Share button is 44 pt; card renders with art and three changes; Retry on failure | `testShareUpdateButton` |
| Reading time | G-7 | "N min read", VoiceOver "About N minutes to read" | audit |
| Page turn | D-10 | Book only: 0.35 s slide from the spine, shadow fades, taps ignored until done; Reduce Motion gives a 0.2 s crossfade in every pose; debug overlay shows no overlap with the hinge | capture mid-turn |
| Add by type, say, photo, camera | A-1 to A-9, J-6c | One results list with pinned "Add N games" bar (44 pt); Is this it? guesses; Added toast with Undo for 5 s | `testPinnedAddBar` |
| First-run welcome | A-1 | Four rows and Skip for now; Skip lands on the empty Library, never blank; row opens Add on that method | `testFirstRunWelcomeAndSkip` |
| Permission explainers | G-10 | Explainer before the system prompt; Not now and denied states always offer Type it first | `testSayItExplainer` |
| Tabletop rail | TT-0 | Playing and Upcoming on the lower trailing rail; rail still fits at AX5 | fold audit |
| Reader performance | J-2d | Dawnwalker 1.1 scrolls without hitches | `ReaderPerformanceTests` (device) |

## Real-device checks (Terry's Duo or any iPhone)
- **Microphone, Say it:** explainer, then system prompts for speech and mic; hold to talk; transcript; nothing heard copy; denied state offers Type it, Open Settings.
- **Photo:** pick a shelf photo; titles found; "No game titles found" path; Is this it? list.
- **Camera:** explainer, system prompt, live scan on a shelf or game boxes, Find these games; denied state; unsupported device.
- **Home Screen widget:** add small, medium, large; unread shows New chip and "N new updates" (large); tapping a row opens that update; empty and no-games copy; light and dark; VoiceOver labels.
- **Lock Screen widget:** rectangular and inline; newest unread; tap opens the update.
- **Siri and Spotlight:** only if the App Intents spike (#119) is accepted into 0.5.0; "What's new in <game>" by voice and Shortcuts; a library game found in Spotlight opens its page.
- **Notifications:** release-day alert for a Wishlist game; known-issue fixed alert; permission card shows at most twice.
- **Settings:** version line "Version 0.5.0, build N, <sha>".
- **Signing (before TestFlight):** App Group and widget App ID registered per `docs/release.md`.

## Sign-offs
Backend and data, front end (tap evidence for every row), and UX and UI, each naming the SHA; then the sprint review; then
Terry's go (docs/release.md).
