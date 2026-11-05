import Foundation

/// What the Home Screen widget shows. The app writes it into the shared App Group container;
/// the widget only reads it. Official PS5 updates only, newest and unread first (same order as
/// the Library's Latest updates deck). No source names or URLs.
struct WidgetSnapshot: Codable, Equatable, Sendable {
    struct Row: Codable, Equatable, Sendable, Identifiable {
        var gameID: String
        var game: String
        var releaseID: String
        var update: String
        var date: Date
        var unread: Bool
        /// A cover thumbnail was written for this row (official art only; see `coverData(for:)`).
        var hasCover = false
        /// Version chip such as "v1.1", when the update name ends in a version.
        var chip: String?
        var id: String { releaseID }
        var url: URL { URL(string: "playscribe://release/\(gameID)/\(releaseID)")! }
    }

    /// The App Group derives from the bundle ID build setting (Info.plist key PlayscribeAppGroup).
    static var group: String {
        Bundle.main.object(forInfoDictionaryKey: "PlayscribeAppGroup") as? String ?? "group.co.codeconnectors.playscribe"
    }
    static let coverPrefix = "widget-cover-"
    static let fileName = "widget-snapshot.json"

    var rows: [Row]
    var unreadCount: Int
    var hasGames: Bool

    static let empty = WidgetSnapshot(rows: [], unreadCount: 0, hasGames: false)

    /// Gallery preview, same sample as the share card.
    static let sample = WidgetSnapshot(
        rows: [Row(gameID: "the-blood-of-dawnwalker", game: "The Blood of Dawnwalker", releaseID: "update-1-1",
                   update: "Update 1.1", date: Date(timeIntervalSince1970: 1_792_627_200), unread: true)],
        unreadCount: 1, hasGames: true)

    static var containerURL: URL? { FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: group) }

    static func coverFile(for releaseID: String) -> String { "\(coverPrefix)\(releaseID).jpg" }

    static func coverData(for row: Row) -> Data? {
        containerURL.flatMap { try? Data(contentsOf: $0.appendingPathComponent(coverFile(for: row.releaseID))) }
    }

    static func load() -> WidgetSnapshot {
        guard let url = containerURL?.appendingPathComponent(fileName),
              let data = try? Data(contentsOf: url),
              let snap = try? JSONDecoder().decode(WidgetSnapshot.self, from: data) else { return .empty }
        return snap
    }

    func save() {
        guard let url = Self.containerURL?.appendingPathComponent(Self.fileName),
              let data = try? JSONEncoder().encode(self) else { return }
        try? data.write(to: url, options: .atomic)
    }
}
