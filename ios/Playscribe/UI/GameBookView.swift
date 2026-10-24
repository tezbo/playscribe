import SwiftUI

/// The game book. On the inner display it is an ArrangementView with the overlay style: the
/// reading panel is the primary view and the artwork the secondary one. Flat, reading floats over
/// the art; folded, the system puts reading in the trailing (book) or lower (tabletop) region.
struct GameBookView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.duo) private var duo
    var gameID: String

    var body: some View {
        let game = model.game(gameID)
        Group {
            if duo.pose == .closed {
                ReadingPanel(gameID: gameID, compact: true)
            } else {
                ArrangementView {
                    ReadingPanel(gameID: gameID, compact: false)
                        .overlayArrangementEdge(.trailing)
                } secondary: {
                    BookSecondary(gameID: gameID)
                        .allowsHitTesting(duo.pose != .tabletop)
                }
                .arrangementViewStyle(.overlay)
            }
        }
        .background(Color.ink0)
        .navigationTitle(game?.name ?? "")
        .toolbarTitleDisplayMode(.inline)
        .toolbar { ActionToolbar(actions: model.gameActions(gameID)) }
        .onAppear { model.nav.lastGameID = gameID }
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
            Wordmark()
            Text(model.game(gameID)?.name ?? "").font(.title2.bold()).fontDesign(.serif)
            if let r = model.ps5Releases(gameID).first {
                Text(r.displayName).font(.headline).foregroundStyle(.secondary)
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
            Text(chapter.title.uppercased()).font(.caption2.weight(.semibold)).foregroundStyle(.secondary)
            Text(model.game(gameID)?.name ?? "").font(.title3.bold()).fontDesign(.serif)
            ForEach(items, id: \.id) { item in
                Button(action: item.action) {
                    HStack(spacing: 8) {
                        if item.unread { UnreadDot() } else { Capsule().fill(.secondary).frame(width: 8, height: 2) }
                        Text(item.label).font(.subheadline.weight(.medium))
                        Spacer(minLength: 8)
                        Text(item.sub).font(.caption).foregroundStyle(.secondary)
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

    var body: some View {
        let chapter = model.chapters(gameID).contains(model.nav.chapter) ? model.nav.chapter : .updates
        let key = AppModel.bookKey(gameID, chapter)
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 14) {
                if compact { CompactHero(gameID: gameID) }
                header.id("top")
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
            .padding(.trailing, railWidth)
        }
        .scrollPosition(id: Binding(get: { model.nav.anchors[key] }, set: { model.nav.anchors[key] = $0 }), anchor: .top)
        .background(panelBackground)
        .modifier(FlatCard(enabled: !compact && !duo.isFolded, landscape: duo.isLandscape))
    }

    @ViewBuilder private var panelBackground: some View {
        if compact || duo.isFolded { Color.ink1.ignoresSafeArea() } else { Rectangle().fill(.regularMaterial) }
    }

    private var header: some View {
        let game = model.game(gameID)
        return VStack(alignment: .leading, spacing: 6) {
            Text(game?.name ?? "").font(.title.bold()).fontDesign(.serif)
            HStack(spacing: 8) {
                if let e = model.entry(gameID) { StatusPill(status: e.status) }
                if let dev = game?.developer { Text(dev).font(.subheadline).foregroundStyle(.secondary) }
            }
            if model.entry(gameID) == nil, let game {
                // N-9: a game book outside the library is readable, with Add to library.
                Button("Add to library") { model.addGame(game, status: .watching) }
                    .buttonStyle(.borderedProminent)
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
            .overlay(alignment: .bottomLeading) { Wordmark().padding(10) }
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
                                .font(.subheadline.weight(on ? .semibold : .regular))
                                .padding(.horizontal, 12)
                                .frame(minHeight: 44)
                                .background(on ? Color.accentColor.opacity(0.22) : Color.ink3, in: Capsule())
                        }
                        .buttonStyle(.plain)
                        .accessibilityAddTraits(on ? .isSelected : [])
                        .tappableFrame()
                        .id(c)
                    }
                }
                .padding(.horizontal, 2)
            }
            .mask(LinearGradient(stops: [.init(color: .black, location: 0), .init(color: .black, location: 0.9), .init(color: .clear, location: 1)],
                                 startPoint: .leading, endPoint: .trailing))
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
                            Text(r.displayName).font(.footnote.weight(.medium))
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
