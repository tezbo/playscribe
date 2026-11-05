import SwiftUI
import Testing
import UIKit
@testable import Playscribe

/// The fold harness (docs/fold-harness.md): the real RootView laid out at each pose's exact container, fold and size
/// class in an offscreen UIKit window, with the layout rules asserted on the frames. No Device Hub, no pose driver.
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
            #expect(CGRect(origin: .zero, size: p.container).contains(fold), "\(p.id): the fold lies inside the container")
        }
    }

    // MARK: Layout rules at the default text size

    @Test(arguments: ["closed", "closedLandscape", "open", "openPortrait", "book", "tabletop"])
    func libraryRulesHold(_ id: String) async throws {
        let p = HarnessPose.named(id)
        let r = try #require(await FoldHost.render(p), "\(p.id): a window scene to host in")
        defer { FoldHost.dispose(r) }
        // `HARNESS_DUMP_DIR=/tmp/h xcodebuild test …` leaves <pose>.json for compare_harness.py.
        if let dir = ProcessInfo.processInfo.environment["HARNESS_DUMP_DIR"] {
            try? FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
            try? r.probeJSON.write(toFile: "\(dir)/\(p.id).json", atomically: true, encoding: .utf8)
        }
        HarnessRules.require(r.livePose == p.expected, "\(p.id): the injected fold gave pose \(r.livePose), expected \(p.expected)")
        // TT-0 is reported, not asserted, where the system lays pages out (ArrangementView splits at the window's real
        // reserved region, which an offscreen window does not have): the first CI run put Book's right page at x 475, inside
        // the injected 455 to 495 fold, which the simulator never does. The real-hinge gate keeps TT-0 (docs/fold-harness.md).
        if !r.foldCrossings.isEmpty {
            print("harness error: [info, not asserted] \(p.id) TT-0: frames cross the injected fold \(String(describing: r.division)): \(r.foldCrossings.map(HarnessRules.brief))")
        }
        HarnessRules.require(r.aboveTheFold.isEmpty, "\(p.id) G-4: tappable frames above the Tabletop fold: \(r.aboveTheFold.map(HarnessRules.brief))")
        HarnessRules.checkDeck(r, maxFraction: p.id == "tabletop" ? nil : 0.5)
        if p.id == "closed" || p.id == "open" { HarnessRules.checkDeck(r, maxFraction: 0.38) }
        if p.expected != .tabletop { HarnessRules.checkLibraryToolbar(r) }
    }

    // MARK: Accessibility text sizes (7fe84f4, AX3)

    @Test(arguments: ["closed", "open", "openPortrait"], [0, 1])
    func deckStaysBoundedAtAccessibilitySizes(_ id: String, _ sizeIndex: Int) async throws {
        let p = HarnessPose.named(id)
        let size: UIContentSizeCategory = sizeIndex == 0 ? .accessibilityExtraLarge : .accessibilityExtraExtraExtraLarge
        let r = try #require(await FoldHost.render(p, type: size))
        defer { FoldHost.dispose(r) }
        HarnessRules.checkDeck(r, maxFraction: 0.5)
    }
}

/// The frame rules, shared by the harness tests and (later) by sim-side captures.
@MainActor
enum HarnessRules {
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
        require(deck.height <= limit, "\(r.pose.id) J-5: deck \(Int(deck.width)) x \(Int(deck.height)) pt is over \(Int(limit)) pt", sourceLocation: sourceLocation)
    }

    /// TB-1: Settings and Add are both drawn by UIKit, inside the window, and at least 44 pt to touch.
    static func checkLibraryToolbar(_ r: Rendered, sourceLocation: SourceLocation = #_sourceLocation) {
        for (name, frame) in [("Settings", r.uikitControl(identifier: "settingsButton")), ("Add game", r.uikitControl(label: "Add game"))] {
            guard let f = frame else {
                fail("\(r.pose.id) TB-1: the \(name) button was not drawn in the navigation bar. UIKit drew: \(r.topInventory)", sourceLocation: sourceLocation)
                continue
            }
            require(f.width >= 43.5 && f.height >= 43.5, "\(r.pose.id) TB-1: \(name) is \(Int(f.width)) x \(Int(f.height)), under 44 pt", sourceLocation: sourceLocation)
        }
    }
}
