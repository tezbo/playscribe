import SwiftUI

/// PS Plus monthly games (0.5.0, r050-plus-card): this month's lineup in the Library as up to three
/// cover tiles styled like the library's (3:4, 10 pt corners, name in the art, no text under), with
/// "Last chance" in its last three days. Carries the PlayStation Plus badge; the trademark notice sits
/// under the version in Settings. A game you track opens its page. Hidden when no month holds today.
struct PlusCard: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dynamicTypeSize) private var typeSize

    static let maxCovers = 3
    /// Accessibility sizes show two so a plate name stays readable; "+N more" counts the rest.
    static func coverLimit(accessibility: Bool) -> Int { accessibility ? 2 : maxCovers }
    /// No wider than a Library tile, whatever the pose (Iris, #242).
    static let maxCoverWidth: CGFloat = 140

    private static let romans: [String: String] = ["ii": "2", "iii": "3", "iv": "4", "v": "5", "vi": "6", "vii": "7", "viii": "8", "ix": "9", "x": "10"]

    /// Title key for matching: folded, roman numerals as digits ("Alan Wake II" and "Alan Wake 2" agree), no leading "the".
    static func matchKey(_ name: String) -> String {
        var words = PS5Index.fold(name).split(separator: " ").map(String.init)
        if words.first == "the", words.count > 1 { words.removeFirst() }
        return words.map { romans[$0] ?? $0 }.joined(separator: " ")
    }

    /// The same title with its last digit word as a roman numeral, so the index's own spelling is searched too.
    private static func romanVariant(_ name: String) -> String {
        let flip = Dictionary(uniqueKeysWithValues: romans.map { ($0.value, $0.key) })
        return name.split(separator: " ").map { flip[String($0)]?.uppercased() ?? String($0) }.joined(separator: " ")
    }

    /// The catalogue game behind a lineup name: the tracked game when `gameId` is set, else an exact
    /// title match (see `matchKey`) in the bundled PS5 index. nil draws the name plate, never a near miss.
    static func resolve(_ g: PlusMonth.Game, tracked: (String) -> CatalogGame?) -> CatalogGame? {
        if let id = g.gameId, let t = tracked(id) { return t }
        let want = matchKey(g.name)
        for query in [g.name, romanVariant(g.name)] {
            if let hit = PS5Index.shared.search(query, limit: 10).first(where: { matchKey($0.name) == want }) { return hit }
        }
        return nil
    }

    var body: some View {
        if let (month, lastChance) = PlusLogic.visibleMonth(PlusStore.shared.months, cardOff: model.data.plusCardOff) {
            let claimBy = PlusLogic.claimByText(month)
            let limit = Self.coverLimit(accessibility: typeSize.isAccessibilitySize)
            let shown = Array(month.games.prefix(limit))
            VStack(alignment: .leading, spacing: 10) {
                // Wide cards put the heading beside the covers; narrow ones stack it above (Iris, #242).
                // Tries covers at 140, 120 then 100 pt beside the heading, so Open portrait, Tabletop and Closed
                // landscape get a short card; Book's one-page column stacks. Accessibility sizes always stack: beside
                // the covers the heading was squeezed to a word a line (Mac QA, AX3).
                if typeSize.isAccessibilitySize {
                    stacked(shown, lastChance: lastChance, claimBy: claimBy)
                } else {
                    ViewThatFits(in: .horizontal) {
                        sideBySide(shown, lastChance: lastChance, claimBy: claimBy, width: Self.maxCoverWidth)
                        sideBySide(shown, lastChance: lastChance, claimBy: claimBy, width: 120)
                        sideBySide(shown, lastChance: lastChance, claimBy: claimBy, width: 100)
                        stacked(shown, lastChance: lastChance, claimBy: claimBy)
                    }
                }
                // Games past the covers keep a name row, as the old card listed them: tracked ones open their page.
                ForEach(Array(month.games.dropFirst(limit).enumerated()), id: \.offset) { n, g in nameRow(g, lead: n == 0 ? "and " : "") }
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.ink2, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("plusCard")
        }
    }

    private func stacked(_ shown: [PlusMonth.Game], lastChance: Bool, claimBy: String) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            header(lastChance: lastChance, claimBy: claimBy)
            coverRow(shown, fixedWidth: nil)
        }
    }

    private func sideBySide(_ shown: [PlusMonth.Game], lastChance: Bool, claimBy: String, width: CGFloat) -> some View {
        HStack(alignment: .top, spacing: 16) {
            coverRow(shown, fixedWidth: width)
            header(lastChance: lastChance, claimBy: claimBy).frame(minWidth: 160, alignment: .leading)
                .accessibilitySortPriority(1)
            Spacer(minLength: 0)
        }
    }

    private func header(lastChance: Bool, claimBy: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            PlusBadge(height: 26).accessibilityHidden(true)
            Text(lastChance ? "Last chance" : "This month").font(PlayscribeFont.title3)
                .accessibilityLabel(lastChance ? "PS Plus, last chance" : "PS Plus, this month")
                .accessibilityAddTraits(.isHeader)
            Text("Claim by \(claimBy)").font(PlayscribeFont.subheadline).foregroundStyle(PlayscribeColor.textSecondary)
        }
    }

    /// Covers at an explicit size, never larger than `maxCoverWidth` wide (a Library tile), so no pose can stretch them
    /// (Quinn: Closed landscape drew 410 × 550 pt covers). `fixedWidth` is the side-by-side layout; nil: the row
    /// measures its own width and shrinks the covers to fit.
    @ViewBuilder private func coverRow(_ shown: [PlusMonth.Game], fixedWidth: CGFloat?) -> some View {
        PlusCoverRow(games: shown, fixedWidth: fixedWidth) { g, w in
            cover(g).frame(width: w, height: (w * 4 / 3).rounded())
        }
    }

    @ViewBuilder private func nameRow(_ g: PlusMonth.Game, lead: String = "") -> some View {
        if let id = g.gameId, model.entry(id) != nil {
            Button { model.openGame(id) } label: {
                HStack(spacing: 8) {
                    Text(lead + g.name).fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 8)
                    Image(systemName: "chevron.right").foregroundStyle(PlayscribeColor.textSecondary).accessibilityHidden(true)
                }
                .font(PlayscribeFont.subheadline)
                .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading).contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .tappableFrame()
            .accessibilityHint("Opens the game")
        } else {
            Text(lead + g.name).font(PlayscribeFont.subheadline).fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, minHeight: 28, alignment: .leading)
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
                    .overlay(Text(name).font(PlayscribeFont.footnote.weight(.semibold)).multilineTextAlignment(.center)
                        .lineLimit(4).padding(8).foregroundStyle(PlayscribeColor.textPrimary))
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

/// Lays covers out at an explicit width: `PlusCard.maxCoverWidth`, or less when the row is narrower.
struct PlusCoverRow<Content: View>: View {
    var games: [PlusMonth.Game]
    var fixedWidth: CGFloat?
    @ViewBuilder var content: (PlusMonth.Game, CGFloat) -> Content
    @State private var rowWidth: CGFloat = 0
    private let spacing: CGFloat = 10

    private var coverWidth: CGFloat {
        let cap = PlusCard.maxCoverWidth
        if let fixedWidth { return fixedWidth }
        guard rowWidth > 0, !games.isEmpty else { return cap }
        return min(cap, ((rowWidth - spacing * CGFloat(games.count - 1)) / CGFloat(games.count)).rounded(.down))
    }

    var body: some View {
        HStack(spacing: spacing) {
            ForEach(Array(games.enumerated()), id: \.offset) { _, g in content(g, coverWidth) }
            if fixedWidth == nil { Spacer(minLength: 0) }
        }
        .frame(maxWidth: fixedWidth == nil ? .infinity : nil, alignment: .leading)
        .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { rowWidth = $0 }
    }
}
