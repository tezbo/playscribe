import XCTest

/// R-11 (Terry, 19 Nov: "The dawn walker ones all open in YouTube"): a Gallery video plays in the app's own player. In Tabletop the
/// Gallery sits on the view-only stage, so its play rows are in the lower half; tapping one opens the lower-half player (Close shows)
/// and the app stays in front, never handing off to the YouTube app.
@MainActor
final class GalleryVideoTests: XCTestCase {
    func testGalleryVideoPlaysInTheApp() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-qaRoute", "gamepage/dawnwalker/gallery"]
        app.launch()
        let pose = ReleaseRowTests.pose(app)
        print("GalleryVideoTests pose: \(pose)")
        let row = pose.contains("tabletop") ? app.buttons["galleryPlay-v-launch"] : app.buttons["Launch Trailer, video"]
        XCTAssertTrue(row.waitForExistence(timeout: 15), "a Launch Trailer control in reach [\(pose)]")
        if !row.isHittable { app.swipeUp() }
        XCTAssertTrue(row.isHittable, "the Launch Trailer control can be tapped [\(pose)]")
        row.tap()
        sleep(2)
        XCTAssertEqual(app.state, .runningForeground, "Playscribe stays in front: no hand-off to YouTube [\(pose)]")
        XCTAssertTrue(app.buttons["Close"].waitForExistence(timeout: 10), "the in-app player opens [\(pose)]")
        let shot = XCTAttachment(screenshot: app.screenshot()); shot.name = "gallery-video [\(pose)]"; shot.lifetime = .keepAlways; add(shot)
    }

    /// Spec 6 (Terry's Duo, 21 Nov: the top half was a list that wasn't interactive, and the same videos were listed below). In
    /// Tabletop the Gallery's stage is a picture: no list heading and no video rows above the fold; the rows are in the lower half.
    func testTabletopGalleryHasOneList() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-qaRoute", "gamepage/dawnwalker/gallery"]
        app.launch()
        let pose = ReleaseRowTests.pose(app)
        guard pose.contains("tabletop") else { print("GalleryVideoTests one list: skipped in \(pose)"); return }
        XCTAssertTrue(app.buttons["galleryPlay-v-launch"].waitForExistence(timeout: 15), "Launch Trailer row in the lower half")
        XCTAssertFalse(app.staticTexts["Official videos"].exists, "no list heading on the stage")
        XCTAssertFalse(app.buttons["Launch Trailer, video"].exists, "no second, dead copy of the row")
        let shot = XCTAttachment(screenshot: app.screenshot()); shot.name = "gallery-one-list [\(pose)]"; shot.lifetime = .keepAlways; add(shot)
    }
}
