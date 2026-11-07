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
                        Text("Official posts from the studio will appear here.").font(PlayscribeFont.subheadline).foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 20)
                }
            }
            ForEach(list.prefix(20)) { item in
                let row = VStack(alignment: .leading, spacing: 4) {
                    Text(item.title).font(PlayscribeFont.headline).multilineTextAlignment(.leading)
                    HStack(spacing: 8) {
                        if let d = item.date { Text(d.formatted(.dateTime.day().month(.abbreviated).year())) }
                        Tag(text: "Official")
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

/// Library "News" strip (0.5.0 item 17, PR 2): up to 5 official headlines across the library,
/// newest first, game name above each title. Hidden when empty or when loading failed.
struct NewsStrip: View {
    @Environment(AppModel.self) private var model
    @Environment(\.openURL) private var openURL
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
                        Button { openURL(post.item.url) } label: {
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
                        .buttonStyle(.plain)
                        .tappableFrame()
                        .accessibilityElement(children: .ignore)
                        .accessibilityAddTraits(.isLink)
                        .accessibilityLabel("\(post.game), \(post.item.title), Official, opens in browser")
                    }
                }
            }
        }
    }
}
