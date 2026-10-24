import SwiftUI

/// U-1 to U-3: On PS5, Announced and Reported releases for library games, newest first.
struct UpdatesView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.railWidth) private var railWidth

    var body: some View {
        let ids = model.data.collection.map(\.gameID)
        let items = ids.flatMap { model.ps5Releases($0) }.sorted { $0.ps5Date > $1.ps5Date }
        let pcCount = ids.reduce(0) { $0 + model.pcOnlyReleases($1).count }
        Group {
            if ids.isEmpty {
                ContentUnavailableView {
                    Label("Updates for your games will appear here", systemImage: "book.closed")
                } actions: {
                    Button("Add a game") { model.nav.tab = .library }.buttonStyle(.borderedProminent).foregroundStyle(PlayscribeColor.onAccent)
                }
            } else {
                List {
                    ForEach(items) { r in FeedRow(release: r) }
                    if pcCount > 0 {
                        Text("\(pcCount) PC-only update\(pcCount == 1 ? " isn't" : "s aren't") listed because \(pcCount == 1 ? "it's" : "they're") not confirmed on PS5.")
                            .font(PlayscribeFont.footnote).foregroundStyle(.secondary)
                    }
                }
                .contentMargins(.trailing, railWidth, for: .scrollContent)
            }
        }
        .navigationTitle("Updates")
    }
}

struct FeedRow: View {
    @Environment(AppModel.self) private var model
    var release: Release

    var body: some View {
        let unread = model.isUnread(release)
        Button { model.openGame(release.gameID, chapter: .updates, releaseID: release.id) } label: {
            HStack(spacing: 12) {
                if let g = model.game(release.gameID) { CoverView(game: g, cornerRadius: 4).frame(width: 40) }
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 6) {
                        if unread { UnreadDot() }
                        Text(release.displayName).font(PlayscribeFont.subheadline.weight(unread ? .bold : .semibold))
                        ReleaseTag(release: release)
                    }
                    Text("\(model.game(release.gameID)?.name ?? "") · \(release.ps5Date.shortDay)").font(PlayscribeFont.caption).foregroundStyle(.secondary)
                    if let h = release.headline { Text(h).font(PlayscribeFont.footnote).lineLimit(2) }
                }
                Spacer(minLength: 0)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .tappableFrame()
    }
}

/// Search: games, patch notes (spoilers left out) and game book entries.
struct SearchView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.railWidth) private var railWidth
    @State private var query = ""

    var body: some View {
        let term = query.trimmingCharacters(in: .whitespaces).lowercased()
        let library = Set(model.data.collection.map(\.gameID))
        let gameHits = term.isEmpty ? [] : model.games.values.filter { $0.name.lowercased().contains(term) }.sorted { $0.name < $1.name }
        let noteHits: [(Release, String)] = term.isEmpty ? [] : library.flatMap { model.releases($0) }.flatMap { r -> [(Release, String)] in
            var hits: [(Release, String)] = []
            if ([r.displayName, r.headline ?? "", r.summary ?? ""].joined(separator: " ")).lowercased().contains(term) { hits.append((r, r.headline ?? r.displayName)) }
            for s in r.notes { for i in s.items where i.spoiler != true && i.text.lowercased().contains(term) { hits.append((r, i.text)) } }
            return Array(hits.prefix(3))
        }
        let entryHits = term.isEmpty ? [] : model.fixtures.book.filter { library.contains($0.gameID) && ($0.title + " " + $0.body).lowercased().contains(term) }

        List {
            if term.isEmpty {
                Text("Try “subtitles”, “Shadowstep” or “Coen”. Spoiler-tagged notes are left out of results.")
                    .font(PlayscribeFont.footnote).foregroundStyle(.secondary)
            } else if gameHits.isEmpty && noteHits.isEmpty && entryHits.isEmpty {
                ContentUnavailableView.search(text: query)
            }
            if !gameHits.isEmpty {
                Section("Games") {
                    ForEach(gameHits) { g in
                        Button { library.contains(g.id) ? model.openGame(g.id) : (model.addSheetOpen = true) } label: {
                            HStack(spacing: 12) {
                                CoverView(game: g, cornerRadius: 4).frame(width: 36)
                                VStack(alignment: .leading) {
                                    Text(g.name).font(PlayscribeFont.subheadline.weight(.semibold))
                                    Text(library.contains(g.id) ? (model.entry(g.id)?.status.label ?? "") : "Not in your library").font(PlayscribeFont.caption).foregroundStyle(.secondary)
                                }
                            }
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            if !noteHits.isEmpty {
                Section("In patch notes") {
                    ForEach(Array(noteHits.prefix(12).enumerated()), id: \.offset) { _, hit in
                        Button { model.openGame(hit.0.gameID, chapter: .updates, releaseID: hit.0.id) } label: {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("\(hit.0.displayName) · \(model.game(hit.0.gameID)?.name ?? "")").font(PlayscribeFont.subheadline.weight(.semibold))
                                Text(hit.1).font(PlayscribeFont.footnote).lineLimit(2)
                            }
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            if !entryHits.isEmpty {
                Section("In game books") {
                    ForEach(entryHits) { e in
                        Button {
                            let ch: Chapter = e.chapter == .world ? .world : .companion
                            model.openGame(e.gameID, chapter: ch)
                            model.nav.anchors[AppModel.bookKey(e.gameID, ch)] = "entry-\(e.id)"
                        } label: {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(e.title).font(PlayscribeFont.subheadline.weight(.semibold))
                                Text("\(model.game(e.gameID)?.name ?? "") · \(e.section)\(e.spoiler ? " · spoiler" : "")").font(PlayscribeFont.caption).foregroundStyle(.secondary)
                            }
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
        .contentMargins(.trailing, railWidth, for: .scrollContent)
        .searchable(text: $query, prompt: "Games, patch notes, characters…")
        .navigationTitle("Search")
    }
}
