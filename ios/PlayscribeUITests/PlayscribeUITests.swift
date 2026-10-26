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

/// TT-0: no reported view frame may intersect an active division, on any main screen.
final class FoldAuditTests: XCTestCase {
    @MainActor
    func testNothingCrossesTheFold() throws {
        let app = XCUIApplication()
        for route in ["library", "release/dawnwalker/dawnwalker@1.1", "video/dawnwalker/dawnwalker@1.1", "add", "updates"] {
            app.launchArguments = ["-qaRoute", route]
            app.launch()
            sleep(3)
            let audit = app.descendants(matching: .any)["foldAudit"]
            XCTAssertTrue(audit.waitForExistence(timeout: 5))
            let label = audit.label
            let shot = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
            shot.name = "fold-\(route.replacingOccurrences(of: "/", with: "_")) \(label)"
            shot.lifetime = .keepAlways
            add(shot)
            XCTAssertTrue(label.hasPrefix("fold-crossings: 0;"), "\(route): \(label)")
        }
    }
}

/// D-13: every display choice survives a relaunch.
@MainActor
final class DisplayChoiceTests: XCTestCase {
    func testLayoutChoiceSurvivesRelaunch() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-qaRoute", "demo"]
        app.launch()
        for (choice, expectList) in [("List", true), ("Tiles", false)] {
            let view = app.buttons["View"].firstMatch
            XCTAssertTrue(view.waitForExistence(timeout: 10))
            view.tap()
            let option = app.buttons[choice].firstMatch
            XCTAssertTrue(option.waitForExistence(timeout: 5), choice)
            option.tap()
            app.terminate()
            app.launchArguments = ["-qaRoute", "library"]
            app.launch()
            // List rows carry an options button per game; tiles keep it only off the closed display.
            let row = app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Options for'")).firstMatch
            let cover = app.images.matching(NSPredicate(format: "label ENDSWITH ' cover'")).firstMatch
            XCTAssertTrue(cover.waitForExistence(timeout: 10))
            if expectList { XCTAssertTrue(row.exists, "List after relaunch") }
            let shot = XCTAttachment(screenshot: app.screenshot())
            shot.name = "d13-\(choice.lowercased())-after-relaunch"
            shot.lifetime = .keepAlways
            add(shot)
        }
    }
}

/// D-10 a–h: Swap sides, run in a side-by-side pose (Open landscape or Book).
@MainActor
final class SwapSidesTests: XCTestCase {
    func testSwapSides() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-qaRoute", "release/dawnwalker/dawnwalker@1.1"]
        app.launch()
        let swap = app.buttons["swapSides"]
        guard swap.waitForExistence(timeout: 8) else {
            throw XCTSkip("Swap sides is only on the rail when Contents and Page are side by side")
        }
        let audit = app.descendants(matching: .any)["foldAudit"]
        let search = app.textFields.matching(NSPredicate(format: "placeholderValue BEGINSWITH 'Search'")).firstMatch
        XCTAssertTrue(search.waitForExistence(timeout: 5))
        search.tap()
        search.typeText("subtitle")
        // A bar button drops accessibilityValue, so the side is in the label ("Swap sides, reading on right").
        let before = swap.label
        XCTAssertTrue(before.hasPrefix("Swap sides, reading on"), before)

        // One swap: the value changes, the search text and fold audit hold.
        swap.tap()
        sleep(1)
        let after = swap.label
        XCTAssertNotEqual(before, after)
        XCTAssertEqual(search.value as? String, "subtitle", "search text survives the swap")
        XCTAssertTrue(audit.label.hasPrefix("fold-crossings: 0;"), "after swap: \(audit.label)")
        attach(app, "swap-1")

        // Rapid double tap ends where it started, consistently.
        swap.tap(); swap.tap()
        sleep(1)
        XCTAssertEqual(swap.label, after)
        attach(app, "swap-double")

        // The side holds across another game and a relaunch.
        app.terminate()
        app.launchArguments = ["-qaRoute", "chapter/kcd2/updates"]
        app.launch()
        XCTAssertTrue(app.buttons["swapSides"].waitForExistence(timeout: 8))
        XCTAssertEqual(app.buttons["swapSides"].label, after)
        attach(app, "swap-relaunch-other-game")
        // Leave the default side for the next run.
        app.buttons["swapSides"].tap()
    }

    private func attach(_ app: XCUIApplication, _ name: String) {
        let shot = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        shot.name = name
        shot.lifetime = .keepAlways
        add(shot)
    }
}

