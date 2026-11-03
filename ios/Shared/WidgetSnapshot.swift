import Foundation

/// What the Home Screen widget shows. The app writes it into the shared App Group container;
/// the widget only reads it. Official PS5 updates only, newest and unread first (same order as
/// the Library's Latest updates deck). No source names or URLs.
nonisolated struct WidgetSnapshot: Codable, Equatable, Sendable {
    struct Row: Codable, Equatable, Sendable, Identifiable {
        var gameID: String
        var game: String
        var releaseID: String
        var update: String
        var date: Date
        var unread: Bool
        /// A cover thumbnail was written for this row (first row only, for the small widget).
        var hasCover = false
        var id: String { releaseID }
        var url: URL { URL(string: "playscribe://release/\(gameID)/\(releaseID)")! }
    }

    /// The App Group derives from the bundle ID build setting (Info.plist key PlayscribeAppGroup).
    static var group: String {
        Bundle.main.object(forInfoDictionaryKey: "PlayscribeAppGroup") as? String ?? "group.co.codeconnectors.playscribe"
    }
    static let coverFile = "widget-cover.jpg"
    static let fileName = "widget-snapshot.json"

    /// One library game with its newest PS5 update, for Siri, Shortcuts and Spotlight (spike).
    struct GameLine: Codable, Equatable, Sendable, Identifiable {
        var id: String
        var name: String
        var update: String?
        var date: Date?
        var changes: [String]
    }

    var rows: [Row]
    var games: [GameLine]?
    var unreadCount: Int
    var hasGames: Bool

    static let empty = WidgetSnapshot(rows: [], games: nil, unreadCount: 0, hasGames: false)

    /// Gallery preview, same sample as the share card.
    static let sample = WidgetSnapshot(
        rows: [Row(gameID: "the-blood-of-dawnwalker", game: "The Blood of Dawnwalker", releaseID: "update-1-1",
                   update: "Update 1.1", date: Date(timeIntervalSince1970: 1_792_627_200), unread: true)],
        games: nil, unreadCount: 1, hasGames: true)

    static var containerURL: URL? { FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: group) }

    static func coverData() -> Data? {
        containerURL.flatMap { try? Data(contentsOf: $0.appendingPathComponent(coverFile)) }
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
