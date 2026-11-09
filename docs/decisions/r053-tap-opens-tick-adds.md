# r053-tap-opens-tick-adds

Iris's call (v0.5.3 blocker, from Terry's "tapping on a title in Upcoming adds it to my library, and the sound is weird"): a tap on a cover never adds a game; it opens the game. Adding is a deliberate act, a tick on the cover or an explicit Add button. The pop plays only on an explicit add, opening is silent, and the sound default stays off.

Finding: the v0.5.2 build Terry runs (2669d75) still adds to Wishlist when an Upcoming tile is tapped (UpcomingView.tile called addGame); the #243 fix (1ace3d9) is in main, not in 2669d75, so v0.5.3 closes his exact report. In main the only one-tap adds were the first-run "Popular on PS5" covers (strip in Closed and Open, grid on the Book right page).

Change: those covers are now `PopularCover`: the cover opens the game (`browseGame`, silent); a 44 pt tick at the cover's top right adds it (`addGame`, so an upcoming game goes in as Wishlist and the Library row shows "Wishlist"). The tick sits on the cover's outer corner, so it is never on or within 24 pt of the hinge in Book (the grid starts at the page's left, hinge side, and the tick is on each cover's right).

Tests: UpcomingBrowseTests (a tap opens the game and leaves the Library unchanged; a tick adds exactly once, an upcoming game as Wishlist). Stills: first-run in Closed portrait and Open, and the Book right page, for Iris.

Back from an opened game returns to first-run with nothing added (browse never writes to the collection; the unit test covers the model, the Mac hand-checks the screen). Not claimed: no relaunch on a device yet.
Learning: a one-tap add on a browsing surface is a trap; make the adding a separate, visible control and keep the tap for looking.
