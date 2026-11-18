import XCTest

/// bug-056 (#513): the Library's scroll position is no longer a model write per scroll step, so its restore paths need their own checks.
/// Run each on main and on the branch: a failure on both is not a regression of #513. Closed portrait only (the poses where the page
/// scrolls under the large title).
final class LibraryScrollRestoreTests: XCTestCase {
    @MainActor
    private func launch() throws -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-qaRoute", "fill-library/12"]
        app.launch()
        let tile = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'tile-'")).firstMatch
        XCTAssertTrue(tile.waitForExistence(timeout: 15), "the library shows tiles")
        let pose = ReleaseRowTests.pose(app)
        try XCTSkipUnless(pose.contains("pose: closed"), "Closed only (pose: \(pose))")
        return app
    }

    /// Open a game from a scrolled Library and come back: the page is where it was, within 2 pt.
    @MainActor
    func testBackFromAGameKeepsTheLibraryWhereItWas() throws {
        let app = try launch()
        let scroller = app.scrollViews.firstMatch
        for _ in 0..<3 { scroller.swipeUp(velocity: .slow) }
        sleep(1)
        let tiles = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'tile-'"))
        let visible = (0..<tiles.count).map { tiles.element(boundBy: $0) }.filter { $0.isHittable }
        let target = try XCTUnwrap(visible.first, "a tile is on screen after scrolling")
        let label = target.label
        let before = target.frame.minY
        target.tap()
        let back = app.buttons["gameBack"]
        XCTAssertTrue(back.waitForExistence(timeout: 10), "the game page has a back button")
        back.tap()
        let again = app.buttons.matching(NSPredicate(format: "label == %@", label)).firstMatch
        XCTAssertTrue(again.waitForExistence(timeout: 10), "the same tile is back on screen")
        sleep(1)
        XCTAssertEqual(again.frame.minY, before, accuracy: 2, "the Library came back where it was (Mac 5270af1: moved 58 pt)")
    }

    /// Typing in the search, then clearing it with the keyboard away: the page goes to its top, large title and all.
    @MainActor
    func testClearingSearchReturnsToTheTopWithTheTitle() throws {
        let app = try launch()
        let field = app.textFields["Search your library"].exists ? app.textFields["Search your library"] : app.textFields.firstMatch
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        field.tap()
        field.typeText("con")
        XCTAssertTrue(app.keyboards.firstMatch.waitForExistence(timeout: 5))
        let clear = app.buttons["Clear search"]
        XCTAssertTrue(clear.waitForExistence(timeout: 3))
        clear.tap()
        // The Search key sits below the 678 pt Closed window and cannot be tapped; a newline from the keyboard dismisses it.
        field.typeText("\n")
        sleep(2)
        let picker = app.descendants(matching: .any)["libraryTabPicker"]
        XCTAssertTrue(picker.waitForExistence(timeout: 5))
        let title = app.staticTexts["Library"].firstMatch
        XCTAssertTrue(title.exists && title.frame.minY >= 0 && title.frame.maxY <= picker.frame.minY,
                      "the large Library title is on screen above the Playing/Upcoming control (Mac 5270af1: scrolled off)")
    }
}
