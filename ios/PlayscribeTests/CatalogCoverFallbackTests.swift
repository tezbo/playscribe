import Foundation
import Testing
@testable import Playscribe

/// Terry on his Duo (beta 3, build 18): Astro Bot, added by Say it, kept the plate's "A" on its Library tile while its page showed
/// the key art. The bundled catalogue record has no cover (no asset, no IGDB image id) and the tile reads only that record, while
/// the page's art comes from the PS5 index by igdbID, which has the cover too. Every catalogue game with an index cover shows it.
@MainActor
struct CatalogCoverFallbackTests {
    private func model() -> AppModel {
        AppModel(storeURL: URL.temporaryDirectory.appending(path: "cover-\(UUID().uuidString).json"))
    }

    @Test func everyCatalogGameWithAnIndexCoverHasACover() {
        let bare = model().fixtures.games.filter { g in
            guard g.coverAsset == nil, g.coverURL == nil, let id = g.igdbID else { return false }
            return PS5Index.shared.entry(igdb: id)?.c != nil
        }.map(\.id)
        #expect(bare.isEmpty, "catalogue games showing the plate though the PS5 index has their cover: \(bare)")
    }

    @Test func astroBotTileHasItsIndexCover() throws {
        let g = try #require(model().game("astro-bot"))
        #expect(g.coverURL?.absoluteString.contains("coba3k") == true, "Astro Bot's cover comes from the PS5 index, got \(String(describing: g.coverURL))")
    }
}
