import SwiftUI

/// The game book (D-3, D-4): Contents and Page in one ArrangementView(.split), so the system
/// places them for every pose; closed, the Page with the Contents below it.
struct GameBookView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.duo) private var duo
    @AppStorage(ReadingSide.key) private var pageOnLeft = false
    var gameID: String

    var body: some View {
        let game = model.game(gameID)
        Group {
            if duo.pose == .closed {
                // Closed (or any compact width, D-11): the stacked game book, Contents hidden.
                PageView(gameID: gameID, withContents: true)
            } else if sideBySide {
                // Side by side: Contents left, Page right by default (D-10).
                // Layout direction doesn't move ArrangementView's regions, so the swap places the
                // pieces explicitly. Their state lives in the model (selection, search, scroll
                // anchors), so it carries across.
                ArrangementView {
                    if pageOnLeft { page } else { ContentsView(gameID: gameID) }
                } secondary: {
                    if pageOnLeft { ContentsView(gameID: gameID) } else { page }
                }
                .arrangementViewStyle(.split)
            } else {
                // Stacked: the Page on top (the standing half in Tabletop), the Contents below.
                ArrangementView {
                    page
                } secondary: {
                    ContentsView(gameID: gameID)
                }
                .arrangementViewStyle(.split)
            }
        }
        .background(Color.ink0)
        .navigationTitle(game?.name ?? "")
        .toolbar(removing: .title)
        .toolbarTitleDisplayMode(.inline)
        .toolbar {
            ActionToolbar(actions: model.gameActions(gameID))
            // D-10: only when Contents and Page are side by side; absent, not disabled, otherwise.
            if sideBySide {
                ToolbarSpacer(.fixed, placement: .primaryAction)
                ToolbarItem(placement: .primaryAction) { SwapSidesButton(pageOnLeft: $pageOnLeft) }
            }
        }
        .onAppear { model.nav.lastGameID = gameID }
    }

    /// Open landscape and Book in a regular-width scene (D-11).
    private var sideBySide: Bool { duo.pose != .closed && duo.pose != .tabletop && duo.isLandscape }

    /// TT-2: in Tabletop the Page is the paged, display-only reader.
    @ViewBuilder private var page: some View {
        // G-4, TT-1: in Tabletop the standing half is never touchable, whatever the chapter.
        if duo.pose == .tabletop {
            Group {
                if model.nav.chapter == .updates { TabletopReaderStage(gameID: gameID) } else { PageView(gameID: gameID) }
            }
            .allowsHitTesting(false)
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

/// R-7: chapters as a scrolling row with an edge fade; the selected chip scrolls into view.
struct ChapterBar: View {
    @Environment(AppModel.self) private var model
    var gameID: String
    var selected: Chapter

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(model.chapters(gameID)) { c in
                        let on = c == selected
                        Button { model.nav.chapter = c } label: {
                            Label(c.title, systemImage: c.symbol)
                                .font(PlayscribeFont.subheadline.weight(on ? .semibold : .regular))
                                .padding(.horizontal, 12)
                                .frame(minHeight: 44)
                                .background(on ? PlayscribeColor.accent.opacity(0.22) : Color.ink3, in: Capsule())
                        }
                        .buttonStyle(.plain)
                        .accessibilityAddTraits(on ? .isSelected : [])
                        .tappableFrame()
                        .id(c)
                    }
                }
                .padding(.horizontal, 2)
                .padding(.trailing, 24)
            }
            .edgeFade()
            .onAppear { proxy.scrollTo(selected, anchor: .center) }
            .onChange(of: selected) { _, c in withAnimation { proxy.scrollTo(c, anchor: .center) } }
        }
    }
}
