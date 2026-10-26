# Playscribe (formerly Gamebook) UX flows and acceptance criteria (v2.2, 2026-10-26: V-4 "Unconfirmed" treatment for press-reported releases, approved by Terry; v2.1, 2026-10-25: D-10..D-13 side swap, multitasking, PS5-style tiles, saved preferences; v2.0 section 11 "One layout, every pose" after Terry's native test supersedes section 9, B-5, B-6, R-9, R-10, TT-1 and TT-3; v1.4: section 10 gamer-review fixes GR-1..GR-7, N-11 quiet Reported alert; v1.3 Tabletop and video redesign TT/VB; v1.2 section 9 Open pose and transitions added; v1.1 added G-12, G-13)

Owner: UX/CX QA thread. Decided 2026-10-24 under Terry's delegation. This is the contract the SwiftUI app builds against and QA tests against. Put it in the repo as `docs/ux-acceptance.md`. IDs are stable: cite them in commits and test names.

It supersedes `fixes-round1.md`, which is folded in here. The PS5 data rules come from `gamebook/platform-data/ps5-patch-data-spec.md`; where this file says "On PS5", "Reported", "Pending" or "PC only so far", it uses that spec's definitions.

Apple sources (read 2026-10-24): Designing for iPhone Duo, Preparing your app for iPhone Duo, ArrangementView, ReservedRegion, HIG Launching, Onboarding, Notifications, Managing notifications, Privacy, Sheets and Accessibility. The full citations are in the QA report: https://claude.ai/artifact/2Np2LsLqvGewDfR5UFsYEY

---

## 0. Poses and global layout

| Pose | Display / size class | Bars | Main layout |
|---|---|---|---|
| **Closed** (portrait) | outer, compact | system vertical rail, trailing | one column (NavigationStack) |
| **Closed landscape** | outer, compact | vertical rail | one column |
| **Open portrait** | inner, regular | system horizontal bars (top nav, bottom tabs) | one column, wider grid |
| **Open landscape** | inner, regular | vertical rail | NavigationSplitView: library sidebar + detail |
| **Book** (landscape, folded) | inner, divided vertically | vertical rail | left page / right page via ArrangementView split |
| **Tabletop** (portrait, folded) | inner, divided horizontally | **custom: every control on a trailing rail in the lower half** (Terry's rule, overriding the system's horizontal bars) | upper = stage (view only), lower = controls + content, via ArrangementView overlay |

- **G-1** Navigation: a `TabView` with three tabs: Library, Updates and Search (search role). Library pushes the game book onto a `NavigationStack`. In open landscape it is a `NavigationSplitView` (sidebar = library, detail = game book). Navigation containers sit outside every ArrangementView.
- **G-2** Leaving a game book is **Back** (chevron, accessibility label "Library") in every pose. **Close (X)** is used only for modal content: the Add game sheet, the video player and Settings.
- **G-3** Toolbar items have both a title and an SF Symbol. Back sits at the top of the vertical axis, then the pinned action, then the groups. Overflow uses the system menu.
- **G-4** Tabletop: **no tappable element has its frame above the top of the fold region.** This includes alerts the app draws, banners, pills, sheet headers and video posters. The stage view is `.allowsHitTesting(false)`. System alerts and the permission prompt are exempt because the system places them.
- **G-5** No tappable element intersects an active `.division` reserved region in any pose (`proxy.reservedRegions(kind: .division)`).
- **G-6** All content clears the outer camera's `.occlusion` region. Sheets use system presentation so this is automatic.
- **G-7** Hit targets are at least 44 × 44 pt. No text is smaller than 11 pt at default size. Contrast meets WCAG AA in dark mode, which is the default appearance.
- **G-8** Dynamic Type: all text uses text styles. Up to AX5, game names never truncate: they wrap, and rows stack the cover above the text at accessibility sizes. Nothing is clipped horizontally.
- **G-9** Reduce Motion: no parallax, zoom or animated key art. Transitions become cross-fades. Key-art video and animation do not autoplay when Reduce Motion is on or Video Autoplay is off.
- **G-10** VoiceOver: every control has a label. Covers are announced as "<Game> cover". Unread dots are announced as "Unread". Verification tags are read out ("Unconfirmed on PS5, from press reports", V-4).
- **G-11** The app is dark by default and supports light mode. The accent colour is used only for interactive elements and unread state.
- **G-12** No outer-cover content while open. No API lets an app draw on the outer display while the device is open (confirmed by the Xcode build, 2026-10-24). Nothing in the app may depend on a cover, badge or hint there. The brand's cover badge is a design reference only. Re-check if Apple adds an API.
- **G-13** Accent fills (buttons, badges, unread counts) draw text in accent.on #2A1600, never white. Tertiary text is #A39BAE (at least 4.5:1 on every ink surface).

## 1. Pose changes (continuity)

- **P-1** Opening, closing, folding or rotating keeps: the selected tab, the open game, the chapter, which releases are expanded, the scroll anchor (the same release header stays at the top of the viewport, within one row), search text and focus, the note draft, and an open sheet (shown in the new pose's placement).
- **P-2** A playing video keeps playing across every pose change, within 0.5 s of its position, without restarting. The same player instance moves.
- **P-3** No layout jump over 1 s. Controls move only as far as needed. Rail items keep their order in every pose.
- **P-4** Closing the device while a sheet is open keeps the sheet on the outer display, with its Close at the top of the vertical bar.
- **P-5** Unread state is never changed by a pose change.

## 2. Launch and first run

Decision: the native launch screen is a plain background colour matching the Library (no logo or text, per HIG Launching). The branded Playscribe splash plays **only on the first launch after install**. It is posture-aware ("Game | book" across the hinge in Book), lasts 0.8 s plus a 0.3 s fade, and under Reduce Motion it is a 0.3 s fade with no movement. Later launches go straight to the restored state.

- **L-1** Cold launch to an interactive first screen takes 1.0 s or less, excluding the first-run splash.
- **L-2** Later launches restore the last tab, game, chapter and scroll anchor (HIG Launching: restore previous state).
- **L-3** A launch from a notification never shows the splash, even on first run, and goes straight to the release (N-6).
- **L-4** No permission prompt, account prompt or tutorial at launch.

### First run = the empty Library

- **F-1** With an empty library, the Library tab shows the onboarding empty state:
  - the title "Add your PS5 games"
  - the line "Follow a game to get its PS5 patch notes in one place."
  - a search field focused only when tapped
  - "Popular on PS5", a list of 12 titles with cover, name and an Add button
  - the link "Add a game that isn't listed".
- **F-2** Filter chips and Sort are hidden until the library has 2 or more games. The library search field is hidden until it has 6 or more.
- **F-3** The empty-state glyph is a book, not a magnifying glass.
- **F-4** The Updates tab with an empty library says "Updates for your games will appear here" and has a button "Add a game" that switches to Library.
- **F-5** Adding the first game shows it in the library immediately, then shows the notification invitation card (N-1).
- **F-6** This state is reachable in debug builds via a "Reset to first run" item in Settings.

## 3. Library

- **B-1** *(Superseded by D-12: tiles are the default and rows are the List option.)* Closed: rows have a 44 pt cover, the name (up to 2 lines), a status pill, the latest **On PS5** release name with its date, and an unread count. Open flat: 112 pt tiles. Book: 100 pt tiles. Tabletop: 84 pt tiles. One fixed cover size per pose (Terry). When divided, prefer an even number of columns if the fixed size allows it.
- **B-2** *(Superseded by GR-1.)* A game with no On PS5 release shows its latest known PS5 version and date with "Watching for PS5 notes", never a bare "No PS5 notes yet".
- **B-3** Default sort is "Recently updated on PS5". The other sort is "Name". Filters are All, Owned, Wishlist and Watching, each with a count.
- **B-4** "Continue" tile: the game with the most recent unread On PS5 release, as the first item, with key art. Tapping it opens that game on its newest unread release. It is hidden when nothing is unread.
- **B-5** Tabletop: the upper half shows the Continue game's key art and title, view-only. Search, filters, sort and the grid are in the lower half. The Continue tile is the first grid item.
- **B-6** Book: the left page holds key art, title and Continue; the right page holds search, filters and the grid.
- **B-7** The ⋯ menu on a game has: Status (Owned / Wishlist / Watching), Notifications (All updates / Major only / Off) and Remove.
- **B-8** Remove takes effect immediately and shows the toast "Removed <Game>" with **Undo**, visible for 5 s. Undo restores status, notification level, bookmarks and notes.
- **B-9** A filter with no matches shows "No <filter> games" and a "Show all" button.

## 4. Add a game

- **A-1** "+" (pinned toolbar item) opens a system sheet. Its Close is a `cancellationAction`: top of the vertical bar on the outer display, sheet header elsewhere, lower half in tabletop. *(v1.4: rows and tiles select, and an "Add n" confirmation action adds them all, see GR-7.)*
- **A-2** The sheet contains:
  - a status segmented control (Owned, Wishlist, Watching; default Owned)
  - a search field
  - "Popular on PS5", which excludes games already in the library.
- **A-3** Search starts at 2 characters, debounced 250 ms, and matches the IGDB PS5 catalogue. There is one row per IGDB id: no duplicates, and the record with art wins. Games already added show "In library" (disabled) and are listed after the others.
- **A-4** No results: "No PS5 game matches '<query>'" plus "Add '<query>' yourself", which opens custom entry with the name prefilled.
- **A-5** Add closes the sheet, scrolls the library to the new game, highlights it for 1 s, and shows the toast "Added <Game> · Undo".
- **A-6** Custom game: a name (required) and platform (default PS5). It shows a placeholder cover with the title and "No PS5 notes yet".
- **A-7** Search failure (offline or server error): "Can't search right now" plus Retry. Popular titles come from the bundled catalogue and still show.
- **A-8** While the sheet is open, everything behind it is inert, and the rail "+" is hidden or disabled.
- **A-9** The newly added game's default notification level is **All updates** for Owned and **Major only** for Wishlist and Watching.

## 5. Read an update (game book)

- **R-1** Opening a game shows the Updates chapter. The newest **On PS5** release is expanded and scrolled to the top. Older releases are collapsed.
- **R-2** Release header: display name ("Update 1.1"), kind label (Day-one patch / Hotfix / Patch / Major update / Silent update), the PS5 live date, and the PS5 version string exactly as the console shows it ("01.004.000"), or nothing if unknown.
- **R-3** Facts *(v1.4: shown as one line under the key changes, see GR-3; this list is the expanded view)*:
  - **Status:** "Live on PS5", "Announced for PS5" or "Reported on PS5"
  - **PS5 version**
  - **Download:** size, with "Reported" if from the press
  - **Includes:** bundled PC releases, as links to them within the PC only group
  - **Video**
  - the line "Gamebook can't see what's installed on your console."
- **R-4** Notes are grouped by section. Items flagged `ps5ProOnly` carry a "PS5 Pro" tag. PC-only items inside a console release are hidden behind "Show PC-only changes (n)".
- **R-5** Spoiler items are blurred with the label "Spoiler · tap to show". A per-game toggle (eye symbol) reveals all of them.
- **R-6** A release becomes **read** when its expanded body has been at least 50% on screen for 1 s, or via "Mark all read". The app icon badge and the Library tab badge update at once.
- **R-7** Chapters (Updates, World, Companion, Gallery, My book; empty chapters are hidden). On compact width they show as a horizontally scrolling row with an edge fade, and the selected chip is scrolled into view. All chapters are reachable in every pose.
- **R-8** Game actions live in the toolbar only (no duplicate pills): Notifications (bell), Spoilers (eye), Status (tag), Mark all read (checkmark, shown only when unread exists), Bookmark the release (per release, inline).
- **R-9** Book: the left page holds key art and the contents of releases (tap to jump); the right page holds the reading pane.
- **R-10** Tabletop: the upper stage shows the release's key art and display name. The lower half holds chapters, release jump chips and reading. No release header straddles the fold.
- **R-11** Video: tapping the video row opens the player modal. Close is at the top of the rail, or in the lower half in tabletop. In tabletop, video is in the upper half and Play/Pause, scrubber, mute and Close are in the lower half from the start (ArrangementView overlay: controls primary, video secondary). Closing returns to the same scroll anchor. No autoplay with sound.
- **R-12** Video unavailable: the row shows "Video unavailable" plus "Watch on YouTube" (opens in Safari).

### PS5 verification states (from the data spec)

| State | Where it shows | Unread / badge | Push | UI |
|---|---|---|---|---|
| **On PS5** (live + official) | main release list, Updates tab | yes | yes, once | no tag; version shown |
| **Announced for PS5** (official) | main list, under "Coming to PS5" | no | no | "Announced" tag, expected date if official |
| **Reported on PS5** (press only) | main list, "Unconfirmed" group (V-4) | no | quiet alert, once (N-11) | "Unconfirmed" chip (V-4); version only if the press gave one |
| **Silent** (reported, no notes) | main list | no | quiet alert, once (N-11) | "Reported" + "Silent update" + "No official notes" |
| **Pending** | **nowhere** | no | no | none |
| **PC only so far** | collapsed group "PC only so far · n updates" at the end of the journal | never | never | "PC" tag; never in the Updates tab (footnote count only) |
| **Not coming to PS5** (official notPlanned) | inside the PC only group | never | never | "Not planned for PS5" |

- **V-1** Moving from Reported to On PS5 updates the item in place, removes the tag, makes it unread and pushes once, if notifications allow. Moving from On PS5 to anything else never happens in the UI; corrections edit facts silently.
- **V-2** A PC version number never appears as a PS5 version anywhere.
- **V-3** No source names, URLs or credits appear in the UI. Tags are the only provenance signal.
- **V-4 Unconfirmed is always labelled and visibly separate** (Terry, 2026-10-26: "make sure it's tagged/visually separate, i.e. 'Unconfirmed' or similar"). Every Reported or Silent release is shown to users as **Unconfirmed**. The internal state keeps its name. The treatment never borrows the confirmed look (ember, unread dot, "Update" badge).
  - **Chip:** "Unconfirmed", in tertiary text (#A39BAE) inside a 1 pt *dashed* outline, with no fill and no ember. Confirmed releases never have a dashed outline. VoiceOver reads "Unconfirmed on PS5, from press reports" (G-10 updated).
  - **Alert (N-11):** the title starts "Unconfirmed:", for example "Unconfirmed: Kingdom Come: Deliverance II Patch 1.6 on PS5". The body is "From press reports. We'll tell you when it's official."
    - It uses its own `threadIdentifier` ("unconfirmed"), so the system groups these apart from confirmed updates.
    - It has a separate notification category, so the long-press preview shows the chip.
    - On confirmation, the silent replacement takes the confirmed text, with no "Unconfirmed".
  - **Library tile and row:** no ember "Update" badge and no unread count. A small dashed "Unconfirmed" chip sits on the tile's lower-left corner, and the caption reads "Patch 1.6 · Unconfirmed". If a game has both, the confirmed badge wins and the chip is dropped, so there's only one mark per tile.
  - **Game book, Contents:** the release timeline shows an "Unconfirmed" subheader above the confirmed releases whenever any exist. Its rows use the dashed outline and chip, never the unread dot.
  - **Game book, Page:** an unconfirmed release opens with a full-width band under the header that reads "Unconfirmed · From press reports, not in official PS5 notes yet", with a dashed top and bottom rule. The facts line reads "Unconfirmed on PS5 · 7 GB (reported) · 25 Jun".
  - **Updates tab, search results, the Tabletop reader and the Open Margin** use the same chip.
  - **When a release is confirmed,** the chip, the band and the group membership disappear in place, and the release becomes unread with the normal ember treatment (V-1).
  - Acceptance:
    - Every Reported or Silent release shows "Unconfirmed" on every surface listed above, and no confirmed release shows a dashed outline.
    - A snapshot test of the tile, row, Page band and alert text.
    - VoiceOver reads "Unconfirmed".
    - Confirming removes the treatment without a second alert.

## 6. Notifications: invitation back

- **N-1** Permission is asked in context, never at launch. After the first game is added, a card at the top of the Library reads "Get a note when <Game> updates on PS5". It has one button, **Continue**, which opens the system prompt, and the card is swipe-dismissable. The card shows at most twice (two separate sessions) and never after a decision.
- **N-2** Tapping the bell before a decision skips the card and opens the system prompt directly. If permission is denied, the bell menu shows "Notifications are off for Gamebook" plus "Open Settings". The per-game choice is still stored.
- **N-3** A push is sent only when a release reaches On PS5 for a followed game whose level allows it. "Major only" covers `major` and `dayOne`. Hotfix and patch go out with interruption level `.passive`; major and dayOne with `.active`. Never Time Sensitive. There is one push per release, ever.
- **N-4** Content:
  - title = game name
  - body = "<Display name> is live on PS5: <first two key changes>." Sentence case, no app name, no emoji.
  - `threadIdentifier` = game id
  - `hiddenPreviewsBodyPlaceholder` = "New update".
- **N-5** If 3 or more games update within 10 minutes, they are summarised by the system thread grouping. No custom digest.
- **N-6** Tapping a notification (cold, warm, closed or open) opens the game book, Updates chapter, with that release expanded at the top, in whatever pose the device is in. Back goes to Library. In open landscape, the sidebar shows the game selected.
- **N-7** In the foreground, no banner is shown (`willPresent` returns `.badge` and `.list`). The release is inserted into the current list with a 0.3 s highlight. If the user is elsewhere, a pill "New on PS5: <Game> <Display name>" appears above the tab bar or rail. In tabletop it appears in the lower half. The pill stays until tapped or until that game is opened, and swiping dismisses it.
- **N-8** App icon badge = the number of unread On PS5 releases for games whose notifications are not Off. It updates on read, on remove and on a level change.
- **N-9** Deep link to a release that no longer exists: open the game book with the toast "That update is no longer available". Deep link to a game no longer in the library: open its game book read-only with an "Add to library" button.
- **N-10** Settings contains notification levels per game, plus a global "Pause all" toggle (required by HIG Managing notifications).
- **N-11 Quiet "Reported on PS5" alert** (decided 2026-10-25). When a release first becomes Reported (or Silent) for a followed game whose level allows it (same level rules as N-3), the app posts one local notification.
  - Text: "<Game>: Update <display name> reported on PS5". The body is the PS5 headline (GR-2) or "No official notes yet".
  - `interruptionLevel = .passive`, with no sound. Apple: the system "adds the notification to the notification list without lighting up the screen or playing a sound". No badge change (Reported never counts as unread).
  - The request identifier is the release id. Apple: "If you use the same identifier when scheduling a new notification, the system removes the previously scheduled notification with that identifier and replaces it with the new one".
  - On confirm (Reported to On PS5), the app re-adds a request with the same identifier, the On PS5 text and `.passive`. The entry updates in place without alerting, and the release becomes unread with the badge updated (V-1, N-8). This counts as N-3's "one push per release": no second alert. If no Reported alert was ever delivered for that release, N-3 applies as normal.
  - Never for Pending, PC only or Announced. At most one Reported alert per release.
  - Tapping it opens the release as N-6, showing its Reported tag.
  - Acceptance: after confirm, Notification Center holds exactly one entry for the release (`getDeliveredNotifications`). Its text is the On PS5 text. No sound and no screen wake happen on either post.

## 7. Updates tab

- **U-1** Updates is a reverse-chronological feed of On PS5, Announced and Reported releases for library games. Each row has cover, game, display name, tag and date. Unread rows are bold with a dot.
- **U-2** The footnote "<n> PC-only updates aren't listed because they're not confirmed on PS5" appears when n > 0.
- **U-3** Tapping a row opens the game book on that release (same as N-6).

## 8. Errors and offline

- **E-1** Offline: all cached content works. The Library shows a quiet line under the title, "Offline · updated <relative time>". Pull to refresh is disabled with that message. There is no alert.
- **E-2** Refresh failure: the same line, "Couldn't refresh · Retry". It is never a modal alert, and never a notification.
- **E-3** A game's notes fail to load (no cache): inline "Can't load updates" plus Retry, in the reading pane.
- **E-4** Image failure: a placeholder cover with the game title in the display font. Layout never shifts.
- **E-5** Errors that block a user action (for example, adding a game fails) use a system alert with one action.
- **E-6** Stale data: if a release was checked more than 24 h ago, its facts show "Checked <date>" in the secondary text style.

## 9. Open pose ("the Spread") and pose transitions — SUPERSEDED by section 11 (v2.0). Kept for history: O-1..O-6 and T-6..T-9 no longer apply. TT-0, TT-2, TT-4, VB-1..VB-3, T-2..T-5 and T-10 still apply.

Decided 2026-10-25 under Terry's brief: Book pose = the current Open left side plus the Book right side, and the fully Open pose designed fresh. Visual: https://claude.ai/artifact/QEhYMVpHujvaGtMGU9ehZ1 (copy: qa/design/the-spread.html).

Apple basis (fetched 2026-10-25, unchanged from baseline): show an extra level of hierarchy on the inner display; a header may span the full width while scrolling content stays inset; split views adapt their column widths to the fold; favour small adjustments over rearrangement when folding; keep navigation outside arrangement views; `backgroundExtensionEffect()` extends detail content under the sidebar. Everything else in this section is a design decision.

**Five pieces, in every pose:** Art (the game's key art), Library, Page (the open release), Margin (PS5 facts: status, PS5 version, download size and tag, video), Controls (system toolbar and tab bar).

| Pose | Art | Library | Page | Margin | Controls |
|---|---|---|---|---|---|
| Closed | 16:9 header | behind Back (stack) | full column | card under the release | trailing rail |
| Book | left page, top (hero frame) | left page, below the art | right page | card under the release, right page | trailing rail |
| Open landscape | edge to edge, top ~44% of height | leading column, ~28% | centre column, raised over the art's lower edge by ~15% of the art's height | trailing column, ~25%, no card fill | trailing rail |
| Open portrait | full width, top ~40% | cover shelf (one row) under the art | lower leading ~60% | lower trailing ~35%, no card fill | system top and bottom bars |
| Tabletop | upper half: the Reader (one section, large type, over blurred art) or the playing video; display only | flat half: covers row on the Library screen; via the Library tab elsewhere | upper half, paged (see TT-2) | section 6 of the outline | flat half: outline, Previous/Next, chapter switcher, trailing rail |

- **O-1** Open never shows an empty detail. With no game chosen it opens the Continue game, else the most recently updated game.
- **O-2** Art in Open landscape is `StageArt().backgroundExtensionEffect()` in the detail column, so it runs under the Library. It shows the game title (Literata title, at most 2 lines) bottom-leading, inside the Library's width, never under the Page.
- **O-3** The Page is a card (ink 800, vellum hairline) raised over the art. Reading measure stays at 55 to 75 characters. Wider space goes to the Margin, never to a longer line.
- **O-4** The Margin is the same view as the closed and Book facts card (`matchedGeometryEffect(id: "facts.<releaseID>")`). It is shown as a column only when the detail is at least 560 pt wide and no `.division` reserved region exists; otherwise it is the inline card.
- **O-5** The Library in Open landscape is the sidebar of the root `NavigationSplitView`, with the selected game highlighted and unread dots visible. In Open portrait it is a single-row cover shelf (58 × 82 pt covers, selected one ringed in ember, 44 pt+ targets).
- **O-6** Everything tappable in Open meets G-7. Nothing sits under the system rail or bars.

**Tabletop and video redesign (2026-10-25, after Terry's review).** Visual: https://claude.ai/artifact/6kthKpcPy4EvLB5iZ9jEoV (copy: qa/design/tabletop-video.html). Apple basis (fetched 2026-10-25): a partially open overlay arrangement puts the primary view at the trailing or bottom side of the fold and the secondary at the leading or top side; "Locate controls near the content they affect"; "Use the system video player…", and a custom player must reference the system player's behaviour and interface.
- **TT-0** Layout keys on the active `.division` reserved region, not on a pose name: a division wider than tall means tabletop; taller than wide means book. No view's frame may intersect an active division. Add a UI test that fails if any visible view crosses it. (Terry's screenshot showed the Spread's page card across the fold, so the division was being ignored.) TT-0 applies to settled layouts. While a pose transition runs (at most 0.45 s), a moving piece may cross the fold, but it must not take hits until it settles, and once settled nothing may cross.
- **TT-1** Tabletop uses `ArrangementView(.overlay)`. The secondary (top) is the stage, with `.allowsHitTesting(false)`. The primary (bottom) holds every control.
- **TT-2** Tabletop reading: the standing half shows one section of the release at a time (Literata title 32 pt, body 19 pt, max 34 characters per line) over the game's art, blurred to 35% brightness, with page dots and "n of N". The flat half shows the chapter switcher, the release outline (one 44 pt row per section, the current one highlighted), large Previous and Next buttons (52 pt) and the trailing rail. Sections are: Overview, each key change, Fixes, then PS5 facts and video. Nothing scrolls on the standing half.
- **TT-3** Tabletop Library: the standing half shows the Continue art and title (display only). The flat half shows one horizontal row of covers, then the filters.
- **TT-4** Tabletop video: the standing half shows the video at its own aspect ratio, fitted to the width, with captions on the video. The flat half shows the title, scrubber with times, then captions, back 10 s, play/pause (64 pt), forward 10 s and volume, in the system player's order. Below that is a "watch along" list of the video's timestamps (tap to seek; the release's key changes when there are no timestamps). Close is at the top of the rail. This is the only custom transport in the app.
- **VB-1** Video in every pose except Tabletop uses the system player (`AVPlayerViewController` / `VideoPlayer`) with its own controls on the video. Remove the custom transport row.
- **VB-2** Book video: the left page shows the video top-aligned at full page width, with the title, game and duration under it. The right page shows "Watch along" (as TT-4) and a link to the full notes. Close is at the top of the rail. Controls never sit on the other page from the video.
- **VB-3** Closed and Open: the system player is full display, with Close at the top of the rail (T-10 unchanged).

**Transitions.** Pose changes are layout changes, not navigations: nothing pushes, pops or reloads.
- **T-1** Same pieces, same identity: Art, Page and Margin keep their view identity across poses (matched geometry), so they move and resize instead of fading out and in.
- **T-2** One motion: `.spring(duration: 0.45, bounce: 0.12)`, staggered Art 0 ms, Page 40 ms, Library 80 ms, Margin 120 ms. It is interruptible: a pose change during an animation retargets from the current frame.
- **T-3** Text never scales during a transition. It reflows at its final size and the container animates around it.
- **T-4** Reduce Motion: a 0.2 s cross-fade, no movement.
- **T-5** The reading anchor (P-1) is restored in the same frame the layout settles. The release header that was at the top stays at the top.
- **T-6** Closed to Open: the art header grows into the full-width band, the Page lands in the centre column at the same scroll anchor, the Library slides in from leading, and the Margin slides out from under the Page. If the closed display showed the Library list, the list becomes the sidebar at the same scroll position and the Page shows the O-1 game.
- **T-7** Open to Closed: what had focus last wins. If the Page or Margin had focus, the closed display shows that game book; if the Library had focus, it shows the Library.
- **T-8** Open to Book: the gutter opens on the fold. The art contracts into the left page above the Library, and the Margin tucks under the release as a card. The split line sits on the fold (system split view behaviour).
- **T-9** Open landscape to Open portrait or Tabletop (rotation): the art takes the top band or upper half; the Library becomes the shelf (portrait) or steps back to the Library tab (tabletop); controls move to the system position for that pose.
- **T-10** A playing video keeps playing through every transition (P-2). The player the user opened stays the player in every pose: full display in Closed and Open, the upper-half stage in Tabletop. It never shrinks into the Margin. The Margin shows only the video's thumbnail and duration, and tapping it opens the player.

## 10. Gamer-review fixes (v1.4)

Source: the gamer review of 2026-10-25, ranked. Apple basis, fetched 2026-10-25:
- Designing for iPhone Duo: "Labels that include text stay in a horizontal bar, so prefer a symbol wherever one works", and "Provide both a title and a symbol for each toolbar item".
- Toolbars: "Make sure the meaning of each control is clear. Don't make people guess".
- Searching: "Clearly display the current scope of a search", and "Provide suggestions".
- SwiftUI: `accessibilityShowsLargeContentViewer()`, `searchScopes(_:scopes:)` and `searchSuggestions(_:)`.

**Keep unchanged:** tabletop Watch along, spoiler-hidden quest notes, the tabletop step reader (TT-2), the N-7 pill, and Undo (B-8, A-5).

- **GR-1 Never an empty game.** A game with no notes still shows a per-game timeline in the Updates chapter.
  - Each known PS5 release is a row: the PS5 version (never a PC version, V-2), the PS5 date, the reported size, and its tag.
  - Under the rows is the line "Watching for PS5 notes · checked <relative time>".
  - If no PS5 release is known at all, show the PS5 launch date ("Out on PS5 since 4 Feb 2025", or "Out 19 Nov" for a future game) plus the watching line.
  - Library rows (B-2) show the latest known PS5 version and date with "No notes", not "No PS5 notes yet".
  - Acceptance: no game in the demo set renders an empty Updates chapter.
- **GR-2 PS5 pages show PS5 content only.** On a console page, these use only items that apply to PS5:
  - the headline, the summary, the key changes, push text (N-4), and Help / known issues.
  - PC-only items, such as PC hardware, upscalers and frame generation, mouse and keyboard, Steam or Steam Deck features, and GPU vendor crashes, appear only behind R-4's "Show PC-only changes (n)".
  - Items whose platform is unknown can be listed, but they are never the headline or the push line.
  - If the source headline is PC-only, the headline becomes the top PS5 key change.
  - Acceptance: a test fails if FrameGen, DLSS, FSR, XeSS, AMD, NVIDIA, Intel Arc, Steam, Steam Deck, mouse, keyboard or ultrawide appears on a PS5 page outside the PC-only group. Native fixtures must pass the same test. The data rules belong to the backend thread.
- **GR-3 Reading order: story first.**
  - A release opens with the headline (display font), then the summary (at most 3 lines), then the key changes, then the full notes.
  - Facts collapse to one line under the key changes: "Live on PS5 · 13 GB · 22 Oct". Tapping it expands the full R-3 list in place.
  - Tags are chips (PS5 Pro, Reported, Spoiler).
  - Remove the inline provenance legends and explainer paragraphs. Tags stay the only provenance signal (V-3).
  - The "can't see your console" line moves to the expanded facts.
  - Open keeps its Margin (O-4), with the same one-line summary at its top.
- **GR-4 Search inside notes ("did they fix X?").**
  - The Search tab and an in-book search field use `.searchable`, with `searchScopes` "This game" and "All my games". The in-book field defaults to "This game", and the placeholder names the scope: "Search Dawnwalker's notes".
  - Matching starts at 2 characters, is case- and accent-insensitive, and covers PS5 items' text and section names.
  - Results are grouped by release, newest first. Each shows the matching line with the term in bold, the release name, the date and the tag.
  - Tapping a result opens the release with that item highlighted for 1 s at the reading anchor.
  - PC-only matches are listed last under "PC only".
  - No match: "No mention of '<q>' in <Game>'s PS5 notes", plus "Search all my games".
  - `searchSuggestions` offers recent searches. Search text survives pose changes (P-1).
- **GR-5 Release status in Add is honest.** The row's date line follows IGDB's date precision:
  - "Released 2025" for a past date.
  - "Out 19 Nov" for a future date this year, or "Out 19 Nov 2027" for a later year.
  - "Coming 2027" when only the year is known, and "Release date TBA" when nothing is known.
  - A future date never says "Released". A future game added from Add defaults to Wishlist and shows its "Out …" line in the Library.
- **GR-6 Every rail item says what it does.** The Duo rail stays symbol-only (system rule), so:
  - (a) Every item is a `Label` with a title, and every item has `accessibilityShowsLargeContentViewer()`, so a long press shows its name.
  - (b) Use self-explanatory symbols:
    - Notifications: `bell`, or `bell.slash` when off.
    - Spoilers: `eye.slash` when hidden, `eye` when shown.
    - Status: a symbol for the current status, `gamecontroller` (Owned), `star` (Wishlist) or `binoculars` (Watching), instead of `tag`.
    - Mark all read: `envelope.open`, instead of a bare checkmark.
    - Updates tab: `newspaper`, instead of `clock`.
  - (c) Each one-tap item confirms by name: "Spoilers shown", or "3 updates marked read · Undo". Menus (bell, status) show their title as the menu header.
  - (d) In open portrait's horizontal bars, items show title and symbol where the system allows text.
  - Acceptance: the five symbols, a title on every item, and the confirmations.
- **GR-7 Add several at once.**
  - In the Add sheet, tapping a Popular tile or a search row toggles selection (a checkmark badge, plus a selected trait for VoiceOver). Selection persists while the query changes.
  - A `confirmationAction` "Add n" appears when n ≥ 1, after Close at the top of the rail (A-1).
  - Adding closes the sheet and shows "Added 3 games · Undo". Undo removes all of them. The library highlights all the new games.
  - Single add is the same flow with n = 1. Games already in the library stay disabled (A-3).

## 11. One layout, every pose (v2.0)

**Visual:** https://claude.ai/artifact/79xqmm4cgSB4hxVzWcKNVz (copy: qa/design/playscribe-one-layout.html).

**Why.** Terry tested the native build on 2026-10-25 and rejected it:
1. Tabletop (screenshot) showed a 1:3 sidebar, + at the top right of the sidebar, a stray pill, and the scrolling update list in the middle, away from reach.
2. Closing lost the open game, and reopening jumped to the top game.
3. The left side in Book did no work (art over a game list), and it showed two "Library" titles.
4. The rail icons seemed to do nothing.

He's right. We gave every pose its own layout (the Spread, a sidebar, a stage), which Apple tells us not to do.

**Apple basis (fetched 2026-10-25):**
- "Don't reinvent your app when it resizes; allow the existing layout to expand."
- "Avoid extreme layout changes as people fold the device."
- "Keep functionality and the state of elements the same between displays."
- A split arrangement puts the primary view "in the leading position" in landscape and "in the top position" in portrait, and when the device is closed in landscape it "only shows the primary view".
- "Avoid placing an arrangement view inside a navigation split view."
- In a split view, "the system shows bars horizontally for the sidebar". That's why native drew "Library" and "+" in a bar at the top of the sidebar.

**The model.** A game has two parts:
- the **Page**, which is the release you're reading;
- the **Contents**, which is the game's chapters, search, releases and actions.

The game book is a single `ArrangementView(.split)`. A split puts its primary leading (side by side) or on top (stacked). So in side-by-side layouts the Contents are primary (leading, like Mail's list), unless the user swaps sides (D-10). In stacked layouts the Page is primary (on top, the standing half in Tabletop). The views keep stable identity whichever slot they fill. *(v2.1, after Terry's question: the reading side defaults to the right. Apple's own split apps (Mail, Notes) put the list leading and the reading pane trailing, and the system puts the reading pane's bars on the vertical rail beside it. The Contents' rows sit under the left thumb in a two-handed grip.)*

| Pose | Page | Contents | Rail / bars |
|---|---|---|---|
| Closed (outer, landscape) | full display; it includes its own release list inline, so it behaves as today's closed game book | hidden (system: primary only) | vertical rail |
| Open landscape (flat) | trailing half, beside the rail (default; D-10 swaps) | leading half | vertical rail |
| Book (vertical fold) | right page (default; D-10 swaps) | left page | vertical rail |
| Open portrait (flat) | top half | bottom half | horizontal bars |
| Tabletop (horizontal fold) | standing half, display only, paged (TT-2) | flat half: everything you touch | trailing rail on the flat half |

Open becomes Book, and Open portrait becomes Tabletop, with nothing moving except the fold. The halves stay 1:1 on the inner display, so folding doesn't resize anything.

- **D-1 One navigation, outside the layout.**
  - The structure is `TabView` (Library, Updates, Search), then a `NavigationStack`: Library, then the game book.
  - No `NavigationSplitView` and no Library sidebar in any pose. This removes the sidebar header, its "+" and the duplicate "Library" title.
  - The Library is reached with Back (top of the rail), which is the same in every pose (G-2).
- **D-2 State never changes with pose.**
  - These live in one scene model (`@SceneStorage` plus the navigation path) shared by both displays: the open game, the selected release, the chapter, the Page scroll anchor, search text and a playing video.
  - Closing on Kingdom Come shows Kingdom Come on the outer display, at the same release and anchor. Opening again shows Kingdom Come.
  - If you were on the Library, you stay on the Library. Nothing ever auto-selects the first or the Continue game (O-1 is removed).
  - Acceptance: a UI test runs Closed → Book → Closed → Open → Tabletop → Closed with Kingdom Come open, and asserts the same game, release and anchor at every step. It runs again from the Library.
- **D-3 The Page.**
  - It holds the art band (`backgroundExtensionEffect()` under the rail), then headline, summary, key changes, the facts line and the notes (GR-3). The reading measure is 55 to 75 characters.
  - On the inner display it shows only the selected release.
  - In Closed it shows the stacked game book (newest expanded, R-1), because the Contents are hidden.
  - Video plays in the Page's place (VB-2 left page; TT-4 standing half). Watch along takes the Contents' place.
- **D-4 The Contents.** From top to bottom:
  - the game title and status;
  - the chapter chips;
  - search in notes (GR-4);
  - "Mark n read" when something is unread;
  - the release timeline (one 44 pt row per release with date, tag and unread dot; the selected row highlighted; GR-1 rows for releases with no notes);
  - in Tabletop only, the section outline and Previous/Next (TT-2).
  - Tapping a release changes the Page in place, with no navigation push. By default the Contents sit leading, under the left thumb, and the Page sits beside the rail that holds its actions (D-10 can swap them).
- **D-5 Library: one grid, every pose.** There is a single `LazyVGrid` with one large title, "Library", shown once. The Continue tile is the first and largest (B-4).
  - Closed: rows (B-1).
  - Open: 112 pt tiles.
  - Book: tiles in an even number of columns, so the fold falls between columns (Apple: "prefer an even number of columns").
  - Open portrait: a grid under the title.
  - Tabletop: the standing half shows the Continue art and title, display only. The grid and filters go on the flat half.
  - Add (+) is the pinned toolbar item on the rail, never in a sidebar header (A-1).
- **D-6 The rail only holds actions that visibly do something.** In a game, from the top:
  - Back.
  - Notifications (a bell menu headed "Notify me about <Game>").
  - Status (a menu headed "<Game> is in your library as…", showing the current status symbol, GR-6).

  That's all. Spoilers move inline to the Page's "Story spoilers hidden · Show" line, shown only when the release has spoilers. Mark all read moves to the Contents (D-4), next to the unread rows it changes. Each action shows its result where you're looking (the Page or the Contents), and the toast confirms by name (GR-6c).
- **D-7 Nothing app-drawn is empty or decorative.**
  - No pill, card or bar renders without content. The N-7 pill exists only while it has a game to name.
  - Nothing is designed around the system home indicator.
  - Acceptance: a test fails if any app-drawn element in the view hierarchy (outside system chrome) has no text or image.
- **D-8 Transitions.** The pieces are the Page, the Contents and the rail. They keep their identity (T-1) and move with the T-2 spring.
  - Closed → open: the Page widens into its half and the Contents slide in beside it, at the same anchor (T-5).
  - Open → closed: the Contents slide away and the Page fills the outer display.
  - Folding or unfolding: the halves stay put, and only the fold appears or disappears.
  - Rotating (Open landscape to portrait): the Contents move from beside the Page to under it, the system split behaviour.
  - Reduce Motion: cross-fade (T-4).
- **D-10 Swap sides.**
  - In side-by-side layouts (Open landscape, Book), a "Swap sides" control sits at the top corner of the Contents panel nearest the Page. It moves the Page and the Contents to opposite halves.
  - The choice applies to every game and persists (D-13) until it's swapped back.
  - It's hidden in stacked layouts (Open portrait, Tabletop), where the Page is always on top, and in Closed.
  - The glyph is Terry's choice, option A (2026-10-26): the book with the reading page filled and no arrows. Files: brand/ios/symbols/swap-sides.left.svg and swap-sides.right.svg, plus the button variants. The filled page follows the current reading side, so the icon shows where you read now. Use it as a template image with Preserve Vector Data until an SF Symbol template is made on the Mac. Accessibility: the label is "Swap sides" and the value is "Reading on left" or "Reading on right" (`accessibilityValue`), updated on every swap.
  - The swap animates with the T-2 spring, and both pieces keep their scroll positions.
  - Acceptance: swap, change game, close and reopen, relaunch: the side holds every time.
- **D-11 Sharing the screen with another app (Split View).** Apple, fetched 2026-10-25:
  - "When two apps share the inner display with Split View multitasking, each one places controls along its outer edge, so the left app has controls on the left."
  - "Use safe areas to make sure controls don't cover your content, including controls on the opposite edge."
  - From the iPhone Duo tech talk: "All apps participate in multitasking", in side-by-side and stacked layouts, decided with "size classes and scene geometry".

  Rules:
  - Layout keys on the scene's size class and bounds, never on the device pose. A compact-width scene shows the one-piece layout (Library, then the game book with its releases inline, the same as Closed). A regular-width scene shows Page plus Contents. This isn't the closed pose: the rail sits on whichever edge the system chooses (the outer edge), and content uses the safe area on both sides.
  - Entering, leaving or resizing Split View never resets state (D-2). The same game, release, anchor and playing video carry over.
  - A fold inside our scene still applies TT-0. If the fold falls between the two apps, there's no division in our scene and nothing changes.
  - Video keeps the system player, with Picture in Picture available, so a user can keep watching while using the other app.
  - Toasts and the N-7 pill anchor to our scene, away from the rail edge (`toolbarVerticalEdge`).
  - Acceptance: screenshots with Playscribe on the left and on the right of another app, both open flat and in Book, plus a stacked layout with video if the simulator offers one. State holds across enter and exit.
- **D-12 Library: PS5-style tiles by default.** This mirrors the PS5 Game Library's square game tiles in a grid, with Sort and Filter beside them.
  - The default view is **Tiles**: uniform square tiles with 12 pt corners and the game name under each (up to 2 lines, G-8). Each tile carries an unread count badge and a small "Update" mark when a new On PS5 release is unread, which echoes the PS5's update badge.
  - Art, in order (backend PR #7, 2026-10-25; PS Store art is off limits):
    1. `squareCover` (`s`).
    2. Landscape key art (`a`), cropped to a square. Centre the crop on the image's salient region (Vision's attention-based saliency request), not the plain centre, so faces and figures aren't cut.
    3. The portrait cover fitted inside the square over a blurred fill of itself.
  - Never crop a cover's logo. The name under the tile carries the title, so the art doesn't have to.
  - Fixed tile size per pose, and the column count fills the width: Closed 88 pt (3 columns), Open 100 pt, Book 100 pt with an even column count, Open portrait 108 pt, Tabletop 84 pt on the flat half.
  - Continue: in Closed and Open portrait, the brand v2 "NEW CHAPTER" hero card leads the Library when something is unread (accepted 2026-10-26). In side-by-side layouts and on Tabletop's flat half, it's the first tile, double width (2×1) with key art. Tabletop's standing half shows the hero art, display only.
  - The second option is **List**: today's rows (old B-1).
  - A "View" menu sits on the Library's rail under "+" (symbol `square.grid.2x2` or `list.bullet`, matching the current view). It holds View (Tiles / List), Sort (Recently updated on PS5 / Name) and Filter (All / Owned / Wishlist / Watching). The filter chips stay as a shortcut.
  - Acceptance: a first launch shows Tiles in every pose. Switching to List persists (D-13).
- **D-13 Every display choice persists.** Each one is stored with `@AppStorage` (or the SwiftData settings model), survives relaunch, pose changes and updates, and is the same on both displays:
  - Library view, sort and filter (D-12);
  - reading side (D-10);
  - spoilers shown, per game (R-5);
  - notes-search scope (GR-4);
  - captions on or off for video;
  - the chapter last opened, per game;
  - expanded or collapsed facts (GR-3);
  - notification levels (N-10).

  Nothing resets on a new game, a pose change or a cold launch. Only "Reset to first run" (F-6) clears them.
  - Acceptance: change each choice, force-quit, relaunch: all of them hold. Then do the same across Closed and Open.
- **D-9 Evidence needed for native sign-off** (all from the native build, not the prototype):
  - screenshots of the Library and the game book in all five poses;
  - the D-2 test passing, plus a screen recording of Terry's exact path (Closed, Kingdom Come, Book, Closed, Open);
  - the fold-cross test (TT-0) and the D-7 test passing;
  - the Tabletop poses and Open portrait set by hand;
  - VoiceOver and AX5 on the game book.
  - D-10 swap, D-11 Split View screens, D-12 Tiles in all poses, and the D-13 relaunch test.

## 12. QA method

QA re-runs these as a checklist on each build. It uses simulator or Device Hub screenshots for: Library, Add game, game book, video and a notification arrival, each in Closed, Open portrait, Open landscape, Book and Tabletop. It adds an Accessibility Inspector audit and AX5 Dynamic Type screenshots of Library and game book. G-4 and G-5 are measured from frames, not judged by eye. Builds should expose a debug overlay that outlines tappable frames and reserved regions.
