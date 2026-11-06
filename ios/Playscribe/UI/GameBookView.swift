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
            if duo.pose == .closed || (duo.pose == .flat && !duo.isLandscape) {
                // Closed, or the inner display flat in portrait (no fold, so nothing to split on):
                // one page that scrolls as one, the Contents below the Page. Two panes scrolling
                // separately, with the Page cut off mid-line, was wrong on a flat screen.
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
        // The game's full history, not only what's in the newest-100 feed.
        .task(id: gameID) { await model.refreshHistories([gameID]) }

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
            // Not touchable, so not audited as tappable: a frame here is never a fold crossing (TT-1).
            .auditActive(false)
        } else if duo.pose == .flat && !duo.isLandscape {
            // Open portrait (Iris): the Page above the sheet. A whole line, not half a line, at the sheet's edge at
            // rest: 12 pt of bottom room and a 24 pt fade to the sheet colour.
            PageView(gameID: gameID)
                .contentMargins(.bottom, 12, for: .scrollContent)
                .overlay(alignment: .bottom) {
                    // A 24 pt fade left a half line readable at the edge (0c93f25); 44 pt, solid for the last 8 pt,
                    // so a line cut by the sheet is faded out, never shown half drawn.
                    LinearGradient(stops: [.init(color: .clear, location: 0), .init(color: Color.ink0, location: 0.82)],
                                   startPoint: .top, endPoint: .bottom)
                        .frame(height: 44)
                        .allowsHitTesting(false)
                        .accessibilityHidden(true)
                }
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

    private func chip(_ c: Chapter, icons: Bool) -> some View {
        let on = c == selected
        return Button { model.nav.chapter = c } label: {
            Group {
                if icons { Label(c.title, systemImage: c.symbol) } else { Text(c.title) }
            }
            .font(PlayscribeFont.subheadline.weight(on ? .semibold : .regular))
            .lineLimit(1)
            .padding(.horizontal, 12)
            .frame(minHeight: 44)
            .background(on ? PlayscribeColor.accent.opacity(0.22) : Color.ink3, in: Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(on ? .isSelected : [])
        .tappableFrame()
        .id(c)
    }

    private func row(icons: Bool) -> some View {
        HStack(spacing: 8) { ForEach(model.chapters(gameID)) { chip($0, icons: icons) } }
            .padding(.horizontal, 2)
    }

    var body: some View {
        ScrollViewReader { proxy in
            // Every chapter in view whenever the row can hold them: with icons, else titles only (Book's
            // left page cut "My book" to "My b"). Only when even that is too wide does the row scroll.
            ViewThatFits(in: .horizontal) {
                row(icons: true).fixedSize(horizontal: true, vertical: false)
                row(icons: false).fixedSize(horizontal: true, vertical: false)
                ScrollView(.horizontal, showsIndicators: false) {
                    row(icons: true).padding(.trailing, 44)
                }
                // A wider fade so a half-seen last chip reads as "more this way", not as a bug.
                .edgeFade(44)
            }
            .onAppear { proxy.scrollTo(selected, anchor: .center) }
            .onChange(of: selected) { _, c in withAnimation { proxy.scrollTo(c, anchor: .center) } }
        }
    }
}
