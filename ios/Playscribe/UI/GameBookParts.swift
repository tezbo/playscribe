import SwiftUI

/// Contract v2 §11: a game is the Page (the release being read) and the Contents (the game's
/// chapters, search, releases and actions). The game book is one ArrangementView(.split), so the
/// system lays the two out for every pose: side by side in landscape, stacked in portrait, the
/// fold between them when folded, the Page alone when closed.

/// D-10: Contents on the left, Page on the right by default; "Swap sides" flips them, everywhere,
/// and persists (D-13).
enum ReadingSide {
    static let key = "pageOnLeft"
}

/// D-3: the selected release (or chapter) with its art band.
struct PageView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.duo) private var duo
    @State private var position = ScrollPosition()
    var gameID: String
    /// Closed: one stacked book, the Contents below the Page.
    var withContents = false

    var body: some View {
        let chapter = model.chapters(gameID).contains(model.nav.chapter) ? model.nav.chapter : .updates
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                PageArtBand(gameID: gameID)
                if withContents, let g = model.game(gameID) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(g.name).font(PlayscribeFont.title2).accessibilityAddTraits(.isHeader)
                        if let e = model.entry(gameID) { StatusPill(status: e.status) }
                    }
                    .padding(.horizontal, 20)
                }
                Group {
                    switch chapter {
                    case .updates:
                        if let r = model.selectedRelease(gameID) {
                            ReleasePage(release: r)
                            if let g = model.game(gameID) {
                                Divider().overlay(PlayscribeColor.ink700)
                                GameBasicsView(game: g)
                            }
                        } else if let g = model.game(gameID) {
                            NoNotesPage(game: g)
                        }
                    case .world, .companion: EntriesChapter(gameID: gameID, chapter: chapter)
                    case .gallery: GalleryChapter(gameID: gameID)
                    case .mybook: MyBookChapter(gameID: gameID)
                    }
                }
                // Reading measure: 55 to 75 characters.
                .frame(maxWidth: 620, alignment: .leading)
                .padding(.horizontal, 20)
                if withContents {
                    Divider().overlay(PlayscribeColor.ink700).padding(.top, 8)
                    ContentsBody(gameID: gameID).padding(.horizontal, 16)
                }
            }
            .padding(.bottom, 24)
        }
        .scrollIndicators(.hidden)
        // D-2, T-5, D-10: the reading position is model state. Closing, opening, rotating or
        // swapping sides rebuilds this view; it comes back where the reader was.
        .scrollPosition($position)
        .onScrollGeometryChange(for: CGFloat.self) { $0.contentOffset.y + $0.contentInsets.top } action: { _, y in
            model.nav.anchors[anchorKey] = String(Int(y))
        }
        .onAppear(perform: restore)
        .onChange(of: duo.pose) { restore() }
        .onChange(of: model.nav.selected?[gameID]) { position.scrollTo(edge: .top) }
        .background(Color.ink0)
        .foldAudited()
    }

    private var anchorKey: String { "page-\(gameID)-\(model.nav.chapter.rawValue)" }

    private func restore() {
        guard let y = model.nav.anchors[anchorKey].flatMap(Double.init), y > 0 else { return }
        // After layout, so the content has its new height.
        Task { @MainActor in position.scrollTo(y: y) }
    }
}

/// The art band at the top of the Page, extended under the rail.
struct PageArtBand: View {
    @Environment(AppModel.self) private var model
    var gameID: String
    var body: some View {
        ArtView(asset: model.backdrop(gameID, chapter: model.nav.chapter, tall: false), game: model.game(gameID))
            .frame(height: 170)
            .backgroundExtensionEffect()
            .overlay(alignment: .bottom) {
                LinearGradient(colors: [.clear, Color.ink0], startPoint: .top, endPoint: .bottom).frame(height: 60)
            }
            .accessibilityHidden(true)
    }
}

/// One release on the Page: header, then GR-3's story-first body, with spoilers inline (D-6).
struct ReleasePage: View {
    @Environment(AppModel.self) private var model
    var release: Release

    var body: some View {
        let r = release
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                if model.isUnread(r) { UnreadDot() }
                Text(r.displayName).font(PlayscribeFont.headline)
                ReleaseTag(release: r)
            }
            HStack(spacing: 6) {
                Text((r.isPS5Listed ? r.ps5Date : r.latestDate).shortDay)
                if let v = r.ps5Version { Text("·"); Text(v).monospacedDigit() }
            }
            .font(PlayscribeFont.subheadline).foregroundStyle(.secondary)
            SourceLinks(release: r)
            if r.isUnconfirmed { UnconfirmedBand() }
            if r.notes.contains(where: { $0.items.contains { $0.spoiler == true } }) {
                SpoilerLine(gameID: r.gameID)
            }
            ReleaseBody(release: r)
        }
        .id(r.id)
    }
}

/// V-4: the full-width band an unconfirmed release opens with.
struct UnconfirmedBand: View {
    var body: some View {
        let rule = Line().stroke(PlayscribeColor.textTertiary, style: StrokeStyle(lineWidth: 1, dash: [3, 2])).frame(height: 1)
        (Text("Unconfirmed").font(PlayscribeFont.subheadline.weight(.semibold))
            + Text(" · From press reports, not in official PS5 notes yet").font(PlayscribeFont.subheadline))
        .foregroundStyle(PlayscribeColor.textTertiary)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 10)
        .overlay(alignment: .top) { rule }
        .overlay(alignment: .bottom) { rule }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Unconfirmed on PS5, from press reports, not in official PS5 notes yet")
    }
}

nonisolated struct Line: Shape {
    func path(in r: CGRect) -> Path { Path { $0.move(to: CGPoint(x: r.minX, y: r.midY)); $0.addLine(to: CGPoint(x: r.maxX, y: r.midY)) } }
}

/// D-6: "Story spoilers hidden · Show", only when the release has spoilers.
struct SpoilerLine: View {
    @Environment(AppModel.self) private var model
    var gameID: String
    var body: some View {
        let shown = model.spoilersShown(gameID)
        Button {
            model.setSpoilersShown(gameID, !shown)
            model.show(Toast(text: shown ? "Spoilers hidden" : "Spoilers shown"))
        } label: {
            HStack(spacing: 6) {
                Image(systemName: shown ? "eye" : "eye.slash")
                Text(shown ? "Story spoilers shown · Hide" : "Story spoilers hidden · Show")
            }
            .font(PlayscribeFont.subheadline)
            .foregroundStyle(PlayscribeColor.accent)
            .frame(minHeight: 44)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .tappableFrame()
    }
}

/// GR-1: never an empty game.
struct NoNotesPage: View {
    @Environment(AppModel.self) private var model
    var game: CatalogGame
    var body: some View {
        // Terry: a game never opens blank. With no updates, it leads with its release.
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 6) {
                Text(game.ps5AvailabilityLine).font(PlayscribeFont.title3)
                Text("No updates yet · checked \(model.lastChecked.formatted(.relative(presentation: .named)))")
                    .font(PlayscribeFont.subheadline).foregroundStyle(.secondary)
            }
            GameBasicsView(game: game)
        }
    }
}

/// The game's own information: genres, launch trailer, description and story.
struct GameBasicsView: View {
    @Environment(AppModel.self) private var model
    var game: CatalogGame
    @State private var storyOpen = false
    private var store: GameInfoStore { .shared }

    var body: some View {
        let info = game.igdbID.flatMap { store.basics[$0] }
        VStack(alignment: .leading, spacing: 14) {
            if let genres = info?.genres, !genres.isEmpty {
                Text(genres.joined(separator: " · ")).font(PlayscribeFont.subheadline).foregroundStyle(.secondary)
            }
            if let videos = info?.videos, !videos.isEmpty {
                // One video per title: the feed can carry two cuts named "Launch Trailer".
                let unique = videos.reduce(into: [GameBasics.Video]()) { out, v in if !out.contains(where: { $0.name == v.name }) { out.append(v) } }
                ForEach(unique.prefix(3), id: \.youtubeId) { v in
                    Button { model.trailer = (v.youtubeId, v.name) } label: {
                        HStack(spacing: 12) {
                            AsyncImage(url: URL(string: "https://i.ytimg.com/vi/\(v.youtubeId)/mqdefault.jpg")) { $0.resizable().scaledToFill() } placeholder: { Color.ink1 }
                                .frame(width: 112, height: 63)
                                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                                .overlay { Image(systemName: "play.fill").foregroundStyle(.white) }
                            Text(v.name).font(PlayscribeFont.subheadline).lineLimit(2).multilineTextAlignment(.leading)
                            Spacer(minLength: 0)
                        }
                        .frame(minHeight: 44)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Play \(v.name)")
                    .tappableFrame()
                }
            }
            if let summary = info?.summary {
                Text("About").font(PlayscribeFont.headline)
                Text(summary).font(PlayscribeFont.body)
            }
            if let story = info?.storyline {
                Text("Story").font(PlayscribeFont.headline)
                Text(story).font(PlayscribeFont.body).lineLimit(storyOpen ? nil : 4)
                Button(storyOpen ? "Less" : "More") { withAnimation(.snappy) { storyOpen.toggle() } }
                    .font(PlayscribeFont.subheadline.weight(.semibold)).frame(minHeight: 44).tappableFrame()
            }
        }
        .task(id: game.igdbID) { if let id = game.igdbID { await store.load(igdbID: id) } }
    }
}

/// A game's trailer, from its basics (not tied to a release).
struct TrailerView: View {
    @Environment(AppModel.self) private var model
    var videoID: String
    var name: String
    @State private var controller: YouTubeController?
    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 12) {
                Color.black.aspectRatio(16 / 9, contentMode: .fit)
                    .overlay { if let controller { WebSurface(webView: controller.webView) } }
                Text(name).font(PlayscribeFont.headline).padding(.horizontal, 16)
                Spacer()
            }
            .background(Color.black)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button { model.trailer = nil } label: { Label("Close", systemImage: "xmark") }
                }
            }
        }
        .onAppear { if controller == nil { controller = YouTubeController(videoID: videoID) } }
        .onDisappear { controller?.stop() }
    }
}

/// D-4: the Contents, top to bottom: title and status, chapters, search in notes, Mark n read,
/// the release timeline, and in Tabletop the section outline with Previous and Next.
struct ContentsView: View {
    @Environment(\.railWidth) private var railWidth
    var gameID: String

    var body: some View {
        ScrollView {
            ContentsBody(gameID: gameID)
                .padding(.horizontal, 16)
                .padding(.vertical, 14)
                .padding(.trailing, railWidth)
        }
        .scrollIndicators(.hidden)
        .background(Color.ink1)
        .foldAudited()
    }
}

struct ContentsBody: View {
    @Environment(AppModel.self) private var model
    @Environment(\.duo) private var duo
    @AppStorage(ReadingSide.key) private var pageOnLeft = false
    var gameID: String

    var body: some View {
        let game = model.game(gameID)
        let chapter = model.chapters(gameID).contains(model.nav.chapter) ? model.nav.chapter : .updates
            VStack(alignment: .leading, spacing: 14) {
                if duo.pose != .closed { HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(game?.name ?? "").font(PlayscribeFont.title2).lineLimit(2)
                        if let e = model.entry(gameID) { StatusPill(status: e.status) }
                    }
                    Spacer(minLength: 8)
                } }
                if model.entry(gameID) == nil, let game {
                    Button("Add to library") { model.addGame(game, status: .watching) }
                        .buttonStyle(.borderedProminent).foregroundStyle(PlayscribeColor.onAccent).hitTarget()
                }
                ChapterBar(gameID: gameID, selected: chapter)
                NotesSearchField(gameID: gameID)
                if model.noteQuery.count >= 2 {
                    InlineNoteResults(gameID: gameID)
                } else if chapter == .updates {
                    let unread = model.releases(gameID).filter(model.isUnread).count
                    if unread > 0 {
                        Button { model.markAllRead(gameID) } label: {
                            Label("Mark \(unread) read", systemImage: "envelope.open")
                                .font(PlayscribeFont.subheadline.weight(.semibold))
                                .frame(minHeight: 44)
                        }
                        .tappableFrame()
                    }
                    if duo.pose == .tabletop {
                        TabletopOutline(gameID: gameID)
                    }
                    ReleaseTimeline(gameID: gameID)
                }
            }
    }
}

/// D-10: flips Contents and Page; shown only when they're side by side.
struct SwapSidesButton: View {
    @Binding var pageOnLeft: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    private var glyph: String { Self.glyph(pageOnLeft: pageOnLeft) }
    static func glyph(pageOnLeft: Bool) -> String { pageOnLeft ? "swap-sides.left" : "swap-sides.right" }
    static func value(pageOnLeft: Bool) -> String { pageOnLeft ? "Reading on left" : "Reading on right" }

    /// D-10: the T-2 spring, or a cross-fade under Reduce Motion (T-4).
    private func swap() {
        withAnimation(reduceMotion ? .easeInOut(duration: 0.25) : .spring(duration: 0.45, bounce: 0.12)) { pageOnLeft.toggle() }
    }
    /// On the rail with the other actions (D-6, D-10): the glyph as the icon, "Swap sides" as the title.
    var body: some View {
        Button(action: swap) {
            Label { Text("Swap sides") } icon: { Image(glyph).renderingMode(.template) }
        }
        .accessibilityIdentifier("swapSides")
        // The toolbar turns this into a bar button, which drops accessibilityValue, so VoiceOver
        // hears the side as part of the label; Voice Control still answers to "Swap sides".
        .accessibilityLabel("Swap sides, \(SwapSidesButton.value(pageOnLeft: pageOnLeft).lowercased())")
        .accessibilityInputLabels(["Swap sides"])
        .accessibilityShowsLargeContentViewer { Label("Swap sides", image: glyph) }
    }
}

/// GR-4 in the Contents: search this game's notes, or all my games.
struct NotesSearchField: View {
    @Environment(AppModel.self) private var model
    var gameID: String
    var body: some View {
        @Bindable var model = model
        let short = model.game(gameID).map(GameBookView.shortName) ?? "this game"
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                TextField(model.noteScope == .thisGame ? "Search \(short)'s notes" : "Search all my games' notes", text: $model.noteQuery)
                    .autocorrectionDisabled()
                    .submitLabel(.search)
                    .onSubmit { model.rememberSearch(model.noteQuery) }
                if !model.noteQuery.isEmpty {
                    Button { model.noteQuery = "" } label: { Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary) }
                        .accessibilityLabel("Clear search")
                }
            }
            .padding(.horizontal, 12)
            .frame(minHeight: 44)
            .background(PlayscribeColor.ink700, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            if !model.noteQuery.isEmpty {
                Picker("Search in", selection: $model.noteScope) {
                    ForEach(NoteScope.allCases, id: \.self) { Text($0.label).tag($0) }
                }
                .pickerStyle(.segmented)
            }
        }
    }
}

struct InlineNoteResults: View {
    @Environment(AppModel.self) private var model
    var gameID: String
    var body: some View {
        let hits = model.noteHits(model.noteQuery, scope: model.noteScope, gameID: gameID)
        VStack(alignment: .leading, spacing: 6) {
            if hits.isEmpty {
                let name = model.game(gameID)?.name ?? "this game"
                Text(model.noteScope == .thisGame ? "No mention of '\(model.noteQuery)' in \(name)'s PS5 notes" : "No mention of '\(model.noteQuery)' in your games' PS5 notes")
                    .font(PlayscribeFont.subheadline)
                if model.noteScope == .thisGame {
                    Button("Search all my games") { model.noteScope = .allGames }.hitTarget()
                }
            }
            ForEach(hits.filter { !$0.pcOnly } + hits.filter(\.pcOnly)) { h in
                Button {
                    model.rememberSearch(model.noteQuery)
                    if h.release.gameID == gameID { model.select(gameID, releaseID: h.release.id) }
                    else { model.openGame(h.release.gameID, chapter: .updates, releaseID: h.release.id) }
                    model.highlight = h.release.id
                    model.noteQuery = ""
                } label: {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(h.line).font(PlayscribeFont.subheadline).lineLimit(3)
                        HStack(spacing: 6) {
                            Text("\(h.release.displayName) · \(h.pcOnly ? "PC only" : h.section)").font(PlayscribeFont.caption).foregroundStyle(.secondary)
                            if h.release.isUnconfirmed { UnconfirmedChip() }
                        }
                    }
                    .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .tappableFrame()
            }
        }
    }
}

/// D-4: one 44 pt row per release; the selected row highlighted; PC-only last.
struct ReleaseTimeline: View {
    @Environment(AppModel.self) private var model
    var gameID: String

    var body: some View {
        let selected = model.selectedRelease(gameID)?.id
        let ps5 = model.ps5Releases(gameID)
        let pc = model.pcOnlyReleases(gameID)
        VStack(alignment: .leading, spacing: 4) {
            Text("RELEASES").font(PlayscribeFont.caption).tracking(1).foregroundStyle(PlayscribeColor.textTertiary)
            if ps5.isEmpty, let g = model.game(gameID) {
                Text(g.ps5AvailabilityLine).font(PlayscribeFont.subheadline)
            }
            let unconfirmed = ps5.filter(\.isUnconfirmed)
            if !unconfirmed.isEmpty {
                Text("UNCONFIRMED").font(PlayscribeFont.caption).tracking(1).foregroundStyle(PlayscribeColor.textTertiary)
                ForEach(unconfirmed) { row($0, selected: $0.id == selected) }
                if unconfirmed.count < ps5.count {
                    Text("RELEASED").font(PlayscribeFont.caption).tracking(1).foregroundStyle(PlayscribeColor.textTertiary).padding(.top, 8)
                }
            }
            ForEach(ps5.filter { !$0.isUnconfirmed }) { row($0, selected: $0.id == selected) }
            ForEach(pc) { row($0, selected: $0.id == selected) }
        }
    }

    private func row(_ r: Release, selected: Bool) -> some View {
        Button { model.select(gameID, releaseID: r.id) } label: {
            HStack(spacing: 8) {
                if model.isUnread(r) { UnreadDot() } else { Color.clear.frame(width: 8, height: 8) }
                Text(r.displayName).font(PlayscribeFont.subheadline.weight(selected ? .semibold : .regular)).lineLimit(1)
                ReleaseTag(release: r)
                Spacer(minLength: 4)
                Text((r.isPS5Listed ? r.ps5Date : r.latestDate).dayMonthOrYear).font(PlayscribeFont.caption).foregroundStyle(.secondary)
            }
            .padding(.horizontal, 10)
            .frame(minHeight: 44)
            .background(selected ? PlayscribeColor.ink700 : .clear, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            .overlay {
                if r.isUnconfirmed {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .strokeBorder(PlayscribeColor.textTertiary.opacity(0.6), style: StrokeStyle(lineWidth: 1, dash: [3, 2]))
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? .isSelected : [])
        .tappableFrame()
    }
}

/// TT-2 in the Contents: the section outline with Previous and Next.
struct TabletopOutline: View {
    @Environment(AppModel.self) private var model
    var gameID: String
    var body: some View {
        let sections = model.readerRelease(gameID).map(model.readerSections) ?? []
        let index = min(model.readerIndex[gameID] ?? 0, max(0, sections.count - 1))
        VStack(spacing: 2) {
            ForEach(Array(sections.enumerated()), id: \.element.id) { i, s in
                Button { model.readerIndex[gameID] = i } label: {
                    HStack {
                        Text(s.title).font(PlayscribeFont.subheadline.weight(i == index ? .semibold : .regular)).lineLimit(1)
                        Spacer()
                        Text("\(i + 1)").font(PlayscribeFont.caption).foregroundStyle(.secondary)
                    }
                    .padding(.horizontal, 10)
                    .frame(minHeight: 44)
                    .background(i == index ? PlayscribeColor.ink700 : .clear, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .tappableFrame()
            }
            HStack(spacing: 12) {
                pageButton("Previous", "chevron.backward", enabled: index > 0) { model.readerIndex[gameID] = index - 1 }
                pageButton("Next", "chevron.forward", enabled: index < sections.count - 1) { model.readerIndex[gameID] = index + 1 }
            }
            .padding(.top, 6)
        }
    }

    private func pageButton(_ title: String, _ symbol: String, enabled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(title, systemImage: symbol)
                .font(PlayscribeFont.headline)
                .frame(maxWidth: .infinity, minHeight: 52)
                .background(PlayscribeColor.ink700, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
        .opacity(enabled ? 1 : 0.4)
        .tappableFrame()
    }
}
