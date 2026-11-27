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
        // YouTube's iframe elements in full screen are checked by the fullscreen Duo scenario on sim-use's tree
        // (tools/qa/check-no-youtube-buttons.sh, which fails the job), not here (Quinn, #655). XCUITest's snapshot has a
        // known limit: it walks into elements that VoiceOver treats as leaves (it lists an Image inside our Exit button)
        // and into the web view's remote elements whatever their hidden flags. At 66564e9, c93e9d8 and cb3884c it still
        // found YouTube's "Show player controls" (3,44 12x12) with the web view hidden three ways, while sim-use's tree,
        // which honours hidden flags as VoiceOver does, never showed it in full screen. Printed here for the record.
        let stray = any.matching(NSPredicate(format: "label == %@", "Show player controls")).allElementsBoundByIndex
        for e in stray { print("XCUITest limit (informational) Show player controls: \(e.frame) hittable \(e.isHittable)") }
        if !stray.isEmpty {
            let tree = app.debugDescription.components(separatedBy: "\n")
            for (i, line) in tree.enumerated() where line.contains("Show player controls") {
                print("tree around it:\n" + tree[max(0, i - 25)...min(tree.count - 1, i + 3)].joined(separator: "\n"))
            }
        }

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
        // bug-073: Exit no longer fades, so one tap at its point leaves (a second tap would land on the screen behind).
        let point = app.windows.firstMatch.coordinate(withNormalizedOffset: .zero).withOffset(exitPoint)
        point.tap()
        XCTAssertTrue(enter.waitForExistence(timeout: 10), "Exit full screen did not leave full screen")
        app.terminate()
    }

    /// bug-073 (Terry, beta 6: no way to close full screen in Closed): with no -qaBandsStay, after the controls auto-hide, Exit
    /// is still there and tappable, a tap on the picture brings the other controls back, and Exit returns to the starting pose.
    func testExitStaysAfterAutoHideFromPortrait() { exitStaysAfterAutoHide(startLandscape: false) }
    func testExitStaysAfterAutoHideFromLandscape() { exitStaysAfterAutoHide(startLandscape: true) }

    private func exitStaysAfterAutoHide(startLandscape: Bool) {
        XCUIDevice.shared.orientation = startLandscape ? .landscapeLeft : .portrait
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
        let exit = any["videoExitFullScreen"], bands = any["qaBands"]
        XCTAssertTrue(exit.waitForExistence(timeout: 5), "Exit is not shown on entering full screen")
        // From portrait the app turns its scene; turn the simulated device to match, as above, so hit points are computed.
        XCUIDevice.shared.orientation = .landscapeLeft
        sleep(6)   // the controls hide 3 s after the last touch while playing
        let hidden = (bands.value as? String) ?? ""
        print("qaBands after auto-hide: \(hidden)")
        XCTAssertTrue(hidden.contains("shown=0"), "the controls did not auto-hide, so this did not test the hidden state: \(hidden)")
        XCTAssertTrue(exit.exists && exit.isHittable, "Exit full screen is gone once the controls hide")
        print("videoExitFullScreen frame after auto-hide: \(exit.frame) window: \(app.windows.firstMatch.frame)")
        let shot = XCTAttachment(screenshot: app.screenshot())
        shot.name = "fullscreen-hidden-\(startLandscape ? "landscape" : "portrait")"
        shot.lifetime = .keepAlways
        add(shot)
        // Any tap brings the controls back: here one on the middle of the picture.
        app.windows.firstMatch.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
        sleep(1)
        let woken = (bands.value as? String) ?? ""
        print("qaBands after picture tap: \(woken)")
        XCTAssertTrue(woken.contains("shown=1"), "a tap on the picture did not bring the controls back: \(woken)")
        sleep(5)   // hidden again
        exit.tap()
        XCTAssertTrue(enter.waitForExistence(timeout: 10), "Exit full screen did not leave full screen")
        sleep(2)   // the device stays landscape here, so a portrait window means the app turned itself back
        let window = app.windows.firstMatch.frame
        print("window after Exit: \(window)")
        XCTAssertEqual(window.width > window.height, startLandscape, "Exit did not return to the starting orientation: \(window)")
        app.terminate()
        XCUIDevice.shared.orientation = .portrait
    }
}
