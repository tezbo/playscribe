import XCTest

/// G-4 (v0.5.3, #424): in Closed, a focused or filled Library search puts the update deck, News and the cards aside. They stay in the
/// view tree (removing them dropped the keyboard on the third key) but must expose nothing to VoiceOver and take no taps.
/// The accessibility hierarchy is what VoiceOver reads, so an empty `deckCard` query while searching is the check.
final class SearchAsideTests: XCTestCase {
    @MainActor
    func testClosedSearchHidesTheDeckFromAccessibilityAndReturnsOnClear() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-qaRoute", "two-update"]
        app.launch()
        let deck = app.descendants(matching: .any).matching(identifier: "deckCard")
        XCTAssertTrue(deck.firstMatch.waitForExistence(timeout: 10), "the deck shows before searching")
        let pose = ReleaseRowTests.pose(app)
        try XCTSkipUnless(pose.contains("pose: closed"), "the deck steps aside in Closed only (pose: \(pose))")

        let field = app.textFields["Search your library"].exists ? app.textFields["Search your library"] : app.textFields.firstMatch
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        field.tap()
        field.typeText("con")
        XCTAssertTrue(app.keyboards.firstMatch.waitForExistence(timeout: 5), "the keyboard is up")
        // Let the layout settle, then: nothing from the deck in the accessibility tree, and the keyboard is still up.
        sleep(1)
        if deck.count != 0 {
            let dump = XCTAttachment(string: app.debugDescription)
            dump.name = "deck-leak-tree.txt"
            dump.lifetime = .keepAlways
            add(dump)
        }
        XCTAssertEqual(deck.count, 0, "the deck is hidden from VoiceOver while searching")
        XCTAssertTrue(app.keyboards.firstMatch.exists, "typing did not drop the keyboard")

        let clear = app.buttons["Clear search"]
        XCTAssertTrue(clear.waitForExistence(timeout: 3))
        clear.tap()
        // The return key reads "Search" on the Duo simulator (Mac 6a2d5f1); accept the other labels so the test also runs elsewhere.
        let keys = app.keyboards.buttons
        let returnKey = ["Search", "search", "Return", "return"].map { keys[$0] }.first { $0.exists } ?? keys["Search"]
        returnKey.tap()
        XCTAssertTrue(deck.firstMatch.waitForExistence(timeout: 5), "the deck returns when the field is empty and unfocused")
    }
}

/// v0.5.3 (#424): a fast "control" in Closed once left the tile list blank and stuck (Mac 677e7eb, run 3 of 10). Types it ten times
/// and, when no tile shows, attaches the accessibility tree so the cause (no tile in the tree, or a tile with no frame) is readable.
final class SearchBlankListTests: XCTestCase {
    @MainActor
    func testFastControlNeverLeavesTheListBlank() throws { try fastControl(landscape: false) }

    /// r054: the same ten runs in Closed landscape, the case left to a hand check on the Duo until -qaOrientation (#627) let a
    /// test turn the outer display. A window that never turns fails plainly (OrientationGuard) rather than measuring portrait.
    @MainActor
    func testFastControlNeverLeavesTheListBlankInClosedLandscape() throws { try fastControl(landscape: true) }

    @MainActor
    private func fastControl(landscape: Bool) throws {
        let app = XCUIApplication()
        app.launchArguments = ["-qaRoute", "demo"] + (landscape ? ["-qaOrientation", "landscape"] : [])
        app.launch()
        if landscape {
            defer { XCUIDevice.shared.orientation = .portrait }
            guard app.require(.landscapeLeft) else { app.terminate(); return }
            try runFastControl(app, tag: "closed landscape")
            return
        }
        try runFastControl(app, tag: "closed")
    }

    @MainActor
    private func runFastControl(_ app: XCUIApplication, tag: String) throws {
        let pose = ReleaseRowTests.pose(app)
        try XCTSkipUnless(pose.contains("pose: closed"), "run in Closed (pose: \(pose))")
        let field = app.textFields["Search your library"].exists ? app.textFields["Search your library"] : app.textFields.firstMatch
        XCTAssertTrue(field.waitForExistence(timeout: 10))
        let tiles = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'tile-'"))
        for run in 1...10 {
            field.tap()
            field.typeText("control")
            sleep(2)
            if !tiles.firstMatch.exists {
                let dump = XCTAttachment(string: app.debugDescription)
                dump.name = "blank-list-\(tag.replacingOccurrences(of: " ", with: "-"))-run\(run)-tree.txt"
                dump.lifetime = .keepAlways
                add(dump)
                print("BLANKLIST run \(run)\n\(app.debugDescription)")
                XCTFail("\(tag) run \(run): no tile after typing 'control' (tree attached)")
                return
            }
            XCTAssertEqual(tiles.count, 1, "\(tag) run \(run): one match for 'control'")
            let clear = app.buttons["Clear search"]
            if clear.waitForExistence(timeout: 3) { clear.tap() }
            app.keyboards.buttons.matching(NSPredicate(format: "label IN {'Search','search','Return','return'}")).firstMatch.tap()
            sleep(1)
        }
    }

    /// The Library body's run count from its QA probe ("qa-library-body: N"), or 0 where the probe is absent.
    static func libraryBodyRuns(_ app: XCUIApplication) -> Int {
        let probe = app.descendants(matching: .any)["qaLibraryBody"]
        guard probe.exists else { return 0 }
        return Int(probe.label.split(separator: " ").last ?? "") ?? 0
    }

    /// r054-library-blank-list-fast-typing: 20 characters typed at speed (a match, then 13 that match nothing), the 13 deleted
    /// at speed, ten runs: the list is never left blank, "control" shows its one tile, and clearing brings back every tile.
    @MainActor
    func testTwentyFastCharactersThenClearRestoresEveryTile() throws { try twentyFast(landscape: false) }

    /// The same in Closed landscape, turned by -qaOrientation (#627): Quinn's failure there was in clearing (d194c511 still
    /// showed 1 tile after 1 s), which only the Duo hand check covered. A window that never turns fails plainly.
    @MainActor
    func testTwentyFastCharactersThenClearRestoresEveryTileInClosedLandscape() throws { try twentyFast(landscape: true) }

    @MainActor
    private func twentyFast(landscape: Bool) throws {
        let app = XCUIApplication()
        app.launchArguments = ["-qaRoute", "demo"] + (landscape ? ["-qaOrientation", "landscape"] : [])
        app.launch()
        defer { if landscape { XCUIDevice.shared.orientation = .portrait } }
        if landscape { guard app.require(.landscapeLeft) else { app.terminate(); return } }
        let pose = ReleaseRowTests.pose(app)
        // Closed (portrait and landscape) and Open portrait (Quinn on #624: the grid no longer rebuilt per query, proved outside Closed too).
        let openPortrait = pose.contains("pose: flat") && app.frame.height > app.frame.width
        try XCTSkipUnless(pose.contains("pose: closed") || openPortrait, "run in Closed or Open portrait (pose: \(pose))")
        let field = app.textFields["Search your library"].exists ? app.textFields["Search your library"] : app.textFields.firstMatch
        XCTAssertTrue(field.waitForExistence(timeout: 10))
        let tiles = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'tile-'"))
        XCTAssertTrue(tiles.firstMatch.waitForExistence(timeout: 10), "the Library shows tiles before searching")
        let all = tiles.count
        func blank(_ what: String, _ run: Int) {
            let dump = XCTAttachment(string: app.debugDescription)
            dump.name = "blank-list-\(what)-run\(run)-tree.txt"
            dump.lifetime = .keepAlways
            add(dump)
            XCTFail("run \(run): \(what) (tree attached)")
        }
        for run in 1...10 {
            let bodyBefore = Self.libraryBodyRuns(app)
            field.tap()
            field.typeText("controlqqqqqqqqqqqqq")   // 20 characters in one burst
            field.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: 13))
            // Mac d194c511: the tile took 3.4 to 6.3 s, because every key rewrote the saved state and rebuilt the grid. A player
            // waiting that long calls search broken, so a late tile fails: it must show within 1 s of the last key. The time and
            // the Library body runs for the 33 keys are recorded either way, so a slow run names its cost.
            let start = Date()
            let shown = tiles.firstMatch.waitForExistence(timeout: 1)
            let late = XCTAttachment(string: String(format: "run %d: tile after %.2f s, Library body runs %d", run,
                                                    Date().timeIntervalSince(start), Self.libraryBodyRuns(app) - bodyBefore))
            late.name = "fast-typing-run\(run)-time"; late.lifetime = .keepAlways; add(late)
            guard shown else { return blank("no tile 1 s after 'control' typed fast", run) }
            XCTAssertEqual(tiles.count, 1, "run \(run): one match for 'control'")
            let clear = app.buttons["Clear search"]
            XCTAssertTrue(clear.waitForExistence(timeout: 3), "run \(run): Clear search shows")
            clear.tap()
            app.keyboards.buttons.matching(NSPredicate(format: "label IN {'Search','search','Return','return'}")).firstMatch.tap()
            // Every tile within 1 s of clearing (Closed landscape at d194c511 still showed 1 after 1 s).
            let back = Date()
            while tiles.count != all && Date().timeIntervalSince(back) < 1 { usleep(100_000) }
            guard tiles.firstMatch.exists else { return blank("no tile after clearing", run) }
            XCTAssertEqual(tiles.count, all, "run \(run): clearing brings back every tile")
        }
    }
}
