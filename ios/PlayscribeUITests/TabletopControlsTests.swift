import XCTest

/// TT-4 (Terry's Duo, 21 Nov: the controls "look like they should dim or could be dismissed but they can't"; Iris, reflection-0.6
/// spec 5 and 8.7). In Tabletop, while the video plays, the controls fade after 4 s; the rail's Close stays; a tap in the lower half
/// brings them back and does nothing else; paused, they stay. Outside Tabletop the YouTube player's own controls apply, so the test
/// only runs in Tabletop.
@MainActor
final class TabletopControlsTests: XCTestCase {
    func testControlsFadeWhilePlayingAndTapRevealsThem() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-qaRoute", "video/dawnwalker/dawnwalker@1.1"]
        app.launch()
        let pose = ReleaseRowTests.pose(app)
        guard pose.contains("tabletop") else { print("TabletopControlsTests: skipped in \(pose)"); return }
        let play = app.buttons["Play"], pause = app.buttons["Pause"]
        XCTAssertTrue(play.waitForExistence(timeout: 10), "Play on the transport")
        for _ in 1...3 where !pause.exists {
            if play.exists && play.isHittable { play.tap() }
            if pause.waitForExistence(timeout: 10) { break }
        }
        guard pause.exists else { return XCTFail("the video never started") }
        let reveal = app.descendants(matching: .any)["showControls"]
        XCTAssertTrue(reveal.waitForExistence(timeout: 8), "the controls fade within about 4 s of playing")
        XCTAssertFalse(pause.exists, "the faded controls are out of reach")
        XCTAssertTrue(app.buttons["Close"].isHittable, "the rail's Close stays")
        let faded = XCTAttachment(screenshot: app.screenshot()); faded.name = "controls-faded"; faded.lifetime = .keepAlways; add(faded)
        reveal.tap()
        XCTAssertTrue(pause.waitForExistence(timeout: 2), "a tap brings the controls back")
        XCTAssertTrue(pause.isHittable, "and only reveals: the video is still playing")
        pause.tap()
        XCTAssertTrue(play.waitForExistence(timeout: 5))
        sleep(6)
        XCTAssertTrue(play.isHittable, "paused, the controls stay")
        XCTAssertFalse(reveal.exists)
    }
}
