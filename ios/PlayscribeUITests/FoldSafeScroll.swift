import XCTest

extension XCUIApplication {
    /// Scrolls the page up by swiping the scroll view element itself, the way `ReleaseRowTests.reveal` does: the Contents list
    /// where there is one (Book, Tabletop's lower half), otherwise the one-column page. A drag built from `windows.firstMatch`
    /// coordinates never moved the Open portrait game page (Mac at e354e0e1: 20 drags, page still at its top), while element
    /// swipes on the same page pass there (OpenPortraitTabBarTests, PageBottomFadeTests, ReleaseRowTests). Logs the window and
    /// app frames once so the Mac log shows which coordinate space the old drag used.
    func scrollPageUpAvoidingFold() {
        let contents = scrollViews["contentsScroll"], page = scrollViews["pageScroll"].firstMatch
        if !FoldSafeScrollLog.logged {
            FoldSafeScrollLog.logged = true
            print("FoldSafeScroll: window \(windows.firstMatch.frame) app \(frame) page \(page.exists ? "\(page.frame)" : "none")")
        }
        if contents.exists && contents.isHittable { contents.swipeUp(velocity: .slow) }
        else if page.exists && page.isHittable { page.swipeUp(velocity: .slow) }
        else { swipeUp(velocity: .slow) }
    }

    /// Scrolls until `element` is hittable, up to `limit` swipes. Returns whether it got there.
    @discardableResult
    func scrollUntilHittable(_ element: XCUIElement, limit: Int = 25) -> Bool {
        for _ in 0..<limit {
            if element.exists && element.isHittable { return true }
            scrollPageUpAvoidingFold()
        }
        return element.exists && element.isHittable
    }
}

@MainActor enum FoldSafeScrollLog { static var logged = false }

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
