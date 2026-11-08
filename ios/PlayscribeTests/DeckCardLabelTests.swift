import Foundation
import SwiftUI
import Testing
@testable import Playscribe

/// r054: the deck card's VoiceOver label carries the release summary at every Dynamic Type size. At AX3 and above the visible
/// summary line is dropped (hero caption cap, Iris), so the spoken label is the only place a VoiceOver user gets it.
@MainActor
struct DeckCardLabelTests {
    @Test func labelCarriesTheSummary() throws {
        let model = FoldHost.demoModel()
        let withSummary = model.latestDeck.filter { $0.release?.summary?.isEmpty == false }
        let card = try #require(withSummary.first, "the demo deck has a card with a summary")
        let summary = try #require(card.release?.summary)
        let label = DeckCardView.accessibilityText(for: card)
        #expect(label.contains(summary), "the label holds the summary: \(label)")
        #expect(label.contains(card.game.name))
    }
}
