import SwiftUI
import WidgetKit

struct SnapshotProvider: TimelineProvider {
    func placeholder(in context: Context) -> SnapshotEntry { SnapshotEntry(date: .now, snapshot: .sample) }
    func getSnapshot(in context: Context, completion: @escaping (SnapshotEntry) -> Void) {
        completion(SnapshotEntry(date: .now, snapshot: context.isPreview ? .sample : .load()))
    }
    func getTimeline(in context: Context, completion: @escaping (Timeline<SnapshotEntry>) -> Void) {
        let entry = SnapshotEntry(date: .now, snapshot: .load())
        completion(Timeline(entries: [entry], policy: .after(.now.addingTimeInterval(3600))))
    }
}

@main
struct PlayscribeWidgetBundle: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "LatestUpdates", provider: SnapshotProvider()) { entry in
            WidgetView(entry: entry)
        }
        .configurationDisplayName("Latest updates")
        .description("See the newest updates for your games.")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge, .accessoryRectangular, .accessoryInline])
    }
}

#if DEBUG
private func previewEntry(_ snap: WidgetSnapshot) -> SnapshotEntry { SnapshotEntry(date: .now, snapshot: snap) }

private var previewMany: WidgetSnapshot {
    let base = WidgetSnapshot.sample.rows[0]
    var rows = [base]
    for (i, g) in ["Kingdom Come: Deliverance II", "CONTROL Resonant", "Blue Prince"].enumerated() {
        var r = base
        r.gameID = "g\(i)"; r.game = g; r.releaseID = "r\(i)"; r.update = "Update 1.\(i + 2)"
        r.date = base.date.addingTimeInterval(-Double(i + 1) * 86_400); r.unread = i == 0; r.chip = "v1.\(i + 2)"
        rows.append(r)
    }
    return WidgetSnapshot(rows: rows, unreadCount: 2, hasGames: true)
}

/// Preview harness: S/M/L, light and dark, plus the empty and no-games states.
#Preview("Small", as: .systemSmall) { PlayscribeWidgetBundle() } timeline: { previewEntry(previewMany) }
#Preview("Medium", as: .systemMedium) { PlayscribeWidgetBundle() } timeline: { previewEntry(previewMany) }
#Preview("Large", as: .systemLarge) { PlayscribeWidgetBundle() } timeline: { previewEntry(previewMany) }
#Preview("Caught up", as: .systemMedium) { PlayscribeWidgetBundle() } timeline: {
    previewEntry(WidgetSnapshot(rows: [], unreadCount: 0, hasGames: true))
}
#Preview("No games", as: .systemSmall) { PlayscribeWidgetBundle() } timeline: { previewEntry(.empty) }
#endif
