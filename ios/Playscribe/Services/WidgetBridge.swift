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
                         date: r.ps5Date, unread: c.unread, chip: r.versionChip)
        }
        // Cover thumbnails: each row's bundled official art, scaled down. No art, no thumbnail.
        // Stale thumbnails from earlier publishes are removed so the container stays small.
        if let dir = WidgetSnapshot.containerURL {
            let keep = Set(rows.map { WidgetSnapshot.coverFile(for: $0.releaseID) })
            for f in (try? FileManager.default.contentsOfDirectory(atPath: dir.path)) ?? []
            where f.hasPrefix(WidgetSnapshot.coverPrefix) && !keep.contains(f) {
                try? FileManager.default.removeItem(at: dir.appendingPathComponent(f))
            }
            for i in rows.indices {
                guard let asset = cards.first(where: { $0.release?.id == rows[i].releaseID })?.game.keyArtAsset,
                      let img = UIImage(named: asset) else { continue }
                let size = CGSize(width: 360, height: 360 * img.size.height / max(img.size.width, 1))
                let thumb = UIGraphicsImageRenderer(size: size).image { _ in img.draw(in: CGRect(origin: .zero, size: size)) }
                let url = dir.appendingPathComponent(WidgetSnapshot.coverFile(for: rows[i].releaseID))
                if let data = thumb.jpegData(compressionQuality: 0.7), (try? data.write(to: url, options: .atomic)) != nil {
                    rows[i].hasCover = true
                }
            }
        }
        let snap = WidgetSnapshot(rows: Array(rows), unreadCount: cards.filter(\.unread).count,
                                  hasGames: !model.data.collection.isEmpty)
        guard snap != WidgetSnapshot.load() else { return }
        snap.save()
        WidgetCenter.shared.reloadAllTimelines()
    }
}
