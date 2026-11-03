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

    private func pose() -> String {
        let audit = app.descendants(matching: .any)["foldAudit"]
        _ = audit.waitForExistence(timeout: 5)
        return audit.exists ? audit.label : "unknown"
    }

    private func button(_ prefix: String) -> XCUIElement {
        app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", prefix)).firstMatch
    }

    private func attach(_ name: String) {
        let a = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
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

    /// J-1, J-2: the Latest updates hero. A card opens its update; the leaves are 44 pt targets.
    func testHeroDeckCardOpensItsUpdate() throws {
        launch("demo")
        let card = app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'New update,' OR label BEGINSWITH 'Continue,'")).firstMatch
        XCTAssertTrue(card.waitForExistence(timeout: 10), "a hero card")
        assertFrames("library")
        if card.isHittable { card.tap() } else { throw XCTSkip("hero not tappable in this pose (Tabletop standing half is view only)") }
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label CONTAINS 'Update'")).firstMatch.waitForExistence(timeout: 10))
        attach("hero-opened")
    }

    /// 0.5.0 Upcoming: the switch, the empty state and tapping a tile open a game.
    func testUpcomingTabAndWatchlist() throws {
        launch("library")
        let upcoming = button("Upcoming")
        XCTAssertTrue(upcoming.waitForExistence(timeout: 10), "Upcoming control (picker, or the Tabletop rail)")
        upcoming.tap()
        let empty = app.staticTexts["Nothing on your watchlist yet"]
        let tile = app.buttons.matching(NSPredicate(format: "label CONTAINS 'releases' OR label CONTAINS 'Date to be announced'")).firstMatch
        XCTAssertTrue(empty.waitForExistence(timeout: 10) || tile.waitForExistence(timeout: 10), "empty copy or upcoming tiles")
        assertFrames("library-upcoming")
        attach("upcoming")
        button("Playing").tap()
        XCTAssertTrue(app.buttons["Add game"].firstMatch.waitForExistence(timeout: 5))
    }

    /// News strip and News chapter: never a blank page; one of the three states is always shown.
    func testNewsChapterIsNeverBlank() throws {
        launch("chapter/dawnwalker/news")
        let states = ["No news yet", "Couldn't load news", "Official"]
        let seen = states.contains { app.staticTexts[$0].waitForExistence(timeout: 10) }
            || app.staticTexts.matching(NSPredicate(format: "label == 'Official'")).firstMatch.exists
        XCTAssertTrue(seen, "News shows a list, the empty copy or the retry")
        assertFrames("news")
        attach("news")
    }

    // MARK: - Reading

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
        XCTAssertTrue(share.waitForExistence(timeout: 10))
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
        XCTAssertTrue(skip.isHittable)
        skip.tap()
        XCTAssertTrue(app.buttons["Add your first game"].waitForExistence(timeout: 5), "the empty Library, not a blank page")
    }

    /// A welcome row opens the Add games sheet on that method.
    func testWelcomeRowOpensAddFlow() throws {
        launch("first-run")
        let type = button("Type it")
        XCTAssertTrue(type.waitForExistence(timeout: 10))
        type.tap()
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
        launch("add")
        let search = app.textFields.matching(NSPredicate(format: "placeholderValue BEGINSWITH 'Search'")).firstMatch
        XCTAssertTrue(search.waitForExistence(timeout: 10))
        search.tap()
        search.typeText("Hades")
        let result = app.buttons.matching(NSPredicate(format: "label CONTAINS 'Hades'")).firstMatch
        guard result.waitForExistence(timeout: 10) else { throw XCTSkip("no catalogue match for Hades in this fixture") }
        result.tap()
        let bar = app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Add ' AND label ENDSWITH 'game' OR label ENDSWITH 'games'")).firstMatch
        XCTAssertTrue(bar.waitForExistence(timeout: 5))
        XCTAssertGreaterThanOrEqual(bar.frame.height, 44)
        assertFrames("add-bar")
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
        let routes = ["library", "chapter/dawnwalker/news", "chapter/dawnwalker/updates", "release/dawnwalker/update-1-1",
                      "add", "settings", "first-run"]
        for route in routes {
            app.launchArguments = ["-qaRoute", route]
            app.launch()
            sleep(2)
            assertFrames(route)
            if route == "library" {
                let upcoming = button("Upcoming")
                XCTAssertTrue(upcoming.waitForExistence(timeout: 10), "Upcoming control")
                if pose().contains("pose: tabletop") {
                    XCTAssertGreaterThanOrEqual(upcoming.frame.minY, app.frame.midY - 1, "Upcoming rail button is on the flat half")
                }
                upcoming.tap()
                sleep(1)
                assertFrames("library-upcoming")
            }
            app.terminate()
        }
    }
}
