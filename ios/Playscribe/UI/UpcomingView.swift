import SwiftUI

/// Library "Upcoming" (0.5.0 item 14, PR 1): games not out yet. Watching a game files it as
/// Wishlist, so the existing status, menu and game page all apply; it moves to Playing on release day.
enum LibraryTab: String, CaseIterable, Identifiable {
    case playing, upcoming
    var id: String { rawValue }
    var label: String { self == .playing ? "Playing" : "Upcoming" }
}

extension AppModel {
    /// Watched games first (soonest first), then the catalogue's unreleased PS5 games.
    var upcomingWatched: [CatalogGame] {
        data.collection.compactMap { c -> CatalogGame? in
            guard c.status == .wishlist, let g = game(c.gameID), g.isUpcoming || g.releasePrecision == .tbd else { return nil }
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
    /// Measured width of the grid area, so the columns can share it out exactly.
    @State private var width: CGFloat = 0
    @Environment(\.duo) private var duo
    @Environment(\.railWidth) private var railWidth

    /// Book: how many of `n` tiles go on the left page, in proportion to each page's column count
    /// (the same split the Library uses), so the rest flow onto the right page and none crosses the fold.
    static func leftCount(of n: Int, leftColumns: Int, rightColumns: Int) -> Int {
        min(n, Int((Double(n) * Double(leftColumns) / Double(leftColumns + rightColumns)).rounded(.up)))
    }

    /// One section's tiles. In Book each page gets its own columns, sharing the page width, so the fold
    /// falls in the gap between the two grids and never through a tile (G-4); elsewhere one grid spans the width.
    @ViewBuilder private func grid(_ games: [CatalogGame], watching: Bool, columns: [GridItem]) -> some View {
        if duo.pose == .book, let fold = duo.division {
            // Same page geometry as the Library's Book layout (the grids share its scroll origin).
            let leftWidth = max(0, fold.minX - 24 - 16)
            let rightStart = fold.maxX + 24 - 16
            let rightWidth = max(0, duo.size.width - railWidth - 16 - (fold.maxX + 24))
            let left = LibraryShelf.pageFit(width: leftWidth), right = LibraryShelf.pageFit(width: rightWidth)
            let k = Self.leftCount(of: games.count, leftColumns: left.count, rightColumns: right.count)
            func page(_ list: [CatalogGame], _ fit: (count: Int, size: CGFloat)) -> some View {
                LazyVGrid(columns: Array(repeating: GridItem(.fixed(fit.size), spacing: 10, alignment: .top), count: fit.count),
                          alignment: .leading, spacing: 14) { ForEach(list) { tile($0, watching: watching) } }
            }
            HStack(alignment: .top, spacing: 0) {
                page(Array(games.prefix(k)), left).frame(width: leftWidth, alignment: .topLeading)
                page(Array(games.dropFirst(k)), right).frame(width: rightWidth, alignment: .topLeading)
                    .padding(.leading, max(0, rightStart - leftWidth))
            }
        } else {
            LazyVGrid(columns: columns, spacing: 14) { ForEach(games) { tile($0, watching: watching) } }
        }
    }

    /// Columns that fill the width: tiles at least 104 pt, 10 pt gaps, the leftover shared equally,
    /// so no dead strip is left on the trailing side (a capped adaptive grid left one when wide).
    static func fit(width: CGFloat) -> (count: Int, size: CGFloat) {
        let n = max(2, Int((width + 10) / 114))
        // Rounded down to the hundredth so n tiles and n - 1 gaps never exceed the width.
        return (n, (((width - CGFloat(n - 1) * 10) / CGFloat(n)) * 100).rounded(.down) / 100)
    }

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
        .gameQuickActions(g)
    }

    var body: some View {
        let watched = model.upcomingWatched
        let more = model.upcomingMore
        let columns: [GridItem]
        if width > 0 {
            let f = Self.fit(width: width)
            columns = Array(repeating: GridItem(.fixed(f.size), spacing: 10, alignment: .top), count: f.count)
        } else {
            columns = [GridItem(.adaptive(minimum: 104), spacing: 10, alignment: .top)]
        }
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
                    grid(soon, watching: true, columns: columns)
                }
                if !later.isEmpty {
                    let laterTitle = soon.isEmpty ? "On your watchlist" : "Coming later"
                    Text(laterTitle).font(PlayscribeFont.headline).accessibilityAddTraits(.isHeader)
                        .accessibilityLabel("\(laterTitle), \(later.count) game\(later.count == 1 ? "" : "s")")
                    grid(later, watching: true, columns: columns)
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
                grid(more, watching: false, columns: columns)
            }
        }
        .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { width = $0 }
        .task { await UpcomingStore.shared.load() }
    }
}
