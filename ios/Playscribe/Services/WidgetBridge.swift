import Foundation
import WidgetKit

/// Publishes the Latest updates to the Home Screen widget (r050-widget).
enum WidgetBridge {
    @MainActor static func publish(_ model: AppModel) {
        let cards = model.latestDeck.filter { $0.release != nil }
        let rows = cards.prefix(4).compactMap { c -> WidgetSnapshot.Row? in
            guard let r = c.release else { return nil }
            return .init(gameID: c.game.id, game: c.game.name, releaseID: r.id, update: r.displayName,
                         date: r.ps5Date, unread: c.unread)
        }
        let snap = WidgetSnapshot(rows: Array(rows), unreadCount: cards.filter(\.unread).count,
                                  hasGames: !model.data.collection.isEmpty)
        guard snap != WidgetSnapshot.load() else { return }
        snap.save()
        WidgetCenter.shared.reloadAllTimelines()
    }
}
