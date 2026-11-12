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

    /// The chips: the PS5 version and "On PS5" first, then the day, then the change count; never a PC version.
    @Test func chipsLeadWithThePS5Version() {
        let deck = demoModel().latestDeck
        for card in deck {
            let chips = FrontCoverPlate.chips(card)
            guard let r = card.release else { continue }
            #expect(chips.first?.live == true)
            #expect(chips.first?.text.hasSuffix("On PS5") == true)
            if let v = r.versionChip { #expect(chips.first?.text.hasPrefix(v) == true) }
            #expect(chips.filter { $0.live }.count == 1)
            if r.noteCount > 1 { #expect(chips.contains { $0.text == "\(r.noteCount) changes" }) }
        }
    }
}
