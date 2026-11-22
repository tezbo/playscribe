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
}
