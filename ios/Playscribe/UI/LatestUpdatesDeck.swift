import SwiftUI

/// One card of the Latest updates hero (0.5.0 item 1, J-1 to J-4). `release` is nil for a
/// release-info card, shown only when nothing in the library updated in the last 90 days.
struct DeckCard: Identifiable, Hashable {
    var game: CatalogGame
    var release: Release?
    var unread: Bool
    var date: Date?
    /// The chip on an unread card: "New update", or "Day-one patch" (r060-dayone-patch-alert-app); nil once read.
    var freshLabel: String? = nil
    /// The unread chip's words: "Day-one patch" for a day-one patch, else "New update".
    var chipText: String { freshLabel ?? FreshCopy.newUpdate }
    var id: String { release.map { "u-" + $0.id } ?? "r-" + game.id }

    // `unread` is part of equality: SwiftUI skips re-rendering a view whose Equatable inputs compare equal, so a card that
    // went from unread to read (opened, or Mark as read) kept its "New update" chip on the Library deck (Mac, 9c62a8b).
    static func == (a: DeckCard, b: DeckCard) -> Bool { a.id == b.id && a.unread == b.unread }
    func hash(into h: inout Hasher) { h.combine(id); h.combine(unread) }

    /// The line under a hero headline for a card with no release: the headline is already the game name, so the line
    /// never repeats it (r053-hero-duplicate-title-no-notes). A game the feed does not follow says so, as the Page does.
    static func noReleaseLine(tracked: Bool) -> String {
        tracked ? "No patch notes yet" : "We don’t track this game’s updates yet"
    }
}

extension AppModel {
    /// Up to 5 cards, one per game (one dot each): games with an unread On PS5 update first, then the rest from the last 90 days, newest first.
    /// With nothing in 90 days, the newest release dates of the library's games.
    static let deckLimit = 5
    var latestDeck: [DeckCard] { Array(latestDeckAll.prefix(Self.deckLimit)) }

    /// Updates beyond the deck's 5 cards: the Open portrait "+N more updates" chip opens the Updates list.
    var latestDeckOverflow: Int { max(0, latestDeckAll.count - Self.deckLimit) }

    private var latestDeckAll: [DeckCard] {
        let cutoff = Date.now.addingTimeInterval(-90 * 86400)
        var cards: [DeckCard] = []
        for c in data.collection {
            guard let g = game(c.gameID) else { continue }
            // A launch marker is history, not an update (bug-061).
            for r in ps5Releases(c.gameID) where r.ps5State == .onPS5 && r.launch != true && !qaNoReleases {
                let unread = isUnread(r)
                if unread || r.ps5Date > cutoff { cards.append(DeckCard(game: g, release: r, unread: unread, date: r.ps5Date, freshLabel: freshLabel(r))) }
            }
        }
        if cards.isEmpty {
            let info = data.collection.compactMap { c -> DeckCard? in
                guard let g = game(c.gameID), let d = g.releaseDate?.isoDay, d <= .now else { return nil }
                return DeckCard(game: g, release: nil, unread: false, date: d)
            }
            return info.sorted { ($0.date ?? .distantPast) > ($1.date ?? .distantPast) }
        }
        // QA (route one-update): only the one fresh update, so the deck is a single hero.
        if qaSingleUpdate { cards = cards.filter(\.unread) }
        cards.sort { a, b in
            a.unread != b.unread ? a.unread : (a.date ?? .distantPast) > (b.date ?? .distantPast)
        }
        // One card per game (bug-hero-deck-one-per-game, Iris 13 Nov): the sort above puts a game's unread updates first, newest
        // first, then its read ones, so the first card seen for a game is its newest unread update, or its newest if none is unread.
        // Older hotfixes of the same game never take a card, and the page dots equal the games shown.
        var seen = Set<String>()
        let spread = cards.filter { seen.insert($0.game.id).inserted }
        guard qaPadDeck, !spread.isEmpty else { return spread }
        var padded = spread, n = 0
        while padded.count < 12 {
            var c = spread[n % spread.count]
            if var r = c.release { r.id += "-qa\(n)"; c.release = r }
            padded.append(c); n += 1
        }
        return padded
    }
}

/// Cards visible at once per pose: Closed one with the next peeking, Open two.
struct LatestUpdatesDeck: View {
    @Environment(AppModel.self) private var model
    @Environment(\.duo) private var duo
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var typeSize
    var cards: [DeckCard]
    /// Open portrait: the deck is full width, one card at a time.
    var compact = false
    /// Compact only: the whole deck (card, caption, page edge) is at most this tall (Iris: 38% of the height).
    var maxHeight: CGFloat = 0
    /// Compact only: updates beyond the deck's cards; a trailing "+N more updates" chip in the dots row opens the list.
    var moreCount: Int = 0
    @State private var current: String?
    /// Accessibility sizes: each card's measured height. The deck's frame grows to the tallest, so a long headline
    /// grows the card instead of overflowing it upwards.
    @State private var captionH: CGFloat = 0
    /// Closed landscape: the pager's own width, so a wide card is exactly that wide and never wider than its container
    /// (AX5: the card ran past the right edge and lost its border and corner).
    @State private var pagerWidth: CGFloat = 0
    /// The pager rests at its scroll end (the last card flush on the trailing edge).
    @State private var atEnd = false

    /// The page edge (44 pt leaves) and the 8 pt gap above it; the card takes the rest of maxHeight.
    private static let pageEdgeHeight: CGFloat = 52
    /// Accessibility sizes: room for the "+N more updates" chip on its own row (two wrapped lines and a gap).
    private static let chipRowAX: CGFloat = 96

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

    var body: some View { content.namedFrame("latestDeck") }

    /// `base`, or at accessibility sizes the tallest caption plus the page edge when that is more.
    private func grown(_ base: CGFloat) -> CGFloat {
        guard typeSize.isAccessibilitySize, captionH > 0 else { return base }
        return min(max(base, captionH + edgeHeight), max(base, axCap))
    }

    /// The art height of a card: `base`, or at accessibility sizes tall enough for the whole caption, never past the
    /// J-5 bound; a caption that still does not fit sheds its lowest-priority lines (`AdaptiveCaption`).
    private func grownArt(_ base: CGFloat) -> CGFloat {
        guard typeSize.isAccessibilitySize else { return base }
        return min(max(base, captionH), max(base, axCap - edgeHeight))
    }

    /// Whether the dots row (page edge, and/or the "+N more updates" chip) is on screen under the deck.
    private var hasEdgeRow: Bool { cards.count > 1 || (compact && moreCount > 0) }
    private var edgeHeight: CGFloat { hasEdgeRow ? Self.pageEdgeHeight : 0 }

    /// Compact: the card's art height. The card keeps `maxHeight` less the page edge whether or not that row shows.
    private var compactArt: CGFloat { grownArt(max(96, maxHeight - Self.pageEdgeHeight)) }

    /// J-5: the deck is at most half the container's height (the harness allows 12 pt more; 4 pt here for rounding).
    private var axCap: CGFloat { (duo.size.height * 0.5).rounded(.down) + 4 }

    /// Accessibility sizes: every card's caption laid out invisibly at the card's width, so the tallest sets the card's
    /// height from a real measurement, not from what a scroll view offers (the headline was clipped off the top).
    @ViewBuilder private func ruler(width: CGFloat) -> some View {
        if typeSize.isAccessibilitySize {
            ZStack(alignment: .topLeading) {
                ForEach(cards) { card in
                    CompactCaption(card: card).frame(width: width, alignment: .leading).fixedSize(horizontal: false, vertical: true)
                }
            }
            .opacity(0).allowsHitTesting(false).accessibilityHidden(true)
            .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { captionH = $0 }
        }
    }

    @ViewBuilder private var content: some View {
        if compact {
            // Explicit geometry: every card is exactly the column wide, so a swipe snaps card to card, and the
            // art is capped so the deck never grows past maxHeight (the 727 pt card, 20d77ea).
            GeometryReader { g in
                deck(cardWidth: g.size.width, artHeight: compactArt)
                    .background(alignment: .topLeading) { ruler(width: g.size.width) }
            }
            // The wrapped chip at accessibility sizes sits on its own row under the dots: the deck grows by that row.
            // The page-edge row is reserved only when it shows (several cards, or the "+N more" chip): a lone update has
            // no dots, so the deck ends at the card and nothing is left empty under it (0.5.3, Iris: dead space under the hero).
            .frame(height: maxHeight > 0 ? compactArt + edgeHeight + (typeSize.isAccessibilitySize && moreCount > 0 ? Self.chipRowAX : 0) : nil)
        } else if typeSize.isAccessibilitySize && !(duo.pose == .closed && duo.isLandscape) {
            // Accessibility sizes: one card per screen at an explicit height. The unsized pager let the card fill the
            // screen (7fe84f4, AX3).
            GeometryReader { g in
                deck(cardWidth: g.size.width, artHeight: grownArt(axArtHeight))
                    .background(alignment: .topLeading) { ruler(width: g.size.width) }
            }
            .frame(height: grown(axArtHeight + (cards.count > 1 ? Self.pageEdgeHeight : 0)))
        } else if duo.pose == .closed && duo.isLandscape {
            // Closed landscape: the wide card's height is set on the pager itself (40% of the container,
            // 168 to 240 pt); a horizontal ScrollView otherwise sizes to what it is offered (151 pt drawn).
            deck(cardWidth: nil, artHeight: nil, scrollHeight: WideDeckCard.height(container: duo.size.height, accessibility: typeSize.isAccessibilitySize))
        } else {
            // Full-width stacked layouts (Open landscape, Closed portrait) at the default text size: explicit geometry
            // too. The unsized pager took the height it was offered, so with 28 games the card ran off the screen
            // (e869273: 835 x 727 pt in Open, a screen-tall card in Closed portrait). Bounded to 38% of the height.
            GeometryReader { g in
                deck(cardWidth: Self.cardWidth(in: g.size.width, perScreen: perScreen), artHeight: stackedArtHeight)
            }
            .frame(height: stackedArtHeight + (cards.count > 1 ? Self.pageEdgeHeight : 0))
        }
    }

    /// One card's width so that `perScreen` cards fit the container (the next one peeking when it is 1.12), 12 pt apart.
    static func cardWidth(in container: CGFloat, perScreen: CGFloat) -> CGFloat {
        let gaps = max(0, perScreen.rounded(.up) - 1) * 12
        return max(120, ((container - gaps) / perScreen).rounded(.down))
    }

    /// The art is 38% of the container height, less the page edge, 120 pt at least.
    private var stackedArtHeight: CGFloat {
        max(120, (duo.size.height * 0.38).rounded() - (cards.count > 1 ? Self.pageEdgeHeight : 0))
    }

    /// 40% of the container, 200 pt at least; independent of the column width so the frame and the card agree.
    private var axArtHeight: CGFloat { max(200, (duo.size.height * 0.4).rounded()) }


    private var visibleCards: Int { max(1, Int(perScreen.rounded(.down))) }

    /// The card the page edge and the page label count from: at the scroll end it is the first of the last whole screen
    /// (Open: card 4 of 5; Closed: card 5), whatever id the scroll view last reported.
    private var shownID: String? {
        guard let i = cards.firstIndex(where: { $0.id == (current ?? cards.first?.id) }) else { return cards.first?.id }
        return cards[Self.shownIndex(current: i, count: cards.count, visible: visibleCards, atEnd: atEnd)].id
    }

    static func shownIndex(current: Int, count: Int, visible: Int, atEnd: Bool) -> Int {
        atEnd && count > visible ? count - visible : min(current, max(0, count - 1))
    }

    /// J-8 (Mac de571b0a): a leaf whose card cannot lead the screen (the last one, or the last two in Open) scrolls the
    /// LAST card to the trailing edge, the scroll end. Asking the pager to lead with an unreachable card overshot the end by
    /// 16 pt in Open landscape and 2 pt in Closed portrait, the right card cut at the edge.
    static func tapTarget(index: Int, count: Int, visible: Int) -> (index: Int, trailing: Bool) {
        index >= count - visible ? (count - 1, true) : (index, false)
    }

    private func pageEdge(_ proxy: ScrollViewProxy) -> some View {
        // Open shows two cards across: both are lit, so the last leaf lights when the deck reaches its end (Iris on #512).
        PageEdge(cards: cards, current: shownID, visible: visibleCards) { id in
            guard let i = cards.firstIndex(where: { $0.id == id }) else { return }
            let t = Self.tapTarget(index: i, count: cards.count, visible: visibleCards)
            withAnimation(reduceMotion ? .easeInOut(duration: 0.2) : .snappy) {
                if t.trailing { proxy.scrollTo(cards[t.index].id, anchor: .trailing) } else { current = id }
            }
        }
    }

    private func deck(cardWidth: CGFloat?, artHeight: CGFloat?, scrollHeight: CGFloat? = nil) -> some View {
        // Closed landscape at accessibility sizes: the pager is as tall as the card's caption, not a fixed height.
        let wideAX = scrollHeight != nil && typeSize.isAccessibilitySize && pagerWidth > 0
        return ScrollViewReader { proxy in VStack(alignment: .leading, spacing: 8) {
            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(alignment: .top, spacing: 12) {
                    ForEach(cards) { card in
                        Group {
                            if let w = cardWidth {
                                DeckCardView(card: card, artHeight: artHeight).frame(width: w)
                            } else if scrollHeight != nil, pagerWidth > 0 {
                                DeckCardView(card: card, wideWidth: pagerWidth).frame(width: pagerWidth)
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
            // Compact: the pager is exactly the card's height, so a taller dots row (the "+N more updates" chip wraps at
            // accessibility sizes) can never squeeze the card and clip its bottom edge.
            .frame(height: wideAX ? nil : (scrollHeight ?? (compact ? artHeight : nil)))
            .fixedSize(horizontal: false, vertical: wideAX)
            .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { if scrollHeight != nil, abs($0 - pagerWidth) > 0.5 { pagerWidth = $0 } }
            .scrollPosition(id: $current)
            .onScrollGeometryChange(for: Bool.self, of: { g in
                g.contentSize.width > g.containerSize.width + 1
                    && g.contentOffset.x + g.containerSize.width >= g.contentSize.width + g.contentInsets.trailing - 1
            }, action: { _, end in atEnd = end })
            .onChange(of: current) { _, new in model.deckSelection = new }
            // One card per flick, however fast (Iris on #512: a 120 pt flick in Open landscape jumped KCD to Phantom Blade).
            .scrollTargetBehavior(.viewAligned(limitBehavior: .alwaysByOne))
            .contentMargins(.trailing, 0, for: .scrollContent)
            // Closed landscape (scrollHeight set): the dots sit inside the hero's bottom edge, centred, so the
            // first screen still shows the chips and the first tile row (Iris, cf6c889).
            // At accessibility sizes the caption fills the card, and the dots drew over its text (Closed landscape AX5,
            // bug-deck-card-closed-landscape-ax5-dots-order): there they sit in their own row under the card, as in Closed portrait.
            .overlay(alignment: .bottom) { if scrollHeight != nil && !typeSize.isAccessibilitySize && cards.count > 1 { pageEdge(proxy) } }
            if (scrollHeight == nil || typeSize.isAccessibilitySize) && (cards.count > 1 || (compact && moreCount > 0)) {
                // The dots row: dots centred, the "+N more updates" chip trailing (Iris), a 44 pt control that wraps at AX.
                // At accessibility sizes the chip takes its own row under the dots, so the dots always read as dots.
                let showChip = compact && moreCount > 0
                let chip = Button { model.nav.tab = .updates } label: {
                    HStack(spacing: 4) {
                        Text("+\(moreCount) more updates").multilineTextAlignment(.trailing)
                        Image(systemName: "chevron.right").accessibilityHidden(true)
                    }
                    // The action role, not the raw accent: the chip sits on the page, and the light accent on cream was about 2:1
                    // (#594, Iris). Light is the action brown (as Skip tour); dark keeps the accent.
                    .font(PlayscribeFont.subheadline.weight(.semibold)).foregroundStyle(PlayscribeRole.action)
                    .frame(minHeight: 44)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .tappableFrame()
                .accessibilityLabel("\(moreCount) more updates, opens the Updates list")
                if typeSize.isAccessibilitySize {
                    VStack(alignment: .trailing, spacing: 0) {
                        if cards.count > 1 { pageEdge(proxy).frame(maxWidth: .infinity) }
                        if showChip { chip }
                    }
                } else {
                    ZStack(alignment: .trailing) {
                        if cards.count > 1 { pageEdge(proxy) }
                        if showChip { chip }
                    }
                }
            }
        }
        } // ScrollViewReader
        .accessibilityElement(children: .contain)
        .accessibilityLabel(compact || cards.count > 1
            ? "Latest updates, page \((cards.firstIndex { $0.id == shownID } ?? 0) + 1) of \(cards.count)" : "Latest updates")
        .accessibilityIdentifier("latestDeckPager")
    }
}

struct DeckCardView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.duo) private var duo
    @Environment(\.dynamicTypeSize) private var typeSize
    var card: DeckCard
    /// Open portrait: a fixed art height, so the card never outgrows its share of the screen.
    var artHeight: CGFloat?
    /// Closed landscape: the pager's measured width (0 until known).
    var wideWidth: CGFloat = 0

    /// Closed landscape (container wider than tall): the wide hero card, never a device check.
    private var wide: Bool { duo.pose == .closed && duo.isLandscape }
    /// 40% of the container's height, 168 to 240 pt (Iris, hero-wide-layouts).
    private var wideHeight: CGFloat { WideDeckCard.height(container: duo.size.height, accessibility: typeSize.isAccessibilitySize) }

    var body: some View {
        let game = card.game
        Button {
            if let r = card.release { model.openFromDeck(game.id, releaseID: r.id) }
            else { model.openGame(game.id, chapter: .updates) }
        } label: {
            if wide {
                WideDeckCard(card: card, height: wideHeight, width: wideWidth)
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
                Text(card.release.map { $0.ps5Headline ?? $0.displayName } ?? game.name.gluingTrailingNumeral)
                    .font(PlayscribeFont.title3).foregroundStyle(PlayscribeColor.textPrimary)
                    .lineLimit(typeSize.isAccessibilitySize ? 3 : 2).fixedSize(horizontal: false, vertical: true)
                DeckByline(card: card, dateText: dateText)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
            }
        }
        .buttonStyle(.plain)
        .tappableFrame()
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(label)
        .accessibilityIdentifier("deckCard")
        .accessibilityAddTraits(.isButton)
    }

    private var dateText: String { card.date.map(AppModel.tileDay) ?? "" }
    private var label: String { Self.label(card, tracked: model.feedTracksGame(card.game.id)) }

    /// The card's one VoiceOver element. It never reads the type size: at AX3 and above the visible summary is dropped (Iris: by
    /// design), and this label is where the summary stays (r054-deck-card-voiceover-label-ax3, Iris's condition).
    static func label(_ card: DeckCard, tracked: Bool) -> String {
        let dateText = card.date.map(AppModel.tileDay) ?? ""
        if let r = card.release {
            let summary = (r.summary?.isEmpty == false) ? ", \(r.summary!)" : ""
            return "\(card.unread ? card.chipText + ", " : "")\(r.ps5Headline ?? r.displayName), \(card.game.name), \(r.deckVersionChip.map { $0 + ", " } ?? "")\(dateText)\(summary)"
        }
        return "\(card.game.name), released \(dateText), \(DeckCard.noReleaseLine(tracked: tracked).lowercased())"
    }
}

/// Open portrait card: fills its height with the key art, caption on a dark fade inside (16 pt padding).
struct CompactDeckCard: View {
    var card: DeckCard
    var height: CGFloat
    @State private var captionHeight: CGFloat = 0
    @Environment(\.colorSchemeContrast) private var contrast
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.qaSolid) private var qaSolid
    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        // The caller gives a `height` that already holds the whole caption at accessibility sizes (measured by the deck's
        // ruler), so nothing can overflow the card; the art and its scrim are the background.
        // Light art (Iris, taste pass): no veil over the art and no grey haze. heroGround rises from the bottom only, clear at 55%
        // of the card's height up, eased to 90% by the caption's top edge and held under it, so the art above stays clean and the
        // caption sits on ink (white text on 90% ink950 over white art is about 15:1).
        AdaptiveCaption(card: card)
            .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { captionHeight = $0 }
            .frame(maxWidth: .infinity, alignment: .bottomLeading)
            .frame(height: height, alignment: .bottomLeading)
            .background {
                ZStack(alignment: .bottomLeading) {
                    ArtView(asset: card.game.keyArtAsset, game: card.game)
                    // Increase Contrast / Reduce Transparency: a solid ink scrim behind the caption, not a fade.
                    if contrast == .increased || reduceTransparency || qaSolid {
                        PlayscribeColor.ink950.opacity(0.92).frame(height: height * 0.45)
                            .frame(maxHeight: .infinity, alignment: .bottom)
                    } else {
                        HeroGroundRise(cardHeight: height, captionHeight: captionHeight)
                    }
                }
            }
            // The same top-left spot on every card, on 75% ink, the label-on-art rule (Iris, over-art-materials.md).
            .overlay(alignment: .topLeading) {
                if !typeSize.isAccessibilitySize { HStack(spacing: 6) { DeckChips(card: card) }.padding(12) }
            }
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(PlayscribeColor.vellum100.opacity(0.6), lineWidth: 1.5))
            .accessibilityHidden(true)
    }
}

/// heroGround rising from a hero card's bottom edge (Iris, taste pass on light art): clear at `reach` of the card's height up,
/// eased (smoothstep) to `strength` by the caption's top edge, held to the bottom. A caption taller than `reach` still gets at
/// least `minRamp` of ease above it, so there is never a hard edge.
struct HeroGroundRise: View {
    var cardHeight: CGFloat
    var captionHeight: CGFloat
    var reach: CGFloat = 0.55
    var strength: Double = 0.9
    var minRamp: CGFloat = 40

    /// The ramp (clear to full) and the solid part under it, in points.
    static func bands(cardHeight: CGFloat, captionHeight: CGFloat, reach: CGFloat, minRamp: CGFloat) -> (ramp: CGFloat, solid: CGFloat) {
        let solid = min(max(captionHeight, 0), cardHeight)
        let ramp = min(max(cardHeight * reach - solid, minRamp), max(cardHeight - solid, 0))
        return (ramp, solid)
    }

    var body: some View {
        let b = Self.bands(cardHeight: cardHeight, captionHeight: captionHeight, reach: reach, minRamp: minRamp)
        VStack(spacing: 0) {
            LinearGradient(stops: (0...16).map { i in
                let t = Double(i) / 16
                return Gradient.Stop(color: PlayscribeColor.heroGround.opacity(strength * t * t * (3 - 2 * t)), location: t)
            }, startPoint: .top, endPoint: .bottom)
            .frame(height: b.ramp)
            PlayscribeColor.heroGround.opacity(strength).frame(height: b.solid)
        }
        .frame(maxHeight: .infinity, alignment: .bottom)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

/// The caption of an Open portrait / Book / Closed hero card: chips (accessibility sizes only, as a row above the headline),
/// headline and byline, with its padding. The deck measures it, at the card's width, to size the card.
struct CompactCaption: View {
    var card: DeckCard
    /// Accessibility sizes, when the card is capped by J-5: how many words of the headline to show. Fewer than all of
    /// them ends the headline in "..." after a whole word, never mid-word. nil is the whole headline. Chips never go.
    var words: Int?
    /// Standard sizes: false drops the summary line, for a card too short to hold it whole with the chip row (AdaptiveCaption).
    var summary = true
    @Environment(\.dynamicTypeSize) private var typeSize
    private var dateText: String { card.date.map(AppModel.tileDay) ?? "" }

    /// The summary cut at a word boundary (never mid-word, Iris 2026-11-06): the first sentence if it is short
    /// enough, else whole words up to `limit` characters, then an ellipsis.
    static func wholeWords(_ text: String, limit: Int) -> String {
        let t = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if let end = t.firstIndex(where: { ".!?".contains($0) }), t.distance(from: t.startIndex, to: end) < limit {
            return String(t[...end])
        }
        guard t.count > limit else { return t }
        let head = String(t.prefix(limit))
        let cut = head.lastIndex(of: " ").map { String(head[..<$0]) } ?? head
        return cut.trimmingCharacters(in: CharacterSet(charactersIn: " ,;:-")) + "…"
    }

    static func headline(_ card: DeckCard) -> String {
        card.release.map { $0.ps5Headline ?? $0.displayName } ?? card.game.name
    }

    private var headline: String {
        let full = Self.headline(card)
        guard let n = words else { return full }
        let parts = full.split(separator: " ", omittingEmptySubsequences: true)
        guard n < parts.count else { return full }
        return parts.prefix(max(1, n)).joined(separator: " ") + "\u{2026}"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: typeSize.isAccessibilitySize ? 2 : 4) {
            // Accessibility sizes: the chips join the caption (side by side when they fit, else stacked; coordinator, 28c6063 Book
            // AX3), so a tall caption never runs under them. Standard sizes: top left on the art, on 75% ink (DeckChips).
            if typeSize.isAccessibilitySize {
                DeckChipRow(card: card).padding(.bottom, 6)
            }
            Text(headline)
                .font(PlayscribeFont.title3).foregroundStyle(PlayscribeColor.textPrimary)
                // The whole headline, or whole words and an ellipsis (AX rule: at most 4 lines), never scaled down.
                .lineLimit(typeSize.isAccessibilitySize ? nil : 3).fixedSize(horizontal: false, vertical: true)
            // One-line summary under the headline: whole words, at most 2 lines, dropped at accessibility sizes (its
            // text stays in the VoiceOver label).
            if summary, !typeSize.isAccessibilitySize, let text = card.release?.summary, !text.isEmpty {
                SummaryLines(text: text)
            }
            DeckByline(card: card, dateText: dateText)
        }
        .padding(.horizontal, 16)
        // Tighter top and bottom at accessibility sizes keeps the grown deck inside its 50% bound (J-5).
        .padding(.vertical, typeSize.isAccessibilitySize ? 12 : 16)
        // The hero is a bounded picture caption: its text stops growing at AX3 (the card's VoiceOver label is unchanged).
        // At AX5 a 4-line headline, two chip rows and the byline cannot fit a card that J-5 holds to half the screen.
        .dynamicTypeSize(...DynamicTypeSize.accessibility3)
    }
}

/// A hero card's summary in at most two lines, always ending on a whole word: the longest whole-word cut (100, 70 or 45
/// characters) that wraps into two lines. A lineLimit cut mid-word ("refineme…") once the chip row joined the caption.
struct SummaryLines: View {
    var text: String
    private var twoLines: CGFloat { ceil(UIFont.preferredFont(forTextStyle: .subheadline).lineHeight * 2) + 1 }
    var body: some View {
        ViewThatFits(in: .vertical) {
            ForEach([100, 70, 45], id: \.self) { limit in
                Text(CompactCaption.wholeWords(text, limit: limit)).font(PlayscribeFont.subheadline)
                    .foregroundStyle(PlayscribeColor.textPrimary.opacity(0.85))
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxHeight: twoLines, alignment: .topLeading)
    }
}

/// The caption at the card's height: the whole caption when it fits, else the headline loses whole words from its end
/// until it does (J-5 caps the card); the chips and the byline always stay.
struct AdaptiveCaption: View {
    var card: DeckCard
    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        if typeSize.isAccessibilitySize {
            let count = CompactCaption.headline(card).split(separator: " ", omittingEmptySubsequences: true).count
            ViewThatFits(in: .vertical) {
                CompactCaption(card: card, words: nil)
                ForEach(Array(stride(from: count - 1, through: 1, by: -1)), id: \.self) { n in
                    CompactCaption(card: card, words: n)
                }
            }
        } else {
            // The whole caption when it fits the card; else without the summary line, so nothing is cut (chips, headline and
            // byline always stay).
            ViewThatFits(in: .vertical) {
                CompactCaption(card: card)
                CompactCaption(card: card, summary: false)
            }
        }
    }
}

/// A hero card's chips in its caption, at accessibility sizes: side by side when they fit, else stacked, never dropped
/// (coordinator, 28c6063 Book AX3). Standard sizes: one line that never wraps.
struct DeckChipRow: View {
    var card: DeckCard
    @Environment(\.dynamicTypeSize) private var typeSize
    var body: some View {
        if typeSize.isAccessibilitySize {
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 6) { DeckChips(card: card) }
                VStack(alignment: .leading, spacing: 6) { DeckChips(card: card) }
            }
        } else {
            HStack(spacing: 6) { DeckChips(card: card) }
                .fixedSize(horizontal: true, vertical: false)
                .frame(minHeight: 22, alignment: .leading)
        }
    }
}

/// The version, "New update" and "Released" chips of a hero card.
struct DeckChips: View {
    var card: DeckCard

    /// One entry per chip, drawn through a ForEach so a Layout (FlowLayout) gets one subview per chip; a multi-view body
    /// was one subview there, and the chips drew on top of each other ("New update" lost under "v1.1", Book AX3).
    private var items: [(text: String, filled: Bool)] {
        var list: [(text: String, filled: Bool)] = []
        if let v = card.release?.deckVersionChip { list.append((v, false)) }
        if card.unread { list.append((card.chipText, true)) }
        if card.release == nil, let d = card.date { list.append(("Released " + AppModel.tileDay(d), false)) }
        return list
    }

    var body: some View {
        ForEach(items, id: \.text) { chip($0.text, filled: $0.filled) }
    }

    private func chip(_ text: String, filled: Bool) -> some View {
        Text(text.keepingVersionsTogether).font(PlayscribeFont.caption).monospacedDigit().lineLimit(1)
            .foregroundStyle(filled ? PlayscribeColor.ink950 : PlayscribeColor.accent)
            .padding(.horizontal, 8).frame(minHeight: 22)
            .modifier(DeckChipGround(filled: filled))
    }
}

/// The game name and date under a hero headline. Standard sizes: one line, name then date. Accessibility
/// sizes: the name wraps to two lines and the date takes its own line, so nothing truncates mid-word.
struct DeckByline: View {
    var card: DeckCard
    var dateText: String
    /// Accessibility sizes, when the card is capped: the name on one line.
    var tight = false
    @Environment(\.dynamicTypeSize) private var typeSize
    /// Optional so a preview or test host without the model does not crash; an absent model reads as tracked.
    @Environment(AppModel.self) private var model: AppModel?

    var body: some View {
        if card.release == nil {
            // The headline is the game name already; say why there is no update instead of repeating it.
            let line = DeckCard.noReleaseLine(tracked: model?.feedTracksGame(card.game.id) ?? true)
            if typeSize.isAccessibilitySize {
                // Whole-word cut, trailing punctuation trimmed before the ellipsis (never mid-word).
                WholeWordText(text: line, font: PlayscribeFont.subheadline, lines: tight ? 2 : 3, color: PlayscribeColor.textPrimary.opacity(0.9))
            } else {
                Text(line)
                    .foregroundStyle(PlayscribeColor.textPrimary.opacity(0.9)).shadow(color: .black.opacity(0.5), radius: 2)
                    .lineLimit(2).fixedSize(horizontal: false, vertical: true)
                    .font(PlayscribeFont.subheadline)
            }
        } else if typeSize.isAccessibilitySize {
            // One text, name then date, so the date shares the name's last line: a line less than name and date
            // stacked, which is what the headline needs under the J-5 cap.
            Group {
                if card.release != nil && !dateText.isEmpty {
                    Text("\(Text(card.game.name.gluingTrailingNumeral).foregroundStyle(PlayscribeColor.textPrimary))  \(Text(dateText).foregroundStyle(PlayscribeColor.textSecondary))")
                } else {
                    Text(card.game.name.gluingTrailingNumeral).foregroundStyle(PlayscribeColor.textPrimary)
                }
            }
            .lineLimit(tight ? 2 : 3).fixedSize(horizontal: false, vertical: true)
            .font(PlayscribeFont.subheadline)
        } else {
            HStack(spacing: 8) {
                Text(card.game.name.gluingTrailingNumeral).foregroundStyle(PlayscribeColor.textPrimary)
                if card.release != nil { Text(dateText).foregroundStyle(PlayscribeColor.textSecondary) }
            }
            .font(PlayscribeFont.subheadline).lineLimit(1)
        }
    }
}

/// Closed landscape hero: art left to right with a dark fade from the leading edge; the caption
/// (New update chip, the patch name, then the game name) on the leading 55%.
struct WideDeckCard: View {
    var card: DeckCard
    var height: CGFloat
    /// The pager's width once measured; the AX card sizes itself from its caption and this width.
    var width: CGFloat = 0
    @Environment(\.dynamicTypeSize) private var typeSize
    /// Accessibility sizes: a little taller (still inside J-5's half of the container) so the caption is whole.
    private var cardHeight: CGFloat { height }
    /// 40% of the container, 168 to 240 pt (Iris, hero-wide-layouts); at accessibility sizes up to 232 pt, never past the J-5
    /// bound (half the container plus 4 pt). The pager's frame uses this same height, so it never clips the card.
    static func height(container: CGFloat, accessibility: Bool) -> CGFloat {
        let base = min(240, max(168, container * 0.4))
        return accessibility ? max(base, min(232, (container * 0.5).rounded(.down) + 4)) : base
    }

    var body: some View {
        if typeSize.isAccessibilitySize && width > 0 { accessibilityCard } else { standardCard }
    }

    /// The caption's two lines (bug-deck-card-closed-landscape-ax5-dots-order, Nadia): the patch name leads, as in every other
    /// deck card and on the update page, with the game name under it. A card with no release leads with the game name (the
    /// shared deck headline) and says when it was released.
    static func lines(_ card: DeckCard) -> (headline: String, sub: String) {
        let headline = CompactCaption.headline(card)
        if card.release != nil { return (headline, card.game.name.gluingTrailingNumeral) }
        return (headline, "Released " + (card.date.map(AppModel.tileDay) ?? ""))
    }

    /// Accessibility sizes: the card is as tall as its caption (at least the base height), so nothing is cut. J-5's half-container
    /// bound is not held here, only in Closed landscape: showing the whole caption wins (Iris, never drop chips or cut lines).
    /// The headline at the AX3 cap, at most three lines: the whole text when it fits, else whole words and "…", never a cut word.
    private var subline: some View {
        let full = Self.lines(card).sub
        let words = full.split(separator: " ", omittingEmptySubsequences: true).map(String.init)
        let ax3 = UITraitCollection(preferredContentSizeCategory: .accessibilityExtraLarge)
        let maxH = ceil(UIFont.preferredFont(forTextStyle: .subheadline, compatibleWith: ax3).lineHeight * 3)
        let variants = [full] + (words.count > 1 ? Array(stride(from: words.count - 1, through: 1, by: -1)).map { words.prefix($0).joined(separator: " ") + "\u{2026}" } : [])
        return ViewThatFits(in: .vertical) {
            ForEach(variants, id: \.self) { v in
                Text(v).font(PlayscribeFont.subheadline).foregroundStyle(PlayscribeColor.textPrimary.opacity(0.9))
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxHeight: maxH, alignment: .topLeading)
    }

    private var accessibilityCard: some View {
        VStack(alignment: .leading, spacing: 6) {
            captionChips
            Text(Self.lines(card).headline).font(PlayscribeFont.title2.bold())
                .foregroundStyle(PlayscribeColor.textPrimary).fixedSize(horizontal: false, vertical: true)
            subline
        }
        .padding(.horizontal, 16).padding(.vertical, 16)
        .frame(width: width * 0.8, alignment: .leading)
        .frame(maxWidth: .infinity, minHeight: height, alignment: .leading)
        .background {
            ZStack {
                ArtView(asset: card.game.keyArtAsset, game: card.game)
                LinearGradient(colors: [PlayscribeColor.ink950.opacity(0.92), PlayscribeColor.ink950.opacity(0.7), .clear],
                               startPoint: .leading, endPoint: .trailing)
            }
        }
        .dynamicTypeSize(...DynamicTypeSize.accessibility3)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(PlayscribeColor.vellum100.opacity(0.6), lineWidth: 1.5))
        .accessibilityHidden(true)
    }

    private var standardCard: some View {
        GeometryReader { g in
            ZStack(alignment: .leading) {
                ArtView(asset: card.game.keyArtAsset, game: card.game)
                LinearGradient(colors: [PlayscribeColor.ink950.opacity(0.92), PlayscribeColor.ink950.opacity(0.55), .clear],
                               startPoint: .leading, endPoint: .trailing)
                VStack(alignment: .leading, spacing: 6) {
                    captionChips
                    let lines = Self.lines(card)
                    // The patch name leads (two lines, whole words), the game name under it.
                    WholeWordText(text: lines.headline, font: PlayscribeFont.title2.bold(), lines: 2, color: PlayscribeColor.textPrimary)
                    Text(lines.sub)
                        .font(PlayscribeFont.subheadline).foregroundStyle(PlayscribeColor.textPrimary.opacity(0.9))
                        .lineLimit(1).fixedSize(horizontal: false, vertical: true)
                }
                .padding(.horizontal, 16).padding(.vertical, typeSize.isAccessibilitySize ? 22 : 16)
                .frame(width: g.size.width * 0.55, alignment: .leading)
            }
        }
        .dynamicTypeSize(...DynamicTypeSize.accessibility3)
        .frame(height: cardHeight)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(PlayscribeColor.vellum100.opacity(0.6), lineWidth: 1.5))
        .accessibilityHidden(true)
    }

    /// The unread and version chips, on the caption's ink side, never on the art (Iris, taste pass: a top-trailing version chip
    /// sat on a character's hair).
    /// The row keeps its 22 pt height without a chip, so every wide card matches in height (Iris).
    private var captionChips: some View {
        HStack(spacing: 6) {
            if card.unread { chip(card.chipText, filled: true) }
            if let v = card.release?.deckVersionChip { chip(v, filled: false) }
        }
        .fixedSize(horizontal: true, vertical: false)
        .frame(minHeight: 22, alignment: .leading)
        // One 8 pt step above the title (the caption's spacing is 6).
        .padding(.bottom, 2)
    }

    private func chip(_ text: String, filled: Bool) -> some View {
        Text(text.keepingVersionsTogether).font(PlayscribeFont.caption).monospacedDigit().lineLimit(1)
            .foregroundStyle(filled ? PlayscribeColor.ink950 : PlayscribeColor.accent)
            .padding(.horizontal, 8).padding(.vertical, 2).frame(minHeight: 22)
            .modifier(DeckChipGround(filled: filled))
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
            // The same top-left spot on every card, on 75% ink (Iris, over-art-materials.md).
            .overlay(alignment: .topLeading) { HStack(spacing: 6) { DeckChips(card: card) }.padding(10) }
            .accessibilityHidden(true)
    }
}

/// The hero's page indicator (Iris, after Terry on beta 4: the capsule marks were "terribly ugly"). One 6 pt dot per update,
/// 10 pt apart, centred under the deck; the cards on screen are ONE pill, 6 pt tall, spanning exactly their dots (one card: a dot;
/// two: 22 pt). Unlit dots are textSecondary at 35%, the pill the action colour (amber in dark, action brown in light). No
/// animation, under Reduce Motion or not: it jumps one step when the deck settles (#587). Fixed sizes, never scaled with
/// Dynamic Type. Never tappable, in any pose (the cards swipe; in Tabletop `DeckStepRow` changes the stage card); one VoiceOver
/// element, "Updates 2 and 3 of 5", whose swipe up or down moves the deck one card.
struct PageEdge: View {
    var cards: [DeckCard]
    /// The leading card on screen (the scroll position).
    var current: String?
    /// Cards fully on screen at once: 2 in Open (two across), else 1.
    var visible: Int = 1
    var select: (String) -> Void
    @Environment(\.colorScheme) private var scheme

    static let dot: CGFloat = 6
    static let gap: CGFloat = 10
    /// The row's height, so the deck's layout around it is unchanged.
    static let rowHeight: CGFloat = 44
    /// Unlit dots in light: #A39B97 on cream (2.5:1), the weight the dark dots carry (Iris on #616). Dark keeps textSecondary at 35%.
    static let unlitLight = UIColor(hex: 0xA39B97)

    /// One page only: every card is on screen at once, so there is nothing to page and no indicator (HIG page controls;
    /// Iris on #616, Open landscape with 2 updates showed a lone pill).
    static func hidden(count: Int, visible: Int) -> Bool { count <= max(1, visible) }

    /// The pill over the lit dots, in the dots row's own space (x from the first dot's leading edge). Nil when nothing is lit.
    static func pill(lit: Set<Int>, window: [Int]) -> CGRect? {
        let slots = window.enumerated().filter { lit.contains($0.element) }.map(\.offset)
        guard let a = slots.min(), let b = slots.max() else { return nil }
        return CGRect(x: CGFloat(a) * (dot + gap), y: 0, width: CGFloat(b - a) * (dot + gap) + dot, height: dot)
    }

    /// "Update 2 of 5", "Updates 2 and 3 of 5".
    static func spoken(lit: Set<Int>, count: Int) -> String {
        let n = lit.sorted().map { $0 + 1 }
        guard let last = n.last else { return "Updates" }
        if n.count == 1 { return "Update \(last) of \(count)" }
        return "Updates \(n.dropLast().map(String.init).joined(separator: ", ")) and \(last) of \(count)"
    }

    /// The leaves lit: the leading card and the others fully on screen beside it. At the deck's end the pager cannot lead
    /// with the last card when two show, so lighting only the leading one left the last leaf dark for good (Iris on #512).
    static func lit(cards: [DeckCard], current: String?, visible: Int) -> Set<Int> {
        guard !cards.isEmpty else { return [] }
        let lead = cards.firstIndex { $0.id == current } ?? 0
        let first = min(lead, max(0, cards.count - max(1, visible)))
        return Set(first..<min(cards.count, first + max(1, visible)))
    }

    /// The card that leads after one step (VoiceOver increment or decrement, or Tabletop's Previous and Next): exactly one card, clamped so
    /// the last lead still shows the last card. Nil when already at that end.
    static func step(cards: [DeckCard], current: String?, visible: Int, by delta: Int) -> String? {
        guard !cards.isEmpty else { return nil }
        let lastLead = max(0, cards.count - max(1, visible))
        let lead = min(cards.firstIndex { $0.id == current } ?? 0, lastLead)
        let next = min(max(0, lead + (delta > 0 ? 1 : -1)), lastLead)
        return next == lead ? nil : cards[next].id
    }

    /// At most 5 dots, in a window that follows the current card (Iris, 6589abf).
    private var window: [(index: Int, card: DeckCard)] {
        let all = Array(cards.enumerated())
        guard all.count > 5 else { return all.map { ($0.offset, $0.element) } }
        let cur = Self.lit(cards: cards, current: current, visible: visible).max() ?? 0
        let start = min(max(0, cur - 2), all.count - 5)
        return all[start..<(start + 5)].map { ($0.offset, $0.element) }
    }

    var body: some View {
        if Self.hidden(count: cards.count, visible: visible) {
            // The row keeps its height, so the deck's layout does not move between two cards and three.
            Color.clear.frame(height: Self.rowHeight).accessibilityHidden(true)
        } else {
            dots
        }
    }

    @ViewBuilder private var dots: some View {
        let lit = Self.lit(cards: cards, current: current, visible: visible)
        let win = window
        let pill = Self.pill(lit: lit, window: win.map(\.index))
        ZStack(alignment: .leading) {
            HStack(spacing: Self.gap) {
                ForEach(win, id: \.card.id) { item in
                    Circle()
                        .fill(lit.contains(item.index) ? Color.clear : scheme == .light ? Color(Self.unlitLight) : PlayscribeRole.textSecondary.opacity(0.35))
                        .frame(width: Self.dot, height: Self.dot)
                }
            }
            if let pill {
                Capsule().fill(PlayscribeRole.action)
                    .frame(width: pill.width, height: Self.dot)
                    .offset(x: pill.minX)
            }
        }
        .frame(height: Self.rowHeight)
        .frame(maxWidth: .infinity, alignment: .center)
        // The VoiceOver element is the whole 44 pt row, not the dots' 22 x 6 bounds: the system audit read the adjustable
        // element as a hit area too small (#588, Mac 75e96041 Closed).
        .contentShape(.accessibility, Rectangle())
        .allowsHitTesting(false)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Self.spoken(lit: lit, count: cards.count))
        .accessibilityIdentifier("deckIndicator")
        // VoiceOver swipe up or down moves the deck one card (Quinn and Iris on #512).
        .accessibilityAdjustableAction { direction in
            let delta = direction == .increment ? 1 : direction == .decrement ? -1 : 0
            if delta != 0, let id = Self.step(cards: cards, current: current, visible: visible, by: delta) { select(id) }
        }
        // One step when the deck settles, never a slide (Terry, build 18; #587).
        .transaction { $0.animation = nil }
    }
}

/// Tabletop only: the stage is view only and the page indicator is never tappable, so Previous and Next change the stage card,
/// at the top of the lower half, in the update page's Previous / Next style (Iris on #616). Disabled at the ends.
struct DeckStepRow: View {
    var cards: [DeckCard]
    var current: String?
    var select: (String) -> Void

    var body: some View {
        let back = PageEdge.step(cards: cards, current: current, visible: 1, by: -1)
        let forward = PageEdge.step(cards: cards, current: current, visible: 1, by: 1)
        HStack(spacing: 12) {
            button("Previous", "chevron.backward", target: back)
            button("Next", "chevron.forward", target: forward)
        }
    }

    private func button(_ title: String, _ symbol: String, target: String?) -> some View {
        Button { if let target { select(target) } } label: {
            Label(title, systemImage: symbol)
                .font(PlayscribeFont.headline)
                .frame(maxWidth: .infinity, minHeight: 52)
                .background(PlayscribeRole.chipFill, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(title + " update")
        .accessibilityIdentifier("deckStep" + title)
        .disabled(target == nil)
        .opacity(target == nil ? 0.4 : 1)
        .tappableFrame()
    }
}

/// Tabletop's standing half: the selected card as content only (G-4); the page edge below drives it.
struct DeckStage: View {
    var card: DeckCard
    /// Upcoming tab: the stage fronts the soonest unreleased game, so it carries an eyebrow and the date line, not an update.
    var upcomingLine: String? = nil
    @Environment(AppModel.self) private var model
    @Environment(\.duo) private var duo
    @Environment(\.dynamicTypeSize) private var typeSize
    @State private var stageBottom: CGFloat = 0

    var body: some View {
        let headline = card.release.map { $0.ps5Headline ?? $0.displayName } ?? card.game.name
        let dateText = card.date.map { AppModel.tileDay($0) }
        // The stage's own size comes only from its parent: art and scrim are a background and the caption an overlay,
        // so neither the caption's height nor the clearance can change what the split layout measures. (A caption
        // that set the stage's ideal size let ArrangementView re-pick its arrangement every pass at AX5: a hang.)
        Color.clear
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background {
                ZStack {
                    ArtView(asset: card.game.keyArtAsset, game: card.game, drift: true)
                    // A fixed scrim, independent of the art and of the caption's height: clear at the top of the stage, ink 950 at
                    // 0.8 from the caption block down (Iris, Quinn: stage legibility).
                    // At accessibility sizes the caption is tall and sits higher in the stage, so the scrim reaches full strength sooner
                    // and a little darker (Quinn: cream on beige at AX5).
                    LinearGradient(stops: typeSize.isAccessibilitySize
                                       ? [.init(color: .clear, location: 0.1),
                                          .init(color: PlayscribeColor.ink950.opacity(0.9), location: 0.4)]
                                       : [.init(color: .clear, location: 0.3),
                                          .init(color: PlayscribeColor.ink950.opacity(0.8), location: 0.75)],
                                   startPoint: .top, endPoint: .bottom)
                }
            }
            .overlay(alignment: .bottomLeading) {
            VStack(alignment: .leading, spacing: 6) {
                // Wraps instead of squeezing "New update" away at accessibility sizes (28c6063 Tabletop AX3).
                FlowLayout(spacing: 8) {
                    if upcomingLine != nil { Text("Coming soon").foregroundStyle(PlayscribeColor.accent) }
                    if card.unread { Text(card.chipText).foregroundStyle(PlayscribeColor.accent) }
                    if let v = card.release?.deckVersionChip { Text(v.keepingVersionsTogether).monospacedDigit().foregroundStyle(PlayscribeColor.textPrimary.opacity(0.9)) }
                }
                .font(PlayscribeFont.caption)
                .shadow(color: .black.opacity(0.6), radius: 3)
                Text(headline)
                    .font(PlayscribeFont.title3).foregroundStyle(PlayscribeColor.textPrimary).lineLimit(4)
                    .fixedSize(horizontal: false, vertical: true)
                // One wrapping text (name, then date), so a long name wraps on whole words instead of cutting.
                // The date is vellum 100, not grey, so it reads over bright art (Iris, Quinn: stage legibility).
                Group {
                    if let line = upcomingLine {
                        Text(line).foregroundStyle(PlayscribeColor.vellum100)
                    } else if card.release == nil {
                        // The stage headline is the game name already: the line says why there is no update (the date stays).
                        let line = DeckCard.noReleaseLine(tracked: model.feedTracksGame(card.game.id))
                        if let dateText {
                            // "Released 14 Apr" matches the Closed chip (same UTC day), after the line and a thin separator.
                            // Standard size: one line. Accessibility sizes: the date wraps to its own line and is never dropped.
                            if typeSize.isAccessibilitySize {
                                VStack(alignment: .leading, spacing: 2) {
                                    WholeWordText(text: line, font: PlayscribeFont.subheadline, lines: 3, color: PlayscribeColor.textPrimary)
                                    Text("Released " + dateText).foregroundStyle(PlayscribeColor.vellum100)
                                }
                            } else {
                                Text("\(Text(line).foregroundStyle(PlayscribeColor.textPrimary))  \(Text("Released " + dateText).foregroundStyle(PlayscribeColor.vellum100))")
                                    .lineLimit(1).minimumScaleFactor(0.85)
                            }
                        } else {
                            Text(line).foregroundStyle(PlayscribeColor.textPrimary)
                        }
                    } else if let dateText {
                        Text("\(Text(card.game.name.gluingTrailingNumeral).foregroundStyle(PlayscribeColor.textPrimary))  \(Text(dateText).foregroundStyle(PlayscribeColor.vellum100))")
                    } else {
                        Text(card.game.name.gluingTrailingNumeral).foregroundStyle(PlayscribeColor.textPrimary)
                    }
                }
                .font(PlayscribeFont.subheadline).fixedSize(horizontal: false, vertical: true)
            }
            // The caption block itself (no padding), so a test can measure that it ends 24 pt above the division (gate #592,
            // as the legacy stage's caption did). Its texts stay separate elements.
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("stageCaption")
            .padding(20)
            .dynamicTypeSize(...DynamicTypeSize.accessibility3)
            // The caption ends 24 pt above the division, measured in screen space (as in 0.2.0 #174/#176).
            .padding(.bottom, duo.clearance(forBottom: stageBottom))
            // bug-text-on-bright-art: 75% black behind the block, since the ember eyebrow needs more than white lines (Iris 2b).
            // Full bleed: the whole stage width, held to the stage's bottom edge, so it has no side, top or bottom edge on the art
            // (Iris on #514: the boxed scrim showed its right and top edges in Tabletop).
            .brightArtScrim(0.75, fullBleed: true)
            }
            .background(Color.clear.onGeometryChange(for: CGFloat.self) { $0.frame(in: .global).maxY.rounded() } action: { new in
                if abs(new - stageBottom) > 0.5 { stageBottom = new }
            })
        .allowsHitTesting(false)
        .accessibilityElement(children: .contain)
    }
}


/// bug-text-on-bright-art (Iris spec 2b): a fixed black scrim behind a text block over key art, so small text keeps 4.5:1 on
/// the brightest art. 0% a line and a half above the block, eased, full `strength` from the block's top to 8 pt under its last line, soft
/// side edges, no box. It belongs to the text, not the art, so it does not move under key-art motion. `strength` is at least
/// 0.6 behind white lines and 0.75 behind the ember eyebrow ("New update", "Coming soon").
struct BrightArtScrim: ViewModifier {
    var strength: Double
    /// One text line and a half above the block, well under the Tabletop cap of 15% of the stage (about 56 pt).
    var ramp: CGFloat = 40
    /// Full strength holds this far under the last line, then eases out over `fade` more, so the bottom is no hard edge either.
    var tail: CGFloat = 8
    var fade: CGFloat = 28
    var feather: CGFloat = 40
    /// Tabletop stage: the scrim spans the block's full width (the block fills the stage) and holds full strength to its bottom
    /// edge, with no side feather and no bottom fade; only the top eases in, over `stageRamp`. A box with feathered sides showed
    /// its right and top edges on bright art (Iris on #514).
    var fullBleed = false
    /// Under the Tabletop cap of 15% of the stage (about 56 pt).
    static let stageRamp: CGFloat = 56

    /// An eased (smoothstep) ramp so there is no visible edge where the scrim starts. More stops for the long stage ramp, so its
    /// straight segments leave no bands.
    private func eased(_ top: Double, steps: Int = 5) -> [Gradient.Stop] {
        (0...steps).map { i in
            let t = Double(i) / Double(steps)
            let k = t * t * (3 - 2 * t)
            return Gradient.Stop(color: .black.opacity(top * k), location: t)
        }
    }

    func body(content: Content) -> some View {
        if fullBleed {
            content.frame(maxWidth: .infinity, alignment: .leading).background(alignment: .bottom) {
                VStack(spacing: 0) {
                    LinearGradient(stops: eased(strength, steps: 16), startPoint: .top, endPoint: .bottom).frame(height: Self.stageRamp)
                    Color.black.opacity(strength)
                }
                .padding(.top, -Self.stageRamp)
                .allowsHitTesting(false)
                .accessibilityHidden(true)
            }
        } else {
            boxed(content)
        }
    }

    private func boxed(_ content: Content) -> some View {
        content.background(alignment: .bottom) {
            VStack(spacing: 0) {
                LinearGradient(stops: eased(strength), startPoint: .top, endPoint: .bottom).frame(height: ramp)
                Color.black.opacity(strength)
                LinearGradient(stops: eased(strength), startPoint: .bottom, endPoint: .top).frame(height: fade)
            }
            .mask {
                HStack(spacing: 0) {
                    LinearGradient(stops: eased(1), startPoint: .leading, endPoint: .trailing).frame(width: feather)
                    Color.black
                    LinearGradient(stops: eased(1), startPoint: .trailing, endPoint: .leading).frame(width: feather)
                }
            }
            .padding(.top, -ramp).padding(.bottom, -(tail + fade)).padding(.horizontal, -feather)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
        }
    }
}

extension View {
    func brightArtScrim(_ strength: Double, fullBleed: Bool = false) -> some View {
        modifier(BrightArtScrim(strength: strength, fullBleed: fullBleed))
    }
}

/// A hero chip's ground: "New update" is the one filled (ember) label, every other chip is the ink label on art (Iris,
/// over-art-materials).
struct DeckChipGround: ViewModifier {
    var filled: Bool
    func body(content: Content) -> some View {
        if filled { content.background(Capsule().fill(PlayscribeColor.accent)) } else { content.artLabel(in: Capsule()) }
    }
}
