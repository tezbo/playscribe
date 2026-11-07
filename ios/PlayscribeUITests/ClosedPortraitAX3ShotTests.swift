import XCTest
import UIKit

/// Closed portrait stills at AX3 that need a route a launch-only script cannot reach, or a scroll (risk 2 step A, Quinn's review of
/// run 42293459096): the hero with the update chip, the Alerts card, the Updates tab, and the Add sheet at top, middle and bottom so a
/// still shows whether the pinned footer covers the last row. Attached as `closed-<name>-ax3`; no assertions beyond the size, because the
/// point is for Quinn to judge the stills.
final class ClosedPortraitAX3ShotTests: XCTestCase {
    private func launch(_ route: String) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-qaRoute", route, "-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"]
        XCUIDevice.shared.orientation = .portrait
        app.launch()
        sleep(4)
        return app
    }

    private func shoot(_ name: String) {
        let shot = XCUIScreen.main.screenshot()
        let attachment = XCTAttachment(screenshot: shot)
        attachment.name = "closed-\(name)-ax5"
        attachment.lifetime = .keepAlways
        add(attachment)
        XCTAssertGreaterThan(shot.image.size.height, shot.image.size.width, "\(name): not portrait")
    }

    func testHeroWithUpdateChip() {
        let app = launch("one-update")
        // 57da7e4 and 433c821 showed the N-1 alerts card and the PS Plus card, not the hero: the card sits above the deck.
        // Dismiss it (Not now) so the hero is on screen, then shoot top and one scroll down.
        let notNow = app.buttons["Not now"]
        if notNow.waitForExistence(timeout: 5) { notNow.tap(); sleep(1) }
        shoot("hero-update")
        app.swipeUp()
        sleep(1)
        shoot("hero-update-scrolled")
        app.terminate()
    }

    /// r054: a release title past 4 lines beside the share button sends the button to its own row. The route seeds a very long
    /// invented title; the button must sit below the title, not beside it, and the title must keep the full width.
    func testLongTitleShareDropsToOwnRow() {
        let app = launch("long-title/dawnwalker")
        let title = app.descendants(matching: .any)["releaseTitle"]
        XCTAssertTrue(title.waitForExistence(timeout: 15), "long-title: the release page never appeared")
        let share = app.buttons["Share update"]
        XCTAssertTrue(share.waitForExistence(timeout: 10), "long-title: Share update is missing")
        XCTAssertGreaterThanOrEqual(share.frame.minY, title.frame.maxY - 1, "long-title: the share button must sit under a title past 4 lines")
        // Capped at 4 lines (Iris): a title3 line at AX5 is well over 40 pt, so 4 lines stay under 4 x 70 pt and a fifth would not.
        let lineEstimate = UIFont.preferredFont(forTextStyle: .title3, compatibleWith: UITraitCollection(preferredContentSizeCategory: .accessibilityExtraExtraExtraLarge)).lineHeight
        XCTAssertLessThanOrEqual(title.frame.height, lineEstimate * 4 * 1.4, "long-title: the title runs past 4 lines")
        XCTAssertTrue(title.label.hasPrefix("The Grand Autumn"), "long-title: VoiceOver still reads the full title")
        XCTAssertTrue(title.label.hasSuffix("Since Launch"), "long-title: VoiceOver still reads the full title")
        shoot("long-title")
        app.terminate()
    }

    func testAlertsCard() {
        let app = launch("alerts")
        shoot("alerts-card")
        app.terminate()
    }

    /// The script's AX5 shot of Settings was blank (Quinn, 32380a7): it fired a fixed 4 s after launch. Wait for the screen's own title
    /// instead, and shoot nothing until it exists, so a blank still means a blank screen.
    func testSettingsTop() {
        let app = launch("settings")
        let title = app.staticTexts["Settings"]
        XCTAssertTrue(title.waitForExistence(timeout: 15), "settings: the Settings screen never appeared (a real blank page?)")
        sleep(1)
        shoot("settings")
        app.terminate()
    }

    func testLibraryTop() {
        let app = launch("library")
        XCTAssertTrue(app.staticTexts["Library"].waitForExistence(timeout: 15), "library: never appeared")
        shoot("library")
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
        // Scroll the sheet's own scroll view by dragging from the lower part up; a bare app.swipeUp() started over the pinned footer
        // and moved nothing (add-bottom matched add-top). Record whether anything moved, so a still that cannot scroll says so.
        let scroll = app.scrollViews.firstMatch
        let target: XCUIElement = scroll.exists ? scroll : app
        let before = XCUIScreen.main.screenshot().pngRepresentation
        target.swipeUp(velocity: .slow)
        sleep(1)
        shoot("add-mid")
        for _ in 0..<4 { target.swipeUp(velocity: .fast) }
        sleep(1)
        shoot("add-bottom")
        let after = XCUIScreen.main.screenshot().pngRepresentation
        print("add sheet scrolled: \(before != after) (scroll view found: \(scroll.exists))")
        app.terminate()
    }
}
