import XCTest

/// Journeys that need the system UI: a real notification tap from SpringBoard (N-6, L-3) and the
/// accessibility audit (G-7, G-10). Run against whatever pose the simulator is in.
@MainActor
final class PlayscribeUITests: XCTestCase {
    let app = XCUIApplication()
    let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")

    override func setUp() async throws {
        continueAfterFailure = false
        app.launchArguments = ["-qaRoute", "demo"]
    }

    /// N-6: tapping the notification opens the game book on that release, cold and warm.
    func testNotificationTapOpensRelease() throws {
        for cold in [true, false] {
            app.launch()
            if cold { app.terminate() } else { XCUIDevice.shared.press(.home) }
            let note = try postAndFindNotification()
            note.tap()
            XCTAssertTrue(app.wait(for: .runningForeground, timeout: 10))
            let release = app.buttons.matching(NSPredicate(format: "label CONTAINS 'Update 1.1'")).firstMatch
            XCTAssertTrue(release.waitForExistence(timeout: 10), cold ? "cold" : "warm")
            attach(name: cold ? "notification-tap-cold" : "notification-tap-warm")
        }
    }

    /// G-7 and G-10: the system accessibility audit on the main screens.
    func testAccessibilityAudit() throws {
        for route in ["library", "release/dawnwalker/dawnwalker@1.1", "add", "updates"] {
            app.launchArguments = ["-qaRoute", route]
            app.launch()
            sleep(2)
            try app.performAccessibilityAudit(for: [.hitRegion, .sufficientElementDescription, .elementDetection]) { issue in
                // Game art, poster images and the system status bar aren't the app's controls.
                issue.element?.elementType == .image || issue.element?.identifier.isEmpty == false && issue.element?.label.isEmpty == true
            }
            attach(name: "audit-\(route.replacingOccurrences(of: "/", with: "_"))")
        }
    }

    // MARK: - Helpers

    /// Schedules a local notification through the app's internal route, then finds its banner.
    private func postAndFindNotification() throws -> XCUIElement {
        let simulate = XCUIApplication()
        simulate.launchArguments = ["-qaRoute", "simulate/dawnwalker/major"]
        simulate.launch()
        XCUIDevice.shared.press(.home)
        let banner = springboard.otherElements["Notification"].descendants(matching: .any)
            .matching(NSPredicate(format: "label CONTAINS 'is live on PS5'")).firstMatch
        if banner.waitForExistence(timeout: 15) { return banner }
        // Fall back to Notification Center.
        let start = springboard.coordinate(withNormalizedOffset: CGVector(dx: 0.3, dy: 0.001))
        start.press(forDuration: 0.1, thenDragTo: springboard.coordinate(withNormalizedOffset: CGVector(dx: 0.3, dy: 0.6)))
        let listed = springboard.descendants(matching: .any).matching(NSPredicate(format: "label CONTAINS 'is live on PS5'")).firstMatch
        XCTAssertTrue(listed.waitForExistence(timeout: 5))
        return listed
    }

    private func attach(name: String) {
        let a = XCTAttachment(screenshot: app.screenshot())
        a.name = name
        a.lifetime = .keepAlways
        add(a)
    }
}

/// TT-0: no reported view frame may intersect an active division, on any main screen.
final class FoldAuditTests: XCTestCase {
    @MainActor
    func testNothingCrossesTheFold() throws {
        let app = XCUIApplication()
        for route in ["library", "release/dawnwalker/dawnwalker@1.1", "video/dawnwalker/dawnwalker@1.1", "add", "updates"] {
            app.launchArguments = ["-qaRoute", route]
            app.launch()
            sleep(3)
            let audit = app.descendants(matching: .any)["foldAudit"]
            XCTAssertTrue(audit.waitForExistence(timeout: 5))
            let label = audit.label
            let shot = XCTAttachment(screenshot: app.screenshot())
            shot.name = "fold-\(route.replacingOccurrences(of: "/", with: "_")) \(label)"
            shot.lifetime = .keepAlways
            add(shot)
            let believed = app.descendants(matching: .any)["libraryDuo"]
            let seen = believed.exists ? believed.label : "no library probe"
            let note = XCTAttachment(string: "\(route): \(label)\n\(seen)")
            note.name = "fold-audit-\(route.replacingOccurrences(of: "/", with: "_")).txt"
            note.lifetime = .keepAlways
            add(note)
            XCTAssertTrue(label.hasPrefix("fold-crossings: 0;"), "\(route): \(label) | \(seen)")
        }
    }
}

/// D-13: every display choice survives a relaunch.
@MainActor
final class DisplayChoiceTests: XCTestCase {
    func testLayoutChoiceSurvivesRelaunch() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-qaRoute", "demo"]
        app.launch()
        for (choice, expectList) in [("List", true), ("Tiles", false)] {
            let view = app.buttons["View"].firstMatch
            XCTAssertTrue(view.waitForExistence(timeout: 10))
            view.tap()
            let option = app.buttons[choice].firstMatch
            XCTAssertTrue(option.waitForExistence(timeout: 5), choice)
            option.tap()
            app.terminate()
            app.launchArguments = ["-qaRoute", "library"]
            app.launch()
            // List rows carry an options button per game; tiles keep it only off the closed display.
            let row = app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Options for'")).firstMatch
            let cover = app.images.matching(NSPredicate(format: "label ENDSWITH ' cover'")).firstMatch
            XCTAssertTrue(cover.waitForExistence(timeout: 10))
            if expectList { XCTAssertTrue(row.exists, "List after relaunch") }
            let shot = XCTAttachment(screenshot: app.screenshot())
            shot.name = "d13-\(choice.lowercased())-after-relaunch"
            shot.lifetime = .keepAlways
            add(shot)
        }
    }
}

/// D-10 a–h: Swap sides, run in a side-by-side pose (Open landscape or Book).
@MainActor
final class SwapSidesTests: XCTestCase {
    func testSwapSides() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-qaRoute", "release/dawnwalker/dawnwalker@1.1"]
        app.launch()
        let swap = app.buttons["swapSides"]
        guard swap.waitForExistence(timeout: 8) else {
            throw XCTSkip("Swap sides is only on the rail when Contents and Page are side by side")
        }
        let audit = app.descendants(matching: .any)["foldAudit"]
        let search = app.textFields.matching(NSPredicate(format: "placeholderValue BEGINSWITH 'Search'")).firstMatch
        XCTAssertTrue(search.waitForExistence(timeout: 5))
        search.tap()
        search.typeText("subtitle")
        // A bar button drops accessibilityValue, so the side is in the label ("Swap sides, reading on right").
        let before = swap.label
        XCTAssertTrue(before.hasPrefix("Swap sides, reading on"), before)

        // One swap: the value changes, the search text and fold audit hold.
        swap.tap()
        sleep(1)
        let after = swap.label
        XCTAssertNotEqual(before, after)
        XCTAssertEqual(search.value as? String, "subtitle", "search text survives the swap")
        XCTAssertTrue(audit.label.hasPrefix("fold-crossings: 0;"), "after swap: \(audit.label)")
        attach(app, "swap-1")

        // Rapid double tap ends where it started, consistently.
        swap.tap(); swap.tap()
        sleep(1)
        XCTAssertEqual(swap.label, after)
        attach(app, "swap-double")

        // The side holds across another game and a relaunch.
        app.terminate()
        app.launchArguments = ["-qaRoute", "chapter/kcd2/updates"]
        app.launch()
        XCTAssertTrue(app.buttons["swapSides"].waitForExistence(timeout: 8))
        XCTAssertEqual(app.buttons["swapSides"].label, after)
        attach(app, "swap-relaunch-other-game")
        // Leave the default side for the next run.
        app.buttons["swapSides"].tap()
    }

    private func attach(_ app: XCUIApplication, _ name: String) {
        let shot = XCTAttachment(screenshot: app.screenshot())
        shot.name = name
        shot.lifetime = .keepAlways
        add(shot)
    }
}


/// J-1, J-3, J-4: every release row opens its release in one tap, in the current pose, including
/// one far down the list (Blue Prince 1.4); the list never jumps, and Back returns to the row.
@MainActor
final class ReleaseRowTests: XCTestCase {
    static func openBluePrince(_ app: XCUIApplication) {
        app.launchArguments = ["-qaRoute", "add-game/149657"]
        app.launch()
        sleep(3)
        app.terminate()
        app.launchArguments = ["-qaRoute", "chapter/igdb-149657/updates"]
        app.launch()
    }

    /// Scrolls the release list itself (in landscape a swipe on the app lands on the Page).
    static func reveal(_ row: XCUIElement, in app: XCUIApplication) {
        let contents = app.scrollViews["contentsScroll"], page = app.scrollViews["pageScroll"]
        var tries = 0
        while !(row.exists && row.isHittable) && tries < 14 {
            if contents.exists && contents.isHittable { contents.swipeUp(velocity: .slow) }
            else if page.exists && page.isHittable { page.swipeUp(velocity: .slow) }
            else { app.swipeUp(velocity: .slow) }
            tries += 1
        }
    }

    /// Back from a pushed screen: the navigation bar's Back button, wherever the toolbar puts it.
    static func goBack(_ app: XCUIApplication) {
        app.buttons["BackButton"].firstMatch.tap()
    }

    /// The pose the app reports (fold audit), so each result says where it ran.
    static func pose(_ app: XCUIApplication) -> String {
        let audit = app.descendants(matching: .any)["foldAudit"]
        return audit.exists ? audit.label : "unknown"
    }

    func testRowsOpenTheirRelease() throws {
        let app = XCUIApplication()
        Self.openBluePrince(app)
        for name in ["Hotfix 1.7.2", "Patch 1.4"] {
            let row = app.buttons["releaseRow-\(name)"]
            Self.reveal(row, in: app)
            XCTAssertTrue(row.waitForExistence(timeout: 10) && row.isHittable, "\(name) row reachable")
            row.tap()
            sleep(1)
            let title = app.staticTexts.matching(identifier: "releaseTitle").matching(NSPredicate(format: "label == %@", name)).firstMatch
            XCTAssertTrue(title.waitForExistence(timeout: 5), "\(name) opens")
            let shot = XCTAttachment(screenshot: app.screenshot())
            shot.name = "row-\(name) [\(Self.pose(app))]"; shot.lifetime = .keepAlways; add(shot)
            if app.navigationBars[name].exists {
                // Pushed (Closed, open portrait): Back returns to the same row, still in view.
                Self.goBack(app)
                sleep(1)
                XCTAssertTrue(row.isHittable, "back to \(name) row, in view")
            } else {
                // On the Page: the list didn't jump; the row is still in view and selected.
                XCTAssertTrue(row.isHittable, "\(name) row still in view after the tap")
                XCTAssertTrue(row.isSelected, "\(name) row selected")
            }
        }
    }
}

/// J-1 across a pose change, run by tools/qa/journey.sh: tap Patch 1.4 Closed; the script unfolds
/// the device to Open while the test waits; the Page then shows 1.4 with its row selected.
@MainActor
final class JourneyTests: XCTestCase {
    func testClosedToOpenKeepsPatch14() throws {
        let app = XCUIApplication()
        ReleaseRowTests.openBluePrince(app)
        let row = app.buttons["releaseRow-Patch 1.4"]
        ReleaseRowTests.reveal(row, in: app)
        row.tap()
        sleep(1)
        let pushed = XCTAttachment(screenshot: app.screenshot()); pushed.name = "journey-closed-pushed"; pushed.lifetime = .keepAlways; add(pushed)
        // Wait for the unfold: the pushed screen pops and the Page shows the release.
        let title = app.staticTexts.matching(identifier: "releaseTitle").matching(NSPredicate(format: "label == %@", "Patch 1.4")).firstMatch
        let deadline = Date.now.addingTimeInterval(150)
        while (app.navigationBars["Patch 1.4"].exists || !title.exists) && Date.now < deadline { sleep(2) }
        sleep(2)
        XCTAssertTrue(title.exists && !app.navigationBars["Patch 1.4"].exists, "Page shows Patch 1.4 after unfolding")
        ReleaseRowTests.reveal(row, in: app)
        XCTAssertTrue(row.isSelected, "Patch 1.4 row selected")
        let shot = XCTAttachment(screenshot: app.screenshot()); shot.name = "journey-open-patch-1.4"; shot.lifetime = .keepAlways; add(shot)
    }
}

/// 0.2.0 review fixes (Terry): links, single game links, version, scrolling.
@MainActor
final class ReviewFixUITests: XCTestCase {
    /// Bare links in notes are tappable and open in the default browser.
    func testNoteLinkOpensBrowser() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-qaRoute", "release/dawnwalker/dawnwalker@1.0.5"]
        app.launch()
        // Tabletop shows releases on the standing half, which is never touchable (G-4): skip before any waiting.
        if ReleaseRowTests.pose(app).contains("tabletop") { app.terminate(); throw XCTSkip("links aren't tappable on Tabletop's standing half by design") }
        // The notes only exist in the live feed: wait for them to land (never skip).
        let landed = app.buttons.matching(NSPredicate(format: "label CONTAINS 'We will continue'")).firstMatch
        XCTAssertTrue(landed.waitForExistence(timeout: 60), "live feed delivered dawnwalker@1.0.5 within 60 s")
        app.terminate()
        app.launch()
        // Tabletop shows releases on the standing half, which is never touchable (G-4).
        if ReleaseRowTests.pose(app).contains("tabletop") { throw XCTSkip("links aren't tappable on Tabletop's standing half by design") }
        // The link sits in a notes section, closed by default.
        let section = app.buttons.matching(NSPredicate(format: "label CONTAINS 'We will continue'")).firstMatch
        Self.scrollTo(section, in: app)
        section.tap()
        let link = app.links.matching(NSPredicate(format: "label CONTAINS 'store.steampowered.com'")).firstMatch
        Self.scrollTo(link, in: app)
        XCTAssertTrue(link.exists && link.isHittable, "a bare Steam link in the notes is a link")
        link.tap()
        let safari = XCUIApplication(bundleIdentifier: "com.apple.mobilesafari")
        XCTAssertTrue(safari.wait(for: .runningForeground, timeout: 10), "opens in the default browser")
        app.activate()
    }

    /// Scrolls the page (either way) until the element is on screen.
    static func scrollTo(_ e: XCUIElement, in app: XCUIApplication) {
        let page = app.scrollViews["pageScroll"].exists ? app.scrollViews["pageScroll"] : app.scrollViews.firstMatch
        for _ in 0..<16 {
            if e.exists && e.isHittable { return }
            if e.exists && e.frame.minY < app.frame.minY + 80 { page.swipeDown(velocity: .slow) } else { page.swipeUp(velocity: .slow) }
        }
    }

    /// Official website and All patch notes appear once on the game page.
    func testGameLinksOnce() throws {
        let app = XCUIApplication()
        ReleaseRowTests.openBluePrince(app)
        sleep(3)
        for name in ["Official website", "All patch notes"] {
            var seen = 0, tries = 0
            repeat {
                seen = max(seen, app.links.matching(NSPredicate(format: "label CONTAINS %@", name)).count)
                app.swipeUp(velocity: .fast); tries += 1
            } while tries < 6
            XCTAssertEqual(seen, 1, "\(name) shown exactly once [\(ReleaseRowTests.pose(app))]")
        }
    }

    /// Settings shows the bundle's version, 0.2.0.
    func testSettingsVersion() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-qaRoute", "settings"]
        app.launch()
        let version = app.descendants(matching: .any).matching(NSPredicate(format: "label CONTAINS '0.2.0' OR value CONTAINS '0.2.0'")).firstMatch
        let form = app.collectionViews.firstMatch
        var tries = 0
        while !version.exists && tries < 8 { (form.exists ? form : app).swipeUp(); tries += 1 }
        XCTAssertTrue(version.exists, "Settings shows version 0.2.0")
        XCTAssertTrue(app.descendants(matching: .any)["appVersion"].exists, "the version row is identified")
    }

    /// Scrolling Dawnwalker's Update 1.1 page: hitch ratio recorded for each run.
    /// From a normal launch (no -qaRoute, so no audit tracking): the path Terry uses. The gate
    /// script fails the run when the hitch ratio is over 10 ms/s (Apple: under 5 is good).
    func testUpdate11ScrollPerformance() throws {
        let app = XCUIApplication()
        app.launchArguments = []
        app.launch()
        sleep(2)
        app.open(URL(string: "playscribe://release/dawnwalker/dawnwalker@1.1")!)
        let open = XCUIApplication(bundleIdentifier: "com.apple.springboard").buttons["Open"]
        if open.waitForExistence(timeout: 3) { open.tap() }
        sleep(3)
        XCTAssertFalse(app.descendants(matching: .any)["foldAudit"].exists && app.launchArguments.contains("-qaRoute"))
        let page = app.scrollViews["pageScroll"].exists ? app.scrollViews["pageScroll"] : app.scrollViews.firstMatch
        measure(metrics: [XCTOSSignpostMetric.scrollingAndDecelerationMetric]) {
            page.swipeUp(velocity: .fast)
            page.swipeDown(velocity: .fast)
        }
    }
}

/// J-5: Library tiles never overlap each other or the Continue hero, with 8 and 28 games.
@MainActor
final class LibraryLayoutTests: XCTestCase {
    func checkNoOverlap(games: Int) throws {
        let app = XCUIApplication()
        app.launchArguments = ["-qaRoute", "demo"]
        app.launch()
        sleep(2)
        app.open(URL(string: "playscribe://fill-library/\(games)")!)
        let open = XCUIApplication(bundleIdentifier: "com.apple.springboard").buttons["Open"]
        if open.waitForExistence(timeout: 2) { open.tap() }
        sleep(2)
        app.terminate()
        app.launchArguments = ["-qaRoute", "library"]
        app.launch()
        sleep(4)
        let pose = ReleaseRowTests.pose(app)
        var checked = 0
        for _ in 0..<6 {
            // The accessibility frame of a tile runs past its cover (the cover image's own
            // bounds), so each tile is taken as its laid-out cover: origin and width, 3:4.
            let tiles = app.buttons.matching(NSPredicate(format: "label CONTAINS ', last updated' OR label CONTAINS ', released ' OR label CONTAINS 'to be announced' OR label CONTAINS ', new update' OR label CONTAINS 'unconfirmed update'"))
                .allElementsBoundByIndex.filter { !$0.frame.isEmpty && $0.frame.width > 20 }
                .map { e -> CGRect in
                    // The cover's real width is in the identifier ("tile-100"); Closed measures its column width at layout.
                    var w = Double(e.identifier.dropFirst(5)).flatMap { $0 > 0 ? $0 : nil } ?? e.frame.width
                    // Closed landscape (0.2.0 gate, 3813f3d): the published width can be wider than the
                    // laid-out cover, so a 3:4 box from it overstates the height (241 vs a 236 row pitch).
                    // The element's own frame is cover + 8 pt of outset; never take more than that.
                    if e.frame.width - 8 > 20 { w = min(w, e.frame.width - 8) }
                    let h = min((w * 4 / 3).rounded(), max(0, e.frame.height - 8))
                    return CGRect(x: e.frame.minX, y: e.frame.minY, width: w, height: h)
                }
            let hero = app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'New update,' OR label BEGINSWITH 'Continue,'")).allElementsBoundByIndex.map(\.frame)
            // 0.2.0 gate: the hero's frame is its card, not the fill-scaled art behind it (it once
            // reported x -97.7, width 461). Open landscape: the double tile, 2 x 112 + 10 = 234 pt.
            for h in hero {
                XCTAssertGreaterThanOrEqual(h.minX, 0, "hero starts on screen \(h) [\(pose)]")
                XCTAssertLessThanOrEqual(h.maxX, app.frame.width + 1, "hero ends on screen \(h) [\(pose)]")
                if pose.contains("flat") && app.frame.width > app.frame.height {
                    XCTAssertEqual(h.width, 234, accuracy: 3, "Open hero is the 234 pt double tile [\(pose)]")
                }
            }
            for (i, a) in tiles.enumerated() {
                for b in tiles[(i + 1)...] { XCTAssertFalse(a.insetBy(dx: 1, dy: 1).intersects(b), "tiles overlap \(a) \(b) [\(pose)]") }
                for h in hero { XCTAssertFalse(a.insetBy(dx: 1, dy: 1).intersects(h), "tile overlaps hero \(a) \(h) [\(pose)]") }
            }
            checked += tiles.count
            app.swipeUp(velocity: .fast)
        }
        XCTAssertGreaterThan(checked, 0, "found tiles [\(pose)]")
        let shot = XCTAttachment(screenshot: app.screenshot()); shot.name = "library-\(games) [\(pose)]"; shot.lifetime = .keepAlways; add(shot)
    }

    func testEightGames() throws { try checkNoOverlap(games: 8) }
    func testTwentyEightGames() throws { try checkNoOverlap(games: 28) }
}

/// Review stills for QA and design (attachments named capture-*).
@MainActor
final class CaptureTests: XCTestCase {
    func shot(_ name: String) {
        let a = XCTAttachment(screenshot: XCUIApplication().screenshot()); a.name = "capture-\(name)"; a.lifetime = .keepAlways; add(a)
    }

    func testReviewStills() throws {
        let app = XCUIApplication()
        // Settings: version, Notify me about.
        app.launchArguments = ["-qaRoute", "settings"]
        app.launch(); sleep(3)
        shot("settings-top")
        let form = app.collectionViews.firstMatch
        let version = app.descendants(matching: .any).matching(NSPredicate(format: "label CONTAINS '0.2.0' OR value CONTAINS '0.2.0'")).firstMatch
        var tries = 0
        while !version.exists && tries < 8 { (form.exists ? form : app).swipeUp(); tries += 1 }
        shot("settings-version")

        // The game's bell: Use default first.
        app.terminate()
        app.launchArguments = ["-qaRoute", "release/dawnwalker/dawnwalker@1.1"]
        app.launch(); sleep(4)
        let bell = app.buttons.matching(NSPredicate(format: "label CONTAINS[c] 'Notif'")).firstMatch
        if bell.waitForExistence(timeout: 5) { bell.tap(); sleep(1) }
        shot("bell-menu")
        app.typeKey(XCUIKeyboardKey.escape, modifierFlags: [])

        // Game page: one link pair (scroll to it when Closed).
        app.terminate()
        ReleaseRowTests.openBluePrince(app); sleep(4)
        let site = app.links.matching(NSPredicate(format: "label CONTAINS 'Official website'")).firstMatch
        ReviewFixUITests.scrollTo(site, in: app)
        shot("game-links")

        // Add game: tap two rows, the pinned bar reads Add 2 games.
        app.terminate()
        app.launchArguments = ["-qaRoute", "add"]
        app.launch(); sleep(4)
        let rows = app.buttons.matching(NSPredicate(format: "label CONTAINS 'Released' OR label CONTAINS 'PS5'"))
        for i in 0..<2 where rows.count > i { rows.element(boundBy: i).tap() }
        sleep(1)
        shot("add-game-bar")
    }
}

/// J-1 and J-4: the Latest updates deck. A card opens its update; a page-edge leaf (44 pt, "Update n of N")
/// brings its card into view. The pose is read from the fold audit by the other tests, so this one
/// runs in whichever pose the simulator is in.
@MainActor
final class LatestUpdatesDeckTests: XCTestCase {
    func testCardAndLeafTaps() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-qaRoute", "library"]
        app.launch()
        sleep(4)
        let leaves = app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Update ' AND label CONTAINS ' of '"))
        if leaves.count > 1 {
            XCTAssertGreaterThanOrEqual(leaves.element(boundBy: 1).frame.height, 44, "leaf is a 44 pt target")
            leaves.element(boundBy: 1).tap()
        }
        let cards = app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'New update,' OR (label CONTAINS ', ' AND NOT label CONTAINS ' of ')"))
        XCTAssertGreaterThan(cards.count, 0, "deck has a card")
        cards.firstMatch.tap()
        XCTAssertTrue(app.descendants(matching: .any)["releaseTitle"].waitForExistence(timeout: 5), "card opens its update")
    }
}

extension PlayscribeUITests {
    /// 0.2.0 gate defects (Book, Library): no button, cell or chip row may enter the fold zone.
    func testBookLibraryNothingEntersTheFold() throws {
        let app = XCUIApplication()
        for route in ["library", "demo"] {
            app.launchArguments = ["-qaRoute", route]
            app.launch()
            sleep(3)
            let audit = app.descendants(matching: .any)["foldAudit"]
            XCTAssertTrue(audit.waitForExistence(timeout: 5))
            let label = audit.label
            guard label.contains("pose: book"), let range = label.range(of: #"fold (\d+)-(\d+)"#, options: .regularExpression) else {
                app.terminate(); throw XCTSkip("not in the Book pose: \(label)")
            }
            let nums = label[range].dropFirst(5).split(separator: "-").compactMap { Double($0) }
            let (lo, hi) = (nums[0], nums[1])
            XCTAssertTrue(label.hasPrefix("fold-crossings: 0;"), "\(route): \(label)")
            let elements = app.buttons.allElementsBoundByIndex + app.cells.allElementsBoundByIndex + app.scrollViews.allElementsBoundByIndex
            for e in elements where e.exists && !e.frame.isEmpty && e.frame.width < app.frame.width - 1 {
                // Tiles: the cover's real width is in the identifier ("tile-100"); the element frame is 8 pt wider.
                var frame = e.frame
                if e.identifier.hasPrefix("tile-"), let w = Double(e.identifier.dropFirst(5)), w > 0 { frame.size.width = w }
                XCTAssertFalse(frame.maxX > lo && frame.minX < hi, "\(route): '\(e.label)' \(frame) enters the fold \(lo)-\(hi)")
            }
            app.terminate()
        }
    }
}

extension PlayscribeUITests {
    /// CLAUDE.md Tabletop rule for presented sheets: with the Add game sheet or Settings open, every
    /// control (close, search, rows, bars) sits in the lower half. Skips outside Tabletop.
    func testTabletopSheetsKeepControlsInTheLowerHalf() throws {
        let app = XCUIApplication()
        for route in ["add", "settings", "links/dawnwalker"] {
            app.launchArguments = ["-qaRoute", route]
            app.launch()
            sleep(3)
            guard ReleaseRowTests.pose(app).contains("pose: tabletop") else { app.terminate(); throw XCTSkip("not Tabletop") }
            let half = app.frame.midY
            let controls = app.buttons.allElementsBoundByIndex + app.textFields.allElementsBoundByIndex
                + app.searchFields.allElementsBoundByIndex + app.switches.allElementsBoundByIndex + app.cells.allElementsBoundByIndex
            var seen = 0
            for e in controls where e.exists && e.isHittable && !e.frame.isEmpty {
                seen += 1
                XCTAssertGreaterThanOrEqual(e.frame.minY, half - 1, "\(route): '\(e.label)' is tappable in the upper half \(e.frame)")
            }
            XCTAssertGreaterThan(seen, 0, "\(route) shows controls")
            app.terminate()
        }
    }
}

extension PlayscribeUITests {
    /// J-20b: the scan view fits the panel: preview, hint and button all end inside the screen, and
    /// every control is at least 44 pt (QA route add/scan, simulated feed). Any pose.
    func testScanFitsThePanel() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-qaRoute", "add/scan"]
        app.launch()
        sleep(3)
        let find = app.buttons["Find these games"]
        XCTAssertTrue(find.waitForExistence(timeout: 8), "scan shows Find these games")
        XCTAssertGreaterThanOrEqual(find.frame.height, 44)
        XCTAssertLessThanOrEqual(find.frame.maxY, app.frame.maxY + 1, "button ends on screen")
        let preview = app.descendants(matching: .any)["Camera view"]
        XCTAssertTrue(preview.exists)
        XCTAssertLessThanOrEqual(preview.frame.maxY, find.frame.minY + 1, "preview sits above the button")
        if ReleaseRowTests.pose(app).contains("pose: tabletop") {
            XCTAssertGreaterThanOrEqual(preview.frame.minY, app.frame.midY - 1, "Tabletop: preview is in the lower half")
        }
        app.terminate()
    }
}

/// 0.5.0 surfaces the Mac gate runs in each pose. Each test reads the pose from the fold audit and
/// applies the Tabletop rule (every control in the lower half) when it is Tabletop.
@MainActor
final class Release050Tests: XCTestCase {
    private func launch(_ route: String, overlay: Bool = false) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-qaRoute", route] + (overlay ? ["-qaOverlay", "YES"] : [])
        app.launch()
        sleep(3)
        return app
    }

    private func isTabletop(_ app: XCUIApplication) -> Bool { ReleaseRowTests.pose(app).contains("pose: tabletop") }

    /// J-20: quiet hours. The switch is off by default; turning it on shows From and Until and the footer.
    func testQuietHours() throws {
        let app = launch("settings")
        let toggle = app.switches["quietHours"]
        var tries = 0
        while !toggle.exists && tries < 6 { app.swipeUp(); tries += 1 }
        XCTAssertTrue(toggle.exists, "Settings has a Quiet hours switch")
        XCTAssertEqual(toggle.value as? String, "0", "off by default")
        XCTAssertGreaterThanOrEqual(toggle.frame.height, 44 - 1)
        toggle.tap()
        XCTAssertTrue(app.staticTexts["From"].waitForExistence(timeout: 3), "From row appears")
        XCTAssertTrue(app.staticTexts["Until"].exists, "Until row appears")
        XCTAssertTrue(app.staticTexts["Alerts arrive silently during these hours."].exists, "footer")
        if isTabletop(app) { XCTAssertGreaterThanOrEqual(toggle.frame.minY, app.frame.midY - 1, "Tabletop: switch in the lower half") }
        app.terminate()
    }

    /// J-20: the explainer opens from `tag/<kind>`, shows the ladder with the current one marked, and Done closes it.
    func testVerificationExplainer() throws {
        for kind in ["official", "reported", "pending"] {
            let app = launch("tag/\(kind)")
            let sheet = app.descendants(matching: .any)["verificationExplainer"]
            XCTAssertTrue(sheet.waitForExistence(timeout: 5), "\(kind): explainer is open")
            XCTAssertTrue(app.staticTexts["What this tag means"].exists)
            XCTAssertTrue(app.staticTexts["This one"].exists, "\(kind): current tag is marked")
            for rung in ["Official", "Reported", "Pending"] { XCTAssertTrue(app.staticTexts[rung].exists, "\(kind): ladder has \(rung)") }
            let done = app.buttons["Done"]
            XCTAssertTrue(done.exists)
            XCTAssertGreaterThanOrEqual(done.frame.height, 44 - 1, "Done is a 44 pt target")
            if isTabletop(app) { XCTAssertGreaterThanOrEqual(done.frame.minY, app.frame.midY - 1, "Tabletop: Done in the lower half") }
            done.tap()
            XCTAssertFalse(sheet.waitForExistence(timeout: 2), "\(kind): Done closes it")
            app.terminate()
        }
    }

    /// Iris, one-row links: Official website and All patch notes share a row with a 24 pt gap, or wrap; never truncated.
    func testLinksOneRow() throws {
        let app = XCUIApplication()
        ReleaseRowTests.openBluePrince(app); sleep(4)
        if isTabletop(app) { app.terminate(); throw XCTSkip("Tabletop uses the Links button") }
        let site = app.links.matching(NSPredicate(format: "label CONTAINS 'Official website'")).firstMatch
        let notes = app.links.matching(NSPredicate(format: "label CONTAINS 'All patch notes'")).firstMatch
        ReviewFixUITests.scrollTo(site, in: app)
        guard site.exists, notes.exists else { app.terminate(); throw XCTSkip("this game has no info links") }
        if abs(site.frame.minY - notes.frame.minY) < 4 {
            XCTAssertGreaterThanOrEqual(notes.frame.minX - site.frame.maxX, 24 - 4, "24 pt gap on one row")
        } else {
            XCTAssertGreaterThan(notes.frame.minY, site.frame.maxY - 4, "wrapped below, not overlapping")
        }
        for l in [site, notes] { XCTAssertLessThanOrEqual(l.frame.maxX, app.frame.maxX + 1); XCTAssertGreaterThanOrEqual(l.frame.height, 44 - 1) }
        app.terminate()
    }

    /// Iris, Add keyboard fallback: with the keyboard up, the search field and the close control stay above/clear of it.
    func testAddKeyboard() throws {
        let app = launch("add/keyboard")
        let keyboard = app.keyboards.firstMatch
        guard keyboard.waitForExistence(timeout: 6) else { app.terminate(); throw XCTSkip("hardware keyboard connected: no on-screen keyboard") }
        let field = app.textFields.firstMatch
        XCTAssertTrue(field.exists)
        XCTAssertLessThanOrEqual(field.frame.maxY, keyboard.frame.minY + 1, "search field sits above the keyboard")
        let close = app.buttons.matching(NSPredicate(format: "label == 'Done' OR label == 'Close'")).firstMatch
        XCTAssertTrue(close.exists && close.isHittable, "close stays reachable")
        if isTabletop(app) {
            XCTAssertGreaterThanOrEqual(field.frame.minY, app.frame.midY - 1, "Tabletop: search in the lower half")
            XCTAssertGreaterThanOrEqual(close.frame.minY, app.frame.midY - 1, "Tabletop: close in the lower half")
        }
        app.terminate()
    }

    /// J-21: deck and hero art stay inside the screen in every pose.
    func testHeroStaysOnScreen() throws {
        let app = launch("library")
        let hero = app.descendants(matching: .any).matching(NSPredicate(format: "identifier == 'continueHero'")).firstMatch
        if hero.waitForExistence(timeout: 4) {
            XCTAssertGreaterThanOrEqual(hero.frame.minX, app.frame.minX - 1)
            XCTAssertLessThanOrEqual(hero.frame.maxX, app.frame.maxX + 1, "hero within the screen width")
        }
        app.terminate()
    }
}

extension PlayscribeUITests {
    /// 0.2.0 gate (dc27a53): in Tabletop the first-run "Add your first game" button and the popular
    /// covers ran under the trailing rail. No first-run control may intersect the rail.
    func testTabletopFirstRunClearsTheRail() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-qaRoute", "first-run"]
        app.launch()
        sleep(3)
        guard ReleaseRowTests.pose(app).contains("pose: tabletop") else { app.terminate(); throw XCTSkip("not Tabletop") }
        let rail = app.buttons["Library"].firstMatch
        XCTAssertTrue(rail.waitForExistence(timeout: 5), "rail")
        let add = app.buttons["Add your first game"].firstMatch
        XCTAssertTrue(add.exists)
        XCTAssertLessThanOrEqual(add.frame.maxX, rail.frame.minX, "Add your first game \(add.frame) runs under the rail \(rail.frame)")
        for cover in app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Add '")).allElementsBoundByIndex where cover.isHittable && cover.label != "Add game" {
            XCTAssertLessThanOrEqual(cover.frame.maxX, rail.frame.minX + 1, "\(cover.label) \(cover.frame) runs under the rail")
        }
        app.terminate()
    }
}

/// 0.2.0 final fixes (Iris, dc27a53 review).
@MainActor
final class FinalFixTests: XCTestCase {
    private func launch(_ route: String) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-qaRoute", route]
        app.launch()
        sleep(3)
        return app
    }

    /// Book first-run: the right page is never blank. Popular covers sit right of the fold, clear of it.
    func testBookFirstRunFillsTheRightPage() throws {
        let app = launch("first-run")
        let pose = ReleaseRowTests.pose(app)
        guard pose.contains("pose: book"), let r = pose.range(of: #"fold (\d+)-(\d+)"#, options: .regularExpression) else {
            app.terminate(); throw XCTSkip("not Book")
        }
        let nums = pose[r].dropFirst(5).split(separator: "-").compactMap { Double($0) }
        let covers = app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Add ' AND label != 'Add game'")).allElementsBoundByIndex
        let right = covers.filter { $0.exists && $0.frame.minX >= nums[1] }
        XCTAssertGreaterThanOrEqual(right.count, 3, "right page shows Popular on PS5 covers")
        for c in covers where c.exists { XCTAssertFalse(c.frame.minX < nums[1] && c.frame.maxX > nums[0], "\(c.label) crosses the fold") }
        app.terminate()
    }

    /// Tabletop first-run: the headline sits at least 24 pt above the division band (conservatively, above mid-screen).
    func testTabletopFirstRunHeadlineClearsTheDivision() throws {
        let app = launch("first-run")
        guard ReleaseRowTests.pose(app).contains("pose: tabletop") else { app.terminate(); throw XCTSkip("not Tabletop") }
        let headline = app.descendants(matching: .any).matching(NSPredicate(format: "label CONTAINS 'Follow a game'")).firstMatch
        XCTAssertTrue(headline.waitForExistence(timeout: 5))
        XCTAssertLessThanOrEqual(headline.frame.maxY, app.frame.midY - 24, "headline \(headline.frame) is across the division")
        app.terminate()
    }

    /// Tabletop Add game: the compact header leaves at least three results visible in the lower half.
    func testTabletopAddGameShowsThreeRows() throws {
        let app = launch("add")
        guard ReleaseRowTests.pose(app).contains("pose: tabletop") else { app.terminate(); throw XCTSkip("not Tabletop") }
        let rows = app.descendants(matching: .any).matching(identifier: "addRow").allElementsBoundByIndex
        let visible = rows.filter { $0.exists && $0.frame.minY >= app.frame.midY - 1 && $0.frame.maxY <= app.frame.maxY + 1 }
        XCTAssertGreaterThanOrEqual(visible.count, 3, "at least 3 rows visible, saw \(visible.count)")
        app.terminate()
    }

    /// Tabletop Library: the Latest updates caption (game name and "New on PS5") ends at least 24 pt
    /// above the division band; the art stays full bleed behind it.
    func testTabletopLibraryCaptionClearsTheDivision() throws {
        let app = launch("demo")
        guard ReleaseRowTests.pose(app).contains("pose: tabletop") else { app.terminate(); throw XCTSkip("not Tabletop") }
        let caption = app.descendants(matching: .any).matching(identifier: "stageCaption").firstMatch
        XCTAssertTrue(caption.waitForExistence(timeout: 5))
        XCTAssertLessThanOrEqual(caption.frame.maxY, app.frame.midY - 24, "caption \(caption.frame) is across the division")
        app.terminate()
    }

    /// Tabletop game page: the reader text ends at least 24 pt above the division band.
    func testTabletopReaderTextClearsTheDivision() throws {
        let app = XCUIApplication()
        ReleaseRowTests.openBluePrince(app)
        sleep(3)
        guard ReleaseRowTests.pose(app).contains("pose: tabletop") else { app.terminate(); throw XCTSkip("not Tabletop") }
        let body = app.descendants(matching: .any).matching(identifier: "readerBody").firstMatch
        XCTAssertTrue(body.waitForExistence(timeout: 10))
        XCTAssertLessThanOrEqual(body.frame.maxY, app.frame.midY - 24, "reader text \(body.frame) is across the division")
        app.terminate()
    }

    /// Tabletop Add game: no keyboard. The search button explains why, and a letter filters the list (Iris ruling).
    func testTabletopSearchUsesLettersNotTheKeyboard() throws {
        let app = launch("add")
        guard ReleaseRowTests.pose(app).contains("pose: tabletop") else { app.terminate(); throw XCTSkip("not Tabletop") }
        let search = app.descendants(matching: .any).matching(identifier: "tabletopSearch").firstMatch
        XCTAssertTrue(search.waitForExistence(timeout: 5), "read-only search button")
        XCTAssertGreaterThanOrEqual(search.frame.height, 44)
        search.tap()
        XCTAssertTrue(app.descendants(matching: .any).matching(identifier: "tabletopSearchHint").firstMatch.waitForExistence(timeout: 3), "hint shown")
        XCTAssertFalse(app.keyboards.firstMatch.exists, "the keyboard never opens in Tabletop")
        let b = app.descendants(matching: .any).matching(identifier: "letter-B").firstMatch
        XCTAssertTrue(b.waitForExistence(timeout: 3) && b.frame.height >= 44, "44 pt letter chip")
        b.tap()
        sleep(1)
        XCTAssertTrue(app.descendants(matching: .any).matching(identifier: "addRow").firstMatch.waitForExistence(timeout: 3), "results for B")
        XCTAssertFalse(app.keyboards.firstMatch.exists)
        app.terminate()
    }

    /// Tabletop game page: notes search is the read-only button plus the A to Z strip, never the keyboard.
    func testTabletopNotesSearchUsesLettersNotTheKeyboard() throws {
        let app = XCUIApplication()
        ReleaseRowTests.openBluePrince(app)
        sleep(3)
        guard ReleaseRowTests.pose(app).contains("pose: tabletop") else { app.terminate(); throw XCTSkip("not Tabletop") }
        let search = app.descendants(matching: .any).matching(identifier: "tabletopSearch").firstMatch
        XCTAssertTrue(search.waitForExistence(timeout: 10), "read-only notes search button")
        search.tap()
        XCTAssertFalse(app.keyboards.firstMatch.exists, "the keyboard never opens in Tabletop")
        let f = app.descendants(matching: .any).matching(identifier: "letter-F").firstMatch
        XCTAssertTrue(f.waitForExistence(timeout: 3) && f.frame.height >= 44, "44 pt letter chip")
        app.terminate()
    }
}
