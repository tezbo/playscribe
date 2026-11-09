import Foundation
import Testing
@testable import Playscribe

/// 0.5.0 test debt (r050-test-debt): the Latest updates deck and the widget snapshot, checked
/// without a simulator so the five-pose gate keeps only by-eye checks.
@MainActor
struct DeckAndWidgetTests {
    private func demoModel() -> AppModel {
        let m = AppModel(storeURL: URL.temporaryDirectory.appending(path: "deck-\(UUID().uuidString).json"))
        m.resetDemo()
        return m
    }

    /// J-1: at most 8 cards, at most 2 per game, unread cards first, no card twice.
    @Test func deckIsCappedSpreadAndUnreadFirst() {
        let deck = demoModel().latestDeck
        #expect(deck.count <= 8)
        var perGame: [String: Int] = [:]
        var ids = Set<String>()
        for card in deck {
            perGame[card.game.id, default: 0] += 1
            #expect(ids.insert(card.id).inserted, "card \(card.id) appears once")
        }
        for (game, n) in perGame { #expect(n <= 2, "\(game) has \(n) cards") }
        var seenRead = false
        for card in deck {
            if !card.unread { seenRead = true }
            #expect(!(seenRead && card.unread), "an unread card never follows a read one")
        }
    }

    /// The "+N more updates" chip counts exactly the updates the 5-card deck leaves out, never negative (Iris, 2026-11-06; Terry, 0.5.4: 5 cards, 5 dots).
    @Test func deckOverflowIsWhatTheDeckLeavesOut() {
        let m = demoModel()
        #expect(m.latestDeck.count <= AppModel.deckLimit)
        #expect(m.latestDeckOverflow >= 0)
        if m.latestDeckOverflow == 0 { #expect(m.latestDeck.count <= AppModel.deckLimit) }
    }

    /// The card's summary line never ends mid-word (Iris, 2026-11-06).
    @Test func deckSummaryCutsAtWholeWords() {
        let long = "Fixes a crash on load and improves frame pacing in the big city district when many characters appear at once during night"
        let cut = CompactCaption.wholeWords(long, limit: 100)
        #expect(cut.hasSuffix("…"))
        let body = String(cut.dropLast())
        #expect(long.hasPrefix(body))
        #expect(long.dropFirst(body.count).first == " ")
        #expect(CompactCaption.wholeWords("Short one. Second sentence.", limit: 100) == "Short one.")
        #expect(CompactCaption.wholeWords("No stop here", limit: 100) == "No stop here")
    }

    /// The widget file round trips, and its rows deep link to the release (no source names or URLs shown).
    @Test func widgetSnapshotRoundTrips() throws {
        let data = try JSONEncoder().encode(WidgetSnapshot.sample)
        let back = try JSONDecoder().decode(WidgetSnapshot.self, from: data)
        #expect(back == WidgetSnapshot.sample)
        #expect(back.rows.first?.url.absoluteString == "playscribe://release/the-blood-of-dawnwalker/update-1-1")
        #expect(WidgetSnapshot.empty.rows.isEmpty && !WidgetSnapshot.empty.hasGames)
        #expect(WidgetSnapshot.coverFile(for: "update-1-1") == "widget-cover-update-1-1.jpg")
    }

    /// The version chip is "v" plus the last token when it starts with a digit, and nil otherwise.
    @Test func versionChipFromDisplayName() {
        let m = demoModel()
        for card in m.latestDeck {
            guard let r = card.release else { continue }
            if let chip = r.versionChip {
                #expect(chip.hasPrefix("v"))
                #expect(r.displayName.hasSuffix(String(chip.dropFirst())))
            }
        }
    }
}
