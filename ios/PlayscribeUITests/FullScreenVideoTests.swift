import XCTest

/// bug-071, R-13: full-screen video in Closed. Entering shows our band controls (Exit in the top band), a tap in a band is
/// ours (qaBands counts it), and Exit full screen leaves. From portrait the scene turns to landscape. The trailer is a real
/// YouTube embed, so this needs the network. qaFullScreen logs what the frame math saw.
@MainActor
final class FullScreenVideoTests: XCTestCase {
    func testEnterShowsBandsBandTapIsOursAndExitLeaves() {
        let app = XCUIApplication()
        app.launchArguments = ["-qaRoute", "trailer/dQw4w9WgXcQ/dawnwalker", "-qaVideoTime", "YES"]
        app.launch()
        let any = app.descendants(matching: .any)
        let play = any["videoPlay"]
        XCTAssertTrue(play.waitForExistence(timeout: 60), "the trailer did not load")
        expectation(for: NSPredicate(format: "isEnabled == true"), evaluatedWith: play)
        waitForExpectations(timeout: 60)
        play.tap()
        let enter = any["videoFullScreen"]
        XCTAssertTrue(enter.waitForExistence(timeout: 15), "no Full screen button")
        enter.tap()

        let exit = any["videoExitFullScreen"]
        XCTAssertTrue(exit.waitForExistence(timeout: 5), "the band controls were not shown on entering full screen")
        // The app turns its own scene to landscape; XCUITest still computes hit points for a portrait device and gets none
        // (run 45743580991: Exit frame (inf, inf, 0, 0), hit point {-1, -1}). Turn the simulated device to match the scene
        // (interface landscape-right is device landscape-left).
        XCUIDevice.shared.orientation = .landscapeLeft
        sleep(1)
        let probe = any["qaFullScreen"], bands = any["qaBands"]
        print("qaFullScreen entered: \(probe.value ?? "-")")
        print("videoExitFullScreen frame: \(exit.frame) window: \(app.windows.firstMatch.frame)")
        let shot = XCTAttachment(screenshot: app.screenshot())
        shot.name = "fullscreen-entered"
        shot.lifetime = .keepAlways
        add(shot)

        // While playing the controls fade after 3 s; a tap in the top band is ours and shows them again.
        sleep(5)
        print("qaBands after 5 s: \(bands.value ?? "-") time \(any["qaVideoTime"].value ?? "-")")
        app.windows.firstMatch.coordinate(withNormalizedOffset: CGVector(dx: 0.75, dy: 0)).withOffset(CGVector(dx: 0, dy: 30)).tap()
        sleep(1)
        let after = (bands.value as? String) ?? ""
        print("qaBands after band tap: \(after)")
        XCTAssertFalse(after.contains("wakes=0"), "a tap in the top band did not reach our controls: \(after)")
        XCTAssertTrue(exit.waitForExistence(timeout: 3), "Exit full screen is not shown after a band tap")
        // VoiceOver (Iris, #655): the scrubber speaks elapsed of total; the picture is one element; YouTube's iframe is hidden.
        let scrubberValue = (any["videoScrubber"].value as? String) ?? ""
        print("videoScrubber value: \(scrubberValue)")
        XCTAssertTrue(scrubberValue.contains(" of "), "the scrubber does not speak elapsed of total: \(scrubberValue)")
        XCTAssertTrue(any["videoFullScreenPicture"].exists, "the picture has no VoiceOver element")
        XCTAssertFalse(app.webViews.firstMatch.exists, "YouTube's web view is still exposed to VoiceOver")

        // The controls fade 3 s after the last touch while playing, often before XCUITest can read Exit's frame (runs 45748630556
        // and 45751314856). So Exit's point comes from the measured geometry in qaFullScreen: the top row starts 12 pt inside
        // the safe leading inset and is centred in the top band. The first tap shows the controls, the second is Exit.
        let geometry = (probe.value as? String) ?? ""
        func numbers(after key: String) -> [CGFloat] {
            guard let r = geometry.range(of: key + "=") else { return [] }
            let field = geometry[r.upperBound...].prefix { $0 != " " }
            return field.split(whereSeparator: { $0 == "," || $0 == "x" }).compactMap { Double($0).map { CGFloat($0) } }
        }
        let pic = numbers(after: "pic"), safe = numbers(after: "safe")
        XCTAssertEqual(pic.count, 4, "qaFullScreen has no picture frame: \(geometry)")
        XCTAssertEqual(safe.count, 4, "qaFullScreen has no safe insets: \(geometry)")
        guard pic.count == 4, safe.count == 4 else { return }
        let exitPoint = CGVector(dx: safe[1] + 12 + 22, dy: (pic[1] - 44) / 2 + 22)
        XCTAssertGreaterThanOrEqual(exitPoint.dx - 22, 92, "Exit would sit in the camera housing")
        sleep(4)
        let point = app.windows.firstMatch.coordinate(withNormalizedOffset: .zero).withOffset(exitPoint)
        point.tap()
        point.tap()
        XCTAssertTrue(enter.waitForExistence(timeout: 10), "Exit full screen did not leave full screen")
        app.terminate()
    }
}
