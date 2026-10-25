# Playscribe (formerly Gamebook) UX flows and acceptance criteria (v1.2, 2026-10-25: section 9 Open pose and transitions added; v1.1 added G-12, G-13)

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
- **G-10** VoiceOver: every control has a label. Covers are announced as "<Game> cover". Unread dots are announced as "Unread". Verification tags are read out ("Reported on PS5").
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

- **B-1** Closed: rows have a 44 pt cover, the name (up to 2 lines), a status pill, the latest **On PS5** release name with its date, and an unread count. Open flat: 112 pt tiles. Book: 100 pt tiles. Tabletop: 84 pt tiles. One fixed cover size per pose (Terry). When divided, prefer an even number of columns if the fixed size allows it.
- **B-2** A game with no On PS5 release shows "No PS5 notes yet" in place of the version.
- **B-3** Default sort is "Recently updated on PS5". The other sort is "Name". Filters are All, Owned, Wishlist and Watching, each with a count.
- **B-4** "Continue" tile: the game with the most recent unread On PS5 release, as the first item, with key art. Tapping it opens that game on its newest unread release. It is hidden when nothing is unread.
- **B-5** Tabletop: the upper half shows the Continue game's key art and title, view-only. Search, filters, sort and the grid are in the lower half. The Continue tile is the first grid item.
- **B-6** Book: the left page holds key art, title and Continue; the right page holds search, filters and the grid.
- **B-7** The ⋯ menu on a game has: Status (Owned / Wishlist / Watching), Notifications (All updates / Major only / Off) and Remove.
- **B-8** Remove takes effect immediately and shows the toast "Removed <Game>" with **Undo**, visible for 5 s. Undo restores status, notification level, bookmarks and notes.
- **B-9** A filter with no matches shows "No <filter> games" and a "Show all" button.

## 4. Add a game

- **A-1** "+" (pinned toolbar item) opens a system sheet. Its Close is a `cancellationAction`: top of the vertical bar on the outer display, sheet header elsewhere, lower half in tabletop. There is no Done button, because adding is per row.
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
- **R-3** Facts:
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
| **Reported on PS5** (press only) | main list | no | no | "Reported" tag; version only if the press gave one |
| **Silent** (reported, no notes) | main list | no | no | "Reported" + "Silent update" + "No official notes" |
| **Pending** | **nowhere** | no | no | none |
| **PC only so far** | collapsed group "PC only so far · n updates" at the end of the journal | never | never | "PC" tag; never in the Updates tab (footnote count only) |
| **Not coming to PS5** (official notPlanned) | inside the PC only group | never | never | "Not planned for PS5" |

- **V-1** Moving from Reported to On PS5 updates the item in place, removes the tag, makes it unread and pushes once, if notifications allow. Moving from On PS5 to anything else never happens in the UI; corrections edit facts silently.
- **V-2** A PC version number never appears as a PS5 version anywhere.
- **V-3** No source names, URLs or credits appear in the UI. Tags are the only provenance signal.

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

## 9. Open pose ("the Spread") and pose transitions

Decided 2026-10-25 under Terry's brief: Book pose = the current Open left side plus the Book right side, and the fully Open pose designed fresh. Visual: https://claude.ai/artifact/QEhYMVpHujvaGtMGU9ehZ1 (copy: qa/design/the-spread.html).

Apple basis (fetched 2026-10-25, unchanged from baseline): show an extra level of hierarchy on the inner display; a header may span the full width while scrolling content stays inset; split views adapt their column widths to the fold; favour small adjustments over rearrangement when folding; keep navigation outside arrangement views; `backgroundExtensionEffect()` extends detail content under the sidebar. Everything else in this section is a design decision.

**Five pieces, in every pose:** Art (the game's key art), Library, Page (the open release), Margin (PS5 facts: status, PS5 version, download size and tag, video), Controls (system toolbar and tab bar).

| Pose | Art | Library | Page | Margin | Controls |
|---|---|---|---|---|---|
| Closed | 16:9 header | behind Back (stack) | full column | card under the release | trailing rail |
| Book | left page, top (hero frame) | left page, below the art | right page | card under the release, right page | trailing rail |
| Open landscape | edge to edge, top ~44% of height | leading column, ~28% | centre column, raised over the art's lower edge by ~15% of the art's height | trailing column, ~25%, no card fill | trailing rail |
| Open portrait | full width, top ~40% | cover shelf (one row) under the art | lower leading ~60% | lower trailing ~35%, no card fill | system top and bottom bars |
| Tabletop | entire upper half, display only (video plays here) | via the Library tab | lower half | card under the release | trailing rail, lower half |

- **O-1** Open never shows an empty detail. With no game chosen it opens the Continue game, else the most recently updated game.
- **O-2** Art in Open landscape is `StageArt().backgroundExtensionEffect()` in the detail column, so it runs under the Library. It shows the game title (Literata title, at most 2 lines) bottom-leading, inside the Library's width, never under the Page.
- **O-3** The Page is a card (ink 800, vellum hairline) raised over the art. Reading measure stays at 55 to 75 characters. Wider space goes to the Margin, never to a longer line.
- **O-4** The Margin is the same view as the closed and Book facts card (`matchedGeometryEffect(id: "facts.<releaseID>")`). It is shown as a column only when the detail is at least 560 pt wide and no `.division` reserved region exists; otherwise it is the inline card.
- **O-5** The Library in Open landscape is the sidebar of the root `NavigationSplitView`, with the selected game highlighted and unread dots visible. In Open portrait it is a single-row cover shelf (58 × 82 pt covers, selected one ringed in ember, 44 pt+ targets).
- **O-6** Everything tappable in Open meets G-7. Nothing sits under the system rail or bars.

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
- **T-10** A playing video keeps playing through every transition (P-2). In Tabletop it moves into the upper-half stage; in Open it stays in the Margin.

## 10. QA method

QA re-runs these as a checklist on each build. It uses simulator or Device Hub screenshots for: Library, Add game, game book, video and a notification arrival, each in Closed, Open portrait, Open landscape, Book and Tabletop. It adds an Accessibility Inspector audit and AX5 Dynamic Type screenshots of Library and game book. G-4 and G-5 are measured from frames, not judged by eye. Builds should expose a debug overlay that outlines tappable frames and reserved regions.
