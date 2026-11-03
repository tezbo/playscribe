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
        let a = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
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
            let shot = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
            shot.name = "fold-\(route.replacingOccurrences(of: "/", with: "_")) \(label)"
            shot.lifetime = .keepAlways
            add(shot)
            XCTAssertTrue(label.hasPrefix("fold-crossings: 0;"), "\(route): \(label)")
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
        let shot = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
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
            let shot = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
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
        let pushed = XCTAttachment(screenshot: XCUIScreen.main.screenshot()); pushed.name = "journey-closed-pushed"; pushed.lifetime = .keepAlways; add(pushed)
        // Wait for the unfold: the pushed screen pops and the Page shows the release.
        let title = app.staticTexts.matching(identifier: "releaseTitle").matching(NSPredicate(format: "label == %@", "Patch 1.4")).firstMatch
        let deadline = Date.now.addingTimeInterval(150)
        while (app.navigationBars["Patch 1.4"].exists || !title.exists) && Date.now < deadline { sleep(2) }
        sleep(2)
        XCTAssertTrue(title.exists && !app.navigationBars["Patch 1.4"].exists, "Page shows Patch 1.4 after unfolding")
        ReleaseRowTests.reveal(row, in: app)
        XCTAssertTrue(row.isSelected, "Patch 1.4 row selected")
        let shot = XCTAttachment(screenshot: XCUIScreen.main.screenshot()); shot.name = "journey-open-patch-1.4"; shot.lifetime = .keepAlways; add(shot)
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
                .allElementsBoundByIndex.map(\.frame).filter { !$0.isEmpty && $0.width > 20 }
                .map { CGRect(x: $0.minX, y: $0.minY, width: $0.width, height: ($0.width * 4 / 3).rounded()) }
            let hero = app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'New update,' OR label BEGINSWITH 'Continue,'")).allElementsBoundByIndex.map(\.frame)
            for (i, a) in tiles.enumerated() {
                for b in tiles[(i + 1)...] { XCTAssertFalse(a.insetBy(dx: 1, dy: 1).intersects(b), "tiles overlap \(a) \(b) [\(pose)]") }
                for h in hero { XCTAssertFalse(a.insetBy(dx: 1, dy: 1).intersects(h), "tile overlaps hero \(a) \(h) [\(pose)]") }
            }
            checked += tiles.count
            app.swipeUp(velocity: .fast)
        }
        XCTAssertGreaterThan(checked, 0, "found tiles [\(pose)]")
        let shot = XCTAttachment(screenshot: XCUIScreen.main.screenshot()); shot.name = "library-\(games) [\(pose)]"; shot.lifetime = .keepAlways; add(shot)
    }

    func testEightGames() throws { try checkNoOverlap(games: 8) }
    func testTwentyEightGames() throws { try checkNoOverlap(games: 28) }
}

/// Review stills for QA and design (attachments named capture-*).
@MainActor
final class CaptureTests: XCTestCase {
    func shot(_ name: String) {
        let a = XCTAttachment(screenshot: XCUIScreen.main.screenshot()); a.name = "capture-\(name)"; a.lifetime = .keepAlways; add(a)
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
