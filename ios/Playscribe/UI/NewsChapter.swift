import SwiftUI

/// Official news headlines per game (0.5.0 item 17, PR 1): title, date, "Official", opens in the
/// default browser. Headlines only; no source names, no article text.
struct NewsItem: Codable, Hashable, Identifiable {
    var title: String
    var date: Date?
    var url: URL
    var id: String { url.absoluteString }
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
        struct Row: Decodable { var gameId: String; var title: String; var date: Date?; var url: URL }
        var items: [Headline]
        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            var list = try c.nestedUnkeyedContainer(forKey: .items)
            var out: [Headline] = []
            // One malformed item never costs the list.
            while !list.isAtEnd {
                if let r = try? list.decode(Row.self) { out.append(Headline(gameID: r.gameId, item: NewsItem(title: r.title, date: r.date, url: r.url))) } else { _ = try? list.decode(File.Skip.self) }
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
                                    date: .now.addingTimeInterval(-Double(i) * 86_400), url: URL(string: "https://example.com/\(i)")!))
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
                        Text(item.title).font(PlayscribeFont.headline).multilineTextAlignment(.leading)
                        HStack(spacing: 8) {
                            if let d = item.date { Text(d.formatted(.dateTime.day().month(.abbreviated).year())) }
                            Tag(text: "Official")
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
                                    Tag(text: "Official")
                                }
                                .font(PlayscribeFont.caption).foregroundStyle(.secondary)
                            }
                            .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                            .contentShape(Rectangle())
                        }
                        .tappableFrame()
                        .accessibilityElement(children: .ignore)
                        .accessibilityLabel("\(post.game), \(post.item.title), Official, opens in browser")
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
        let items = sorted.filter { mine.contains($0.gameID) } + sorted.filter { !mine.contains($0.gameID) }
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
                    .contentMargins(.trailing, railWidth, for: .scrollContent)
            }
        }
        .frame(maxHeight: duo.pose == .tabletop ? max(0, duo.size.height - (duo.division?.maxY ?? 0)) : .infinity)
        .frame(maxHeight: .infinity, alignment: .bottom)
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
                    Text(headline.item.title).font(PlayscribeFont.subheadline.weight(.semibold)).multilineTextAlignment(.leading)
                    HStack(spacing: 8) {
                        Tag(text: "Official")
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
        .accessibilityLabel("\(game?.name ?? ""), \(headline.item.title), Official, opens in browser")
    }
}
