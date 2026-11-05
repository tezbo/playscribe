import Foundation

/// News, as opposed to patch notes (docs/api.md `news.json`, `news/<id>.json`): what a studio or the
/// press says about a game that is not an update. Cached on the device so it reads offline (E-1).
/// A studio post is tagged Official and carries an excerpt; a press item is Reported, headline only.
struct NewsItem: Codable, Hashable, Identifiable {
    var id: String
    /// The feed's game id; nil for wider PS5 news that names none of the tracked games.
    var gameId: String?
    var title: String
    var publishedAt: Date
    var excerpt: String?
    /// A string, not a URL, so one malformed link cannot fail the whole file.
    var url: String
    var kind: String

    var link: URL? { URL(string: url).flatMap { $0.scheme == "https" ? $0 : nil } }
    var isOfficial: Bool { kind == "official" }
}

extension FeedClient {
    struct News: Codable { var updatedAt: Date?; var items: [NewsItem] }

    static var newsCacheURL: URL { URL.applicationSupportDirectory.appending(path: "feed-news.json") }
    static func gameNewsCacheURL(_ feedID: String) -> URL { URL.applicationSupportDirectory.appending(path: "feed-news-\(feedID).json") }

    static func decodeNews(_ raw: Data) -> News? { try? JSONCoding.decoder.decode(News.self, from: raw) }
}

extension AppModel {
    func loadCachedNews() {
        #if INTERNAL
        // QA: `-qaNews` seeds sample items so layouts can be checked in every pose without a feed.
        if ProcessInfo.processInfo.arguments.contains("-qaNews") {
            let day: TimeInterval = 86_400
            let long = "A longer excerpt from the studio post that runs over three lines so the row shows how it wraps next to a cover in every pose, including the narrow closed layout."
            let ids = data.collection.map { newsFeedID($0.gameID) }
            news = (0..<12).map { i in
                NewsItem(id: "qa-\(i)", gameId: i % 4 == 3 ? nil : ids[i % max(ids.count, 1)], title: i.isMultiple(of: 2) ? "Sample studio post number \(i) with a fairly long headline" : "Sample headline \(i)",
                         publishedAt: .now.addingTimeInterval(-Double(i) * day), excerpt: i.isMultiple(of: 2) ? long : nil,
                         url: "https://example.com/\(i)", kind: i.isMultiple(of: 2) ? "official" : "reported")
            }
            return
        }
        #endif
        if let raw = try? Data(contentsOf: FeedClient.newsCacheURL), let n = FeedClient.decodeNews(raw) { news = n.items }
        for c in data.collection {
            if let raw = try? Data(contentsOf: FeedClient.gameNewsCacheURL(newsFeedID(c.gameID))), let n = FeedClient.decodeNews(raw) {
                gameNews[c.gameID] = n.items
            }
        }
    }

    /// The feed's id for one of the app's games: the same id, else the one with the same IGDB id.
    func newsFeedID(_ gameID: String) -> String { feedIDs[gameID] ?? gameID }

    /// The global news file, and the news of each library game. Failures keep what is cached.
    func refreshNews() async {
        if let (index, _) = try? await FeedClient.fetch("index.json", as: FeedClient.Index.self) {
            for c in data.collection {
                let igdb = game(c.gameID)?.igdbID
                if let e = index.games.first(where: { $0.id == c.gameID }) ?? index.games.first(where: { igdb != nil && $0.igdbId == igdb }) {
                    feedIDs[c.gameID] = e.id
                }
            }
        }
        if let (all, raw) = try? await FeedClient.fetch("news.json", as: FeedClient.News.self) {
            try? raw.write(to: FeedClient.newsCacheURL, options: .atomic)
            news = all.items
        }
        for c in data.collection { await refreshGameNews(c.gameID) }
    }

    /// One game's news (the game page's News chapter). Games the feed does not track keep an empty list.
    func refreshGameNews(_ gameID: String) async {
        let feedID = newsFeedID(gameID)
        guard let (n, raw) = try? await FeedClient.fetch("news/\(feedID).json", as: FeedClient.News.self) else { return }
        try? raw.write(to: FeedClient.gameNewsCacheURL(feedID), options: .atomic)
        gameNews[gameID] = n.items
    }

    /// News for this game: its own file merged with the global file, newest first.
    func newsFor(_ gameID: String) -> [NewsItem] {
        let feedID = newsFeedID(gameID)
        var seen = Set<String>()
        return ((gameNews[gameID] ?? []) + news.filter { $0.gameId == feedID })
            .filter { seen.insert($0.id).inserted }
            .sorted { $0.publishedAt > $1.publishedAt }
    }

    /// The News tab: library games' news first, then the rest, each newest first. Spoiler-safe: news is never notes.
    var newsForLibrary: [NewsItem] {
        let mine = Set(data.collection.map { newsFeedID($0.gameID) })
        var seen = Set<String>()
        let merged = (gameNews.values.flatMap { $0 } + news).filter { seen.insert($0.id).inserted }
        return merged.filter { $0.gameId.map(mine.contains) ?? false }.sorted { $0.publishedAt > $1.publishedAt }
    }

    var newsAroundPS5: [NewsItem] {
        let mine = Set(data.collection.map { newsFeedID($0.gameID) })
        return news.filter { $0.gameId.map { !mine.contains($0) } ?? true }.sorted { $0.publishedAt > $1.publishedAt }
    }

    /// The app's game for a feed game id, if the app has it.
    func appGame(forFeedID feedID: String?) -> CatalogGame? {
        guard let feedID else { return nil }
        if let g = game(feedID) { return g }
        if let k = feedIDs.first(where: { $0.value == feedID })?.key { return game(k) }
        return nil
    }
}
