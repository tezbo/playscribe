import SwiftUI

/// Contract v2 §11: a game is the Page (the release being read) and the Contents (the game's
/// chapters, search, releases and actions). The game book is one ArrangementView(.split), so the
/// system lays the two out for every pose: side by side in landscape, stacked in portrait, the
/// fold between them when folded, the Page alone when closed.

/// D-10: Contents on the left, Page on the right by default; "Swap sides" flips them, everywhere,
/// and persists (D-13).
enum ReadingSide {
    static let key = "pageOnLeft"
}

/// D-3: the selected release (or chapter) with its art band.
struct PageView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.duo) private var duo
    @State private var position = ScrollPosition(idType: String.self)
    @State private var liveOffset: CGFloat = 0
    var gameID: String
    /// Closed: one stacked book, the Contents below the Page.
    var withContents = false

    var body: some View {
        let chapter = model.chapters(gameID).contains(model.nav.chapter) ? model.nav.chapter : .updates
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                PageArtBand(gameID: gameID)
                StaleHint()
                if withContents, let g = model.game(gameID) {
                    VStack(alignment: .leading, spacing: 6) {
                        GameTitleWithStatus(gameID: gameID, name: g.name)
                    }
                    .padding(.horizontal, 20)
                }
                Group {
                    switch chapter {
                    case .updates:
                        if let r = model.selectedRelease(gameID) {
                            VStack(alignment: .leading, spacing: 16) {
                                ReleasePage(release: r)
                                if let g = model.game(gameID) {
                                    Divider().overlay(PlayscribeColor.ink700)
                                    GameBasicsView(game: g)
                                }
                            }
                            .pageTurn(key: r.id)
                        } else if let g = model.game(gameID) {
                            NoNotesPage(game: g)
                        }
                    case .news: NewsChapter(gameID: gameID)
                    case .world, .companion: EntriesChapter(gameID: gameID, chapter: chapter)
                    case .gallery: GalleryChapter(gameID: gameID)
                    case .mybook: MyBookChapter(gameID: gameID)
                    }
                }
                // Reading measure: 55 to 75 characters.
                .frame(maxWidth: 620, alignment: .leading)
                .padding(.horizontal, 20)
                if withContents {
                    Divider().overlay(PlayscribeColor.ink700).padding(.top, 8)
                    ContentsBody(gameID: gameID).padding(.horizontal, 16)
                }
            }
            .padding(.bottom, 24)
        }
        .scrollIndicators(.hidden)
        // D-2, T-5, D-10: the reading position is model state. Closing, opening, rotating or
        // swapping sides rebuilds this view; it comes back where the reader was.
        .scrollPosition($position)
        .accessibilityIdentifier("pageScroll")
        // A stacked Page ends at the Contents' edge: dissolve the last lines instead of cutting
        // them mid-letter under the game title.
        .mask {
            if withContents || duo.pose == .closed { Rectangle() } else {
                VStack(spacing: 0) {
                    Rectangle()
                    LinearGradient(colors: [.black, .clear], startPoint: .top, endPoint: .bottom).frame(height: 28)
                }
            }
        }
        // J-1: Back from a pushed release lands on its row (Closed shares this scroll).
        .onChange(of: model.nav.detailReleaseID) { old, new in
            // After the restore of the saved offset, which no longer points at the row.
            if withContents, new == nil, let old {
                Task { try? await Task.sleep(for: .milliseconds(250)); position.scrollTo(id: "row-\(old)", anchor: .center) }
            }
        }
        // Track the offset locally and persist it only when scrolling settles: writing model
        // state every frame re-rendered the whole page and made long notes lag (Terry, 0.2.0).
        .onScrollGeometryChange(for: CGFloat.self) { $0.contentOffset.y + $0.contentInsets.top } action: { _, y in
            liveOffset = y
        }
        .onScrollPhaseChange { _, phase in
            if phase == .idle { model.nav.anchors[anchorKey] = String(Int(liveOffset)) }
        }
        .onAppear(perform: restore)
        .onChange(of: duo.pose) { restore() }
        // Closed, the list shares this scroll; jumping to the top would lose the tapped row (J-1).
        .onChange(of: model.nav.selected?[gameID]) { if !withContents { position.scrollTo(edge: .top) } }
        .background(Color.ink0)
        .foldAudited()
    }

    private var anchorKey: String { "page-\(gameID)-\(model.nav.chapter.rawValue)" }

    private func restore() {
        guard let y = model.nav.anchors[anchorKey].flatMap(Double.init), y > 0 else { return }
        // After layout, so the content has its new height.
        Task { @MainActor in position.scrollTo(y: y) }
    }
}

private struct ExtensionUnlessSlim: ViewModifier {
    var slim: Bool
    @ViewBuilder func body(content: Content) -> some View {
        if slim { content } else { content.backgroundExtensionEffect() }
    }
}

/// The art band at the top of the Page, extended under the rail. The faded key-art header is the
/// default (A8, header-fade handoff): key art top-trailing under a left and a bottom fade into
/// ink; a portrait cover alone sits right over a blurred copy of itself; no art at all falls back
/// to the Playscribe landscape.
struct PageArtBand: View {
    @Environment(AppModel.self) private var model
    @Environment(\.duo) private var duo
    var gameID: String
    /// Closed landscape is wide and short (594 x 432 pt): a fixed 170 pt band took 40% of the screen and the
    /// extension effect stretched catalogue art past it (Terry, 0.5.0 build 6). There it is a slim, clipped band.
    private var slim: Bool { duo.isLandscape && duo.pose == .closed }
    var body: some View {
        let game = model.game(gameID)
        let asset = model.backdrop(gameID, chapter: model.nav.chapter, tall: false)
        let coverOnly = asset != nil && asset == game?.coverAsset && asset != game?.heroAsset
        let hasArt = asset != nil || game?.heroArtURL != nil || game?.coverURL != nil
        Group {
            if coverOnly || (asset == nil && game?.heroArtURL == nil && game?.coverURL != nil) {
                CoverHeader(game: game, asset: asset)
            } else {
                ArtView(asset: asset, game: game)
                    .modifier(hasArt ? FadeMask() : FadeMask(enabled: false))
            }
        }
        .frame(height: slim ? 96 : 170)
        .frame(maxWidth: .infinity)
        .clipped()
        .modifier(ExtensionUnlessSlim(slim: slim))
        .accessibilityHidden(true)
    }
}

/// Two gradients, no hard edge: left to right from ink to clear at 55%, bottom clear at 55% to ink.
struct FadeMask: ViewModifier {
    var enabled = true
    func body(content: Content) -> some View {
        if enabled {
            content
                .overlay(LinearGradient(stops: [.init(color: Color.ink0, location: 0), .init(color: .clear, location: 0.55)],
                                        startPoint: .leading, endPoint: .trailing))
                .overlay(LinearGradient(stops: [.init(color: .clear, location: 0.55), .init(color: Color.ink0, location: 1)],
                                        startPoint: .top, endPoint: .bottom))
        } else {
            content.overlay(alignment: .bottom) {
                LinearGradient(colors: [.clear, Color.ink0], startPoint: .top, endPoint: .bottom).frame(height: 60)
            }
        }
    }
}

/// Step 3 of the ladder: the portrait cover on the right at about 60% of the header height,
/// over a heavily blurred, darkened copy of itself, in the same faded treatment.
struct CoverHeader: View {
    var game: CatalogGame?
    var asset: String?
    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .trailing) {
                cover.scaledToFill().frame(width: geo.size.width, height: geo.size.height).blur(radius: 30).brightness(-0.35).clipped()
                cover.scaledToFit().frame(height: geo.size.height * 0.6).padding(.trailing, 24)
            }
        }
        .modifier(FadeMask())
    }

    @ViewBuilder private var cover: some View {
        if let asset { Image(asset).resizable() }
        else if let url = game?.coverURL {
            AsyncImage(url: url) { $0.resizable() } placeholder: { Color.ink1 }
        } else { Color.ink1 }
    }
}

/// One release on the Page: header, then GR-3's story-first body, with spoilers inline (D-6).
struct ReleasePage: View {
    @Environment(AppModel.self) private var model
    var release: Release
    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        let r = release
        VStack(alignment: .leading, spacing: 12) {
            // Accessibility sizes: the title and tags first, then the share button on its own row at the page's trailing
            // edge, 24 pt clear of the rail, so it never sits under the rail's buttons (R-2, Iris on #288 at AX3).
            if typeSize.isAccessibilitySize {
                HStack(spacing: 8) {
                    if model.isUnread(r) { UnreadDot() }
                    TitleWithTags(release: r) {
                        Text(r.displayName).font(PlayscribeFont.title3).accessibilityIdentifier("releaseTitle")
                    }
                }
                if r.isPS5Listed {
                    HStack { Spacer(minLength: 0); ShareUpdateButton(release: r) }.padding(.trailing, 24)
                }
            } else {
            HStack(spacing: 8) {
                if model.isUnread(r) { UnreadDot() }
                // Roles (Iris, PR #32): game name title2, update name title3, in every pose.
                TitleWithTags(release: r) {
                    Text(r.displayName).font(PlayscribeFont.title3)
                        .accessibilityIdentifier("releaseTitle")
                }
                Spacer(minLength: 0)
                if r.isPS5Listed { ShareUpdateButton(release: r) }
            }
            }
            HStack(spacing: 8) {
                Text((r.isPS5Listed ? r.ps5Date : r.latestDate).shortDay)
                if let v = r.ps5Version { Text(v).monospacedDigit() }
            }
            .font(PlayscribeFont.subheadline).foregroundStyle(.secondary)
            SourceLinks(release: r)
            ForYouCard(release: r)
            if r.notes.contains(where: { $0.items.contains { $0.spoiler == true } }) {
                SpoilerLine(gameID: r.gameID)
            }
            ReleaseBody(release: r)
        }
        .id(r.id)
    }
}



/// D-6: "Story spoilers hidden" with a Show button, only when the release has spoilers.
struct SpoilerLine: View {
    @Environment(AppModel.self) private var model
    var gameID: String
    var body: some View {
        let shown = model.spoilersShown(gameID)
        Button {
            model.setSpoilersShown(gameID, !shown)
            model.show(Toast(text: shown ? "Spoilers hidden" : "Spoilers shown"))
        } label: {
            HStack(spacing: 8) {
                Image(systemName: shown ? "eye" : "eye.slash")
                Text(shown ? "Story spoilers shown" : "Story spoilers hidden").foregroundStyle(.secondary)
                Text(shown ? "Hide" : "Show").fontWeight(.semibold)
            }
            .font(PlayscribeFont.subheadline)
            .foregroundStyle(PlayscribeColor.accent)
            .frame(minHeight: 44)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .tappableFrame()
    }
}

/// GR-1: never an empty game.
struct NoNotesPage: View {
    @Environment(AppModel.self) private var model
    var game: CatalogGame
    var body: some View {
        // Terry: a game never opens blank. With no updates, it leads with its release.
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 6) {
                Text(game.ps5AvailabilityLine).font(PlayscribeFont.title3)
                NoUpdatesLine()
            }
            GameBasicsView(game: game)
        }
    }
}

/// The game's own information: genres, launch trailer, description and story.
/// The game's official website and patch notes (info links); Link opens the default browser.
/// In the Contents, so in Tabletop they're on the flat half.
struct GameLinks: View {
    var game: CatalogGame
    var body: some View {
        let links = game.igdbID.flatMap { GameInfoStore.shared.basics[$0] }?.links
        if links?.official != nil || links?.patchNotes != nil {
            // One row, a 24 pt gap and no separators; wraps to a second line rather than truncating (Iris 0.5.0).
            FlowLayout(spacing: 24) {
                if let url = links?.official {
                    Link(destination: url) { Label("Official website", systemImage: "arrow.up.right.square").frame(minHeight: 44).contentShape(Rectangle()) }.tappableFrame()
                }
                if let url = links?.patchNotes {
                    Link(destination: url) { Label(LinkHost.label("All patch notes", url), systemImage: "arrow.up.right.square").frame(minHeight: 44).contentShape(Rectangle()) }.tappableFrame().accessibilityHint("Opens in browser")
                }
            }
            .font(PlayscribeFont.subheadline)
            .foregroundStyle(PlayscribeColor.accent)
        }
    }
}

struct GameBasicsView: View {
    @Environment(\.duo) private var duo
    @Environment(AppModel.self) private var model
    var game: CatalogGame
    @State private var storyOpen = false
    private var store: GameInfoStore { .shared }

    var body: some View {
        let info = game.igdbID.flatMap { store.basics[$0] }
        // A game not in the catalogue still opens with what the upcoming feed carries.
        let fallback = game.igdbID.flatMap { UpcomingStore.shared.extras[$0] }
        let genres = info?.genres ?? fallback?.genres ?? []
        let summary = info?.summary ?? fallback?.summary
        let videos = info?.videos ?? fallback?.trailerId.map { [GameBasics.Video(youtubeId: $0, name: "Trailer")] } ?? []
        VStack(alignment: .leading, spacing: 14) {
            if let move = fallback?.move?.line {
                Text(move).font(PlayscribeFont.subheadline.weight(.semibold)).foregroundStyle(PlayscribeColor.accent)
            }
            if !genres.isEmpty {
                Text(genres.joined(separator: ", ")).font(PlayscribeFont.subheadline).foregroundStyle(.secondary)
            }
            if !videos.isEmpty {
                // One video per title: the feed can carry two cuts named "Launch Trailer".
                let unique = videos.reduce(into: [GameBasics.Video]()) { out, v in if !out.contains(where: { $0.name == v.name }) { out.append(v) } }
                ForEach(unique.prefix(3), id: \.youtubeId) { v in
                    Button { model.trailer = (v.youtubeId, v.name) } label: {
                        HStack(spacing: 12) {
                            AsyncImage(url: URL(string: "https://i.ytimg.com/vi/\(v.youtubeId)/mqdefault.jpg")) { $0.resizable().scaledToFill() } placeholder: { Color.ink1 }
                                .frame(width: 112, height: 63)
                                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                                .overlay { Image(systemName: "play.fill").foregroundStyle(.white) }
                            Text(v.name).font(PlayscribeFont.subheadline).lineLimit(2).multilineTextAlignment(.leading)
                            Spacer(minLength: 0)
                        }
                        .frame(minHeight: 44)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Play \(v.name)")
                    .tappableFrame()
                }
            }
            // The slot is always reserved: when the details did not load, say so and offer Retry.
            if info == nil, let id = game.igdbID, store.failedShards.contains(id % 100) {
                HStack {
                    Text("Details need a connection").font(PlayscribeFont.subheadline).foregroundStyle(.secondary)
                    Spacer(minLength: 0)
                    Button { Task { await store.load(igdbID: id) } } label: { Text("Retry").frame(minWidth: 44, minHeight: 44).contentShape(Rectangle()) }
                        .font(PlayscribeFont.subheadline.weight(.semibold)).foregroundStyle(PlayscribeColor.accent)
                        .tappableFrame()
                }
                .padding(.horizontal, 14)
                .background(Color.ink2, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            }
            // Closed has no Contents panel, so the links sit with the basics.
            if duo.pose == .closed { GameLinks(game: game) }
            if let summary {
                Text("About").font(PlayscribeFont.headline)
                LinkedTextView(text: summary).font(PlayscribeFont.body)
            }
            if let story = info?.storyline {
                Text("Story").font(PlayscribeFont.headline)
                LinkedTextView(text: story).font(PlayscribeFont.body).lineLimit(storyOpen ? nil : 4)
                Button(storyOpen ? "Less" : "More") { withAnimation(.snappy) { storyOpen.toggle() } }
                    .font(PlayscribeFont.subheadline.weight(.semibold)).frame(minWidth: 44, minHeight: 44).contentShape(Rectangle()).tappableFrame()
            }
            SimilarGamesRow(game: game)
        }
        .task(id: game.igdbID) { if let id = game.igdbID { await store.load(igdbID: id) } }
    }
}

/// "You might also like": up to 8 PS5 games related to this one, none already in the library.
/// Hidden when empty; a failed load shows nothing (0.5.0 item 18).
struct SimilarGamesRow: View {
    @Environment(AppModel.self) private var model
    var game: CatalogGame
    @State private var choosing: CatalogGame?

    private var games: [CatalogGame] {
        let inLibrary = Set(model.data.collection.compactMap { model.game($0.gameID)?.igdbID })
        let similar = game.igdbID.flatMap { GameInfoStore.shared.basics[$0] }?.similar ?? []
        return similar.compactMap { s -> CatalogGame? in
            guard s.igdbId != game.igdbID, !inLibrary.contains(s.igdbId),
                  let e = PS5Index.shared.entry(igdb: s.igdbId) else { return nil }
            return PS5Index.shared.game(e)
        }.prefix(8).map { $0 }
    }

    var body: some View {
        let list = games
        if !list.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                Text("You might also like").font(PlayscribeFont.headline).accessibilityAddTraits(.isHeader)
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 10) {
                        ForEach(list) { g in
                            Button { choosing = g } label: {
                                TileCover(game: g).frame(width: 104, height: 139)
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel(g.name)
                            .accessibilityHint("Choose how to add it")
                            .tappableFrame()
                        }
                    }
                }
                .edgeFade(40)
            }
            .confirmationDialog(choosing?.name ?? "", isPresented: Binding(get: { choosing != nil }, set: { if !$0 { choosing = nil } }), titleVisibility: .visible) {
                if let g = choosing {
                    Button("Add to library") { model.addGame(g, status: .owned); model.openGame(g.id) }
                    Button("Add to watchlist") { model.addGame(g, status: .wishlist); model.openGame(g.id) }
                }
                Button("Cancel", role: .cancel) {}
            }
        }
    }
}

/// A game's trailer, from its basics (not tied to a release).
struct TrailerView: View {
    @Environment(AppModel.self) private var model
    var videoID: String
    var name: String
    @State private var controller: YouTubeController?
    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 12) {
                Color.black.aspectRatio(16 / 9, contentMode: .fit)
                    .overlay { if let controller { WebSurface(webView: controller.webView) } }
                Text(name).font(PlayscribeFont.headline).padding(.horizontal, 16)
                Spacer()
            }
            .background(Color.black)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button { model.trailer = nil } label: { Label("Close", systemImage: "xmark") }
                }
            }
        }
        .onAppear { if controller == nil { controller = YouTubeController(videoID: videoID) } }
        .onDisappear { controller?.stop() }
    }
}

/// D-4: the Contents, top to bottom: title and status, chapters, search in notes, Mark n read,
/// the release timeline, and in Tabletop the section outline with Previous and Next.
struct ContentsView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.railWidth) private var railWidth
    @State private var position = ScrollPosition(idType: String.self)
    var gameID: String

    var body: some View {
        ScrollView {
            ContentsBody(gameID: gameID)
                .padding(.horizontal, 16)
                .padding(.vertical, 14)
                .padding(.trailing, railWidth)
        }
        .scrollPosition($position)
        .accessibilityIdentifier("contentsScroll")
        // J-1: Back from a pushed release (open portrait) lands on its row.
        .onChange(of: model.nav.detailReleaseID) { old, new in
            if new == nil, let old { position.scrollTo(id: "row-\(old)", anchor: .center) }
        }
        .scrollIndicators(.hidden)
        .background(Color.ink1)
        .foldAudited()
    }
}

struct ContentsBody: View {
    @Environment(AppModel.self) private var model
    @Environment(\.duo) private var duo
    @AppStorage(ReadingSide.key) private var pageOnLeft = false
    var gameID: String

    var body: some View {
        let game = model.game(gameID)
        let chapter = model.chapters(gameID).contains(model.nav.chapter) ? model.nav.chapter : .updates
            VStack(alignment: .leading, spacing: 14) {
                if duo.pose != .closed { HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 4) {
                        GameTitleWithStatus(gameID: gameID, name: game?.name ?? "")
                    }
                    Spacer(minLength: 8)
                } }
                // Once per page (Terry): closed, the links sit with the game's basics instead.
                if duo.pose != .closed && duo.pose != .tabletop, let game { GameLinks(game: game) }
                if model.entry(gameID) == nil, let game {
                    Button("Add to library") { model.addGame(game, status: .watching) }
                        .buttonStyle(.borderedProminent).foregroundStyle(PlayscribeColor.onAccent).hitTarget()
                }
                ChapterBar(gameID: gameID, selected: chapter)
                NotesSearchField(gameID: gameID)
                if model.noteQuery.count >= 2 || (duo.pose == .tabletop && model.noteLetter != nil) {
                    InlineNoteResults(gameID: gameID)
                } else if chapter == .updates {
                    let unread = model.releases(gameID).filter(model.isUnread).count
                    if unread > 0 {
                        Button { model.markAllRead(gameID) } label: {
                            Label("Mark \(unread) read", systemImage: "envelope.open")
                                .font(PlayscribeFont.subheadline.weight(.semibold))
                                .frame(minHeight: 44)
                        }
                        .tappableFrame()
                    }
                    if duo.pose == .tabletop {
                        TabletopOutline(gameID: gameID)
                    }
                    ReleaseTimeline(gameID: gameID)
                }
            }
    }
}

/// D-10: flips Contents and Page; shown only when they're side by side.
struct SwapSidesButton: View {
    @Binding var pageOnLeft: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    private var glyph: String { Self.glyph(pageOnLeft: pageOnLeft) }
    static func glyph(pageOnLeft: Bool) -> String { pageOnLeft ? "swap-sides.left" : "swap-sides.right" }
    static func value(pageOnLeft: Bool) -> String { pageOnLeft ? "Reading on left" : "Reading on right" }

    /// D-10: the T-2 spring, or a cross-fade under Reduce Motion (T-4).
    private func swap() {
        withAnimation(reduceMotion ? .easeInOut(duration: 0.25) : .spring(duration: 0.45, bounce: 0.12)) { pageOnLeft.toggle() }
    }
    /// On the rail with the other actions (D-6, D-10): the glyph as the icon, "Swap sides" as the title.
    var body: some View {
        Button(action: swap) {
            Label { Text("Swap sides") } icon: { Image(glyph).renderingMode(.template) }
        }
        .accessibilityIdentifier("swapSides")
        // The toolbar turns this into a bar button, which drops accessibilityValue, so VoiceOver
        // hears the side as part of the label; Voice Control still answers to "Swap sides".
        .accessibilityLabel("Swap sides, \(SwapSidesButton.value(pageOnLeft: pageOnLeft).lowercased())")
        .accessibilityInputLabels(["Swap sides"])
        .accessibilityShowsLargeContentViewer { Label("Swap sides", image: glyph) }
    }
}

/// GR-4 in the Contents: search this game's notes, or all my games.
struct NotesSearchField: View {
    @Environment(AppModel.self) private var model
    @Environment(\.duo) private var duo
    var gameID: String
    var body: some View {
        @Bindable var model = model
        if duo.pose == .tabletop {
            // Tabletop: no keyboard; a read-only button and an A to Z strip (Iris, 0.2.0 ruling).
            VStack(alignment: .leading, spacing: 8) {
                TabletopSearch(letter: $model.noteLetter,
                               prompt: model.noteScope == .thisGame ? "Search this game's notes" : "Search all my games' notes")
                if model.noteLetter != nil {
                    Picker("Search in", selection: $model.noteScope) {
                        ForEach(NoteScope.allCases, id: \.self) { Text($0.label).tag($0) }
                    }
                    .pickerStyle(.segmented)
                }
            }
        } else {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                TextField(model.noteScope == .thisGame ? "Search this game's notes" : "Search all my games' notes", text: $model.noteQuery)
                    .autocorrectionDisabled()
                    .submitLabel(.search)
                    .onSubmit { model.rememberSearch(model.noteQuery) }
                if !model.noteQuery.isEmpty {
                    Button { model.noteQuery = "" } label: { Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary) }
                        .accessibilityLabel("Clear search")
                }
            }
            .padding(.horizontal, 12)
            .frame(minHeight: 44)
            .background(PlayscribeColor.ink700, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            if !model.noteQuery.isEmpty {
                Picker("Search in", selection: $model.noteScope) {
                    ForEach(NoteScope.allCases, id: \.self) { Text($0.label).tag($0) }
                }
                .pickerStyle(.segmented)
            }
        }
        }
    }
}

struct InlineNoteResults: View {
    @Environment(AppModel.self) private var model
    @Environment(\.duo) private var duo
    var gameID: String
    var body: some View {
        let byLetter = duo.pose == .tabletop ? model.noteLetter : nil
        let hits = byLetter.map { model.noteHits(letter: $0, scope: model.noteScope, gameID: gameID) }
            ?? model.noteHits(model.noteQuery, scope: model.noteScope, gameID: gameID)
        VStack(alignment: .leading, spacing: 6) {
            if !hits.isEmpty {
                Text("\(hits.count) result\(hits.count == 1 ? "" : "s")")
                    .font(PlayscribeFont.caption).foregroundStyle(.secondary)
                    .accessibilityLabel("\(hits.count) results")
            }
            if hits.isEmpty {
                let none = model.noteScope == .thisGame ? "Nothing in this game's notes matches" : "Nothing in your games' notes matches"
                Text(byLetter.map { "No notes start with \($0)" } ?? none)
                    .font(PlayscribeFont.headline)
                if model.noteScope == .thisGame {
                    Button("Search all my games") { model.noteScope = .allGames }.hitTarget()
                }
            }
            ForEach(hits.filter { !$0.pcOnly } + hits.filter(\.pcOnly)) { h in
                Button {
                    model.rememberSearch(model.noteQuery)
                    if h.release.gameID == gameID { model.select(gameID, releaseID: h.release.id) }
                    else { model.openGame(h.release.gameID, chapter: .updates, releaseID: h.release.id) }
                    model.highlight = h.release.id
                    model.noteQuery = ""
                    model.noteLetter = nil
                } label: {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(NoteHit.bolded(h.line, query: model.noteQuery)).font(PlayscribeFont.subheadline).lineLimit(3)
                        HStack(spacing: 6) {
                            Text(h.release.displayName).font(PlayscribeFont.caption)
                            Text(h.pcOnly ? "PC only" : h.section).font(PlayscribeFont.caption).foregroundStyle(.secondary)
                        }
                    }
                    .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .tappableFrame()
            }
        }
    }
}

/// D-4: one 44 pt row per release; the selected row highlighted; PC-only last.
struct ReleaseTimeline: View {
    @Environment(AppModel.self) private var model
    @Environment(\.duo) private var duo
    @Environment(\.dynamicTypeSize) private var typeSize
    var gameID: String

    var body: some View {
        let selected = model.selectedRelease(gameID)?.id
        let ps5 = model.ps5Releases(gameID)
        let pc = model.pcOnlyReleases(gameID)
        VStack(alignment: .leading, spacing: 4) {
            Text("ALL UPDATES").font(PlayscribeFont.caption).tracking(1).foregroundStyle(PlayscribeColor.textTertiary)
            if ps5.isEmpty, let g = model.game(gameID) {
                Text(g.ps5AvailabilityLine).font(PlayscribeFont.subheadline)
            }
            ForEach(ps5) { row($0, selected: $0.id == selected) }
            ForEach(pc) { row($0, selected: $0.id == selected) }
        }
    }

    private func row(_ r: Release, selected: Bool) -> some View {
        Button {
            // J-1: side by side (and Tabletop, where the Page is the standing half) the Page shows
            // it; Closed and open portrait push it as its own screen.
            if duo.pose == .closed || (duo.pose == .flat && !duo.isLandscape) {
                model.select(gameID, releaseID: r.id)
                model.nav.detailReleaseID = r.id
            } else {
                model.select(gameID, releaseID: r.id)
            }
        } label: {
            let title = TitleWithTags(release: r) {
                Text(r.displayName).font(PlayscribeFont.subheadline.weight(selected ? .semibold : .regular))
                    .lineLimit(typeSize.isAccessibilitySize ? 3 : 1)
            }
            let date = Text((r.isPS5Listed ? r.ps5Date : r.latestDate).dayMonthOrYear).font(PlayscribeFont.caption).foregroundStyle(.secondary)
            HStack(alignment: .top, spacing: 8) {
                if model.isUnread(r) { UnreadDot() } else { Color.clear.frame(width: 8, height: 8) }
                if typeSize.isAccessibilitySize {
                    // No trailing date column at AX: the date takes its own full-width line under the title and tags.
                    VStack(alignment: .leading, spacing: 4) { title; date }
                    Spacer(minLength: 0)
                } else {
                    title
                    Spacer(minLength: 4)
                    date
                }
            }
            .padding(.horizontal, 10)
            .frame(minHeight: 44)
            .background(selected ? PlayscribeColor.ink700 : .clear, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("releaseRow-\(r.displayName)")
        .id("row-\(r.id)")
        .accessibilityAddTraits(selected ? .isSelected : [])
        .tappableFrame()
    }
}

/// TT-2 in the Contents: the section outline with Previous and Next.
struct TabletopOutline: View {
    @State private var fullText = false
    @Environment(AppModel.self) private var model
    var gameID: String
    var body: some View {
        let sections = model.readerRelease(gameID).map(model.readerSections) ?? []
        let index = min(model.readerIndex[gameID] ?? 0, max(0, sections.count - 1))
        VStack(spacing: 2) {
            ForEach(Array(sections.enumerated()), id: \.element.id) { i, s in
                Button { model.readerIndex[gameID] = i } label: {
                    HStack {
                        Text(s.title).font(PlayscribeFont.subheadline.weight(i == index ? .semibold : .regular)).lineLimit(1)
                        Spacer()
                        Text("\(i + 1)").font(PlayscribeFont.caption).foregroundStyle(.secondary)
                    }
                    .padding(.horizontal, 10)
                    .frame(minHeight: 44)
                    .background(i == index ? PlayscribeColor.ink700 : .clear, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .tappableFrame()
            }
            // The stage caps long text (never mid-word); the whole of it is here, in the lower half.
            if let sec = sections[safe: index], ReaderBody.isCapped(title: sec.title, body: sec.body) {
                Button { fullText.toggle() } label: {
                    HStack {
                        Text(fullText ? "Hide full text" : "Full text").font(PlayscribeFont.subheadline.weight(.semibold))
                        Spacer()
                        Image(systemName: fullText ? "chevron.up" : "chevron.down")
                    }
                    .foregroundStyle(PlayscribeColor.accent)
                    .padding(.horizontal, 10).frame(minHeight: 44).contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .tappableFrame()
                .accessibilityIdentifier("readerFullText")
                if fullText {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(sec.title).font(PlayscribeFont.headline)
                        Text(sec.body).font(PlayscribeFont.body)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 10)
                }
            }
            HStack(spacing: 12) {
                pageButton("Previous", "chevron.backward", enabled: index > 0) { model.readerIndex[gameID] = index - 1 }
                pageButton("Next", "chevron.forward", enabled: index < sections.count - 1) { model.readerIndex[gameID] = index + 1 }
            }
            .padding(.top, 6)
        }
    }

    private func pageButton(_ title: String, _ symbol: String, enabled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(title, systemImage: symbol)
                .font(PlayscribeFont.headline)
                .frame(maxWidth: .infinity, minHeight: 52)
                .background(PlayscribeColor.ink700, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
        .opacity(enabled ? 1 : 0.4)
        .tappableFrame()
    }
}

/// J-1: one release as its own screen, pushed from the list in Closed and open portrait.
struct ReleaseDetailView: View {
    @Environment(AppModel.self) private var model
    var gameID: String
    var releaseID: String
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                PageArtBand(gameID: gameID)
                if let r = model.release(gameID, releaseID) {
                    ReleasePage(release: r).padding(.horizontal, 20)
                }
            }
            .padding(.bottom, 24)
        }
        .background(Color.ink0)
        .navigationTitle(model.release(gameID, releaseID)?.displayName ?? "")
        .toolbarTitleDisplayMode(.inline)
        .foldAudited()
    }
}

/// The game's name with its status glyph inline (Iris, 0.2.0): a tick in a circle for Owned, a
/// bookmark for Wishlist, an eye for Watching. Tapping the glyph opens the status choice.
struct GameTitleWithStatus: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dynamicTypeSize) private var typeSize
    var gameID: String
    var name: String

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            titleRow
            if model.entry(gameID)?.status == .wishlist, let g = model.game(gameID), g.isUpcoming || g.releasePrecision == .tbd {
                Text("On your watchlist").font(PlayscribeFont.subheadline).foregroundStyle(.secondary)
            }
        }
    }

    private var titleRow: some View {
        // Accessibility sizes: the status glyph sits under the title instead of beside it, so the title gets the whole
        // column and "Deliverance" is never cut mid-word (Iris on #289, b5b0b1a).
        let layout = typeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: 0)) : AnyLayout(HStackLayout(alignment: .firstTextBaseline, spacing: 8))
        return layout {
            // Up to 4 lines, and the title text stops growing at AX3: at AX5 one long word ("Deliverance") is wider than a
            // Closed portrait column and cut mid-word (c240de9). The reader shows the true size.
            Text(name).font(PlayscribeFont.title2).lineLimit(typeSize.isAccessibilitySize ? 4 : 2)
                .fixedSize(horizontal: false, vertical: true).accessibilityAddTraits(.isHeader)
                .dynamicTypeSize(...DynamicTypeSize.accessibility3)
            if let e = model.entry(gameID) {
                Menu { ActionMenuContent(sections: model.statusMenu(gameID)) } label: {
                    Image(systemName: Self.symbol(e.status))
                        .font(.system(size: 20))
                        .foregroundStyle(e.status == .owned ? PlayscribeColor.accent : PlayscribeColor.textSecondary)
                        .frame(width: 44, height: 44)
                        .contentShape(Rectangle())
                }
                .padding(.vertical, -12)
                .accessibilityLabel(e.status.label)
                .accessibilityHint("Change status")
                .accessibilityIdentifier("statusGlyph")
                .tappableFrame()
            }
        }
    }

    static func symbol(_ s: OwnershipStatus) -> String {
        switch s { case .owned: "checkmark.circle.fill"; case .wishlist: "bookmark.fill"; case .watching: "eye.fill" }
    }
}


/// J-11: the game's links as sheet rows, Tabletop only (the inline row stays in every other pose).
struct LinksSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.panelClose) private var panelClose
    var gameID: String

    private struct Row: Identifiable { var id: String; var title: String; var url: URL }

    private var rows: [Row] {
        var out: [Row] = []
        if let game = model.game(gameID) {
            let links = game.igdbID.flatMap { GameInfoStore.shared.basics[$0] }?.links
            if let u = links?.official { out.append(Row(id: "official", title: "Official website", url: u)) }
            if let u = links?.patchNotes { out.append(Row(id: "notes", title: LinkHost.label("All patch notes", u), url: u)) }
        }
        if let r = model.readerRelease(gameID), let u = r.links?.steamNotes { out.append(Row(id: "steam", title: LinkHost.label("Read full notes", u), url: u)) }
        return out
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("Links").font(PlayscribeFont.title3).accessibilityAddTraits(.isHeader)
                Spacer()
                Button { if let panelClose { panelClose() } else { model.linksSheetOpen = false } } label: {
                    Image(systemName: "xmark.circle.fill").font(PlayscribeFont.title3).frame(width: 44, height: 44)
                }
                .foregroundStyle(.secondary)
                .accessibilityLabel("Close links")
                .tappableFrame()
            }
            .padding(.horizontal, 20).padding(.top, 8).padding(.bottom, 4)
            ForEach(rows) { row in
                Link(destination: row.url) {
                    HStack {
                        Text(row.title).font(PlayscribeFont.body)
                        Spacer()
                        Image(systemName: "arrow.up.right.square")
                    }
                    .padding(.horizontal, 20)
                    .frame(maxWidth: .infinity, minHeight: 52, alignment: .leading)
                    .contentShape(Rectangle())
                }
                .foregroundStyle(PlayscribeColor.accent)
                .accessibilityLabel("\(row.title), opens in browser")
                .tappableFrame()
            }
            Spacer(minLength: 0)
        }
        .background(Color.ink1)
    }

    static func hasLinks(_ model: AppModel, _ gameID: String) -> Bool {
        let links = model.game(gameID)?.igdbID.flatMap { GameInfoStore.shared.basics[$0] }?.links
        return links?.official != nil || links?.patchNotes != nil || model.readerRelease(gameID)?.links?.steamNotes != nil
    }
}
