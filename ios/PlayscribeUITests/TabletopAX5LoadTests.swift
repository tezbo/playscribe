import XCTest

/// Tabletop AX5 game page must load (r054-tabletop-ax5, Iris). At 2dbcd13 the stage text grew the stage it sat in, which moved the
/// clearance that sized the text, and the app sat at 100% CPU on the splash for over two minutes. A layout loop never reaches the
/// content, so this fails on the wait: the stage's release title must exist well inside 40 s (main loaded the same route in under 25 s
/// in the simulator).
@MainActor
final class TabletopAX5LoadTests: XCTestCase {
    private func launch(_ size: String) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-qaRoute", "gamepage/dawnwalker", "-qaPose", "tabletop",
                               "-UIPreferredContentSizeCategoryName", size]
        app.launch()
        return app
    }

    func testGamePageLoadsAtAX5() {
        let app = launch("UICTContentSizeCategoryAccessibilityXXXL")
        let stage = app.descendants(matching: .any)["releaseTitle"]
        XCTAssertTrue(stage.waitForExistence(timeout: 40), "Tabletop AX5 game page did not reach its content: layout loop?")
        app.terminate()
    }

    func testGamePageLoadsAtStandardSize() {
        let app = launch("UICTContentSizeCategoryL")
        XCTAssertTrue(app.descendants(matching: .any)["releaseTitle"].waitForExistence(timeout: 40))
        app.terminate()
    }
}
