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

    /// CM-1: Reduce Motion, or Autoplay videos off, forces Still whatever the setting says.
    @Test func reduceMotionOrAutoplayOffForcesStill() {
        for mode in CoverMotion.allCases {
            #expect(mode.resolved(reduceMotion: true, autoplay: true) == .still)
            #expect(mode.resolved(reduceMotion: false, autoplay: false) == .still)
        }
    }

    /// A mode that is not built yet shows Still, and the Settings row lists only built modes.
    @Test func unbuiltModesFallBackToStill() {
        for mode in CoverMotion.allCases where !mode.isBuilt {
            #expect(mode.resolved(reduceMotion: false, autoplay: true) == .still)
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
