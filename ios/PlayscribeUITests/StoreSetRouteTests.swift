import XCTest

/// The store capture routes must do what their names say (r052-store-set-content). Two stills in a row came back identical to the
/// plain Library because a scroll silently did not happen; these run in about a minute on the Mac, in any pose:
/// -only-testing:PlayscribeUITests/StoreSetRouteTests
@MainActor
final class StoreSetRouteTests: XCTestCase {
    let app = XCUIApplication()

    override func setUp() async throws { continueAfterFailure = false }

    private func launch(_ route: String) {
        app.launchArguments = ["-qaRoute", route]
        app.launch()
    }

    /// `store-set/end` and `store-set/titles` leave the long-title tile whole on screen, title included.
    func testStoreSetEndShowsTheLastTileWhole() throws {
        for route in ["store-set/end", "store-set/titles"] {
            launch(route)
            let tile = app.descendants(matching: .any).matching(NSPredicate(format: "identifier BEGINSWITH 'tile-' AND label CONTAINS 'The Long Quiet Orchard'")).firstMatch
            XCTAssertTrue(tile.waitForExistence(timeout: 15), "\(route): the Orchard tile exists")
            sleep(2)   // the route scrolls 0.7 s after the Library appears
            XCTAssertTrue(tile.isHittable, "\(route): the Orchard tile is hittable")
            XCTAssertGreaterThanOrEqual(tile.frame.minY, 0, "\(route): the tile starts on screen")
            XCTAssertLessThanOrEqual(tile.frame.maxY, app.frame.maxY - 1, "\(route): the tile and its title end on screen (\(tile.frame) in \(app.frame))")
            app.terminate()
        }
    }

    /// `reader/<game>/<release>/<y>` opens the update scrolled, so its bullets are on screen and not just the "What's new" heading.
    func testReaderRouteShowsTheBullets() throws {
        launch("reader/store-lantern-reach/store-lantern-reach@update-1.3/320")
        let bullet = app.staticTexts["Night expeditions to the far shore."]
        XCTAssertTrue(bullet.waitForExistence(timeout: 15), "the first bullet exists")
        sleep(2)
        XCTAssertGreaterThanOrEqual(bullet.frame.minY, 0, "the bullet is not scrolled off the top (\(bullet.frame))")
        XCTAssertLessThanOrEqual(bullet.frame.maxY, app.frame.maxY - 1, "the bullet ends on screen (\(bullet.frame) in \(app.frame))")
    }
}
