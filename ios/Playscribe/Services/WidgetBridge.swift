import Foundation
import UIKit
import WidgetKit

/// Publishes the Latest updates to the Home Screen widget (r050-widget).
enum WidgetBridge {
    @MainActor static func publish(_ model: AppModel) {
        let cards = model.latestDeck.filter { $0.release != nil }
        var rows = cards.prefix(4).compactMap { c -> WidgetSnapshot.Row? in
            guard let r = c.release else { return nil }
            return .init(gameID: c.game.id, game: c.game.name, releaseID: r.id, update: r.displayName,
                         date: r.ps5Date, unread: c.unread)
        }
        // Small widget cover: the first game's bundled art, scaled down. Official art only; no art, no thumbnail.
        if !rows.isEmpty, let asset = cards.first?.game.keyArtAsset, let img = UIImage(named: asset),
           let url = WidgetSnapshot.containerURL?.appendingPathComponent(WidgetSnapshot.coverFile) {
            let size = CGSize(width: 320, height: 320 * img.size.height / max(img.size.width, 1))
            let thumb = UIGraphicsImageRenderer(size: size).image { _ in img.draw(in: CGRect(origin: .zero, size: size)) }
            if let data = thumb.jpegData(compressionQuality: 0.7), (try? data.write(to: url, options: .atomic)) != nil {
                rows[0].hasCover = true
            }
        }
        let lines = model.data.collection.compactMap { c -> WidgetSnapshot.GameLine? in
            guard let g = model.game(c.gameID) else { return nil }
            let latest = model.ps5Releases(c.gameID).filter { $0.ps5State == .onPS5 }.max { $0.ps5Date < $1.ps5Date }
            let changes = (latest?.ps5KeyChanges ?? []).prefix(3)
            return .init(id: g.id, name: g.name, update: latest?.displayName, date: latest?.ps5Date, changes: Array(changes))
        }
        let snap = WidgetSnapshot(rows: Array(rows), games: lines, unreadCount: cards.filter(\.unread).count,
                                  hasGames: !model.data.collection.isEmpty)
        guard snap != WidgetSnapshot.load() else { return }
        snap.save()
        WidgetCenter.shared.reloadAllTimelines()
        GameSpotlight.index(lines)
    }
}
