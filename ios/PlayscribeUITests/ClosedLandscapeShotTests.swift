import XCTest

/// Closed landscape stills on a hosted runner, where the Mac's Device Hub rotate is not available (risk 2 step A).
/// `XCUIDevice.shared.orientation` turns the simulator; each still is attached as `closed-land-<screen>[-ax3]` and the test
/// fails when the screenshot is not wider than it is tall, so a run that did not reach landscape says so.
final class ClosedLandscapeShotTests: XCTestCase {
    private let screens: [(name: String, route: String)] = [
        ("library", "library"), ("hero", "demo"), ("alerts", "alerts"), ("settings", "settings"), ("add", "add"),
    ]

    private func shoot(ax3: Bool) {
        let suffix = ax3 ? "-ax3" : ""
        for screen in screens {
            let app = XCUIApplication()
            app.launchArguments = ["-qaRoute", screen.route]
                + (ax3 ? ["-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityL"] : [])
            XCUIDevice.shared.orientation = .landscapeLeft
            app.launch()
            XCUIDevice.shared.orientation = .landscapeLeft
            sleep(4)
            let shot = XCUIScreen.main.screenshot()
            let attachment = XCTAttachment(screenshot: shot)
            attachment.name = "closed-land-\(screen.name)\(suffix)"
            attachment.lifetime = .keepAlways
            add(attachment)
            let size = shot.image.size
            XCTAssertGreaterThan(size.width, size.height,
                                 "\(screen.name)\(suffix): still is \(Int(size.width))x\(Int(size.height)), not landscape")
            app.terminate()
        }
    }

    func testClosedLandscapeStandard() { shoot(ax3: false) }
    func testClosedLandscapeAX3() { shoot(ax3: true) }
}
