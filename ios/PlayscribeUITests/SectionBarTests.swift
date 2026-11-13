import XCTest

/// R-7 (0.5.6, Card C), spec acceptance 4: the section bar (the picker at accessibility sizes, the table of contents in Book) stays
/// on screen at every scroll position, in whatever pose the simulator is in. Blue Prince has the longest update list in the
/// fixtures, so the end of its What's new is far below the bar.
@MainActor
final class SectionBarTests: XCTestCase {
    func testBarStaysVisibleAtTheEndOfALongList() throws {
        let app = XCUIApplication()
        ReleaseRowTests.openBluePrince(app)
        let bar = app.descendants(matching: .any)["sectionBar"]
        XCTAssertTrue(bar.waitForExistence(timeout: 10), "section bar shown [\(ReleaseRowTests.pose(app))]")

        // Scroll the list itself to its end: the one-column page, or the Contents in Book and Tabletop.
        let page = app.scrollViews["pageScroll"], contents = app.scrollViews["contentsScroll"]
        let list = contents.exists && contents.isHittable ? contents : page
        XCTAssertTrue(list.exists, "a scrolling list")
        for _ in 0..<14 { list.swipeUp(velocity: .fast) }
        sleep(1)

        let window = app.windows.firstMatch.frame
        XCTAssertTrue(bar.exists, "bar still in the tree at the end of the list")
        XCTAssertTrue(window.contains(bar.frame), "bar on screen at the end: \(bar.frame) in \(window)")
        XCTAssertTrue(bar.buttons.firstMatch.isHittable, "a section is tappable at the end of the list [\(ReleaseRowTests.pose(app))]")
        let shot = XCTAttachment(screenshot: app.screenshot())
        shot.name = "section-bar-end [\(ReleaseRowTests.pose(app))]"; shot.lifetime = .keepAlways; add(shot)

        // Switching a section keeps the bar on screen and adds nothing to Back (Card D).
        let back = app.buttons["gameBack"]
        let backLabel = back.exists ? back.label : nil
        let news = bar.buttons["News"]
        if news.exists && news.isHittable {
            news.tap()
            sleep(1)
            XCTAssertTrue(bar.buttons.firstMatch.isHittable, "bar on screen after switching to News")
            if let backLabel { XCTAssertEqual(back.label, backLabel, "switching a section leaves Back as it was") }
        }
    }
}
