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
        #if INTERNAL
        if Self.qaLogStart != nil { Self.qaLog("applyLatest: \(releases.count) releases, \(releases == feedReleases ? "unchanged" : "changed")") }
        #endif
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
        Self.qaLog("pulse armed: every \(seconds) s")
        var pulses = 0
        while !Task.isCancelled {
            pulses += 1
            try? await Task.sleep(for: .seconds(seconds))
            Self.qaLog("pulse \(pulses) fire (every \(seconds) s, only \(only ?? "all"))")
            if only != "apply" { feedStatus = .refreshing }
            try? await Task.sleep(for: .milliseconds(200))
            if only == "status" { feedStatus = .updated(.now); continue }
            if only == "apply" {   // applyLatest without its status write
                notifyNewlyOnPS5()
                alertAddressedIssues()
                notifyNewlyOnPS5()
                Self.qaLog("pulse \(pulses) apply done (apply only)")
                continue
            }
            applyLatest(releases: feedReleases, updatedAt: .now)
            alertAddressedIssues()
            notifyNewlyOnPS5()
            Self.qaLog("pulse \(pulses) apply done")
        }
    }

    /// QA (Quinn, #585): `-qaPulseNewAt <seconds> [-qaPulseNew <gameID>]` applies, once and that many seconds after launch, the
    /// feed the app has plus one new PS5 hotfix for that game (default: the first game in the collection), live now, through the
    /// same apply path as a real refresh. Independent of `-qaFeedPulse`, so a clip knows exactly when new data lands. There is
    /// no deferral anywhere on this path: applyLatest writes feedReleases at once, so a tile that stays stale after this log
    /// line is a bug, not timing.
    func runQANewRelease(after seconds: Double) async {
        let args = ProcessInfo.processInfo.arguments
        let wanted = args.firstIndex(of: "-qaPulseNew").flatMap { args.indices.contains($0 + 1) ? args[$0 + 1] : nil }
        Self.qaLog("new release armed: fires at t+\(seconds) s for \(wanted ?? "the first game")")
        try? await Task.sleep(for: .seconds(seconds))
        guard let id = data.collection.first(where: { $0.gameID == wanted })?.gameID ?? data.collection.first?.gameID else {
            Self.qaLog("new release: no game in the collection"); return
        }
        Self.qaLog("new release fire for \(id) at \(seconds) s; newest before: \(releases(id).first?.displayName ?? "none")")
        let release = simulatedRelease(gameID: id, kind: .hotfix, arrives: .now)
        tick()   // releases(_:) hides anything later than the model clock
        applyLatest(releases: [release] + feedReleases, updatedAt: .now)
        alertAddressedIssues()
        Self.qaLog("new release apply done for \(id); newest now: \(releases(id).first?.displayName ?? "none")")
    }

    /// One line per QA pulse event, with the wall clock and seconds since the first line, in the device log and the console.
    static func qaLog(_ text: String) {
        let t = Date.now
        if qaLogStart == nil { qaLogStart = t }
        NSLog("qa-pulse: %@ t+%.2f %@", t.formatted(.iso8601.time(includingFractionalSeconds: true)),
              t.timeIntervalSince(qaLogStart ?? t), text)
    }
    nonisolated(unsafe) static var qaLogStart: Date?
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
