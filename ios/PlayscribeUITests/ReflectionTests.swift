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
        // Mac at 29f6d44: one tap before the YouTube player was ready left the video at 0:00 (video peak 0), so the test measured
        // nothing. Tap the orange Play until the transport says Pause, up to three times.
        let play = app.buttons["Play"]
        XCTAssertTrue(play.waitForExistence(timeout: 10) && play.isHittable, "Play on the transport")
        let pause = app.buttons["Pause"]
        for attempt in 1...3 where !pause.exists {
            if play.exists && play.isHittable { play.tap() }
            if pause.waitForExistence(timeout: 10) { break }
            print("ReflectionTests pose: \(pose) Play attempt \(attempt) did not start the video")
        }
        guard pause.exists else { return XCTFail("the video never started, so there is nothing to mirror [\(pose)]") }
        let on = expectation(for: NSPredicate(format: "label == %@", "mirror: on"), evaluatedWith: audit)
        wait(for: [on], timeout: 30)
        print("ReflectionTests pose: \(pose) mirror after Play: \(audit.label)")
        let shot = XCTAttachment(screenshot: app.screenshot())
        shot.name = "reflection-playing [\(pose)]"; shot.lifetime = .keepAlways; add(shot)
        measureMirror(audit, pose: pose)
    }

    /// The pixels (19 Nov, Terry: "it's missing entirely" on his Duo while the label said on). An XCUITest screenshot of the inner
    /// display in Tabletop is all black on the Duo simulator (Mac at 0e1f3e5), so the test cannot read them itself. It prints where
    /// the video and the mirror band are and keeps the video playing for 15 s; tools/qa/mirror-pixels.sh, running the test, takes
    /// `simctl io` screenshots meanwhile and fails unless the band's brightest pixels reach 40% of the video's on a bright frame.
    private func measureMirror(_ audit: XCUIElement, pose: String) {
        let g = (audit.value as? String ?? "").split(separator: " ").compactMap { Double($0) }
        guard g.count == 6, g[2] > 0, g[3] > 0, g[5] > 0 else { return XCTFail("mirror geometry missing: \(audit.value ?? "nil") [\(pose)]") }
        let w = XCUIApplication().windows.firstMatch.frame
        print("MIRROR_GEOMETRY window \(Int(w.width)) \(Int(w.height)) video \(g[0]) \(g[1]) \(g[2]) \(g[3]) band \(g[4]) \(min(g[5], g[3] * 0.25))")
        sleep(15)
        print("MIRROR_GEOMETRY done")
    }
}
