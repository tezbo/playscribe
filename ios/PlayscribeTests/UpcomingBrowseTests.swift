import Foundation
import Testing
@testable import Playscribe

/// Tapping a game in Library > Upcoming only opens it; it must not file it as Wishlist.
@MainActor
struct UpcomingBrowseTests {
    private func model() -> AppModel {
        AppModel(storeURL: URL.temporaryDirectory.appending(path: "browse-\(UUID().uuidString).json"))
    }

    @Test func openingAnUpcomingGameDoesNotAddItToTheLibrary() {
        let m = model()
        guard let g = m.upcomingMore.first ?? PS5Index.shared.entries.map({ PS5Index.shared.game($0) }).first(where: \.isUpcoming) else { return }
        let before = m.data.collection.count
        m.browseGame(g)
        #expect(m.data.collection.count == before)
        #expect(m.entry(g.id) == nil)
        #expect(m.nav.gameID == g.id)
        #expect(m.game(g.id) != nil)
        #expect(!m.data.customGames.contains { $0.id == g.id })
    }
}
