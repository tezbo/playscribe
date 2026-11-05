import SwiftUI

/// The News tab: what is happening around your games and PS5, newest first. Your games' news comes
/// first, then the rest of PS5 news. Same layout rules as Updates: rows stay off the fold in the
/// book pose, and in Tabletop the list lives on the flat half.
struct NewsView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.railWidth) private var railWidth
    @Environment(\.duo) private var duo

    var body: some View {
        let mine = model.newsForLibrary
        let around = model.newsAroundPS5
        Group {
            if mine.isEmpty && around.isEmpty {
                ContentUnavailableView {
                    Label("News will appear here", systemImage: "megaphone")
                } description: {
                    Text(model.feedStatusLine ?? "Studio posts and PS5 headlines for your games.")
                }
            } else if duo.pose == .book, let fold = duo.division {
                ScrollView {
                    LazyVGrid(columns: [GridItem(.fixed(max(0, fold.minX - 32)), spacing: 0, alignment: .top),
                                        GridItem(.fixed(fold.width + 32), spacing: 0),
                                        GridItem(.flexible(), spacing: 0, alignment: .top)],
                              alignment: .leading, spacing: 12) {
                        ForEach(Array((mine + around).enumerated()), id: \.element.id) { i, item in
                            NewsRow(item: item)
                                .padding(12)
                                .background(PlayscribeColor.ink700.opacity(0.5), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                            if i.isMultiple(of: 2) { Color.clear.frame(height: 1).accessibilityHidden(true) }
                        }
                    }
                    .padding(.horizontal, 16)
                }
                .frame(width: duo.size.width)
            } else {
                List {
                    if !mine.isEmpty {
                        Section("Your games") { ForEach(mine) { NewsRow(item: $0) } }
                    }
                    if !around.isEmpty {
                        Section("Around PS5") { ForEach(around) { NewsRow(item: $0) } }
                    }
                }
                .contentMargins(.trailing, railWidth, for: .scrollContent)
            }
        }
        .frame(maxHeight: duo.pose == .tabletop ? max(0, duo.size.height - (duo.division?.maxY ?? 0)) : .infinity)
        .frame(maxHeight: .infinity, alignment: .bottom)
        .overlay(alignment: .topLeading) {
            if duo.pose == .tabletop {
                Text("News").font(PlayscribeFont.largeTitle).padding(24).allowsHitTesting(false)
            }
        }
        .navigationTitle("News")
    }
}

/// One news item. It opens in the default browser; the only provenance shown is the Official or Reported tag.
struct NewsRow: View {
    @Environment(AppModel.self) private var model
    @Environment(\.openURL) private var openURL
    var item: NewsItem
    /// Inside a game's own News chapter the cover and game name are redundant.
    var showsGame = true

    var body: some View {
        let game = showsGame ? model.appGame(forFeedID: item.gameId) : nil
        Button { if let u = item.link { openURL(u) } } label: {
            HStack(alignment: .top, spacing: 12) {
                if let game { CoverView(game: game, cornerRadius: 4).frame(width: 40) }
                VStack(alignment: .leading, spacing: 4) {
                    Text(item.title).font(PlayscribeFont.subheadline.weight(.semibold)).multilineTextAlignment(.leading)
                    HStack(spacing: 8) {
                        Tag(text: item.isOfficial ? "Official" : "Reported", tint: item.isOfficial ? PlayscribeColor.accent : .secondary)
                        if let game { Text(game.name) }
                        Text(item.publishedAt.shortDay).foregroundStyle(.secondary)
                    }
                    .font(PlayscribeFont.caption)
                    if let e = item.excerpt, !e.isEmpty {
                        Text(e).font(PlayscribeFont.footnote).foregroundStyle(.secondary).lineLimit(3).multilineTextAlignment(.leading)
                    }
                }
                Spacer(minLength: 0)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(item.link == nil)
        .tappableFrame()
    }
}

/// A game page's News chapter. Never blank: with nothing yet it says so and where news comes from.
struct NewsChapter: View {
    @Environment(AppModel.self) private var model
    var gameID: String

    var body: some View {
        let items = model.newsFor(gameID)
        VStack(alignment: .leading, spacing: 14) {
            if items.isEmpty {
                Text("No news for this game yet. Studio posts and headlines will show up here as they arrive.")
                    .font(PlayscribeFont.subheadline).foregroundStyle(.secondary)
            } else {
                ForEach(items.prefix(30)) { item in
                    NewsRow(item: item, showsGame: false)
                    Divider().overlay(PlayscribeColor.ink700)
                }
            }
        }
        .task(id: gameID) { await model.refreshGameNews(gameID) }
    }
}
