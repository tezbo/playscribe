import SwiftUI

/// Official news headlines per game (0.5.0 item 17, PR 1): title, date, "Official", opens in the
/// default browser. Headlines only; no source names, no article text.
struct NewsItem: Codable, Hashable, Identifiable {
    var title: String
    var date: Date?
    var url: URL
    /// "official" (a studio's own post) or "reported" (anything else). Older files carry none: they only ever held studio posts.
    var kind: String?
    var id: String { url.absoluteString }
    var isReported: Bool { kind == "reported" }
    var tagText: String { isReported ? "Reported" : "Official" }
    /// At most 3 lines in a row: a long headline is cut at a clause (a comma, colon, dash or semicolon) when one falls
    /// late enough, else at a word.
    var shortTitle: String {
        let limit = 120
        guard title.count > limit else { return title }
        let head = String(title.prefix(limit))
        let clause = head.lastIndex(where: { ",;:–—".contains($0) }).flatMap { head.distance(from: head.startIndex, to: $0) >= 40 ? $0 : nil }
        let cut = clause.map { String(head[..<$0]) } ?? head.lastIndex(of: " ").map { String(head[..<$0]) } ?? head
        return cut.trimmingCharacters(in: CharacterSet(charactersIn: " ,;:-–—.")) + "…"
    }
}

extension NewsItem {
    /// A stage caption is at most 2 lines: a longer headline ends at a word with an ellipsis (the full headline opens on tap; Iris).
    var captionTitle: String {
        let limit = 80
        guard title.count > limit else { return title }
        let head = String(title.prefix(limit))
        let cut = head.lastIndex(of: " ").map { String(head[..<$0]) } ?? head
        return cut.trimmingCharacters(in: CharacterSet(charactersIn: " ,;:-–—.")) + "…"
    }
}

/// The verification tag: Official for studio posts, Reported otherwise. The only provenance shown.
struct NewsTag: View {
    var item: NewsItem
    var body: some View { Tag(text: item.tagText, tint: .secondary) }
}

@MainActor @Observable
final class NewsStore {
    static let shared = NewsStore()
    private(set) var items: [String: [NewsItem]] = [:]
    private(set) var failed: Set<String> = []
    private(set) var loaded: Set<String> = []
    @ObservationIgnored private var index: FeedClient.Index?

    fileprivate struct File: Decodable {
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

    /// The global feed (news.json): the newest headlines across every game, each with its feed game id.
    struct Headline: Hashable, Identifiable {
        var gameID: String
        var item: NewsItem
        var id: String { gameID + item.id }
    }
    private(set) var global: [Headline] = []
    private(set) var globalFailed = false
    private(set) var globalLoaded = false

    private struct GlobalFile: Decodable {
        struct Row: Decodable { var gameId: String; var title: String; var date: Date?; var url: URL; var kind: String? }
        var items: [Headline]
        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            var list = try c.nestedUnkeyedContainer(forKey: .items)
            var out: [Headline] = []
            // One malformed item never costs the list.
            while !list.isAtEnd {
                if let r = try? list.decode(Row.self) { out.append(Headline(gameID: r.gameId, item: NewsItem(title: r.title, date: r.date, url: r.url, kind: r.kind))) } else { _ = try? list.decode(File.Skip.self) }
            }
            items = out
        }
        enum CodingKeys: String, CodingKey { case items }
    }

    #if INTERNAL
    /// QA: `-qaNews` seeds sample headlines (global and per game) so layouts can be checked in every pose without a feed.
    static let qaSeeded = ProcessInfo.processInfo.arguments.contains("-qaNews")
    func seedQA(gameIDs: [String]) {
        guard Self.qaSeeded, !gameIDs.isEmpty else { return }
        let long = "A headline long enough to wrap onto a second and a third line beside the cover, so the row shows how it behaves in every pose"
        let list = (0..<14).map { i in
            Headline(gameID: gameIDs[i % gameIDs.count],
                     item: NewsItem(title: i.isMultiple(of: 2) ? "Sample studio post \(i): \(long)" : "Sample headline \(i)",
                                    date: .now.addingTimeInterval(-Double(i) * 86_400), url: URL(string: "https://example.com/\(i)")!, kind: i.isMultiple(of: 3) ? "reported" : "official"))
        }
        global = list; globalLoaded = true
        for id in gameIDs { items[id] = list.filter { $0.gameID == id }.map(\.item); loaded.insert(id) }
    }
    #endif

    func loadGlobal() async {
        #if INTERNAL
        if Self.qaSeeded { return }
        #endif
        if global.isEmpty, let raw = try? Data(contentsOf: Self.cacheURL("global")), let f = try? JSONCoding.decoder.decode(GlobalFile.self, from: raw) { global = f.items }
        if let (f, raw) = try? await FeedClient.fetch("news.json", as: GlobalFile.self) {
            try? raw.write(to: Self.cacheURL("global"), options: .atomic)
            global = f.items
            globalFailed = false
        } else if global.isEmpty {
            globalFailed = true
        }
        globalLoaded = true
    }

    private static func cacheURL(_ id: String) -> URL { URL.cachesDirectory.appending(path: "news-\(id).json") }

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
                            .tappableFrame()
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
                        Text("Official posts from the studio will appear here.").font(PlayscribeFont.subheadline).foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 20)
                }
            }
            ForEach(list.prefix(20)) { item in
                Link(destination: item.url) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(item.shortTitle).font(PlayscribeFont.headline).multilineTextAlignment(.leading).lineLimit(3)
                        HStack(spacing: 8) {
                            if let d = item.date { Text(d.formatted(.dateTime.day().month(.abbreviated).year())) }
                            NewsTag(item: item)
                        }
                        .font(PlayscribeFont.caption).foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                    .contentShape(Rectangle())
                }
                .tappableFrame()
            }
        }
        .task(id: gameID) {
            #if INTERNAL
            store.seedQA(gameIDs: model.data.collection.map(\.gameID))
            #endif
            await store.load(gameID: gameID, igdbID: model.game(gameID)?.igdbID)
        }
    }
}

/// Library "News" strip (0.5.0 item 17, PR 2): up to 5 official headlines across the library,
/// newest first, game name above each title. Hidden when empty or when loading failed.
struct NewsStrip: View {
    @Environment(AppModel.self) private var model
    private var store: NewsStore { .shared }

    private var ids: [String] { model.data.collection.map(\.gameID) }

    private var posts: [(game: String, item: NewsItem)] {
        ids.flatMap { id in (store.items[id] ?? []).map { (model.game(id)?.name ?? "", $0) } }
            .sorted { ($0.item.date ?? .distantPast) > ($1.item.date ?? .distantPast) }
            .prefix(5).map { $0 }
    }

    var body: some View {
        let list = posts
        Group {
            if !list.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text("News").font(PlayscribeFont.title3).accessibilityAddTraits(.isHeader)
                    ForEach(list, id: \.item.id) { post in
                        Link(destination: post.item.url) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(post.game).font(PlayscribeFont.caption).foregroundStyle(.secondary)
                                Text(post.item.title).font(PlayscribeFont.subheadline.weight(.semibold))
                                    .multilineTextAlignment(.leading).lineLimit(2)
                                HStack(spacing: 8) {
                                    if let d = post.item.date { Text(d.formatted(.dateTime.day().month(.abbreviated))) }
                                    NewsTag(item: post.item)
                                }
                                .font(PlayscribeFont.caption).foregroundStyle(.secondary)
                            }
                            .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                            .contentShape(Rectangle())
                        }
                        .tappableFrame()
                        .accessibilityElement(children: .ignore)
                        .accessibilityLabel("\(post.game), \(post.item.title), \(post.item.tagText), opens in browser")
                    }
                }
            }
        }
        .task(id: ids) {
            for id in ids.prefix(12) { await store.load(gameID: id, igdbID: model.game(id)?.igdbID) }
        }
    }
}


/// The News tab (Terry, 0.5.1): the newest official headlines across all games, your library's first.
/// Same layout rules as Updates: cards either side of the fold in the book pose, the flat half in Tabletop.
struct GlobalNewsView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.railWidth) private var railWidth
    @Environment(\.duo) private var duo
    private var store: NewsStore { .shared }

    var body: some View {
        let mine = Set(model.data.collection.map(\.gameID))
        let sorted = store.global.sorted { ($0.item.date ?? .distantPast) > ($1.item.date ?? .distantPast) }
        let all = sorted.filter { mine.contains($0.gameID) } + sorted.filter { !mine.contains($0.gameID) }
        // Tabletop: the newest post is the stage art on the standing half; the list on the flat half starts from the second.
        let lead: NewsStore.Headline? = duo.pose == .tabletop && all.count > 1 ? all.first : nil
        let items = lead == nil ? all : Array(all.dropFirst())
        Group {
            if items.isEmpty {
                ContentUnavailableView {
                    Label(store.globalFailed ? "Couldn't load news" : (store.globalLoaded ? "No news yet" : "Loading news"), systemImage: "newspaper")
                } description: {
                    Text(store.globalFailed ? "Check your connection and try again." : "Official posts from studios will appear here.")
                } actions: {
                    if store.globalFailed {
                        Button("Retry") { Task { await store.loadGlobal() } }.buttonStyle(.borderedProminent).foregroundStyle(PlayscribeColor.onAccent)
                            .tappableFrame()
                    }
                }
            } else if duo.pose == .book, let fold = duo.division {
                ScrollView {
                    LazyVGrid(columns: [GridItem(.fixed(max(0, fold.minX - 32)), spacing: 0, alignment: .top),
                                        GridItem(.fixed(fold.width + 32), spacing: 0),
                                        GridItem(.flexible(), spacing: 0, alignment: .top)],
                              alignment: .leading, spacing: 12) {
                        ForEach(Array(items.prefix(60).enumerated()), id: \.element.id) { i, h in
                            GlobalNewsRow(headline: h)
                                .padding(12)
                                .background(PlayscribeColor.ink700.opacity(0.5), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                            if i.isMultiple(of: 2) { Color.clear.frame(height: 1).accessibilityHidden(true) }
                        }
                    }
                    .padding(.horizontal, 16)
                }
                .frame(width: duo.size.width)
            } else {
                List { ForEach(items.prefix(60)) { GlobalNewsRow(headline: $0) } }
                    // Closed: the badge and clock sit top right and the tab capsule floats on the right edge, so the card
                    // starts lower and keeps clear of the rail.
                    .contentMargins(.top, duo.pose == .closed ? 24 : 0, for: .scrollContent)
                    .contentMargins(.trailing, duo.pose == .closed ? 72 : railWidth, for: .scrollContent)
            }
        }
        .frame(maxHeight: duo.pose == .tabletop ? max(0, duo.size.height - (duo.division?.maxY ?? 0)) : .infinity)
        .frame(maxHeight: .infinity, alignment: .bottom)
        .background(alignment: .top) {
            if let lead, let fold = duo.division { NewsStage(headline: lead).frame(height: fold.minY).allowsHitTesting(false) }
        }
        .overlay(alignment: .topLeading) {
            if duo.pose == .tabletop { Text("News").font(PlayscribeFont.largeTitle).padding(24).allowsHitTesting(false) }
        }
        .navigationTitle("News")
        .task {
            #if INTERNAL
            store.seedQA(gameIDs: model.data.collection.map(\.gameID))
            #endif
            await store.loadGlobal()
        }
    }
}

struct GlobalNewsRow: View {
    @Environment(AppModel.self) private var model
    @Environment(\.duo) private var duo
    var headline: NewsStore.Headline

    var body: some View {
        let game = model.game(headline.gameID)
        Link(destination: headline.item.url) {
            HStack(alignment: .top, spacing: 12) {
                if let game { CoverView(game: game, cornerRadius: 4).frame(width: 40) }
                VStack(alignment: .leading, spacing: 4) {
                    Text(headline.item.shortTitle).font(PlayscribeFont.subheadline.weight(.semibold)).multilineTextAlignment(.leading).lineLimit(3)
                    HStack(spacing: 8) {
                        NewsTag(item: headline.item)
                        if let game { Text(game.name) }
                        if let d = headline.item.date { Text(d.formatted(.dateTime.day().month(.abbreviated).year())).foregroundStyle(.secondary) }
                    }
                    .font(PlayscribeFont.caption)
                }
                Spacer(minLength: 0)
            }
            .frame(minHeight: 44)
            .contentShape(Rectangle())
        }
        .tappableFrame()
        .accessibilityLabel("\(game?.name ?? ""), \(headline.item.title), \(headline.item.tagText), opens in browser")
    }
}


/// Tabletop's standing half: the newest post's game art with its caption above the band. View only (G-4).
struct NewsStage: View {
    @Environment(AppModel.self) private var model
    @Environment(\.duo) private var duo
    /// The stage's bottom edge in screen space: the caption block ends 24 pt above the division band.
    @State private var stageBottom: CGFloat = 0
    var headline: NewsStore.Headline

    var body: some View {
        let game = model.game(headline.gameID)
        ZStack(alignment: .bottomLeading) {
            ArtView(asset: model.backdrop(headline.gameID, chapter: .news, tall: false), game: game)
            // The art layer fills whatever the stage is offered and never depends on the caption, so measuring it cannot feed back
            // into the caption's padding.
            .onGeometryChange(for: CGFloat.self) { $0.frame(in: .global).maxY } action: { if abs($0 - stageBottom) > 0.5 { stageBottom = $0 } }
            LinearGradient(stops: [.init(color: .clear, location: 0.25), .init(color: .black.opacity(0.88), location: 0.7), .init(color: .black.opacity(0.92), location: 1)], startPoint: .top, endPoint: .bottom)
            VStack(alignment: .leading, spacing: 4) {
                Text(headline.item.captionTitle).font(PlayscribeFont.title3.weight(.semibold)).lineLimit(2)
                HStack(spacing: 8) {
                    NewsTag(item: headline.item)
                    if let game { Text(game.name) }
                    if let d = headline.item.date { Text(d.formatted(.dateTime.day().month(.abbreviated).year())) }
                }
                .font(PlayscribeFont.caption)
                // Its own fill, so the chip never sits on the art's studio logo.
                .padding(.horizontal, 10).padding(.vertical, 4)
                .background(Capsule().fill(PlayscribeColor.ink700.opacity(0.7)))
            }
            .padding(.horizontal, 24).padding(.bottom, 24 + duo.clearance(forBottom: stageBottom))
            .padding(.trailing, TabletopRail.width)
        }
        .clipped()
        .accessibilityHidden(true)
    }
}


/// Tabletop's standing half for a game's News chapter: the game's art to the fold, with its newest headline as the caption.
/// View only (G-4); the headlines themselves are in the lower half.
struct NewsStageArt: View {
    @Environment(AppModel.self) private var model
    @Environment(\.duo) private var duo
    @State private var stageBottom: CGFloat = 0
    var gameID: String

    var body: some View {
        let game = model.game(gameID)
        let newest = (NewsStore.shared.items[gameID] ?? []).max { ($0.date ?? .distantPast) < ($1.date ?? .distantPast) }
        ZStack(alignment: .bottomLeading) {
            ArtView(asset: model.backdrop(gameID, chapter: .news, tall: false), game: game).ignoresSafeArea()
            // The art layer fills whatever the stage is offered and never depends on the caption, so measuring it cannot feed back
            // into the caption's padding.
            .onGeometryChange(for: CGFloat.self) { $0.frame(in: .global).maxY } action: { if abs($0 - stageBottom) > 0.5 { stageBottom = $0 } }
            LinearGradient(stops: [.init(color: .clear, location: 0.25), .init(color: .black.opacity(0.88), location: 0.7), .init(color: .black.opacity(0.92), location: 1)], startPoint: .top, endPoint: .bottom)
            VStack(alignment: .leading, spacing: 4) {
                Text(game?.name ?? "").font(PlayscribeFont.subheadline.weight(.semibold)).foregroundStyle(PlayscribeColor.accent)
                if let newest { Text(newest.captionTitle).font(PlayscribeFont.title3.weight(.semibold)).lineLimit(2) }
            }
            .padding(.horizontal, 24).padding(.bottom, 24 + duo.clearance(forBottom: stageBottom))
            .padding(.trailing, TabletopRail.width)
        }
        .clipped()
        .accessibilityHidden(true)
    }
}
