import XCTest

/// r060-dayone-patch-alert-app (Iris): in Tabletop the install line sits at the top of the lower half, read first by VoiceOver,
/// on the visit that opens an unread day-one patch. The Mac found it missing twice (2597a48, 4192b77): opening reads the update
/// before its page appears, and the Tabletop lower half had no place for the line.
@MainActor
final class TabletopDayOneTests: XCTestCase {
    private func launch(_ size: String) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-qaRoute", "dayone/dawnwalker/open", "-qaPose", "tabletop",
                               "-UIPreferredContentSizeCategoryName", size]
        app.launch()
        return app
    }

    private func assertInstallLine(_ size: String) {
        let app = launch(size)
        XCTAssertTrue(app.descendants(matching: .any)["releaseTitle"].waitForExistence(timeout: 40), "Tabletop game page did not load")
        let line = app.descendants(matching: .any)["dayOneNote"]
        XCTAssertTrue(line.waitForExistence(timeout: 5), "no install line on the Tabletop game page at \(size)")
        if line.exists { XCTAssertEqual(line.label, "Install this before you first play.") }
        let shot = XCTAttachment(screenshot: app.screenshot())
        shot.name = "tabletop-dayone-\(size)"
        shot.lifetime = .keepAlways
        add(shot)
        app.terminate()
    }

    func testInstallLineAtStandardSize() { assertInstallLine("UICTContentSizeCategoryL") }
    func testInstallLineAtAX5() { assertInstallLine("UICTContentSizeCategoryAccessibilityXXXL") }
}
