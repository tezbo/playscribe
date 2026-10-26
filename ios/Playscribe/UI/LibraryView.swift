import SwiftUI

struct LibraryView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.duo) private var duo

    var body: some View {
        Group {
            if model.data.collection.isEmpty {
                OnboardingView()
            } else if duo.pose == .tabletop {
                // D-5: the standing half shows the Continue art, display only; the grid is below.
                // The primary takes the standing (upper) half.
                ArrangementView {
                    LibraryStage()
                } secondary: {
                    LibraryShelf()
                }
                .arrangementViewStyle(.split)
            } else {
                LibraryShelf()
            }
        }
        .background(Color.ink0)
        .navigationTitle("Library")
        .toolbarTitleDisplayMode(.large)
        .toolbar {
            ToolbarItem(placement: .topBarPinnedTrailing) {
                Button { model.addSheetOpen = true } label: { Label("Add game", systemImage: "plus") }
                    .disabled(model.addSheetOpen)
            }
            // D-7: nothing to arrange in an empty library.
            if !model.data.collection.isEmpty {
                ToolbarItem(placement: .primaryAction) {
                    LibraryViewMenu()
                }
            }
        }
    }
}

/// Tabletop's standing half: the Continue art and title, view only (G-4, D-5).
struct LibraryStage: View {
    @Environment(AppModel.self) private var model
    @Environment(\.duo) private var duo

    var body: some View {
        let game = model.featuredGame
        ZStack(alignment: .bottomLeading) {
            ArtView(asset: game?.keyArtAsset, game: game, drift: true)
            LinearGradient(colors: [.clear, .black.opacity(0.75)], startPoint: .center, endPoint: .bottom)
            VStack(alignment: .leading, spacing: 8) {
                if let game {
                    Text(game.name).font(PlayscribeFont.title2.bold()).lineLimit(3)
                    if let c = model.continueItem, c.game.id == game.id {
                        Text("New on PS5: \(c.release.displayName)").font(PlayscribeFont.subheadline).foregroundStyle(.secondary)
                    }
                }
            }
            .padding(20)
        }
        .allowsHitTesting(false)
        .accessibilityElement(children: .contain)
    }
}

enum LibraryLayout: String, CaseIterable, Identifiable {
    case tiles, list
    var id: String { rawValue }
    var label: String { self == .tiles ? "Tiles" : "List" }
    var symbol: String { self == .tiles ? "square.grid.2x2" : "list.bullet" }
    static let key = "libraryLayout"
}

struct LibraryShelf: View {
    @Environment(AppModel.self) private var model
    @Environment(\.duo) private var duo
    @Environment(\.railWidth) private var railWidth
    @AppStorage(LibraryLayout.key) private var layout: LibraryLayout = .tiles

    /// D-12: one square tile size per pose.
    private var tileSize: CGFloat {
        switch duo.pose {
        case .closed: 88
        case .flat: duo.isLandscape ? 100 : 108
        case .book: 100
        case .tabletop: 84
        }
    }

    /// Book: an even column count across both pages (Apple: prefer an even number of columns).
    private var columns: [GridItem] {
        if duo.pose == .closed {
            return Array(repeating: GridItem(.flexible(), spacing: 12, alignment: .top), count: 3)
        }
        if let book = bookLayout {
            // A spacer column before each page's tiles centres them on their page; the fold
            // falls in the middle spacer, never through a tile.
            let tiles = { (n: Int) in (0..<n).map { i in GridItem(.fixed(tileSize), spacing: i == n - 1 ? 0 : 14, alignment: .top) } }
            return [GridItem(.fixed(book.lead), spacing: 0)] + tiles(book.perPage) + [GridItem(.fixed(book.gap), spacing: 0)] + tiles(book.perPage)
        }
        return [GridItem(.adaptive(minimum: tileSize, maximum: tileSize + 24), spacing: 14, alignment: .top)]
    }

    /// Book (D-12): the same number of tiles on each page (Apple: prefer an even number of
    /// columns), each group centred on its page.
    private var bookLayout: (perPage: Int, lead: CGFloat, gap: CGFloat)? {
        guard duo.pose == .book, let fold = duo.division else { return nil }
        let x0: CGFloat = 16, edge = duo.size.width - railWidth - 16
        let leftPage = fold.minX - 8 - x0, rightStart = fold.maxX + 8, rightPage = edge - rightStart
        var k = max(1, Int((min(leftPage, rightPage) + 14) / (tileSize + 14)))
        while k > 1 && CGFloat(k) * tileSize + CGFloat(k - 1) * 14 > min(leftPage, rightPage) { k -= 1 }
        let group = CGFloat(k) * tileSize + CGFloat(k - 1) * 14
        let lead = max(0, (leftPage - group) / 2)
        let gap = max(0, rightStart + max(0, (rightPage - group) / 2) - (x0 + lead + group))
        return (k, lead, gap)
    }

    /// Grid cells: in the book pose, an empty cell in each spacer column.
    private func cells(_ rows: [AppModel.LibraryRow]) -> [(id: String, row: AppModel.LibraryRow?)] {
        guard let book = bookLayout else { return rows.map { ($0.id, $0) } }
        var out: [(id: String, row: AppModel.LibraryRow?)] = []
        for (i, row) in rows.enumerated() {
            let slot = i % (book.perPage * 2)
            if slot == 0 { out.append(("lead-\(i)", nil)) }
            if slot == book.perPage { out.append(("gap-\(i)", nil)) }
            out.append((row.id, row))
        }
        return out
    }

    var body: some View {
        @Bindable var model = model
        let rows = model.shownRows()
        let all = model.libraryRows
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 14) {
                if let line = model.feedStatusLine {
                    HStack {
                        Text(line).font(PlayscribeFont.footnote).foregroundStyle(.secondary)
                        if case .failed = model.feedStatus {
                            Button("Retry") { Task { await model.refreshFeed() } }.font(PlayscribeFont.footnote).hitTarget()
                        }
                    }
                }
                if model.showsNotificationCard, let first = all.first {
                    NotificationInviteCard(gameName: first.game.name)
                }
                if all.count >= 6 {
                    TextField("Search your library", text: $model.data.nav.query)
                        .textFieldStyle(.roundedBorder)
                        .submitLabel(.search)
                        .frame(minHeight: 44)
                }
                // D-7: a narrowed list always says so and offers the way back.
                if model.nav.filter != .all && layout == .list {
                    Button { model.nav.filter = .all } label: {
                        Label("Showing \(model.nav.filter.label) · Show all", systemImage: "line.3.horizontal.decrease")
                            .font(PlayscribeFont.subheadline)
                            .frame(minHeight: 44)
                    }
                    .tappableFrame()
                }
                if rows.isEmpty {
                    VStack(spacing: 12) {
                        Text("No \(model.nav.filter == .all ? "" : model.nav.filter.label.lowercased() + " ")games").font(PlayscribeFont.headline)
                        Button("Show all") { model.nav.filter = .all; model.nav.query = "" }.hitTarget()
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 40)
                }
                // D-12: the Continue hero spans two tiles; Tabletop shows it on the standing half.
                if let c = model.continueItem {
                    ContinueRow(game: c.game, release: c.release)
                        // D-12: the full hero card in Closed and open portrait; side by side, a
                        // double-width tile.
                        .frame(maxWidth: layout == .tiles && duo.isLandscape ? tileSize * 2 + 14 + (duo.pose == .flat ? 120 : 0) : .infinity,
                               alignment: .leading)
                }
                if all.count >= 2 && layout == .tiles {
                    // TT-0: in the book pose the chip row stays on the left page.
                    FilterBar().frame(maxWidth: duo.pose == .book ? max(0, (duo.division?.minX ?? 0) - 24) : .infinity, alignment: .leading)
                }
                if layout == .list {
                    ForEach(rows) { row in GameRow(row: row).id("lib-\(row.id)") }
                } else {
                    LazyVGrid(columns: columns, alignment: .leading, spacing: 18) {
                        ForEach(cells(rows), id: \.id) { cell in
                            if let row = cell.row {
                                GameTile(row: row, size: tileSize).id("lib-\(row.id)")
                            } else {
                                Color.clear.frame(height: 1).accessibilityHidden(true)
                            }
                        }
                    }
                }
            }
            .scrollTargetLayout()
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .padding(.trailing, railWidth)
        }
        .scrollPosition(id: Binding(get: { model.nav.anchors["library"] }, set: { model.nav.anchors["library"] = $0 }), anchor: .top)
        .contentMargins(.bottom, model.pill == nil && model.toast == nil ? 0 : 96, for: .scrollContent)
        .refreshable { await model.refreshFeed() }
    }
}

extension AppModel {
    /// GR-1: one line under a game in the Library, tile or row: the newest PS5 release, else
    /// what is known about the game on PS5.
    /// The tile's shorter caption (D-12): the chip carries Unconfirmed, and the availability line
    /// drops the day.
    func tileLine(_ row: LibraryRow) -> String {
        if let r = row.latest { return "\(r.displayName) · \(r.ps5Date.dayMonth)" }
        if let r = ps5Releases(row.id).first { return r.isUnconfirmed ? r.displayName : "\(r.displayName) · Announced" }
        return "\(row.game.ps5ShortLine) · No notes"
    }

    func shelfLine(_ row: LibraryRow) -> String {
        if let r = row.latest { return "\(r.displayName) · \(r.ps5Date.dayMonth)" }
        if let r = ps5Releases(row.id).first { return "\(r.displayName) · \(r.isUnconfirmed ? "Unconfirmed" : "Announced")" }
        return "\(row.game.ps5AvailabilityLine) · No notes"
    }
}

/// D-12: the View menu under Add: Tiles or List, Sort and Filter. Every choice persists (D-13).
struct LibraryViewMenu: View {
    @Environment(AppModel.self) private var model
    @AppStorage(LibraryLayout.key) private var layout: LibraryLayout = .tiles

    var body: some View {
        @Bindable var model = model
        let rows = model.libraryRows
        Menu {
            Picker("Show as", selection: $layout) {
                ForEach(LibraryLayout.allCases) { Label($0.label, systemImage: $0.symbol).tag($0) }
            }
            .pickerStyle(.inline)
            Picker("Sort by", selection: $model.data.nav.sort) {
                ForEach(LibrarySort.allCases) { Text($0.label).tag($0) }
            }
            .pickerStyle(.menu)
            Picker("Show", selection: $model.data.nav.filter) {
                ForEach(LibraryFilter.allCases) { f in
                    let n = f.status.map { st in rows.filter { $0.status == st }.count } ?? rows.count
                    Text("\(f.label) (\(n))").tag(f)
                }
            }
            .pickerStyle(.menu)
            Divider()
            Button { model.settingsOpen = true } label: { Label("Settings", systemImage: "gearshape") }
        } label: {
            Label("View", systemImage: model.nav.filter == .all ? layout.symbol : "line.3.horizontal.decrease.circle.fill")
        }
        .accessibilityShowsLargeContentViewer()
    }
}


struct FilterBar: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        let rows = model.libraryRows
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(LibraryFilter.allCases) { f in
                    let n = f.status.map { s in rows.filter { $0.status == s }.count } ?? rows.count
                    let on = model.nav.filter == f
                    Button { model.nav.filter = f } label: {
                        Text("\(f.label) \(n)")
                            .font(PlayscribeFont.subheadline.weight(on ? .semibold : .regular))
                            .padding(.horizontal, 12)
                            .frame(minHeight: 44)
                            .background(on ? PlayscribeColor.accent.opacity(0.22) : Color.ink3, in: Capsule())
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(on ? .isSelected : [])
                    .tappableFrame()
                }
                Menu {
                    Picker("Sort by", selection: Binding(get: { model.nav.sort }, set: { model.nav.sort = $0 })) {
                        ForEach(LibrarySort.allCases) { Text($0.label).tag($0) }
                    }
                } label: {
                    Label(model.nav.sort.label, systemImage: "arrow.up.arrow.down")
                        .font(PlayscribeFont.subheadline)
                        .padding(.horizontal, 12)
                        .frame(minHeight: 44)
                        .background(Color.ink3, in: Capsule())
                }
                .tappableFrame()
            }
            .padding(.trailing, 24)
        }
        .edgeFade(40)
    }
}

extension View {
    /// R-7: a scrolling chip row fades at its edges instead of clipping hard.
    func edgeFade(_ width: CGFloat = 24) -> some View {
        mask {
            HStack(spacing: 0) {
                LinearGradient(colors: [.clear, .black], startPoint: .leading, endPoint: .trailing).frame(width: 8)
                Rectangle()
                LinearGradient(colors: [.black, .clear], startPoint: .leading, endPoint: .trailing).frame(width: width)
            }
        }
    }
}

/// B-4 on the closed display: the Continue game's key art in Playscribe's own frame (brand
/// README, "Closed Library hero"): no badge on game art; the frame says "this is the app".
/// The whole card is one button. In tabletop the art is display-only in the upper half.
/// The Continue hero (B-4, D-12): the first and largest thing in the Library. When the release is
/// unread it reads as a new chapter (brand v2): label, version chip and an invite back in.
struct ContinueRow: View {
    @Environment(AppModel.self) private var model
    var game: CatalogGame
    var release: Release

    var body: some View {
        let fresh = model.isUnread(release)
        Button { model.openGame(game.id, chapter: .updates, releaseID: release.id) } label: {
            VStack(alignment: .leading, spacing: 10) {
                HeroFrame(asset: game.keyArtAsset, game: game)
                ContinueText(game: game, release: release, fresh: fresh)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .frame(minHeight: 44)
        .tappableFrame()
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(fresh ? "New chapter, \(release.displayName), \(game.name)" : "Continue, \(release.displayName), \(game.name)")
        .accessibilityAddTraits(.isButton)
    }
}

struct ContinueText: View {
    var game: CatalogGame
    var release: Release
    var fresh: Bool
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 8) {
                Text(fresh ? "NEW CHAPTER" : "CONTINUE")
                    .font(PlayscribeFont.caption)
                    .tracking(12 * 0.08)
                    .foregroundStyle(PlayscribeColor.accent)
                if fresh, let v = release.versionChip {
                    Text(v)
                        .font(PlayscribeFont.caption)
                        .monospacedDigit()
                        .foregroundStyle(PlayscribeColor.accent)
                        .padding(.horizontal, 8)
                        .frame(height: 19)
                        .overlay(Capsule().strokeBorder(PlayscribeColor.accent.opacity(0.7), lineWidth: 1))
                }
            }
            Text(game.name).font(PlayscribeFont.title2).foregroundStyle(PlayscribeColor.textPrimary)
            Text(fresh ? "\(release.displayName) is here. Catch up, then jump back in." : release.displayName)
                .font(PlayscribeFont.body).foregroundStyle(PlayscribeColor.textSecondary)
        }
        .padding(.horizontal, 4)
    }
}

extension Release {
    /// "Update 1.1" → "v1.1", for the hero's version chip.
    var versionChip: String? {
        guard let token = displayName.split(separator: " ").last, token.first?.isNumber == true else { return nil }
        return "v" + token
    }
}

/// The framed key art: continuous 14 pt top corners, a bottom edge that dips 16 pt to the centre
/// like an open book's pages meeting at the spine, and a vellum hairline. Decorative.
struct HeroFrame: View {
    var asset: String?
    var game: CatalogGame?
    @Environment(\.duo) private var duo
    var body: some View {
        ArtView(asset: asset, game: game)
            // Closed: 16:9 so the library rows stay on screen; larger displays keep the taller page.
            .aspectRatio(duo.pose == .closed || duo.pose == .book ? 16 / 9 : 365 / 300, contentMode: .fit)
            .clipShape(BookEdgeShape())
            // Brand v2: an inset lit edge, 1.5 pt visible (3 pt stroke clipped to the shape).
            .overlay(BookEdgeShape().stroke(PlayscribeColor.vellum100.opacity(0.6), lineWidth: 3).clipShape(BookEdgeShape()))
            .accessibilityHidden(true)
    }
}

nonisolated struct BookEdgeShape: Shape {
    var radius: CGFloat = 14
    var dip: CGFloat = 16

    func path(in r: CGRect) -> Path {
        var p = Path()
        let bottom = r.maxY - dip
        p.move(to: CGPoint(x: r.minX, y: r.minY + radius))
        p.addQuadCurve(to: CGPoint(x: r.minX + radius, y: r.minY), control: CGPoint(x: r.minX, y: r.minY))
        p.addLine(to: CGPoint(x: r.maxX - radius, y: r.minY))
        p.addQuadCurve(to: CGPoint(x: r.maxX, y: r.minY + radius), control: CGPoint(x: r.maxX, y: r.minY))
        p.addLine(to: CGPoint(x: r.maxX, y: bottom))
        // brand/library/closed-hero.svg: controls at 77% and 23% of the width, level with the sides.
        p.addQuadCurve(to: CGPoint(x: r.midX, y: r.maxY), control: CGPoint(x: r.minX + r.width * 0.769, y: bottom))
        p.addQuadCurve(to: CGPoint(x: r.minX, y: bottom), control: CGPoint(x: r.minX + r.width * 0.231, y: bottom))
        p.closeSubpath()
        return p
    }
}

/// Closed display row (B-1): 44 pt cover, name up to two lines, status, latest On PS5 release, unread count.
struct GameRow: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dynamicTypeSize) private var typeSize
    var row: AppModel.LibraryRow

    var body: some View {
        let stacked = typeSize.isAccessibilitySize
        HStack(spacing: 0) {
            Button { model.openGame(row.id) } label: {
                let layout = stacked ? AnyLayout(VStackLayout(alignment: .leading, spacing: 8)) : AnyLayout(HStackLayout(spacing: 12))
                layout {
                    CoverView(game: row.game, cornerRadius: 6).frame(width: 44)
                    VStack(alignment: .leading, spacing: 4) {
                        Text(row.game.name).font(PlayscribeFont.headline).lineLimit(stacked ? nil : 2).multilineTextAlignment(.leading)
                        HStack(spacing: 6) {
                            StatusPill(status: row.status)
                            Text(model.shelfLine(row)).font(PlayscribeFont.footnote).foregroundStyle(.secondary)
                        }
                    }
                    if !stacked { Spacer(minLength: 0) }
                    if row.unread > 0 { UnreadBadge(count: row.unread) }
                }
                .padding(.vertical, 6)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .tappableFrame()
            .background((model.highlight == row.id || model.highlightSet.contains(row.id)) ? PlayscribeColor.accent.opacity(0.15) : .clear)
            GameMenuButton(gameID: row.id)
        }
        .accessibilityElement(children: .contain)
        .task(id: model.highlight) { await clearHighlight() }
    }

    private func clearHighlight() async {
        guard model.highlight == row.id || model.highlightSet.contains(row.id) else { return }
        try? await Task.sleep(for: .seconds(1))
        model.highlight = nil
        model.highlightSet = []
    }
}

struct UnreadBadge: View {
    var count: Int
    var body: some View {
        Text("\(count)")
            .font(PlayscribeFont.caption2.bold())
            .monospacedDigit()
            .padding(.horizontal, 6)
            .frame(minWidth: 20, minHeight: 20)
            .background(PlayscribeColor.accent, in: Capsule())
            .foregroundStyle(PlayscribeColor.onAccent)
            .accessibilityLabel("\(count) unread")
    }
}

struct GameMenuButton: View {
    @Environment(AppModel.self) private var model
    var gameID: String
    var body: some View {
        Menu { ActionMenuContent(sections: model.statusMenu(gameID)) } label: {
            Image(systemName: "ellipsis").frame(width: 44, height: 44).contentShape(Rectangle())
        }
        .accessibilityLabel("Options for \(model.game(gameID)?.name ?? "game")")
        .tappableFrame()
    }
}

/// Inner display tile: a fixed-size cover, name, a status dot and the unread count.
struct GameTile: View {
    @Environment(AppModel.self) private var model
    @Environment(\.duo) private var duo
    @Environment(\.dynamicTypeSize) private var typeSize
    var row: AppModel.LibraryRow
    var size: CGFloat

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Button { model.openGame(row.id) } label: {
                SquareCover(game: row.game, size: size)
                    .overlay(alignment: .topTrailing) {
                        if row.unread > 0 { UnreadBadge(count: row.unread).padding(4) }
                    }
                    .overlay(alignment: .bottomLeading) {
                        // D-12: the PS5-style update mark for an unread On PS5 release. V-4: else a
                        // dashed Unconfirmed chip; one mark per tile, the confirmed one wins.
                        if row.unread == 0, model.ps5Releases(row.id).first?.isUnconfirmed == true {
                            UnconfirmedChip()
                                .background(Color.black.opacity(0.55), in: Capsule())
                                .padding(5)
                        } else if let r = row.latest, model.isUnread(r) {
                            Text("Update")
                                .font(PlayscribeFont.caption2.weight(.semibold))
                                .foregroundStyle(PlayscribeColor.onAccent)
                                .padding(.horizontal, 6).padding(.vertical, 2)
                                .background(PlayscribeColor.accent, in: Capsule())
                                .padding(5)
                                .accessibilityHidden(true)
                        }
                    }
            }
            .buttonStyle(.plain)
            .contextMenu { ActionMenuContent(sections: model.statusMenu(row.id)) }
            .tappableFrame()
            // G-8: game names never truncate.
            Text(row.game.name).font(PlayscribeFont.footnote.weight(.semibold))
                .lineLimit(typeSize.isAccessibilitySize ? 4 : 3)
                .fixedSize(horizontal: false, vertical: true)
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Circle().fill(row.status.tint).frame(width: 6, height: 6)
                Text(model.tileLine(row)).font(PlayscribeFont.caption2).foregroundStyle(.secondary).lineLimit(4)
                Spacer(minLength: 0)
                // Closed tiles are too narrow for the caption and a button; the cover's menu remains.
                if duo.pose != .closed {
                    GameMenuButton(gameID: row.id).frame(width: 28).padding(.trailing, -8).padding(.vertical, -10)
                }
            }
        }
        .frame(width: size)
        .background((model.highlight == row.id || model.highlightSet.contains(row.id)) ? PlayscribeColor.accent.opacity(0.15) : .clear)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("\(row.game.name), \(row.status.label)\(row.unread > 0 ? ", \(row.unread) unread" : "")")
    }
}

/// B-4: the game with the most recent unread On PS5 release, first in the grid, with key art.
/// D-12: PS5-style square tile. Until square art exists, the portrait cover fits over a blurred
/// fill of itself.
struct SquareCover: View {
    var game: CatalogGame
    var size: CGFloat
    @State private var art: TileArtLoader.Loaded?

    var body: some View {
        let tileArt = game.tileArt
        ZStack {
            if let art {
                // Key art: a square crop centred on the salient region; a square cover as is.
                let scale = size / min(art.image.size.width, art.image.size.height)
                let width = art.image.size.width * scale
                let offset = min(0, max(size - width, size / 2 - art.centreX * width))
                Image(uiImage: art.image).resizable().interpolation(.high)
                    .frame(width: width, height: art.image.size.height * scale)
                    .offset(x: offset + (width - size) / 2)
            } else {
                CoverView(game: game, cornerRadius: 0)
                    .frame(width: size)
                    .blur(radius: 18)
                    .overlay(Color.black.opacity(0.35))
                    .accessibilityHidden(true)
                CoverView(game: game, cornerRadius: 4)
                    .frame(height: size - 12)
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(.white.opacity(0.08)))
        .accessibilityElement()
        .accessibilityLabel("\(game.name) cover")
        .accessibilityAddTraits(.isImage)
        .task(id: tileArt) {
            switch tileArt {
            case .square(let url)?: art = await TileArtLoader.shared.load(url, salient: false)
            case .keyArt(let url)?: art = await TileArtLoader.shared.load(url, salient: true)
            case nil: art = nil
            }
        }
    }
}



/// The open-flat banner: the featured game's art with the wordmark, so it reads as the app.

/// N-1: asked in context after the first game is added. One Continue button, swipe to dismiss.
struct NotificationInviteCard: View {
    @Environment(AppModel.self) private var model
    var gameName: String
    @State private var counted = false

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "bell.badge").font(PlayscribeFont.title2).foregroundStyle(PlayscribeColor.accent)
            VStack(alignment: .leading, spacing: 8) {
                Text("Get a note when \(gameName) updates on PS5").font(PlayscribeFont.headline)
                Button("Continue") {
                    model.data.notificationCardDismissed = true
                    Task { await NotificationService.shared.requestAuthorization() }
                }
                .buttonStyle(.borderedProminent).foregroundStyle(PlayscribeColor.onAccent)
                .hitTarget()
                .tappableFrame()
            }
            Spacer(minLength: 0)
        }
        .padding(16)
        .background(Color.ink2, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .gesture(DragGesture(minimumDistance: 30).onEnded { v in
            if abs(v.translation.width) > 60 { model.data.notificationCardDismissed = true }
        })
        .accessibilityAction(named: "Dismiss") { model.data.notificationCardDismissed = true }
        .onAppear {
            guard !counted else { return }
            counted = true
            model.data.notificationCardShows += 1
        }
    }
}

/// Open landscape sidebar (G-1).
