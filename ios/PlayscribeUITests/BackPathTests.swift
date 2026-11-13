import XCTest

/// D-1 (0.5.6, Card D, s4.png): Back from a game opened from the Updates tab returns to the Updates tab, and says so.
@MainActor
final class BackPathTests: XCTestCase {
    func testBackFromAGameOpenedInUpdatesReturnsToUpdates() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-qaRoute", "updates"]
        app.launch()
        // Tabletop hides the system tab bar (the rail carries the tabs), so the selected tab can't be read there.
        if ReleaseRowTests.pose(app).contains("tabletop") { app.terminate(); throw XCTSkip("Tabletop: no system tab bar to read") }
        let row = app.buttons["feedRow"].firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 10), "an Updates row")
        row.tap()
        // Closed and Open portrait push the update: its Back leads to the game first.
        let back = app.buttons["gameBack"].firstMatch
        if !back.waitForExistence(timeout: 5) {
            let pushedBack = app.navigationBars.buttons.firstMatch
            XCTAssertTrue(pushedBack.waitForExistence(timeout: 5), "the pushed update's Back")
            pushedBack.tap()
            XCTAssertTrue(back.waitForExistence(timeout: 5), "the game's Back")
        }
        XCTAssertEqual(back.label, "Updates, back")
        back.tap()
        let updates = app.tabBars.buttons["Updates"].firstMatch
        XCTAssertTrue(updates.waitForExistence(timeout: 5))
        XCTAssertTrue(updates.isSelected, "Back returned to the Updates tab")
        XCTAssertTrue(app.buttons["feedRow"].firstMatch.waitForExistence(timeout: 5), "the Updates list is showing")
        app.terminate()
    }
}
