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
    /// Measured width of the grid area, so the columns can share it out exactly.
    @State private var width: CGFloat = 0
    @Environment(\.duo) private var duo
    @Environment(\.railWidth) private var railWidth

    /// Book: how many of `n` tiles go on the left page, in proportion to each page's column count
    /// (the same split the Library uses), so the rest flow onto the right page and none crosses the fold.
    static func leftCount(of n: Int, leftColumns: Int, rightColumns: Int) -> Int {
        min(n, Int((Double(n) * Double(leftColumns) / Double(leftColumns + rightColumns)).rounded(.up)))
    }

    /// The Library's tile metric (Iris, #287): 120-168 pt tiles, 16 pt gaps, at least 3 columns; a short row sits left-aligned.
    static let gap = LibraryShelf.tileGap
    static func fit(width: CGFloat) -> (count: Int, size: CGFloat) { LibraryShelf.pageFit(width: width) }

    /// Book: both pages keep their own column count, but share one tile size, the smaller of the two, so a
    /// tile never changes size across the fold (Iris, #287). The narrower page's fit is the one that always fits both.
    static func bookFits(leftWidth: CGFloat, rightWidth: CGFloat) -> (left: (count: Int, size: CGFloat), right: (count: Int, size: CGFloat)) {
        var l = fit(width: leftWidth), r = fit(width: rightWidth)
        let size = min(l.size, r.size)
        l.size = size; r.size = size
        return (l, r)
    }

    /// One section: its header (24 pt above, 12 pt below) and tiles. In Book each page gets its own
    /// columns, so the fold falls in the gap between two grids and never through a tile or a header (G-4);
    /// a section that spills onto the right page repeats its plain header there. Closed stays 3 across.
    private func header(_ title: String, spoken: String?) -> some View {
        Text(title).font(PlayscribeFont.headline).accessibilityAddTraits(.isHeader)
            .accessibilityLabel(spoken ?? title)
            .padding(.top, 10)   // 24 pt above with the stack's 14 pt spacing
    }

    private func page(_ list: [CatalogGame], _ fit: (count: Int, size: CGFloat), watching: Bool) -> some View {
        LazyVGrid(columns: Array(repeating: GridItem(.fixed(fit.size), spacing: Self.gap, alignment: .top), count: fit.count),
                  alignment: .leading, spacing: 14) { ForEach(list) { tile($0, watching: watching) } }
    }

    /// Open and Tabletop: a short section is only as wide as its tiles, so the next section can sit beside it
    /// instead of leaving the rest of the row empty (Terry, 6 Nov). Longer sections still fill the row.
    static func blockColumns(games: Int, available: Int) -> Int { max(1, min(games, available)) }

    @ViewBuilder private func section(_ title: String, count: Int? = nil, games: [CatalogGame], watching: Bool, packed: Bool = false) -> some View {
        let spoken = count.map { "\(title), \($0) game\($0 == 1 ? "" : "s")" } ?? title
        if duo.pose == .book, let fold = duo.division {
            // Same page geometry as the Library's Book layout (the grids share its scroll origin).
            let leftWidth = max(0, fold.minX - 24 - 16)
            let rightStart = fold.maxX + 24 - 16
            let rightWidth = max(0, duo.size.width - railWidth - 16 - (fold.maxX + 24))
            let (left, right) = Self.bookFits(leftWidth: leftWidth, rightWidth: rightWidth)
            let k = Self.leftCount(of: games.count, leftColumns: left.count, rightColumns: right.count)
            HStack(alignment: .top, spacing: 0) {
                VStack(alignment: .leading, spacing: 12) {
                    header(title, spoken: spoken)
                    page(Array(games.prefix(k)), left, watching: watching)
                }.frame(width: leftWidth, alignment: .topLeading)
                VStack(alignment: .leading, spacing: 12) {
                    if games.count > k { header(title, spoken: nil).accessibilityHidden(true); page(Array(games.dropFirst(k)), right, watching: watching) }
                }.frame(width: rightWidth, alignment: .topLeading)
                    .padding(.leading, max(0, rightStart - leftWidth))
            }
        } else {
            VStack(alignment: .leading, spacing: 12) {
                header(title, spoken: spoken)
                if duo.pose == .closed {
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: Self.gap, alignment: .top), count: 3),
                              alignment: .leading, spacing: 14) { ForEach(games) { tile($0, watching: watching) } }
                } else if width > 0 {
                    let f = Self.fit(width: width)
                    if packed {
                        let k = Self.blockColumns(games: games.count, available: f.count)
                        page(games, (k, f.size), watching: watching)
                            .frame(width: CGFloat(k) * f.size + CGFloat(k - 1) * Self.gap, alignment: .topLeading)
                    } else {
                        page(games, f, watching: watching)
                    }
                } else {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 120, maximum: 168), spacing: Self.gap, alignment: .top)],
                              alignment: .leading, spacing: 14) { ForEach(games) { tile($0, watching: watching) } }
                }
            }
        }
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
            // Opening a game never changes its status; watching is the game page's own control.
            model.browseGame(g)
        } label: {
            VStack(alignment: .leading, spacing: 6) {
                TileCover(game: g).aspectRatio(3 / 4, contentMode: .fit)
                Text(g.name).font(PlayscribeFont.subheadline.weight(.semibold)).lineLimit(3)
                Text(dateLine(g)).font(PlayscribeFont.caption).foregroundStyle(.secondary).lineLimit(2).fixedSize(horizontal: false, vertical: true)
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
                // Book: the empty state stays on the left page, centred there, never across the spine (Quinn, #348).
                .frame(width: duo.pose == .book ? duo.division.map { max(0, $0.minX - 24 - 16) } : nil)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.vertical, 20)
                .accessibilityElement(children: .combine)
            } else {
                let soon = watched.filter { g in
                    guard (g.releasePrecision ?? .day) == .day, let d = g.releaseDate?.isoDay else { return false }
                    return d >= Calendar.current.startOfDay(for: .now) && d.timeIntervalSinceNow < 7 * 86400
                }
                let later = watched.filter { g in !soon.contains { $0.id == g.id } }
                let laterTitle = soon.isEmpty ? "On your watchlist" : "Coming later"
                if duo.pose == .flat || duo.pose == .tabletop {
                    // Blocks wrap: two short sections share a row, a long one takes its own (top-aligned).
                    FlowLayout(spacing: Self.gap) {
                        if !soon.isEmpty { section("Out this week", count: soon.count, games: soon, watching: true, packed: true) }
                        if !later.isEmpty { section(laterTitle, count: later.count, games: later, watching: true, packed: true) }
                    }
                } else {
                    if !soon.isEmpty { section("Out this week", count: soon.count, games: soon, watching: true) }
                    if !later.isEmpty { section(laterTitle, count: later.count, games: later, watching: true) }
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
                section("Coming to PS5", games: more, watching: false)
            }
        }
        .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { width = $0 }
        .task { await UpcomingStore.shared.load() }
    }
}
