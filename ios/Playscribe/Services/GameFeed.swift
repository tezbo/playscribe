import Foundation

/// Each library game's full history (docs/api.md `games/<id>.json`). `latest.json` only holds the
/// newest 100 releases across every game, so a quieter game's updates (Blue Prince, 17 of them)
/// never appeared. `index.json` maps catalogue ids to feed ids and says when a game last changed.
extension FeedClient {
    struct Index: Decodable {
        struct Game: Decodable { var id: String; var igdbId: Int?; var name: String?; var updatedAt: Date? }
        var updatedAt: Date
        var games: [Game]
    }
    struct GameHistory: Decodable {
        var releases: [Release]
        var issues: [KnownIssue]
        enum CodingKeys: String, CodingKey { case releases, issues }
        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            releases = try c.decode([Release].self, forKey: .releases)
            // Additive: a bad or missing issues list never costs the history.
            issues = (try? c.decodeIfPresent([KnownIssue].self, forKey: .issues)) ?? []
        }
    }

    static func fetch<T: Decodable>(_ path: String, as: T.Type) async throws -> (T, Data) {
        guard let url = baseURL?.appending(path: path) else { throw URLError(.badURL) }
        var request = URLRequest(url: url)
        request.cachePolicy = .reloadRevalidatingCacheData
        let (data, response) = try await URLSession.shared.data(for: request)
        guard (response as? HTTPURLResponse)?.statusCode == 200 else { throw URLError(.badServerResponse) }
        return (try JSONCoding.decoder.decode(T.self, from: data), data)
    }

    static func historyCacheURL(_ gameID: String) -> URL { URL.applicationSupportDirectory.appending(path: "feed-game-\(gameID).json") }
    static var indexCacheURL: URL { URL.applicationSupportDirectory.appending(path: "feed-index.json") }
}

extension AppModel {
    /// The cached histories, at launch.
    func loadCachedHistories() {
        if let raw = try? Data(contentsOf: FeedClient.indexCacheURL), let idx = try? JSONCoding.decoder.decode(FeedClient.Index.self, from: raw) {
            feedIndexGames = idx.games
        }
        var out: [String: [Release]] = [:]
        for c in data.collection {
            if let raw = try? Data(contentsOf: FeedClient.historyCacheURL(c.gameID)),
               let h = try? JSONCoding.decoder.decode(FeedClient.GameHistory.self, from: raw) {
                out[c.gameID] = h.releases.map { $0.reassigned(to: c.gameID) }
                gameIssues[c.gameID] = h.issues
                markPastAsRead(out[c.gameID] ?? [])
            }
        }
        gameReleases = out
    }

    /// Fetches the full history of these library games (all of them when nil), skipping any whose
    /// index entry hasn't changed since the last fetch.
    func refreshHistories(_ gameIDs: [String]? = nil) async {
        guard let (index, rawIndex) = try? await FeedClient.fetch("index.json", as: FeedClient.Index.self) else { return }
        try? rawIndex.write(to: FeedClient.indexCacheURL, options: .atomic)
        feedIndexGames = index.games
        let ids = gameIDs ?? data.collection.map(\.gameID)
        for gameID in ids {
            let igdb = game(gameID)?.igdbID
            guard let entry = index.games.first(where: { $0.id == gameID }) ?? index.games.first(where: { igdb != nil && $0.igdbId == igdb }) else { continue }
            let stamp = entry.updatedAt.map { String($0.timeIntervalSince1970) } ?? ""
            if gameReleases[gameID] != nil, historyStamps[gameID] == stamp { continue }
            guard let (history, raw) = try? await FeedClient.fetch("games/\(entry.id).json", as: FeedClient.GameHistory.self) else { continue }
            try? raw.write(to: FeedClient.historyCacheURL(gameID), options: .atomic)
            let fresh = history.releases.map { $0.reassigned(to: gameID) }
            // A history seen for the first time is the past, not news: anything that went live
            // more than 72 hours ago is read and never alerts (docs/api.md).
            markPastAsRead(fresh, backCatalogue: true)
            historyStamps[gameID] = stamp
            gameReleases[gameID] = fresh
            gameIssues[gameID] = history.issues
        }
        alertAddressedIssues()
        notifyNewlyOnPS5()
    }
}

extension AppModel {
    /// Whether the feed follows this game's patch notes at all (it is in index.json). A game outside the tracked set has no
    /// history to wait for, so its page must not say "No updates yet". Until an index has been seen the answer is yes, so the
    /// app never claims a game is untracked on a guess.
    func feedTracksGame(_ gameID: String) -> Bool {
        if qaUntracked { return false }
        // Any history the feed has served for this game settles it, whatever a cached index says: a game the feed added today
        // can be missing from an index cached yesterday.
        if gameReleases[gameID] != nil { return true }
        guard let games = feedIndexGames else { return true }
        let igdb = game(gameID)?.igdbID
        return games.contains { $0.id == gameID || (igdb != nil && $0.igdbId == igdb) }
    }

    /// The name to show for a game: the catalogue's, else the feed index's (a game the app does not know, such as one the
    /// feed onboarded, still has a name there), else empty. Never a blank title with only the update name ("Patch 5.01").
    func gameDisplayName(_ gameID: String) -> String {
        if let name = game(gameID)?.name, !name.isEmpty { return name }
        return feedIndexGames?.first { $0.id == gameID }?.name ?? ""
    }
}

extension AppModel {
    /// A release first seen more than 72 hours after it went live is the past: read, no alert.
    /// `force`: after a reset, everything is newly seen.
    /// `backCatalogue`: a game's history seen for the first time (just added, or a cold cache). A patch that is
    /// itself older than 72 hours is the past for this player even when the feed's alert date is recent (a
    /// consoles-later port folds years of patches under the console launch date), so it never counts as news.
    func markPastAsRead(_ releases: [Release], force: Bool = false, backCatalogue: Bool = false) {
        let cutoff = Date.now.addingTimeInterval(-72 * 3600)
        var known = data.knownOnPS5 ?? []
        // Recent ones stay unknown so notifyNewlyOnPS5 can alert for them.
        for r in releases where (force || !known.contains(r.id)) && (r.alertDate < cutoff || (backCatalogue && r.ps5Date < cutoff)) {
            known.insert(r.id)
            if data.read[r.id] == nil { data.read[r.id] = .now }
        }
        // A game seen for the first time shows at most its latest update as unread: a few patches inside the 72 hours are
        // still its back catalogue, not news (Terry, 12 Nov). The older ones are read and never alert.
        if backCatalogue {
            let recent = releases.filter { $0.ps5State == .onPS5 && data.read[$0.id] == nil && !known.contains($0.id) }
            for (_, group) in Dictionary(grouping: recent, by: \.gameID) {
                for r in group.sorted(by: { $0.ps5Date > $1.ps5Date }).dropFirst() {
                    known.insert(r.id)
                    data.read[r.id] = .now
                }
            }
        }
        data.knownOnPS5 = known
    }
}

extension Release {
    /// N-3: news only when both the alert date and the patch itself are inside the last 72 hours. A patch older than that is
    /// the past even under a recent alert date (a port's folded history).
    func isAlertWorthy(now: Date = .now) -> Bool {
        let cutoff = now.addingTimeInterval(-72 * 3600)
        return alertDate > cutoff && ps5Date > cutoff
    }

    /// Feed releases carry the feed's game id; a game added from the catalogue has its own.
    func reassigned(to gameID: String) -> Release { var r = self; r.gameID = gameID; return r }
}
