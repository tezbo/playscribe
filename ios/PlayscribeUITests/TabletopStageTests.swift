import XCTest

/// G-4 / TT-1 on the Companion section (Mac, 9cd4775-tabletop-std-companion-top.png): in Tabletop the standing half is a
/// view-only stage, so no element on it is a button. The stage's Companion card carried a hittable "Bookmark <entry>" glyph at
/// y 324 (std) and 364 (AX5). Bookmarking an entry in Tabletop is the rail's Bookmarks menu, in the lower half (design, #521).
/// Skips outside Tabletop.
@MainActor
final class TabletopStageTests: XCTestCase {
    func testCompanionStageHasNothingTappableAboveTheFold() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-qaRoute", "chapter/dawnwalker/companion"]
        app.launch()
        let audit = app.descendants(matching: .any)["foldAudit"]
        XCTAssertTrue(audit.waitForExistence(timeout: 10), "fold audit present")
        guard audit.label.contains("pose: tabletop") else { throw XCTSkip("Tabletop only [\(audit.label)]") }
        sleep(2)
        let half = app.frame.midY
        let tappable = app.buttons.allElementsBoundByIndex + app.cells.allElementsBoundByIndex
            + app.switches.allElementsBoundByIndex + app.textFields.allElementsBoundByIndex
        for e in tappable where e.exists && e.isHittable && !e.frame.isEmpty {
            XCTAssertGreaterThanOrEqual(e.frame.minY, half - 1, "'\(e.label)' is tappable above the fold in Tabletop Companion at \(e.frame)")
        }
        // The lower half carries bookmarking: the rail's Bookmarks menu lists the entries the stage shows.
        let menu = app.buttons["Bookmarks"]
        XCTAssertTrue(menu.waitForExistence(timeout: 5) && menu.isHittable, "Bookmarks on the rail")
        XCTAssertGreaterThanOrEqual(menu.frame.minY, half - 1, "Bookmarks is in the lower half")
        let shot = XCTAttachment(screenshot: app.screenshot())
        shot.name = "tabletop-companion-top"; shot.lifetime = .keepAlways; add(shot)
    }
}
