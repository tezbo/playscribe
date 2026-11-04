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
    /// The stage's bottom edge in screen space; the caption lifts to end 24 pt above the division.
    @State private var stageBottom: CGFloat = 0

    var body: some View {
        let deck = model.latestDeck
        if let card = deck.first(where: { $0.id == model.deckSelection }) ?? deck.first {
            DeckStage(card: card)
        } else {
            legacyStage
        }
    }

    @ViewBuilder private var legacyStage: some View {
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
                    if let c = model.continueItem, c.game.id == game.id {
                        Text("New on PS5: \(c.release.displayName)").font(PlayscribeFont.subheadline).foregroundStyle(.secondary)
                    }
                }
                if !model.data.collection.isEmpty {
                    Text("Nothing new in 90 days").font(PlayscribeFont.subheadline).foregroundStyle(.secondary)
                }
            }
            .padding(20)
            .padding(.bottom, duo.clearance(forBottom: stageBottom))
            .accessibilityElement(children: .combine)
            .accessibilityIdentifier("stageCaption")
        }
        .onGeometryChange(for: CGFloat.self) { $0.frame(in: .global).maxY } action: { stageBottom = $0 }
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
    /// Tabletop: first-letter filter instead of typing (the keyboard never opens there).
    @State private var letter: String?

    /// D-12: one square tile size per pose.
    private var tileSize: CGFloat {
        switch duo.pose {
        case .closed: 88
        case .flat: 112
        case .book: 100
        case .tabletop: 84
        }
    }

    /// Book: an even column count across both pages (Apple: prefer an even number of columns).
    private var columns: [GridItem] {
        if duo.pose == .closed {
            return Array(repeating: GridItem(.flexible(), spacing: 10, alignment: .top), count: 3)
        }
        if let book = bookLayout {
            // A spacer column before each page's tiles centres them on their page; the fold
            // falls in the middle spacer, never through a tile.
            let tiles = { (n: Int) in (0..<n).map { i in GridItem(.fixed(tileSize), spacing: i == n - 1 ? 0 : 10, alignment: .top) } }
            return [GridItem(.fixed(book.lead), spacing: 0)] + tiles(book.perPage) + [GridItem(.fixed(book.gap), spacing: 0)] + tiles(book.perPage)
        }
        return [GridItem(.adaptive(minimum: tileSize, maximum: tileSize + 24), spacing: 10, alignment: .top)]
    }

    /// Book (D-12): the same number of tiles on each page (Apple: prefer an even number of
    /// columns), each group centred on its page.
    private var bookLayout: (perPage: Int, lead: CGFloat, gap: CGFloat)? {
        guard duo.pose == .book, let fold = duo.division else { return nil }
        let x0: CGFloat = 16, edge = duo.size.width - railWidth - 16
        let leftPage = fold.minX - 8 - x0, rightStart = fold.maxX + 8, rightPage = edge - rightStart
        var k = max(1, Int((min(leftPage, rightPage) + 10) / (tileSize + 10)))
        while k > 1 && CGFloat(k) * tileSize + CGFloat(k - 1) * 10 > min(leftPage, rightPage) { k -= 1 }
        let group = CGFloat(k) * tileSize + CGFloat(k - 1) * 10
        // Polish 2: the left page's tiles start at the same margin as search, hero and filters.
        let lead: CGFloat = 0
        let gap = max(0, rightStart + max(0, (rightPage - group) / 2) - (x0 + lead + group))
        return (k, lead, gap)
    }

    /// Changes with the pose and the fold, so layouts that cache by position are rebuilt.
    private var poseKey: String {
        "\(duo.pose.rawValue)-\(Int(duo.division?.minX ?? -1))-\(Int(duo.division?.minY ?? -1))-\(Int(duo.size.width))"
    }

    /// QA: what this view believes (pose, fold, layout), read by FoldAuditTests next to the root audit.
    private var probe: some View {
        let mode = bookLayout.map { "book k=\($0.perPage) lead=\(Int($0.lead)) gap=\(Int($0.gap))" } ?? "grid"
        let fold = duo.division.map { "fold \(Int($0.minX))-\(Int($0.maxX))" } ?? "no fold"
        let label = "library-duo pose: \(duo.pose.rawValue); \(fold); width \(Int(duo.size.width)); rail \(Int(railWidth)); tile \(Int(tileSize)); \(mode)"
        return Text(label).font(.system(size: 1)).opacity(0.01)
            .accessibilityIdentifier("libraryDuo").accessibilityLabel(label)
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

    /// Book with 3 or more recent updates: the hero carousel takes the right page's top.
    private var heroOnRightPage: Bool {
        duo.pose == .book && duo.division != nil && model.libraryTab != .upcoming && model.latestDeck.count >= 3
    }

    /// The library search field; one page wide in Book, and reported to the fold audit.
    private func searchField(binding: Binding<String>) -> some View {
                    // The same field as the notes search; the system rounded border read as a
                    // faded box behind the large title on the dark Library (QA, a258f0c).
                    HStack(spacing: 8) {
                        Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                        TextField("Search your library", text: binding)
                            .submitLabel(.search)
                            .autocorrectionDisabled()
                    }
                    .padding(.horizontal, 12)
                    .frame(minHeight: 44)
                    .background(PlayscribeColor.ink700, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                    // Book: one page wide (like the chip row), and reported to the fold audit.
                    .frame(width: duo.pose == .book ? duo.division.map { max(0, $0.minX - 24 - 16) } : nil, alignment: .leading)
                    .tappableFrame()
                    .padding(.top, 4)
    }

    var body: some View {
        @Bindable var model = model
        let rows = duo.pose == .tabletop && letter != nil
            ? model.shownRows().filter { LetterIndex.matches($0.game.name, letter ?? "") } : model.shownRows()
        let all = model.libraryRows
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 14) {
                LibraryTabPicker()
                if model.libraryTab == .upcoming {
                    UpcomingView()
                } else {
                if let line = model.feedStatusLine {
                    HStack {
                        Text(line).font(PlayscribeFont.footnote).foregroundStyle(.secondary)
                        if case .failed = model.feedStatus {
                            Button("Retry") { Task { await model.retryCheck() } }.font(PlayscribeFont.footnote).hitTarget()
                        }
                    }
                }
                CatchUpCard()
                if model.showsNotificationCard, let first = all.first {
                    NotificationInviteCard(gameName: first.game.name)
                }
                if all.count >= 6 && duo.pose == .tabletop {
                    // Tabletop: no keyboard; a read-only button and an A to Z strip (Iris, 0.2.0 ruling).
                    TabletopSearch(letter: $letter, prompt: "Search your library").padding(.top, 4)
                } else if !heroOnRightPage, all.count >= 6 { searchField(binding: $model.data.nav.query) }
                // D-7: a narrowed list always says so and offers the way back.
                if model.nav.filter != .all && layout == .list {
                    HStack(spacing: 12) {
                        Label("Showing \(model.nav.filter.label)", systemImage: "line.3.horizontal.decrease")
                            .font(PlayscribeFont.subheadline).foregroundStyle(.secondary)
                        Button("Show all") { model.nav.filter = .all }
                            .font(PlayscribeFont.subheadline.weight(.semibold))
                            .frame(minHeight: 44)
                            .tappableFrame()
                    }
                }
                if rows.isEmpty {
                    VStack(spacing: 12) {
                        Text("No \(model.nav.filter == .all ? "" : model.nav.filter.label.lowercased() + " ")games").font(PlayscribeFont.headline)
                        Button("Show all") { model.nav.filter = .all; model.nav.query = "" }.hitTarget()
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 40)
                }
                // Book, 3 or more recent updates (Iris, hero-wide-layouts): search, news and filters stay on
                // the left page and the carousel spans the top of the RIGHT page; the tiles start below both.
                if heroOnRightPage, let fold = duo.division {
                    let rightStart = fold.maxX + 24 - 16
                    let rightWidth = max(0, duo.size.width - railWidth - 16 - (fold.maxX + 24))
                    HStack(alignment: .top, spacing: 0) {
                        VStack(alignment: .leading, spacing: 14) {
                            if all.count >= 6 { searchField(binding: $model.data.nav.query) }
                            NewsStrip().frame(maxWidth: .infinity, alignment: .leading)
                            if all.count >= 2 && layout == .tiles {
                                FilterBar().frame(maxWidth: .infinity, alignment: .leading).clipped().contentShape(Rectangle())
                            }
                        }
                        .frame(width: max(0, fold.minX - 24 - 16), alignment: .topLeading)
                        LatestUpdatesDeck(cards: model.latestDeck)
                            .frame(width: rightWidth, alignment: .leading)
                            .padding(.leading, max(0, rightStart - max(0, fold.minX - 24 - 16)))
                    }
                    .id(poseKey)
                }
                // D-12: the Continue hero spans two tiles; Tabletop shows it on the standing half.
                // Tabletop: the Continue art is the standing half; the flat half is the grid.
                // Open landscape: Continue is a double-width tile leading the grid (D-12).
                // 0.5.0 item 1: the Latest updates deck replaces the single Continue hero. Tabletop
                // shows the first card in the standing half and the page edge on this lower half.
                if duo.pose != .tabletop && !heroOnRightPage {
                    let deck = model.latestDeck
                    if !deck.isEmpty {
                        LatestUpdatesDeck(cards: deck)
                            .frame(maxWidth: duo.pose == .book ? max(0, (duo.division?.minX ?? 0) - 24) : .infinity, alignment: .leading)
                    } else if !model.data.collection.isEmpty {
                        CaughtUpCard()
                            .frame(maxWidth: duo.pose == .book ? max(0, (duo.division?.minX ?? 0) - 24) : .infinity, alignment: .leading)
                    }
                } else if duo.pose == .tabletop {
                    let deck = model.latestDeck
                    if deck.count > 1 { PageEdge(cards: deck, current: model.deckSelection ?? deck.first?.id) { model.deckSelection = $0 } }
                }
                if !heroOnRightPage { NewsStrip().frame(maxWidth: duo.pose == .book ? max(0, (duo.division?.minX ?? 0) - 24) : .infinity, alignment: .leading) }
                if !heroOnRightPage && all.count >= 2 && layout == .tiles {
                    // TT-0: in the book pose the chip row stays on the left page.
                    // TT-0: in the book pose the chip row is exactly the left page wide, clipped, so its
                    // accessibility frame never reaches the fold either.
                    Group {
                        if duo.pose == .book, let fold = duo.division {
                            FilterBar().frame(width: max(0, fold.minX - 24 - 16), alignment: .leading)
                                .clipped().contentShape(Rectangle())
                        } else {
                            FilterBar().frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                    .id(poseKey)
                }
                if layout == .list {
                    ForEach(rows) { row in GameRow(row: row).id("lib-\(row.id)") }
                } else if duo.pose == .flat && duo.isLandscape {
                    FlowLayout(spacing: 10) {
                        ForEach(rows) { row in GameTile(row: row, size: tileSize).id("lib-\(row.id)") }
                    }
                } else {
                    LazyVGrid(columns: columns, alignment: .leading, spacing: 10) {
                        ForEach(cells(rows), id: \.id) { cell in
                            if let row = cell.row {
                                GameTile(row: row, size: duo.pose == .closed ? nil : tileSize).id("lib-\(row.id)")
                            } else {
                                Color.clear.frame(height: 1).accessibilityHidden(true)
                            }
                        }
                    }
                    // A pose or fold change rebuilds the grid: lazily cached cells kept their old frames
                    // (0.2.0 gate: Book showed the open-pose grid across the fold).
                    .id(poseKey)
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
        .overlay(alignment: .topLeading) { if FoldAuditSwitch.enabled { probe.allowsHitTesting(false) } }
    }
}

extension AppModel {
    /// GR-1: one line under a game in the Library, tile or row: the newest PS5 release, else
    /// what is known about the game on PS5.
    /// The tile's shorter caption (D-12): the chip carries Unconfirmed, and the availability line
    /// drops the day.
    func tileLine(_ row: LibraryRow) -> String {
        if let r = row.latest { return "\(r.displayName), \(r.ps5Date.dayMonth)" }
        if let r = ps5Releases(row.id).first { return "\(r.displayName), announced" }
        return "\(row.game.ps5ShortLine). No notes yet"
    }

    func shelfLine(_ row: LibraryRow) -> String {
        if let r = row.latest { return "\(r.displayName), \(r.ps5Date.dayMonth)" }
        if let r = ps5Releases(row.id).first { return "\(r.displayName), announced" }
        return "\(row.game.ps5AvailabilityLine). No notes yet"
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


/// Filter pills on one line; Sort lives in the View menu (D-12).
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
                            .padding(.horizontal, 10)
                            .frame(minHeight: 44)
                            .background(on ? PlayscribeColor.accent.opacity(0.22) : Color.ink3, in: Capsule())
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(on ? .isSelected : [])
                    .tappableFrame()
                }
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
        .accessibilityLabel(fresh ? "New update, \(release.displayName), \(game.name)" : "Continue, \(release.displayName), \(game.name)")
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
                Text(fresh ? "NEW UPDATE" : "CONTINUE")
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
                .lineLimit(2).fixedSize(horizontal: false, vertical: true)
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
            .clipped()
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
            .squeezePop(id: row.id, isNew: model.highlightSet.contains(row.id))
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
/// Library tile (brand library-tiles, approved by Terry 26 Oct): a 3:4 cover with no text under
/// it. Top right, a glass status circle; bottom left, a date pill that carries the update state.
/// Long-press opens the game's actions.
struct GameTile: View {
    @Environment(AppModel.self) private var model
    var row: AppModel.LibraryRow
    /// nil: fill the column (Closed, 3 across).
    var size: CGFloat?
    /// Closed fills its column, so the cover's width is only known once laid out.
    @State private var measuredWidth: CGFloat = 0
    /// QA probe only (fold audit on): the tile's outer width, to compare with the published id.
    @State private var outerWidth: CGFloat = 0

    /// Reports the cover itself to the fold audit and publishes its width. The measure sits on the
    /// 3:4 cover, inside the column-filling wrapper: measuring the wrapper gave the column's width
    /// (181 pt), not the cover's (J-5 then read 241 pt tall tiles on a 236 pt pitch).
    private func measured(_ cover: some View) -> some View {
        cover.tappableFrame().onGeometryChange(for: CGFloat.self) { $0.size.width } action: { measuredWidth = $0 }
    }

    @ViewBuilder private func tileFrame(_ cover: some View) -> some View {
        if let size { measured(cover.frame(width: size, height: (size * 4 / 3).rounded())) }
        else { measured(cover.aspectRatio(3 / 4, contentMode: .fit)).frame(maxWidth: .infinity) }
    }

    var body: some View {
        Button { model.openGame(row.id) } label: {
            // Height from the width (3:4), so the grid's row height is the tile's (J-5). A tile
            // sized only by its overlays measured ~50 pt in a flow layout and rows overlapped.
            tileFrame(TileCover(game: row.game))
                .overlay(alignment: .topTrailing) { StatusCircle(status: row.status).padding(6) }
                .overlay(alignment: .bottomLeading) { DatePill(row: row).padding(6) }
                .background((model.highlight == row.id || model.highlightSet.contains(row.id)) ? PlayscribeColor.accent.opacity(0.3) : .clear,
                            in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
        .buttonStyle(.plain)
        .squeezePop(id: row.id, isNew: model.highlightSet.contains(row.id))
        .contextMenu { ActionMenuContent(sections: model.statusMenu(row.id)) }
        .accessibilityElement(children: .ignore)
        // The accessibility frame runs 8 pt wider than the cover; the id carries the cover's real
        // width so the frame tests measure the cover, not the element (fold audit, J-5).
        .accessibilityIdentifier("tile-\(Int((size ?? measuredWidth).rounded()))")
        .accessibilityLabel(model.tileAccessibilityLabel(row))
        .accessibilityAddTraits(.isButton)
        .accessibilityValue(FoldAuditSwitch.enabled ? "probe id=\(Int((size ?? measuredWidth).rounded())) cover=\(Int(measuredWidth.rounded())) outer=\(Int(outerWidth.rounded()))" : "")
        .onGeometryChange(for: CGFloat.self) { FoldAuditSwitch.enabled ? $0.size.width : 0 } action: { outerWidth = $0 }
    }
}

/// The cover: portrait art; else landscape art cropped with the name set in Literata at the top;
/// else the ink plate with the name. 10 pt corners and a faint inner edge.
struct TileCover: View {
    var game: CatalogGame
    var body: some View {
        Color.ink1
            .overlay {
                if game.coverAsset != nil || game.coverURL != nil {
                    CoverView(game: game, cornerRadius: 0)
                } else if let art = game.keyArtAsset {
                    Image(art).resizable().scaledToFill()
                        .overlay(alignment: .top) {
                            Text(game.name).font(PlayscribeFont.title3)
                                .multilineTextAlignment(.center).lineLimit(3).padding(8)
                                .frame(maxWidth: .infinity)
                                .background(LinearGradient(colors: [.black.opacity(0.7), .clear], startPoint: .top, endPoint: .bottom))
                        }
                } else {
                    CoverView(game: game, cornerRadius: 0)
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(.white.opacity(0.1), lineWidth: 1))
    }
}

struct StatusCircle: View {
    var status: OwnershipStatus
    var body: some View {
        Image(systemName: Self.symbol(status))
            .font(.system(size: 11, weight: .bold))
            .foregroundStyle(.white)
            .frame(width: 20, height: 20)
            .adaptiveGlass(in: Circle())
            // 20 pt so titles on art stay readable; the whole tile remains the 44 pt+ tap target.
    }
    static func symbol(_ s: OwnershipStatus) -> String {
        switch s { case .owned: "checkmark"; case .wishlist: "bookmark.fill"; case .watching: "eye.fill" }
    }
}

/// The date pill: solid ember with the spark for an unread update; glass with an ember dot for an
/// update in the last 7 days; plain glass for older; "Out <date>" when there are no updates.
struct DatePill: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dynamicTypeSize) private var typeSize
    var row: AppModel.LibraryRow
    var body: some View {
        let state = model.tileDate(row)
        HStack(spacing: 4) {
            switch state.kind {
            case .unread: SparkShape().fill(PlayscribeColor.onAccent).frame(width: 9, height: 9)
            case .recent: Circle().fill(PlayscribeColor.accent).frame(width: 6, height: 6)
            default: EmptyView()
            }
            Text(state.text)
                .font(PlayscribeFont.caption2.weight(.semibold))
                // Accessibility sizes: wrap to two lines inside the tile instead of running off it.
                .lineLimit(typeSize.isAccessibilitySize ? 2 : 1)
                .fixedSize(horizontal: !typeSize.isAccessibilitySize, vertical: true)
                .foregroundStyle(state.kind == .unread ? PlayscribeColor.onAccent : state.kind == .none ? PlayscribeColor.textSecondary : PlayscribeColor.textPrimary)
        }
        .padding(.horizontal, 7).padding(.vertical, 3)
        .background {
            if state.kind == .unread { Capsule().fill(Color(red: 1, green: 0.69, blue: 0.31)) }
            else { Capsule().fill(.clear).adaptiveGlass(in: Capsule()) }
        }
    }
}

extension AppModel {
    enum TileDateKind { case unread, recent, older, none }

    func tileDate(_ row: LibraryRow) -> (kind: TileDateKind, text: String) {
        if let r = row.latest {
            let d = r.ps5Date
            if isUnread(r) { return (.unread, Self.tileDay(d)) }
            return (d > .now.addingTimeInterval(-7 * 86400) ? .recent : .older, Self.tileDay(d))
        }
        if let d = row.game.releaseDate?.isoDay { return (.none, (d <= .now ? "Released " : "") + Self.tileDay(d)) }
        return (.none, "TBA")
    }

    /// "12 Oct" this year, "Jul 2025" before.
    static func tileDay(_ d: Date) -> String {
        Calendar.current.isDate(d, equalTo: .now, toGranularity: .year)
            ? d.dayMonth
            : d.formatted(Date.FormatStyle(locale: Locale(identifier: "en_GB")).month(.abbreviated).year())
    }

    /// "Elden Ring, last updated Jul 2025, owned".
    func tileAccessibilityLabel(_ row: LibraryRow) -> String {
        let state = tileDate(row)
        let when: String
        switch state.kind {
        case .unread: when = "new update \(state.text)"
        case .recent, .older: when = "last updated \(state.text)"
        case .none: when = state.text == "TBA" ? "release date to be announced" : state.text.lowercased().hasPrefix("released") ? state.text.lowercased() : "out \(state.text)"
        }
        return "\(row.game.name), \(when), \(row.status.label.lowercased())"
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

/// D-12, side by side: the Continue tile, two tiles wide, with key art and the new chapter.
struct ContinueTile: View {
    @Environment(AppModel.self) private var model
    var game: CatalogGame
    var release: Release
    var size: CGFloat

    var body: some View {
        let fresh = model.isUnread(release)
        Button { model.openGame(game.id, chapter: .updates, releaseID: release.id) } label: {
            // A fixed-size clear base with the art as an overlay: the art is proposed exactly the
            // card's size and cannot widen the label (it once reported x -97.7, width 461).
            Color.clear
                .frame(width: size * 2 + 10, height: (size * 4 / 3).rounded())
                .overlay { ArtView(asset: game.keyArtAsset, game: game) }
                .clipped()
                .overlay {
                    LinearGradient(colors: [.clear, .black.opacity(0.8)], startPoint: .center, endPoint: .bottom)
                }
                .overlay(alignment: .bottomLeading) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(fresh ? "NEW UPDATE" : "CONTINUE").font(PlayscribeFont.caption2).tracking(1).foregroundStyle(PlayscribeColor.accent)
                        Text(game.name).font(PlayscribeFont.subheadline.weight(.semibold)).lineLimit(2)
                        Text(release.displayName).font(PlayscribeFont.caption).foregroundStyle(.secondary)
                    }
                    .padding(10)
                }
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(.white.opacity(0.1), lineWidth: 1))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        // The accessibility element is the card-sized container, not the button's label content.
        .frame(width: size * 2 + 10, height: (size * 4 / 3).rounded())
        .clipped()
        .accessibilityElement(children: .ignore)
        .accessibilityIdentifier("continueHero")
        .accessibilityLabel(fresh ? "New update, \(release.displayName), \(game.name)" : "Continue, \(release.displayName), \(game.name)")
        .accessibilityAddTraits(.isButton)
        .tappableFrame()
    }
}

/// Lays children left to right, wrapping, each at its own size.
struct FlowLayout: Layout {
    var spacing: CGFloat = 14
    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        place(proposal.width ?? .infinity, subviews).size
    }
    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        for (i, p) in place(bounds.width, subviews).points.enumerated() {
            let size = subviews[i].sizeThatFits(.unspecified)
            subviews[i].place(at: CGPoint(x: bounds.minX + p.x, y: bounds.minY + p.y), proposal: ProposedViewSize(size))
        }
    }
    private func place(_ width: CGFloat, _ subviews: Subviews) -> (points: [CGPoint], size: CGSize) {
        var points: [CGPoint] = [], x: CGFloat = 0, y: CGFloat = 0, row: CGFloat = 0, maxX: CGFloat = 0
        for v in subviews {
            let s = v.sizeThatFits(.unspecified)
            if x > 0 && x + s.width > width { x = 0; y += row + spacing; row = 0 }
            points.append(CGPoint(x: x, y: y))
            x += s.width + spacing; row = max(row, s.height); maxX = max(maxX, x - spacing)
        }
        return (points, CGSize(width: maxX, height: y + row))
    }
}

/// A newly added game squeeze-pops into the library (handoff/0.5.0-scan-haptics.md, Add pop):
/// 0.6 scale and clear, spring to size, opacity easeOut 0.15 s, 70 ms stagger capped at 8 tiles,
/// a 3 pt ember ring that fades in 0.3 s, one light impact. Reduce Motion: a 0.2 s fade only.
private struct SqueezePop: ViewModifier {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(AppModel.self) private var model
    var id: String
    @State private var settled: Bool
    @State private var ring: Bool

    init(id: String, isNew: Bool) { self.id = id; _settled = State(initialValue: !isNew); _ring = State(initialValue: false) }

    func body(content: Content) -> some View {
        content
            .overlay {
                if !reduceMotion {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .strokeBorder(PlayscribeColor.accent, lineWidth: 3)
                        .opacity(ring ? 1 : 0)
                        .allowsHitTesting(false)
                        .accessibilityHidden(true)
                }
            }
            .scaleEffect(reduceMotion || settled ? 1 : 0.6)
            .opacity(settled ? 1 : 0)
            .onAppear {
                guard !settled else { return }
                let i = min(model.addedOrder.firstIndex(of: id) ?? 0, 7)
                let delay = Double(i) * 0.07
                if reduceMotion {
                    withAnimation(.easeInOut(duration: 0.2).delay(delay)) { settled = true }
                    return
                }
                withAnimation(.spring(response: 0.38, dampingFraction: 0.58).delay(delay)) { settled = true }
                ring = true
                withAnimation(.easeOut(duration: 0.3).delay(delay + 0.05)) { ring = false }
                if i < 4 {
                    Task {
                        try? await Task.sleep(for: .seconds(delay + 0.12))
                        Haptics.pop(first: i == 0)
                    }
                }
            }
    }
}

extension View {
    func squeezePop(id: String, isNew: Bool) -> some View { modifier(SqueezePop(id: id, isNew: isNew)) }
}
