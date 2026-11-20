import Foundation
import Testing
@testable import Playscribe

/// bug-catalog-missing-igdb-ids (0.5.5): a game without an igdbID opens with no genres, About, trailers, links or similar games in
/// every pose (Ghost of Yōtei and Astro Bot did, found on the Tabletop parity run). Every bundled catalog game carries one, and it
/// is the number the feed uses for the same game id (backend/src/sources/registry.json, `igdbId`).
@MainActor
struct CatalogIgdbIDTests {
    private func model() -> AppModel {
        AppModel(storeURL: URL.temporaryDirectory.appending(path: "igdb-\(UUID().uuidString).json"))
    }

    @Test func everyCatalogGameHasAnIgdbID() {
        let missing = model().fixtures.games.filter { $0.igdbID == nil }.map(\.id)
        #expect(missing.isEmpty, "catalog games without an igdbID: \(missing)")
    }

    /// The registry is repository data, not in the app bundle: read it from the source tree when the test runs from a checkout.
    @Test func catalogIgdbIDsMatchTheFeedRegistry() throws {
        let registry = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appending(path: "backend/src/sources/registry.json")
        guard let data = try? Data(contentsOf: registry),
              let root = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let games = root["games"] as? [String: [String: Any]] else { return }
        for g in model().fixtures.games {
            guard let id = g.igdbID, let feed = games[g.id]?["igdbId"] as? Int else { continue }
            #expect(id == feed, "\(g.id): catalog \(id), feed \(feed)")
        }
    }
}
