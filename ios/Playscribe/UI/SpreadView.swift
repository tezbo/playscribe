import SwiftUI

/// The Open pose, "the Spread" (docs/ux-acceptance.md §9): Art, Page and Margin in the detail
/// column, with the Library as the sidebar (landscape) or a cover shelf (portrait).
///
///   landscape: art edge to edge across the top ~44%, under the sidebar (backgroundExtensionEffect);
///              the Page is a card raised over the art's lower edge; the Margin is a trailing column.
///   portrait:  art across the top ~40%, a one-row cover shelf, then Page (~60%) and Margin (~35%).
struct SpreadView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.duo) private var duo
    var gameID: String
    @State private var headerVisible = true

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width, h = geo.size.height
            let portrait = h > w
            // O-4: a Margin column only with room for it and no fold across the detail.
            let showMargin = w >= 560 && duo.division == nil
            let marginRelease = showMargin ? marginTarget : nil
            let artH = (portrait ? 0.40 : 0.44) * h

            ZStack(alignment: .topLeading) {
                StageArt(gameID: gameID)
                    .frame(width: w, height: artH)
                    .backgroundExtensionEffect()

                VStack(alignment: .leading, spacing: 0) {
                    Color.clear.frame(height: portrait ? artH : artH * 0.85)
                    if portrait {
                        CoverShelf(selected: gameID)
                            .padding(.vertical, 10)
                    }
                    HStack(alignment: .top, spacing: 20) {
                        ReadingPanel(gameID: gameID, compact: false, headerVisible: $headerVisible, spreadPage: true)
                            .environment(\.marginReleaseID, marginRelease?.id)
                            .frame(width: showMargin ? w * (portrait ? 0.60 : 0.47) : nil)
                            .frame(maxWidth: showMargin ? nil : 680)
                            .background(Color.ink2, in: UnevenRoundedRectangle(topLeadingRadius: 20, topTrailingRadius: 20, style: .continuous))
                            .overlay(UnevenRoundedRectangle(topLeadingRadius: 20, topTrailingRadius: 20, style: .continuous)
                                .strokeBorder(PlayscribeColor.vellum300.opacity(0.25), lineWidth: 1))
                        if let r = marginRelease {
                            MarginColumn(release: r)
                                .frame(width: w * (portrait ? 0.32 : 0.25))
                                .padding(.top, portrait ? 0 : artH * 0.15 + 12)
                        }
                    }
                    .padding(.horizontal, 20)
                }
            }
        }
        .background(Color.ink0)
        .navigationTitle(headerVisible ? "" : (model.game(gameID)?.name ?? ""))
        .toolbarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarPinnedTrailing) {
                Button { model.addSheetOpen = true } label: { Label("Add game", systemImage: "plus") }
            }
            ActionToolbar(actions: model.gameActions(gameID))
        }
        .onAppear { model.nav.lastGameID = gameID }
    }

    /// The release the Margin describes: the focused one, else the newest On PS5 release.
    private var marginTarget: Release? {
        if let id = model.focusReleaseID, let r = model.release(gameID, id) { return r }
        return model.ps5Releases(gameID).first ?? model.releases(gameID).first
    }
}

/// The game's key art with its title, bottom-leading, inside the Library's width (O-2).
struct StageArt: View {
    @Environment(AppModel.self) private var model
    var gameID: String

    var body: some View {
        let game = model.game(gameID)
        ZStack(alignment: .bottomLeading) {
            ArtView(asset: model.backdrop(gameID, chapter: model.nav.chapter, tall: false), game: game, drift: true)
            LinearGradient(colors: [.clear, .black.opacity(0.7)], startPoint: .center, endPoint: .bottom)
            Text(game?.name ?? "")
                .font(PlayscribeFont.title)
                .lineLimit(2)
                .frame(maxWidth: 320, alignment: .leading)
                .padding(.leading, 20)
                .padding(.bottom, 56)
        }
        .clipped()
        .accessibilityHidden(true)
    }
}

/// The Margin: the PS5 facts for the release in view, without a card fill (O-4).
struct MarginColumn: View {
    var release: Release
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                Text(release.displayName.uppercased())
                    .font(PlayscribeFont.caption)
                    .tracking(1)
                    .foregroundStyle(PlayscribeColor.textTertiary)
                Facts(release: release)
            }
            .padding(.vertical, 12)
        }
        .scrollIndicators(.hidden)
    }
}

/// Open portrait: the Library as a one-row cover shelf, the selected game ringed in ember (O-5).
struct CoverShelf: View {
    @Environment(AppModel.self) private var model
    var selected: String

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    ForEach(model.libraryRows) { row in
                        Button { model.openGame(row.id) } label: {
                            CoverView(game: row.game, cornerRadius: 6)
                                .frame(width: 58, height: 82)
                                .overlay {
                                    if row.id == selected {
                                        RoundedRectangle(cornerRadius: 7, style: .continuous).strokeBorder(PlayscribeColor.accent, lineWidth: 2)
                                    }
                                }
                                .overlay(alignment: .topTrailing) {
                                    if row.unread > 0 { UnreadDot().padding(4) }
                                }
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(row.game.name)
                        .accessibilityAddTraits(row.id == selected ? .isSelected : [])
                        .tappableFrame()
                        .id(row.id)
                    }
                    Button { model.addSheetOpen = true } label: {
                        Image(systemName: "plus").frame(width: 58, height: 82)
                            .background(Color.ink2, in: RoundedRectangle(cornerRadius: 6, style: .continuous))
                    }
                    .accessibilityLabel("Add game")
                }
                .padding(.horizontal, 20)
            }
            .edgeFade()
            .onAppear { proxy.scrollTo(selected, anchor: .center) }
        }
    }
}

/// Book pose, left page: the art in the hero frame above the Library list (§9 table; Terry,
/// 24 Oct: the Open layout's left side on the book's left page).
struct BookLeftPage: View {
    @Environment(AppModel.self) private var model
    var gameID: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if let id = gameID, let game = model.game(id) {
                HeroFrame(asset: game.keyArtAsset, game: game)
                    .padding(.horizontal, 14)
                    .padding(.top, 8)
            }
            LibrarySidebar()
        }
        .background(Color.ink0)
    }
}

extension AppModel {
    /// O-1: Open never shows an empty detail. The chosen game, else Continue, else the most
    /// recently updated game in the library.
    var spreadGameID: String? {
        nav.gameID ?? continueItem?.game.id ?? shownRows().first?.id
    }
}
