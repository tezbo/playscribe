import XCTest

extension XCUIApplication {
    /// Scrolls the page up by about a third of the window, starting the drag low in the lower display. `swipeUp()` starts at the
    /// window's centre, which in Open portrait is the fold's division band: the drag never reached the page (Mac at a5221d12:
    /// 14 swipes left the Open portrait game page at its top, so no Gallery or trailer row ever became hittable).
    func scrollPageUpAvoidingFold() {
        let w = windows.firstMatch
        let from = w.coordinate(withNormalizedOffset: CGVector(dx: 0.4, dy: 0.9))
        let to = w.coordinate(withNormalizedOffset: CGVector(dx: 0.4, dy: 0.6))
        from.press(forDuration: 0.05, thenDragTo: to)
    }

    /// Scrolls until `element` is hittable, up to `limit` drags. Returns whether it got there.
    @discardableResult
    func scrollUntilHittable(_ element: XCUIElement, limit: Int = 25) -> Bool {
        for _ in 0..<limit {
            if element.exists && element.isHittable { return true }
            scrollPageUpAvoidingFold()
        }
        return element.exists && element.isHittable
    }
}

/// Quinn (Mac at a5221d12): scrolled to the end, the game page's last rows clear the bottom tab bar, so nothing at the end of a
/// page sits behind it. The About section's trailer rows are the page's last controls.
@MainActor
final class PageEndClearsTabBarTests: XCTestCase {
    func testLastTrailerRowClearsTheTabBar() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-qaRoute", "gamepage/dawnwalker"]
        app.launch()
        let pose = ReleaseRowTests.pose(app)
        guard !pose.contains("tabletop") else { print("PageEndClearsTabBarTests: Tabletop has no About rows; skipped"); return }
        let rows = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'trailerPlay-'"))
        XCTAssertTrue(rows.firstMatch.waitForExistence(timeout: 30), "trailer rows load [\(pose)]")
        let last = rows.element(boundBy: rows.count - 1)
        XCTAssertTrue(app.scrollUntilHittable(last), "the last trailer row can be reached [\(pose)]")
        for _ in 0..<3 { app.scrollPageUpAvoidingFold() }   // at the end of the page
        let shot = XCTAttachment(screenshot: app.screenshot()); shot.name = "page-end [\(pose)]"; shot.lifetime = .keepAlways; add(shot)
        let bar = app.tabBars.firstMatch
        if bar.exists, bar.frame.width > bar.frame.height {
            XCTAssertLessThanOrEqual(last.frame.maxY, bar.frame.minY + 1, "the last row clears the bottom tab bar [\(pose)]: \(last.frame) vs \(bar.frame)")
        }
        XCTAssertTrue(last.isHittable, "the last row is still tappable at the end [\(pose)]")
    }
}
