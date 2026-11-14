import XCTest

/// R-11, Reflection mode (Terry's Duo test, 14 Nov, 0.5.5): the mirror is the live video itself, in Tabletop only. Outside Tabletop
/// there is none; in Tabletop there is none until the video plays, then there is one. Read from the player's `mirrorAudit`
/// accessibility label (INTERNAL builds), not from pixels: a screenshot shows only one display, and walking the YouTube web view's
/// texts timed out (Mac at fd95a88). Autoplay is off by default, so the video has not started when the test first looks.
@MainActor
final class ReflectionTests: XCTestCase {
    func testMirrorOnlyInTabletopAndOnlyWhilePlaying() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-qaRoute", "video/dawnwalker/dawnwalker@1.1"]
        app.launch()
        let audit = app.descendants(matching: .any)["mirrorAudit"]
        XCTAssertTrue(audit.waitForExistence(timeout: 10), "mirror audit present")
        let pose = ReleaseRowTests.pose(app)
        // The pose in the run's output, so one log shows every pose the test covered (Quinn on #533).
        print("ReflectionTests pose: \(pose)")
        sleep(2)
        XCTAssertEqual(audit.label, "mirror: off", "no mirror before the video plays [\(pose)]")
        guard pose.contains("tabletop") else {
            // Outside Tabletop nothing turns it on: the player's own controls play the video, and the mirror stays off.
            sleep(3)
            XCTAssertEqual(audit.label, "mirror: off", "no mirror outside Tabletop [\(pose)]")
            print("ReflectionTests pose: \(pose) after waiting: \(audit.label)")
            return
        }
        let play = app.buttons["Play"]
        XCTAssertTrue(play.waitForExistence(timeout: 10) && play.isHittable, "Play on the transport")
        play.tap()
        let on = expectation(for: NSPredicate(format: "label == %@", "mirror: on"), evaluatedWith: audit)
        wait(for: [on], timeout: 30)
        print("ReflectionTests pose: \(pose) mirror after Play: \(audit.label)")
        let shot = XCTAttachment(screenshot: app.screenshot())
        shot.name = "reflection-playing [\(pose)]"; shot.lifetime = .keepAlways; add(shot)
    }
}
