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

struct NewsChapter: View {
    var gameID: String
    @Environment(AppModel.self) private var model
    private var store: NewsStore { .shared }

    var body: some View {
        let list = store.items[gameID] ?? []
        VStack(alignment: .leading, spacing: 12) {
            if list.isEmpty {
                if store.failed.contains(gameID) {
                    HStack {
                        Text("Couldn't load news").font(PlayscribeFont.subheadline).foregroundStyle(.secondary)
                        Spacer(minLength: 0)
                        Button("Retry") { Task { await store.load(gameID: gameID, igdbID: model.game(gameID)?.igdbID) } }
                            .font(PlayscribeFont.subheadline.weight(.semibold)).foregroundStyle(PlayscribeColor.accent)
                            .frame(minHeight: 44).tappableFrame()
                    }
                } else if store.loaded.contains(gameID) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("No news yet").font(PlayscribeFont.headline)
                        Text("Official posts from the studio will show here.").font(PlayscribeFont.subheadline).foregroundStyle(.secondary)
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
        .task(id: gameID) { await store.load(gameID: gameID, igdbID: model.game(gameID)?.igdbID) }
    }
}
