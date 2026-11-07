# r052-mac-gate-failures (gate 6511ae4, 7 Nov 2026)
Goal: a green Mac gate on main. Rule: no skips, decide app or test wrong for each.
- testUpcomingTabAndWatchlist, testNewSurfacesKeepFrameRules (Closed, Tabletop): hierarchy is the empty-library onboarding ("Add your first game"), so no picker or rail. Cause: the first-run route leaves an empty store on disk and the next `library` launch loads it. App (QA route) wrong: `library` now reseeds the demo set when the collection is empty.
- testLibraryToolbarCogAndAdd (Closed): Settings and Add frames are 38 x 38. App wrong: toolbar labels now at least 44 x 44 with a 44 pt hit shape.
- testEightGames, testTwentyEightGames (Tabletop): the hierarchy has the SpringBoard app switcher on top and the screenshot is black; the inner display was not showing the app. Mac/harness, not app. Needs a rerun after the library fix; open if it repeats.
- testPlusCardSwitch, testQuietHours (Tabletop): Library showed, Settings never opened; needs evidence after a rerun (likely the same state or display cause).
- Still open, need evidence: Closed "Potentially inaccessible text", testPinnedAddBar, testPillLeavesTheTopOfThePageAlone; Tabletop "Hit area is too small", testNewsChapterIsNeverBlank.
