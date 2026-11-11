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
    /// INTERNAL QA (`-qaRoute news-empty`, `news-demo`): a fixed set of headlines instead of the feed, so the empty state and
    /// the Reported chip can be shot without network. Reversible tooling; no effect in real installs.
    @ObservationIgnored private var qaFixed = false

    enum QAMode { case empty, demo }
    func setQA(_ mode: QAMode, ids: [String]) {
        qaFixed = true
        failed = []
        items = [:]
        loaded = Set(ids)
        guard mode == .demo, let first = ids.first else { return }
        let day: TimeInterval = 86400
        items[first] = [
            NewsItem(title: "Free photo mode and a new difficulty arrive next week", date: Date(timeIntervalSinceNow: -2 * day),
                     url: URL(string: "https://example.com/news/photo-mode")!, verification: "reported"),
            NewsItem(title: "One million copies sold, thank you", date: Date(timeIntervalSinceNow: -6 * day),
                     url: URL(string: "https://example.com/news/one-million")!, verification: "official"),
        ]
        if ids.count > 1 {
            items[ids[1]] = [NewsItem(title: "Developer roadmap for the year ahead", date: Date(timeIntervalSinceNow: -4 * day),
                                      url: URL(string: "https://example.com/news/roadmap")!, verification: "reported")]
        }
    }

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

    func load(gameID: String, igdbID: Int?) async {
        if qaFixed { loaded.insert(gameID); return }
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
    /// Clear space between a Book card column and the hinge band, each side (Iris, 11 Nov).
    static let hingeGap: CGFloat = 24
    static let emptyCopy = "Studio news for the games you follow will show up here."
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

    var body: some View {
        let list = posts
        Group {
            if duo.pose == .tabletop {
                // G-4, TT-1: the standing half is the newest story, view only and read by VoiceOver (Iris, 11 Nov);
                // the list is below the fold. Same split as the Library (D-5).
                ArrangementView {
                    NewsStage(post: list.first, mode: stageMode(list))
                } secondary: {
                    content(list)
                }
                .arrangementViewStyle(.split)
            } else {
                content(list)
            }
        }
        .navigationTitle("News")
        .task(id: ids) { await load() }
    }

    private func stageMode(_ list: [(game: String, item: NewsItem)]) -> NewsStage.Mode {
        if ids.isEmpty { return .noGames }
        if !list.isEmpty { return .story }
        if stillLoading { return .loading }
        if ids.contains(where: { store.failed.contains($0) }) { return .failed }
        return .empty
    }

    @ViewBuilder private func content(_ list: [(game: String, item: NewsItem)]) -> some View {
        let badgeExtra = duo.occlusions.filter { $0.minY < 190 && $0.maxY > 40 }
            .map { max(0, duo.size.width - $0.minX) }.max() ?? 0
        if ids.isEmpty {
            ContentUnavailableView {
                Label("News for your games will appear here", systemImage: "newspaper")
            } actions: {
                Button("Add a game") { model.nav.tab = .library }.buttonStyle(.borderedProminent).foregroundStyle(PlayscribeColor.onAccent)
            }
        } else if list.isEmpty {
            // Never a blank page: loading, then the empty copy, or Retry when nothing could be fetched. Centred (Iris).
            VStack(spacing: 12) {
                if stillLoading {
                    ProgressView()
                    Text("Loading news").font(PlayscribeFont.subheadline).foregroundStyle(.secondary)
                } else if ids.contains(where: { store.failed.contains($0) }) {
                    Text("Couldn't load news. Check your connection and try again.").font(PlayscribeFont.subheadline).foregroundStyle(.secondary).multilineTextAlignment(.center)
                    Button { Task { await load() } } label: { Text("Retry").frame(minWidth: 44, minHeight: 44).contentShape(Rectangle()) }
                        .font(PlayscribeFont.subheadline.weight(.semibold)).foregroundStyle(PlayscribeColor.accent)
                        .tappableFrame()
                } else {
                    Text("No news yet").font(PlayscribeFont.headline)
                    Text(Self.emptyCopy).font(PlayscribeFont.subheadline).foregroundStyle(.secondary).multilineTextAlignment(.center)
                }
            }
            .padding(24)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .accessibilityElement(children: .combine)
        } else if duo.pose == .book, let fold = duo.division {
            // TT-0: in the book pose the rows are cards on either page, never across the fold, and each column keeps
            // `hingeGap` clear of the hinge band on its side (Iris, 11 Nov: 14 and 20 pt were too close). The grid has 16 pt
            // side padding, so the left column ends at fold.minX - hingeGap and the right starts at fold.maxX + hingeGap.
            ScrollView {
                LazyVGrid(columns: [GridItem(.fixed(max(0, fold.minX - 16 - Self.hingeGap)), spacing: 0, alignment: .top),
                                    GridItem(.fixed(fold.width + 2 * Self.hingeGap), spacing: 0),
                                    GridItem(.flexible(), spacing: 0, alignment: .top)],
                          alignment: .leading, spacing: 12) {
                    ForEach(Array(list.enumerated()), id: \.element.item.id) { i, post in
                        NewsRow(gameID: post.game, item: post.item)
                            .padding(12)
                            // Both cards of a row share its height (Iris).
                            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                            .background(PlayscribeColor.ink700.opacity(0.5), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                        if i.isMultiple(of: 2) { Color.clear.frame(height: 1).accessibilityHidden(true) }
                    }
                }
                .padding(.horizontal, 16)
            }
            // Pull to refresh in Book too (Quinn: the List had it, the grid did not).
            .refreshable { await load(force: true) }
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

/// Tabletop's standing half for News: the newest story as content only (G-4, TT-1), art, headline, game, date and tag,
/// one VoiceOver element. Without a story it carries the page title and the same state copy as the list, so the stage is
/// never blank and never silent.
struct NewsStage: View {
    enum Mode { case story, loading, failed, empty, noGames }
    var post: (game: String, item: NewsItem)?
    var mode: Mode
    @Environment(AppModel.self) private var model
    @Environment(\.duo) private var duo
    @Environment(\.dynamicTypeSize) private var typeSize
    @State private var stageBottom: CGFloat = 0

    var body: some View {
        let game = post.flatMap { model.game($0.game) }
        // Size from the parent only (see DeckStage): art and scrim are a background, the caption an overlay.
        Color.clear
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background {
                ZStack {
                    ArtView(asset: game?.keyArtAsset, game: game, drift: true)
                    LinearGradient(stops: typeSize.isAccessibilitySize
                                       ? [.init(color: .clear, location: 0.1), .init(color: PlayscribeColor.ink950.opacity(0.9), location: 0.4)]
                                       : [.init(color: .clear, location: 0.3), .init(color: PlayscribeColor.ink950.opacity(0.8), location: 0.75)],
                                   startPoint: .top, endPoint: .bottom)
                }
            }
            .overlay(alignment: .topLeading) {
                Text("News").font(PlayscribeFont.largeTitle).padding(24).shadow(color: .black.opacity(0.6), radius: 3)
                    .accessibilityAddTraits(.isHeader)
            }
            .overlay(alignment: .bottomLeading) {
                VStack(alignment: .leading, spacing: 6) {
                    if let post, let game {
                        Text(post.item.tagText).font(PlayscribeFont.caption).foregroundStyle(PlayscribeColor.accent)
                            .shadow(color: .black.opacity(0.6), radius: 3)
                        // Headline cap 3 lines at accessibility sizes (Iris, #232 Tabletop News), 4 at standard.
                        WholeWordText(text: post.item.title, font: PlayscribeFont.title3, lines: typeSize.isAccessibilitySize ? 3 : 4, color: PlayscribeColor.textPrimary)
                        if let d = post.item.date {
                            Text("\(Text(game.name).foregroundStyle(PlayscribeColor.textPrimary))  \(Text(d.formatted(.dateTime.day().month(.abbreviated))).foregroundStyle(PlayscribeColor.vellum100))")
                        } else {
                            Text(game.name).foregroundStyle(PlayscribeColor.textPrimary)
                        }
                    } else {
                        Text(stateLine).foregroundStyle(PlayscribeColor.textPrimary)
                    }
                }
                .font(PlayscribeFont.subheadline).fixedSize(horizontal: false, vertical: true)
                .padding(20)
                .dynamicTypeSize(...DynamicTypeSize.accessibility3)
                // The caption ends 24 pt above the division, measured in screen space.
                .padding(.bottom, duo.clearance(forBottom: stageBottom))
                .accessibilityElement(children: .combine)
                .accessibilityIdentifier("newsStageCaption")
            }
            .background(Color.clear.onGeometryChange(for: CGFloat.self) { $0.frame(in: .global).maxY.rounded() } action: { new in
                if abs(new - stageBottom) > 0.5 { stageBottom = new }
            })
            .clipped()
            // View only means no touch, never hidden from VoiceOver (Iris, 7 Nov).
            .allowsHitTesting(false)
            .accessibilityElement(children: .contain)
    }

    private var stateLine: String {
        switch mode {
        case .story: ""
        case .loading: "Loading news"
        case .failed: "Couldn't load news"
        case .empty: "No news yet. " + NewsView.emptyCopy
        case .noGames: "News for your games will appear here"
        }
    }
}
