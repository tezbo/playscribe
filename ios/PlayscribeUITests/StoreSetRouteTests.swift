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
            if tile.frame.maxY > app.frame.maxY - 1 {
                let a = XCTAttachment(string: app.debugDescription); a.lifetime = .keepAlways; add(a)   // the hierarchy: scroll view and tab frames
            }
            XCTAssertLessThanOrEqual(tile.frame.maxY, app.frame.maxY - 1, "\(route): the tile and its title end on screen (\(tile.frame) in \(app.frame))")
            app.terminate()
        }
    }

    /// `reader/<game>/<release>/<y>` opens the update scrolled, so its bullets are on screen and not just the "What's new" heading.
    func testReaderRouteShowsTheBullets() throws {
        launch("reader/store-lantern-reach/store-lantern-reach@update-1.3/320")
        let bullet = app.staticTexts["night expeditions to the far shore"]   // the "What's new" key-change line as the reader shows it (the full-sentence bullets sit in the collapsed "What's changed" section)
        if !bullet.waitForExistence(timeout: 15) {
            let a = XCTAttachment(string: app.debugDescription); a.lifetime = .keepAlways; add(a)   // the hierarchy, for the Mac report
            XCTFail("the first bullet exists"); return
        }
        sleep(2)
        XCTAssertGreaterThanOrEqual(bullet.frame.minY, 0, "the bullet is not scrolled off the top (\(bullet.frame))")
        XCTAssertLessThanOrEqual(bullet.frame.maxY, app.frame.maxY - 1, "the bullet ends on screen (\(bullet.frame) in \(app.frame))")
    }

    /// A later route in a capture run is a fresh process: the store set's invented Upcoming games must survive it (gate 3f22417).
    func testUpcomingAfterStoreSetListsInventedGames() throws {
        launch("store-set")
        sleep(3)
        app.terminate()
        launch("library/upcoming")
        let invented = app.descendants(matching: .any).matching(NSPredicate(format: "label CONTAINS 'Pale Harbour Lanterns'")).firstMatch
        XCTAssertTrue(invented.waitForExistence(timeout: 15), "an invented Upcoming game shows")
        XCTAssertFalse(app.descendants(matching: .any).matching(NSPredicate(format: "label CONTAINS 'Football Manager'")).firstMatch.exists, "no real catalogue title")
    }

    /// The Hollow Meridian hotfix lists its open known issue with a Follow control, also in a fresh process.
    func testHotfixReaderShowsKnownIssueWithFollow() throws {
        launch("store-set")
        sleep(3)
        app.terminate()
        launch("reader/store-hollow-meridian/store-hollow-meridian@hotfix-1.1.2/420/issues")   // the Known issues section is collapsed by design; the route opens it and scrolls
        let issue = app.staticTexts.matching(NSPredicate(format: "label CONTAINS 'autosaves can fail'")).firstMatch
        if !issue.waitForExistence(timeout: 15) {
            let a = XCTAttachment(string: app.debugDescription); a.lifetime = .keepAlways; add(a)   // the hierarchy, for the Mac report
            XCTFail("the known issue line shows"); return
        }
        let follow = app.buttons["Follow this issue"]
        XCTAssertTrue(follow.waitForExistence(timeout: 5), "its Follow control shows")
        XCTAssertLessThanOrEqual(follow.frame.maxY, app.frame.maxY - 1, "the Follow control is on screen (\(follow.frame) in \(app.frame))")
    }
}
