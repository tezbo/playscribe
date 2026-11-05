import SwiftUI

/// PS Plus monthly games (0.5.0, r050-plus-card): this month's lineup in the Library as up to three
/// cover tiles styled like the library's (3:4, 10 pt corners, name in the art, no text under), with
/// "Last chance" in its last three days. Carries the PlayStation Plus badge; the trademark notice sits
/// under the version in Settings. A game you track opens its page. Hidden when no month holds today.
struct PlusCard: View {
    @Environment(AppModel.self) private var model

    static let maxCovers = 3

    /// The catalogue game behind a lineup name: the tracked game when `gameId` is set, else an exact
    /// (accent- and case-folded) title match in the bundled PS5 index. nil draws the name plate.
    static func resolve(_ g: PlusMonth.Game, tracked: (String) -> CatalogGame?) -> CatalogGame? {
        if let id = g.gameId, let t = tracked(id) { return t }
        let want = PS5Index.fold(g.name)
        return PS5Index.shared.search(g.name, limit: 5).first { PS5Index.fold($0.name) == want }
    }

    var body: some View {
        if let (month, lastChance) = PlusLogic.current(PlusStore.shared.months) {
            let claimBy = PlusLogic.claimByText(month)
            let shown = Array(month.games.prefix(Self.maxCovers))
            VStack(alignment: .leading, spacing: 10) {
                VStack(alignment: .leading, spacing: 2) {
                    PlusBadge(height: 26)
                    Text(lastChance ? "Last chance" : "This month").font(PlayscribeFont.title3)
                        .accessibilityAddTraits(.isHeader)
                    Text("Claim by \(claimBy)").font(PlayscribeFont.subheadline).foregroundStyle(PlayscribeColor.textSecondary)
                }
                HStack(spacing: 10) {
                    ForEach(Array(shown.enumerated()), id: \.offset) { _, g in cover(g) }
                    // Fewer than three: keep each cover the width of a third.
                    ForEach(0..<(Self.maxCovers - shown.count), id: \.self) { _ in Color.clear.aspectRatio(3 / 4, contentMode: .fit) }
                }
                if month.games.count > Self.maxCovers {
                    Text("+\(month.games.count - Self.maxCovers) more this month")
                        .font(PlayscribeFont.footnote).foregroundStyle(PlayscribeColor.textSecondary)
                }
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.ink2, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("plusCard")
        }
    }

    @ViewBuilder private func cover(_ g: PlusMonth.Game) -> some View {
        let game = Self.resolve(g) { model.game($0) }
        let art = PlusCover(name: g.name, game: game)
        if let id = g.gameId, model.entry(id) != nil {
            Button { model.openGame(id) } label: { art }
                .buttonStyle(.plain)
                .tappableFrame()
                .accessibilityLabel(g.name)
                .accessibilityHint("Opens the game")
        } else {
            art.accessibilityElement().accessibilityLabel(g.name)
        }
    }
}

/// One lineup cover: the library's TileCover, or the ink plate with the name when the index has no match.
struct PlusCover: View {
    var name: String
    var game: CatalogGame?
    var body: some View {
        Group {
            if let game { TileCover(game: game) }
            else {
                RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Color.ink1)
                    .overlay(Text(name).font(PlayscribeFont.title3).multilineTextAlignment(.center)
                        .minimumScaleFactor(0.6).padding(8).foregroundStyle(PlayscribeColor.textPrimary))
                    .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(.white.opacity(0.1), lineWidth: 1))
            }
        }
        .aspectRatio(3 / 4, contentMode: .fit)
    }
}

/// The PlayStation Plus badge, bundled (never hotlinked). The artwork has black type, so it sits on a vellum pill
/// to stay readable on the ink card.
struct PlusBadge: View {
    var height: CGFloat
    var body: some View {
        Image("ps-plus-badge").resizable().scaledToFit().frame(height: height)
            .padding(.horizontal, height * 0.4).padding(.vertical, height * 0.2)
            .background(Color(red: 0.984, green: 0.957, blue: 0.902), in: Capsule())
            .accessibilityLabel("PlayStation Plus")
            .accessibilityAddTraits(.isImage)
    }
}
