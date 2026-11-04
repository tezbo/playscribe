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
            // Add trails, Settings leads: the system collapsed a second trailing item away in Closed and
            // Open (0.5.0 Mac stills, TB-1), so the cog sits in its own region and is always drawn.
            ToolbarItem(placement: .topBarTrailing) {
                Button { model.addSheetOpen = true } label: { Label("Add game", systemImage: "plus") }
                    .disabled(model.addSheetOpen)
            }
            ToolbarItem(placement: .topBarLeading) {
                Button { model.settingsOpen = true } label: { Label("Settings", systemImage: "gearshape") }
                    .accessibilityIdentifier("settingsButton")
                    .disabled(model.settingsOpen)
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
    @Environment(\.dynamicTypeSize) private var typeSize
    @AppStorage(LibraryLayout.key) private var layout: LibraryLayout = .tiles
    /// Tabletop: first-letter filter instead of typing (the keyboard never opens there).
    @State private var letter: String?

    /// D-12: one square tile size per pose.
    private var tileSize: CGFloat {
        switch duo.pose {
        case .closed: 88
        case .flat: flatFit.size
        case .book: 100
        case .tabletop: 84
        }
    }

    /// Open (flat), 0.2.0 gate: the column count comes from the container width (tiles at least 124 pt,
    /// 10 pt gaps) and the leftover is spread equally, so the grid fills the width between the 16 pt
    /// margins with no dead space on the trailing side.
    private var flatFit: (count: Int, size: CGFloat) {
        let width = max(0, duo.size.width - railWidth - 32)
        let n = max(2, Int((width + 10) / (124 + 10)))
        // Rounded down to the hundredth so n tiles and n - 1 gaps never exceed the width.
        return (n, (((width - CGFloat(n - 1) * 10) / CGFloat(n)) * 100).rounded(.down) / 100)
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
        if duo.pose == .flat {
            return Array(repeating: GridItem(.fixed(flatFit.size), spacing: 10, alignment: .top), count: flatFit.count)
        }
        return [GridItem(.adaptive(minimum: tileSize, maximum: tileSize + 24), spacing: 10, alignment: .top)]
    }

    /// Columns that fill a Book page: at least 124 pt tiles, 10 pt gaps, the leftover shared equally.
    static func pageFit(width: CGFloat) -> (count: Int, size: CGFloat) {
        let n = max(2, Int((width + 10) / 134))
        return (n, (((width - CGFloat(n - 1) * 10) / CGFloat(n)) * 100).rounded(.down) / 100)
    }

    /// One Book page's tiles, top to bottom, on that page's own columns.
    private func pageGrid(_ rows: [AppModel.LibraryRow], fit: (count: Int, size: CGFloat)) -> some View {
        LazyVGrid(columns: Array(repeating: GridItem(.fixed(fit.size), spacing: 10, alignment: .top), count: fit.count),
                  alignment: .leading, spacing: 10) {
            ForEach(rows) { row in GameTile(row: row, size: fit.size).id("lib-\(row.id)") }
        }
        .padding(.top, 2)
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
        let label = "library-duo pose: \(duo.pose.rawValue); \(fold); width \(Int(duo.size.width)); rail \(Int(railWidth)); tile \(Int(tileSize)); \(mode); route \(model.qaRoute ?? "none"); hero \(model.continueItem?.release.id ?? "none")"
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

    /// Closed landscape (container wider than tall): the compact first screen.
    private var closedWide: Bool { duo.pose == .closed && duo.isLandscape }

    /// Book with any recent update: the hero carousel takes the right page's top; the left page keeps the controls, chips and grid.
    private var heroOnRightPage: Bool {
        duo.pose == .book && duo.division != nil && model.libraryTab != .upcoming && !model.latestDeck.isEmpty
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
                    .padding(.vertical, typeSize.isAccessibilitySize ? 12 : 0)
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
            VStack(alignment: .leading, spacing: 14) {
                // Book: the control stays on the left page; it never crosses the fold (Iris, hero-wide-layouts).
                if closedWide {
                    // Closed landscape: the control and the search field share one row, 44 pt each (Iris, cf6c889).
                    HStack(spacing: 12) {
                        LibraryTabPicker().frame(width: 220, height: 44)
                        if model.libraryTab == .playing && !all.isEmpty { searchField(binding: $model.data.nav.query) }
                    }
                } else if !heroOnRightPage {
                    LibraryTabPicker()
                        .frame(width: duo.pose == .book ? duo.division.map { max(0, $0.minX - 24 - 16) } : nil, alignment: .leading)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                if model.libraryTab == .upcoming {
                    UpcomingView()
                } else {
                if let line = model.feedStatusLine {
                    HStack {
                        Text(line).font(PlayscribeFont.footnote).foregroundStyle(.secondary)
                        if case .failed = model.feedStatus {
                            Button { Task { await model.retryCheck() } } label: { Text("Retry").frame(minWidth: 44, minHeight: 44).contentShape(Rectangle()) }.font(PlayscribeFont.footnote)
                        }
                    }
                }
                CatchUpCard()
                PlusCard()
                if model.showsNotificationCard, let first = all.first {
                    NotificationInviteCard(gameName: first.game.name)
                }
                if !all.isEmpty && duo.pose == .tabletop {
                    // Tabletop: no keyboard; a read-only button and an A to Z strip (Iris, 0.2.0 ruling).
                    TabletopSearch(letter: $letter, prompt: "Search your library").padding(.top, 4)
                } else if !heroOnRightPage, !closedWide, !all.isEmpty { searchField(binding: $model.data.nav.query) }
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
                // Book, any recent update (Iris, hero-wide-layouts): search, news and filters stay on
                // the left page and the carousel spans the top of the RIGHT page; the tiles start below both.
                if heroOnRightPage, let fold = duo.division {
                    let leftWidth = max(0, fold.minX - 24 - 16)
                    let rightStart = fold.maxX + 24 - 16
                    let rightWidth = max(0, duo.size.width - railWidth - 16 - (fold.maxX + 24))
                    // Each page flows on its own (Iris, cf6c889): the left tiles start 16 pt under the filters, the
                    // right tiles under the deck; order is the left page top to bottom, then the right page. The
                    // tiles share each page's width equally (min 124 pt, 10 pt gaps).
                    let left = Self.pageFit(width: leftWidth), right = Self.pageFit(width: rightWidth)
                    let leftCount = layout == .tiles
                        ? min(rows.count, Int((Double(rows.count) * Double(left.count) / Double(left.count + right.count)).rounded(.up))) : 0
                    HStack(alignment: .top, spacing: 0) {
                        VStack(alignment: .leading, spacing: 14) {
                            LibraryTabPicker()
                            if !all.isEmpty { searchField(binding: $model.data.nav.query) }
                            NewsStrip().frame(maxWidth: .infinity, alignment: .leading)
                            if all.count >= 2 && layout == .tiles {
                                FilterBar().frame(maxWidth: .infinity, alignment: .leading).clipped().contentShape(Rectangle())
                            }
                            if layout == .tiles { pageGrid(Array(rows.prefix(leftCount)), fit: left) }
                        }
                        .frame(width: leftWidth, alignment: .topLeading)
                        VStack(alignment: .leading, spacing: 14) {
                            // 16:9 art at the page's width plus the page edge, sized explicitly: left to the pager the
                            // card came out as tall as the screen and pushed the grid off (834a5eb).
                            LatestUpdatesDeck(cards: model.latestDeck, compact: true, maxHeight: (rightWidth * 9 / 16).rounded() + 52)
                            if layout == .tiles { pageGrid(Array(rows.dropFirst(leftCount)), fit: right) }
                        }
                        .frame(width: rightWidth, alignment: .topLeading)
                        .padding(.leading, max(0, rightStart - leftWidth))
                    }
                    .id(poseKey)
                }
                // D-12: the Continue hero spans two tiles; Tabletop shows it on the standing half.
                // Tabletop: the Continue art is the standing half; the flat half is the grid.
                // Open landscape: Continue is a double-width tile leading the grid (D-12).
                // 0.5.0 item 1: the Latest updates deck replaces the single Continue hero. Tabletop
                // shows the first card in the standing half and the page edge on this lower half.
                if duo.pose == .flat && !duo.isLandscape && !model.latestDeck.isEmpty {
                    // Open portrait (Iris, 0.5.0): the deck on the left at the 0.2.0 hero's width, the Also new
                    // panel on the right at the same height, listing every update but the deck's front card.
                    let deck = model.latestDeck
                    let front = deck.first { $0.id == model.deckSelection } ?? deck.first
                    let deckHeight = (duo.size.height * 0.38).rounded()
                    if typeSize.isAccessibilitySize {
                        // Accessibility sizes (Iris): the deck full width, Also new below it as a list.
                        VStack(alignment: .leading, spacing: 14) {
                            // Taller than the 38% side-by-side deck: the title needs up to 4 lines at AX3 (no ellipsis).
                            LatestUpdatesDeck(cards: deck, compact: true, maxHeight: (duo.size.height * 0.46).rounded())
                            AlsoNewPanel(hero: front?.release).frame(height: 460)
                        }
                        .id(poseKey)
                    } else {
                    HStack(alignment: .top, spacing: 10) {
                        LatestUpdatesDeck(cards: deck, compact: true, maxHeight: deckHeight)
                            .frame(width: max(0, (duo.size.width - railWidth - 32 - 10) * 0.46), alignment: .leading)
                        AlsoNewPanel(hero: front?.release)
                            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                    }
                    .frame(height: deckHeight)
                    .id(poseKey)
                    }
                } else if duo.pose != .tabletop && !heroOnRightPage {
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
                } else if heroOnRightPage {
                    EmptyView()   // the two page grids above carry the tiles
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
        .overlay(alignment: .topLeading) {
            if FoldAuditSwitch.enabled {
                ZStack {
                    probe
                    if let r = model.qaRoute {
                        Text("qa-route-\(r)").font(.system(size: 1)).opacity(0.01).accessibilityIdentifier("qa-route-\(r)")
                    }
                }
                .allowsHitTesting(false)
            }
        }
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
        } label: {
            Label("View", systemImage: model.nav.filter == .all ? layout.symbol : "line.3.horizontal.decrease.circle.fill")
        }
        .accessibilityShowsLargeContentViewer()
    }
}


/// Filter pills on one line; Sort lives in the View menu (D-12).
struct FilterBar: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dynamicTypeSize) private var typeSize

    private func chip(_ f: LibraryFilter, rows: [AppModel.LibraryRow]) -> some View {
        let n = f.status.map { s in rows.filter { $0.status == s }.count } ?? rows.count
        let on = model.nav.filter == f
        return Button { model.nav.filter = f } label: {
            Text("\(f.label) \(n)")
                .font(PlayscribeFont.subheadline.weight(on ? .semibold : .regular))
                // Never cut mid-glyph: one unbroken line in the scrolling row, two at accessibility sizes.
                .lineLimit(typeSize.isAccessibilitySize ? 2 : 1)
                .fixedSize(horizontal: !typeSize.isAccessibilitySize, vertical: true)
                .padding(.horizontal, 10)
                .padding(.vertical, typeSize.isAccessibilitySize ? 6 : 0)
                .frame(maxWidth: typeSize.isAccessibilitySize ? .infinity : nil, minHeight: 44)
                .background(on ? PlayscribeColor.accent.opacity(0.22) : Color.ink3, in: Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(on ? .isSelected : [])
        .tappableFrame()
    }

    var body: some View {
        let rows = model.libraryRows
        if typeSize.isAccessibilitySize {
            // Accessibility sizes: one chip per row at the full column width, so "Watching 1" stays on one line
            // inside its pill and tap frame (Closed AX3, 382 pt); a row grows if it must wrap.
            LazyVGrid(columns: [GridItem(.flexible())], spacing: 8) {
                ForEach(LibraryFilter.allCases) { f in chip(f, rows: rows) }
            }
        } else {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(LibraryFilter.allCases) { f in chip(f, rows: rows) }
                }
                .padding(.trailing, 24)
            }
            .edgeFade(40)
        }
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
            // Iris: the caption's last line sat 2 pt from the hero frame's bottom edge.
            .padding(.bottom, 8)
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

/// Open portrait: the space beside the hero. The next three most recent updates across the library
/// (not the hero's game), each opening that update; with none, the hero update's top three changes.
struct AlsoNewPanel: View {
    @Environment(AppModel.self) private var model
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var typeSize
    /// The deck's front card's update: left out of the list, and the "What's new" source when it is alone.
    var hero: Release?

    private var others: [Release] { model.alsoNewReleases(excludingRelease: hero?.id) }

    private var changes: [String] {
        guard let hero else { return [] }
        let key = (hero.keyChanges ?? []).filter { !$0.isEmpty }
        if !key.isEmpty { return Array(key.prefix(5)) }
        return Array(hero.notes.flatMap { $0.items.filter { $0.spoiler != true }.map(\.text) }.prefix(5))
    }

    private static let age: RelativeDateTimeFormatter = {
        let f = RelativeDateTimeFormatter(); f.unitsStyle = .full; return f
    }()

    var body: some View {
        let all = others
        GeometryReader { geo in
            // Iris's fill rule: 72 pt rows (3 to 6, what fits), grown evenly to 96 pt when 24 pt or more
            // is spare, a heading block above and a pinned 56 pt footer below.
            // Top padding 12, heading 26 + 12 to the first row, footer 56: the whole stack fits the panel exactly.
            let headingH: CGFloat = typeSize.isAccessibilitySize ? 44 : 26
            let avail = max(0, geo.size.height - 12 - (headingH + 12) - 56)
            // Accessibility sizes (0.5.0 a11y): rows grow to 2-line names, so fewer fit (never a clipped row).
            let unit: CGFloat = typeSize.isAccessibilitySize ? 104 : 72
            let fit = min(6, max(typeSize.isAccessibilitySize ? 1 : 3, Int(avail / unit)))
            let rows = Array(all.prefix(fit))
            let spare = avail - CGFloat(rows.count) * unit
            // Three rows are the floor: when they do not quite fit, they give up a few points each (never below 64).
            let rowHeight: CGFloat = rows.isEmpty ? unit : spare < 0 ? max(typeSize.isAccessibilitySize ? 88 : 64, avail / CGFloat(rows.count))
                : spare <= 24 ? unit : min(unit + 24, unit + spare / CGFloat(rows.count))
            VStack(alignment: .leading, spacing: 0) {
                Text(all.isEmpty ? "What's new" : "Also new").font(PlayscribeFont.title3.weight(.bold))
                    .accessibilityAddTraits(.isHeader)
                    .frame(minHeight: headingH, alignment: .topLeading)
                    .padding(.bottom, 12)
                if all.isEmpty {
                    whatsNew(lines: shownChanges(width: geo.size.width - 24, available: avail), available: avail, width: geo.size.width - 24)
                } else {
                    ForEach(rows) { r in row(r, height: rowHeight).transition(.opacity) }
                }
                Spacer(minLength: 0)
                if all.isEmpty {
                    // Iris: a 56 pt row pinned to the bottom, so the panel never ends half empty.
                    Button { if let hero { model.openGame(hero.gameID, chapter: .updates, releaseID: hero.id) } } label: {
                        HStack {
                            Text("Read the full update").font(PlayscribeFont.subheadline.weight(.semibold))
                            Spacer(minLength: 0)
                            Image(systemName: "chevron.right").font(PlayscribeFont.caption).accessibilityHidden(true)
                        }
                        .foregroundStyle(PlayscribeColor.accent)
                        .frame(maxWidth: .infinity, minHeight: 56, alignment: .center)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .tappableFrame()
                } else {
                    Button { model.nav.tab = .updates } label: {
                        Text("See all updates").font(PlayscribeFont.subheadline.weight(.semibold))
                            .foregroundStyle(PlayscribeColor.accent)
                            .frame(maxWidth: .infinity, minHeight: 56, alignment: .center)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .tappableFrame()
                }
            }
            .padding(.horizontal, 12)
            .padding(.top, 12)
            .frame(width: geo.size.width, height: geo.size.height, alignment: .topLeading)
            // Paging the deck swaps one row for another: a 200 ms cross fade, none under Reduce Motion.
            .animation(reduceMotion ? nil : .easeInOut(duration: 0.2), value: all.map(\.id))
        }
        .background(PlayscribeColor.ink700, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .accessibilityElement(children: .contain)
        .accessibilityLabel(all.isEmpty ? "What's new" : "Also new, \(min(all.count, 6)) updates")
    }

    /// Estimated height of one change line at 17 pt: up to three lines of 22 pt plus 16 pt around it.
    private func estimate(_ line: String, width: CGFloat) -> CGFloat {
        let perLine = max(12, width / 8.6)
        let n = min(3, max(1, Int((Double(line.count) / Double(perLine)).rounded(.up))))
        return CGFloat(n) * 22 + 16 + 1
    }

    /// Iris: the top 3 to 5 change lines, as many as fit above the footer.
    private func shownChanges(width: CGFloat, available: CGFloat) -> [String] {
        var used: CGFloat = 0, out: [String] = []
        for line in changes.prefix(5) {
            let h = estimate(line, width: width)
            if out.count >= 3 && used + h > available { break }
            out.append(line); used += h
        }
        return out
    }

    /// No ellipsis mid-sentence: each line wraps to up to three lines. Hairlines between, no bullets.
    private func whatsNew(lines: [String], available: CGFloat, width: CGFloat) -> some View {
        let used = lines.reduce(CGFloat(0)) { $0 + estimate($1, width: width) }
        // Spare height goes to line spacing, up to 24 pt between lines, then to the footer.
        let extra = lines.isEmpty ? 0 : min(4, max(0, (available - used) / CGFloat(lines.count * 2)))
        return VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(lines.enumerated()), id: \.offset) { i, line in
                if i > 0 { Rectangle().fill(PlayscribeColor.textPrimary.opacity(0.14)).frame(height: 1) }
                Text(line).font(PlayscribeFont.body).lineLimit(3)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 8 + extra)
            }
        }
    }

    private func row(_ r: Release, height: CGFloat) -> some View {
        let game = model.game(r.gameID)
        let age = Self.age.localizedString(for: r.ps5Date, relativeTo: .now)
        return Button { model.openGame(r.gameID, chapter: .updates, releaseID: r.id) } label: {
            HStack(spacing: 10) {
                if let g = game { CoverView(game: g, cornerRadius: 4).frame(width: 48) }
                VStack(alignment: .leading, spacing: 1) {
                    // Game names never truncate below two lines (0.5.0 a11y).
                    Text(game?.name ?? "").font(PlayscribeFont.headline).lineLimit(2)
                    Text("\(r.displayName), \(age)").font(PlayscribeFont.caption).foregroundStyle(.secondary)
                        .lineLimit(2).minimumScaleFactor(0.85)
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.right").font(PlayscribeFont.caption).foregroundStyle(.secondary).accessibilityHidden(true)
            }
            .frame(minHeight: height)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .tappableFrame()
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(game?.name ?? ""), \(r.displayName), \(age), opens update")
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
            // Open portrait, 0.2.0 gate: the whole hero card (art plus caption) is at most 38% of the
            // container height, the art cropped to fill, so search, filters and tiles show on the first screen.
            .frame(maxHeight: duo.pose == .flat ? max(160, duo.size.height * 0.38 - 76) : .infinity)
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
        // Accessibility sizes: the pill would cover the art, so it is hidden; the date stays in the label
        // and on the game page (Iris, 0.5.0 a11y).
        if !typeSize.isAccessibilitySize {
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
}

extension AppModel {
    enum TileDateKind { case unread, recent, older, none }

    func tileDate(_ row: LibraryRow) -> (kind: TileDateKind, text: String) {
        if let r = row.latest {
            let d = r.ps5Date
            if isUnread(r) { return (.unread, Self.tileDay(d)) }
            return (d > .now.addingTimeInterval(-7 * 86400) ? .recent : .older, Self.tileDay(d))
        }
        if let d = row.game.releaseDate?.isoDay { return (.none, Self.tileDay(d)) }
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
        case .none:
            // The pill is the short form; VoiceOver gets the full words (Iris, 6589abf).
            if state.text == "TBA" { when = "release date to be announced" }
            else if let d = row.game.releaseDate?.isoDay, d <= .now { when = "released \(state.text)" }
            else { when = "expected \(state.text)" }
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
