import XCTest

/// J-1, D-1 in Open portrait (Nadia, 0.5.7 walk at f1fdde8): a swipe back from a pushed update left Patch 2.31 showing with All updates
/// gone, and a swipe is not what most readers do. This one uses the Back button: an older update pushed from the game page's list,
/// then Back, lands on the list with that row in view and no update page left on screen. Open portrait only (the Mac's inner display).
@MainActor
final class OpenPortraitBackTests: XCTestCase {
    func testBackButtonFromAPushedUpdateReturnsToTheList() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-qaRoute", "gamepage/kcd2"]
        app.launch()
        guard app.require(.portrait) else { return }
        let rows = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'releaseRow-'"))
        XCTAssertTrue(rows.firstMatch.waitForExistence(timeout: 15), "the game page lists its updates")
        let pose = ReleaseRowTests.pose(app)
        try XCTSkipUnless(pose.contains("pose: flat"), "Open portrait only (pose: \(pose))")

        // An older update, so Back landing on the newest would show.
        let hittable = rows.allElementsBoundByIndex.filter { $0.isHittable }
        let row = try XCTUnwrap(hittable.count > 1 ? hittable[1] : hittable.first, "an update row on screen")
        let id = row.identifier
        row.tap()
        let detail = app.descendants(matching: .any)["releaseDetail"]
        XCTAssertTrue(detail.waitForExistence(timeout: 5), "the update opens as its own page")

        let back = app.navigationBars.buttons.firstMatch
        XCTAssertTrue(back.waitForExistence(timeout: 5) && back.isHittable, "the pushed update's Back button")
        back.tap()
        sleep(1)
        XCTAssertFalse(detail.exists, "no update page is left on screen after Back")
        XCTAssertTrue(app.buttons["gameBack"].waitForExistence(timeout: 5), "Back lands on the game page")
        let again = app.buttons[id]
        XCTAssertTrue(again.waitForExistence(timeout: 5) && again.isHittable, "\(id) is in view again on the list")
        app.terminate()
    }
}
