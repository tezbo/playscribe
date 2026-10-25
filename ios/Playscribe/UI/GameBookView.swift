import SwiftUI

/// The game book. On the inner display it is an ArrangementView with the overlay style: the
/// reading panel is the primary view and the artwork the secondary one. Flat, reading floats over
/// the art; folded, the system puts reading in the trailing (book) or lower (tabletop) region.
struct GameBookView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.duo) private var duo
    @Environment(\.inSplitDetail) private var inSplitDetail
    var gameID: String
    @State private var headerVisible = true

    var body: some View {
        let game = model.game(gameID)
        Group {
            if duo.pose == .closed || inSplitDetail {
                ReadingPanel(gameID: gameID, compact: true, headerVisible: $headerVisible)
            } else if duo.pose == .tabletop && model.nav.chapter == .updates {
                // TT-2: the Reader. One section on the standing half, its controls on the flat half.
                ArrangementView {
                    TabletopReaderControls(gameID: gameID)
                } secondary: {
                    TabletopReaderStage(gameID: gameID)
                        .allowsHitTesting(false)
                }
                .arrangementViewStyle(.overlay)
            } else {
                ArrangementView {
                    ReadingPanel(gameID: gameID, compact: false, headerVisible: $headerVisible)
                        .overlayArrangementEdge(.trailing)
                } secondary: {
                    BookSecondary(gameID: gameID)
                        .allowsHitTesting(duo.pose != .tabletop)
                }
                .arrangementViewStyle(.overlay)
            }
        }
        .overlay {
            // GR-4: in-book note search, scoped to this game by default.
            if model.noteQuery.count >= 2 {
                NoteSearchResults(query: model.noteQuery, scope: model.noteScope, gameID: gameID) { model.noteScope = .allGames }
            }
        }
        .searchable(text: Binding(get: { model.noteQuery }, set: { model.noteQuery = $0 }),
                    prompt: "Search \(game.map(Self.shortName) ?? "")'s notes")
        .searchScopes(Binding(get: { model.noteScope }, set: { model.noteScope = $0 })) {
            ForEach(NoteScope.allCases, id: \.self) { Text($0.label).tag($0) }
        }
        .searchSuggestions {
            ForEach(model.recentSearches, id: \.self) { Text($0).searchCompletion($0) }
        }
        .onSubmit(of: .search) { model.rememberSearch(model.noteQuery) }
        .background(Color.ink0)
        // The large header carries the name; the bar shows it once the header scrolls away.
        .navigationTitle(headerVisible ? "" : (game?.name ?? ""))
        .toolbarTitleDisplayMode(.inline)
        .toolbar { ActionToolbar(actions: model.gameActions(gameID)) }
        .onAppear { model.nav.lastGameID = gameID }
    }
}

extension GameBookView {
    /// "Dawnwalker" for "The Blood of Dawnwalker": the last word of a long name, for placeholders.
    static func shortName(_ g: CatalogGame) -> String {
        let words = g.name.split(separator: " ")
        guard words.count > 2 else { return g.name }
        return words.last.map(String.init)?.trimmingCharacters(in: .punctuationCharacters) ?? g.name
    }
}

/// The artwork side: backdrop and, where it can be touched, the chapter's contents (the folio).
/// In tabletop it is a view-only stage with the release's name (R-10).
struct BookSecondary: View {
    @Environment(AppModel.self) private var model
    @Environment(\.duo) private var duo
    var gameID: String

    var body: some View {
        let chapter = model.nav.chapter
        let tall = !duo.isFolded && duo.size.height > duo.size.width
        ZStack(alignment: .bottomLeading) {
            ArtView(asset: model.backdrop(gameID, chapter: chapter, tall: tall), game: model.game(gameID), drift: true)
                .ignoresSafeArea()
            LinearGradient(colors: [.black.opacity(0.1), .black.opacity(0.65)], startPoint: .top, endPoint: .bottom)
                .ignoresSafeArea()
            if duo.pose == .tabletop {
                TabletopStageTitle(gameID: gameID).padding(20)
            } else {
                Folio(gameID: gameID, chapter: chapter)
                    .padding(20)
                    .frame(maxWidth: 360, maxHeight: .infinity, alignment: duo.isFolded ? .bottomLeading : .topLeading)
            }
        }
    }
}

struct TabletopStageTitle: View {
    @Environment(AppModel.self) private var model
    var gameID: String
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(model.game(gameID)?.name ?? "").font(PlayscribeFont.title2.bold())
            if let r = model.ps5Releases(gameID).first {
                Text(r.displayName).font(PlayscribeFont.headline).foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// The left page: a table of contents for the open chapter. It moves the reading panel (R-9).
struct Folio: View {
    @Environment(AppModel.self) private var model
    var gameID: String
    var chapter: Chapter

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(chapter.title.uppercased()).font(PlayscribeFont.caption2.weight(.semibold)).foregroundStyle(.secondary)
            Text(model.game(gameID)?.name ?? "").font(PlayscribeFont.title3.bold())
            ForEach(items, id: \.id) { item in
                Button(action: item.action) {
                    HStack(spacing: 8) {
                        if item.unread { UnreadDot() } else { Capsule().fill(.secondary).frame(width: 8, height: 2) }
                        Text(item.label).font(PlayscribeFont.subheadline.weight(.medium))
                        Spacer(minLength: 8)
                        Text(item.sub).font(PlayscribeFont.caption).foregroundStyle(.secondary)
                    }
                    .frame(minHeight: 44)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .tappableFrame()
            }
        }
        .padding(16)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private struct Item { var id: String; var label: String; var sub: String; var unread: Bool; var action: () -> Void }

    private var items: [Item] {
        let key = AppModel.bookKey(gameID, chapter)
        switch chapter {
        case .updates:
            return model.ps5Releases(gameID).prefix(6).map { r in
                Item(id: r.id, label: r.displayName, sub: r.ps5Date.dayMonth, unread: model.isUnread(r)) {
                    model.openGame(gameID, chapter: .updates, releaseID: r.id)
                }
            }
        case .world, .companion:
            let entries = model.fixtures.book.filter { $0.gameID == gameID && $0.chapter.rawValue == chapter.rawValue }
            var seen: [String] = []
            for e in entries where !seen.contains(e.section) { seen.append(e.section) }
            return seen.map { sec in
                Item(id: sec, label: sec, sub: "\(entries.filter { $0.section == sec }.count) entries", unread: false) {
                    model.nav.anchors[key] = "sec-\(sec)"
                }
            }
        case .mybook:
            return [
                Item(id: "bm", label: "Bookmarks", sub: "\(model.data.bookmarks.filter { $0.gameID == gameID }.count)", unread: false) { model.nav.anchors[key] = "mybook-marks" },
                Item(id: "nt", label: "Notes", sub: "\(model.data.notes.filter { $0.gameID == gameID }.count)", unread: false) { model.nav.anchors[key] = "mybook-notes" },
            ]
        case .gallery:
            return []
        }
    }
}

/// The reading side: header, chapters and the open chapter.
struct ReadingPanel: View {
    @Environment(AppModel.self) private var model
    @Environment(\.duo) private var duo
    @Environment(\.railWidth) private var railWidth
    var gameID: String
    var compact: Bool
    @Binding var headerVisible: Bool
    /// The Spread's Page: no hero (the art is above it) and no floating-card frame.
    var spreadPage = false
    @State private var position = ScrollPosition(idType: String.self)

    var body: some View {
        let chapter = model.chapters(gameID).contains(model.nav.chapter) ? model.nav.chapter : .updates
        let key = AppModel.bookKey(gameID, chapter)
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                if compact { CompactHero(gameID: gameID) }
                header.id("top")
                    .onScrollVisibilityChange(threshold: 0.2) { headerVisible = $0 }
                ChapterBar(gameID: gameID, selected: chapter)
                if duo.pose == .tabletop, chapter == .updates { ReleaseJumpChips(gameID: gameID) }
                switch chapter {
                case .updates: JournalView(gameID: gameID)
                case .world, .companion: EntriesChapter(gameID: gameID, chapter: chapter)
                case .gallery: GalleryChapter(gameID: gameID)
                case .mybook: MyBookChapter(gameID: gameID)
                }
            }
            .scrollTargetLayout()
            .padding(.horizontal, compact ? 16 : 20)
            .padding(.vertical, 16)
            .padding(.trailing, spreadPage ? 0 : railWidth)
        }
        // R-1 / N-6: a deep link or jump brings its release header to the top, including on a
        // cold launch, where rows inside the journal are not direct scroll targets.
        .task(id: model.focusToken) {
            guard let target = model.focusReleaseID.map({ "rel-\($0)" }) ?? model.nav.anchors[key] else { return }
            // Twice: once laid out, and again after the expanded release has measured its notes.
            for delay in [300, 700] {
                try? await Task.sleep(for: .milliseconds(delay))
                position.scrollTo(id: target, anchor: .top)
            }
        }
        .scrollPosition($position, anchor: .top)
        .background(panelBackground)
        .foldAudited()
        .modifier(FlatCard(enabled: !compact && !duo.isFolded && !spreadPage, landscape: duo.isLandscape))
    }

    @ViewBuilder private var panelBackground: some View {
        if spreadPage { Color.clear } else if compact || duo.isFolded { Color.ink1.ignoresSafeArea() } else { Rectangle().fill(.regularMaterial) }
    }

    private var header: some View {
        let game = model.game(gameID)
        return VStack(alignment: .leading, spacing: 6) {
            // In the Spread the title is on the art (O-2); the Page doesn't repeat it.
            if !spreadPage { Text(game?.name ?? "").font(PlayscribeFont.title.bold()) }
            HStack(spacing: 8) {
                if let e = model.entry(gameID) { StatusPill(status: e.status) }
                if let dev = game?.developer { Text(dev).font(PlayscribeFont.subheadline).foregroundStyle(.secondary) }
            }
            if model.entry(gameID) == nil, let game {
                // N-9: a game book outside the library is readable, with Add to library.
                Button("Add to library") { model.addGame(game, status: .watching) }
                    .buttonStyle(.borderedProminent).foregroundStyle(PlayscribeColor.onAccent)
                    .hitTarget()
            }
        }
    }
}

/// Flat inner display: the reading panel is a card over the artwork, trailing in landscape and
/// along the bottom in portrait. Folded, the arrangement gives it a whole region.
struct FlatCard: ViewModifier {
    var enabled: Bool
    var landscape: Bool
    func body(content: Content) -> some View {
        if enabled {
            GeometryReader { geo in
                content
                    .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
                    .frame(width: landscape ? min(600, max(360, geo.size.width * 0.58)) : geo.size.width - 32,
                           height: landscape ? geo.size.height - 32 : max(320, geo.size.height * 0.6))
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: landscape ? .trailing : .bottom)
                    .padding(16)
            }
        } else {
            content
        }
    }
}

struct CompactHero: View {
    @Environment(AppModel.self) private var model
    var gameID: String
    var body: some View {
        ArtView(asset: model.backdrop(gameID, chapter: model.nav.chapter, tall: false), game: model.game(gameID))
            .frame(height: 150)
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
}

/// R-7: chapters as a scrolling row with an edge fade; the selected chip scrolls into view.
struct ChapterBar: View {
    @Environment(AppModel.self) private var model
    var gameID: String
    var selected: Chapter

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(model.chapters(gameID)) { c in
                        let on = c == selected
                        Button { model.nav.chapter = c } label: {
                            Label(c.title, systemImage: c.symbol)
                                .font(PlayscribeFont.subheadline.weight(on ? .semibold : .regular))
                                .padding(.horizontal, 12)
                                .frame(minHeight: 44)
                                .background(on ? PlayscribeColor.accent.opacity(0.22) : Color.ink3, in: Capsule())
                        }
                        .buttonStyle(.plain)
                        .accessibilityAddTraits(on ? .isSelected : [])
                        .tappableFrame()
                        .id(c)
                    }
                }
                .padding(.horizontal, 2)
                .padding(.trailing, 24)
            }
            .edgeFade()
            .onAppear { proxy.scrollTo(selected, anchor: .center) }
            .onChange(of: selected) { _, c in withAnimation { proxy.scrollTo(c, anchor: .center) } }
        }
    }
}

/// Tabletop: the release contents live in the lower half, under the chapters (R-10).
struct ReleaseJumpChips: View {
    @Environment(AppModel.self) private var model
    var gameID: String
    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(model.ps5Releases(gameID).prefix(8)) { r in
                    Button { model.openGame(gameID, chapter: .updates, releaseID: r.id) } label: {
                        HStack(spacing: 6) {
                            if model.isUnread(r) { UnreadDot() }
                            Text(r.displayName).font(PlayscribeFont.footnote.weight(.medium))
                        }
                        .padding(.horizontal, 12)
                        .frame(minHeight: 44)
                        .background(Color.ink2, in: Capsule())
                    }
                    .buttonStyle(.plain)
                    .tappableFrame()
                }
            }
        }
    }
}
