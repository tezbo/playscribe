import SwiftUI
import UIKit
import WidgetKit

/// The Home Screen widget views, shared by the extension and the app target so tests can render them (J-15).
struct SnapshotEntry: TimelineEntry {
    var date: Date
    var snapshot: WidgetSnapshot
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

struct Notice: View {
    var title: String
    var message: String
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Image(systemName: "book.closed.fill").font(W.big).foregroundStyle(W.accent).accessibilityHidden(true)
            Text(title).font(W.big)
            Text(message).font(W.body).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(title), \(message.widgetLowercasedFirst)")
    }
}

private extension String {
    var widgetLowercasedFirst: String { prefix(1).lowercased() + dropFirst() }
}

struct WidgetView: View {
    @Environment(\.widgetFamily) private var envFamily
    @Environment(\.colorScheme) private var scheme
    var entry: SnapshotEntry
    /// Snapshot tests set this; WidgetKit's family is read-only outside a widget.
    var forcedFamily: WidgetFamily?
    private var family: WidgetFamily { forcedFamily ?? envFamily }

    private var limit: Int {
        switch family { case .systemSmall: 1; case .systemMedium: 3; default: 5 }
    }

    var body: some View {
        if family == .accessoryRectangular || family == .accessoryInline {
            lockScreen
        } else {
            home
        }
    }

    /// Lock Screen: the newest unread update, else the newest. Tapping opens it.
    @ViewBuilder private var lockScreen: some View {
        let snap = entry.snapshot
        let row = snap.rows.first { $0.unread } ?? snap.rows.first
        Group {
            if !snap.hasGames {
                if family == .accessoryInline { Text("Add your games") } else { lockText("Add your games", "Open Playscribe to build your library.") }
            } else if let r = row {
                if family == .accessoryInline {
                    Text(r.unread ? "New: \(r.game)" : r.game)
                } else {
                    lockText(r.game, r.update + (r.unread ? ", new" : ""))
                }
            } else if family == .accessoryInline {
                Text("You're all caught up")
            } else {
                lockText("You're all caught up", "Playscribe will show new updates here.")
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(row.map(voice) ?? (snap.hasGames ? "You're all caught up" : "Add your games, open Playscribe to build your library"))
        .widgetURL(row?.url)
        .containerBackground(for: .widget) { Color.clear }
    }

    private func lockText(_ title: String, _ detail: String) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(title).font(W.title).lineLimit(2)
            Text(detail).font(W.body).lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var home: some View {
        let snap = entry.snapshot
        let rows = Array(snap.rows.prefix(limit))
        return Group {
            if !snap.hasGames {
                Notice(title: "Add your first game", message: "Open Playscribe to build your library.")
                    .accessibilityLabel("Add your games, open Playscribe to build your library")
                    .foregroundStyle(scheme == .dark ? W.primary : W.ink900)
            } else if rows.isEmpty {
                Notice(title: "All caught up", message: "Playscribe will show new updates here.")
                    .foregroundStyle(scheme == .dark ? W.primary : W.ink900)
            } else if family == .systemSmall, let r = rows.first {
                HeroText(row: r, tall: true).widgetURL(r.url)
            } else if family == .systemMedium, let r = rows.first {
                HStack(spacing: 12) {
                    HeroText(row: r, tall: true)
                        .frame(maxWidth: .infinity)
                        .widgetURL(r.url)
                    VStack(alignment: .leading, spacing: 8) {
                        ForEach(rows.dropFirst()) { ThumbRow(row: $0) }
                        if rows.count == 1 { Spacer(minLength: 0) }
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                    .foregroundStyle(scheme == .dark ? W.primary : W.ink900)
                }
            } else if let r = rows.first {
                VStack(alignment: .leading, spacing: 10) {
                    HeroText(row: r, tall: false)
                        .frame(height: 140)
                        .widgetURL(r.url)
                    if snap.unreadCount > 0 {
                        Text(snap.unreadCount == 1 ? "1 new update" : "\(snap.unreadCount) new updates").font(W.big)
                    }
                    ForEach(rows.dropFirst()) { ThumbRow(row: $0) }
                    Spacer(minLength: 0)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .foregroundStyle(scheme == .dark ? W.primary : W.ink900)
            }
        }
        .containerBackground(for: .widget) { WidgetBackground(entry: entry) }
    }
}

/// The widget's background: art edge to edge on the small, the left half of the medium and the top of the large.
struct WidgetBackground: View {
    @Environment(\.widgetFamily) private var envFamily
    @Environment(\.colorScheme) private var scheme
    var entry: SnapshotEntry
    var forcedFamily: WidgetFamily?
    private var family: WidgetFamily { forcedFamily ?? envFamily }
    var body: some View {
        let plate = scheme == .dark ? W.ink950 : W.vellum100
        if entry.snapshot.rows.isEmpty || !entry.snapshot.hasGames
            || family == .accessoryRectangular || family == .accessoryInline {
            plate
        } else if family == .systemSmall {
            HeroArt(row: entry.snapshot.rows[0])
        } else if family == .systemMedium {
            HStack(spacing: 0) {
                HeroArt(row: entry.snapshot.rows[0]).frame(maxWidth: .infinity)
                plate.frame(maxWidth: .infinity)
            }
        } else {
            VStack(spacing: 0) {
                HeroArt(row: entry.snapshot.rows[0]).frame(height: 168)
                plate
            }
        }
    }
}

/// Test-only: covers injected by a snapshot test, keyed by release ID, used when the App Group has none.
private struct InjectedCoversKey: EnvironmentKey {
    static var defaultValue: [String: UIImage] { [:] }
}
extension EnvironmentValues {
    var injectedCovers: [String: UIImage] {
        get { self[InjectedCoversKey.self] }
        set { self[InjectedCoversKey.self] = newValue }
    }
}

/// One widget tile as it looks on the Home Screen, for snapshot tests: background, content margins and corner radius.
struct WidgetCanvas: View {
    var entry: SnapshotEntry
    var family: WidgetFamily
    var scheme: ColorScheme
    var size: CGSize
    var covers: [String: UIImage] = [:]
    var tinted = false
    var body: some View {
        WidgetView(entry: entry, forcedFamily: family)
            .padding(16)
            .frame(width: size.width, height: size.height)
            .background { WidgetBackground(entry: entry, forcedFamily: family) }
            .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
            .environment(\.colorScheme, scheme)
            .environment(\.injectedCovers, covers)
            .grayscale(tinted ? 1 : 0)
            .colorMultiply(tinted ? W.accent : .white)
    }
}

private func cover(_ r: WidgetSnapshot.Row, injected: [String: UIImage] = [:]) -> UIImage? {
    if let img = injected[r.releaseID] { return img }
    return r.hasCover ? WidgetSnapshot.coverData(for: r).flatMap { UIImage(data: $0) } : nil
}

/// Official art with a scrim that keeps white text at 4.5:1 or better on any cover. With no art (gallery
/// preview, no cover written) a plum plate stands in so the tile is never blank.
struct HeroArt: View {
    @Environment(\.injectedCovers) private var injected
    var row: WidgetSnapshot.Row
    var body: some View {
        ZStack {
            if let img = cover(row, injected: injected) {
                Color.clear.overlay {
                    Image(uiImage: img).resizable().widgetAccentedRenderingMode(.desaturated).scaledToFill()
                }.clipped()
            } else {
                LinearGradient(colors: [Color(red: 0.231, green: 0.176, blue: 0.341), W.ink950],
                               startPoint: .topLeading, endPoint: .bottomTrailing)
            }
            LinearGradient(colors: [W.ink950.opacity(0.25), W.ink950.opacity(0.92)], startPoint: .top, endPoint: .bottom)
        }
    }
}

/// The text block that sits on the art: chips, game, update, age. No note text.
struct HeroText: View {
    var row: WidgetSnapshot.Row
    var tall: Bool
    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Spacer(minLength: 0)
            HStack(spacing: 6) {
                if row.unread { NewChip() }
                if !tall, let c = row.chip { Text(c).font(W.chip).foregroundStyle(W.primary) }
            }
            Text(row.game).font(W.title).lineLimit(2).minimumScaleFactor(0.85)
            Text(row.update).font(W.body).lineLimit(1)
            Text(age(row.date)).font(W.body).lineLimit(1)
        }
        .foregroundStyle(W.primary)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(voice(row))
    }
}

/// Inset art card for the medium and large widgets.
struct HeroCard: View {
    var row: WidgetSnapshot.Row
    var tall: Bool
    var body: some View {
        ZStack {
            HeroArt(row: row)
            HeroText(row: row, tall: tall).padding(10)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

/// Small cover, game, update and date. Tapping opens that update.
struct ThumbRow: View {
    @Environment(\.injectedCovers) private var injected
    var row: WidgetSnapshot.Row
    var body: some View {
        Link(destination: row.url) {
            HStack(spacing: 8) {
                Group {
                    if let img = cover(row, injected: injected) {
                        Image(uiImage: img).resizable().scaledToFill()
                    } else {
                        W.ink900
                    }
                }
                .frame(width: 36, height: 36).clipShape(RoundedRectangle(cornerRadius: 8))
                .overlay(alignment: .topTrailing) {
                    if row.unread { Circle().fill(W.accent).frame(width: 10, height: 10).offset(x: 3, y: -3) }
                }
                VStack(alignment: .leading, spacing: 1) {
                    Text(row.game).font(W.title).lineLimit(2).minimumScaleFactor(0.9)
                    Text(row.update).font(W.body).foregroundStyle(.secondary).lineLimit(1)
                }
                Spacer(minLength: 0)
            }
            .frame(minHeight: 44)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(voice(row))
    }
}

