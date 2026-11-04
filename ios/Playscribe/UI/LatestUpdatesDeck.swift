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
        // QA (route one-update): only the one fresh update, so the deck is a single hero.
        if qaSingleUpdate { cards = cards.filter(\.unread) }
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
    /// Open portrait: the deck is the left column beside the Also new panel, one card at a time.
    var compact = false
    /// Compact only: the whole deck (card, caption, page edge) is at most this tall (Iris: 38% of the height).
    var maxHeight: CGFloat = 0
    @State private var current: String?

    /// The page edge (44 pt leaves) and the 8 pt gap above it; the card takes the rest of maxHeight.
    private static let pageEdgeHeight: CGFloat = 52

    private var perScreen: CGFloat {
        if compact { return 1 }
        // A lone card, or the wide Closed landscape screen, takes the full content width: no card
        // narrower than its row with an empty area beside it (Iris, dc27a53 polish item 6).
        if cards.count == 1 || (duo.pose == .closed && duo.isLandscape) { return 1 }
        return switch duo.pose {
        case .closed: 1.12            // one card, the next peeking
        case .book: 1.12              // the deck lives on the left page
        case .flat: 2                 // Open, either orientation: two cards across (mock-up v3)
        default: 1.12
        }
    }

    var body: some View {
        if compact {
            // Explicit geometry: every card is exactly the column wide, so a swipe snaps card to card, and the
            // art is capped so the deck never grows past maxHeight (the 727 pt card, 20d77ea).
            GeometryReader { g in
                let art = max(96, maxHeight - Self.pageEdgeHeight)
                deck(cardWidth: g.size.width, artHeight: art)
            }
            .frame(height: maxHeight > 0 ? maxHeight : nil)
        } else {
            deck(cardWidth: nil, artHeight: nil)
        }
    }

    private func deck(cardWidth: CGFloat?, artHeight: CGFloat?) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(spacing: 12) {
                    ForEach(cards) { card in
                        Group {
                            if let w = cardWidth {
                                DeckCardView(card: card, artHeight: artHeight).frame(width: w)
                            } else {
                                DeckCardView(card: card)
                                    .containerRelativeFrame(.horizontal, count: Int((perScreen * 100).rounded()), span: 100, spacing: 12)
                            }
                        }
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
        .accessibilityElement(children: .contain)
        .accessibilityLabel(compact || cards.count > 1
            ? "Latest updates, page \((cards.firstIndex { $0.id == (current ?? cards.first?.id) } ?? 0) + 1) of \(cards.count)" : "Latest updates")
    }
}

struct DeckCardView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.duo) private var duo
    var card: DeckCard
    /// Open portrait: a fixed art height, so the card never outgrows its share of the screen.
    var artHeight: CGFloat?

    /// Closed landscape (container wider than tall): the wide hero card, never a device check.
    private var wide: Bool { duo.pose == .closed && duo.isLandscape }
    /// 40% of the container's height, 168 to 240 pt (Iris, hero-wide-layouts).
    private var wideHeight: CGFloat { min(240, max(168, duo.size.height * 0.4)) }

    var body: some View {
        let game = card.game
        Button {
            if let r = card.release { model.openGame(game.id, chapter: .updates, releaseID: r.id) }
            else { model.openGame(game.id, chapter: .updates) }
        } label: {
            if wide {
                WideDeckCard(card: card, height: wideHeight)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
            } else if let h = artHeight {
                // Open portrait (Iris): art fills the card, caption inside it with 16 pt padding, version pill top leading.
                CompactDeckCard(card: card, height: h)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
            } else {
            VStack(alignment: .leading, spacing: 8) {
                DeckCardArt(card: card, height: artHeight)
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

/// Open portrait card: fills its height with the key art, caption on a dark fade inside (16 pt padding).
struct CompactDeckCard: View {
    var card: DeckCard
    var height: CGFloat
    private var dateText: String { card.date.map(AppModel.tileDay) ?? "" }

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            ArtView(asset: card.game.keyArtAsset, game: card.game)
            LinearGradient(colors: [.clear, PlayscribeColor.ink950.opacity(0.9)], startPoint: .center, endPoint: .bottom)
            VStack(alignment: .leading, spacing: 4) {
                Text(card.release.map { $0.ps5Headline ?? $0.displayName } ?? card.game.name)
                    .font(PlayscribeFont.title3).foregroundStyle(PlayscribeColor.textPrimary).lineLimit(3)
                HStack(spacing: 8) {
                    Text(card.game.name).foregroundStyle(PlayscribeColor.textPrimary)
                    if card.release != nil { Text(dateText).foregroundStyle(PlayscribeColor.textSecondary) }
                }
                .font(PlayscribeFont.subheadline).lineLimit(1)
            }
            .padding(16)
        }
        .overlay(alignment: .topLeading) {
            HStack(spacing: 6) {
                if let v = card.release?.versionChip { chip(v, filled: false) }
                if card.unread { chip("New update", filled: true) }
                if card.release == nil, let d = card.date { chip("Released " + AppModel.tileDay(d), filled: false) }
            }
            .padding(12)
        }
        .frame(height: height)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(PlayscribeColor.vellum100.opacity(0.6), lineWidth: 1.5))
        .accessibilityHidden(true)
    }

    private func chip(_ text: String, filled: Bool) -> some View {
        Text(text).font(PlayscribeFont.caption).monospacedDigit()
            .foregroundStyle(filled ? PlayscribeColor.ink950 : PlayscribeColor.accent)
            .padding(.horizontal, 8).frame(height: 22)
            .background(Capsule().fill(filled ? PlayscribeColor.accent : PlayscribeColor.ink950.opacity(0.75)))
    }
}

/// Closed landscape hero: art left to right with a dark fade from the leading edge; the caption
/// (New update chip, game name, one-line summary) on the leading 55%, the version chip trailing.
struct WideDeckCard: View {
    var card: DeckCard
    var height: CGFloat

    var body: some View {
        GeometryReader { g in
            ZStack(alignment: .leading) {
                ArtView(asset: card.game.keyArtAsset, game: card.game)
                LinearGradient(colors: [PlayscribeColor.ink950.opacity(0.92), PlayscribeColor.ink950.opacity(0.55), .clear],
                               startPoint: .leading, endPoint: .trailing)
                VStack(alignment: .leading, spacing: 6) {
                    if card.unread { chip("New update", filled: true) }
                    Text(card.game.name).font(PlayscribeFont.title2.bold())
                        .foregroundStyle(PlayscribeColor.textPrimary).lineLimit(2)
                    Text(card.release.map { $0.ps5Headline ?? $0.displayName } ?? "Released " + (card.date.map(AppModel.tileDay) ?? ""))
                        .font(PlayscribeFont.subheadline).foregroundStyle(PlayscribeColor.textPrimary.opacity(0.9))
                        // Two lines, never an ellipsis mid-sentence (Iris, hero-wide-layouts).
                        .lineLimit(2).fixedSize(horizontal: false, vertical: true)
                }
                .padding(16)
                .frame(width: g.size.width * 0.55, alignment: .leading)
            }
            .overlay(alignment: .topTrailing) {
                if let v = card.release?.versionChip { chip(v, filled: false).padding(12) }
            }
        }
        .frame(height: height)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(PlayscribeColor.vellum100.opacity(0.6), lineWidth: 1.5))
        .accessibilityHidden(true)
    }

    private func chip(_ text: String, filled: Bool) -> some View {
        Text(text).font(PlayscribeFont.caption).monospacedDigit()
            .foregroundStyle(filled ? PlayscribeColor.ink950 : PlayscribeColor.accent)
            .padding(.horizontal, 8).frame(height: 22)
            .background(Capsule().fill(filled ? PlayscribeColor.accent : PlayscribeColor.ink950.opacity(0.75)))
    }
}

/// With a height, the art fills the card's width at exactly that height (cropped), else 16:9.
private struct FixedArtHeight: ViewModifier {
    var height: CGFloat?
    func body(content: Content) -> some View {
        if let h = height {
            Color.clear.frame(maxWidth: .infinity).frame(height: h)
                .overlay { content.aspectRatio(nil, contentMode: .fill) }
                .clipped()
        } else { content }
    }
}

/// The art in the lit frame, with the chips. Display only; the card is the button.
struct DeckCardArt: View {
    var card: DeckCard
    var height: CGFloat?
    var body: some View {
        // The 16:9 box comes from a clear base, so the art's own size never sets the card's height (a Book
        // hero came out as tall as the screen when the proposal had no height).
        Color.clear.aspectRatio(16 / 9, contentMode: .fit)
            .overlay { ArtView(asset: card.game.keyArtAsset, game: card.game) }
            .clipped()
            .modifier(FixedArtHeight(height: height))
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

    /// At most 5 leaves, in a window that slides with the current card (Iris, 6589abf): the current one
    /// ember and tall, the outer ones of a longer deck smaller, centred under the deck.
    private var window: [(index: Int, card: DeckCard)] {
        let all = Array(cards.enumerated())
        guard all.count > 5 else { return all.map { ($0.offset, $0.element) } }
        let cur = cards.firstIndex { $0.id == current } ?? 0
        let start = min(max(0, cur - 2), all.count - 5)
        return all[start..<(start + 5)].map { ($0.offset, $0.element) }
    }

    var body: some View {
        HStack(spacing: 0) {
            ForEach(window, id: \.card.id) { item in
                let isCurrent = item.card.id == current
                // The ends of a window that has more cards beyond it are drawn smaller.
                let trimmed = cards.count > 5 && !isCurrent
                    && ((item.index == window.first?.index && item.index > 0) || (item.index == window.last?.index && item.index < cards.count - 1))
                Button { select(item.card.id) } label: {
                    RoundedRectangle(cornerRadius: 1.5)
                        .fill(isCurrent ? PlayscribeColor.accent : (item.card.unread ? PlayscribeColor.vellum100 : PlayscribeColor.textSecondary.opacity(0.5)))
                        .frame(width: trimmed ? 2 : 3, height: isCurrent ? 18 : (trimmed ? 6 : 10))
                        .frame(width: 44, height: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .tappableFrame()
                .accessibilityLabel("Update \(item.index + 1) of \(cards.count)")
                .accessibilityAddTraits(isCurrent ? [.isButton, .isSelected] : .isButton)
            }
        }
        .frame(maxWidth: .infinity, alignment: .center)
    }
}

/// Tabletop's standing half: the selected card as content only (G-4); the page edge below drives it.
struct DeckStage: View {
    var card: DeckCard
    @Environment(\.duo) private var duo
    @State private var stageBottom: CGFloat = 0

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
            // The caption ends 24 pt above the division, measured in screen space (as in 0.2.0 #174/#176).
            .padding(.bottom, duo.clearance(forBottom: stageBottom))
        }
        .onGeometryChange(for: CGFloat.self) { $0.frame(in: .global).maxY } action: { stageBottom = $0 }
        .allowsHitTesting(false)
        .accessibilityElement(children: .contain)
    }
}
