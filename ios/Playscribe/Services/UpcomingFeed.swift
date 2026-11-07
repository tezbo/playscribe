import Foundation
import Observation

/// Unreleased PS5 games from the feed (docs/api.md `v1/upcoming/<igdbId % 10>.json`). Dates keep
/// their precision: a month, quarter or year is never turned into a day.
@MainActor @Observable
final class UpcomingStore {
    static let shared = UpcomingStore()
    private(set) var games: [CatalogGame] = []
    private(set) var failed = false
    private(set) var extras: [Int: Extras] = [:]
    private(set) var loading = false

    struct Entry: Codable {
        var igdbId: Int
        var name: String
        var date: String?
        var datePrecision: String?
        var status: String?
        var coverId: String?
        var summary: String?
        var genres: [String]?
        var trailerId: String?
        var move: Move?
    }
    /// A real change in the date, kept by the feed for 14 days (docs/api.md).
    struct Move: Codable {
        var kind: String
        var previousDate: String?
        var previousPrecision: String?
        var movedAt: String?
    }
    /// What the feed knows about a game that is not in the bundled catalogue, by IGDB id.
    struct Extras {
        var summary: String?
        var genres: [String]
        var trailerId: String?
        var move: Move?
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
        extras = Dictionary(all.map { ($0.igdbId, Extras(summary: $0.summary, genres: $0.genres ?? [], trailerId: $0.trailerId, move: $0.move)) },
                            uniquingKeysWith: { a, _ in a })
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
        NotificationService.shared.notifyDateMoves()
    }
}

extension UpcomingStore.Move {
    /// "Delayed from March", "Moved earlier" or "Now dated"; nil when there is nothing plain to say.
    var line: String? {
        switch kind {
        case "dated": return "Now dated"
        case "earlier": return "Moved earlier"
        case "delayed":
            guard let was = previousLabel else { return "Delayed" }
            return "Delayed from \(was)"
        default: return nil
        }
    }

    private var previousLabel: String? {
        guard let previousDate, let d = previousDate.isoDay else { return nil }
        // A previous release date is a UTC day, printed as one (r060-utc-day-labels).
        let cal = Date.utcCalendar
        let year = cal.component(.year, from: d)
        switch previousPrecision {
        case "year": return String(year)
        case "quarter": return "Q\((cal.component(.month, from: d) - 1) / 3 + 1) \(year)"
        case "month": return d.formatted(Date.FormatStyle(timeZone: .gmt).month(.wide).year())
        case "day": return d.formatted(Date.FormatStyle(timeZone: .gmt).day().month(.wide))
        default: return nil
        }
    }
}

extension UpcomingStore.Move {
    var movedDate: Date? { movedAt.flatMap { try? Date($0, strategy: .iso8601) } }

    /// Whether this move may alert now: a real kind, and within 72 hours of the change like every
    /// other alert (the feed keeps a move for 14 days, so an older one is the past).
    func isFresh(now: Date = .now) -> Bool {
        guard line != nil, let d = movedDate else { return false }
        return d > now.addingTimeInterval(-72 * 3600)
    }
}
