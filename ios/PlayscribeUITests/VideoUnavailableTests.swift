import XCTest

/// R-12 (Terry, 20 Nov: "If video unavailable then it must instead say open in YouTube"). A video that can't play in our player
/// says why and offers Open in YouTube and Close, in every pose. Driven by the `video-blocked` QA route, so no real blocked video
/// or network is needed. Nothing is tapped that would leave the app.
@MainActor
final class VideoUnavailableTests: XCTestCase {
    func testBlockedEmbedOffersOpenInYouTube() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-qaRoute", "video-blocked/dawnwalker/dawnwalker@1.1"]
        app.launch()
        let pose = ReleaseRowTests.pose(app)
        XCTAssertTrue(app.staticTexts["This video plays only on YouTube"].waitForExistence(timeout: 10), "reason for 150 [\(pose)]")
        let open = app.buttons["Open in YouTube"]
        XCTAssertTrue(open.exists && open.isHittable, "Open in YouTube [\(pose)]")
        XCTAssertTrue(app.buttons["Close"].isHittable, "Close [\(pose)]")
        XCTAssertFalse(app.buttons["Watch on YouTube"].exists, "one wording only [\(pose)]")
    }

    func testOtherErrorKeepsOpenInYouTube() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-qaRoute", "video-blocked/dawnwalker/dawnwalker@1.1/5"]
        app.launch()
        XCTAssertTrue(app.staticTexts["This video can’t play here"].waitForExistence(timeout: 10), "generic reason")
        XCTAssertTrue(app.buttons["Open in YouTube"].exists, "Open in YouTube on every error that stops playback")
    }
}
