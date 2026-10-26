import Foundation
import Observation

/// Every game's basics (docs/api.md `info/<n>.json`): description, storyline, genres, first
/// release and YouTube videos with the launch trailer first, so no game page is ever blank.
struct GameBasics: Codable, Hashable {
    struct Video: Codable, Hashable { var youtubeId: String; var name: String }
    var summary: String?
    var storyline: String?
    var genres: [String]?
    var firstRelease: String?
    var videos: [Video]?
}

@MainActor @Observable
final class GameInfoStore {
    static let shared = GameInfoStore()
    private(set) var basics: [Int: GameBasics] = [:]
    @ObservationIgnored private var loaded: Set<Int> = []

    private struct Shard: Codable { var games: [String: GameBasics] }

    private static func cacheURL(_ shard: Int) -> URL { URL.cachesDirectory.appending(path: "info-\(shard).json") }

    /// Loads the shard for this game: the cached copy first, then a refresh from the feed.
    func load(igdbID: Int) async {
        let shard = igdbID % 100
        if let raw = try? Data(contentsOf: Self.cacheURL(shard)) { merge(raw) }
        guard !loaded.contains(shard), let base = FeedClient.baseURL else { return }
        loaded.insert(shard)
        guard let (data, response) = try? await URLSession.shared.data(from: base.appending(path: "info/\(shard).json")),
              (response as? HTTPURLResponse)?.statusCode == 200 else { return }
        try? data.write(to: Self.cacheURL(shard), options: .atomic)
        merge(data)
    }

    private func merge(_ raw: Data) {
        guard let shard = try? JSONDecoder().decode(Shard.self, from: raw) else { return }
        for (key, value) in shard.games { if let id = Int(key) { basics[id] = value } }
    }
}
