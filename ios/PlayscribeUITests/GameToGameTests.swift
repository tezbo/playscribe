import XCTest

/// Terry on beta 3 (real Duo, 22 Nov): "View game" from "You might also like" lagged, then showed a black screen; the page
/// appeared only once he scrolled. No game opens blank. "View game" sits at the end of a game page, so the reader is scrolled
/// far down when another game opens in its place (browseGame, then openGame). This opens a browsed game the same way from the
/// bottom of a long page and measures where the new page's first frame sits: its title control on screen, at once, with no
/// scroll.
@MainActor
final class GameToGameTests: XCTestCase {
    func testAGameOpenedFromTheEndOfAnotherShowsItsTop() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-qaRoute", "gamepage/dawnwalker"]
        app.launch()
        sleep(3)
        if ReleaseRowTests.pose(app).contains("tabletop") { app.terminate(); throw XCTSkip("Tabletop's page is the lower panel") }
        let page = app.descendants(matching: .any)["pageScroll"].firstMatch   // several match (Mac at c206578f)
        guard page.waitForExistence(timeout: 5) else { app.terminate(); throw XCTSkip("no one-column page in this pose (Book)") }
        for _ in 0..<10 { page.swipeUp(velocity: .fast) }
        sleep(1)

        // Astro's Playroom: in the PS5 index, not the catalogue, so it opens browsed with "Add to library" under its title.
        app.open(URL(string: "playscribe://index-game/134597")!)
        let addButton = app.buttons["addToLibrary"]
        let shown = addButton.waitForExistence(timeout: 3)
        let shot = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        shot.name = "game-to-game-first-frame"
        shot.lifetime = .keepAlways
        add(shot)
        let window = app.windows.firstMatch.frame
        let note = "\(ReleaseRowTests.pose(app)); title control exists \(shown), frame \(addButton.frame), hittable \(shown && addButton.isHittable), window \(window)"
        print("GameToGame: \(note)")
        XCTContext.runActivity(named: note) { _ in }
        XCTAssertTrue(shown, "the new game's page has its title block")
        XCTAssertTrue(shown && addButton.isHittable && window.intersects(addButton.frame),
                      "the new page opens at its top, not at the old page's scroll (blank until scrolled): \(note)")
        app.terminate()
    }

    /// bug-070 (Terry, 25 Nov): a game opened from another game's page ("View game", browseGame) goes back to that game, by the
    /// Back button and by the edge swipe, before the Library. Red on main: both landed on the Library.
    func testBackAndEdgeSwipeReturnToTheGameItWasOpenedFrom() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-qaRoute", "gamepage/dawnwalker"]
        app.launch()
        let back = app.descendants(matching: .any)["gameBack"]
        XCTAssertTrue(back.waitForExistence(timeout: 30), "the game page did not load")
        let pose = ReleaseRowTests.pose(app)
        if pose.contains("tabletop") { app.terminate(); throw XCTSkip("Tabletop's Back is on the lower rail; this walks the one-column page") }

        for way in ["Back button", "edge swipe"] {
            // Astro's Playroom: a PS5-index game, opened browsed exactly as View game opens it.
            app.open(URL(string: "playscribe://index-game/134597")!)
            XCTAssertTrue(app.buttons["addToLibrary"].waitForExistence(timeout: 10), "\(way): the second game did not open")
            XCTAssertEqual(back.label, "Back to The Blood of Dawnwalker", "\(way): Back should name the game it returns to")
            if way == "Back button" {
                back.tap()
            } else {
                // A steady drag at a set speed with a short hold at the end, not press-then-fling: on slow runners (25 Nov, #645 and
                // #646 heads) the fling left the page where it was while the same build passed on main (run 45583465960).
                let w = app.windows.firstMatch
                w.coordinate(withNormalizedOffset: CGVector(dx: 0.005, dy: 0.5))
                    .press(forDuration: 0.1, thenDragTo: w.coordinate(withNormalizedOffset: CGVector(dx: 0.85, dy: 0.5)),
                           withVelocity: 800, thenHoldForDuration: 0.2)
            }
            // Wait for the pop to finish rather than a fixed 2 s.
            let gone = XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == false"), object: app.buttons["addToLibrary"])
            _ = XCTWaiter().wait(for: [gone], timeout: 10)
            XCTAssertFalse(app.buttons["addToLibrary"].exists, "\(way): still on the second game")
            XCTAssertTrue(back.waitForExistence(timeout: 5), "\(way): left the games altogether (\(pose))")
            XCTAssertEqual(back.label, "Back to Library", "\(way): not back on Dawnwalker (\(pose))")
        }
        back.tap()
        XCTAssertFalse(back.waitForExistence(timeout: 3), "Back from the first game should leave for the Library")
        app.terminate()
    }
}
