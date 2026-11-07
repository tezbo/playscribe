import SwiftUI

/// U-1 to U-3: On PS5, Announced and Reported releases for library games, newest first.
struct UpdatesView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.railWidth) private var railWidth
    @Environment(\.duo) private var duo

    var body: some View {
        let ids = model.data.collection.map(\.gameID)
        let items = ids.flatMap { model.ps5Releases($0) }.sorted { $0.ps5Date > $1.ps5Date }
        let badgeExtra = duo.occlusions.filter { $0.minY < 190 && $0.maxY > 40 }
            .map { max(0, duo.size.width - $0.minX) }.max() ?? 0
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
                .clearsMessages()
                .frame(width: duo.size.width)
            } else {
                List {
                    ForEach(items) { r in FeedRow(release: r) }

                }
                // The inset is on the list itself: row backgrounds, separators and tap frames all stop at the
                // rail and the time/Wi-Fi badge; scroll-content margins left them running underneath.
                .padding(.trailing, railWidth + (duo.pose == .tabletop ? 0 : badgeExtra))
                .clearsMessages()
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
    /// Half the title's cap height: lifts the dot's centre to the middle of the first line at every text size.
    @ScaledMetric(relativeTo: .subheadline) private var dotLift: CGFloat = 5
    @Environment(\.dynamicTypeSize) private var typeSize
    var release: Release

    var body: some View {
        let unread = model.isUnread(release)
        Button { model.openGame(release.gameID, chapter: .updates, releaseID: release.id) } label: {
            // At accessibility sizes the thumbnail sits above the text so the column gets the row's full width: a game
            // name never breaks inside a word and a date stays whole (Iris, AX5).
            let rowLayout = typeSize.isAccessibilitySize ? AnyLayout(VStackLayout(alignment: .leading, spacing: 8)) : AnyLayout(HStackLayout(spacing: 28))
            rowLayout {
                if let g = model.game(release.gameID) { CoverView(game: g, cornerRadius: 4).frame(width: 40) }
                VStack(alignment: .leading, spacing: 3) {
                    // At accessibility sizes the row stacks: the title takes the full width in whole words,
                    // the tags and date each get their own line, the summary goes under.
                    // The dot hangs in the gutter left of the text (12 pt clear of the first letter, centred on the title's first
                    // line), so read and unread rows share one title edge (Iris, Quinn).
                    TitleWithTags(release: release) {
                        Text(release.displayName).font(PlayscribeFont.subheadline.weight(unread ? .bold : .semibold))
                    }
                    .overlay(alignment: Alignment(horizontal: .leading, vertical: .firstTextBaseline)) {
                        if unread {
                            UnreadDot()
                                .alignmentGuide(.firstTextBaseline) { $0[VerticalAlignment.center] + dotLift }
                                // A plain offset, not a leading guide (Mac, fd23684: the guide left the dot on the first letter's stem):
                                // the dot's right edge sits 12 pt left of the title's left edge, its left edge 8 pt right of the cover.
                                .offset(x: -(8 + 12))
                        }
                    }
                    if typeSize.isAccessibilitySize {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(model.game(release.gameID)?.name ?? "").fixedSize(horizontal: false, vertical: true)
                            Text(release.ps5Date.shortDay).foregroundStyle(.secondary).fixedSize()
                        }
                        .font(PlayscribeFont.caption)
                    } else {
                        HStack(spacing: 8) {
                            Text(model.game(release.gameID)?.name ?? "").fixedSize(horizontal: false, vertical: true)
                            Text(release.ps5Date.shortDay).foregroundStyle(.secondary)
                        }
                        .font(PlayscribeFont.caption)
                    }
                    if let h = release.headline {
                        // Whole words only: a capped summary ends "…" at a word boundary (Iris, AX3).
                        if typeSize.isAccessibilitySize { WholeWordText(text: h, font: PlayscribeFont.footnote, lines: 4) }
                        else { Text(h).font(PlayscribeFont.footnote).lineLimit(2) }
                    }
                }
                Spacer(minLength: 0)
            }
            // One rule for every pose: at accessibility sizes there is no cover beside the text for the hung unread dot to sit
            // against, so the row keeps its own 12 pt margin + 8 pt dot + 12 pt clearance (32 pt) before the text. The dot is then
            // 12 pt inside the card's edge in Closed, Open and Book alike (Mac, 99a1f3b: flush with the edge in Closed and Open).
            .padding(.leading, typeSize.isAccessibilitySize ? 32 : 0)
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
        // Every pose but Tabletop has its own field in the list: the system drawer field ran flush to
        // the time and Wi-Fi badge (Mac, ea3af92) and could not be inset. The field and the hint card
        // share the same insets, and the list keeps clear of any occlusion at the top (Iris, #185).
        let ownField = !tabletop
        let badgeExtra = duo.occlusions.filter { $0.minY < 190 && $0.maxY > 40 }
            .map { max(0, duo.size.width - $0.minX) }.max() ?? 0
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
                    // Iris: the result cards are as wide as the list's sections, so the field row uses the
                    // section's full width too (no extra content inset), matching their edges.
                    .listRowInsets(EdgeInsets(top: 8, leading: 0, bottom: 8, trailing: 0))
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
                // Search is universal: every game and every patch note in the library. The scope picker that
                // silently limited it to the last game opened is gone (Terry, 0.2.0 build 5); a game's own
                // search lives in that game's Contents.
                if query.isEmpty, !model.recentSearches.isEmpty {
                    Section("Recent") {
                        ForEach(model.recentSearches, id: \.self) { r in
                            Button { query = r } label: { Label(r, systemImage: "clock.arrow.circlepath") }
                                .buttonStyle(.plain).frame(minHeight: 44).tappableFrame()
                        }
                    }
                }
            }
            if !active {
                Text(tabletop ? "Typing needs the flat screen. Pick a letter above, or open your Duo flat to type."
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
                    .listRowInsets(EdgeInsets(top: 8, leading: tabletop ? 0 : 16, bottom: 8, trailing: tabletop ? 0 : 16))
            } else if gameHits.isEmpty && noteHits.isEmpty && entryHits.isEmpty {
                // Iris: the No Results card has the field's leading and trailing edges, like the hint card.
                ContentUnavailableView.search(text: tabletop ? (letter ?? "") : query)
                    .padding(12)
                    .frame(maxWidth: .infinity)
                    .background(PlayscribeColor.ink700, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
                    .listRowInsets(EdgeInsets(top: 8, leading: tabletop ? 0 : 16, bottom: 8, trailing: tabletop ? 0 : 16))
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
                        .gameQuickActions(g)
                        // Iris: a deliberate swipe only (no full swipe), and only for games in the library.
                        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                            if library.contains(g.id) {
                                Button("Remove", role: .destructive) { model.removeGame(g.id) }
                            }
                        }
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
        .contentMargins(.trailing, railWidth + (tabletop ? 0 : badgeExtra), for: .scrollContent)
        .clearsMessages()
        // Book: Search lives on the right page, never across the fold (0.2.0 gate: field and hint ran full width).
        .padding(.leading, duo.pose == .book ? (duo.division.map { $0.maxX + 8 } ?? 0) : 0)
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
        // Back to where Search was opened from: a visible button (the rail has its own in Tabletop) and the edge swipe.
        .toolbar {
            if !tabletop {
                ToolbarItem(placement: .topBarLeading) {
                    Button { model.leaveSearch() } label: { Label("Back", systemImage: "chevron.backward") }
                        .accessibilityIdentifier("searchBack")
                }
            }
        }
        .simultaneousGesture(DragGesture(minimumDistance: 24).onEnded { v in
            if v.startLocation.x < 28 && v.translation.width > 80 && abs(v.translation.height) < 60 { model.leaveSearch() }
        })
    }
}
