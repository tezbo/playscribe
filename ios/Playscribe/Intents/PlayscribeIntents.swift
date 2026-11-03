import AppIntents
import CoreSpotlight
import Foundation

// SPIKE (draft): Siri, Shortcuts and Spotlight for "What's new in <game>?".
// Reads the same App Group snapshot the widget uses, so an intent never needs the app's model.
// Every API here must be checked against the installed SDK's swiftinterface before this leaves draft.

nonisolated struct GameEntity: AppEntity {
    static let typeDisplayRepresentation = TypeDisplayRepresentation(name: "Game")
    static let defaultQuery = GameQuery()
    let id: String
    let name: String
    var displayRepresentation: DisplayRepresentation { DisplayRepresentation(title: "\(name)") }
}

nonisolated struct GameQuery: EntityStringQuery {
    private func all() -> [GameEntity] {
        (WidgetSnapshot.load().games ?? []).map { GameEntity(id: $0.id, name: $0.name) }
    }
    func entities(for identifiers: [String]) async throws -> [GameEntity] { all().filter { identifiers.contains($0.id) } }
    func entities(matching string: String) async throws -> [GameEntity] {
        all().filter { $0.name.localizedCaseInsensitiveContains(string) }
    }
    func suggestedEntities() async throws -> [GameEntity] { all() }
}

struct WhatsNewIntent: AppIntent {
    static let title: LocalizedStringResource = "What's new in a game"
    static let description = IntentDescription("Hears the newest PS5 update for one of your games.")

    @Parameter(title: "Game") var game: GameEntity

    func perform() async throws -> some IntentResult & ProvidesDialog {
        guard let line = WidgetSnapshot.load().games?.first(where: { $0.id == game.id }), let update = line.update else {
            return .result(dialog: "\(game.name) has no PS5 update yet.")
        }
        let when = line.date.map { " on \($0.formatted(.dateTime.day().month(.wide)))" } ?? ""
        let changes = line.changes.isEmpty ? "" : " " + line.changes.joined(separator: ". ") + "."
        return .result(dialog: "\(game.name), \(update)\(when).\(changes)")
    }
}

nonisolated struct PlayscribeShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(intent: WhatsNewIntent(), phrases: ["What's new in \(\.$game) in \(.applicationName)",
                                                        "Latest \(\.$game) update in \(.applicationName)"],
                    shortTitle: "What's new", systemImageName: "book")
    }
}

/// Library games in Spotlight. Tapping a result opens the game (see onContinueUserActivity in PlayscribeApp).
enum GameSpotlight {
    nonisolated static func index(_ lines: [WidgetSnapshot.GameLine]) {
        let items = lines.map { line -> CSSearchableItem in
            let attrs = CSSearchableItemAttributeSet(contentType: .content)
            attrs.title = line.name
            attrs.contentDescription = line.update.map { "Latest PS5 update: \($0)" } ?? "PS5 patch notes"
            attrs.contentURL = URL(string: "playscribe://game/\(line.id)")
            return CSSearchableItem(uniqueIdentifier: "game:\(line.id)", domainIdentifier: "games", attributeSet: attrs)
        }
        let index = CSSearchableIndex.default()
        index.deleteSearchableItems(withDomainIdentifiers: ["games"]) { _ in
            index.indexSearchableItems(items) { _ in }
        }
    }
}
