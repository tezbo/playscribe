import XCTest

/// D-1 (0.5.6, Card D; Nadia, 13 Nov): an Updates-tab row opens the update page. In Closed and Open portrait it is pushed
/// over the list and Back returns to the list in one step, at the same scroll; side by side the game opens with that update
/// and its Back ("Back to Updates") returns to the Updates tab.
@MainActor
final class BackPathTests: XCTestCase {
    func testAnUpdatesRowOpensTheUpdateAndBackReturnsToUpdates() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-qaRoute", "updates"]
        app.launch()
        // Tabletop hides the system tab bar (the rail carries the tabs), so the selected tab can't be read there.
        if ReleaseRowTests.pose(app).contains("tabletop") { app.terminate(); throw XCTSkip("Tabletop: no system tab bar to read") }
        let rows = app.buttons.matching(identifier: "feedRow")
        XCTAssertTrue(rows.firstMatch.waitForExistence(timeout: 10), "an Updates row")
        // A row below the first, so "the same scroll" is a real check.
        app.swipeUp()
        // A row wholly between the bars: isHittable alone took a row scrolled under the nav bar (y -88), whose tap did nothing
        // (gate #593). The floor is the nav bar's bottom, or the status bar's when there is no nav bar.
        let nav = app.navigationBars.firstMatch
        let top = nav.exists ? nav.frame.maxY : app.statusBars.firstMatch.frame.maxY
        let tabBar = app.tabBars.firstMatch
        let bottom = tabBar.exists ? tabBar.frame.minY : app.frame.maxY
        let inView = rows.allElementsBoundByIndex.filter { $0.isHittable && $0.frame.minY >= top && $0.frame.maxY <= bottom }
        XCTAssertFalse(inView.isEmpty, "an Updates row wholly between the bars (top \(top), bottom \(bottom))")
        let row = inView.first ?? rows.firstMatch
        let label = row.label
        row.tap()

        let detail = app.descendants(matching: .any)["releaseDetail"]
        if detail.waitForExistence(timeout: 5) {
            // Pushed: Back pops straight to the list.
            let back = app.navigationBars.buttons.firstMatch
            XCTAssertTrue(back.waitForExistence(timeout: 5), "the pushed update's Back")
            XCTAssertFalse(app.buttons["gameBack"].exists, "a pushed update has no game page under it")
            back.tap()
        } else {
            let back = app.buttons["gameBack"].firstMatch
            XCTAssertTrue(back.waitForExistence(timeout: 5), "the game's Back")
            XCTAssertEqual(back.label, "Back to Updates")
            back.tap()
        }
        let updates = app.tabBars.buttons["Updates"].firstMatch
        XCTAssertTrue(updates.waitForExistence(timeout: 5))
        XCTAssertTrue(updates.isSelected, "Back returned to the Updates tab")
        let again = app.buttons.matching(identifier: "feedRow").matching(NSPredicate(format: "label == %@", label)).firstMatch
        XCTAssertTrue(again.waitForExistence(timeout: 5) && again.isHittable, "the opened row is in view again: the list kept its scroll")
        app.terminate()
    }
}
