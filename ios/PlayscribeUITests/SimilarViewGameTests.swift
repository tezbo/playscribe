import XCTest

/// Terry on beta 3 (real Duo, 22 Nov): "View game" in "You might also like" lagged, then showed a black screen until he
/// scrolled. Opening a game by URL from the end of a page drew at once (Mac 596b), so this takes his exact path: the end of a
/// game page, a tile, the confirmation dialog, "View game". It samples from the tap: when the new page's title block is on
/// screen and hittable, and how much of the screen is lit (a black frame is almost all dark). Every sample goes in the log.
@MainActor
final class SimilarViewGameTests: XCTestCase {
    func testViewGameFromYouMightAlsoLikeDrawsAtOnce() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-qaRoute", "gamepage/dawnwalker"]
        app.launch()
        sleep(4)
        if ReleaseRowTests.pose(app).contains("tabletop") { app.terminate(); throw XCTSkip("Tabletop's page is the lower panel") }
        let page = app.descendants(matching: .any)["pageScroll"].firstMatch
        guard page.waitForExistence(timeout: 5) else { app.terminate(); throw XCTSkip("no one-column page in this pose (Book)") }

        // The row loads with the game's basics from the live feed.
        let header = app.staticTexts["You might also like"].firstMatch
        var swipes = 0
        while !(header.exists && header.isHittable) && swipes < 14 { page.swipeUp(); swipes += 1 }
        guard header.exists else { app.terminate(); throw XCTSkip("no You might also like row (basics did not load)") }
        page.swipeUp()   // the tiles under the header into view
        sleep(1)
        let below = header.frame.maxY
        // Frame first: asking a far-off row whether it is hittable throws (Mac, Open portrait: "releaseRow-Launch activation point
        // invalid"), so only tile-sized buttons just under the header get that question.
        let tile = app.buttons.allElementsBoundByIndex.first {
            let f = $0.frame
            return f.minY >= below - 4 && f.minY < below + 60 && f.width >= 80 && f.width <= 140 && $0.isHittable
        }
        guard let tile else { app.terminate(); XCTFail("no tile under You might also like at y \(below)"); return }
        let name = tile.label
        tile.tap()
        let view = app.buttons["View game"].firstMatch
        XCTAssertTrue(view.waitForExistence(timeout: 3), "the dialog offers View game")

        let start = Date()
        view.tap()
        let tapped = Date().timeIntervalSince(start)
        let addButton = app.buttons["addToLibrary"]
        let pageMarker = app.staticTexts.matching(identifier: "qaPageScroll")
        var samples: [String] = []
        var titleAt: Double?, litAt: Double?
        var worst: XCUIScreenshot?
        while Date().timeIntervalSince(start) < 4 {
            let t = Date().timeIntervalSince(start)
            let shot = XCUIScreen.main.screenshot()
            let lit = Self.litFraction(shot.image)
            let shown = addButton.exists && addButton.isHittable
            if shown && titleAt == nil { titleAt = t }
            if lit >= 0.10 && litAt == nil { litAt = t }
            if lit < 0.10 && worst == nil { worst = shot }
            let pages = pageMarker.allElementsBoundByIndex.map(\.label).joined(separator: " / ")
            samples.append(String(format: "%.2fs lit %.3f title %@ ", t, lit, shown ? "yes" : "no") + pages)
        }
        for (label, s) in [("view-game-dark-frame", worst), ("view-game-final", XCUIScreen.main.screenshot())] {
            guard let s else { continue }
            let a = XCTAttachment(screenshot: s); a.name = label; a.lifetime = .keepAlways; add(a)
        }
        let black = HeroMarksTests.isBlack(XCUIScreen.main.screenshot().image)
        let note = "\(ReleaseRowTests.pose(app)); tile \(name); View game tap took \(String(format: "%.2f", tapped))s; title at \(titleAt.map { String(format: "%.2f", $0) } ?? "never"); lit at \(litAt.map { String(format: "%.2f", $0) } ?? "never"); screenshots black \(black)\n" + samples.joined(separator: "\n")
        print("SimilarViewGame: " + note.replacingOccurrences(of: "\n", with: " | "))
        XCTContext.runActivity(named: note) { _ in }
        XCTAssertNotNil(titleAt, "the new game's page shows its title block")
        XCTAssertLessThan(titleAt ?? 99, 1.0, "within a second of View game")
        if !black {   // the Mac's Open screenshots come back black; Closed reads pixels
            XCTAssertLessThan(litAt ?? 99, 1.0, "the page is drawn, not black, within a second")
        }
        app.terminate()
    }

    /// Share of sampled pixels brighter than the page ink (any channel above 60), every 6th pixel.
    static func litFraction(_ image: UIImage) -> Double {
        guard case let (bytes, w, h)? = HeroMarksTests.pixels(in: CGRect(origin: .zero, size: image.size), of: image) else { return 0 }
        var lit = 0, n = 0
        for y in stride(from: 0, to: h, by: 6) {
            for x in stride(from: 0, to: w, by: 6) {
                let i = (y * w + x) * 4
                if max(bytes[i], bytes[i + 1], bytes[i + 2]) > 60 { lit += 1 }
                n += 1
            }
        }
        return n == 0 ? 0 : Double(lit) / Double(n)
    }
}
