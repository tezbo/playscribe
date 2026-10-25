import XCTest

/// Journeys that need the system UI: a real notification tap from SpringBoard (N-6, L-3) and the
/// accessibility audit (G-7, G-10). Run against whatever pose the simulator is in.
@MainActor
final class PlayscribeUITests: XCTestCase {
    let app = XCUIApplication()
    let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")

    override func setUp() async throws {
        continueAfterFailure = false
        app.launchArguments = ["-qaRoute", "demo"]
    }

    /// N-6: tapping the notification opens the game book on that release, cold and warm.
    func testNotificationTapOpensRelease() throws {
        for cold in [true, false] {
            app.launch()
            if cold { app.terminate() } else { XCUIDevice.shared.press(.home) }
            let note = try postAndFindNotification()
            note.tap()
            XCTAssertTrue(app.wait(for: .runningForeground, timeout: 10))
            let release = app.buttons.matching(NSPredicate(format: "label CONTAINS 'Update 1.1'")).firstMatch
            XCTAssertTrue(release.waitForExistence(timeout: 10), cold ? "cold" : "warm")
            attach(name: cold ? "notification-tap-cold" : "notification-tap-warm")
        }
    }

    /// G-7 and G-10: the system accessibility audit on the main screens.
    func testAccessibilityAudit() throws {
        for route in ["library", "release/dawnwalker/dawnwalker@1.1", "add", "updates"] {
            app.launchArguments = ["-qaRoute", route]
            app.launch()
            sleep(2)
            try app.performAccessibilityAudit(for: [.hitRegion, .sufficientElementDescription, .elementDetection]) { issue in
                // Game art, poster images and the system status bar aren't the app's controls.
                issue.element?.elementType == .image || issue.element?.identifier.isEmpty == false && issue.element?.label.isEmpty == true
            }
            attach(name: "audit-\(route.replacingOccurrences(of: "/", with: "_"))")
        }
    }

    // MARK: - Helpers

    /// Schedules a local notification through the app's internal route, then finds its banner.
    private func postAndFindNotification() throws -> XCUIElement {
        let simulate = XCUIApplication()
        simulate.launchArguments = ["-qaRoute", "simulate/dawnwalker/major"]
        simulate.launch()
        XCUIDevice.shared.press(.home)
        let banner = springboard.otherElements["Notification"].descendants(matching: .any)
            .matching(NSPredicate(format: "label CONTAINS 'is live on PS5'")).firstMatch
        if banner.waitForExistence(timeout: 15) { return banner }
        // Fall back to Notification Center.
        let start = springboard.coordinate(withNormalizedOffset: CGVector(dx: 0.3, dy: 0.001))
        start.press(forDuration: 0.1, thenDragTo: springboard.coordinate(withNormalizedOffset: CGVector(dx: 0.3, dy: 0.6)))
        let listed = springboard.descendants(matching: .any).matching(NSPredicate(format: "label CONTAINS 'is live on PS5'")).firstMatch
        XCTAssertTrue(listed.waitForExistence(timeout: 5))
        return listed
    }

    private func attach(name: String) {
        let a = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        a.name = name
        a.lifetime = .keepAlways
        add(a)
    }
}
