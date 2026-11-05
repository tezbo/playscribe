import Foundation
import Testing
@testable import Playscribe

/// 0.5.0 test debt (r050-test-debt): the Latest updates deck, Also new and the widget snapshot, checked
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

    /// Iris, 3548a21: Also new has one row per game, never the front card's game, and every row is an update.
    @Test func alsoNewIsOnePerGameWithoutTheFrontGame() {
        let m = demoModel()
        guard let front = m.latestDeck.first?.release else { return }
        let rows = m.alsoNewReleases(excludingRelease: front.id)
        let games = rows.map(\.gameID)
        #expect(Set(games).count == games.count)
        #expect(!games.contains(front.gameID))
        #expect(rows.allSatisfy { $0.versionChip != nil })
        #expect(rows.count <= 6)
    }

    /// The widget file round trips, and its rows deep link to the release (no source names or URLs shown).
    @Test func widgetSnapshotRoundTrips() throws {
        let data = try JSONEncoder().encode(WidgetSnapshot.sample)
        let back = try JSONDecoder().decode(WidgetSnapshot.self, from: data)
        #expect(back == WidgetSnapshot.sample)
        #expect(back.rows.first?.url.absoluteString == "playscribe://release/the-blood-of-dawnwalker/update-1-1")
        #expect(WidgetSnapshot.empty.rows.isEmpty && !WidgetSnapshot.empty.hasGames)
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
