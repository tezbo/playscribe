import BackgroundTasks
import Foundation

/// Reads the static JSON feed (docs/api.md): latest.json on launch and in background refresh.
/// Releases are cached on the device so everything works offline (E-1). When a followed game's
/// release newly becomes On PS5, a local notification is posted (N-3), at most once per release.
enum FeedClient {
    static let refreshTaskID = "co.codeconnectors.playscribe.refresh"

    struct Latest: Decodable {
        var updatedAt: Date
        var releases: [Release]
    }

    static var baseURL: URL? { PushRegistrar.baseURL }

    static var cacheURL: URL { URL.applicationSupportDirectory.appending(path: "feed-latest.json") }

    static func loadCache() -> Latest? {
        guard let raw = try? Data(contentsOf: cacheURL) else { return nil }
        return try? JSONCoding.decoder.decode(Latest.self, from: raw)
    }

    static func fetchLatest() async throws -> (Latest, Data) {
        guard let url = baseURL?.appending(path: "latest.json") else { throw URLError(.badURL) }
        var request = URLRequest(url: url)
        request.cachePolicy = .reloadRevalidatingCacheData
        let (data, response) = try await URLSession.shared.data(for: request)
        guard (response as? HTTPURLResponse)?.statusCode == 200 else { throw URLError(.badServerResponse) }
        return (try JSONCoding.decoder.decode(Latest.self, from: data), data)
    }

    /// Schedules the next background refresh. iOS decides when it actually runs.
    static func scheduleRefresh() {
        let request = BGAppRefreshTaskRequest(identifier: refreshTaskID)
        request.earliestBeginDate = .now.addingTimeInterval(60 * 60)
        Task { try? await BGTaskScheduler.shared.submitTaskRequest(request) }
    }
}

enum FeedStatus: Equatable {
    case idle
    case refreshing
    case updated(Date)
    case offline(Date?)
    case failed(Date?)
}

extension AppModel {
    /// Loads the cached feed at launch without notifying.
    func loadCachedFeed() {
        if let cached = FeedClient.loadCache() {
            feedReleases = cached.releases
            feedStatus = .updated(cached.updatedAt)
        }
        if data.knownOnPS5 == nil {
            // First run: what is already On PS5 is not news.
            data.knownOnPS5 = Set((data.simulated + allReleasesMerged).filter { $0.ps5State == .onPS5 }.map(\.id))
        }
    }

    func refreshFeed() async {
        guard FeedClient.baseURL != nil else { return }
        let previous = lastFeedDate
        feedStatus = .refreshing
        do {
            let (latest, raw) = try await FeedClient.fetchLatest()
            try? raw.write(to: FeedClient.cacheURL, options: .atomic)
            feedReleases = latest.releases
            feedStatus = .updated(latest.updatedAt)
            notifyNewlyOnPS5()
        } catch let error as URLError where [.notConnectedToInternet, .networkConnectionLost, .timedOut].contains(error.code) {
            feedStatus = .offline(previous)
        } catch {
            feedStatus = .failed(previous)
        }
    }

    private var lastFeedDate: Date? {
        if case .updated(let d) = feedStatus { return d }
        return FeedClient.loadCache()?.updatedAt
    }

    /// V-1 and N-3: a release that is newly On PS5 for a followed game notifies once.
    func notifyNewlyOnPS5() {
        guard var known = data.knownOnPS5 else {
            // After a reset nothing has been seen yet: what is already On PS5 is not news.
            data.knownOnPS5 = Set(allReleasesMerged.filter { $0.ps5State == .onPS5 }.map(\.id))
            return
        }
        var reported = data.knownReported ?? Set(allReleasesMerged.filter { $0.ps5State == .reported }.map(\.id))
        for c in data.collection {
            for r in releases(c.gameID) where r.ps5State == .reported && !reported.contains(r.id) && !known.contains(r.id) {
                reported.insert(r.id)
                NotificationService.shared.scheduleReported(release: r, game: game(c.gameID), level: notifyLevel(c.gameID),
                                                            pauseAll: data.pauseAll, model: self)
            }
            for r in releases(c.gameID) where r.ps5State == .onPS5 && !known.contains(r.id) {
                known.insert(r.id)
                NotificationService.shared.schedule(release: r, game: game(c.gameID), level: notifyLevel(c.gameID),
                                                    pauseAll: data.pauseAll, delay: 1, model: self)
            }
        }
        data.knownOnPS5 = known
        data.knownReported = reported
        NotificationService.shared.updateBadge(badgeCount)
    }

    /// When the feed was last checked (GR-1), else the bundled data's check time.
    var lastChecked: Date {
        if case .updated(let d) = feedStatus { return d }
        return FeedClient.loadCache()?.updatedAt ?? "2026-10-23".isoDay ?? .now
    }

    /// The Library's quiet status line (E-1, E-2).
    var feedStatusLine: String? {
        switch feedStatus {
        case .offline(let d): "Offline" + (d.map { " · updated \($0.formatted(.relative(presentation: .named)))" } ?? "")
        case .failed: "Couldn't refresh"
        default: nil
        }
    }
}
