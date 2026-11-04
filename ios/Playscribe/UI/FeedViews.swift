import SwiftUI

/// U-1 to U-3: On PS5, Announced and Reported releases for library games, newest first.
struct UpdatesView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.railWidth) private var railWidth
    @Environment(\.duo) private var duo

    var body: some View {
        let ids = model.data.collection.map(\.gameID)
        let items = ids.flatMap { model.ps5Releases($0) }.sorted { $0.ps5Date > $1.ps5Date }
        Group {
            if ids.isEmpty {
                ContentUnavailableView {
                    Label("Updates for your games will appear here", systemImage: "book.closed")
                } actions: {
                    Button("Add a game") { model.nav.tab = .library }.buttonStyle(.borderedProminent).foregroundStyle(PlayscribeColor.onAccent)
                }
            } else if duo.pose == .book, let fold = duo.division {
                // TT-0: in the book pose the rows are cards on either page, never across the fold.
                ScrollView {
                    LazyVGrid(columns: [GridItem(.fixed(max(0, fold.minX - 32)), spacing: 0, alignment: .top),
                                        GridItem(.fixed(fold.width + 32), spacing: 0),
                                        GridItem(.flexible(), spacing: 0, alignment: .top)],
                              alignment: .leading, spacing: 12) {
                        ForEach(Array(items.enumerated()), id: \.element.id) { i, r in
                            FeedRow(release: r)
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
                    ForEach(items) { r in FeedRow(release: r) }

                }
                .contentMargins(.trailing, railWidth, for: .scrollContent)
            }
        }
        // G-4, TT-0: in Tabletop the list lives on the flat half; the standing half only titles it.
        .frame(maxHeight: duo.pose == .tabletop ? max(0, duo.size.height - (duo.division?.maxY ?? 0)) : .infinity)
        .frame(maxHeight: .infinity, alignment: .bottom)
        .overlay(alignment: .topLeading) {
            if duo.pose == .tabletop {
                Text("Updates").font(PlayscribeFont.largeTitle).padding(24).allowsHitTesting(false)
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
                    HStack(spacing: 8) {
                        Text(model.game(release.gameID)?.name ?? "")
                        Text(release.ps5Date.shortDay).foregroundStyle(.secondary)
                    }
                    .font(PlayscribeFont.caption)
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
    @Environment(\.duo) private var duo
    @State private var query = ""
    /// Tabletop: first-letter filter instead of typing (the keyboard never opens there; Iris, 0.2.0).
    @State private var letter: String?

    private func noteLines(term: String, library: Set<String>, tabletop: Bool) -> [(Release, String)] {
        if tabletop {
            guard let l = letter else { return [] }
            return model.noteHits(letter: l, scope: .allGames, gameID: nil).prefix(12).map { ($0.release, $0.line) }
        }
        guard !term.isEmpty else { return [] }
        var out: [(Release, String)] = []
        for g in library {
            for r in model.releases(g) {
                var hits: [(Release, String)] = []
                if ([r.displayName, r.headline ?? "", r.summary ?? ""].joined(separator: " ")).lowercased().contains(term) { hits.append((r, r.headline ?? r.displayName)) }
                for s in r.notes { for i in s.items where i.spoiler != true && i.text.lowercased().contains(term) { hits.append((r, i.text)) } }
                out += hits.prefix(3)
            }
        }
        return out
    }

    var body: some View {
        let tabletop = duo.pose == .tabletop
        let book = duo.pose == .book && duo.division != nil
        // Closed portrait: the system drawer field runs to the edge of the narrow window, touching the
        // time and Wi-Fi badge beside it (Mac, ea3af92: 0.3 pt clear). Iris: 16 pt clear, so this pose
        // has its own field with 16 pt margins.
        let ownField = duo.pose == .closed && !duo.isLandscape
        let term = tabletop ? "" : query.trimmingCharacters(in: .whitespaces).lowercased()
        let active = tabletop ? letter != nil : !term.isEmpty
        let library = Set(model.data.collection.map(\.gameID))
        let gameHits: [CatalogGame] = tabletop
            ? (letter.map { l in model.games.values.filter { LetterIndex.matches($0.name, l) }.sorted { $0.name < $1.name } } ?? [])
            : term.isEmpty ? [] : model.games.values.filter { $0.name.lowercased().contains(term) }.sorted { $0.name < $1.name }
        let noteHits = noteLines(term: term, library: library, tabletop: tabletop)
        let entryHits: [BookEntry] = tabletop
            ? (letter.map { l in model.fixtures.book.filter { library.contains($0.gameID) && LetterIndex.matches($0.title, l) } } ?? [])
            : term.isEmpty ? [] : model.fixtures.book.filter { library.contains($0.gameID) && ($0.title + " " + $0.body).lowercased().contains(term) }

        List {
            if tabletop {
                TabletopSearch(letter: $letter, prompt: "Search games, patch notes, characters")
                    .listRowBackground(Color.clear)
            }
            if ownField {
                HStack(spacing: 8) {
                    Image(systemName: "magnifyingglass").foregroundStyle(.secondary).accessibilityHidden(true)
                    TextField("Games, patch notes, characters…", text: $query)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                        .submitLabel(.search)
                        .onSubmit { model.rememberSearch(query) }
                        .accessibilityIdentifier("searchField")
                    if !query.isEmpty {
                        Button { query = "" } label: {
                            Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
                                .frame(width: 44, height: 44).contentShape(Rectangle())
                        }
                        .buttonStyle(.plain).accessibilityLabel("Clear search").tappableFrame()
                    }
                }
                .padding(.horizontal, 12)
                .frame(minHeight: 44)
                .background(PlayscribeColor.ink700, in: Capsule())
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)
                .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 4, trailing: 16))
                if !query.isEmpty {
                    Picker("Search in", selection: Binding(get: { model.noteScope }, set: { model.noteScope = $0 })) {
                        ForEach(NoteScope.allCases, id: \.self) { Text($0.label).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
                    .listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 4, trailing: 16))
                } else if !model.recentSearches.isEmpty {
                    Section("Recent") {
                        ForEach(model.recentSearches, id: \.self) { r in
                            Button { query = r } label: { Label(r, systemImage: "clock.arrow.circlepath") }
                                .buttonStyle(.plain).frame(minHeight: 44).tappableFrame()
                        }
                    }
                }
            }
            if !active && !book {
                Text(tabletop ? "Pick a letter to see games, patch notes and game book entries that start with it. Spoiler-tagged notes are left out."
                              : "Try “subtitles”, “Shadowstep” or “Coen”. Spoiler-tagged notes are left out of results.")
                    .font(PlayscribeFont.footnote).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    // Iris: the hint card is exactly as wide as the field, ending at its trailing edge
                    // (a list row's own background ran to the screen edge in every pose).
                    .padding(12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(PlayscribeColor.ink700, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
                    .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
            } else if gameHits.isEmpty && noteHits.isEmpty && entryHits.isEmpty {
                ContentUnavailableView.search(text: tabletop ? (letter ?? "") : query)
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
                                HStack(spacing: 6) {
                                    Text(hit.0.displayName).font(PlayscribeFont.subheadline.weight(.semibold))
                                    Text(model.game(hit.0.gameID)?.name ?? "").font(PlayscribeFont.subheadline).foregroundStyle(.secondary)
                                }
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
                                HStack(spacing: 8) {
                                    Text(model.game(e.gameID)?.name ?? "")
                                    Text(e.section).foregroundStyle(.secondary)
                                    if e.spoiler { Tag(text: "Spoiler") }
                                }
                                .font(PlayscribeFont.caption)
                            }
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
        .contentMargins(.trailing, railWidth, for: .scrollContent)
        .overlay {
            if query.count >= 2 && model.noteScope == .thisGame && model.nav.lastGameID != nil {
                NoteSearchResults(query: query, scope: .thisGame, gameID: model.nav.lastGameID) { model.noteScope = .allGames }
            }
        }
        .modifier(SearchFieldIfTyping(enabled: !tabletop && !ownField, drawer: duo.pose != .book, query: $query))
        // Book: Search lives on the right page, never across the fold (0.2.0 gate: field and hint ran full width).
        .padding(.leading, duo.pose == .book ? (duo.division.map { $0.maxX + 8 } ?? 0) : 0)
        // Book: the hint sits on the left page under the title, so the left page is not empty and the
        // field and results own the right page (Iris, #185 review).
        .overlay(alignment: .topLeading) {
            if book, !active, let fold = duo.division {
                Text("Try “subtitles”, “Shadowstep” or “Coen”. Spoiler-tagged notes are left out of results.")
                    .font(PlayscribeFont.footnote).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(width: max(0, fold.minX - 16 - 24), alignment: .leading)
                    .padding(.leading, 16).padding(.top, 120)
                    .allowsHitTesting(false)
            }
        }
        // G-4, TT-0: in Tabletop the list lives on the flat half; the standing half only titles it.
        .frame(maxHeight: tabletop ? max(0, duo.size.height - (duo.division?.maxY ?? 0)) : .infinity)
        .frame(maxHeight: .infinity, alignment: .bottom)
        .overlay(alignment: .topLeading) {
            if tabletop {
                Text("Search").font(PlayscribeFont.largeTitle).padding(24).allowsHitTesting(false)
            }
        }
        .navigationTitle("Search")
        .navigationBarTitleDisplayMode(.large)
    }
}

/// The system search field everywhere except Tabletop, which uses the read-only button and letter strip.
/// Closed poses hide the tab-bar search field, so it sits in the navigation drawer in every pose.
private struct SearchFieldIfTyping: ViewModifier {
    @Environment(AppModel.self) private var model
    var enabled: Bool
    /// Closed and flat poses hide the tab-bar field, so it moves into the nav drawer; Book keeps the
    /// system's own placement, which sits on the right page.
    var drawer: Bool
    @Binding var query: String

    func body(content: Content) -> some View {
        if enabled {
            content
            .searchable(text: $query, placement: drawer ? .navigationBarDrawer(displayMode: .always) : .automatic, prompt: "Games, patch notes, characters…")
            .searchScopes(Binding(get: { model.noteScope }, set: { model.noteScope = $0 })) {
                ForEach(NoteScope.allCases, id: \.self) { Text($0.label).tag($0) }
            }
            .searchSuggestions {
                ForEach(model.recentSearches, id: \.self) { Text($0).searchCompletion($0) }
            }
            .onSubmit(of: .search) { model.rememberSearch(query) }
        } else {
            content
        }
    }
}
