import SwiftUI

/// One card of the Latest updates hero (0.5.0 item 1, J-1 to J-4). `release` is nil for a
/// release-info card, shown only when nothing in the library updated in the last 90 days.
struct DeckCard: Identifiable, Hashable {
    var game: CatalogGame
    var release: Release?
    var unread: Bool
    var date: Date?
    var id: String { release.map { "u-" + $0.id } ?? "r-" + game.id }

    static func == (a: DeckCard, b: DeckCard) -> Bool { a.id == b.id }
    func hash(into h: inout Hasher) { h.combine(id) }
}

extension AppModel {
    /// Up to 8 cards: unread On PS5 updates first, then the rest from the last 90 days, newest first.
    /// With nothing in 90 days, the newest release dates of the library's games.
    var latestDeck: [DeckCard] {
        let cutoff = Date.now.addingTimeInterval(-90 * 86400)
        var cards: [DeckCard] = []
        for c in data.collection {
            guard let g = game(c.gameID) else { continue }
            for r in ps5Releases(c.gameID) where r.ps5State == .onPS5 {
                let unread = isUnread(r)
                if unread || r.ps5Date > cutoff { cards.append(DeckCard(game: g, release: r, unread: unread, date: r.ps5Date)) }
            }
        }
        if cards.isEmpty {
            let info = data.collection.compactMap { c -> DeckCard? in
                guard let g = game(c.gameID), let d = g.releaseDate?.isoDay, d <= .now else { return nil }
                return DeckCard(game: g, release: nil, unread: false, date: d)
            }
            return Array(info.sorted { ($0.date ?? .distantPast) > ($1.date ?? .distantPast) }.prefix(8))
        }
        cards.sort { a, b in
            a.unread != b.unread ? a.unread : (a.date ?? .distantPast) > (b.date ?? .distantPast)
        }
        // At most 2 cards per game, so one busy game cannot fill the deck (Quinn, PR 55).
        var perGame: [String: Int] = [:]
        let spread = cards.filter { c in
            perGame[c.game.id, default: 0] += 1
            return perGame[c.game.id]! <= 2
        }
        return Array(spread.prefix(8))
    }
}

/// Cards visible at once per pose: Closed one with the next peeking, Open two.
struct LatestUpdatesDeck: View {
    @Environment(AppModel.self) private var model
    @Environment(\.duo) private var duo
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var cards: [DeckCard]
    @State private var current: String?

    private var perScreen: CGFloat {
        switch duo.pose {
        case .closed: 1.12            // one card, the next peeking
        case .book: 1.12              // the deck lives on the left page
        case .flat: 2                 // Open, either orientation: two cards across (mock-up v3)
        default: 1.12
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(spacing: 12) {
                    ForEach(cards) { card in
                        DeckCardView(card: card)
                            .containerRelativeFrame(.horizontal, count: Int((perScreen * 100).rounded()), span: 100, spacing: 12)
                            .id(card.id)
                    }
                }
                .scrollTargetLayout()
            }
            .scrollPosition(id: $current)
            .onChange(of: current) { _, new in model.deckSelection = new }
            .scrollTargetBehavior(.viewAligned)
            .contentMargins(.trailing, 0, for: .scrollContent)
            if cards.count > 1 {
                PageEdge(cards: cards, current: current ?? cards.first?.id) { id in
                    withAnimation(reduceMotion ? .easeInOut(duration: 0.2) : .snappy) { current = id }
                }
            }
        }
    }
}

struct DeckCardView: View {
    @Environment(AppModel.self) private var model
    var card: DeckCard

    var body: some View {
        let game = card.game
        Button {
            if let r = card.release { model.openGame(game.id, chapter: .updates, releaseID: r.id) }
            else { model.openGame(game.id, chapter: .updates) }
        } label: {
            VStack(alignment: .leading, spacing: 8) {
                DeckCardArt(card: card)
                Text(card.release.map { $0.ps5Headline ?? $0.displayName } ?? game.name)
                    .font(PlayscribeFont.title3).foregroundStyle(PlayscribeColor.textPrimary)
                    .lineLimit(2).fixedSize(horizontal: false, vertical: true)
                HStack(spacing: 8) {
                    Text(game.name).foregroundStyle(PlayscribeColor.textPrimary)
                    if card.release != nil { Text(dateText).foregroundStyle(PlayscribeColor.textSecondary) }
                }
                .font(PlayscribeFont.subheadline).lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .tappableFrame()
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(label)
        .accessibilityAddTraits(.isButton)
    }

    private var dateText: String { card.date.map(AppModel.tileDay) ?? "" }
    private var label: String {
        if let r = card.release { return "\(card.unread ? "New update, " : "")\(r.ps5Headline ?? r.displayName), \(card.game.name), \(dateText)" }
        return "\(card.game.name), released \(dateText)"
    }
}

/// The art in the lit frame, with the chips. Display only; the card is the button.
struct DeckCardArt: View {
    var card: DeckCard
    var body: some View {
        ArtView(asset: card.game.keyArtAsset, game: card.game)
            .aspectRatio(16 / 9, contentMode: .fit)
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(PlayscribeColor.vellum100.opacity(0.6), lineWidth: 1.5))
            .overlay(alignment: .topLeading) {
                HStack(spacing: 6) {
                    if card.unread { chip("New update", filled: true) }
                    if let v = card.release?.versionChip { chip(v, filled: false) }
                    if card.release == nil, let d = card.date { chip("Released " + AppModel.tileDay(d), filled: false) }
                }
                .padding(10)
            }
            .accessibilityHidden(true)
    }

    private func chip(_ text: String, filled: Bool) -> some View {
        Text(text).font(PlayscribeFont.caption).monospacedDigit()
            .foregroundStyle(filled ? PlayscribeColor.ink950 : PlayscribeColor.accent)
            .padding(.horizontal, 8).frame(height: 22)
            .background(Capsule().fill(filled ? PlayscribeColor.accent : PlayscribeColor.ink950.opacity(0.75)))
    }
}

/// The page edge: one leaf per update, unread in ember, the current one tall in vellum.
/// Each leaf is a 44 pt target labelled "Update n of N".
struct PageEdge: View {
    var cards: [DeckCard]
    var current: String?
    var select: (String) -> Void

    var body: some View {
        // 8 leaves at 44 pt are 352 pt: when that does not fit (Closed, the Book's left page), the
        // edge scrolls sideways instead of overflowing.
        ViewThatFits(in: .horizontal) {
            leaves
            ScrollView(.horizontal, showsIndicators: false) { leaves }
        }
        .frame(maxWidth: .infinity, alignment: .center)
    }

    private var leaves: some View {
        HStack(spacing: 0) {
            ForEach(Array(cards.enumerated()), id: \.element.id) { i, card in
                let isCurrent = card.id == current
                Button { select(card.id) } label: {
                    RoundedRectangle(cornerRadius: 1.5)
                        .fill(isCurrent ? PlayscribeColor.vellum100 : (card.unread ? PlayscribeColor.accent : PlayscribeColor.textSecondary.opacity(0.5)))
                        .frame(width: 3, height: isCurrent ? 18 : 10)
                        .frame(width: 44, height: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .tappableFrame()
                .accessibilityLabel("Update \(i + 1) of \(cards.count)")
                .accessibilityAddTraits(isCurrent ? [.isButton, .isSelected] : .isButton)
            }
        }
    }
}

/// Tabletop's standing half: the selected card as content only (G-4); the page edge below drives it.
struct DeckStage: View {
    var card: DeckCard
    @Environment(\.duo) private var duo
    @State private var stageHeight: CGFloat = 0

    /// Polish 1: in Tabletop the caption sits at least 24 pt above the division, never under it.
    private var clearance: CGFloat {
        guard let d = duo.division else { return 0 }
        let overlap = stageHeight - d.minY
        return overlap > 0 ? overlap + 4 : 0
    }

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            ArtView(asset: card.game.keyArtAsset, game: card.game, drift: true)
            LinearGradient(colors: [.clear, PlayscribeColor.ink950.opacity(0.85)], startPoint: .center, endPoint: .bottom)
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 8) {
                    if card.unread { Text("New update").foregroundStyle(PlayscribeColor.accent) }
                    if let v = card.release?.versionChip { Text(v).monospacedDigit().foregroundStyle(PlayscribeColor.textSecondary) }
                }
                .font(PlayscribeFont.caption)
                Text(card.release.map { $0.ps5Headline ?? $0.displayName } ?? card.game.name)
                    .font(PlayscribeFont.title3).foregroundStyle(PlayscribeColor.textPrimary).lineLimit(3)
                HStack(spacing: 8) {
                    Text(card.game.name).foregroundStyle(PlayscribeColor.textPrimary)
                    if let d = card.date { Text(AppModel.tileDay(d)).foregroundStyle(PlayscribeColor.textSecondary) }
                }
                .font(PlayscribeFont.subheadline)
            }
            .padding(20)
            .padding(.bottom, clearance)
        }
        .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { stageHeight = $0 }
        .allowsHitTesting(false)
        .accessibilityElement(children: .contain)
    }
}
