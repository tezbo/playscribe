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
        XCTAssertEqual(deck.count, 0, "the deck is hidden from VoiceOver while searching")
        XCTAssertTrue(app.keyboards.firstMatch.exists, "typing did not drop the keyboard")

        let clear = app.buttons["Clear search"]
        XCTAssertTrue(clear.waitForExistence(timeout: 3))
        clear.tap()
        app.keyboards.buttons["Search"].tap()  // the return key reads "Search" (Mac 6a2d5f1)
        XCTAssertTrue(deck.firstMatch.waitForExistence(timeout: 5), "the deck returns when the field is empty and unfocused")
    }
}
