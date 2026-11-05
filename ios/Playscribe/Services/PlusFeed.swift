import Foundation
import Observation

/// The PS Plus monthly games (docs/api.md `v1/plus.json`, r050-plus-card): hand-curated, newest month first.
/// Names and dates only. The card shows the month whose window holds today, and "Last chance" in its last three days.
struct PlusMonth: Codable, Equatable {
    struct Game: Codable, Equatable { var name: String; var gameId: String? }
    var month: String
    /// First and last day the lineup can be claimed ("YYYY-MM-DD", inclusive).
    var from: String
    var until: String
    var games: [Game]
}

struct PlusFile: Codable, Equatable {
    var version: Int?
    var months: [PlusMonth]
}

enum PlusLogic {
    /// Today as "YYYY-MM-DD" in the device's calendar; day strings compare in order.
    static func dayKey(_ date: Date, calendar: Calendar = .current) -> String {
        let c = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", c.year ?? 0, c.month ?? 0, c.day ?? 0)
    }

    /// The month to show today, and whether it is in its last three days. nil hides the card.
    static func current(_ months: [PlusMonth], now: Date = .now, calendar: Calendar = .current) -> (month: PlusMonth, lastChance: Bool)? {
        let today = dayKey(now, calendar: calendar)
        guard let m = months.first(where: { $0.from <= today && today <= $0.until && !$0.games.isEmpty }) else { return nil }
        let lastChanceFrom = dayKey(leavingSoonStart(m, calendar: calendar) ?? now, calendar: calendar)
        return (m, today >= lastChanceFrom)
    }

    /// The first of the last three claim days, at the start of that day.
    static func leavingSoonStart(_ m: PlusMonth, calendar: Calendar = .current) -> Date? {
        let p = m.until.split(separator: "-").compactMap { Int($0) }
        guard p.count == 3,
              let last = calendar.date(from: DateComponents(year: p[0], month: p[1], day: p[2])) else { return nil }
        return calendar.date(byAdding: .day, value: -2, to: last)
    }

    /// When the "Leaving soon" reminder fires: 10:00 on the first of the last three days. nil once that time has passed.
    static func leavingSoonFire(_ m: PlusMonth, now: Date = .now, calendar: Calendar = .current) -> Date? {
        guard let start = leavingSoonStart(m, calendar: calendar),
              let fire = calendar.date(bySettingHour: 10, minute: 0, second: 0, of: start), fire > now else { return nil }
        return fire
    }

    /// "1 December" for "2026-12-01".
    static func claimByText(_ m: PlusMonth, calendar: Calendar = .current) -> String {
        let p = m.until.split(separator: "-").compactMap { Int($0) }
        guard p.count == 3, let d = calendar.date(from: DateComponents(year: p[0], month: p[1], day: p[2])) else { return m.until }
        return d.formatted(.dateTime.day().month(.wide))
    }
}

@MainActor @Observable
final class PlusStore {
    static let shared = PlusStore()
    private(set) var months: [PlusMonth] = []

    private static var cacheURL: URL { URL.cachesDirectory.appending(path: "plus.json") }

    init() {
        if let raw = try? Data(contentsOf: Self.cacheURL), let f = try? JSONDecoder().decode(PlusFile.self, from: raw) { months = f.months }
    }

    func load() async {
        guard let base = FeedClient.baseURL else { return }
        if let (data, response) = try? await URLSession.shared.data(from: base.appending(path: "plus.json")),
           (response as? HTTPURLResponse)?.statusCode == 200, let f = try? JSONDecoder().decode(PlusFile.self, from: data) {
            try? data.write(to: Self.cacheURL, options: .atomic)
            months = f.months
        }
        NotificationService.shared.syncPlusLeavingSoon()
    }
}
