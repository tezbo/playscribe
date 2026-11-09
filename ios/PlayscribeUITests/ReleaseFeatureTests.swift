import XCTest

/// 0.5.0 feature journeys (docs/ux-acceptance.md J-1 to J-4 "every tap lands", J-5 Library never
/// overlaps, A-1 to A-9 add flow, G-7/G-10 accessibility, TT-0 fold). Written for the Mac gate: run
/// them in each of the five poses with the PlayscribeUI scheme. They tap, they do not just look.
/// A test skips (never passes silently) when its precondition is absent from the simulator, for
/// example a permission already decided or a feed shard that is not cached.
@MainActor
final class ReleaseFeatureTests: XCTestCase {
    let app = XCUIApplication()

    override func setUp() async throws {
        continueAfterFailure = false
    }

    private func launch(_ route: String) {
        app.launchArguments = ["-qaRoute", route]
        app.launch()
    }

    private var inTabletop: Bool { pose().contains("pose: tabletop") }

    private func pose() -> String {
        let audit = app.descendants(matching: .any)["foldAudit"]
        _ = audit.waitForExistence(timeout: 5)
        return audit.exists ? audit.label : "unknown"
    }

    /// The Playing / Upcoming switch: a rail button in Tabletop, else a segmented Picker whose segments are not
    /// reliably exposed (the gate found none by label in any pose), so the picker itself is tapped at its half.
    private func switchTo(_ label: String) -> Bool {
        let rail = app.descendants(matching: .any)[label == "Upcoming" ? "upcomingRail" : "playingRail"]
        if rail.waitForExistence(timeout: 10) { rail.tap(); return true }
        let seg = app.descendants(matching: .any).matching(NSPredicate(format: "label == %@", label)).firstMatch
        if seg.exists { seg.tap(); return true }
        let picker = app.descendants(matching: .any)["libraryTabPicker"]
        guard picker.waitForExistence(timeout: 10) else { return false }
        picker.coordinate(withNormalizedOffset: CGVector(dx: label == "Upcoming" ? 0.75 : 0.25, dy: 0.5)).tap()
        return true
    }

    private func button(_ prefix: String) -> XCUIElement {
        app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", prefix)).firstMatch
    }

    private func attach(_ name: String) {
        // The app window, not XCUIScreen.main: in Book the main screen is the outer display and the capture came back black (48404f1).
        let a = XCTAttachment(screenshot: app.screenshot())
        a.name = name
        a.lifetime = .keepAlways
        add(a)
    }

    /// TT-0 and the Tabletop rule: no frame crosses an active division, and in Tabletop nothing
    /// tappable sits in the upper half.
    private func assertFrames(_ screen: String, file: StaticString = #filePath, line: UInt = #line) {
        let label = pose()
        XCTAssertTrue(label.hasPrefix("fold-crossings: 0;"), "\(screen): \(label)", file: file, line: line)
        guard label.contains("pose: tabletop") else { return }
        let half = app.frame.midY
        let tappable = app.buttons.allElementsBoundByIndex + app.cells.allElementsBoundByIndex
            + app.switches.allElementsBoundByIndex + app.textFields.allElementsBoundByIndex
        for e in tappable where e.exists && e.isHittable && !e.frame.isEmpty {
            XCTAssertGreaterThanOrEqual(e.frame.minY, half - 1,
                                        "\(screen): '\(e.label)' is tappable above the fold in Tabletop", file: file, line: line)
        }
    }

    // MARK: - Library

    /// B-10 (gate only): hold a Library tile so the Mac can shoot the status menu. Attaches a still of the open menu,
    /// then dismisses it. Skips when no tile is reachable (for example Tabletop's upper half is view only).
    func testLongPressTileShowsStatusMenu() throws {
        launch("quick/wishlist")
        let tile = app.descendants(matching: .any).matching(NSPredicate(format: "identifier BEGINSWITH %@", "tile-")).firstMatch
        // The grid is lazy and below the cards, so it is not in the tree at launch: wait for the Library, then scroll
        // the lower half (never the view-only upper half) until a tile exists and can be pressed.
        _ = app.descendants(matching: .any)["libraryTabPicker"].waitForExistence(timeout: 15)
        // Swipe the Library's own scroll view (the one holding the tab picker): a hand-placed drag started on the
        // Tabletop search button and never scrolled the pane (Mac, 20d340f).
        let shelf = app.scrollViews.containing(.any, identifier: "libraryTabPicker").firstMatch
        var tries = 0
        while !(tile.exists && tile.isHittable) && tries < 10 {
            if shelf.exists { shelf.swipeUp(velocity: .slow) } else { app.swipeUp() }
            tries += 1
        }
        if !tile.exists {
            let dump = XCTAttachment(string: app.debugDescription)
            dump.name = "tree-no-tile-after-scroll-\(pose().replacingOccurrences(of: " ", with: "-"))"
            dump.lifetime = .keepAlways
            add(dump)
            throw XCTSkip("no tile after scrolling; the accessibility tree is attached")
        }
        guard tile.isHittable else { throw XCTSkip("no tappable tile in this pose after scrolling") }
        tile.press(forDuration: 1.2)
        let remove = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Remove ")).firstMatch
        XCTAssertTrue(remove.waitForExistence(timeout: 5), "B-10: the long-press menu lists Remove")
        XCTAssertTrue(app.buttons["Wishlist"].exists && app.buttons["Owned"].exists && app.buttons["Watching"].exists)
        let shot = XCTAttachment(screenshot: app.screenshot())
        shot.name = "quick-menu-\(pose().replacingOccurrences(of: " ", with: "-"))"
        shot.lifetime = .keepAlways
        add(shot)
        app.coordinate(withNormalizedOffset: CGVector(dx: 0.05, dy: 0.05)).tap()
    }

    /// J-1, J-2: the Latest updates hero. A card opens its update; the leaves are 44 pt targets.
    func testHeroDeckCardOpensItsUpdate() throws {
        launch("demo")
        let card = app.buttons.matching(NSPredicate(format: "identifier == 'deckCard' OR identifier == 'continueHero' OR label BEGINSWITH 'New update,' OR label BEGINSWITH 'Continue,'")).firstMatch
        if !card.waitForExistence(timeout: 10), inTabletop { throw XCTSkip("Tabletop's upper half is view only: its deck card is not an accessibility target") }
        XCTAssertTrue(card.exists, "a hero card")
        assertFrames("library")
        if card.isHittable { card.tap() } else { throw XCTSkip("hero not tappable in this pose (Tabletop standing half is view only)") }
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label CONTAINS 'Update'")).firstMatch.waitForExistence(timeout: 10))
        attach("hero-opened")
    }

    /// 0.5.0 Upcoming: the switch, the empty state and tapping a tile open a game.
    func testUpcomingTabAndWatchlist() throws {
        launch("demo")   // seeds the demo collection: the switch only shows with games (an earlier first-run test leaves the store empty)
        XCTAssertTrue(switchTo("Upcoming"), "Upcoming control (picker, or the Tabletop rail)")
        let empty = app.staticTexts["Nothing on your watchlist yet"]
        let tile = app.buttons.matching(NSPredicate(format: "label CONTAINS 'releases' OR label CONTAINS 'Date to be announced'")).firstMatch
        XCTAssertTrue(empty.waitForExistence(timeout: 10) || tile.waitForExistence(timeout: 10), "empty copy or upcoming tiles")
        assertFrames("library-upcoming")
        attach("upcoming")
        XCTAssertTrue(switchTo("Playing"), "Playing control")
        XCTAssertTrue(app.buttons["Add game"].firstMatch.waitForExistence(timeout: 5))
    }

    /// News strip and News chapter: never a blank page; one of the three states is always shown.
    func testNewsChapterIsNeverBlank() throws {
        launch("chapter/dawnwalker/news")
        let states = ["No news yet", "Loading news", "Official"]
        let failed = app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH \"Couldn't load news\"")).firstMatch
        func shown() -> Bool {
            // Tabletop (Iris): the stage is read only, never hidden from VoiceOver. A headline row is one combined text element
            // ("<title>, <date>, Official"), so look for the tag in any element's label.
            if inTabletop {
                let row = app.descendants(matching: .any).matching(NSPredicate(format: "label CONTAINS ', Official' OR label BEGINSWITH 'No news yet' OR label BEGINSWITH 'Loading news' OR label BEGINSWITH \"Couldn't load news\"")).firstMatch
                return row.waitForExistence(timeout: 5)
            }
            return states.contains { app.staticTexts[$0].waitForExistence(timeout: 3) } || failed.exists
                || app.staticTexts.matching(NSPredicate(format: "label == 'Official'")).firstMatch.exists
        }
        var seen = shown()
        // Tabletop (48404f1): the chapter chips and search row fill the half-height page and the News body sits below them, in
        // a lazy list that draws nothing until scrolled. Scroll the page itself, then look again.
        var scrolls = 0
        while !seen && scrolls < 4 {
            // Not on Tabletop's stage: view only means no touch, and the News body must be in the tree without any scrolling there.
            let page = app.descendants(matching: .any)["pageScroll"]
            if !inTabletop { (page.exists ? page : app).swipeUp() }
            scrolls += 1
            seen = shown()
        }
        if !seen {
            let tree = XCTAttachment(string: app.debugDescription); tree.name = "news-hierarchy.txt"; tree.lifetime = .keepAlways; add(tree)
        }
        // Iris, 15:20: view only means no touch, never hidden from VoiceOver. In Tabletop the upper stage must still expose the News body.
        XCTAssertTrue(seen, "News shows a list, the empty copy or the retry (Tabletop: readable by VoiceOver in the upper stage)")
        assertFrames("news")
        attach("news")
    }

    // MARK: - Reading

    /// Iris (15:20): the Tabletop upper stage is view only, never hidden from VoiceOver. The Updates chapter shows the release's
    /// title and body in the stage; both must be in the accessibility tree there, and neither may be an action.
    func testTabletopStageIsReadable() throws {
        launch("release/dawnwalker/dawnwalker@1.1")
        guard inTabletop else { throw XCTSkip("the stage is a Tabletop surface") }
        let title = app.descendants(matching: .any)["releaseTitle"]
        let body = app.descendants(matching: .any)["readerBody"]
        XCTAssertTrue(title.waitForExistence(timeout: 10), "the stage's release title is in the tree (VoiceOver can read it)")
        XCTAssertTrue(body.waitForExistence(timeout: 5), "the stage's body is in the tree (VoiceOver can read it)")
        XCTAssertFalse(title.label.isEmpty, "the title has a label")
        XCTAssertFalse(body.label.isEmpty, "the body has text")
        let tree = XCTAttachment(string: app.debugDescription); tree.name = "tabletop-stage-hierarchy.txt"; tree.lifetime = .keepAlways; add(tree)
    }

    /// Iris (7 Nov, signing #393): in Tabletop the News headlines and the Gallery empty-state links are text in the stage's
    /// accessibility tree, and none of them is an action: no button, no link trait.
    func testTabletopNewsAndLinksAreReadableText() throws {
        launch("chapter/dawnwalker/news")
        guard inTabletop else { throw XCTSkip("the stage is a Tabletop surface") }
        let any = app.descendants(matching: .any)
        let row = any.matching(NSPredicate(format: "label CONTAINS ', Official' OR label BEGINSWITH 'No news yet' OR label BEGINSWITH 'Loading news'")).firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 10), "News (headline row, or its empty or loading copy) is in the tree")
        XCTAssertFalse(row.label.isEmpty)
        XCTAssertNotEqual(row.elementType, .button, "a News headline is text, not a button, in Tabletop")
        XCTAssertNotEqual(row.elementType, .link, "a News headline is text, not a link, in Tabletop")
        XCTAssertEqual(app.buttons.matching(NSPredicate(format: "label CONTAINS ', Official'")).count, 0, "no News headline is exposed as a button")
        XCTAssertEqual(app.links.matching(NSPredicate(format: "label CONTAINS ', Official'")).count, 0, "no News headline is exposed as a link")
        let newsTree = XCTAttachment(string: app.debugDescription); newsTree.name = "tabletop-news-hierarchy.txt"; newsTree.lifetime = .keepAlways; add(newsTree)

        // The Gallery empty state (Astro Bot and Ghost of Yotei have no art or videos): "Find trailers online" is plain text.
        app.terminate()
        launch("chapter/astro-bot/gallery")
        let trailers = app.descendants(matching: .any).matching(NSPredicate(format: "label == 'Find trailers online'")).firstMatch
        XCTAssertTrue(trailers.waitForExistence(timeout: 10), "the Gallery empty state's trailer text is in the tree")
        XCTAssertEqual(trailers.elementType, .staticText, "it is text in Tabletop, not a link or button")
        XCTAssertEqual(app.links.matching(NSPredicate(format: "label CONTAINS 'Find trailers online' OR label CONTAINS 'Official website'")).count, 0, "no Gallery link has a link trait in Tabletop")
        XCTAssertEqual(app.buttons.matching(NSPredicate(format: "label CONTAINS 'Find trailers online' OR label CONTAINS 'Official website'")).count, 0, "no Gallery link is a button in Tabletop")
        let galleryTree = XCTAttachment(string: app.debugDescription); galleryTree.name = "tabletop-gallery-hierarchy.txt"; galleryTree.lifetime = .keepAlways; add(galleryTree)
    }

    /// Known issues: following toggles and says so.
    func testFollowKnownIssue() throws {
        launch("release/dawnwalker/dawnwalker@1.1")
        let follow = button("Follow this issue")
        guard follow.waitForExistence(timeout: 8) else { throw XCTSkip("no known issue in this fixture's current release") }
        follow.tap()
        XCTAssertTrue(app.staticTexts["Following this issue"].waitForExistence(timeout: 5)
                      || button("Following this issue").waitForExistence(timeout: 5))
        button("Following this issue").tap()
        XCTAssertTrue(app.staticTexts["Stopped following"].waitForExistence(timeout: 5)
                      || button("Follow this issue").waitForExistence(timeout: 5))
    }

    /// Share card: the button is reachable and offers the card.
    func testShareUpdateButton() throws {
        launch("release/dawnwalker/dawnwalker@1.1")
        let share = app.buttons["Share update"]
        XCTAssertTrue(share.waitForExistence(timeout: 10), "Share update is offered (Tabletop: on the lower rail)")
        if inTabletop { XCTAssertGreaterThanOrEqual(share.frame.minY, app.frame.midY - 1, "Tabletop: Share sits in the lower half") }
        XCTAssertGreaterThanOrEqual(share.frame.height, 44, "44 pt target")
        assertFrames("release")
    }

    /// A widget row opens its update (playscribe://release/<game>/<release>).
    func testWidgetDeepLinkOpensUpdate() throws {
        launch("library")
        app.open(URL(string: "playscribe://release/dawnwalker/dawnwalker@1.1")!)
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label CONTAINS 'Update 1.1'")).firstMatch.waitForExistence(timeout: 10))
    }

    // MARK: - First run and adding

    /// Welcome: four rows, Skip for now lands on the empty Library, never a blank page.
    func testFirstRunWelcomeAndSkip() throws {
        launch("first-run")
        XCTAssertTrue(app.staticTexts["Add your games to see every update"].waitForExistence(timeout: 10))
        for row in ["Type it", "Say it", "From a photo", "Scan with camera"] {
            XCTAssertTrue(button(row).exists, row)
        }
        assertFrames("first-run")
        attach("welcome")
        let skip = app.buttons["Skip for now"]
        var swipes = 0
        // Swipe the welcome's own scroll view when there is one: in Book a swipe on the app's centre can land on the other page.
        while !skip.isHittable && swipes < 8 { (app.scrollViews.firstMatch.exists ? app.scrollViews.firstMatch : app).swipeUp(); swipes += 1 }
        if !skip.isHittable {
            let tree = XCTAttachment(string: app.debugDescription); tree.name = "first-run-hierarchy.txt"; tree.lifetime = .keepAlways; add(tree)
        }
        XCTAssertTrue(skip.isHittable, "Skip for now is reachable (scrolling if the welcome is taller than the screen)")
        skip.tap()
        XCTAssertTrue(app.buttons["Add your first game"].waitForExistence(timeout: 5), "the empty Library, not a blank page")
    }

    /// A welcome row opens the Add games sheet on that method.
    func testWelcomeRowOpensAddFlow() throws {
        launch("first-run")
        let type = button("Type it")
        XCTAssertTrue(type.waitForExistence(timeout: 10))
        type.tap()
        if inTabletop { throw XCTSkip("Tabletop has no keyboard: Type it opens a read-only search with an A to Z strip") }
        XCTAssertTrue(app.textFields.firstMatch.waitForExistence(timeout: 10) || app.searchFields.firstMatch.waitForExistence(timeout: 5))
        attach("add-type-it")
    }

    /// The explainer comes before the system prompt, and Not now never dead-ends.
    func testSayItExplainer() throws {
        launch("first-run")
        let say = button("Say it")
        XCTAssertTrue(say.waitForExistence(timeout: 10))
        say.tap()
        guard app.staticTexts["Let Playscribe hear your list"].waitForExistence(timeout: 5) else {
            throw XCTSkip("speech permission already decided on this simulator, so no explainer")
        }
        XCTAssertTrue(app.buttons["Continue"].exists)
        app.buttons["Not now"].tap()
        if inTabletop { throw XCTSkip("Tabletop has no keyboard: Not now opens the read-only search") }
        XCTAssertTrue(app.textFields.firstMatch.waitForExistence(timeout: 5) || app.searchFields.firstMatch.waitForExistence(timeout: 5),
                      "Not now goes to Type it")
    }

    func testCameraExplainerOrDeniedStateOffersTypeIt() throws {
        launch("first-run")
        let scan = button("Scan with camera")
        XCTAssertTrue(scan.waitForExistence(timeout: 10))
        scan.tap()
        let explainer = app.staticTexts["Let Playscribe see your games"]
        let denied = app.staticTexts["Scan with camera is off"]
        let unsupported = app.staticTexts["This device can't scan titles."]
        XCTAssertTrue(explainer.waitForExistence(timeout: 5) || denied.exists || unsupported.exists || app.buttons["Find these games"].exists)
        if explainer.exists { XCTAssertTrue(app.buttons["Continue"].exists && app.buttons["Not now"].exists) }
        if denied.exists || unsupported.exists { XCTAssertTrue(app.buttons["Type it"].exists, "Type it is always offered first") }
    }

    /// J-6c: the pinned bar is at least 44 pt and sits clear of the hinge.
    func testPinnedAddBar() throws {
        launch("add/keyboard")   // Type it, search focused: the sheet opens on the method choice otherwise
        if inTabletop { throw XCTSkip("Tabletop has no keyboard: its add search is read-only with an A to Z strip (#179)") }
        let search = app.textFields.matching(NSPredicate(format: "placeholderValue BEGINSWITH 'Search'")).firstMatch
        XCTAssertTrue(search.waitForExistence(timeout: 10))
        // Open portrait (48404f1): "Neither element nor any descendant has keyboard focus". The route already asks for focus, and
        // a second tap on a focused field can drop it, so wait for focus, tap only if it did not arrive, then wait again.
        func focused() -> Bool { (search.value(forKey: "hasKeyboardFocus") as? Bool) == true }
        let deadline = Date.now.addingTimeInterval(4)
        while !focused() && Date.now < deadline { usleep(250_000) }
        if !focused() { search.tap() }
        let deadline2 = Date.now.addingTimeInterval(4)
        while !focused() && Date.now < deadline2 { usleep(250_000) }
        XCTAssertTrue(focused(), "the add search has keyboard focus")
        search.typeText("Hades")
        let result = app.buttons.matching(NSPredicate(format: "label CONTAINS 'Hades'")).firstMatch
        guard result.waitForExistence(timeout: 10) else { throw XCTSkip("no catalogue match for Hades in this fixture") }
        result.tap()
        let bar = app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Add ' AND (label ENDSWITH ' game' OR label ENDSWITH ' games')")).firstMatch
        XCTAssertTrue(bar.waitForExistence(timeout: 5))
        XCTAssertGreaterThanOrEqual(bar.frame.height, 44)
        assertFrames("add-bar")
    }

    /// A-1, v0.5.3 (Terry, 8 Nov; cc04658 Mac hand check 1): a tap inside the typed text keeps the keyboard and moves the caret; typing
    /// goes on; a tap on a bare area puts the keyboard away.
    func testAddSearchKeepsFocusOnTextTapAndDismissesOnOutsideTap() throws {
        launch("add/keyboard")
        if inTabletop { throw XCTSkip("Tabletop has no keyboard") }
        let search = app.textFields.matching(NSPredicate(format: "placeholderValue BEGINSWITH 'Search'")).firstMatch
        XCTAssertTrue(search.waitForExistence(timeout: 10))
        func focused() -> Bool { (search.value(forKey: "hasKeyboardFocus") as? Bool) == true }
        func waitFocus(_ want: Bool) -> Bool {
            let end = Date.now.addingTimeInterval(4)
            while focused() != want && Date.now < end { usleep(200_000) }
            return focused() == want
        }
        if !waitFocus(true) { search.tap() }
        XCTAssertTrue(waitFocus(true), "the add search has keyboard focus")
        search.typeText("elden")
        // Tap at the leading edge of the typed text, then type again: focus must hold and the caret must have moved to the start.
        // Not mid-word: the 6ef2f42 A/B showed a plain TextField in the same sheet, with none of our code, also leaves the caret at
        // the end after a tap 20 pt into "elden" (likely iOS snapping a single tap to a word boundary). The start is a boundary either way.
        search.coordinate(withNormalizedOffset: CGVector(dx: 0, dy: 0.5)).withOffset(CGVector(dx: 2, dy: 0)).tap()
        usleep(600_000)
        XCTAssertTrue(focused(), "a tap inside the typed text keeps the keyboard")
        XCTAssertTrue(app.keyboards.firstMatch.exists, "the keyboard is still up after a tap in the text")
        search.typeText("x")
        let value = (search.value as? String) ?? ""
        XCTAssertTrue(value.lowercased().contains("x") && value.count == 6, "typing continues after the tap, got '\(value)'")
        XCTAssertEqual(value.lowercased(), "xelden", "the caret moved to the start of the text")
        // A tap on a bare area (the sheet title bar) puts the keyboard away.
        app.navigationBars.firstMatch.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
        if !waitFocus(false) {
            // 69d27ce Mac run, Open portrait: the sheet's bar centre did not dismiss. Fall back to a bare list area, the section header.
            let header = app.staticTexts.matching(NSPredicate(format: "label CONTAINS[c] 'Best matches' OR label CONTAINS[c] 'Popular on PS5'")).firstMatch
            if header.exists { header.tap() }
        }
        XCTAssertTrue(waitFocus(false), "a tap outside the field dismisses the keyboard")
    }

    /// A-1, v0.5.3 (Quinn, 9d41ce0 hand check): a tap on the field's row padding right after the keyboard was put away must bring it
    /// back, every time. Ten rounds of title tap, then padding tap; the focus state is read from UIKit each time.
    func testAddSearchPaddingTapAfterDismissAlwaysFocuses() throws {
        launch("add/keyboard")
        if inTabletop { throw XCTSkip("Tabletop has no keyboard") }
        let search = app.textFields.matching(NSPredicate(format: "placeholderValue BEGINSWITH 'Search'")).firstMatch
        XCTAssertTrue(search.waitForExistence(timeout: 10))
        func focused() -> Bool { (search.value(forKey: "hasKeyboardFocus") as? Bool) == true }
        func wait(_ want: Bool, _ secs: Double = 3) -> Bool {
            let end = Date.now.addingTimeInterval(secs)
            while focused() != want && Date.now < end { usleep(100_000) }
            return focused() == want
        }
        if !wait(true, 5) { search.tap() }
        XCTAssertTrue(wait(true, 5), "the add search starts focused")
        // VoiceOver: the row is one "Search" field, not a field plus a second tappable element.
        // Only the Add sheet's own field: the Library's "Search your library" field sits behind the sheet in the same window and is
        // in the element tree too (36d340c Mac run counted 2 on bbcbbe2 as well, so it is not a duplicate in the Add row).
        let addFields = app.textFields.matching(NSPredicate(format: "placeholderValue CONTAINS 'PS5 games'"))
        XCTAssertEqual(addFields.count, 1, "one Add search field; Search fields in the tree: \(app.textFields.allElementsBoundByIndex.map { $0.placeholderValue ?? "?" })")
        // Scoped to the field's own row: the tab bar's Search tab (b880cc8 Mac run) is also a "Search" button, elsewhere on screen.
        let overlapping = app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Search'")).allElementsBoundByIndex
            .filter { $0.frame.intersects(search.frame) }
        XCTAssertEqual(overlapping.count, 0, "no second Search element over the field: \(overlapping.map(\.label))")
        var misses: [Int] = []
        var log: [String] = []
        func shot(_ name: String) {
            let a = XCTAttachment(screenshot: app.screenshot()); a.name = name; a.lifetime = .keepAlways; add(a)
        }
        func state(_ tag: String) -> String {
            "\(tag): focus=\(focused()) keyboard=\(app.keyboards.firstMatch.exists) fieldFrame=\(search.frame)"
        }
        for round in 1...10 {
            let before = state("r\(round) start")
            let bar = app.navigationBars.firstMatch
            let titlePoint = bar.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
            titlePoint.tap()
            let titleDismissed = wait(false)
            let afterTitle = state("r\(round) after title tap (bar \(bar.frame), dismissed=\(titleDismissed))")
            if !titleDismissed { shot("r\(round)-title-did-not-dismiss"); log += [before, afterTitle]; misses.append(round); continue }
            // Padding: just outside the field's leading edge, inside the row.
            let f = search.frame
            // Rounds cycle through the four sides of the row padding: leading, trailing, above and below the field (the row has
            // 4 pt of vertical padding; the horizontal strips are kept inside the window).
            let windowMaxX = app.windows.firstMatch.frame.maxX
            let side = ["leading", "trailing", "above", "below"][(round - 1) % 4]
            let paddingX: CGFloat, paddingY: CGFloat
            switch side {
            case "leading": (paddingX, paddingY) = (f.minX - 8, f.midY)
            case "trailing": (paddingX, paddingY) = (min(f.maxX + 8, windowMaxX - 2), f.midY)
            case "above": (paddingX, paddingY) = (f.midX, f.minY - 2)
            default: (paddingX, paddingY) = (f.midX, f.maxY + 2)
            }
            app.windows.firstMatch.coordinate(withNormalizedOffset: .zero).withOffset(CGVector(dx: paddingX, dy: paddingY)).tap()
            let refocused = wait(true)
            let afterPadding = state("r\(round) after \(side) padding tap at (\(paddingX), \(paddingY)), insideFieldFrame=\(f.contains(CGPoint(x: paddingX, y: paddingY))), refocused=\(refocused)")
            log += [before, afterTitle, afterPadding]
            if !refocused {
                shot("r\(round)-padding-did-not-focus")
                misses.append(round)
                // Recover so each round is measured on its own: a tap inside the field.
                search.tap(); _ = wait(true)
            }
        }
        print("PADDINGTAP LOG\n" + log.joined(separator: "\n"))
        let logAttachment = XCTAttachment(string: log.joined(separator: "\n")); logAttachment.name = "padding-tap-log"; logAttachment.lifetime = .keepAlways; add(logAttachment)
        XCTAssertTrue(misses.isEmpty, "title tap then padding tap failed in rounds \(misses); see the padding-tap-log attachment")
    }

    // MARK: - Accessibility (G-7, G-10)

    /// The new screens pass the system audit for hit regions and element descriptions.
    func testNewScreensPassAccessibilityAudit() throws {
        for route in ["first-run", "chapter/dawnwalker/news"] {
            app.launchArguments = ["-qaRoute", route]
            app.launch()
            sleep(2)
            try app.performAccessibilityAudit(for: [.hitRegion, .sufficientElementDescription]) { issue in
                issue.element?.elementType == .image
            }
            app.terminate()
        }
    }

    /// Every 0.5.0 surface keeps the frame rules in the current pose: no frame crosses a division,
    /// and in Tabletop nothing tappable sits above the fold. Upcoming is reached from the rail.
    func testNewSurfacesKeepFrameRules() throws {
        let routes = ["demo", "chapter/dawnwalker/news", "updates", "release/dawnwalker/dawnwalker@1.1",
                      "add", "settings", "first-run"]
        for route in routes {
            app.launchArguments = ["-qaRoute", route]
            app.launch()
            sleep(2)
            assertFrames(route)
            if route == "demo" {
                if pose().contains("pose: tabletop") {
                    let rail = app.descendants(matching: .any)["upcomingRail"]
                    XCTAssertTrue(rail.waitForExistence(timeout: 10), "Upcoming rail button")
                    XCTAssertGreaterThanOrEqual(rail.frame.minY, app.frame.midY - 1, "Upcoming rail button is on the flat half")
                }
                XCTAssertTrue(switchTo("Upcoming"), "Upcoming control")
                sleep(1)
                assertFrames("library-upcoming")
            }
            app.terminate()
        }
    }
}
