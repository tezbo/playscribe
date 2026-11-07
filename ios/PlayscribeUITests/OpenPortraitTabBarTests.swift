import XCTest

/// r053-open-portrait-tabbar-covers-last-row: in Open portrait the floating tab bar must not cover the last row of a scrolling
/// screen at the end of the scroll (std and AX5). Pose is read from the fold audit; in any other pose the test only records that.
@MainActor
final class OpenPortraitTabBarTests: XCTestCase {
    private func launch(_ route: String, ax5: Bool) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-qaRoute", route] + (ax5 ? ["-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"] : [])
        app.launch()
        sleep(4)
        return app
    }

    /// The lowest edge any content reaches, after scrolling the first scroll view or list to its end.
    private func lastContentMaxY(_ app: XCUIApplication) -> CGFloat {
        // Library is a ScrollView; Updates is a List, which the system may expose as a table or a collection view.
        let candidates = [app.scrollViews, app.tables, app.collectionViews].map { $0.firstMatch }.filter { $0.exists }
        guard let scroller = candidates.max(by: { $0.frame.height < $1.frame.height }) else { return 0 }
        for _ in 0..<12 { scroller.swipeUp(velocity: .fast) }
        sleep(1)
        var maxY: CGFloat = 0
        for e in scroller.descendants(matching: .any).allElementsBoundByIndex {
            let l = e.label.lowercased()
            if l.contains("scroll bar") || e.frame.isEmpty { continue }
            maxY = max(maxY, e.frame.maxY)
        }
        return maxY
    }

    private func check(_ route: String, ax5: Bool, _ name: String) {
        let app = launch(route, ax5: ax5)
        let pose = ReleaseRowTests.pose(app)
        let bar = app.tabBars.firstMatch
        guard pose.contains("pose: flat"), app.frame.height > app.frame.width, bar.waitForExistence(timeout: 5) else {
            print("\(name): skipped, not Open portrait [\(pose)]")
            return
        }
        let end = lastContentMaxY(app)
        XCTAssertGreaterThan(end, 0, "\(name): no scroll view, table or collection view found")
        let attachment = XCTAttachment(screenshot: (XCUIScreen.screens.max { $0.screenshot().image.size.height < $1.screenshot().image.size.height } ?? XCUIScreen.main).screenshot())
        attachment.name = "open-portrait-\(name)-end\(ax5 ? "-ax5" : "")"
        attachment.lifetime = .keepAlways
        add(attachment)
        XCTAssertLessThanOrEqual(end, bar.frame.minY + 0.5, "\(name): last row maxY \(end) must clear the tab bar minY \(bar.frame.minY)")
        app.terminate()
    }

    func testLibraryEndClearsTabBar() { check("many-updates", ax5: false, "library") }
    func testLibraryEndClearsTabBarAX5() { check("many-updates", ax5: true, "library") }
    func testUpdatesEndClearsTabBar() { check("many-updates/updates", ax5: false, "updates") }
    func testUpdatesEndClearsTabBarAX5() { check("many-updates/updates", ax5: true, "updates") }
}
