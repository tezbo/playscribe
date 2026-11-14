import SwiftUI
import OSLog

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
    @AppStorage(ReadingSide.key) private var pageOnLeft = false
    @State private var position = ScrollPosition(idType: String.self)
    @State private var liveOffset: CGFloat = 0
    var gameID: String
    /// Closed: one stacked book, the Contents below the Page.
    var withContents = false

    /// Closed and Open portrait, Updates chapter: the Contents (bar, search, Mark read, All updates) between the release and About.
    private var closedContents: some View {
        VStack(alignment: .leading, spacing: 16) {
            Divider().overlay(PlayscribeColor.ink700)
            ContentsBody(gameID: gameID, addControl: false)
        }
    }

    var body: some View {
        let chapter = model.chapters(gameID).contains(model.nav.chapter) ? model.nav.chapter : .updates
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                PageArtBand(gameID: gameID)
                StaleHint()
                if withContents, !model.gameDisplayName(gameID).isEmpty {
                    VStack(alignment: .leading, spacing: 6) {
                        GameTitleWithStatus(gameID: gameID, name: model.gameDisplayName(gameID))
                        // Closed has no Contents header, so a browsed game (Upcoming, PS Plus) gets its add control here.
                        if let g = model.game(gameID), model.entry(gameID) == nil {
                            Button("Add to library") { model.addGame(g, status: .watching) }
                                .buttonStyle(.borderedProminent).foregroundStyle(PlayscribeColor.onAccent).hitTarget()
                                .accessibilityIdentifier("addToLibrary")
                                // 20 pt clear of the title above and the page below (Iris, #442). The 44 pt hit frame leaves
                                // 4 pt round the 36 pt pill, so the stack gaps (6 above, 16 below) plus the text's own leading
                                // read as 15 and 25 on the Closed still; 5 each way evens them (0e10f45 still: 3/-14 overshot).
                                .padding(.top, 5).padding(.bottom, -5)
                        }
                    }
                    .padding(.leading, duo.hingeInset(20, facingHinge: !pageOnLeft))
                    .padding(.trailing, duo.hingeInset(20, facingHinge: pageOnLeft))
                }
                Group {
                    switch chapter {
                    case .updates:
                        if let r = model.selectedRelease(gameID) {
                            VStack(alignment: .leading, spacing: 16) {
                                ReleasePage(release: r)
                                // Closed and Open portrait (one column): All updates (the Contents) sits above About (Terry, 0.5.4), so the reader reaches
                                // the game's other updates before its blurb; You might also like stays last.
                                if withContents { closedContents }
                                if let g = model.game(gameID) {
                                    Divider().overlay(PlayscribeColor.ink700)
                                    GameBasicsView(game: g)
                                }
                            }
                            .pageTurn(key: r.id)
                        } else if let g = model.game(gameID) {
                            NoNotesPage(game: g) { if withContents { closedContents } }
                        }
                    case .news: NewsChapter(gameID: gameID)
                    case .world, .companion: EntriesChapter(gameID: gameID, chapter: chapter)
                    case .gallery: GalleryChapter(gameID: gameID)
                    case .mybook: MyBookChapter(gameID: gameID)
                    }
                }
                // Reading measure: 55 to 75 characters.
                .frame(maxWidth: 620, alignment: .leading)
                .padding(.leading, duo.hingeInset(20, facingHinge: !pageOnLeft))
                .padding(.trailing, duo.hingeInset(20, facingHinge: pageOnLeft))
                // The other chapters keep the Contents below the page (the Updates chapter draws it above About).
                if withContents && chapter != .updates {
                    Divider().overlay(PlayscribeColor.ink700).padding(.top, 8)
                    ContentsBody(gameID: gameID, addControl: false).padding(.horizontal, 16)
                }
            }
            .padding(.bottom, 24)
            // The column is exactly what the scroll view proposes (its viewport beside the rail: 382 pt in Closed, 372 in Book) as
            // long as every child can shrink to it. A vertical scroll view centres content wider than its viewport, so one child
            // that could not (the PS4 update + Reported tag row at AX5, 514 pt) pushed the whole page 66 pt left under the screen
            // edge: "atch 5.01", a clipped "9 Oct", the share button behind the rail (Closed AX5, frame dump on 805ceb3). The tags
            // wrap (ReleaseTag) and the two links stack (SourceLinks) now, and a frame dump at e4833ee shows nothing wider than
            // the viewport. Do not pin the column to a measured width instead: a Color probe inside the content measured the
            // frame rail included (466; b8fbaad), and the scroll view's own geometry minus its insets came out 20 to 80 pt short
            // (57227e2); each one moved the page in some pose (R-2).
        }
        .clearsMessages()
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
    /// Lifts the dot from the first line's baseline to half the cap height (centred on line 1; Iris) (same idea as FeedRow's dotLift).
    @ScaledMetric(relativeTo: .title3) private var dotLift: CGFloat = 7

    /// The unread dot and the title block, the dot level with the title's FIRST line however many lines it wraps to.
    @ViewBuilder private func dotAndTitle(_ r: Release) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {   // 12 pt clear of the text (Iris)
            if model.isUnread(r) {
                UnreadDot().alignmentGuide(.firstTextBaseline) { $0[VerticalAlignment.center] + dotLift }
            }
            TitleWithTags(release: r) {
                // At accessibility sizes a plain Text wraps a word wider than the column by character and can leave a comma
                // alone at the start of a line (r061, "Rebalancing" / ", Quality of"); WholeWordText cuts on a whole word.
                if typeSize.isAccessibilitySize {
                    WholeWordText(text: r.displayName, font: PlayscribeFont.title3, lines: 4, color: nil)
                        .accessibilityIdentifier("releaseTitle")
                } else {
                    Text(r.displayName).font(PlayscribeFont.title3).accessibilityIdentifier("releaseTitle")
                }
            }
        }
    }

    var body: some View {
        let r = release
        VStack(alignment: .leading, spacing: 12) {
            // Accessibility sizes: the title and tags first, then the share button on its own row, its right edge on the
            // text column's trailing line (the one the headline and body wrap to), so it is clear of the rail and the
            // hinge band without extra padding; the VStack's 12 pt is the gap above and below (R-2, r060, Iris).
            if typeSize.isAccessibilitySize {
                if r.isPS5Listed {
                    // A title that fits one line leaves room for the button beside it, level with that first line (Iris, #441);
                    // a longer one keeps the button on its own row below, so the title never loses width.
                    ViewThatFits(in: .horizontal) {
                        HStack(alignment: .top, spacing: 8) {
                            dotAndTitle(r)
                            Spacer(minLength: 0)
                            ShareUpdateButton(release: r)
                        }
                        VStack(alignment: .leading, spacing: 12) {
                            dotAndTitle(r)
                            HStack { Spacer(minLength: 0); ShareUpdateButton(release: r) }
                        }
                    }
                } else {
                    dotAndTitle(r)
                }
            } else {
            HStack(spacing: 8) {
                // Roles (Iris, PR #32): game name title2, update name title3, in every pose.
                dotAndTitle(r)
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
    @Environment(\.dynamicTypeSize) private var typeSize
    var gameID: String
    var body: some View {
        let shown = model.spoilersShown(gameID)
        Button {
            model.setSpoilersShown(gameID, !shown)
            model.show(Toast(text: shown ? "Spoilers hidden" : "Spoilers shown"))
        } label: {
            // At accessibility sizes the label takes the full width in whole words and the Show button sits under it,
            // on its own 44 pt line, so the label never breaks by letter and the button is never cut by the next row.
            let layout = typeSize.isAccessibilitySize ? AnyLayout(VStackLayout(alignment: .leading, spacing: 4)) : AnyLayout(HStackLayout(spacing: 8))
            layout {
                HStack(spacing: 8) {
                    Image(systemName: shown ? "eye" : "eye.slash")
                    Text(shown ? "Story spoilers shown" : "Story spoilers hidden").foregroundStyle(PlayscribeColor.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Text(shown ? "Hide" : "Show").fontWeight(.semibold)
                    .frame(minHeight: 44, alignment: .leading)
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
struct NoNotesPage<Contents: View>: View {
    @Environment(AppModel.self) private var model
    var game: CatalogGame
    /// Closed: the Contents, drawn above About as on a page with notes.
    @ViewBuilder var contents: () -> Contents
    init(game: CatalogGame, @ViewBuilder contents: @escaping () -> Contents = { EmptyView() }) {
        self.game = game
        self.contents = contents
    }
    var body: some View {
        // Terry: a game never opens blank. With no updates, it leads with its release.
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 6) {
                Text(game.ps5AvailabilityLine).font(PlayscribeFont.title3)
                NoUpdatesLine(gameID: game.id)
            }
            contents()
            GameBasicsView(game: game)
        }
    }
}

/// The game's own information: genres, launch trailer, description and story.
/// The game's official website and patch notes (info links); Link opens the default browser.
/// In the Contents, so in Tabletop they're on the flat half.
struct GameLinks: View {
    var game: CatalogGame
    /// The row's available width and the width both links need side by side. FlowLayout reported one row's height
    /// when asked with no width and then wrapped when placed, so the second link landed under the chip row
    /// (Open and Book, std, r052-contents-chips-overlap). Here the stack is chosen from measured widths, so the
    /// height always belongs to the layout that is drawn; until measured it is the tall, safe one.
    @State private var available: CGFloat = 0
    @State private var needed: CGFloat = .infinity
    var body: some View {
        let links = game.igdbID.flatMap { GameInfoStore.shared.basics[$0] }?.links
        if links?.official != nil || links?.patchNotes != nil {
            let layout = needed <= available ? AnyLayout(HStackLayout(spacing: 24)) : AnyLayout(VStackLayout(alignment: .leading, spacing: 0))
            layout { items(links) }
                .frame(maxWidth: .infinity, alignment: .leading)
                .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { available = $0 }
                .background(
                    HStack(spacing: 24) { items(links) }
                        .fixedSize()
                        .hidden()
                        .accessibilityHidden(true)
                        .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { needed = $0 }
                )
                .font(PlayscribeFont.subheadline)
                .foregroundStyle(PlayscribeColor.accent)
        }
    }

    @ViewBuilder private func items(_ links: GameBasics.Links?) -> some View {
        if let url = links?.official {
            Link(destination: url) { Label("Official website", systemImage: "arrow.up.right.square").frame(minHeight: 44).contentShape(Rectangle()) }.tappableFrame()
        }
        if let url = links?.patchNotes {
            Link(destination: url) { Label(LinkHost.label("All patch notes", url), systemImage: "arrow.up.right.square").frame(minHeight: 44).contentShape(Rectangle()) }.tappableFrame().accessibilityHint("Opens in browser")
        }
    }
}

/// Tabletop: the genres line under the title (Iris, bug-tabletop-game-details-missing). Whole words, wraps, hidden with no genres.
struct GameGenresLine: View {
    var game: CatalogGame
    var body: some View {
        let info = game.igdbID.flatMap { GameInfoStore.shared.basics[$0] }
        let genres = info?.genres ?? game.igdbID.flatMap { UpcomingStore.shared.extras[$0] }?.genres ?? []
        if !genres.isEmpty {
            Text(genres.joined(separator: ", ")).font(PlayscribeFont.subheadline).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

/// Tabletop's end of the lower panel, after Contents: About (three lines, More in place), the link rows, You might also like.
struct TabletopGameTail: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var open = false
    @State private var storyOpen = false
    var game: CatalogGame
    var body: some View {
        let info = game.igdbID.flatMap { GameInfoStore.shared.basics[$0] }
        let summary = info?.summary ?? game.igdbID.flatMap { UpcomingStore.shared.extras[$0] }?.summary
        VStack(alignment: .leading, spacing: 14) {
            if let summary {
                Text("About").font(PlayscribeFont.headline).accessibilityAddTraits(.isHeader)
                if open { LinkedTextView(text: summary).font(PlayscribeFont.body) }
                else { WholeWordText(text: LinkedText.clean(summary), font: PlayscribeFont.body, lines: 3, color: nil) }
                Button(open ? "Less" : "More") {
                    if reduceMotion { open.toggle() } else { withAnimation(.snappy) { open.toggle() } }
                }
                .font(PlayscribeFont.subheadline.weight(.semibold)).frame(minWidth: 44, minHeight: 44).contentShape(Rectangle()).tappableFrame()
                .accessibilityIdentifier("aboutMore")
            }
            // Story, as the Page's About section carries it in every other pose (PP-1: Closed had it, Tabletop did not).
            if let story = info?.storyline {
                Text("Story").font(PlayscribeFont.headline).accessibilityAddTraits(.isHeader)
                if storyOpen { LinkedTextView(text: story).font(PlayscribeFont.body) }
                else { WholeWordText(text: LinkedText.clean(story), font: PlayscribeFont.body, lines: 4, color: nil) }
                Button(storyOpen ? "Less" : "More") {
                    if reduceMotion { storyOpen.toggle() } else { withAnimation(.snappy) { storyOpen.toggle() } }
                }
                .font(PlayscribeFont.subheadline.weight(.semibold)).frame(minWidth: 44, minHeight: 44).contentShape(Rectangle()).tappableFrame()
                .accessibilityIdentifier("storyMore")
            }
            GameLinks(game: game)
            SimilarGamesRow(game: game, limit: 3)
        }
        .padding(.top, 4)
        .task(id: game.igdbID) { if let id = game.igdbID { await GameInfoStore.shared.load(igdbID: id) } }
    }
}

struct GameBasicsView: View {
    /// The game's trailers as About lists them: up to three, one per title (the feed can carry two cuts named "Launch
    /// Trailer"). Also Tabletop's stage tile and "Play trailer" (bug-tabletop-trailer-tile-missing).
    @MainActor static func trailers(_ game: CatalogGame) -> [GameBasics.Video] {
        let info = game.igdbID.flatMap { GameInfoStore.shared.basics[$0] }
        let fallback = game.igdbID.flatMap { UpcomingStore.shared.extras[$0] }
        let videos = info?.videos ?? fallback?.trailerId.map { [GameBasics.Video(youtubeId: $0, name: "Trailer")] } ?? []
        let unique = videos.reduce(into: [GameBasics.Video]()) { out, v in if !out.contains(where: { $0.name == v.name }) { out.append(v) } }
        return Array(unique.prefix(3))
    }

    @Environment(\.duo) private var duo
    @Environment(\.dynamicTypeSize) private var typeSize
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
        let videos = Self.trailers(game)
        VStack(alignment: .leading, spacing: 14) {
            if let move = fallback?.move?.line {
                Text(move).font(PlayscribeFont.subheadline.weight(.semibold)).foregroundStyle(PlayscribeColor.accent)
            }
            if !genres.isEmpty {
                Text(genres.joined(separator: ", ")).font(PlayscribeFont.subheadline).foregroundStyle(.secondary)
            }
            if !videos.isEmpty {
                ForEach(videos, id: \.youtubeId) { v in
                    Button { model.trailer = (v.youtubeId, v.name) } label: {
                        // At accessibility sizes the thumbnail sits above the title, so the title has the whole column and a word
                        // like "Cinematic" is not cut by letter beside a 112 pt picture (Iris, r054 Closed AX5).
                        let layout = typeSize.isAccessibilitySize ? AnyLayout(VStackLayout(alignment: .leading, spacing: 8)) : AnyLayout(HStackLayout(spacing: 12))
                        layout {
                            AsyncImage(url: URL(string: "https://i.ytimg.com/vi/\(v.youtubeId)/mqdefault.jpg")) { $0.resizable().scaledToFill() } placeholder: { Color.ink1 }
                                .frame(width: 112, height: 63)
                                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                                .overlay { Image(systemName: "play.fill").foregroundStyle(.white) }
                            // Whole words only (G-8): a plain lineLimit cut "E3 2018 Open Be…" mid-word (The Crew 2, Closed AX5).
                            WholeWordText(text: v.name, font: PlayscribeFont.subheadline, lines: typeSize.isAccessibilitySize ? 4 : 2)
                            if !typeSize.isAccessibilitySize { Spacer(minLength: 0) }
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
                // Collapsed: four lines ending on a whole word (G-8), never "conflicts swe…". Open: the full text with its links.
                if storyOpen { LinkedTextView(text: story).font(PlayscribeFont.body) }
                else { WholeWordText(text: LinkedText.clean(story), font: PlayscribeFont.body, lines: 4, color: nil) }
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
    @Environment(\.dynamicTypeSize) private var typeSize
    var game: CatalogGame
    /// Tabletop shows up to 3 (Iris, bug-tabletop-game-details-missing); AX3 and up as a vertical list of 55 pt rows.
    var limit = 8
    @State private var choosing: CatalogGame?

    private var games: [CatalogGame] {
        let inLibrary = Set(model.data.collection.compactMap { model.game($0.gameID)?.igdbID })
        let similar = game.igdbID.flatMap { GameInfoStore.shared.basics[$0] }?.similar ?? []
        return similar.compactMap { s -> CatalogGame? in
            guard s.igdbId != game.igdbID, !inLibrary.contains(s.igdbId),
                  let e = PS5Index.shared.entry(igdb: s.igdbId) else { return nil }
            return PS5Index.shared.game(e)
        }.prefix(limit).map { $0 }
    }

    var body: some View {
        let list = games
        if !list.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                Text("You might also like").font(PlayscribeFont.headline).accessibilityAddTraits(.isHeader)
                if typeSize >= .accessibility3 && limit < 8 {
                    VStack(alignment: .leading, spacing: 8) {
                        ForEach(list) { g in
                            Button { choosing = g } label: {
                                HStack(spacing: 12) {
                                    TileCover(game: g).frame(width: 42, height: 56)
                                    WholeWordText(text: g.name, font: PlayscribeFont.subheadline, lines: 4)
                                    Spacer(minLength: 0)
                                }
                                .frame(maxWidth: .infinity, minHeight: 56, alignment: .leading).contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel(g.name)
                            .accessibilityHint("View it, or choose how to add it")
                            .tappableFrame()
                        }
                    }
                } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 10) {
                        ForEach(list) { g in
                            Button { choosing = g } label: {
                                TileCover(game: g).frame(width: 104, height: 139)
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel(g.name)
                            .accessibilityHint("View it, or choose how to add it")
                            .tappableFrame()
                        }
                    }
                }
                .edgeFade(40)
                }
            }
            .confirmationDialog(choosing?.name ?? "", isPresented: Binding(get: { choosing != nil }, set: { if !$0 { choosing = nil } }), titleVisibility: .visible) {
                if let g = choosing {
                    // A plain look first (Terry, 0.5.4): opens the game page without filing it anywhere.
                    Button("View game") { model.browseGame(g) }
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
    @Environment(\.duo) private var duo
    @AppStorage(VideoReflection.key) private var reflectionMode = VideoReflection.defaultOn
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    var body: some View {
        NavigationStack {
            // R-11 (Iris, 13 Nov): the player is always 16:9 and sized to the open area, the width of the area or, where the area is
            // short (the Tabletop lower half), as wide as the height allows after a two-line caption. Centred, with the caption
            // centred under it. In Tabletop only, the live video is mirrored under it (Terry, 14 Nov).
            let mirror = VideoReflection.shows(pose: duo.pose, setting: reflectionMode, reduceMotion: reduceMotion, reduceTransparency: reduceTransparency)
            let live = mirror && controller?.started == true
            GeometryReader { geo in
                // Room kept under the video: a two-line caption (64 pt) and the reflection's 120 pt fade.
                let captionRoom: CGFloat = 64 + 120
                let h = max(0, min(geo.size.width * 9 / 16, geo.size.height - captionRoom))
                let w = h * 16 / 9
                VStack(spacing: 0) {
                    Color.black.frame(width: w, height: h)
                        .overlay { if let controller { MirroredVideoSurface(webView: controller.webView, mirrored: live) } }
                        .frame(maxWidth: .infinity)
                    VStack(spacing: 0) {
                        Text(name).font(PlayscribeFont.headline)
                            .multilineTextAlignment(.center)
                            .overMirror(mirror)
                            .padding(.horizontal, 16).padding(.top, 12)
                        Spacer(minLength: 0)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                    // R-11: the mirror lands flush under the video and shows through this fade, under the caption. It takes no
                    // layout room and no touches.
                    .background(alignment: .top) { if live { MirrorFade() } else { Color.black } }
                    .clipped()
                }
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
    @Environment(\.duo) private var duo
    @Environment(\.railWidth) private var railWidth
    @AppStorage(ReadingSide.key) private var pageOnLeft = false
    @State private var position = ScrollPosition(idType: String.self)
    var gameID: String

    var body: some View {
        ScrollView {
            ContentsBody(gameID: gameID)
                // Book: the edge that faces the hinge keeps 24 pt clear of the division band (r054-book-gamepage-hinge-inset).
                .padding(.leading, duo.hingeInset(16, facingHinge: pageOnLeft))
                .padding(.trailing, duo.hingeInset(16, facingHinge: !pageOnLeft))
                .padding(.vertical, 14)
                .padding(.trailing, railWidth)
        }
        // Tabletop only, as the Library shelf (#487): scrolled, the lower half's top edge cut a Contents row through its glyphs at
        // AX5 (Iris, 21efef8 still: "Better targeting, look-on…"). The panel is ink1, so the edge is too.
        .modifier(ScrolledTopEdge(active: duo.pose == .tabletop, ink: Color.ink1))
        .clearsMessages()
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
    /// False in the stacked book, where the Page header already carries it (the Contents sit far below the update).
    var addControl = true

    var body: some View {
        let game = model.game(gameID)
        let chapter = model.chapters(gameID).contains(model.nav.chapter) ? model.nav.chapter : .updates
            VStack(alignment: .leading, spacing: 14) {
                if duo.pose != .closed { HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 4) {
                        GameTitleWithStatus(gameID: gameID, name: model.gameDisplayName(gameID))
                    }
                    Spacer(minLength: 8)
                } }
                // Once per page (Terry): closed, the links sit with the game's basics instead.
                if duo.pose != .closed && duo.pose != .tabletop, let game { GameLinks(game: game) }
                // Tabletop (Iris, bug-tabletop-game-details-missing): genres under the title; About, links and similar games at the end.
                if duo.pose == .tabletop, let game { GameGenresLine(game: game) }
                if addControl, model.entry(gameID) == nil, let game {
                    Button("Add to library") { model.addGame(game, status: .watching) }
                        .buttonStyle(.borderedProminent).foregroundStyle(PlayscribeColor.onAccent).hitTarget()
                }
                // A game with no notes has no outline, so its Play trailer row sits here, above the chips (Iris order: trailer first).
                if duo.pose == .tabletop, model.ps5Releases(gameID).isEmpty, model.pcOnlyReleases(gameID).isEmpty {
                    TabletopTrailerRow(gameID: gameID)
                }
                ChapterBar(gameID: gameID, selected: chapter)
                // Tabletop, a game with no notes: search, the A to Z strip and Previous/Next have nothing to act on (Quinn, #426),
                // so they are not drawn; the list below says why there is nothing (NoUpdatesLine).
                let tabletopNoNotes = duo.pose == .tabletop && model.ps5Releases(gameID).isEmpty && model.pcOnlyReleases(gameID).isEmpty
                if !tabletopNoNotes { NotesSearchField(gameID: gameID) }
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
                    if duo.pose == .tabletop, !tabletopNoNotes {
                        TabletopOutline(gameID: gameID)
                    }
                    ReleaseTimeline(gameID: gameID)
                    if duo.pose == .tabletop, let game { TabletopGameTail(game: game) }
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
    @Environment(\.dynamicTypeSize) private var typeSize
    var gameID: String
    /// At accessibility sizes the placeholder is the short "Search notes" (Iris, r054 Tabletop AX5): "Search this game's n…" was cut
    /// mid-word. Standard sizes keep the scoped wording.
    private var prompt: String {
        if typeSize.isAccessibilitySize { return "Search notes" }
        return model.noteScope == .thisGame ? "Search this game's notes" : "Search all my games' notes"
    }
    var body: some View {
        @Bindable var model = model
        if duo.pose == .tabletop {
            // Tabletop: no keyboard; a read-only button and an A to Z strip (Iris, 0.2.0 ruling).
            VStack(alignment: .leading, spacing: 8) {
                TabletopSearch(letter: $model.noteLetter, prompt: prompt)
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
                TextField(prompt, text: $model.noteQuery)
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
                // Tabletop's lower half: the Page is the view-only stage above, so this list is where a reader looks for why there
                // is nothing (untracked: "We don't track this game's updates yet."; tracked: "No updates yet." and Checked).
                if pc.isEmpty, duo.pose == .tabletop { NoUpdatesLine(gameID: gameID).padding(.top, 2) }
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
        .readToggleActions(r)
    }
}

/// TT-2 in the Contents: the section outline with Previous and Next.
/// R-11: "Play trailer", first row of Tabletop's lower panel, for every game (also one with no notes, which has no outline).
struct TabletopTrailerRow: View {
    @Environment(AppModel.self) private var model
    var gameID: String
    var body: some View {
        Group {
            if let g = model.game(gameID), let v = GameBasicsView.trailers(g).first {
                Button { model.trailer = (v.youtubeId, v.name) } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "play.fill").accessibilityHidden(true)
                        Text("Play trailer").font(PlayscribeFont.subheadline.weight(.semibold))
                            .fixedSize(horizontal: false, vertical: true)
                        Spacer(minLength: 0)
                    }
                    .foregroundStyle(PlayscribeColor.accent)
                    .padding(.horizontal, 10).frame(maxWidth: .infinity, minHeight: 44).contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Play trailer")
                .accessibilityIdentifier("playTrailer")
                .tappableFrame()
            }
        }
        // The trailer list comes from the game's basics, which About loads when it appears. About is not on the Tabletop stage,
        // so this row loads them itself, or "Play trailer" and the stage tile never show (Mac, #486 at a2eeb67).
        .task(id: model.game(gameID)?.igdbID) {
            if let id = model.game(gameID)?.igdbID { await GameInfoStore.shared.load(igdbID: id) }
        }
    }
}

struct TabletopOutline: View {
    @State private var fullText = false
    @Environment(AppModel.self) private var model
    var gameID: String
    var body: some View {
        let sections = model.readerRelease(gameID).map(model.readerSections) ?? []
        let index = min(model.readerIndex[gameID] ?? 0, max(0, sections.count - 1))
        VStack(spacing: 2) {
            TabletopTrailerRow(gameID: gameID).padding(.bottom, 4)
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
        .clearsMessages()
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
        // Accessibility sizes: the title wraps on whole words and the status glyph sits inline right after the last word,
        // wrapping with it (Iris on #289: never on a line of its own, and "Deliverance" is never cut mid-word).
        // The title text stops growing at AX3: at AX5 one long word is wider than a Closed portrait column.
        if typeSize.isAccessibilitySize { return AnyView(inlineTitleRow) }
        return AnyView(HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(name.gluingTrailingNumeral).font(PlayscribeFont.title2).lineLimit(2)
                .fixedSize(horizontal: false, vertical: true).accessibilityAddTraits(.isHeader)
                .dynamicTypeSize(...DynamicTypeSize.accessibility3)
            statusMenu
        })
    }

    private var inlineTitleRow: some View {
        let words = name.gluingTrailingNumeral.split(separator: " ", omittingEmptySubsequences: true).map(String.init)
        return WordFlow(hSpacing: 8, vSpacing: 0) {
            ForEach(Array(words.enumerated()), id: \.offset) { i, w in
                if i == words.count - 1 {
                    HStack(alignment: .firstTextBaseline, spacing: 0) {
                        Text(w).font(PlayscribeFont.title2).accessibilityHidden(true)
                        statusMenu
                    }
                } else {
                    Text(w).font(PlayscribeFont.title2).accessibilityHidden(true)
                }
            }
        }
        .dynamicTypeSize(...DynamicTypeSize.accessibility3)
        .background(Color.clear.accessibilityElement().accessibilityLabel(name).accessibilityAddTraits(.isHeader))
    }

    @ViewBuilder private var statusMenu: some View {
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

    static func symbol(_ s: OwnershipStatus) -> String {
        switch s { case .owned: "checkmark.circle.fill"; case .wishlist: "bookmark.fill"; case .watching: "eye.fill" }
    }
}


/// J-11: the game's links as sheet rows, Tabletop only (the inline row stays in every other pose).
struct LinksSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.panelClose) private var panelClose
    var gameID: String

    struct Row: Identifiable { var id: String; var title: String; var url: URL }

    private var rows: [Row] { Self.rows(model, gameID) }

    static func rows(_ model: AppModel, _ gameID: String) -> [Row] {
        var out: [Row] = []
        if let game = model.game(gameID) {
            let links = game.igdbID.flatMap { GameInfoStore.shared.basics[$0] }?.links
            if let u = links?.official { out.append(Row(id: "official", title: "Official website", url: u)) }
            if let u = links?.patchNotes { out.append(Row(id: "notes", title: LinkHost.label("All patch notes", u), url: u)) }
            // The empty Gallery's "Find trailers online" is view-only text in Tabletop (nothing tappable on the stage), so its
            // control lives here, in the lower half, as "Official website" does (0.5.5, r054-tabletop-find-trailers).
            if model.gallery(gameID).isEmpty, let u = GalleryEmpty.trailerSearchURL(game.name) {
                out.append(Row(id: "trailers", title: "Find trailers online", url: u))
            }
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
        // One log line per opened row, so a QA run can confirm the tap reached the system (#493: the simulator showed black).
        .environment(\.openURL, OpenURLAction { url in
            Logger(subsystem: "co.codeconnectors.playscribe", category: "links").info("links open: \(url.host() ?? "?", privacy: .public)")
            return .systemAction
        })
    }

    static func hasLinks(_ model: AppModel, _ gameID: String) -> Bool { !rows(model, gameID).isEmpty }
}


/// Words flowing left to right and wrapping at the proposed width; a word wider than the width gets its own line.
/// One subview per word (the caller uses ForEach), so the last one can carry an inline glyph.
struct WordFlow: Layout {
    var hSpacing: CGFloat = 8
    var vSpacing: CGFloat = 0
    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        place(proposal.width ?? .infinity, subviews).size
    }
    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        for (i, p) in place(bounds.width, subviews).points.enumerated() {
            subviews[i].place(at: CGPoint(x: bounds.minX + p.x, y: bounds.minY + p.y), proposal: .unspecified)
        }
    }
    private func place(_ width: CGFloat, _ subviews: Subviews) -> (points: [CGPoint], size: CGSize) {
        var points: [CGPoint] = [], x: CGFloat = 0, y: CGFloat = 0, row: CGFloat = 0, maxX: CGFloat = 0
        for v in subviews {
            let s = v.sizeThatFits(.unspecified)
            if x > 0 && x + s.width > width { x = 0; y += row + vSpacing; row = 0 }
            points.append(CGPoint(x: x, y: y))
            x += s.width + hSpacing; row = max(row, s.height); maxX = max(maxX, x - hSpacing)
        }
        return (points, CGSize(width: maxX, height: y + row))
    }
}
