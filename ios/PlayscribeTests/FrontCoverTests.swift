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

    /// A mode that is not built yet falls back down the chain, ending at Still; the default is Key-art motion.
    @Test func unbuiltModesFallBack() {
        for mode in CoverMotion.allCases {
            #expect(mode.resolved(reduceMotion: false, autoplay: true).isBuilt)
        }
        #expect(CoverMotion.still.isBuilt)
        #expect(CoverMotion.defaultMode == .keyArt)
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
        // Standard sizes keep the signed shade.
        #expect(FrontCoverPage.fadeStops(accessibility: false, plateTop: 0.4).map(\.location) == [0, 0.18, 0.45, 0.85, 1])
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
            #expect(chips.first?.text.lowercased().hasSuffix("on ps5") == true)
            if let v = r.versionChip { #expect(chips.first?.text.hasPrefix(v) == true) }
            #expect(chips.filter { $0.live }.count == 1)
            if r.noteCount > 1 { #expect(chips.contains { $0.text == "\(r.noteCount) changes" }) }
        }
    }
}
