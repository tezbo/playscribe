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

        print("videoExitFullScreen frame before Exit: \(exit.frame) hittable \(exit.isHittable)")
        exit.tap()
        XCTAssertTrue(enter.waitForExistence(timeout: 10), "Exit full screen did not leave full screen")
        app.terminate()
    }
}
