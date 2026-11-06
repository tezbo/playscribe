# Changelog

Playscribe follows semantic versioning. Each `## x.y.z` section becomes that build's "What to Test" in TestFlight,
so write it for testers. Release steps are in docs/release.md.

## 0.5.2 (candidate, not released)

- Playscribe can now tell you about a new PS5 update even when the app is closed. Allow notifications when asked. Quiet hours in Settings also apply to these alerts.
- Home Screen widget redesigned: small, medium and large now lead with game art, with the version and how long ago the update landed.
- Reflection mode is on by default for Tabletop video, and Settings has a switch for it.
- The PlayStation Plus card stays on the left page in the open book, and Settings has a switch to hide it.
- Adding a game no longer floods your unread count: updates older than 72 hours count as read.
- Settings has bigger toggle rows, a footer under Notify me about, and a 44 pt Close button in Tabletop.
- The "New on PS5" pill wraps onto two lines at the largest text sizes, and sits a little higher in Tabletop.
- Press and hold a game in your Library, Upcoming or Search to change its status or remove it. A wishlist game has a yellow circle.

Check on the Duo:

- Allow notifications, then wait for the next PS5 update to one of your games: an alert should arrive with the app closed.
- Add a game that has a long history: your unread count should not jump.
- Press and hold a game tile: the menu offers Owned, Wishlist, Watching and Remove.
- Turn the text size up to the largest setting: the pill should wrap to two lines and nothing should sit under it.

## 0.5.1

- Tabletop: the text on the stage sits on one calm panel and stops at four lines, with a Full text row in the lower half when there is more to read.
- Tabletop and Closed share the same rail, with a clear selected and pressed state on every button.
- Closed landscape has a slimmer art band, so more of the update shows.
- Open portrait: a page now fades out cleanly at the bottom edge instead of cutting a line in half.
- Spoiler warnings are clearer, and their hidden counts leave out PC-only lines on a PS5 page.
- The add sheet and a few counts and dates are tidied up.
- Settings has Autoplay videos, off by default.

Check on the Duo:

- Tabletop: open a long update. The text should stay in the lower part of the stage, and Full text should open the rest.
- Closed, turned to landscape: the art band should be slim and nothing should be cut off.
- Open portrait: scroll a long update; the last line at the bottom should fade, not cut.

## 0.5.0

- Your Library opens on Latest updates: swipe through the newest updates for your games, newest first, unread first. Playing and Upcoming sit at the top of the Library.
- A catch-up card tells you what changed since you last looked: new, fixed and rebalanced, with the headline changes.
- Every update is sorted into what's new, what's fixed and balance changes, and shows its reading time. Search now looks across every game and every patch note.
- Known issues: follow an issue and Playscribe tells you when an update fixes it.
- News: official posts from each game's studio, on the game page and as a strip on your Library.
- Upcoming: a watchlist of games that aren't out yet, with release-day alerts. Tap a game to watch it.
- You might also like: similar PS5 games on each game page, one tap to add or watch.
- Share any update as a picture card.
- In the open book, a new update turns in from the spine (a gentle fade if Reduce Motion is on).
- Home Screen widget: the latest updates in small, medium and large.
- Add your games by typing, speaking, a photo or the camera. Playscribe asks before using the microphone or camera, and always offers Type it.
- A first-run welcome walks you through adding your games; Skip for now takes you to your Library.
- Alerts say what changed, not just that something did. Quiet hours (Settings) deliver the app's own alerts silently overnight, and a tap on a verification tag explains it.
- Settings has its own cog. Search has a Back button. A game with no pictures says so and points elsewhere, bookmarking offers "Open My book", and a game page can check for updates.
- Tabletop: Playing, Upcoming and Settings sit on the lower rail, and the A to Z search strip is in the lower half.

Check on the Duo:

- Open the Library in each way you hold the Duo (closed, open, book, tabletop) and swipe the Latest updates; nothing should be cut off or sit across the fold.
- Open a game, change its notifications to Major only, go back and return: it should still say Major only.
- Open Enshrouded: it should open on its newest patch.
- Turn Quiet hours on in Settings and set it to cover the current time: an alert from the app should arrive without a sound.
- Open Search, tap Back or swipe in from the left edge: you should land where you started.
- Open an upcoming game in Upcoming and tap it to watch it: it moves to your watchlist, and a release-day alert is set for it.
- Share an update: a picture card with the game and update appears in the share sheet.
- Add a game by speaking, then by photo, then by camera: each asks permission first and each offers Type it.
- Follow a known issue on a game page: it appears under Following. (The alert itself only arrives when an update fixes it.)

## 0.2.0

Shipped as TestFlight build 5.

- Every game shows its full update history, and Blue Prince is no longer empty.
- Updates that reached consoles a little after Steam now count as released on PS5, so none of them show as PC only.
- Tap any update in the list to open it. On a closed phone it opens full screen and Back returns to your place.
- A cold launch opens on your Library.
- Links open in your browser. Each game links to its official website and "All patch notes", and each update has "Open in Steam".
- A game without artwork gets the Playscribe header instead of a blank space. Image dots only show when there is more than one image.

## 0.1.0

First TestFlight build (builds 2 to 4, 1 to 2 Nov 2026).

- Library of PS5 games with cover tiles, release dates and update state.
- Patch journals for each game, unfolding into the game book on iPhone Duo.
- Every Steam update is treated as out on PS5 too, with links to the Steam notes and any studio PS5 page.
- Update alerts as soon as a patch lands.
