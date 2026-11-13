import SwiftUI

/// The game book (D-3, D-4, R-7). One column (GamePageColumn) in Closed and Open; in Book and Tabletop, Contents and Page in
/// one ArrangementView(.split), so the system places them on the fold.
struct GameBookView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.duo) private var duo
    @AppStorage(ReadingSide.key) private var pageOnLeft = false
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
        .background(Color.ink0)
        .navigationTitle(game?.name ?? "")
        .toolbar(removing: .title)
        .toolbarTitleDisplayMode(.inline)
        // The system back button reached VoiceOver and tests with an empty label in Closed (Mac back check, 380e71b), and its label
        // cannot be set. This one says where it goes (HIG: the previous screen's title).
        .navigationBarBackButtonHidden(true)
        .keepsSwipeBack()
        .toolbar {
            // A custom 44 x 44 button (Iris: the 36 pt floor is for system-drawn toolbar buttons only), so no system glass around it:
            // the glass would size it to about 38. The chevron stays centred, whatever the frame.
            ToolbarItem(placement: .topBarLeading) {
                Button { model.closeGame() } label: {
                    Image(systemName: "chevron.backward")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(Color.primary)
                        .frame(width: 44, height: 44)
                        .background(Circle().fill(.regularMaterial))
                        .contentShape(Rectangle())
                }
                .accessibilityLabel(model.backTitle)
                .accessibilityIdentifier("gameBack")
            }
            .sharedBackgroundVisibility(.hidden)
            ActionToolbar(actions: model.gameActions(gameID))
            // D-10: only when Contents and Page are side by side; absent, not disabled, otherwise.
            if sideBySide {
                ToolbarSpacer(.fixed, placement: .primaryAction)
                ToolbarItem(placement: .primaryAction) { SwapSidesButton(pageOnLeft: $pageOnLeft) }
            }
        }
        .onAppear { model.nav.lastGameID = gameID }
        // The game's full history, not only what's in the newest-100 feed.
        .task(id: gameID) { await model.refreshHistories([gameID]) }

    }

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
