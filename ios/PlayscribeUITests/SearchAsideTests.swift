import XCTest

/// G-4 (v0.5.3, #424): in Closed, a focused or filled Library search puts the update deck, News and the cards aside. They stay in the
/// view tree (removing them dropped the keyboard on the third key) but must expose nothing to VoiceOver and take no taps.
/// The accessibility hierarchy is what VoiceOver reads, so an empty `deckCard` query while searching is the check.
final class SearchAsideTests: XCTestCase {
    @MainActor
    func testClosedSearchHidesTheDeckFromAccessibilityAndReturnsOnClear() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-qaRoute", "two-update"]
        app.launch()
        let deck = app.descendants(matching: .any).matching(identifier: "deckCard")
        XCTAssertTrue(deck.firstMatch.waitForExistence(timeout: 10), "the deck shows before searching")
        let pose = ReleaseRowTests.pose(app)
        try XCTSkipUnless(pose.contains("pose: closed"), "the deck steps aside in Closed only (pose: \(pose))")

        let field = app.textFields["Search your library"].exists ? app.textFields["Search your library"] : app.textFields.firstMatch
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        field.tap()
        field.typeText("con")
        XCTAssertTrue(app.keyboards.firstMatch.waitForExistence(timeout: 5), "the keyboard is up")
        // Let the layout settle, then: nothing from the deck in the accessibility tree, and the keyboard is still up.
        sleep(1)
        if deck.count != 0 {
            let dump = XCTAttachment(string: app.debugDescription)
            dump.name = "deck-leak-tree.txt"
            dump.lifetime = .keepAlways
            add(dump)
        }
        XCTAssertEqual(deck.count, 0, "the deck is hidden from VoiceOver while searching")
        XCTAssertTrue(app.keyboards.firstMatch.exists, "typing did not drop the keyboard")

        let clear = app.buttons["Clear search"]
        XCTAssertTrue(clear.waitForExistence(timeout: 3))
        clear.tap()
        // The return key reads "Search" on the Duo simulator (Mac 6a2d5f1); accept the other labels so the test also runs elsewhere.
        let keys = app.keyboards.buttons
        let returnKey = ["Search", "search", "Return", "return"].map { keys[$0] }.first { $0.exists } ?? keys["Search"]
        returnKey.tap()
        XCTAssertTrue(deck.firstMatch.waitForExistence(timeout: 5), "the deck returns when the field is empty and unfocused")
    }
}

/// v0.5.3 (#424): a fast "control" in Closed once left the tile list blank and stuck (Mac 677e7eb, run 3 of 10). Types it ten times
/// and, when no tile shows, attaches the accessibility tree so the cause (no tile in the tree, or a tile with no frame) is readable.
final class SearchBlankListTests: XCTestCase {
    @MainActor
    func testFastControlNeverLeavesTheListBlank() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-qaRoute", "demo"]
        app.launch()
        let pose = ReleaseRowTests.pose(app)
        try XCTSkipUnless(pose.contains("pose: closed"), "run in Closed (pose: \(pose))")
        let field = app.textFields["Search your library"].exists ? app.textFields["Search your library"] : app.textFields.firstMatch
        XCTAssertTrue(field.waitForExistence(timeout: 10))
        let tiles = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'tile-'"))
        for run in 1...10 {
            field.tap()
            field.typeText("control")
            sleep(2)
            if !tiles.firstMatch.exists {
                let dump = XCTAttachment(string: app.debugDescription)
                dump.name = "blank-list-run\(run)-tree.txt"
                dump.lifetime = .keepAlways
                add(dump)
                print("BLANKLIST run \(run)\n\(app.debugDescription)")
                XCTFail("run \(run): no tile after typing 'control' (tree attached)")
                return
            }
            XCTAssertEqual(tiles.count, 1, "run \(run): one match for 'control'")
            let clear = app.buttons["Clear search"]
            if clear.waitForExistence(timeout: 3) { clear.tap() }
            app.keyboards.buttons.matching(NSPredicate(format: "label IN {'Search','search','Return','return'}")).firstMatch.tap()
            sleep(1)
        }
    }
}
