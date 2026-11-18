import SwiftUI

/// The game book (D-3, D-4): Contents and Page in one ArrangementView(.split), so the system
/// places them for every pose; closed, the Page with the Contents below it.
struct GameBookView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.duo) private var duo
    @AppStorage(ReadingSide.key) private var pageOnLeft = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
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
                SplitArrangement {
                    if pageOnLeft { page } else { ContentsView(gameID: gameID) }
                } secondary: {
                    if pageOnLeft { ContentsView(gameID: gameID) } else { page }
                }
            } else {
                // Stacked: the Page on top (the standing half in Tabletop), the Contents below.
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
        // Closed landscape (Iris, 0.5.6 walk at 1c5ebfc): the system bar had room for two of the four buttons beside the tab
        // column and dropped Back and Status. Here the rail is our own second column, immediately leading of the tab column, and
        // the page reflows beside it.
        .safeAreaInset(edge: .trailing, spacing: 0) {
            if closedLandscape { ClosedLandscapeRail(gameID: gameID) }
        }
        .toolbar {
          if !closedLandscape {
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
                // Iris (0.5.6 hotfix): "Back to <origin>", the same label on the Tabletop rail.
                .accessibilityLabel("Back to Library")
                .accessibilityIdentifier("gameBack")
            }
            .sharedBackgroundVisibility(.hidden)
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

/// R-7: chapters in one row when they fit, wrapped onto a second row when they do not.
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
        // Every chapter is always in view (Quinn, #331): one row with icons, else one row of titles, else the
        // chips wrap onto a second row (AX sizes, narrow columns). Nothing hides behind a scroll.
        ViewThatFits(in: .horizontal) {
            row(icons: true).fixedSize(horizontal: true, vertical: false)
            row(icons: false).fixedSize(horizontal: true, vertical: false)
            FlowLayout(spacing: 8) {
                ForEach(model.chapters(gameID)) { chip($0, icons: false) }
            }
            .padding(.horizontal, 2)
        }
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
            RailButton(action: ScreenAction(id: "back", title: "Back to Library", systemImage: "chevron.backward",
                                            kind: .button { model.closeGame() }))
            ForEach(model.gameActions(gameID)) { RailButton(action: $0) }
        }
        .padding(.top, 8)
        .frame(width: TabletopRail.width)
        .frame(maxHeight: .infinity, alignment: .top)
        .dynamicTypeSize(...DynamicTypeSize.large)
    }
}
