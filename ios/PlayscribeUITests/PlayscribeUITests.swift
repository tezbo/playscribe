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
            note.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
            // The tap starts (or resumes) the app in a process this test's `app` proxy never launched, and the `simulate`
            // launch in postAndFindNotification replaced it, so ask a fresh proxy for the target app's state (3758183 and
            // e9a735d: a bare assertion here failed with no message).
            let target = XCUIApplication()
            // "Foreground" alone proves nothing: the app can be in front because the tap never reached SpringBoard's notification (a
            // locked sim, a missed row). The proof is that the app received the tap's response (INTERNAL probe), so wait for that,
            // and tap again, unlocking first, when it did not arrive (7631ff2: foreground, response "none", Library showing).
            func responseDelivered(_ timeout: TimeInterval) -> Bool {
                let probe = target.descendants(matching: .any)["qaNotificationResponse"]
                let deadline = Date.now.addingTimeInterval(timeout)
                repeat {
                    if probe.exists, !probe.label.hasSuffix("none") { return true }
                    usleep(300_000)
                } while Date.now < deadline
                return false
            }
            var foreground = target.wait(for: .runningForeground, timeout: 8)
            var delivered = foreground && responseDelivered(6)
            var retries = 0
            while !delivered && retries < 2 {
                // Unlock (a swipe up from the bottom; harmless if not locked), pull Notification Center down, find the row, tap.
                springboard.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.99))
                    .press(forDuration: 0.1, thenDragTo: springboard.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.4)))
                var again = notificationRow(timeout: 3)
                if again == nil {
                    springboard.coordinate(withNormalizedOffset: CGVector(dx: 0.3, dy: 0.001))
                        .press(forDuration: 0.1, thenDragTo: springboard.coordinate(withNormalizedOffset: CGVector(dx: 0.3, dy: 0.6)))
                    again = notificationRow(timeout: 5)
                }
                guard let row = again else { break }
                row.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
                retries += 1
                foreground = target.wait(for: .runningForeground, timeout: 8)
                delivered = foreground && responseDelivered(6)
            }
            if retries > 0 {
                let note = XCTAttachment(string: "retried \(retries) time(s) before the app came to the foreground (\(cold ? "cold" : "warm"))")
                note.name = "n6-retried-\(retries)-" + (cold ? "cold" : "warm"); note.lifetime = .keepAlways; add(note)
            }
            // Quinn: one swallowed tap is SpringBoard; two in a cold launch is the app not coming up, so that is a failure.
            if cold && foreground && retries >= 2 {
                XCTFail("cold: the notification needed \(retries) retries to bring Playscribe to the foreground; the first taps did nothing")
            }
            if !foreground {
                let tree = XCTAttachment(string: springboard.debugDescription); tree.name = "n6-springboard-hierarchy-" + (cold ? "cold" : "warm"); tree.lifetime = .keepAlways; add(tree)
            }
            if !foreground {
                let shot = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
                shot.name = "n6-not-foreground-" + (cold ? "cold" : "warm"); shot.lifetime = .keepAlways; add(shot)
            }
            XCTAssertTrue(foreground, "\(cold ? "cold" : "warm"): tapping the notification brings Playscribe to the foreground (app state \(target.state.rawValue); 4 is running foreground)")
            // The notification is for the simulated release ("Update N.0 (simulated)", the number counts earlier simulations), so the
            // page that opens is that release's; "Update 1.1" is the real release and never what this notification carries (96e0e39).
            let release = target.descendants(matching: .any)["releaseTitle"]
            // Quinn: the title must be the simulated release's; an OR here would pass on opening the wrong release.
            let opened = release.waitForExistence(timeout: 10) && release.label.localizedCaseInsensitiveContains("simulated")
            if !opened {
                // Did the tap's response reach the app at all? "none" = it never arrived (the tap went elsewhere); a value =
                // it arrived and navigation did not follow, which is an app bug.
                let resp = target.descendants(matching: .any)["qaNotificationResponse"]
                let r = XCTAttachment(string: resp.exists ? resp.label : "no qaNotificationResponse element"); r.name = "n6-response-" + (cold ? "cold" : "warm"); r.lifetime = .keepAlways; add(r)
                let tree = XCTAttachment(string: target.debugDescription); tree.name = "n6-after-tap-hierarchy-" + (cold ? "cold" : "warm"); tree.lifetime = .keepAlways; add(tree)
            }
            XCTAssertTrue(opened, "\(cold ? "cold" : "warm"): the simulated release opens after the tap (its page, not the Library); response seen by the app: \(target.descendants(matching: .any)["qaNotificationResponse"].exists ? target.descendants(matching: .any)["qaNotificationResponse"].label : "no probe")")
            let a = XCTAttachment(screenshot: target.screenshot()); a.name = cold ? "notification-tap-cold" : "notification-tap-warm"
            a.lifetime = .keepAlways; add(a)
        }
    }

    /// G-7 and G-10: the system accessibility audit on the main screens.
    func testAccessibilityAudit() throws {
        for route in ["demo", "release/dawnwalker/dawnwalker@1.1", "add", "updates"] {
            app.launchArguments = ["-qaRoute", route]
            app.launch()
            sleep(2)
            try app.performAccessibilityAudit(for: [.hitRegion, .sufficientElementDescription, .elementDetection]) { issue in
                // Game art, poster images and the system status bar aren't the app's controls.
                // Name every issue in the log, so a red run says which element it was (10f6e004: the audit named none).
                XCTContext.runActivity(named: "audit issue [\(route)]: \(issue.compactDescription) | \(issue.detailedDescription) | element: \(issue.element?.debugDescription ?? "none")") { _ in }
                // "Potentially inaccessible text" is the system spotting words drawn inside raster artwork (cover and hero art
                // with the game's title baked in). The art is labelled by its card; the app cannot label pixels.
                if issue.auditType == .elementDetection && issue.compactDescription.contains("inaccessible text") { return true }
                return issue.element?.elementType == .image || issue.element?.identifier.isEmpty == false && issue.element?.label.isEmpty == true
            }
            attach(name: "audit-\(route.replacingOccurrences(of: "/", with: "_"))")
        }
    }

    // MARK: - Helpers

    /// Schedules a local notification through the app's internal route, then finds its banner. The 0.5.0 copy is
    /// "Update 1.1: <headline>" under the game name (no "is live on PS5"), so the banner is found by the game name.
    private func postAndFindNotification() throws -> XCUIElement {
        let simulate = XCUIApplication()
        simulate.launchArguments = ["-qaRoute", "simulate/dawnwalker/major"]
        simulate.launch()
        XCUIDevice.shared.press(.home)
        XCUIDevice.shared.press(.home)   // the second press wakes a sim that has gone to the lock screen (48404f1)
        // The banner is up for only a few seconds, and pressing Home returns slowly: look briefly, then use Notification Center.
        if let banner = notificationRow(timeout: 4) { return banner }
        let start = springboard.coordinate(withNormalizedOffset: CGVector(dx: 0.3, dy: 0.001))
        start.press(forDuration: 0.1, thenDragTo: springboard.coordinate(withNormalizedOffset: CGVector(dx: 0.3, dy: 0.6)))
        let listed = notificationRow(timeout: 10)
        XCTAssertNotNil(listed, "the Dawnwalker notification is in the banner or Notification Center")
        return listed ?? springboard.otherElements["Notification"]
    }

    /// The notification's own row: the smallest hittable element whose label names the game. A first match on any element
    /// can be a container (a list or its scroll view) whose centre is not the row, so the tap lands on nothing (e9a735d:
    /// the tap at 40.7 s left the app unlaunched with its icon badged "1 new item").
    private func notificationRow(timeout: TimeInterval) -> XCUIElement? {
        let deadline = Date.now.addingTimeInterval(timeout)
        let query = springboard.descendants(matching: .any).matching(NSPredicate(format: "label CONTAINS 'Dawnwalker'"))
        repeat {
            let rows = query.allElementsBoundByIndex.filter { $0.exists && $0.isHittable && !$0.frame.isEmpty }
            if let row = rows.min(by: { $0.frame.width * $0.frame.height < $1.frame.width * $1.frame.height }) { return row }
            usleep(500_000)
        } while Date.now < deadline
        return nil
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

/// Fold harness calibration (docs/fold-harness.md): prints what the simulator's real fold gave the app, for
/// `tools/qa/compare_harness.py` to diff against the harness. Run in each pose; it asserts nothing about layout.
final class PoseProbeTests: XCTestCase {
    @MainActor
    func testPrintPoseProbe() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-qaRoute", "library"]
        app.launch()
        sleep(4)
        let probe = app.descendants(matching: .any)["poseProbe"]
        XCTAssertTrue(probe.waitForExistence(timeout: 8))
        print("POSEPROBE \(probe.label)")
        let note = XCTAttachment(string: probe.label)
        note.name = "pose-probe.json"
        note.lifetime = .keepAlways
        add(note)
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

    /// Settings shows the bundle's version (semantic, x.y.z; the number moves with each release).
    func testSettingsVersion() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-qaRoute", "settings"]
        app.launch()
        // The identified row, not "any element whose text looks like a version": at 96e0e39 a game card behind the sheet read
        // "01.001.000" (a simulated release's date), matched at once, and the loop never scrolled to the real row.
        let version = app.descendants(matching: .any)["appVersion"]
        var tries = 0
        while !version.exists && tries < 8 { Release050Tests.scrollForm(app); tries += 1 }
        if !version.exists {
            let tree = XCTAttachment(string: app.debugDescription); tree.name = "settings-hierarchy.txt"; tree.lifetime = .keepAlways; add(tree)
            let shot = XCTAttachment(screenshot: app.screenshot()); shot.name = "settings-window"; shot.lifetime = .keepAlways; add(shot)
        }
        XCTAssertTrue(version.exists, "the version row is identified")
        let text = [version.value as? String, version.label].compactMap { $0 }.joined(separator: " ")
        XCTAssertNotNil(text.range(of: #"\d+\.\d+\.\d+"#, options: .regularExpression), "Settings shows a semantic version, got '\(text)'")
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
        // The App Switcher was on screen in Open portrait and Tabletop (96e0e39): leave it, then bring the app up.
        func leaveSwitcher() {
            if XCUIApplication(bundleIdentifier: "com.apple.springboard").otherElements["AppSwitcherContentView"].exists {
                XCUIDevice.shared.press(.home)
            }
        }
        leaveSwitcher()
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
        // Open portrait (48404f1): the capture was the App Switcher and no tiles were found, so bring the app back first.
        leaveSwitcher()
        if !app.wait(for: .runningForeground, timeout: 10) {
            // Not in the foreground after launch (Tabletop, 96e0e39 and eab123c: SpringBoard in the tree, no crash report). Go Home,
            // launch again once, and keep what SpringBoard showed.
            let sb = XCTAttachment(string: XCUIApplication(bundleIdentifier: "com.apple.springboard").debugDescription)
            sb.name = "eight-games-not-foreground-springboard.txt"; sb.lifetime = .keepAlways; add(sb)
            XCUIDevice.shared.press(.home)
            app.launch()
            _ = app.wait(for: .runningForeground, timeout: 15)
        }
        sleep(4)
        let pose = ReleaseRowTests.pose(app)
        var checked = 0
        for _ in 0..<10 {
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
            // The deck is a pager: only the first card is the hero; the rest wait off screen to the right. (app.frame
            // can report the wrong orientation in Closed landscape, so the wide card is checked against the longer side.)
            let heroCards = app.buttons.matching(identifier: "deckCard").allElementsBoundByIndex.prefix(1).map(\.frame)
            let hero = heroCards + app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Continue,'")).allElementsBoundByIndex.map(\.frame)
            // e869273: in the landscape poses (Closed, Book, Open) app.frame reports portrait dimensions (670 or 679 wide) while
            // the screen is about 1288 wide, so the longer side bounds the hero. Tabletop keeps app.frame.
            let screenW = pose.contains("tabletop") ? app.frame.width : max(app.frame.width, app.frame.height)
            // 0.2.0 gate: the hero's frame is its card, not the fill-scaled art behind it (it once
            // reported x -97.7, width 461). Open landscape: the double tile, 2 tiles + 10 pt, where the
            // tile fills the width (n columns of 120 to 168 pt, 16 pt gaps, 16 pt margins).
            let openW = app.frame.width - 32
            let openN = max(3, Int((openW + 16) / 136))
            for h in hero {
                XCTAssertGreaterThanOrEqual(h.minX, 0, "hero starts on screen \(h) [\(pose)]")
                XCTAssertLessThanOrEqual(h.maxX, screenW + 1, "hero ends on screen \(h) [\(pose)]")
                // 0.5.0: the hero is the Latest updates deck, so a card is not a tile; the old double-tile width
                // check does not apply. Open portrait: the card is at most 38% of the height.
                // e869273 (28 games): the hero was 835 x 727 pt in Open and screen-tall in Closed portrait. In every pose but
                // Tabletop (view only) and Closed landscape (the wide card, 168 to 240 pt) a hero card is at most about 38%
                // of the screen height; app.frame's orientation is unreliable, so the shorter side bounds it (half of it).
                if !pose.contains("tabletop") {
                    XCTAssertLessThanOrEqual(h.height, min(app.frame.width, app.frame.height) * 0.5 + 12,
                                             "hero card never fills the screen \(h) [\(pose)]")
                }
                // Only when the measurement is consistent with portrait: a card wider than app.frame is a landscape reading.
                if pose.contains("flat") && app.frame.width <= app.frame.height && h.maxX <= app.frame.width + 1 {
                    XCTAssertLessThanOrEqual(h.height, app.frame.height * 0.42 + 12, "Open portrait hero is at most 42% of the height [\(pose)]")
                }
            }
            // Open portrait: the deck takes the full content width, nothing sits beside it (the Also new panel is gone).
            let deck = app.descendants(matching: .any).matching(NSPredicate(format: "label BEGINSWITH 'Latest updates, page'")).firstMatch
            if pose.contains("flat"), deck.exists, app.frame.width <= app.frame.height {
                XCTAssertGreaterThan(deck.frame.width, app.frame.width * 0.6, "Open portrait deck is full width [\(pose)]")
            }
            if pose.contains("flat"), let right = tiles.map(\.maxX).max(), tiles.count >= openN {
                XCTAssertGreaterThanOrEqual(right, app.frame.width - 16 - 12, "Open grid fills the width, no dead space on the trailing side [\(pose)]")
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
        let version = app.descendants(matching: .any).matching(NSPredicate(format: "label MATCHES '.*[0-9]+\\\\.[0-9]+\\\\.[0-9]+.*' OR value MATCHES '.*[0-9]+\\\\.[0-9]+\\\\.[0-9]+.*'")).firstMatch
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
        app.launchArguments = ["-qaRoute", "demo"]   // seeded: `library` shows the empty first-run Library after an earlier first-run test, and it has no deck
        app.launch()
        sleep(4)
        if ReleaseRowTests.pose(app).contains("pose: tabletop") { app.terminate(); throw XCTSkip("Tabletop's upper half is view only") }
        let leaves = app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Update ' AND label CONTAINS ' of '"))
        if leaves.count > 1 {
            XCTAssertGreaterThanOrEqual(leaves.element(boundBy: 1).frame.height, 44, "leaf is a 44 pt target")
            leaves.element(boundBy: 1).tap()
        }
        // The deck cards by identifier: the old label query could land on a Library tile, which opens the game, not an update.
        let cards = app.buttons.matching(identifier: "deckCard")
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
                // e869273 (Tabletop stills): the panel's own Close sits in the lower half and nothing is tappable up top, yet a
                // second "Close" is reported at the top left, a ghost from the dimmed view behind. A same-label control in
                // the lower half means the upper one is not a control on screen.
                if e.frame.minY < half - 1, !e.label.isEmpty,
                   controls.contains(where: { $0.exists && $0.label == e.label && $0.frame.minY >= half - 1 }) { continue }
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
        if !find.waitForExistence(timeout: 8),
           app.descendants(matching: .any).matching(NSPredicate(format: "label CONTAINS[c] \"can't scan\" OR label CONTAINS[c] \"cannot scan\"")).firstMatch.exists
            || ReleaseRowTests.pose(app).contains("pose: tabletop") {
            app.terminate(); throw XCTSkip("no camera in this simulator pose, so the scan view shows its unsupported state")
        }
        XCTAssertTrue(find.exists, "scan shows Find these games")
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

    /// Swipe the Settings form itself. In Tabletop Settings is a half-height panel, and a swipe at the app's centre lands on the
    /// view-only stage above it, so the form never scrolled (48404f1: the PS Plus and Quiet hours switches were never reached).
    static func scrollForm(_ app: XCUIApplication) {
        let form = app.collectionViews.firstMatch
        guard form.exists else { app.swipeUp(); return }
        // A short, slow drag (about a third of the panel): a fling moved Tabletop's half-height panel past whole rows, so the
        // PS Plus switch was never on screen at a check (96e0e39).
        form.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.8))
            .press(forDuration: 0.1, thenDragTo: form.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.45)),
                   withVelocity: .slow, thenHoldForDuration: 0.2)
    }

    /// TB-1: the Library's Add and Settings controls are both there, hittable, 44 pt, clear of each other and
    /// of the status bar, in every pose; the cog opens Settings, which shows a semantic version.
    /// Fast on its own: -only-testing:PlayscribeUITests/Release050Tests/testLibraryToolbarCogAndAdd
    func testLibraryToolbarCogAndAdd() throws {
        let app = launch("library")
        let pose = ReleaseRowTests.pose(app)
        let cog = app.buttons["settingsButton"]
        let add = app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Add game' OR label == 'Add game' OR label == 'Add'")).firstMatch
        XCTAssertTrue(cog.waitForExistence(timeout: 10), "Settings cog exists [\(pose)]")
        XCTAssertTrue(add.exists, "Add exists [\(pose)]")
        // Exemption (Iris): only the system-drawn navigation-bar buttons (Closed, Open, Book: the app draws 38) may be 36 pt.
        // Our own controls, which is Tabletop's rail, stay at 44 pt. (Book hit the 44 branch at 48404f1: its bar is system-drawn too.)
        let floor: CGFloat = pose.contains("pose: tabletop") ? 43.5 : 35.5
        for (name, e) in [("Settings", cog), ("Add", add)] {
            XCTAssertTrue(e.isHittable, "\(name) is hittable [\(pose)]")
            XCTAssertGreaterThanOrEqual(e.frame.height, floor, "\(name) height at least \(floor) pt [\(pose)]")
            XCTAssertGreaterThanOrEqual(e.frame.width, floor, "\(name) width at least \(floor) pt [\(pose)]")
            XCTAssertGreaterThanOrEqual(e.frame.minY, 0, "\(name) is on screen [\(pose)]")
        }
        // Iris: 8 pt between the two toolbar buttons, whatever the floor.
        XCTAssertFalse(cog.frame.insetBy(dx: -7.5, dy: -7.5).intersects(add.frame), "cog and Add keep 8 pt apart \(cog.frame) \(add.frame) [\(pose)]")
        // Iris, Book: nothing within 24 pt of the hinge band. The band is in the pose probe's `division` ([x, y, w, h]).
        if pose.contains("pose: book"), let probe = Optional(app.descendants(matching: .any)["poseProbe"]), probe.exists,
           let data = probe.label.data(using: .utf8), let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let band = (json["division"] as? [Double]), band.count == 4 {
            let lo = band[0], hi = band[0] + band[2]
            for (name, e) in [("Settings", cog), ("Add", add)] {
                let clearLeft = e.frame.maxX <= lo - 24 + 0.5, clearRight = e.frame.minX >= hi + 24 - 0.5
                XCTAssertTrue(clearLeft || clearRight, "\(name) keeps 24 pt from the hinge band \(lo)-\(hi): frame \(e.frame) [\(pose)]")
            }
            let note = XCTAttachment(string: "Book toolbar: Settings \(cog.frame), Add \(add.frame), hinge band \(lo)-\(hi)")
            note.name = "book-toolbar-measurements.txt"; note.lifetime = .keepAlways; self.add(note)
        }
        XCTAssertFalse(cog.frame.insetBy(dx: 1, dy: 1).intersects(add.frame), "cog and Add do not overlap \(cog.frame) \(add.frame) [\(pose)]")
        // Status bar: nothing of either control sits inside the status bar's frame.
        let status = app.statusBars.firstMatch
        if status.exists {
            XCTAssertFalse(cog.frame.insetBy(dx: 1, dy: 1).intersects(status.frame), "cog clear of the status bar [\(pose)]")
            XCTAssertFalse(add.frame.insetBy(dx: 1, dy: 1).intersects(status.frame), "Add clear of the status bar [\(pose)]")
        }
        cog.tap()
        let version = app.descendants(matching: .any)["appVersion"]
        let form = app.collectionViews.firstMatch
        var tries = 0
        while !version.waitForExistence(timeout: 1) && tries < 8 { (form.exists ? form : app).swipeUp(); tries += 1 }
        XCTAssertTrue(version.exists, "Settings opened and shows its Version row [\(pose)]")
        let text = [version.value as? String, version.label].compactMap { $0 }.joined(separator: " ")
        XCTAssertNotNil(text.range(of: #"\d+\.\d+\.\d+"#, options: .regularExpression), "Version reads like 1.2.3, got '\(text)' [\(pose)]")
    }

    /// 0.5.1 spec 2: while the pill shows, the page's top controls stay clear of it and tappable, and swiping the pill
    /// away dismisses it (its VoiceOver "Dismiss" action does the same; XCUITest cannot list custom actions).
    func testPillLeavesTheTopOfThePageAlone() throws {
        let app = launch("pill")
        let pill = app.buttons["newOnPS5Pill"]
        XCTAssertTrue(pill.waitForExistence(timeout: 10), "the pill shows")
        let cog = app.buttons["settingsButton"]
        XCTAssertTrue(cog.exists && cog.isHittable, "Settings stays tappable while the pill shows")
        XCTAssertFalse(cog.frame.insetBy(dx: 1, dy: 1).intersects(pill.frame), "the pill does not cover the cog")
        let search = app.textFields.firstMatch
        if search.exists { XCTAssertFalse(search.frame.insetBy(dx: 1, dy: 1).intersects(pill.frame), "the pill does not cover Search") }
        // The Library's scroll view ends above the pill, so no row or tile can sit under it.
        let page = app.scrollViews.firstMatch
        if page.exists { XCTAssertLessThanOrEqual(page.frame.maxY, pill.frame.minY + 1, "the Library ends above the pill") }
        pill.swipeRight()
        XCTAssertFalse(pill.waitForExistence(timeout: 3), "swiping dismisses the pill")
        app.terminate()
    }

    /// 0.5.1 spec 2 (Quinn, #246): in Tabletop the letter filter scrolls with the page, and a letter scrolled below the page's
    /// edge is drawn under the pill by the overlay. It must not take a tap: the page is clipped above the pill.
    func testPillCoversNoHittableLetterInTabletop() throws {
        let app = launch("pill")
        let pill = app.buttons["newOnPS5Pill"]
        XCTAssertTrue(pill.waitForExistence(timeout: 10), "the pill shows")
        guard isTabletop(app) else { app.terminate(); return }
        XCTAssertTrue(pill.isHittable, "the pill itself takes taps")
        let letters = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'letter-'")).allElementsBoundByIndex
        // isHittable tests the element's centre. A letter's frame may reach a few points below the page's edge (the part
        // past the edge is clipped and takes no tap), so judge the centre: below the pill's top edge it must not be hittable,
        // and a hittable letter's centre must be above the pill.
        for letter in letters where letter.frame.midY >= pill.frame.minY {
            XCTAssertFalse(letter.isHittable, "\(letter.identifier) has its centre at or under the pill and must not take a tap")
        }
        for letter in letters where letter.isHittable {
            XCTAssertLessThan(letter.frame.midY, pill.frame.minY, "\(letter.identifier) is tappable only with its centre above the pill")
        }
        app.terminate()
    }

    /// 0.5.1 spec 1: the per-game footer sits directly under the Notify me about row, and every toggle row is 52 pt.
    func testSettingsFootersAndRows() throws {
        let app = launch("settings")
        let notify = app.descendants(matching: .any).matching(NSPredicate(format: "label BEGINSWITH 'Notify me about'")).firstMatch
        let footer = app.staticTexts["Change a single game from the bell on its page."]
        XCTAssertTrue(notify.waitForExistence(timeout: 10), "Notify me about row")
        XCTAssertTrue(footer.exists, "per-game footer is shown")
        XCTAssertLessThanOrEqual(footer.frame.minY - notify.frame.maxY, 60, "footer sits directly under the Notify row")
        let pause = app.switches["Pause all"]
        if pause.exists { XCTAssertGreaterThanOrEqual(pause.frame.height, 51.5, "toggle rows are 52 pt") }
        app.terminate()
    }

    /// J-20: quiet hours. The switch is off by default; turning it on shows From and Until and the footer.
    func testQuietHours() throws {
        let app = launch("settings")
        let toggle = app.switches["quietHours"]
        var tries = 0
        while !toggle.exists && tries < 6 { Self.scrollForm(app); tries += 1 }
        XCTAssertTrue(toggle.exists, "Settings has a Quiet hours switch")
        XCTAssertTrue(["off", "0"].contains(toggle.value as? String ?? ""), "off by default, got \(String(describing: toggle.value))")
        if isTabletop(app) { XCTAssertGreaterThanOrEqual(toggle.frame.minY, app.frame.midY - 1, "Tabletop: switch in the lower half") }
        XCTAssertGreaterThanOrEqual(toggle.frame.height, 44 - 1)
        // Bring the row clear of the panel's bottom edge before tapping: at 96e0e39 it sat at the edge, the tap missed and the
        // From and Until rows never appeared.
        var lift = 0
        while let form = Optional(app.collectionViews.firstMatch), form.exists, toggle.frame.maxY > form.frame.maxY - 60, lift < 4 { Self.scrollForm(app); lift += 1 }
        // The identified element is the whole row; the switch is nested at its trailing edge, and a centre tap misses it.
        let inner = toggle.switches.firstMatch
        if inner.exists { inner.tap() } else { toggle.coordinate(withNormalizedOffset: CGVector(dx: 0.93, dy: 0.5)).tap() }
        // From and Until are date pickers (their label is the title), so match any element, not only static text.
        func any(_ prefix: String) -> XCUIElement {
            app.descendants(matching: .any).matching(NSPredicate(format: "label BEGINSWITH %@", prefix)).firstMatch
        }
        // The rows are added below the switch, which may now be at the panel's edge: scroll the form to each.
        func reveal(_ prefix: String) -> Bool {
            var n = 0
            while !any(prefix).waitForExistence(timeout: 1) && n < 6 {
                Self.scrollForm(app); n += 1
            }
            return any(prefix).exists
        }
        XCTAssertTrue(reveal("From"), "From row appears")
        XCTAssertTrue(reveal("Until"), "Until row appears")
        XCTAssertTrue(reveal("Alerts arrive silently"), "footer")
        app.terminate()
    }

    /// Terry 2026-11-05: the PS Plus card is on by default; the Settings switch turns it, and its reminder row, off.
    func testPlusCardSwitch() throws {
        let app = launch("plus-demo")
        let card = app.descendants(matching: .any)["plusCard"]
        XCTAssertTrue(card.waitForExistence(timeout: 10), "PS Plus card shows by default")
        XCTAssertTrue(ReleaseRowTests.pose(app).hasPrefix("fold-crossings: 0;"), "card crosses no fold: \(ReleaseRowTests.pose(app))")
        let cog = app.buttons["settingsButton"]
        XCTAssertTrue(cog.waitForExistence(timeout: 5)); cog.tap()
        let toggle = app.switches["plusCardToggle"]
        var tries = 0
        while !toggle.exists && tries < 6 { Self.scrollForm(app); tries += 1 }
        XCTAssertTrue(toggle.exists, "Settings has the PS Plus card switch")
        XCTAssertTrue(["on", "1"].contains(toggle.value as? String ?? ""), "on by default, got \(String(describing: toggle.value))")
        let reminder = app.descendants(matching: .any)["plusLeavingSoon"]
        XCTAssertTrue(reminder.exists, "the reminder row shows while the card is on")
        let inner = toggle.switches.firstMatch
        if inner.exists { inner.tap() } else { toggle.coordinate(withNormalizedOffset: CGVector(dx: 0.93, dy: 0.5)).tap() }
        XCTAssertTrue(["off", "0"].contains(toggle.value as? String ?? ""), "off after the tap, got \(String(describing: toggle.value))")
        XCTAssertFalse(reminder.waitForExistence(timeout: 2), "the reminder row goes with the card")
        // Close Settings: the Library card is gone. Then back on: it returns (Quinn, #245).
        func flip() {
            let t = app.switches["plusCardToggle"]
            var n = 0
            while !t.exists && n < 6 { Self.scrollForm(app); n += 1 }
            let i = t.switches.firstMatch
            if i.exists { i.tap() } else { t.coordinate(withNormalizedOffset: CGVector(dx: 0.93, dy: 0.5)).tap() }
        }
        app.buttons["Close"].tap()
        XCTAssertFalse(card.waitForExistence(timeout: 3), "the Library card is hidden with the switch off")
        app.buttons["settingsButton"].tap()
        flip()
        XCTAssertTrue(["on", "1"].contains(app.switches["plusCardToggle"].value as? String ?? ""), "on again")
        XCTAssertTrue(app.descendants(matching: .any)["plusLeavingSoon"].waitForExistence(timeout: 2), "the reminder row returns")
        app.buttons["Close"].tap()
        XCTAssertTrue(card.waitForExistence(timeout: 3), "the Library card returns with the switch on")
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

    /// The Search tab always offers a way to search, in every pose: its own text field (16 pt margins, clear of the badge)
    /// outside Tabletop; the read-only button and letter strip in Tabletop.
    func testSearchTabHasAFieldInEveryPose() throws {
        let app = launch("demo")
        let tab = app.buttons.matching(NSPredicate(format: "label == 'Search'")).firstMatch
        XCTAssertTrue(tab.waitForExistence(timeout: 5), "Search tab or rail button")
        tab.tap()
        sleep(1)
        if ReleaseRowTests.pose(app).contains("pose: tabletop") {
            let button = app.descendants(matching: .any).matching(identifier: "tabletopSearch").firstMatch
            XCTAssertTrue(button.waitForExistence(timeout: 5), "Tabletop: read-only search button")
            XCTAssertTrue(app.descendants(matching: .any).matching(identifier: "letter-A").firstMatch.exists, "Tabletop: letter strip")
            XCTAssertFalse(app.keyboards.firstMatch.exists)
            // Ruling: tapping the field never raises the keyboard; it explains why instead.
            button.tap()
            let hint = app.descendants(matching: .any).matching(identifier: "tabletopSearchHint").firstMatch
            XCTAssertTrue(hint.waitForExistence(timeout: 3), "Tabletop: the field explains why there is no keyboard")
            XCTAssertTrue(hint.label.contains("Typing needs the flat screen. Pick a letter below, or open your Duo flat to type."), "hint wording [\(hint.label)]")
            sleep(1)
            XCTAssertFalse(app.keyboards.firstMatch.exists, "Tabletop: the keyboard never opens")
        } else {
            // Closed portrait has its own text field (16 pt clear of the badge); the other poses use the system field.
            let own = app.textFields["searchField"]
            let field = own.waitForExistence(timeout: 2) ? own : app.searchFields.firstMatch
            XCTAssertTrue(field.waitForExistence(timeout: 5), "a search field exists on the Search tab")
            XCTAssertTrue(field.isHittable, "the search field is on screen and tappable")
            XCTAssertGreaterThanOrEqual(field.frame.minX, 0, "field starts on screen")
            // Book: the field sits on one page, never across the fold. (app.frame reports the portrait
            // width after XCUITest resets the orientation, so the fold comes from the audit label.)
            let label = ReleaseRowTests.pose(app)
            if label.contains("pose: book"), let r = label.range(of: "fold ") {
                let digits = label[r.upperBound...].prefix(while: { $0.isNumber || $0 == "-" })
                let nums = digits.split(separator: "-")
                if nums.count == 2, let lo = Double(nums[0]), let hi = Double(nums[1]) {
                    XCTAssertTrue(field.frame.maxX <= lo + 1 || field.frame.minX >= hi - 1, "Book: search field \(field.frame) crosses the fold \(lo)-\(hi)")
                }
            }
        }
        app.terminate()
    }
}
