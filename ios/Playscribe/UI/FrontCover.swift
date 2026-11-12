import SwiftUI

// The Closed-pose front cover (docs/cover-motion.md, board card duo-closed-cover, 0.7.0).
// This file is the cover itself and its Settings row, Still mode only. Iris (12 Nov) chose layout A: the cover is the
// Closed Library's first page, full bleed under the status bar, controls on a floating rail, the Library peeking 40 pt
// below. LibraryView wraps it after #424 and #455 merge, so until then it shows only in the internal preview
// (Settings > Front cover, or `-qaRoute cover` / `cover/one`). Nothing here is reachable in a TestFlight or App Store build.

/// The three motion modes (Settings > "Cover motion"). Only Still is built; the others land in their own PRs.
enum CoverMotion: String, CaseIterable, Identifiable {
    case trailer, keyArt, still
    var id: String { rawValue }

    static let key = "coverMotion"
    /// Nadia, 12 Nov: the default is Key-art motion.
    static let defaultMode: CoverMotion = .keyArt

    var label: String {
        switch self {
        case .trailer: "Trailer loop"
        case .keyArt: "Key-art motion"
        case .still: "Still"
        }
    }

    /// Built so far. The Settings row lists only these, and a stored mode that is not built yet shows Still.
    var isBuilt: Bool { self == .still }

    /// The next mode down: a Trailer loop that cannot play shows Key-art motion, and Key-art motion falls back to Still.
    var fallback: CoverMotion {
        switch self {
        case .trailer: .keyArt
        case .keyArt, .still: .still
        }
    }

    /// What the cover actually does. CM-1 (Terry via Sam, 12 Nov): only Reduce Motion forces Still. Autoplay videos off
    /// stops the Trailer loop alone, which falls back to Key-art motion (that motion is not video). A mode not built yet
    /// falls back the same way.
    func resolved(reduceMotion: Bool, autoplay: Bool) -> CoverMotion {
        if reduceMotion { return .still }
        var mode = self
        if mode == .trailer && !autoplay { mode = .keyArt }
        while !mode.isBuilt { mode = mode.fallback }
        return mode
    }
}

/// The internal preview gate. Off by default everywhere, and never on in a distribution build, so the 0.5.x
/// Library and its QA stills are unchanged until 0.7 wires the cover in.
enum FrontCoverPreview {
    static var available: Bool { BuildChannel.showsInternalTools }
    /// Set by `-qaRoute cover`; the Settings section opens the preview once and clears it. Never persisted, so a
    /// killed run cannot leave the preview popping up over a later QA shot of Settings.
    static var requestOpen = false
}

/// One page of the cover: the card's key art full bleed, the shade, the plate (eyebrow, game name, chips) and the
/// Playscribe lockup bottom-left. The whole page is the Continue target; nothing else on the art is tappable.
struct FrontCoverPage: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dynamicTypeSize) private var typeSize
    @Environment(\.colorSchemeContrast) private var contrast
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.qaSolid) private var qaSolid
    var card: DeckCard
    /// Leading room kept clear for the leaves, and trailing room for the rail at accessibility sizes (the plate never
    /// sits under the rail, Iris condition 5).
    var leadingInset: CGFloat = 0
    var railInset: CGFloat = 0

    var body: some View {
        Button {
            if let r = card.release { model.openGame(card.game.id, chapter: .updates, releaseID: r.id) }
            else { model.openGame(card.game.id, chapter: .updates) }
        } label: {
            ZStack(alignment: .bottomLeading) {
                ArtView(asset: card.game.keyArtAsset, game: card.game, focusX: card.game.coverFocusX)
                if !solid { fade }
                VStack(alignment: .leading, spacing: 18) {
                    FrontCoverPlate(card: card)
                    Wordmark().foregroundStyle(PlayscribeColor.textPrimary)
                }
                .padding(.leading, 20 + leadingInset)
                .padding(.trailing, typeSize.isAccessibilitySize ? 20 + railInset : 20)
                .padding(.top, solid ? 20 : 0)
                .padding(.bottom, 28)
                .frame(maxWidth: .infinity, alignment: .leading)
                // Increase Contrast / Reduce Transparency: a solid scrim behind the plate, not a fade (as the deck cards).
                .background { if solid { PlayscribeColor.ink950.opacity(0.92) } }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .tappableFrame()
        // CM-7: one element; the motion mode is never announced.
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(FrontCoverPage.label(card))
        .accessibilityValue(card.unread ? "New update" : "")
        .accessibilityAddTraits(.isButton)
        .accessibilityIdentifier("frontCover")
    }

    private var solid: Bool { contrast == .increased || reduceTransparency || qaSolid }

    /// CM-5: the shade is part of the cover, not the art, so the caption meets AA over any art (and, later, any loop
    /// frame). The top darkens a little for the status bar and the rail.
    private var fade: some View {
        LinearGradient(stops: [
            .init(color: PlayscribeColor.ink950.opacity(0.55), location: 0),
            .init(color: .clear, location: 0.18),
            .init(color: .clear, location: typeSize.isAccessibilitySize ? 0.25 : 0.45),
            .init(color: PlayscribeColor.ink950.opacity(0.92), location: typeSize.isAccessibilitySize ? 0.7 : 0.85),
            .init(color: PlayscribeColor.ink950, location: 1),
        ], startPoint: .top, endPoint: .bottom)
    }

    /// CM-7: "<Game> cover, update 1.1 on PS5, 22 Oct". A card with no release says when the game came out.
    static func label(_ card: DeckCard) -> String {
        let day = card.date.map(AppModel.tileDay) ?? ""
        guard let r = card.release else {
            return day.isEmpty ? "\(card.game.name) cover" : "\(card.game.name) cover, released \(day)"
        }
        let update = r.displayName.prefix(1).lowercased() + r.displayName.dropFirst()
        return "\(card.game.name) cover, \(update) on PS5" + (day.isEmpty ? "" : ", \(day)")
    }
}

/// The cover's caption: eyebrow, game name (at most 4 lines, cut only at a word), and the chips, which wrap before any
/// is dropped. Capped at AX3 like the other hero captions.
struct FrontCoverPlate: View {
    var card: DeckCard
    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(card.unread ? "NEW UPDATE" : "CONTINUE")
                .font(PlayscribeFont.caption.weight(.semibold))
                .tracking(12 * 0.12)
                .foregroundStyle(PlayscribeColor.accent)
            WholeWordText(text: card.game.name, font: PlayscribeFont.title, lines: 4, color: PlayscribeColor.textPrimary)
            FlowLayout(spacing: 6) {
                ForEach(Self.chips(card), id: \.text) { chip($0.text, live: $0.live) }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .dynamicTypeSize(...DynamicTypeSize.accessibility3)
    }

    /// "v1.1 · On PS5" (accent), the UTC day, and the change count. The version is always the PS5 one: the deck holds
    /// only releases live on PS5, and `versionChip` comes from the PS5 release's own name.
    static func chips(_ card: DeckCard) -> [(text: String, live: Bool)] {
        var list: [(text: String, live: Bool)] = []
        if let r = card.release {
            list.append(((r.versionChip.map { $0 + " · " } ?? "") + "On PS5", true))
            if let d = card.date { list.append((AppModel.tileDay(d), false)) }
            let n = r.noteCount
            if n > 0 { list.append((n == 1 ? "1 change" : "\(n) changes", false)) }
        } else if let d = card.date {
            list.append(("Released " + AppModel.tileDay(d), false))
        }
        return list
    }

    private func chip(_ text: String, live: Bool) -> some View {
        Text(text).font(PlayscribeFont.caption.weight(.semibold)).monospacedDigit()
            .foregroundStyle(live ? PlayscribeColor.onAccent : PlayscribeColor.textPrimary)
            .padding(.horizontal, 8).padding(.vertical, 3).frame(minHeight: 24)
            .background(RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(live ? PlayscribeColor.accent : PlayscribeColor.ink950.opacity(0.6)))
            .overlay(RoundedRectangle(cornerRadius: 6, style: .continuous)
                .strokeBorder(live ? .clear : PlayscribeColor.vellum100.opacity(0.25), lineWidth: 1))
    }
}

/// The cover's pages (every deck card, newest first, at most 5) with the leaves on the leading edge. The leaves ARE
/// the deck's dots: they drive the same selection, so there is no second pager (Iris condition 4). The rail is the
/// caller's overlay (Iris condition 2: every Library control, 44 pt, on a scrim); `railWidth` keeps the plate clear of it.
struct FrontCover: View {
    @Environment(AppModel.self) private var model
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var cards: [DeckCard]
    var railWidth: CGFloat = 0
    @State private var current: String?

    var body: some View {
        let shown = Array(cards.prefix(AppModel.deckLimit))
        ScrollView(.horizontal, showsIndicators: false) {
            LazyHStack(spacing: 0) {
                ForEach(shown) { card in
                    FrontCoverPage(card: card, leadingInset: shown.count > 1 ? 28 : 0, railInset: railWidth)
                        .containerRelativeFrame([.horizontal, .vertical])
                        .id(card.id)
                }
            }
            .scrollTargetLayout()
        }
        .scrollTargetBehavior(.paging)
        .scrollPosition(id: $current)
        .onAppear { if current == nil { current = model.deckSelection.flatMap { id in shown.first { $0.id == id }?.id } ?? shown.first?.id } }
        .onChange(of: current) { _, new in model.deckSelection = new }
        .overlay(alignment: .leading) {
            if shown.count > 1 {
                CoverLeaves(cards: shown, current: current ?? shown.first?.id) { id in
                    withAnimation(reduceMotion ? .easeInOut(duration: 0.2) : .snappy) { current = id }
                }
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(shown.count > 1
            ? "Cover, page \((shown.firstIndex { $0.id == (current ?? shown.first?.id) } ?? 0) + 1) of \(shown.count)" : "Cover")
    }
}

/// The page-edge leaves, stood on the cover's leading edge: one per update, the current one tall in ember, unread
/// ones in vellum. Each is a 44 pt target labelled "Update n of N".
struct CoverLeaves: View {
    var cards: [DeckCard]
    var current: String?
    var select: (String) -> Void

    var body: some View {
        VStack(spacing: 0) {
            ForEach(Array(cards.enumerated()), id: \.element.id) { index, card in
                let isCurrent = card.id == current
                Button { select(card.id) } label: {
                    RoundedRectangle(cornerRadius: 1.5)
                        .fill(isCurrent ? PlayscribeColor.accent : (card.unread ? PlayscribeColor.vellum100 : PlayscribeColor.textSecondary.opacity(0.6)))
                        .frame(width: 3, height: isCurrent ? 22 : 12)
                        .shadow(color: .black.opacity(0.6), radius: 2)
                        .frame(width: 44, height: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .tappableFrame()
                .accessibilityLabel("Update \(index + 1) of \(cards.count)")
                .accessibilityAddTraits(isCurrent ? [.isButton, .isSelected] : .isButton)
            }
        }
    }
}

/// A rail button for the cover: 44 pt, on a dark scrim so bright art never hides it (Iris condition 2).
struct CoverRailButton: View {
    var title: String
    var symbol: String
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(PlayscribeColor.textPrimary)
                .frame(width: 44, height: 44)
                .background(Circle().fill(PlayscribeColor.ink950.opacity(0.6)))
                .overlay(Circle().strokeBorder(PlayscribeColor.vellum100.opacity(0.18), lineWidth: 1))
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .tappableFrame()
        .accessibilityLabel(title)
    }
}

/// Internal preview of the cover in the Closed pose (until 0.7 wires it into the Library): full bleed, the Library's
/// rounded top edge peeking 40 pt at the bottom (Iris condition 1), a Close button on the rail.
struct FrontCoverPreviewScreen: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 0) {
            if model.latestDeck.isEmpty {
                Text("No updates in the deck. Try -qaRoute cover with a demo library.")
                    .font(PlayscribeFont.body).foregroundStyle(PlayscribeColor.textSecondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ZStack(alignment: .topTrailing) {
                    FrontCover(cards: model.latestDeck, railWidth: 44 + 12)
                        .ignoresSafeArea(edges: .top)
                    // A sibling inside the safe area, so the rail clears the status bar and the outer camera (G-6).
                    CoverRailButton(title: "Close preview", symbol: "xmark") { dismiss() }
                        .padding(.trailing, 12).padding(.top, 8)
                }
            }
            Text("Library")
                .font(PlayscribeFont.headline).foregroundStyle(PlayscribeColor.textPrimary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 16)
                .frame(height: 40)
                .background(UnevenRoundedRectangle(topLeadingRadius: 16, topTrailingRadius: 16).fill(Color.ink0))
                .accessibilityHidden(true)
        }
        .background(Color.ink0)
        // Iris (#467): white text on the shade in both modes, so the status bar is light content over the cover whatever
        // the system appearance. The Library wrap does the same while the cover is on screen.
        .preferredColorScheme(.dark)
    }
}

/// Settings: the cover's motion mode with the CM-1 footnote. Internal builds only until 0.7 (see the top of this file).
struct CoverMotionSection: View {
    @AppStorage(CoverMotion.key) private var stored: CoverMotion = CoverMotion.defaultMode
    @State private var previewOpen = false

    var body: some View {
        if FrontCoverPreview.available {
            Section {
                Picker("Cover motion", selection: Binding(get: { stored.isBuilt ? stored : .still }, set: { stored = $0 })) {
                    ForEach(CoverMotion.allCases.filter(\.isBuilt)) { Text($0.label).tag($0) }
                }
                .frame(minHeight: 52)
                .accessibilityIdentifier("coverMotion")
                Button("Show the front cover") { previewOpen = true }
                    .frame(minHeight: 44)
                    .accessibilityIdentifier("showFrontCover")
            } header: {
                Text("Front cover (internal preview)")
            } footer: {
                // Placeholder wording; Ezra writes the shipping line.
                Text("When the Duo is closed, the Library opens on a cover of your latest updates. Reduce Motion keeps the cover still. With Autoplay videos off, a trailer loop shows key-art motion instead.")
            }
            .fullScreenCover(isPresented: $previewOpen) { FrontCoverPreviewScreen() }
            .onAppear {
                guard FrontCoverPreview.requestOpen else { return }
                FrontCoverPreview.requestOpen = false
                previewOpen = true
            }
        }
    }
}
