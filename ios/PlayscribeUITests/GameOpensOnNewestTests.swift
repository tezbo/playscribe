import XCTest

/// bug-072 (Terry, 25 Nov): a game never reopens on the section it was left on (R-1). Open Dawnwalker on its Gallery, relaunch with
/// the saved state (no route), and the game shows What's new.
@MainActor
final class GameOpensOnNewestUITests: XCTestCase {
    func testRelaunchAfterGalleryShowsTheNewestUpdate() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-qaRoute", "gamepage/dawnwalker/gallery"]
        app.launch()
        let bar = app.descendants(matching: .any)["sectionBar"]
        XCTAssertTrue(bar.waitForExistence(timeout: 20), "the game page did not load")
        let gallery = bar.buttons["Gallery"]
        XCTAssertTrue(gallery.waitForExistence(timeout: 5), "the Gallery tab is missing")
        XCTAssertTrue(gallery.isSelected, "the route should open on Gallery")
        sleep(2)   // the save is debounced
        app.terminate()

        app.launchArguments = []
        app.launch()
        let bar2 = app.descendants(matching: .any)["sectionBar"]
        XCTAssertTrue(bar2.waitForExistence(timeout: 20), "the relaunch did not resume on the game page")
        let news = bar2.buttons["What’s new"]
        XCTAssertTrue(news.waitForExistence(timeout: 5), "the What's new tab is missing")
        XCTAssertTrue(news.isSelected, "the game reopened on the section it was left on")
        app.terminate()
    }
}
