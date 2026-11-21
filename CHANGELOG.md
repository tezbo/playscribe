# Changelog

Playscribe follows semantic versioning. Each `## x.y.z` section becomes that build's "What to Test" in TestFlight,
so write it for testers. Release steps are in docs/release.md.

## 0.6.0 candidate

Playscribe 0.6 is a fresh coat: new colour roles, clearer art, one deck card per game, day-one patches, a moving front cover and every video in our own player. Each line says what to do, then what you should see. Reply with the numbers that failed, or "all good".

1. Add a game with several recent updates. The Library's latest-updates deck shows one card for that game, its newest update, with games you haven't read first.
2. Swipe the deck, then flick it hard. Each swipe or flick moves exactly one card, the dots light for every card you can see, and the last card and its dot can be reached.
3. Open a game with bright key art. Titles and labels over the art stay easy to read in the Library, on deck cards and on the Tabletop stage.
4. When a game has an unread day-one patch, its card shows a Day-one patch chip, the front cover says so, and Tabletop shows the install line. Reading the patch clears all three.
5. Close and open the front cover. The game's key art moves gently; with Reduce Motion on, it stays still.
6. Play an update video, a trailer and a Gallery video, Closed and in Tabletop. All play inside Playscribe. In Tabletop the reflection sits under the video. If a video can't play here, you see an Open in YouTube button instead of an error.
7. Turn on Reduce Transparency in your phone's Settings (Accessibility, then Display & Text Size). In Playscribe, the cards in Settings and Add a game have a visible outline.
8. Open Settings, then Video lab. Nothing crashes.
9. Add a game with Say it: Add a game, Say it, then hold the button and say a title. If asked, allow Speech Recognition and the Microphone. Playscribe stays open and starts listening. To see the permission prompts again, delete Playscribe and reinstall it from TestFlight, then tap Say it and Allow. Deleting the app clears your library and reading progress, so add your games again afterwards.
10. On a game page, open More, then Check for updates. A message says it is checking, then either how many new updates there are, "No new updates" with the time you checked, or why it couldn’t check (try it in Airplane Mode too).
11. Closed or Open, play an update video or a trailer, then tap Full screen (top right, beside Close). The video fills the screen and keeps playing from the same point, with YouTube’s controls still there. Tap Exit full screen (above the video in portrait; top left in landscape, where it fades after 4 seconds and a tap brings it back) and the player is as it was. Turning the phone keeps full screen and re-fits the video; folding into Book or Tabletop leaves it, and playback keeps going. Book and Tabletop have no Full screen button.

Feedback you send through TestFlight, including its comment, may appear in our public issue tracker, so leave out personal details.

## 0.5.9

Videos now stay inside Playscribe. In 0.5.8, Play in Tabletop opened your Duo's own fullscreen player, so the reflection could never show. Each line says what to do, then what you should see.
Reply with the numbers that failed, or "all good".

1. In Tabletop, open Dawnwalker's Update 1.1, open its "Update 1.1 overview" video and press Play in the bottom half. The video plays in the top half, inside Playscribe, with the reflection under it. Your Duo's own fullscreen player never opens.
2. Same in Tabletop with a game trailer (a game page, then Play trailer) and with a Dawnwalker Gallery video. Both play in the top half with the reflection, and the controls stay in the bottom half.
3. Before you press Play, the top half shows the game's art, not YouTube's screen. Once it plays, YouTube's play bar and buttons never show on the video in Tabletop; only its title and logo do.
4. While a video plays in Tabletop, open the phone flat, then fold back to Tabletop. The video carries on from the same place (expect a short reload as it switches).
5. Switch the phone to light mode and open a video in Tabletop. The video screen stays dark and every label is readable.
6. Closed, open Dawnwalker's Gallery and tap a video. It plays in Playscribe, not in the YouTube app.

Feedback you send through TestFlight, including its comment, may appear in our public issue tracker, so leave out personal details.

## 0.5.8

A one-fix build for the video reflection, which was missing on the Duo in 0.5.7.

1. In Tabletop, play an update video or a trailer. A soft reflection of the playing video shows under it, at the top of the lower half, and moves with the video. Pause it and the reflection holds; close the video and it goes.

Feedback you send through TestFlight, including its comment, may appear in our public issue tracker, so leave out personal details.

## 0.5.7

This covers everything you reported as fixed or added in 0.5.6 and 0.5.7. Each line says what to do, then what you should see.
Reply with the numbers that failed, or "all good".

Fold check (about 2 minutes)
1. Open Cyberpunk 2077 and scroll halfway down Update 2.5. Unfold, half-fold into Tabletop, then close. You should stay on Update 2.5 at about the same place. After closing, the cover screen shows Playscribe on the same update, not the home screen.
2. In Tabletop, play a trailer. The top half only shows things, and every button is in the bottom half. The reflection moves with the video, and only in Tabletop.
3. Look at the side buttons in each pose (closed upright, closed sideways, open, Tabletop, book). You should see the same set every time, with none cut off and no scrolling.
4. Unfolded, tap an older patch under All updates, then swipe back. You should land on the game page with All updates showing.
5. Closed, scroll the Library down a bit, open a game, then go Back. The Library should be where you left it.

From 0.5.6
6. Tap Cyberpunk 2077 in the Library. It opens on Update 2.5, the newest, not Patch 2.31. Open Patch 2.31, go back to the Library, and tap Cyberpunk again. It opens on Update 2.5 again.
7. Cyberpunk, All updates: no "Check out what's coming…" or "REDstreams" rows. Those posts are under News instead.
8. Two Point Museum, 2 Nov update: the name reads "Update", not "Update 12.1.247768".
9. Closed sideways, on a game page: the rail has Back, Notifications, Status and More.
10. The Blood of Dawnwalker, Launch entry: it reads "Available on PC, PlayStation 5 and Xbox Series X|S", and says nothing about hotfixes not being tracked.

New in 0.5.7
11. Any update page: the patch name is the biggest thing on the page. The status line starts "Out on PS5". No dot separators anywhere (orange dots mean unread).
12. Any game page, closed or unfolded: the section bar (What’s new, News, Gallery and the rest) stays pinned at the top as you scroll, and tapping a section jumps to it. In Book the same sections are a contents list on the left page.
13. All updates rows lead with the patch name, then the headline, then the date.
14. Tabletop on an update: the patch name shows on the top half.
15. Back keeps the Library where it was and covers don’t flash. The search field no longer starts with a capital letter.
16. Long-running games such as Cyberpunk and KCD II now show their full update history, older years included, with no PC-only rows.

Known, coming in 0.5.8 (no need to report)
- A game you haven't added says "No updates yet" even when it has had patches.
- In Open portrait, the date under the first Library row is cut off hard by the tab bar.
- A feed refresh during a fast scroll can cause a brief stutter.
- After a pose change, the page can land a little above or below your reading place.

Feedback you send through TestFlight, including its comment, may appear in our public issue tracker, so leave out personal details.

## 0.5.6

A fix release for problems found in 0.5.5.

- Opening a game now shows its newest PS5 update, not one you looked at on an earlier visit.
- Tapping an update in All updates and then going back returns you to the page you were on, with All updates still there.
- The buttons beside a game are the same in every position of the phone: Back, Notifications, Status and More. They no longer change, scroll or sit half hidden in Tabletop. Check for updates, Links, Share and (in Book) Swap sides are under More.
- The video reflection now shows only in Tabletop, and it mirrors the video as it plays.
- The Dawnwalker launch entry no longer says its launch hotfixes weren't tracked.
- News posts no longer show up as updates in All updates, and update titles no longer show bare build numbers. This was fixed on our server, so it applies as soon as the list refreshes.

Feedback you send through TestFlight, including its comment, may appear in our public issue tracker, so leave out personal details.

## 0.5.5

- New in Settings: "Help keep my games up to date". Off until you turn it on. When on, the app sends our server the games you follow and a random code, so those games are checked every hour instead of about every 14 hours. The card in the Library explains exactly what is sent, what never is, and that the record is deleted when you turn it off.
- Dates on News and the Library's "Last update" line now show the day the post went up, wherever you are.

Feedback you send through TestFlight, including its comment, may appear in our public issue tracker, so leave out personal details.

## 0.5.4

- News has its own tab, with gaming headlines from five sites. Sale and merchandise headlines are left out.
- PS Plus titles now open their game page, and the PS Plus card wraps at big text sizes.
- On a game page, All updates now sits above About, and "You might also like" leads with View game.
- The update deck at the top of the Library shows up to five updates.
- Sharing an update makes a cleaner card, and its link opens the game.
- Book mode: pages keep clear of the hinge.
- At the largest text sizes, more screens wrap on whole words: category and trailer rows, the Story, and the Tabletop stage. The A to Z letters grow with the text.
- Fixes: stray formatting marks no longer show in some patch notes, and announcements of an upcoming patch no longer show as PS5 updates.

Known issues in this build:

- Search: if you type quickly in the Library search, the list of games can go blank. Clear the search to bring it back.
- Tabletop: for a game with no videos, "Find trailers online" can't be tapped.
- Adding a game can show all of its past updates as unread.
- Tapping a notification while the app is already open has not been checked in this build.
- Some dates on News and in Library "Last update" can show a day earlier or later than the post date, depending on your time zone.

Feedback you send through TestFlight, including its comment, may appear in our public issue tracker, so leave out personal details.

## 0.5.3

- A game we don't track yet now says so, instead of "No updates yet".
- Settings has a new Team alerts switch (development and TestFlight builds only). Turn it on to help us test alerts.
- Turning alerts off now removes your device from our alert list.
- Upcoming fits more on screen: short sections share a row, the cover shows the next game, and at big text sizes everything stacks in one column.
- The "Also new" panel is gone, and the deck runs full width in Open portrait.
- At big text sizes, titles, summaries and captions now wrap on whole words, and the spoiler row, Journal and Updates rows do too.
- We also fixed the unread dot, the share button and spoiler contrast. At the largest sizes the share button lines up with the right edge of the text.
- In Closed portrait the Updates rows stop short of the clock and the rail instead of running under them.
- On a game page the section chips show every section when they fit, and no longer crowd the links. The page counter stays clear of the content, and VoiceOver covers video and the Tabletop reader.
- Link rows say where they go, for example "Read full notes on Steam".
- Pre-launch patches no longer show as PS5 updates.
- Tapping a PS5 update notification no longer crashes the app, and it opens that update's page.

Known issues in this build:

- Search: what you type can occasionally be lost, or the list can go blank while you type. Fixed in the next version.
- Notifications: tapping a notification when the app is already open has not been checked yet. Tapping one when the app is closed has.
- Book mode: on the left page the tiles show after News instead of first.
- VoiceOver on the Library tiles has not been checked on a real device yet.

Check on the Duo:

- Settings, then Team alerts: turn it on. Take a screenshot, tap Share Beta Feedback and send it with the comment "alert test". A team alert should arrive within a minute. If nothing arrives, tell us; that is a useful result too.
- Turn Team alerts off and send another screenshot the same way: no team alert should arrive.
- Settings, then Accessibility, then Display & Text Size, then Larger Text: turn on Larger Accessibility Sizes and drag the slider to the end: titles and the spoiler row should wrap on whole words with nothing cut off.

Feedback you send through TestFlight, including its comment, may appear in our public issue tracker, so leave out personal details.

## 0.5.2

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
