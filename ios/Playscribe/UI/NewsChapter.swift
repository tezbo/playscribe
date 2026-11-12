import SwiftUI

/// Official news headlines per game (0.5.0 item 17, PR 1): title, date, "Official", opens in the
/// default browser. Headlines only; no source names, no article text.
struct NewsItem: Codable, Hashable, Identifiable {
    var title: String
    var date: Date?
    var url: URL
    /// "official" (the studio's own post) or "reported" (a press headline). The tag says which; there is no source name.
    var verification: String?
    var id: String { url.absoluteString }
    var isReported: Bool { verification == "reported" }
    var tagText: String { isReported ? "Reported" : "Official" }
}

@MainActor @Observable
final class NewsStore {
    static let shared = NewsStore()
    private(set) var items: [String: [NewsItem]] = [:]
    private(set) var failed: Set<String> = []
    private(set) var loaded: Set<String> = []
    @ObservationIgnored private var index: FeedClient.Index?

    private struct File: Decodable {
        var items: [NewsItem]
        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            // One malformed item never costs the list.
            var list = try c.nestedUnkeyedContainer(forKey: .items)
            var out: [NewsItem] = []
            while !list.isAtEnd { if let i = try? list.decode(NewsItem.self) { out.append(i) } else { _ = try? list.decode(Skip.self) } }
            items = out
        }
        enum CodingKeys: String, CodingKey { case items }
        struct Skip: Decodable {}
    }

    private static func cacheURL(_ id: String) -> URL { URL.cachesDirectory.appending(path: "news-\(id).json") }

    #if INTERNAL
    /// QA: `-qaNews` seeds sample headlines for every library game, so the News tab and chapters can be shot in every pose
    /// without a feed. Long and short titles, Official and Reported, so wrapping and tags show.
    static let qaSeeded = ProcessInfo.processInfo.arguments.contains("-qaNews")
    func seedQA(gameIDs: [String]) {
        guard Self.qaSeeded, !gameIDs.isEmpty else { return }
        let long = "A headline long enough to wrap onto a second and a third line beside the cover, so the row shows how it behaves in every pose"
        for (g, id) in gameIDs.enumerated() {
            items[id] = (0..<3).map { i in
                let n = g * 3 + i
                return NewsItem(title: n.isMultiple(of: 2) ? "Sample studio post \(n): \(long)" : "Sample headline \(n)",
                                date: .now.addingTimeInterval(-Double(n) * 86_400), url: URL(string: "https://example.com/\(n)")!,
                                verification: n.isMultiple(of: 3) ? "reported" : "official")
            }
            loaded.insert(id)
        }
    }
    #endif

    func load(gameID: String, igdbID: Int?) async {
        #if INTERNAL
        if Self.qaSeeded { return }
        #endif
        failed.remove(gameID)
        if items[gameID] == nil, let raw = try? Data(contentsOf: Self.cacheURL(gameID)),
           let f = try? JSONCoding.decoder.decode(File.self, from: raw) { items[gameID] = f.items }
        if index == nil { index = (try? await FeedClient.fetch("index.json", as: FeedClient.Index.self))?.0 }
        guard let entry = index?.games.first(where: { $0.id == gameID }) ?? index?.games.first(where: { igdbID != nil && $0.igdbId == igdbID }) else {
            if index == nil { failed.insert(gameID) } else { items[gameID] = items[gameID] ?? [] }
            loaded.insert(gameID)
            return
        }
        if let (file, raw) = try? await FeedClient.fetch("news/\(entry.id).json", as: File.self) {
            try? raw.write(to: Self.cacheURL(gameID), options: .atomic)
            items[gameID] = file.items
        } else if items[gameID] == nil {
            failed.insert(gameID)
        }
        loaded.insert(gameID)
    }
}

extension View {
    /// Reports the frame to the fold audit only where the control can be touched. In Tabletop every chapter but
    /// What's new sits on the standing half, which is view only (G-4, TT-1): nothing there is tappable.
    @ViewBuilder func tappableFrame(when touchable: Bool) -> some View {
        if touchable { tappableFrame() } else { self }
    }
}

struct NewsChapter: View {
    var gameID: String
    @Environment(AppModel.self) private var model
    @Environment(\.duo) private var duo
    @Environment(\.openURL) private var openURL
    private var store: NewsStore { .shared }

    var body: some View {
        let list = store.items[gameID] ?? []
        VStack(alignment: .leading, spacing: 12) {
            if list.isEmpty {
                if store.failed.contains(gameID) {
                    HStack {
                        Text("Couldn't load news. Check your connection and try again.").font(PlayscribeFont.subheadline).foregroundStyle(.secondary)
                        Spacer(minLength: 0)
                        Button { Task { await store.load(gameID: gameID, igdbID: model.game(gameID)?.igdbID) } } label: { Text("Retry").frame(minWidth: 44, minHeight: 44).contentShape(Rectangle()) }
                            .font(PlayscribeFont.subheadline.weight(.semibold)).foregroundStyle(PlayscribeColor.accent)
                            .tappableFrame(when: duo.pose != .tabletop)
                            .accessibilityHidden(duo.pose == .tabletop)  // view only on the standing half
                    }
                } else if !store.loaded.contains(gameID) {
                    HStack(spacing: 10) {
                        ProgressView()
                        Text("Loading news").font(PlayscribeFont.subheadline).foregroundStyle(.secondary)
                    }
                    .frame(minHeight: 44)
                    .accessibilityElement(children: .combine)
                } else {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("No news yet").font(PlayscribeFont.headline)
                        Text("Headlines about this game will appear here.").font(PlayscribeFont.subheadline).foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 20)
                }
            }
            ForEach(list.prefix(20)) { item in
                let row = VStack(alignment: .leading, spacing: 4) {
                    Text(item.title).font(PlayscribeFont.headline).multilineTextAlignment(.leading)
                    HStack(spacing: 8) {
                        if let d = item.date { Text(d.formatted(.dateTime.day().month(.abbreviated).year())) }
                        Tag(text: item.tagText)
                    }
                    .font(PlayscribeFont.caption).foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                .contentShape(Rectangle())
                if duo.pose == .tabletop {
                    // View only means no touch, never hidden from VoiceOver (Iris, 7 Nov): the headline is read as text, in order,
                    // and is not a link here (no Button, no link trait, no hint), so there is no action to activate.
                    row.accessibilityElement(children: .combine)
                } else {
                    Button { openURL(item.url) } label: { row }
                        .buttonStyle(.plain)
                        .tappableFrame()
                        .accessibilityAddTraits(.isLink)
                        .accessibilityHint("Opens in your browser")
                }
            }
        }
        .task(id: gameID) { await store.load(gameID: gameID, igdbID: model.game(gameID)?.igdbID) }
    }
}

/// The News tab (Terry, 9 Nov): headlines about the games in the library, newest first, from the studios' own posts and the
/// press. One row per story, a cover and the game's name, "Official" or "Reported" (V-3: never an outlet name). No game takes
/// the page: each is capped, so a run of near-identical posts from one franchise cannot push every other game out.
struct NewsView: View {
    static let perGameCap = 3
    static let totalCap = 60
    @Environment(AppModel.self) private var model
    @Environment(\.railWidth) private var railWidth
    @Environment(\.duo) private var duo
    private var store: NewsStore { .shared }

    private var ids: [String] { model.data.collection.map(\.gameID) }

    /// Newest first across the library, at most `perGameCap` per game, the same story (same words) listed once per game.
    static func merge(_ perGame: [(game: String, items: [NewsItem])]) -> [(game: String, item: NewsItem)] {
        var out: [(game: String, item: NewsItem)] = []
        for (game, items) in perGame {
            var seen = Set<String>()
            for item in items.sorted(by: { ($0.date ?? .distantPast) > ($1.date ?? .distantPast) }) {
                let key = item.title.lowercased().filter { $0.isLetter || $0.isNumber }
                guard seen.insert(key).inserted else { continue }
                out.append((game, item))
                if seen.count >= perGameCap { break }
            }
        }
        return Array(out.sorted { ($0.item.date ?? .distantPast) > ($1.item.date ?? .distantPast) }.prefix(totalCap))
    }

    private var posts: [(game: String, item: NewsItem)] {
        Self.merge(ids.map { ($0, store.items[$0] ?? []) })
    }

    private var stillLoading: Bool { ids.contains { !store.loaded.contains($0) } }
    /// The "News" title's bottom edge in screen space (Tabletop): the stage caption starts below it (Iris, AX5).
    @State private var titleBottom: CGFloat = 0

    var body: some View {
        let all = posts
        // Tabletop: the newest story is the stage on the standing half (art and headline, view only); the list on the flat half
        // starts from the second, so no story is shown twice.
        let lead: (game: String, item: NewsItem)? = duo.pose == .tabletop && all.count > 1 ? all.first : nil
        let list = lead == nil ? all : Array(all.dropFirst())
        let badgeExtra = duo.occlusions.filter { $0.minY < 190 && $0.maxY > 40 }
            .map { max(0, duo.size.width - $0.minX) }.max() ?? 0
        Group {
            if ids.isEmpty {
                ContentUnavailableView {
                    Label("News for your games will appear here", systemImage: "newspaper")
                } actions: {
                    Button("Add a game") { model.nav.tab = .library }.buttonStyle(.borderedProminent).foregroundStyle(PlayscribeColor.onAccent)
                }
            } else if list.isEmpty {
                // Never a blank page: loading, then the empty copy, or Retry when nothing could be fetched.
                VStack(spacing: 12) {
                    if stillLoading {
                        ProgressView()
                        Text("Loading news").font(PlayscribeFont.subheadline).foregroundStyle(.secondary)
                    } else if ids.contains(where: { store.failed.contains($0) }) {
                        Text("Couldn't load news. Check your connection and try again.").font(PlayscribeFont.subheadline).foregroundStyle(.secondary).multilineTextAlignment(.center)
                        Button { Task { await load() } } label: { Text("Retry").frame(minWidth: 44, minHeight: 44).contentShape(Rectangle()) }
                            .font(PlayscribeFont.subheadline.weight(.semibold)).foregroundStyle(PlayscribeColor.accent)
                            .tappableFrame(when: duo.pose != .tabletop)
                            .accessibilityHidden(duo.pose == .tabletop)
                    } else {
                        Text("No news yet").font(PlayscribeFont.headline)
                        Text("Headlines about your games will appear here.").font(PlayscribeFont.subheadline).foregroundStyle(.secondary).multilineTextAlignment(.center)
                    }
                }
                .padding(24)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .accessibilityElement(children: .combine)
            } else if duo.pose == .book, let fold = duo.division {
                // TT-0: in the book pose the rows are cards on either page, never across the fold.
                ScrollView {
                    // Each card's inner edge is 24 pt from the hinge band (Iris, Book): 16 pt page padding plus 24, and the band column
                    // takes 24 on either side.
                    LazyVGrid(columns: [GridItem(.fixed(max(0, fold.minX - 40)), spacing: 0, alignment: .top),
                                        GridItem(.fixed(fold.width + 48), spacing: 0),
                                        GridItem(.flexible(), spacing: 0, alignment: .top)],
                              alignment: .leading, spacing: 12) {
                        ForEach(Array(list.enumerated()), id: \.element.item.id) { i, post in
                            NewsRow(gameID: post.game, item: post.item)
                                .padding(12)
                                .background(PlayscribeColor.ink700.opacity(0.5), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                            if i.isMultiple(of: 2) { Color.clear.frame(height: 1).accessibilityHidden(true) }
                        }
                    }
                    .padding(.horizontal, 16)
                }
                .clearsMessages()
                .frame(width: duo.size.width)
            } else {
                List {
                    ForEach(list, id: \.item.id) { post in NewsRow(gameID: post.game, item: post.item) }
                }
                .padding(.trailing, railWidth + (duo.pose == .tabletop ? 0 : badgeExtra))
                .clearsMessages()
                .refreshable { await load(force: true) }
            }
        }
        // Tabletop: the list lives on the flat half; the standing half only titles it (G-4, TT-0).
        .frame(maxHeight: duo.pose == .tabletop ? max(0, duo.size.height - (duo.division?.maxY ?? 0)) : .infinity)
        .frame(maxHeight: .infinity, alignment: .bottom)
        .background(alignment: .top) {
            if let lead, let fold = duo.division {
                NewsStage(gameID: lead.game, item: lead.item, bandTop: fold.minY, titleBottom: titleBottom)
                    .ignoresSafeArea(edges: .top).allowsHitTesting(false)
            }
        }
        .overlay(alignment: .topLeading) {
            if duo.pose == .tabletop {
                Text("News").font(PlayscribeFont.largeTitle).padding(24).allowsHitTesting(false)
                    .onGeometryChange(for: CGFloat.self) { $0.frame(in: .global).maxY } action: { titleBottom = $0 }
            }
        }
        .navigationTitle("News")
        .task(id: ids) {
            #if INTERNAL
            store.seedQA(gameIDs: ids)
            #endif
            await load()
        }
    }

    private func load(force: Bool = false) async {
        for id in ids.prefix(40) where force || !store.loaded.contains(id) || store.failed.contains(id) {
            await NewsStore.shared.load(gameID: id, igdbID: model.game(id)?.igdbID)
        }
    }
}

struct NewsRow: View {
    var gameID: String
    var item: NewsItem
    @Environment(AppModel.self) private var model
    @Environment(\.openURL) private var openURL
    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        let g = model.game(gameID)
        let game = g?.name ?? ""
        Button { openURL(item.url) } label: {
            let layout = typeSize.isAccessibilitySize ? AnyLayout(VStackLayout(alignment: .leading, spacing: 8)) : AnyLayout(HStackLayout(alignment: .top, spacing: 16))
            layout {
                if let g { CoverView(game: g, cornerRadius: 4).frame(width: 40) }
                VStack(alignment: .leading, spacing: 4) {
                    // Whole words then "…", never a cut word (G-8; Iris): 4 lines at accessibility sizes.
                    WholeWordText(text: item.title, font: PlayscribeFont.subheadline.weight(.semibold), lines: typeSize.isAccessibilitySize ? 4 : 3)
                    Text(game).font(PlayscribeFont.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                    // Chips wrap, never drop, at accessibility sizes.
                    ViewThatFits(in: .horizontal) {
                        HStack(spacing: 8) { meta }
                        VStack(alignment: .leading, spacing: 4) { meta }
                    }
                    .font(PlayscribeFont.caption).foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .tappableFrame()
        .accessibilityElement(children: .ignore)
        .accessibilityAddTraits(.isLink)
        .accessibilityLabel("\(game), \(item.title), \(item.tagText), opens in browser")
    }

    @ViewBuilder private var meta: some View {
        if let d = item.date { Text(d.formatted(.dateTime.day().month(.abbreviated).year())) }
        Tag(text: item.tagText)
    }
}

/// Tabletop's standing half of the News tab: the newest story's game art with its headline as the caption, view only (G-4, J-13).
/// The art and scrim are the Library hero's (DeckStage), so the crop and the logo read the same (Iris). The caption sits below
/// the "News" title and ends 24 pt above the band; the headline takes the lines that fit between them, whole words then "…".
struct NewsStage: View {
    @Environment(\.dynamicTypeSize) private var typeSize
    @Environment(AppModel.self) private var model
    var gameID: String
    var item: NewsItem
    /// The division band's top edge in screen space.
    var bandTop: CGFloat
    /// The "News" title's bottom edge in screen space (padding included).
    var titleBottom: CGFloat = 0
    /// The stage's top edge in screen space: the stage is `bandTop` minus this tall, so its bottom edge is exactly on the band.
    @State private var stageTop: CGFloat = 0
    @State private var lineHeight: CGFloat = 0
    @State private var metaHeight: CGFloat = 0

    var body: some View {
        let game = model.game(gameID)
        let stageHeight = max(0, bandTop - stageTop)
        // Room for the headline: under the title, 24 pt above the band, inside the panel's 24 pt of padding, above the meta row.
        let room = stageHeight - max(0, titleBottom - stageTop) - 24 - 24 - 4 - metaHeight
        let maxLines = typeSize.isAccessibilitySize ? 4 : 2
        let lines = lineHeight > 0 && stageHeight > 0 ? max(1, min(maxLines, Int(room / lineHeight))) : maxLines
        ZStack(alignment: .bottomLeading) {
            ArtView(asset: game?.keyArtAsset, game: game)
            LinearGradient(stops: typeSize.isAccessibilitySize
                               ? [.init(color: .clear, location: 0.1), .init(color: PlayscribeColor.ink950.opacity(0.9), location: 0.4)]
                               : [.init(color: .clear, location: 0.3), .init(color: PlayscribeColor.ink950.opacity(0.8), location: 0.75)],
                           startPoint: .top, endPoint: .bottom)
            VStack(alignment: .leading, spacing: 4) {
                WholeWordText(text: item.title, font: PlayscribeFont.title3.weight(.semibold), lines: lines)
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 8) { meta(game) }
                    VStack(alignment: .leading, spacing: 4) { meta(game) }
                }
                .font(PlayscribeFont.caption)
                .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { metaHeight = $0 }
            }
            .background(alignment: .topLeading) {
                Text("Ag").font(PlayscribeFont.title3.weight(.semibold)).hidden().accessibilityHidden(true)
                    .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { lineHeight = $0 }
            }
            // Iris: the whole caption on one solid ink panel, so contrast never depends on the art.
            .padding(12)
            .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(PlayscribeColor.ink700.opacity(0.7)))
            .padding(.horizontal, 24).padding(.bottom, 24)
            .padding(.trailing, TabletopRail.width)
        }
        .frame(height: stageHeight)
        .background(alignment: .top) {
            Color.clear.frame(height: 1)
                .onGeometryChange(for: CGFloat.self) { $0.frame(in: .global).minY } action: { if abs($0 - stageTop) > 0.5 { stageTop = $0 } }
        }
        .clipped()
        // View only, and read by VoiceOver as one caption (the same story is not in the list below).
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(game?.name ?? ""), \(item.title), \(item.tagText)")
    }

    @ViewBuilder private func meta(_ game: CatalogGame?) -> some View {
        Tag(text: item.tagText)
        if let game { Text(game.name) }
        if let d = item.date { Text(d.formatted(.dateTime.day().month(.abbreviated).year())) }
    }
}

/// Tabletop's standing half for a game's News chapter: the game's art to the fold, with its newest headline as the caption.
/// View only (G-4); the headlines themselves are in the lower half (ContentsBody).
struct NewsStageArt: View {
    @Environment(\.dynamicTypeSize) private var typeSize
    @Environment(AppModel.self) private var model
    @Environment(\.duo) private var duo
    @State private var stageBottom: CGFloat = 0
    var gameID: String

    var body: some View {
        let game = model.game(gameID)
        let newest = (NewsStore.shared.items[gameID] ?? []).max { ($0.date ?? .distantPast) < ($1.date ?? .distantPast) }
        ZStack(alignment: .bottomLeading) {
            ArtView(asset: model.backdrop(gameID, chapter: .news, tall: false), game: game).ignoresSafeArea()
            LinearGradient(colors: [.clear, .black.opacity(0.5)], startPoint: .center, endPoint: .bottom)
            VStack(alignment: .leading, spacing: 4) {
                Text(game?.name ?? "").font(PlayscribeFont.subheadline.weight(.semibold)).foregroundStyle(PlayscribeColor.accent)
                if let newest { WholeWordText(text: newest.title, font: PlayscribeFont.title3.weight(.semibold), lines: typeSize.isAccessibilitySize ? 4 : 2) }
            }
            // Iris: the whole caption on one solid ink panel; it ends 24 pt above the band.
            .padding(12)
            .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(PlayscribeColor.ink700.opacity(0.7)))
            .padding(.horizontal, 24).padding(.bottom, max(24, duo.clearance(forBottom: stageBottom)))
            .padding(.trailing, TabletopRail.width)
        }
        // The stage's own frame (as the Reader stage does), not the art, which ignores the safe area.
        .background(Color.clear.onGeometryChange(for: CGFloat.self) { $0.frame(in: .global).maxY } action: { if abs($0 - stageBottom) > 0.5 { stageBottom = $0 } })
        .clipped()
        .accessibilityHidden(true)
    }
}
