import XCTest

/// Closed portrait stills at AX3 that need a route a launch-only script cannot reach, or a scroll (risk 2 step A, Quinn's review of
/// run 42293459096): the hero with the update chip, the Alerts card, the Updates tab, and the Add sheet at top, middle and bottom so a
/// still shows whether the pinned footer covers the last row. Attached as `closed-<name>-ax3`; no assertions beyond the size, because the
/// point is for Quinn to judge the stills.
final class ClosedPortraitAX3ShotTests: XCTestCase {
    private func launch(_ route: String) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-qaRoute", route, "-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityL"]
        XCUIDevice.shared.orientation = .portrait
        app.launch()
        sleep(4)
        return app
    }

    private func shoot(_ name: String) {
        let shot = XCUIScreen.main.screenshot()
        let attachment = XCTAttachment(screenshot: shot)
        attachment.name = "closed-\(name)-ax3"
        attachment.lifetime = .keepAlways
        add(attachment)
        XCTAssertGreaterThan(shot.image.size.height, shot.image.size.width, "\(name): not portrait")
    }

    func testHeroWithUpdateChip() {
        let app = launch("one-update")
        shoot("hero-update")
        app.terminate()
    }

    func testAlertsCard() {
        let app = launch("alerts")
        shoot("alerts-card")
        app.terminate()
    }

    func testUpdatesTab() {
        let app = launch("updates")
        shoot("updates")
        app.terminate()
    }

    func testAddSheetTopMiddleBottom() {
        let app = launch("add")
        shoot("add-top")
        app.swipeUp()
        sleep(1)
        shoot("add-mid")
        for _ in 0..<4 { app.swipeUp() }
        sleep(1)
        shoot("add-bottom")
        app.terminate()
    }
}
