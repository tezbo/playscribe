import SwiftUI
import Testing
import UIKit
@testable import Playscribe

/// The fold harness (docs/fold-harness.md): the real RootView laid out at each pose's exact container, fold and size
/// class in an offscreen UIKit window, with the layout rules asserted on the frames. No Device Hub, no pose driver.
///
/// SCOPE (Quinn, #227; docs/fold-harness.md, qa test plan): this harness may FAIL a build on the pose, fold, occlusion, safe-area
/// and rail-placement checks, but it never counts as a pass or a sign-off; sign-offs need real stills on the Mac gate.
/// Frames are 84-88 pt narrow in Closed, Open, Closed landscape and Tabletop (the tab view draws a vertical tab bar here that
/// the Duo does not), about 14 pt high in y, and 44 pt left in Open portrait and Book. So: do not assert widths, wrapping or x;
/// keep any above-the-fold or hinge-band check one-sided with a margin of at least 14 pt (fail only on something clearly
/// inside the band, never claim a pass near the edge); say nothing about Tabletop's lower half (rail overflow, Previous/Next).
///
/// Rules cited: G-4 (nothing tappable above the Tabletop fold), TT-0 (nothing crosses the fold), TB-1 (the Library
/// toolbar always shows Settings and Add), J-5 (the hero deck is bounded; e869273 had 835 x 727 pt).
@MainActor
struct FoldHarnessTests {
    // MARK: Pose derivation (pure)

    @Test(arguments: ["closed", "closedLandscape", "open", "openPortrait", "book", "tabletop"])
    func catalogPoseMatchesWhatDuoReaderDerives(_ id: String) {
        let p = HarnessPose.named(id)
        let ctx = DuoReader<EmptyView>.context(size: p.container, compact: p.compactWidth,
                                               division: p.division, occlusions: p.occlusions)
        #expect(ctx.pose == p.expected, "\(p.id)")
        if let fold = p.division {
            #expect(CGRect(origin: .zero, size: p.windowSize).contains(fold), "\(p.id): the fold lies inside the window (it runs under the bottom inset in the sim)")
        }
    }

    // MARK: Toolbar slots (TB-1)

    /// 551d8ce: Add and Settings shared one trailing group and the system dropped one in every pose but Tabletop. An
    /// offscreen window cannot show that, so assert the cause: every Library toolbar item has a slot of its own.
    /// The overlap rule must fire on a crossing pair and stay quiet on containment and separate frames, or its green means nothing.
    @Test func overlapRuleFindsCrossingFramesOnly() {
        let a = CGRect(x: 0, y: 0, width: 100, height: 40)
        #expect(HarnessRules.overlappingPairs([a, CGRect(x: 60, y: 20, width: 100, height: 40)]).count == 1)
        #expect(HarnessRules.overlappingPairs([a, CGRect(x: 10, y: 5, width: 30, height: 30)]).isEmpty)
        #expect(HarnessRules.overlappingPairs([a, CGRect(x: 0, y: 60, width: 100, height: 40)]).isEmpty)
    }

    @Test func libraryToolbarItemsEachHaveTheirOwnSlot() {
        let slots = [LibraryToolbar.settings, LibraryToolbar.add, LibraryToolbar.viewMenu]
        #expect(Set(slots).count == slots.count, "TB-1: two Library toolbar items share a slot: \(slots)")
        #expect(LibraryToolbar.settings == .leading, "TB-1: Settings leads, so it is never collapsed with Add")
    }

    // MARK: Layout rules at the default text size

    @Test(arguments: ["closed", "closedLandscape", "open", "openPortrait", "book", "tabletop"])
    func libraryRulesHold(_ id: String) async throws {
        let p = HarnessPose.named(id)
        let r = try #require(await FoldHost.render(p), "\(p.id): a window scene to host in")
        defer { FoldHost.dispose(r) }
        // `TEST_RUNNER_HARNESS_DUMP_DIR=/tmp/h xcodebuild test …` leaves <pose>.json for compare_harness.py.
        if let dir = ProcessInfo.processInfo.environment["HARNESS_DUMP_DIR"] {
            try? FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
            try? r.probeJSON.write(toFile: "\(dir)/\(p.id).json", atomically: true, encoding: .utf8)
        }
        HarnessRules.require(r.geometryProblem == nil, "\(p.id): the harness did not reproduce the pose geometry: \(r.geometryProblem ?? "")")
        HarnessRules.require(r.livePose == p.expected, "\(p.id): the injected fold gave pose \(r.livePose), expected \(p.expected)")
        // TT-0 is reported, not asserted, where the system lays pages out (ArrangementView splits at the window's real
        // reserved region, which an offscreen window does not have): the first CI run put Book's right page at x 475, inside
        // the injected 455 to 495 fold, which the simulator never does. The real-hinge gate keeps TT-0 (docs/fold-harness.md).
        if !r.foldCrossings.isEmpty {
            print("harness error: [info, not asserted] \(p.id) TT-0: frames cross the injected fold \(String(describing: r.division)): \(r.foldCrossings.map(HarnessRules.brief))")
        }
        if !r.navigationBandFrames.isEmpty {
            print("harness error: [info, not asserted] \(p.id) G-4: navigation-bar band frames not asserted offscreen: \(r.navigationBandFrames.map(HarnessRules.brief))")
        }
        // Tabletop's rail and pages are placed by the system's ArrangementView at the window's real reserved region. Offscreen
        // the harness laid the rail out as a horizontal row at y 335 and 393, across the fold, where the Duo has a vertical
        // column at x 619 (Mac calibration, 55240fc). So G-4 for Tabletop is reported here and asserted by the real-hinge gate.
        if p.id == "tabletop" {
            if !r.aboveTheFold.isEmpty {
                print("harness error: [info, not asserted] tabletop G-4: tappable frames above the fold offscreen: \(r.aboveTheFold.map(HarnessRules.brief))")
            }
        } else {
            HarnessRules.require(r.aboveTheFold.isEmpty, "\(p.id) G-4: tappable frames above the Tabletop fold: \(r.aboveTheFold.map(HarnessRules.brief))")
        }
        // Widths: Closed is calibrated (deck 346 pt in the 382 pt container with 16 pt margins; before #360's fix 262 pt). One-sided, with
        // margin: fail only when the deck is clearly narrower than the container allows. Other poses are not yet calibrated.
        if p.id == "closed", let deck = r.named["latestDeck"] {
            HarnessRules.require(deck.width >= 330, "closed: deck is \(Int(deck.width)) pt wide in a \(Int(p.container.width)) pt container (expected about 346; the trailing inset is counted twice if it is 262)")
        }
        HarnessRules.checkDeck(r, maxFraction: p.id == "tabletop" ? nil : 0.5)
        if p.id == "closed" || p.id == "open" { HarnessRules.checkDeck(r, maxFraction: 0.38) }
        if p.expected != .tabletop { HarnessRules.checkLibraryToolbar(r) }
    }

    // MARK: Accessibility text sizes (7fe84f4, AX3; all poses at AX3 and AX5 since the #292 / landscape-width review)

    /// The deck bound at AX3 and AX5 in the three poses it was asserted in before. A hung or looping layout (#292 in Tabletop) now
    /// fails this test by name through the time limit instead of stalling the run.
    @Test(.timeLimit(.minutes(2)), arguments: ["closed", "open", "openPortrait"], [0, 1])
    func deckStaysBoundedAtAccessibilitySizes(_ id: String, _ sizeIndex: Int) async throws {
        let p = HarnessPose.named(id)
        let size: UIContentSizeCategory = sizeIndex == 0 ? .accessibilityExtraLarge : .accessibilityExtraExtraExtraLarge
        let r = try #require(await HarnessRules.timedRender(p, type: size))
        defer { FoldHost.dispose(r) }
        HarnessRules.checkDeck(r, maxFraction: 0.5)
    }

    /// Every pose at AX3 and AX5: it must render within the time budget (a layout loop or hang fails here, naming pose and size),
    /// and no tappable frame may overflow the trailing edge (G-8).
    @Test(.timeLimit(.minutes(2)), arguments: ["closed", "closedLandscape", "open", "openPortrait", "book", "tabletop"], [0, 1])
    func everyPoseRendersAndStaysInsideAtAccessibilitySizes(_ id: String, _ sizeIndex: Int) async throws {
        let p = HarnessPose.named(id)
        let size: UIContentSizeCategory = sizeIndex == 0 ? .accessibilityExtraLarge : .accessibilityExtraExtraExtraLarge
        let r = try #require(await HarnessRules.timedRender(p, type: size), "\(p.id): a window scene to host in")
        defer { FoldHost.dispose(r) }
        HarnessRules.reportOverflow(r, size: sizeIndex == 0 ? "AX3" : "AX5")
        HarnessRules.reportOverlap(r, size: sizeIndex == 0 ? "AX3" : "AX5")
    }
}

/// The frame rules, shared by the harness tests and (later) by sim-side captures.
@MainActor
enum HarnessRules {
    /// Render budget. The usual render settles for 1.8 s; anything past this is a layout loop or hang (#292, Tabletop).
    /// 90 s, not 20: a shared macOS runner under load took 47 s for one Book render (#386) with no layout problem. The simulator
    /// does not inherit the runner's environment, so there is no reliable "am I on CI" switch; one generous budget it is. A real
    /// loop never settles and still fails the test's `.timeLimit(.minutes(2))`, which is the hang net.
    static let renderBudget: Double = 90

    /// `FoldHost.render` with a wall-clock check, so a slow or looping layout fails with the pose and size in the message.
    static func timedRender(_ pose: HarnessPose, type: UIContentSizeCategory, model: AppModel = FoldHost.demoModel(), sourceLocation: SourceLocation = #_sourceLocation) async -> Rendered? {
        let start = ContinuousClock.now
        let r = await FoldHost.render(pose, type: type, model: model)
        let d = ContinuousClock.now - start
        let secs = Double(d.components.seconds) + Double(d.components.attoseconds) / 1e18
        if secs > renderBudget {
            fail("\(pose.id) at \(type.rawValue): rendering took \(Int(secs)) s, over the \(Int(renderBudget)) s budget (layout loop or hang?)", sourceLocation: sourceLocation)
        }
        return r
    }

    /// One-sided: a tappable frame reaching past the container's trailing edge by more than 20 pt is clearly overflowing, even with the
    /// harness's 84 to 88 pt narrowing (which can only hide overflow, never invent it). Tabletop's rail is laid out by the system at the
    /// real region and is skipped. Asserted since the first CI run (9bb77b3) showed no overflow in any pose at AX3 or AX5.
    static func reportOverflow(_ r: Rendered, size: String) {
        // Book's pages are split by the system's ArrangementView at the window's real fold, which offscreen starts the right page at
        // x 475 (inside the fold) instead of 495, so a full-width page overruns by 23 pt (#360 run fa44e8e).
        guard r.pose.expected != .tabletop else { return }
        // Book: the offscreen right page starts 20 pt early (x 475, not 495) and runs 23 pt past the container, so a clear overflow
        // has to pass that known placement gap as well. This only catches a gross overrun; the Mac gate is still the Book check.
        let limit = r.pose.container.width + 20 + (r.pose.expected == .book ? 23 : 0)
        let over = r.frames.filter { $0.width > 1 && $0.height > 1 && $0.maxX > limit }
        require(over.isEmpty, "\(r.pose.id) \(size) G-8 overflow: tappable frames past the trailing edge (\(Int(limit)) pt): \(over.map(brief))")
    }

    /// G-8 / TT-0 sibling overlap. Two tappable frames that cross without one containing the other (a chip over a title, a button
    /// over a button) cannot both be hit. Containment is allowed (a card holds its own chips). Printed with the pairs; asserted
    /// only for Closed, Open and Open portrait, where the overflow rule is already calibrated against the Mac. Tabletop's rail is
    /// placed by the system and Book's pages are shifted offscreen, so those two are reported only.
    static func reportOverlap(_ r: Rendered, size: String) {
        let pairs = overlappingPairs(r.frames)
        guard !pairs.isEmpty else { return }
        let message = "\(r.pose.id) \(size) G-8 overlap: \(pairs.count) tappable pair(s) cross: \(pairs.prefix(6))"
        let asserted = r.pose.expected != .tabletop && r.pose.expected != .book && !r.pose.inferred
        if asserted { require(false, message) } else { print("harness error: [info, not asserted] \(message)") }
    }

    /// Pairs of frames that cross by more than 4 pt each way without one containing the other (2 pt slack).
    static func overlappingPairs(_ frames: [CGRect]) -> [String] {
        let fs = frames.filter { $0.width > 8 && $0.height > 8 }
        var pairs: [String] = []
        for i in fs.indices {
            for j in fs.indices where j > i {
                let a = fs[i], b = fs[j], x = a.intersection(b)
                guard !x.isNull, x.width > 4, x.height > 4 else { continue }
                if a.insetBy(dx: -2, dy: -2).contains(b) || b.insetBy(dx: -2, dy: -2).contains(a) { continue }
                pairs.append("\(brief(a)) x \(brief(b))")
            }
        }
        return pairs
    }

    /// One-line failures that say "failed", so the CI log's grep shows them (and so a reader sees the numbers).
    static func require(_ ok: Bool, _ message: String, sourceLocation: SourceLocation = #_sourceLocation) {
        if !ok { fail(message, sourceLocation: sourceLocation) }
    }
    /// Also printed with "error:" so the CI step's grep shows it (Swift Testing's own issue lines are not matched).
    static func fail(_ message: String, sourceLocation: SourceLocation = #_sourceLocation) {
        print("harness error: \(message)")
        Issue.record("harness failed: \(message)", sourceLocation: sourceLocation)
    }
    static func brief(_ r: CGRect) -> String { "\(Int(r.minX)),\(Int(r.minY)) \(Int(r.width))x\(Int(r.height))" }
    /// The deck is at most `maxFraction` of the container height, plus 12 pt of slack (the same slack as the UI test).
    static func checkDeck(_ r: Rendered, maxFraction: CGFloat?, sourceLocation: SourceLocation = #_sourceLocation) {
        guard let maxFraction else { return }
        guard let deck = r.named["latestDeck"] else {
            fail("\(r.pose.id): the Latest updates deck was not on screen", sourceLocation: sourceLocation)
            return
        }
        let limit = r.pose.container.height * maxFraction + 12
        let message = "\(r.pose.id) J-5: deck \(Int(deck.width)) x \(Int(deck.height)) pt is over \(Int(limit)) pt"
        if r.pose.inferred {
            if deck.height > limit { print("harness error: [info, not asserted, insets inferred] \(message)") }
        } else {
            require(deck.height <= limit, message, sourceLocation: sourceLocation)
        }
    }

    /// TB-1, reported and not asserted. The first CI runs showed an offscreen window does not reproduce UIKit's toolbar:
    /// Closed drew bar buttons without accessibility labels, and Open, Open portrait and Book drew none, where the Duo
    /// simulator shows Settings and Add in every pose (UI test, 780c25a). So the toolbar stays a simulator check
    /// (PlayscribeUITests, gate.sh), and this prints what UIKit drew so calibration can revisit it.
    static func checkLibraryToolbar(_ r: Rendered) {
        let settings = r.uikitControl(identifier: "settingsButton"), add = r.uikitControl(label: "Add game")
        if settings == nil || add == nil {
            print("harness error: [info, not asserted] \(r.pose.id) TB-1: toolbar not reproduced offscreen. UIKit drew: \(r.topInventory)")
        }
    }
}
