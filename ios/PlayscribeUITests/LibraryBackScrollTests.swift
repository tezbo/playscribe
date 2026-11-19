import XCTest

/// bug-library-back-scroll-jump: Back from a game must leave the Library where it was. Mac 003eb1d and 2f0cb77, Closed, fill-library/12:
/// the page came back 58 pt lower with its large title expanded. Fixed by making "Library" the first page row instead of a bar large title.
/// Closed only; Tabletop hides the navigation bar.
final class LibraryBackScrollTests: XCTestCase {
    @MainActor func testBackFromAGameKeepsTheLibraryWhereItWas() throws { try backKeepsPlace(ax5: false, swipes: 3) }
    /// Mac 45983f0: Dawnwalker 434.7 to 316.7 (-118) at AX5 with 3 drags, and 457.3 to 445.3 (-12) at std with 20 swipes; both red until the
    /// scroll position is bound to the model again, as on main.
    @MainActor func testBackKeepsTheLibraryWhereItWasAtAX5() throws { try backKeepsPlace(ax5: true, swipes: 3) }
    @MainActor func testBackKeepsTheLibraryWhereItWasAfterALongScroll() throws { try backKeepsPlace(ax5: false, swipes: 20) }

    @MainActor
    private func backKeepsPlace(ax5: Bool, swipes: Int) throws {
        let app = XCUIApplication()
        app.launchArguments = ["-qaRoute", "fill-library/12"]
            + (ax5 ? ["-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"] : [])
        app.launch()
        // Closed portrait, asked for and checked: a simulator left in landscape gave 149 and 125 pt misses (Nadia, f1fdde8).
        guard app.require(.portrait) else { return }
        let tiles = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'tile-'"))
        XCTAssertTrue(tiles.firstMatch.waitForExistence(timeout: 15), "the library shows tiles")
        let pose = ReleaseRowTests.pose(app)
        try XCTSkipUnless(pose.contains("pose: closed"), "Closed only (pose: \(pose))")
        for _ in 0..<swipes { app.scrollViews.firstMatch.swipeUp(velocity: .slow) }
        sleep(1)
        let visible = (0..<tiles.count).map { tiles.element(boundBy: $0) }.filter { $0.isHittable }
        let target = try XCTUnwrap(visible.first, "a tile is on screen after scrolling")
        let label = target.label
        // Every tile carries the same id ("tile-<cover width>", by design: the fold audit measures the cover), so index-based elements can
        // re-resolve to another tile as the layout settles. Find the tile again by its label, which is unique, before measuring and tapping.
        let chosen = app.buttons.matching(NSPredicate(format: "label == %@", label)).firstMatch
        XCTAssertTrue(chosen.waitForExistence(timeout: 5) && chosen.isHittable, "the chosen tile is on screen by its label")
        let before = chosen.frame.minY
        chosen.tap()
        let back = app.buttons["gameBack"]
        XCTAssertTrue(back.waitForExistence(timeout: 10), "the game page has a back button")
        back.tap()
        let again = app.buttons.matching(NSPredicate(format: "label == %@", label)).firstMatch
        XCTAssertTrue(again.waitForExistence(timeout: 10), "the same tile is back on screen")
        sleep(1)
        XCTAssertEqual(again.frame.minY, before, accuracy: 2, "the Library came back where it was")
        // The large title must not come back over the tiles: the bar stays collapsed.
        XCTAssertFalse(app.staticTexts["Library"].isHittable, "the large Library title is not on screen after Back")
    }

    /// Clearing a search from a scrolled page lands on the "Library" title row, with the keyboard away (Closed, fill-library/12).
    /// Red on main and eda31b5: the title stayed scrolled off (Mac 003eb1d, 954ec56).
    @MainActor
    func testClearingSearchReturnsToTheTitle() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-qaRoute", "fill-library/12"]
        app.launch()
        guard app.require(.portrait) else { return }
        XCTAssertTrue(app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'tile-'")).firstMatch.waitForExistence(timeout: 15))
        try XCTSkipUnless(ReleaseRowTests.pose(app).contains("pose: closed"), "Closed only")
        for _ in 0..<3 { app.scrollViews.firstMatch.swipeUp(velocity: .slow) }
        sleep(1)
        let field = app.textFields["Search your library"].exists ? app.textFields["Search your library"] : app.textFields.firstMatch
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        field.tap()
        field.typeText("con")
        XCTAssertTrue(app.keyboards.firstMatch.waitForExistence(timeout: 5))
        let clear = app.buttons["Clear search"]
        XCTAssertTrue(clear.waitForExistence(timeout: 3))
        clear.tap()
        // The Search key sits below the 678 pt Closed window; a newline from the keyboard dismisses it.
        field.typeText("\n")
        sleep(2)
        let title = app.staticTexts["Library"].firstMatch
        XCTAssertTrue(title.waitForExistence(timeout: 5) && title.isHittable, "the Library title row is on screen after the clear")
    }
}
