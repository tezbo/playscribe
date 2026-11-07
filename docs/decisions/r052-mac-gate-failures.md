# r052-mac-gate-failures (gate 6511ae4, 7 Nov 2026)
Goal: a green Mac gate on main. Rule: no skips, decide app or test wrong for each.
- testUpcomingTabAndWatchlist, testNewSurfacesKeepFrameRules (Closed, Tabletop): hierarchy is the empty-library onboarding ("Add your first game"), so no picker or rail. Cause: the first-run route leaves an empty store on disk and the next `library` launch loads it. App (QA route) wrong: `library` now reseeds the demo set when the collection is empty.
- testLibraryToolbarCogAndAdd (Closed): Settings and Add frames are 38 x 38. App wrong: toolbar labels now at least 44 x 44 with a 44 pt hit shape.
- testEightGames, testTwentyEightGames (Tabletop): the hierarchy has the SpringBoard app switcher on top and the screenshot is black; the inner display was not showing the app. Mac/harness, not app. Needs a rerun after the library fix; open if it repeats.
- testPlusCardSwitch, testQuietHours (Tabletop): Library showed, Settings never opened; needs evidence after a rerun (likely the same state or display cause).
- Still open, need evidence: Closed "Potentially inaccessible text", testPinnedAddBar, testPillLeavesTheTopOfThePageAlone; Tabletop "Hit area is too small", testNewsChapterIsNeverBlank.
- Gate 3a1300d (#368 + #225): cleared testUpcomingTabAndWatchlist, testNewSurfacesKeepFrameRules, testEightGames, testTwentyEightGames.
- testPinnedAddBar: test stale. The Add sheet opens on its method chooser, the search field is behind "Type it"; the test now launches `add/keyboard`.
- testPlusCardSwitch, testQuietHours (Tabletop): test wrong. `app.swipeUp()` swipes from mid-screen, the view-only upper half, so the Settings form never scrolled; the loops now swipe the form.
- testLibraryToolbarCogAndAdd (Closed): still 38 pt with a 44 pt label frame. The Settings and Add buttons are drawn by the system at 37 to 38 pt in Closed (the poseProbe occlusion is that region), so the label frame has no effect and is reverted. Needs Iris: custom 44 pt rail buttons in Closed, or the test accepts the system size there. Not changed here.
- testAccessibilityAudit: Closed "potentially inaccessible text" (Dawnwalker reader; the spoiler Show row and "More" are real buttons, so likely an OCR element-detection mismatch) and Tabletop "hit area too small" on the plain-text alerts footer. No change without the audit's element dump.
