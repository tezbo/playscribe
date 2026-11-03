import Foundation
import Observation

/// Unreleased PS5 games from the feed (docs/api.md `v1/upcoming/<igdbId % 10>.json`). Dates keep
/// their precision: a month, quarter or year is never turned into a day.
@MainActor @Observable
final class UpcomingStore {
    static let shared = UpcomingStore()
    private(set) var games: [CatalogGame] = []
    private(set) var failed = false
    private(set) var loading = false

    struct Entry: Codable {
        var igdbId: Int
        var name: String
        var date: String?
        var datePrecision: String?
        var status: String?
        var coverId: String?
    }
    struct Shard: Codable { var games: [String: Entry] }

    private static func cacheURL(_ n: Int) -> URL { URL.cachesDirectory.appending(path: "upcoming-\(n).json") }

    func load() async {
        guard !loading else { return }
        loading = true; defer { loading = false }
        var all: [Entry] = []
        var anyFresh = false
        for n in 0..<10 {
            if let base = FeedClient.baseURL,
               let (data, response) = try? await URLSession.shared.data(from: base.appending(path: "upcoming/\(n).json")),
               (response as? HTTPURLResponse)?.statusCode == 200, let shard = try? JSONDecoder().decode(Shard.self, from: data) {
                try? data.write(to: Self.cacheURL(n), options: .atomic)
                all += shard.games.values; anyFresh = true
            } else if let raw = try? Data(contentsOf: Self.cacheURL(n)), let shard = try? JSONDecoder().decode(Shard.self, from: raw) {
                all += shard.games.values
            }
        }
        failed = !anyFresh && all.isEmpty
        let mapped = all.filter { $0.status != "released" }.map { e -> CatalogGame in
            let precision = e.datePrecision.flatMap(DatePrecision.init(rawValue:)) ?? (e.date == nil ? .tbd : .day)
            var g = PS5Index.shared.entry(igdb: e.igdbId).map { PS5Index.shared.game($0) }
                ?? CatalogGame(id: "igdb-\(e.igdbId)", name: e.name, platforms: [.ps5], igdbID: e.igdbId, coverImageID: e.coverId, coverage: .none)
            g.releaseDate = e.date
            g.releasePrecision = precision
            return g
        }
        games = mapped.sorted {
            ($0.releaseDate?.isoDay ?? .distantFuture, $0.name) < ($1.releaseDate?.isoDay ?? .distantFuture, $1.name)
        }
        .prefix(120).map { $0 }
    }
}
