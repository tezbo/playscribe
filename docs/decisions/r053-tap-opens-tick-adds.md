# r053-tap-opens-tick-adds

Iris's call (v0.5.3 blocker, from Terry's "tapping on a title in Upcoming adds it to my library, and the sound is weird"): a tap on a cover never adds a game; it opens the game. Adding is a deliberate act, a tick on the cover or an explicit Add button. The pop plays only on an explicit add, opening is silent, and the sound default stays off.

Finding: the v0.5.2 build Terry runs (2669d75) still adds to Wishlist when an Upcoming tile is tapped (UpcomingView.tile called addGame); the #243 fix (1ace3d9) is in main, not in 2669d75, so v0.5.3 closes his exact report. In main the only one-tap adds were the first-run "Popular on PS5" covers (strip in Closed and Open, grid on the Book right page).

Change: those covers are now `PopularCover`: the cover opens the game (`browseGame`, silent); a 44 pt tick at the cover's top right adds it (`addGame`, so an upcoming game goes in as Wishlist and the Library row shows "Wishlist"). The 44 pt plate sits in the cover's top right corner, inside the cover's own frame (containment, which the fold audit's overlap rule allows; it only fires on crossing frames). It covers 44 pt of a 96 to 108 pt wide cover: about 40 to 46 percent of the width and 12 to 16 percent of the area. The cover below it still opens the game. Iris judges from the stills whether the plate is too heavy on the small strip covers. In Book the plate is on each cover's right edge, so on the first column it is at least tile width minus 44 pt (about 46 pt or more) plus the page inset away from the hinge side, never within 24 pt of it. The glyph is a fixed 22 pt system size, so Dynamic Type does not grow it past the plate; the plate is capped to the cover's own size on a very small tile.

Tests: UpcomingBrowseTests (a tap opens the game and leaves the Library unchanged; a tick adds exactly once, an upcoming game as Wishlist). Stills: first-run in Closed portrait and Open, and the Book right page, for Iris.

Back from an opened game returns to first-run with nothing added (browse never writes to the collection; the unit test covers the model, the Mac hand-checks the screen). Not claimed: no relaunch on a device yet.
Learning: a one-tap add on a browsing surface is a trap; make the adding a separate, visible control and keep the tap for looking.
