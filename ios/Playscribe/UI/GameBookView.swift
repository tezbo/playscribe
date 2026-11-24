import SwiftUI

/// The game book (D-3, D-4, R-7). One column (GamePageColumn) in Closed and Open; in Book and Tabletop, Contents and Page in
/// one ArrangementView(.split), so the system places them on the fold.
struct GameBookView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.duo) private var duo
    @AppStorage(ReadingSide.key) private var pageOnLeft = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var gameID: String

    var body: some View {
        let game = model.game(gameID)
        Group {
            if duo.oneColumn {
                // R-7 (0.5.6, Card C): Closed and the open display in both orientations: one column, art and title scrolling
                // away, the section bar pinned, an update pushed as its own page.
                GamePageColumn(gameID: gameID)
            } else if duo.pose == .book {
                // Book: the left page is the game (art, title, the sections as a table of contents, the updates), the right
                // page the open update (spec, poses-g1). Swap sides flips them (D-10). Layout direction doesn't move
                // ArrangementView's regions, so the swap places the pieces explicitly; their state lives in the model.
                SplitArrangement {
                    if pageOnLeft { page } else { ContentsView(gameID: gameID) }
                } secondary: {
                    if pageOnLeft { ContentsView(gameID: gameID) } else { page }
                }
            } else {
                // Tabletop: the Page is the view-only standing half; the lower half starts with the section bar.
                SplitArrangement {
                    page
                } secondary: {
                    ContentsView(gameID: gameID)
                }
            }
        }
        .background(PlayscribeRole.bg)
        .navigationTitle(game?.name ?? "")
        .toolbar(removing: .title)
        .toolbarTitleDisplayMode(.inline)
        // The system back button reached VoiceOver and tests with an empty label in Closed (Mac back check, 380e71b), and its label
        // cannot be set. This one says where it goes (HIG: the previous screen's title).
        .navigationBarBackButtonHidden(true)
        .keepsSwipeBack()
        // Closed landscape (Iris, 0.5.6 walk at 1c5ebfc): the system bar had room for two of the four buttons beside the tab
        // column and dropped Back and Status. Here the rail is our own second column, immediately leading of the tab column, and
        // the page reflows beside it.
        .safeAreaInset(edge: .trailing, spacing: 0) {
            if closedLandscape { ClosedLandscapeRail(gameID: gameID) }
        }
        .toolbar {
          if !closedLandscape {
            // A system-drawn toolbar button, as the rail's others (Iris: the 36 pt floor applies). Its glass is the toolbar's own
            // shared Liquid Glass (over-art rule, role 1; the system goes solid under Reduce Transparency): our own glassEffect
            // inside a toolbar item pushed the whole game page down by the bar's height in every pose (#619 screen diffs at
            // f8fcd58), so the toolbar draws it.
            ToolbarItem(placement: .topBarLeading) {
                // A Label, like every ActionToolbar item: when the Duo opens to Book or Open landscape the bar becomes the trailing
                // rail and is rebuilt, and a custom-view item came back as an empty glass disc with no gameBack in the tree (28 of 28
                // Book dumps, run 45489150050) while the Label items beside it survived (bug-landscape-rail-back-empty).
                Button { model.closeGame() } label: {
                    Label(model.backTitle, systemImage: "chevron.backward")
                        .labelStyle(.iconOnly)
                        .foregroundStyle(PlayscribeRole.textPrimary)
                }
                // Iris (0.5.6 hotfix): "Back to <origin>", the same label on every rail.
                .accessibilityLabel(model.backTitle)
                .accessibilityIdentifier("gameBack")
            }
            // Back, Notifications, Status, More in every pose (Iris, 0.5.6 hotfix); D-10's Swap sides is in More while side by side.
            ActionToolbar(actions: model.gameActions(gameID, sideBySide: sideBySide))
          }
        }
        .onChange(of: model.swapSidesRequest) { _, _ in
            guard sideBySide else { return }
            withAnimation(reduceMotion ? .easeInOut(duration: 0.25) : .spring(duration: 0.45, bounce: 0.12)) { pageOnLeft.toggle() }
        }
        .onAppear { model.nav.lastGameID = gameID }
        // The game's full history, not only what's in the newest-100 feed.
        .task(id: gameID) { await model.refreshHistories([gameID]) }

    }

    private var closedLandscape: Bool { duo.pose == .closed && duo.isLandscape }

    /// Book, the one pose with Contents and Page side by side (D-11; Open landscape is one column since 0.5.6, R-7).
    private var sideBySide: Bool { duo.pose == .book }

    /// TT-2: in Tabletop the Page is the paged, display-only reader.
    @ViewBuilder private var page: some View {
        // G-4, TT-1: in Tabletop the standing half is never touchable, whatever the chapter.
        if duo.pose == .tabletop {
            Group {
                if model.section(gameID) == .updates { TabletopReaderStage(gameID: gameID) } else { PageView(gameID: gameID) }
            }
            .allowsHitTesting(false)
            .environment(\.viewOnlyStage, true)
            // Not touchable, so not audited as tappable: a frame here is never a fold crossing (TT-1).
            .auditActive(false)
        } else {
            PageView(gameID: gameID)
        }
    }
}

extension GameBookView {
    /// "Dawnwalker" for "The Blood of Dawnwalker": the last word of a long name, for placeholders.
    static func shortName(_ g: CatalogGame) -> String {
        let words = g.name.split(separator: " ")
        guard words.count > 2 else { return g.name }
        return words.last.map(String.init)?.trimmingCharacters(in: .punctuationCharacters) ?? g.name
    }
}

/// Closed landscape's rail (Iris, 0.5.6): Back, Notifications, Status, More top to bottom, the same buttons, order and gaps as the
/// Tabletop rail, in a 56 pt column beside the tab column. 44 pt buttons that do not grow with text; the large content viewer
/// shows each title.
struct ClosedLandscapeRail: View {
    @Environment(AppModel.self) private var model
    var gameID: String
    var body: some View {
        VStack(spacing: 6) {
            RailButton(action: ScreenAction(id: "back", title: model.backTitle, systemImage: "chevron.backward",
                                            kind: .button { model.closeGame() }))
            ForEach(model.gameActions(gameID)) { RailButton(action: $0) }
        }
        .padding(.top, 8)
        .frame(width: TabletopRail.width)
        .frame(maxHeight: .infinity, alignment: .top)
        .dynamicTypeSize(...DynamicTypeSize.large)
    }
}
