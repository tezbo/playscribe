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
        loadCachedHistories()
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
            applyLatest(releases: latest.releases, updatedAt: latest.updatedAt)
            await refreshHistories()
            await PlusStore.shared.load()
        } catch let error as URLError where [.notConnectedToInternet, .networkConnectionLost, .timedOut].contains(error.code) {
            feedStatus = .offline(previous)
        } catch {
            feedStatus = .failed(previous)
        }
    }

    /// A fetched latest.json, applied: its releases, the Checked time, and any newly On PS5 alert.
    func applyLatest(releases: [Release], updatedAt: Date) {
        // Unchanged releases are not written: the write alone re-runs every view that reads the merged list.
        if releases != feedReleases { feedReleases = releases }
        feedStatus = .updated(updatedAt)
        notifyNewlyOnPS5()
    }

    #if INTERNAL
    /// QA (bug-library-redraw-on-feed-refresh): `-qaFeedPulse <seconds>` runs a feed refresh every so many seconds with the
    /// feed the app already has, through the same apply path as a real one and with no network: Refreshing, then latest.json
    /// applied, then the histories' alert pass. A UI test scrolls the Library through these and counts its body runs.
    func runQAFeedPulse(every seconds: Double) async {
        // A/B for the redraw count (Mac at ffb216b1: feedStatus changed between nearly every pair of runs, but it changes twice a
        // second under the pulse, so that tally cannot say whether it is the cause). `-qaPulseOnly status` writes only the
        // status; `-qaPulseOnly apply` runs only the apply path and leaves the status alone.
        let args = ProcessInfo.processInfo.arguments
        let only = args.firstIndex(of: "-qaPulseOnly").flatMap { args.indices.contains($0 + 1) ? args[$0 + 1] : nil }
        // `-qaPulseNew <gameID>`: the third full pulse brings a new PS5 release for that game, live now, so a clip can show new
        // feed data reaching the Library once scrolling stops (Quinn, #585). Falls back to the first game in the collection.
        let newFor = args.firstIndex(of: "-qaPulseNew").flatMap { args.indices.contains($0 + 1) ? args[$0 + 1] : nil }
        var pulses = 0
        while !Task.isCancelled {
            pulses += 1
            try? await Task.sleep(for: .seconds(seconds))
            if only != "apply" { feedStatus = .refreshing }
            try? await Task.sleep(for: .milliseconds(200))
            if only == "status" { feedStatus = .updated(.now); continue }
            if only == "apply" {   // applyLatest without its status write
                notifyNewlyOnPS5()
                alertAddressedIssues()
                notifyNewlyOnPS5()
                continue
            }
            var releases = feedReleases
            if pulses == 3, let wanted = newFor,
               let id = data.collection.first(where: { $0.gameID == wanted })?.gameID ?? data.collection.first?.gameID {
                releases.insert(simulatedRelease(gameID: id, kind: .hotfix, arrives: self.clock), at: 0)   // visible at the model clock (releases(_:) hides later ones)
            }
            applyLatest(releases: releases, updatedAt: .now)
            alertAddressedIssues()
            notifyNewlyOnPS5()
        }
    }
    #endif

    private var lastFeedDate: Date? {
        if case .updated(let d) = feedStatus { return d }
        return FeedClient.loadCache()?.updatedAt
    }

    /// V-1 and N-3: a release that is newly On PS5 for a followed game notifies once.
    func notifyNewlyOnPS5() {
        guard var known = data.knownOnPS5 else {
            // After a reset nothing has been seen yet: what is already On PS5 is not news.
            data.knownOnPS5 = Set(allReleasesMerged.filter { $0.ps5State == .onPS5 }.map(\.id))
            markPastAsRead(allReleasesMerged.filter { $0.ps5State == .onPS5 }, force: true)
            return
        }
        var reported = data.knownReported ?? Set(allReleasesMerged.filter { $0.ps5State == .reported }.map(\.id))
        for c in data.collection {
            for r in releases(c.gameID) where r.ps5State == .onPS5 && !known.contains(r.id) {
                known.insert(r.id)
                // Like the server: nothing that went live more than 72 hours ago alerts.
                // It's the past, so it's read too: adding a game doesn't flood it with unread updates.
                guard r.isAlertWorthy() else {
                    if data.read[r.id] == nil { data.read[r.id] = .now }
                    continue
                }
                NotificationService.shared.schedule(release: r, game: game(c.gameID), level: notifyLevel(c.gameID),
                                                    pauseAll: data.pauseAll, delay: 1, model: self)
            }
        }
        // Written only when they change: any write to `data` re-runs every view that reads it, the Library shelf among them,
        // and a refresh runs this twice (bug-library-redraw-on-feed-refresh: about 16 shelf runs in 20 swipes).
        if data.knownOnPS5 != known { data.knownOnPS5 = known }
        if data.knownReported != reported { data.knownReported = reported }
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
        case .offline(let d): "Offline" + (d.map { ". Updated \($0.formatted(.relative(presentation: .named)))." } ?? "")
        case .failed: "Couldn’t refresh"
        default: nil
        }
    }
}
