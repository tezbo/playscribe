import Foundation
import Testing
@testable import Playscribe

/// The Closed-pose front cover (docs/cover-motion.md, duo-closed-cover): the motion rules and what the cover says,
/// checked without a simulator.
@MainActor
struct FrontCoverTests {
    private func demoModel() -> AppModel {
        let m = AppModel(storeURL: URL.temporaryDirectory.appending(path: "cover-\(UUID().uuidString).json"))
        m.resetToManyUpdatesDemo()
        return m
    }

    /// CM-1: only Reduce Motion forces Still, whatever the setting says.
    @Test func reduceMotionForcesStill() {
        for mode in CoverMotion.allCases {
            #expect(mode.resolved(reduceMotion: true, autoplay: true) == .still)
            #expect(mode.resolved(reduceMotion: true, autoplay: false) == .still)
        }
    }

    /// CM-1: Autoplay videos off stops only the Trailer loop, which falls back to Key-art motion (not video).
    @Test func autoplayOffStopsOnlyTheTrailer() {
        #expect(CoverMotion.trailer.fallback == .keyArt)
        #expect(CoverMotion.keyArt.fallback == .still)
        for mode in CoverMotion.allCases {
            let expected = mode == .trailer ? CoverMotion.keyArt.resolved(reduceMotion: false, autoplay: true)
                                            : mode.resolved(reduceMotion: false, autoplay: true)
            #expect(mode.resolved(reduceMotion: false, autoplay: false) == expected)
        }
    }

    /// A mode that is not built yet falls back down the chain; Key-art motion is built and is the default (Nadia, 13 Nov).
    @Test func unbuiltModesFallBack() {
        for mode in CoverMotion.allCases {
            #expect(mode.resolved(reduceMotion: false, autoplay: true).isBuilt)
        }
        #expect(CoverMotion.still.isBuilt)
        #expect(CoverMotion.keyArt.isBuilt)
        #expect(!CoverMotion.trailer.isBuilt)
        #expect(CoverMotion.trailer.resolved(reduceMotion: false, autoplay: true) == .keyArt)
        #expect(CoverMotion.defaultMode == .keyArt)
    }

    /// Precedence (Nadia, 13 Nov): a fresh install moves, whatever Autoplay says; Reduce Motion always wins with the still (G-9).
    @Test func defaultMovesAndReduceMotionWins() {
        #expect(CoverMotion.defaultMode.resolved(reduceMotion: false, autoplay: false) == .keyArt)
        #expect(CoverMotion.defaultMode.resolved(reduceMotion: false, autoplay: true) == .keyArt)
        #expect(CoverMotion.defaultMode.resolved(reduceMotion: true, autoplay: true) == .still)
        #expect(CoverMotion.defaultMode.resolved(reduceMotion: true, autoplay: false) == .still)
    }

    /// CM-7: one VoiceOver element, "<Game> cover, update 1.1 on PS5, 22 Oct"; the motion mode is never in it.
    @Test func voiceOverLabelNamesGameUpdateAndDay() {
        let deck = demoModel().latestDeck
        #expect(!deck.isEmpty)
        for card in deck {
            let label = FrontCoverPage.label(card)
            #expect(label.hasPrefix("\(card.game.name) cover"))
            if card.release != nil { #expect(label.contains(" on PS5")) }
            for mode in CoverMotion.allCases { #expect(!label.contains(mode.label)) }
        }
    }

    /// #467 (Mac, 8597112): the cover route's NEW UPDATE pages survive the feed's 72 hour rule, which marks every older
    /// update read after a reset; the deck keeps its read pages too, which show no eyebrow.
    @Test func coverRouteKeepsItsUnreadPages() {
        let m = AppModel(storeURL: URL.temporaryDirectory.appending(path: "cover-\(UUID().uuidString).json"))
        m.handle(url: URL(string: "playscribe://cover")!)
        m.notifyNewlyOnPS5()   // what the first feed refresh after a reset does
        let deck = m.latestDeck
        #expect(deck.count > 1)
        #expect(deck.first?.unread == true)
        // Only the pinned update is unread (the deck repeats it as padding); every other update is read.
        let unreadGames = Set(deck.filter(\.unread).map(\.game.id))
        #expect(unreadGames == [deck.first!.game.id])
        #expect(FrontCoverPreview.shared.open)
        FrontCoverPreview.shared.open = false
    }

    /// `cover/<game>` (Iris, focal-point check): that game's page leads the cover, unread; an unknown game keeps the default.
    @Test func coverRouteCanLeadWithAGame() {
        for id in ["kcd2", "wukong"] {
            let m = AppModel(storeURL: URL.temporaryDirectory.appending(path: "cover-\(UUID().uuidString).json"))
            m.handle(url: URL(string: "playscribe://cover/\(id)")!)
            m.notifyNewlyOnPS5()
            #expect(m.latestDeck.first?.game.id == id)
            #expect(m.latestDeck.first?.unread == true)
        }
        let m = AppModel(storeURL: URL.temporaryDirectory.appending(path: "cover-\(UUID().uuidString).json"))
        m.handle(url: URL(string: "playscribe://cover/no-such-game")!)
        #expect(m.latestDeck.first?.unread == true)
        FrontCoverPreview.shared.open = false
    }

    /// Iris (#467): the focal point never pushes the art off an edge; it lands where asked when there is room.
    @Test func focalCropClampsToTheFrame() {
        let art = CGSize(width: 1600, height: 517), cover = CGSize(width: 466, height: 678)
        let covers: (CGRect) -> Bool = { r in r.minX <= 0.001 && r.minY <= 0.001 && r.maxX >= cover.width - 0.001 && r.maxY >= cover.height - 0.001 }
        for x in stride(from: -0.5, through: 1.5, by: 0.1) {
            for y in stride(from: -0.5, through: 1.5, by: 0.25) {
                for scale in [nil, 0.5, 1, 1.4] as [Double?] {
                    for ty in [0.25, 0.5] {
                        #expect(covers(FocalCrop.place(image: art, in: cover, focus: CoverFocus(x: x, y: y, scale: scale), targetY: ty)))
                    }
                }
            }
        }
        // Room to move: the focal point lands on the cover's centre line.
        let mid = FocalCrop.place(image: art, in: cover, focus: CoverFocus(x: 0.5, y: 0.5))
        #expect(abs(mid.minX + 0.5 * mid.width - cover.width / 2) < 0.5)
        // A zoom lets the point move up into the top half (AX sizes).
        let zoomed = FocalCrop.place(image: art, in: cover, focus: CoverFocus(x: 0.5, y: 0.5, scale: 1.6), targetY: 0.25)
        #expect(zoomed.minY + 0.5 * zoomed.height < cover.height / 2)
        // A scale under 1 never letterboxes.
        let small = FocalCrop.place(image: art, in: cover, focus: CoverFocus(x: 0.5, y: 0.5, scale: 0.5))
        #expect(small.height >= cover.height - 0.001)
    }

    /// Iris (0a4230d): at accessibility sizes the shade is 88 percent or more from the plate's top edge down, ordered stops.
    @Test func accessibilityShadeStartsAtThePlate() {
        for top in [0.2, 0.385, 0.5, 0.9] {
            let stops = FrontCoverPage.fadeStops(accessibility: true, plateTop: top)
            #expect(zip(stops, stops.dropFirst()).allSatisfy { $0.location <= $1.location })
            let atPlate = stops.filter { $0.location >= top - 0.0001 }
            #expect(atPlate.allSatisfy { $0.opacity >= 0.88 })
            #expect(stops.first?.location == 0 && stops.last?.location == 1)
        }
        // Standard sizes keep the signed shade, solid from 90 percent down so no logo in the art ghosts behind the mark.
        let std = FrontCoverPage.fadeStops(accessibility: false, plateTop: 0.4)
        #expect(std.map(\.location) == [0, 0.18, 0.45, 0.82, 0.9, 1])
        #expect(std.filter { $0.location >= 0.9 }.allSatisfy { $0.opacity == 1 })
    }

    /// r060 day-one (Iris on #506): with the "Day-one patch" line above the eyebrow, the standard-size shade follows the plate,
    /// 88 percent or more from the line's top edge (it measured 2.3:1 on the ramp in Closed landscape), solid from 90 percent down.
    @Test func dayOneLineShadeStartsAtThePlate() {
        for top in [0.2, 0.5, 0.7, 0.86, 0.9] {
            let stops = FrontCoverPage.fadeStops(accessibility: false, plateTop: top, followPlate: true)
            #expect(zip(stops, stops.dropFirst()).allSatisfy { $0.location <= $1.location }, "ordered at \(top)")
            #expect(stops.filter { $0.location >= top - 0.0001 }.allSatisfy { $0.opacity >= 0.88 }, "88% from the plate at \(top)")
            #expect(stops.filter { $0.location >= 0.9 }.allSatisfy { $0.opacity == 1 }, "solid foot at \(top)")
            #expect(stops.first?.location == 0 && stops.last?.location == 1)
        }
        // Iris on #506: eased in over plateRamp points, so no row darkens by more than 4/255 over pure white, in Closed
        // landscape (short page) and portrait, at the plate positions the cover lays out; the plate stays 88% or more.
        for (h, tops) in [(300.0, [0.6, 0.7, 0.8]), (420.0, [0.55, 0.7, 0.86]), (678.0, [0.385, 0.5, 0.7, 0.86])] {
            for top in tops {
                for ax in [false, true] {
                    let stops = FrontCoverPage.fadeStops(accessibility: ax, plateTop: top, followPlate: !ax, pageHeight: h)
                    #expect(zip(stops, stops.dropFirst()).allSatisfy { $0.location <= $1.location }, "ordered \(h) \(top)")
                    #expect(stops.filter { $0.location >= top - 0.0001 }.allSatisfy { $0.opacity >= 0.88 }, "plate \(h) \(top)")
                    var last = Self.opacity(stops, at: 0)
                    var worst = 0.0
                    for row in 1...Int(h) {
                        let o = Self.opacity(stops, at: Double(row) / h)
                        worst = max(worst, abs(o - last) * 255)
                        last = o
                    }
                    #expect(worst <= 4, "step \(worst)/255 at page \(h), plate \(top), ax \(ax)")
                }
            }
        }
        // Without the line, the standard shade is unchanged.
        #expect(FrontCoverPage.fadeStops(accessibility: false, plateTop: 0.7, followPlate: false).map(\.location) == [0, 0.18, 0.45, 0.82, 0.9, 1])
    }

    /// The shade's opacity at a location, interpolated linearly between stops as a LinearGradient draws it.
    static func opacity(_ stops: [(opacity: Double, location: Double)], at x: Double) -> Double {
        guard let first = stops.first else { return 0 }
        if x <= first.location { return first.opacity }
        for (a, b) in zip(stops, stops.dropFirst()) where x <= b.location {
            return b.location - a.location < 1e-9 ? b.opacity : a.opacity + (b.opacity - a.opacity) * (x - a.location) / (b.location - a.location)
        }
        return stops.last!.opacity
    }

    /// Iris (#467): the cover is Closed-only. Any other pose closes it at once, the route's Settings with it, and the deck
    /// position stays.
    @Test func coverIsClosedOnly() {
        #expect(FrontCoverPreview.shows(pose: .closed))
        for pose in [Pose.flat, .book, .tabletop] { #expect(!FrontCoverPreview.shows(pose: pose)) }
        let m = AppModel(storeURL: URL.temporaryDirectory.appending(path: "cover-\(UUID().uuidString).json"))
        m.handle(url: URL(string: "playscribe://cover")!)
        #expect(FrontCoverPreview.shared.open && m.settingsOpen)
        m.deckSelection = m.latestDeck.dropFirst().first?.id
        let kept = m.deckSelection
        FrontCoverPreview.shared.closeForPose(m)
        #expect(!FrontCoverPreview.shared.open)
        #expect(!m.settingsOpen)
        #expect(m.deckSelection == kept)
    }

    /// Iris (#467): Wukong's cover keeps the figure, not the left of the mural, in view.
    @Test func wukongCarriesItsFocalPoint() {
        let g = Fixtures.shared.games.first { $0.id == "wukong" }
        #expect(g?.coverFocus?.x ?? 0.5 > 0.6)
    }

    /// The chips: the PS5 version and "On PS5" first, then the day, then the change count; never a PC version.
    @Test func chipsLeadWithThePS5Version() {
        let deck = demoModel().latestDeck
        for card in deck {
            let chips = FrontCoverPlate.chips(card)
            guard let r = card.release else { continue }
            #expect(chips.first?.live == true)
            #expect(chips.first?.text == "Out on PS5")
            if let v = r.ps5Version { #expect(chips.contains { $0.text == v }) }
            #expect(chips.allSatisfy { !$0.text.contains("·") }) // dot-ok: asserts the dot is absent
            #expect(chips.filter { $0.live }.count == 1)
            if r.noteCount > 1 { #expect(chips.contains { $0.text == "\(r.noteCount) changes" }) }
        }
    }

    /// Iris (19 Nov): the patch name is the largest line; the game and the day sit above it in one comma-separated eyebrow,
    /// and the day is no longer a chip.
    @Test func patchNameLeadsWithGameAndDayAbove() {
        for card in demoModel().latestDeck {
            guard let r = card.release else { continue }
            #expect(FrontCoverPlate.headline(card) == r.displayName)
            let eyebrow = FrontCoverPlate.eyebrow(card) ?? ""
            #expect(eyebrow.hasPrefix(card.game.name.gluingTrailingNumeral))
            if let d = card.date {
                #expect(eyebrow.hasSuffix(", \(AppModel.tileDay(d))"))
                #expect(!FrontCoverPlate.chips(card).contains { $0.text == AppModel.tileDay(d) })
            }
            #expect(!eyebrow.contains("·")) // dot-ok: asserts the dot is absent
        }
    }

    /// cover/<game> (Mac at cf4a8c0 and 09eeddb): the feed's sweep leaves the lead unread; opening it reads it, so the cover's unread dot and the deck's unread
    /// state clear, as in the real app. The QA route only picks the starting state.
    @Test func coverRouteHonoursAReadUpdate() throws {
        let m = demoModel()
        m.handle(url: URL(string: "playscribe://cover/kcd2")!)
        let lead = try #require(m.latestDeck.first)
        let r = try #require(lead.release)
        #expect(lead.game.id == "kcd2")
        // The first feed refresh after a reset marks every update older than 72 hours read in the store (FeedClient). The route's
        // fresh update must survive that (Mac at 09eeddb: KCD lost its lead and its dot).
        for id in m.latestDeck.compactMap(\.release?.id) { m.data.read[id] = .now }
        #expect(m.isUnread(r))
        #expect(m.latestDeck.first?.release?.id == r.id && m.latestDeck.first?.unread == true)
        m.openGame("kcd2", chapter: .updates, releaseID: r.id)
        m.markRead(r.id)
        #expect(!m.isUnread(r))
        // Read, it leaves the unread state (and leaves the deck when it is older than 90 days).
        #expect(m.latestDeck.first { $0.release?.id == r.id }?.unread != true)
    }
}
