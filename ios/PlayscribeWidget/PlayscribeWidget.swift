import SwiftUI
import WidgetKit

struct SnapshotEntry: TimelineEntry {
    var date: Date
    var snapshot: WidgetSnapshot
}

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

private enum W {
    static let primary = Color(red: 0.957, green: 0.933, blue: 0.890)
    static let secondary = Color(red: 0.725, green: 0.694, blue: 0.765)
    static let ink900 = Color(red: 0.059, green: 0.055, blue: 0.078)
    static let ink950 = Color(red: 0.035, green: 0.031, blue: 0.047)
    static let vellum100 = Color(red: 0.984, green: 0.957, blue: 0.902)
    static let accent = Color(red: 1.0, green: 0.69, blue: 0.31)
    static let onAccent = Color(red: 0.165, green: 0.086, blue: 0)
    static let title = Font.custom("InstrumentSans-SemiBold", size: 15, relativeTo: .headline)
    static let body = Font.custom("InstrumentSans-Regular", size: 13, relativeTo: .subheadline)
    static let chip = Font.custom("InstrumentSans-SemiBold", size: 11, relativeTo: .caption)
    static let big = Font.custom("InstrumentSans-Bold", size: 20, relativeTo: .title3)
}

private func age(_ d: Date) -> String {
    let f = RelativeDateTimeFormatter()
    f.unitsStyle = .full
    return f.localizedString(for: d, relativeTo: .now)
}

private func voice(_ r: WidgetSnapshot.Row) -> String {
    "\(r.game), \(r.update), \(age(r.date))" + (r.unread ? ", new" : "")
}

struct NewChip: View {
    var body: some View {
        Text("New").font(W.chip).foregroundStyle(W.onAccent)
            .padding(.horizontal, 7).padding(.vertical, 2)
            .background(W.accent, in: Capsule())
    }
}

struct UpdateRow: View {
    var row: WidgetSnapshot.Row
    var body: some View {
        Link(destination: row.url) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(row.game).font(W.title).lineLimit(1)
                    Text(row.update).font(W.body).foregroundStyle(.secondary).lineLimit(1)
                }
                Spacer(minLength: 8)
                VStack(alignment: .trailing, spacing: 2) {
                    if row.unread { NewChip() }
                    Text(row.date, format: .dateTime.day().month(.abbreviated)).font(W.body).foregroundStyle(.secondary)
                }
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(voice(row))
    }
}

struct Notice: View {
    var title: String
    var message: String
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(W.big)
            Text(message).font(W.body).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(title), \(message.lowercasedFirst)")
    }
}

private extension String {
    var lowercasedFirst: String { prefix(1).lowercased() + dropFirst() }
}

struct WidgetView: View {
    @Environment(\.widgetFamily) private var family
    @Environment(\.colorScheme) private var scheme
    var entry: SnapshotEntry

    private var limit: Int {
        switch family { case .systemSmall: 1; case .systemMedium: 2; default: 4 }
    }

    var body: some View {
        let snap = entry.snapshot
        let rows = Array(snap.rows.prefix(limit))
        Group {
            if !snap.hasGames {
                Notice(title: "Add your games", message: "Open Playscribe to build your library.")
                    .accessibilityLabel("Add your games, open Playscribe to build your library")
            } else if rows.isEmpty {
                Notice(title: "You're all caught up", message: "Playscribe will show new updates here.")
            } else if family == .systemSmall, let r = rows.first {
                VStack(alignment: .leading, spacing: 4) {
                    if r.unread { NewChip() }
                    Spacer(minLength: 0)
                    if r.hasCover, let data = WidgetSnapshot.coverData(), let img = UIImage(data: data) {
                        Image(uiImage: img).resizable().scaledToFill()
                            .frame(height: 44).clipShape(RoundedRectangle(cornerRadius: 8)).accessibilityHidden(true)
                    }
                    Text(r.game).font(W.title).lineLimit(3)
                    Text(r.update).font(W.body).foregroundStyle(.secondary).lineLimit(1)
                    Text(age(r.date)).font(W.body).foregroundStyle(.secondary).lineLimit(1)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(voice(r))
                .widgetURL(r.url)
            } else {
                VStack(alignment: .leading, spacing: 10) {
                    if family == .systemLarge, snap.unreadCount > 0 {
                        Text(snap.unreadCount == 1 ? "1 new update" : "\(snap.unreadCount) new updates").font(W.big)
                    }
                    ForEach(rows) { UpdateRow(row: $0) }
                    Spacer(minLength: 0)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            }
        }
        .foregroundStyle(scheme == .dark ? W.primary : W.ink900)
        .containerBackground(scheme == .dark ? W.ink950 : W.vellum100, for: .widget)
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
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
    }
}
