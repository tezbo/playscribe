import SwiftUI

/// Library "Upcoming" (0.5.0 item 14, PR 1): games not out yet. Watching a game files it as
/// Wishlist (a game added as Watching shows here too), so the existing status, menu and game page all apply; it moves to Playing on release day.
enum LibraryTab: String, CaseIterable, Identifiable {
    case playing, upcoming
    var id: String { rawValue }
    var label: String { self == .playing ? "Playing" : "Upcoming" }
}

extension AppModel {
    /// Watched games first (soonest first), then the catalogue's unreleased PS5 games.
    var upcomingWatched: [CatalogGame] {
        data.collection.compactMap { c -> CatalogGame? in
            guard c.status == .wishlist || c.status == .watching, let g = game(c.gameID), g.isUpcoming || g.releasePrecision == .tbd else { return nil }
            return g
        }.sorted { ($0.releaseDate?.isoDay ?? .distantFuture) < ($1.releaseDate?.isoDay ?? .distantFuture) }
    }

    var upcomingMore: [CatalogGame] {
        let inLibrary = Set(data.collection.compactMap { game($0.gameID)?.igdbID })
        let source = UpcomingStore.shared.games.isEmpty ? Self.catalogueUpcoming : UpcomingStore.shared.games
        return source.filter { g in g.igdbID.map { !inLibrary.contains($0) } ?? true }
    }

    @MainActor private static let catalogueUpcoming: [CatalogGame] = {
        let index = PS5Index.shared
        return index.entries.map { index.game($0) }.filter(\.isUpcoming)
            .sorted { ($0.releaseDate?.isoDay ?? .distantFuture) < ($1.releaseDate?.isoDay ?? .distantFuture) }
            .prefix(60).map { $0 }
    }()
}

struct LibraryTabPicker: View {
    @Environment(AppModel.self) private var model
    @Environment(\.duo) private var duo
    var body: some View {
        @Bindable var model = model
        Picker("Library", selection: $model.libraryTab) {
            ForEach(LibraryTab.allCases) { Text($0.label).tag($0) }
        }
        .pickerStyle(.segmented)
        .frame(minHeight: 44)
        .accessibilityIdentifier("libraryTabPicker")
        // Book: exactly the left page wide, so the control never crosses the fold (AX3, 7fe84f4).
        .frame(width: duo.pose == .book ? duo.division.map { max(0, $0.minX - 24 - 16) } : nil, alignment: .leading)
        .tappableFrame()
    }
}

struct UpcomingView: View {
    @Environment(AppModel.self) private var model

    private func dateLine(_ g: CatalogGame) -> String {
        // Ezra's copy: "Out today" on release day, otherwise the date line ("Out" only for dated, near releases).
        if (g.releasePrecision ?? .day) == .day, let d = g.releaseDate?.isoDay, Calendar.current.isDateInToday(d) { return "Out today" }
        let line = g.ps5DateLine ?? "Date to be announced"
        return line == "Release date TBA" ? "Date to be announced" : line
    }

    private func moveLine(_ g: CatalogGame) -> String? {
        g.igdbID.flatMap { UpcomingStore.shared.extras[$0]?.move?.line }
    }

    private func tile(_ g: CatalogGame, watching: Bool) -> some View {
        Button {
            if model.entry(g.id) == nil { model.addGame(g, status: .wishlist) }
            NotificationService.shared.syncReleaseDayAlerts()
            model.openGame(g.id)
        } label: {
            VStack(alignment: .leading, spacing: 6) {
                TileCover(game: g).aspectRatio(3 / 4, contentMode: .fit)
                Text(g.name).font(PlayscribeFont.subheadline.weight(.semibold)).lineLimit(2)
                Text(dateLine(g)).font(PlayscribeFont.caption).foregroundStyle(.secondary).lineLimit(2)
                if let move = moveLine(g) {
                    Text(move).font(PlayscribeFont.caption.weight(.semibold)).foregroundStyle(PlayscribeColor.accent).lineLimit(2)
                }
            }
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(g.name), \(dateLine(g))\(moveLine(g).map { ", " + $0 } ?? "")\(watching ? ", on your watchlist" : "")")
        .accessibilityAddTraits(.isButton)
        .tappableFrame()
    }

    var body: some View {
        let watched = model.upcomingWatched
        let more = model.upcomingMore
        let columns = [GridItem(.adaptive(minimum: 104, maximum: 160), spacing: 10, alignment: .top)]
        VStack(alignment: .leading, spacing: 14) {
            if UpcomingStore.shared.failed && more.isEmpty {
                HStack {
                    Text("Couldn't load upcoming games. Check your connection and try again.").font(PlayscribeFont.subheadline).foregroundStyle(.secondary)
                    Spacer(minLength: 0)
                    Button { Task { await UpcomingStore.shared.load() } } label: { Text("Retry").frame(minWidth: 44, minHeight: 44).contentShape(Rectangle()) }
                        .font(PlayscribeFont.subheadline.weight(.semibold)).foregroundStyle(PlayscribeColor.accent)
                        .tappableFrame()
                }
            }
            if watched.isEmpty {
                VStack(spacing: 8) {
                    Text("Nothing on your watchlist yet").font(PlayscribeFont.headline)
                    Text("Watch a game that isn't out yet and Playscribe will tell you when its first update lands.")
                        .font(PlayscribeFont.subheadline).foregroundStyle(.secondary).multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 20)
                .accessibilityElement(children: .combine)
            } else {
                let soon = watched.filter { g in
                    guard (g.releasePrecision ?? .day) == .day, let d = g.releaseDate?.isoDay else { return false }
                    return d >= Calendar.current.startOfDay(for: .now) && d.timeIntervalSinceNow < 7 * 86400
                }
                let later = watched.filter { g in !soon.contains { $0.id == g.id } }
                if !soon.isEmpty {
                    Text("Out this week").font(PlayscribeFont.headline).accessibilityAddTraits(.isHeader)
                        .accessibilityLabel("Out this week, \(soon.count) game\(soon.count == 1 ? "" : "s")")
                    LazyVGrid(columns: columns, spacing: 14) { ForEach(soon) { tile($0, watching: true) } }
                }
                if !later.isEmpty {
                    let laterTitle = soon.isEmpty ? "On your watchlist" : "Coming later"
                    Text(laterTitle).font(PlayscribeFont.headline).accessibilityAddTraits(.isHeader)
                        .accessibilityLabel("\(laterTitle), \(later.count) game\(later.count == 1 ? "" : "s")")
                    LazyVGrid(columns: columns, spacing: 14) { ForEach(later) { tile($0, watching: true) } }
                }
            }
            if more.isEmpty && watched.isEmpty && UpcomingStore.shared.loading {
                HStack(spacing: 10) {
                    ProgressView()
                    Text("Loading upcoming games").font(PlayscribeFont.subheadline).foregroundStyle(.secondary)
                }
                .accessibilityElement(children: .combine)
            } else if more.isEmpty && watched.isEmpty && !UpcomingStore.shared.failed {
                Text("Nothing upcoming. Announced updates will show here.").font(PlayscribeFont.subheadline).foregroundStyle(.secondary)
            } else if !more.isEmpty {
                Text("Coming to PS5").font(PlayscribeFont.headline)
                LazyVGrid(columns: columns, spacing: 14) { ForEach(more) { tile($0, watching: false) } }
            }
        }
        .task { await UpcomingStore.shared.load() }
    }
}
