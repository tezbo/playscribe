import SwiftUI

/// R-7 (0.5.6 redesign, Card C; spec.md "Game page", s3.png, poses-g1.png): the game page in the one-column poses (Closed, and
/// the open display in both orientations). Top to bottom: the art band and the title (with Add to library for a browsed game),
/// which scroll away, then the section bar, pinned, then the current section. What's new is the list of updates: search first,
/// Mark n read, every update, then About. An update opens as a pushed page (D-1, J-1); Back returns here at the same scroll.
/// On the open display the column keeps a 600 pt reading width; the art stays full width.
struct GamePageColumn: View {
    @Environment(AppModel.self) private var model
    @Environment(\.duo) private var duo
    @State private var position = ScrollPosition(idType: String.self)
    @State private var liveOffset: CGFloat = 0
    /// True once the bar has reached the top and is pinned.
    @State private var barPinned = false
    /// Where the zero-height anchor above the Section sits in the scroll view; the header compares itself with it.
    @State private var anchorY: CGFloat = 0
    var gameID: String

    /// Spec: "reading width capped at 600 pt" on the open display; Closed is narrower than that anyway.
    static let readingWidth: CGFloat = 600

    var body: some View {
        let section = model.section(gameID)
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0, pinnedViews: .sectionHeaders) {
                PageArtBand(gameID: gameID, extendsUnderRail: false)
                VStack(alignment: .leading, spacing: 16) {
                    StaleHint()
                    titleBlock
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 8)
                .frame(maxWidth: Self.readingWidth + 40, alignment: .leading)
                .frame(maxWidth: .infinity)
                Color.clear.frame(height: 0).id("sectionTop")
                    .onGeometryChange(for: CGFloat.self) { $0.frame(in: .scrollView).minY } action: { anchorY = $0 }
                Section {
                    content(section)
                        .padding(.top, 16)
                        .padding(.horizontal, 20)
                        .frame(maxWidth: Self.readingWidth + 40, alignment: .leading)
                        .frame(maxWidth: .infinity)
                } header: {
                    PinnedSectionHeader(gameID: gameID, ink: Color.ink0, maxWidth: Self.readingWidth, anchorY: anchorY, pinned: $barPinned)
                }
            }
            .padding(.bottom, 24)
        }
        // The list fades out over its last 24 pt where the scroll view ends above the floating tab bar, instead of cutting a row
        // at full brightness (Quinn, #526 at feaff25, Open portrait). The page ends 24 pt lower, so its last row rests clear.
        // An overlay in the page's ink, not a mask, so nothing that extends past the scroll view's frame is clipped.
        // The scroll view draws its rows on into the bottom safe area, below its own frame, so the fade alone left a dim band with
        // the rows bright again under it (Quinn, Closed AX5 at 722c752, Open landscape at 7cb8b33). Solid ink hangs below the
        // fade, outside the frame, to the screen edge; views laid out after the page (rail, tab bar, pill) still draw over it.
        .overlay(alignment: .bottom) {
            LinearGradient(colors: [Color.ink0.opacity(0), Color.ink0], startPoint: .top, endPoint: .bottom)
                .frame(height: 24)
                .overlay(alignment: .bottom) { Color.ink0.frame(height: 120).offset(y: 120) }
                .allowsHitTesting(false)
                .accessibilityHidden(true)
        }
        .clearsMessages()
        .scrollIndicators(.hidden)
        .scrollPosition($position)
        .accessibilityIdentifier("pageScroll")
        // J-1: Back from a pushed update lands on its row, after the stack has settled.
        .onChange(of: model.nav.detailReleaseID) { old, new in
            if new == nil, let old {
                Task { try? await Task.sleep(for: .milliseconds(250)); position.scrollTo(id: "row-\(old)", anchor: .center) }
            }
        }
        // D-2, T-5: the reading position is model state, one per section; rotating, unfolding or switching back comes back to it.
        // Persisted only when scrolling settles: writing every frame re-rendered the page (Terry, 0.2.0).
        .onScrollGeometryChange(for: CGFloat.self) { $0.contentOffset.y + $0.contentInsets.top } action: { _, y in liveOffset = y }
        .onScrollPhaseChange { _, phase in
            if phase == .idle { model.nav.anchors[anchorKey(section)] = String(Int(liveOffset)) }
        }
        .onAppear { restore(section) }
        .onChange(of: duo.pose) { restore(model.section(gameID)) }
        // Card C: switching a section keeps the bar where it is. A section seen before comes back at its own scroll; a new one
        // starts at its top, under the pinned bar, or where it is if the bar has not reached the top.
        .onChange(of: section) { old, new in
            model.nav.anchors[anchorKey(old)] = String(Int(liveOffset))
            if !restore(new), barPinned { position.scrollTo(id: "sectionTop", anchor: .top) }
        }
        .background(Color.ink0)
        .foldAudited()
    }

    @ViewBuilder private var titleBlock: some View {
        if !model.gameDisplayName(gameID).isEmpty {
            VStack(alignment: .leading, spacing: 6) {
                GameTitleWithStatus(gameID: gameID, name: model.gameDisplayName(gameID))
                // A browsed game (Upcoming, PS Plus) gets its add control with the title.
                if let g = model.game(gameID), model.entry(gameID) == nil {
                    Button("Add to library") { model.addGame(g, status: .watching) }
                        .buttonStyle(.borderedProminent).foregroundStyle(PlayscribeColor.onAccent).hitTarget()
                        .accessibilityIdentifier("addToLibrary")
                        .padding(.top, 5).padding(.bottom, -5)
                }
            }
        }
    }

    @ViewBuilder private func content(_ section: Chapter) -> some View {
        switch section {
        case .updates: WhatsNewList(gameID: gameID)
        case .news: NewsChapter(gameID: gameID)
        case .world, .companion: EntriesChapter(gameID: gameID)
        case .gallery: GalleryChapter(gameID: gameID)
        case .mybook: MyBookChapter(gameID: gameID)
        }
    }

    private func anchorKey(_ s: Chapter) -> String { "column-\(gameID)-\(s.rawValue)" }

    /// Scrolls to the saved offset for a section, after layout. False when there is none.
    @discardableResult private func restore(_ s: Chapter) -> Bool {
        guard let y = model.nav.anchors[anchorKey(s)].flatMap(Double.init), y > 0 else { return false }
        Task { @MainActor in position.scrollTo(y: y) }
        return true
    }
}

/// What's new in one column: search first (spec: "Search is the first row of What's new"), then Mark n read and every update
/// (each row pushes its page), then the game's basics. A game with no notes leads with its release instead (GR-1).
struct WhatsNewList: View {
    @Environment(AppModel.self) private var model
    var gameID: String

    var body: some View {
        let hasNotes = !model.ps5Releases(gameID).isEmpty || !model.pcOnlyReleases(gameID).isEmpty
        VStack(alignment: .leading, spacing: 16) {
            if !hasNotes, let g = model.game(gameID) {
                NoNotesPage(game: g)
            } else if !hasNotes {
                // A game nothing is known about is never a blank page (s-056).
                Text(GameBasicsView.noDetailsLine).font(PlayscribeFont.subheadline).foregroundStyle(.secondary)
                    .accessibilityIdentifier("noDetailsLine")
            } else {
                NotesSearchField(gameID: gameID)
                if model.noteQuery.count >= 2 {
                    InlineNoteResults(gameID: gameID)
                } else {
                    let unread = model.releases(gameID).filter(model.isUnread).count
                    if unread > 0 {
                        Button { model.markAllRead(gameID) } label: {
                            Label("Mark \(unread) read", systemImage: "envelope.open")
                                .font(PlayscribeFont.subheadline.weight(.semibold))
                                .frame(minHeight: 44)
                        }
                        .tappableFrame()
                    }
                    ReleaseTimeline(gameID: gameID)
                }
                if let g = model.game(gameID) {
                    Divider().overlay(PlayscribeColor.ink700)
                    GameBasicsView(game: g)
                }
            }
        }
    }
}
