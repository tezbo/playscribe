import SwiftUI

/// Tabletop reading (TT-2): the standing half shows one section of the release at a time in
/// large type over the game's art; the flat half holds the chapter switcher, the outline,
/// Previous and Next, and the rail. Nothing scrolls on the standing half.
struct ReaderSection: Identifiable, Hashable {
    var id: String
    var title: String
    var body: String
}

/// A key change without a "Heading: text" split, cleaned for the reader (Iris, 0.2.0 spec): leading
/// bullets and numbers are stripped; a "Fixed:" or "Added:" style prefix becomes the group (it feeds
/// the New / Fixed / Balance grouping in 0.5.0); the title is the first sentence, at most seven
/// words, cut at a word boundary with an ellipsis only when something was cut. Never "Change N".
enum ReaderTitle {
    struct Parsed: Equatable { var group: String?; var title: String; var body: String }

    static let groups = ["new", "added", "add", "fixed", "fix", "balance", "balanced", "changed", "improved", "updated", "other"]

    static func parse(_ text: String, maxWords: Int = 7) -> Parsed {
        var t = text.trimmingCharacters(in: .whitespacesAndNewlines)
        // Leading bullets, then a list number such as "3." or "3)".
        t = String(t.drop { "•-–—*· \t".contains($0) })
        if let r = t.range(of: #"^\d+[.)]\s+"#, options: .regularExpression) { t.removeSubrange(r) }
        // A group prefix such as "Fixed:".
        var group: String?
        if let colon = t.firstIndex(of: ":") {
            let head = t[..<colon].trimmingCharacters(in: .whitespaces)
            if groups.contains(head.lowercased()) {
                group = head.prefix(1).uppercased() + head.dropFirst().lowercased()
                t = String(t[t.index(after: colon)...]).trimmingCharacters(in: .whitespaces)
            }
        }
        guard !t.isEmpty else { return Parsed(group: group, title: "What changed", body: "") }
        let body = t.prefix(1).uppercased() + t.dropFirst()
        // First sentence: a full stop, "!" or "?" followed by a space or the end ("1.1" is not one).
        var sentence = Substring(t)
        var i = t.startIndex
        while i < t.endIndex {
            if ".!?".contains(t[i]) {
                let next = t.index(after: i)
                if next == t.endIndex || t[next] == " " { sentence = t[..<i]; break }
            }
            i = t.index(after: i)
        }
        let words = sentence.split(separator: " ")
        let cut = words.count > maxWords
        let head = words.prefix(maxWords).joined(separator: " ")
            .trimmingCharacters(in: CharacterSet(charactersIn: " ,;:-–—"))
        let title = head.prefix(1).uppercased() + head.dropFirst()
        return Parsed(group: group, title: cut ? title + "…" : title, body: body)
    }
}

extension AppModel {
    /// The release the Reader shows: the focused one, else the newest On PS5 release.
    func readerRelease(_ gameID: String) -> Release? {
        if let id = focusReleaseID, let r = release(gameID, id) { return r }
        // J-1: the release picked in the list, as on every other Page.
        return selectedRelease(gameID) ?? releases(gameID).first
    }

    private static let qaLongBody = "A long overview for checking the Tabletop stage. The first sentence is short. The second sentence runs on a little further so the cap has something to cut. The third sentence adds a good deal more detail about balance changes, performance work, new options and fixes across every mode. The fourth sentence keeps going to be sure the whole text is far longer than four lines on the stage, so that the Full text row appears in the lower half."

    /// Overview, each key change, Fixes, then PS5 facts and video.
    func readerSections(_ r: Release) -> [ReaderSection] {
        var out = [ReaderSection(id: "overview", title: r.headline ?? r.displayName, body: qaLongText ? Self.qaLongBody : (r.summary ?? ""))]
        for (i, k) in (r.keyChanges ?? []).enumerated() {
            let parts = k.split(separator: ":", maxSplits: 1).map { $0.trimmingCharacters(in: .whitespaces) }
            let parsed = ReaderTitle.parse(k)
            if parsed.group == nil, parts.count == 2 {
                // "Heading: text": the heading is the title.
                out.append(ReaderSection(id: "key-\(i)", title: parts[0], body: parts[1].prefix(1).uppercased() + parts[1].dropFirst()))
            } else {
                out.append(ReaderSection(id: "key-\(i)", title: parsed.title, body: parsed.body))
            }
        }
        // Greetings and the spoiler warning are not changes; spoiler lines stay out of the standing
        // half until the game's spoiler switch is on (R-5), which is the same switch as the Page's.
        let changes = r.notes.flatMap(\.items).filter { !ChangeKind.isPreamble($0.text) && !(r.isPS5Listed && $0.isPCOnly) }
        if !changes.isEmpty {
            let shown = spoilersShown(r.gameID)
            let first = changes.filter { shown || $0.spoiler != true }.prefix(3).map { LinkedText.clean($0.text) }
            let hidden = changes.filter { $0.spoiler == true }.count
            var body = "\(changes.count) listed changes"
            if !first.isEmpty { body += ", including: " + first.joined(separator: " ") }
            if hidden > 0 && !shown { body += ". \(hidden) hidden for spoilers." }
            out.append(ReaderSection(id: "fixes", title: "Fixes", body: body))
        }
        var facts = ["Status: Released",
                     "PS5 version: " + (r.ps5Version ?? "not published yet")]
        if let size = r.ps5?.sizeBytes {
            facts.append("Download: " + ByteCountFormatter.string(fromByteCount: size.value, countStyle: .decimal) + (size.verification == .reported ? " (reported)" : ""))
        }
        if let v = r.video { facts.append("Video: \(v.label)" + (v.duration.map { ", \($0)" } ?? "")) }
        out.append(ReaderSection(id: "facts", title: "On your PS5", body: facts.joined(separator: "\n")))
        return out
    }
}

/// The stage's body is capped (Iris): at most `limit` characters, cut at the end of a sentence, else at a word
/// boundary with an ellipsis; the full text is one tap away in the lower half (TabletopReaderControls).
enum ReaderBody {
    static let limit = 170
    static func stage(_ body: String) -> String {
        guard body.count > limit else { return body }
        let head = String(body.prefix(limit))
        if let end = head.lastIndex(where: { ".!?".contains($0) }), head.distance(from: head.startIndex, to: end) > limit / 3 {
            return String(head[...end])
        }
        let cut = head.lastIndex(of: " ").map { String(head[..<$0]) } ?? head
        return cut + "…"
    }
    /// The headline: at most `titleLimit` characters, cut at a word boundary with an ellipsis, so it never ends mid-word.
    static let titleLimit = 56
    static func title(_ t: String) -> String {
        guard t.count > titleLimit else { return t }
        let head = String(t.prefix(titleLimit))
        let cut = head.lastIndex(of: " ").map { String(head[..<$0]) } ?? head
        return cut.trimmingCharacters(in: .punctuationCharacters.union(.whitespaces)) + "…"
    }
    /// VoiceOver: "2 of 5", for a section's place in the update.
    static func position(_ index: Int, of count: Int) -> String { "\(index + 1) of \(count)" }
    static func isCapped(_ body: String) -> Bool { stage(body) != body }
    static func isCapped(title t: String, body: String) -> Bool { title(t) != t || isCapped(body) }
}

struct TabletopReaderStage: View {
    @Environment(AppModel.self) private var model
    @Environment(\.duo) private var duo
    @Environment(\.dynamicTypeSize) private var typeSize
    /// The stage's bottom edge in screen space; the text ends 24 pt above the division.
    @State private var stageBottom: CGFloat = 0
    @State private var stageWidth: CGFloat = 0
    @State private var stageHeight: CGFloat = 0
    @State private var panelHeight: CGFloat = 0

    /// The room right of the text panel (16 pt margin, up to 560 pt, 24 pt gap, 16 pt margin): the tile is 240 pt at most and
    /// is left out below 140 pt, so it never sits under the text.
    private var trailerTileWidth: CGFloat {
        let room = stageWidth - 16 - 560 - 24 - 16
        // Accessibility sizes: the label is larger, so the poster gets smaller rather than the tile being cut by the stage.
        return room >= 140 ? min(typeSize.isAccessibilitySize ? 160 : 240, room) : 0
    }
    /// No side room (the Duo stage is about 670 pt wide): Iris's stacked poster, 120 x 84 pt on the leading edge, the same in every
    /// game, no label. It sits at least 8 pt under the status band and 12 pt above the stage text, and is left out when the room
    /// above the text is shorter than that, and at every accessibility size. "Play trailer" in the lower half is always there.
    private let stackedPosterSize = CGSize(width: 120, height: 84)
    private func stackedPosterFits(clearance: CGFloat) -> Bool {
        guard !typeSize.isAccessibilitySize, trailerTileWidth == 0, panelHeight > 0 else { return false }
        return stageHeight - 56 - (clearance + panelHeight + 12) >= stackedPosterSize.height + 8
    }
    var gameID: String

    var body: some View {
        let release = model.readerRelease(gameID)
        let sections = release.map(model.readerSections) ?? []
        let index = min(model.readerIndex[gameID] ?? 0, max(0, sections.count - 1))
        ZStack {
            // The same art as the Page in every other pose (default header when none loads),
            // shaded towards the text side for legibility.
            ArtView(asset: model.backdrop(gameID, chapter: .updates, tall: false), game: model.game(gameID))
                .overlay(LinearGradient(colors: [.black.opacity(0.85), .black.opacity(0.35)], startPoint: .leading, endPoint: .trailing))
                .ignoresSafeArea()
                // Measure the art layer: its size never depends on the text, so the clearance cannot feed back into
                // layout (the update loop in e6d8ab5). Ignore sub-half-point changes.
                .onGeometryChange(for: CGFloat.self) { $0.frame(in: .global).maxY } action: { new in
                    if abs(new - stageBottom) > 0.5 { stageBottom = new }
                }
            // The text block sits in an overlay on a view that takes exactly the stage's proposed size, so however tall the block is
            // it cannot grow the stage, and the art layer measured above cannot move with it. A sibling in the ZStack could: a block
            // taller than the upper half (AX5, whole-word text that ignores the proposed height) grew the ZStack, which moved the
            // art's bottom edge, which changed the clearance padding, which grew the block again, with the stage body (and its
            // note parsing) re-run each time (hang at 2dbcd13, Mac sample). The block grows upward and is clipped by the stage.
            Color.clear.overlay(alignment: .bottomLeading) { if let section = sections[safe: index] {
                VStack(alignment: .leading, spacing: 14) {
                    // Eyebrow: the game and the date; the release itself is the title below.
                    // At accessibility sizes the name is one line cut on a whole word ("The Blood of…"), never "The Blood of Daw…", and the date keeps its place.
                    HStack(spacing: 8) {
                        if typeSize.isAccessibilitySize {
                            WholeWordText(text: model.gameDisplayName(gameID), font: PlayscribeFont.subheadline.weight(.semibold), lines: 1, color: PlayscribeColor.accent)
                        } else {
                            Text(model.gameDisplayName(gameID))
                        }
                        if let r = release { Text((r.isPS5Listed ? r.ps5Date : r.latestDate).dayMonthOrYear).foregroundStyle(.secondary).fixedSize() }
                    }
                    .font(PlayscribeFont.subheadline.weight(.semibold))
                    .foregroundStyle(PlayscribeColor.accent)
                    // One phrase ("Enshrouded, 5 November") instead of two stops.
                    .accessibilityElement(children: .combine)
                    // The release name for VoiceOver (and J-4), when the title is a headline.
                    Color.clear.frame(width: 1, height: 1)
                        .accessibilityElement()
                        .accessibilityLabel(release?.displayName ?? "")
                        .accessibilityAddTraits(.isStaticText)
                        .accessibilityIdentifier("releaseTitle")
                    // Whole words only (G-8): the stage plate ends on a word and "…", never a cut word.
                    WholeWordText(text: ReaderBody.title(section.title), font: PlayscribeFont.title, lines: typeSize.isAccessibilitySize ? 2 : 4, color: nil)
                        // The stage caps the title; VoiceOver reads all of it, as a heading.
                        .accessibilityLabel(section.title)
                        .accessibilityAddTraits(.isHeader)
                    WholeWordText(text: ReaderBody.stage(section.body), font: PlayscribeFont.body, lines: typeSize.isAccessibilitySize ? 1 : 4,
                                  color: PlayscribeColor.textPrimary.opacity(0.92))
                        // At accessibility sizes the half-height stage has no room for a body line under a two-line title
                        // and the eyebrow (the eyebrow was clipped at the top, fccccaa). The body is not drawn there; it stays
                        // in the accessibility tree and the full text is one tap away.
                        .frame(height: typeSize.isAccessibilitySize ? 0 : nil)
                        .clipped()
                        .accessibilityLabel(section.body)
                        .accessibilityIdentifier("readerBody")
                }
                // Iris (same rule as #232, every Tabletop stage): the whole block sits on one ink panel, 70%, 12 pt
                // radius and padding, so the text keeps 4.5:1 over any art, logo or banner. Left on the 16 pt margin,
                // up to 560 pt wide, its bottom edge 24 pt above the division; it grows upward only.
                .padding(12)
                .frame(maxWidth: 560, alignment: .leading)
                .background(PlayscribeColor.ink950.opacity(0.7), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                // The panel's own height (before the margin and the full-stage frame), for the stacked poster above it.
                .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { h in if abs(h - panelHeight) > 0.5 { panelHeight = h } }
                .padding(.horizontal, 16)
                .padding(.bottom, duo.clearance(forBottom: stageBottom))
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
                .id(section.id)
                .transition(.opacity)
            } }
            // Clip the block, not the ZStack: the art above draws under the status bar on purpose.
            .clipped()
            // R-11 (bug-tabletop-trailer-tile-missing, Iris): the game's trailer poster, whole and uncropped, with a play glyph for
            // orientation only. The stage takes no touches; "Play trailer" in the lower half is the control. Drawn only where it
            // fits beside the text panel, on the same bottom line, 24 pt or more above the fold; at large text it scales down.
            if let g = model.game(gameID), let v = GameBasicsView.trailers(g).first, trailerTileWidth > 0 {
                Color.clear.overlay(alignment: .bottomTrailing) {
                    StageTrailerTile(youtubeID: v.youtubeId, width: trailerTileWidth)
                        .padding(.trailing, 16)
                        .padding(.bottom, duo.clearance(forBottom: stageBottom))
                }
                .clipped()
            } else if let g = model.game(gameID), let v = GameBasicsView.trailers(g).first, stackedPosterFits(clearance: duo.clearance(forBottom: stageBottom)) {
                // R-11: no side room, so the poster sits on the panel's leading edge, 12 pt above it. View only.
                Color.clear.overlay(alignment: .bottomLeading) {
                    StageTrailerTile(youtubeID: v.youtubeId, width: stackedPosterSize.width, posterHeight: stackedPosterSize.height)
                        .padding(.leading, 16)
                        .padding(.bottom, duo.clearance(forBottom: stageBottom) + panelHeight + 12)
                }
                .clipped()
            }
        }
        .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { w in if abs(w - stageWidth) > 0.5 { stageWidth = w } }
        .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { h in if abs(h - stageHeight) > 0.5 { stageHeight = h } }
        .animation(.easeInOut(duration: 0.2), value: index)
        // Its parts stay separate elements, so the release title is findable (J-4).
        .accessibilityElement(children: .contain)
    }
}

struct TabletopReaderControls: View {
    @Environment(AppModel.self) private var model
    @Environment(\.railWidth) private var railWidth
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var gameID: String

    var body: some View {
        let sections = model.readerRelease(gameID).map(model.readerSections) ?? []
        let index = min(model.readerIndex[gameID] ?? 0, max(0, sections.count - 1))
        VStack(alignment: .leading, spacing: 10) {
            ChapterBar(gameID: gameID, selected: .updates)
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(spacing: 2) {
                        ForEach(Array(sections.enumerated()), id: \.element.id) { i, s in
                            Button { go(i) } label: {
                                HStack {
                                    Text(s.title).font(PlayscribeFont.subheadline.weight(i == index ? .semibold : .regular)).lineLimit(1)
                                    Spacer()
                                    Text("\(i + 1)").font(PlayscribeFont.caption).foregroundStyle(.secondary)
                                }
                                .padding(.horizontal, 12)
                                .frame(minHeight: 44)
                                .background(i == index ? PlayscribeColor.ink700 : .clear, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel(s.title)
                            .accessibilityValue(ReaderBody.position(i, of: sections.count))
                            .accessibilityAddTraits(i == index ? .isSelected : [])
                            .tappableFrame()
                            .id(i)
                        }
                    }
                }
                .onChange(of: index) { _, i in withAnimation(reduceMotion ? nil : .default) { proxy.scrollTo(i, anchor: .center) } }
            }
            HStack(spacing: 12) {
                pageButton("Previous", "chevron.backward", enabled: index > 0) { go(index - 1) }
                pageButton("Next", "chevron.forward", enabled: index < sections.count - 1) { go(index + 1) }
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 10)
        .padding(.bottom, 12)
        .padding(.trailing, railWidth)
        .background(Color.ink1)
    }

    private func go(_ i: Int) {
        model.readerIndex[gameID] = i
        if let r = model.readerRelease(gameID), i > 0, model.isUnread(r) { model.markRead(r.id) }
        // The page is on the stage, away from the button just pressed: say which section it is now.
        let sections = model.readerRelease(gameID).map(model.readerSections) ?? []
        if let s = sections[safe: i] {
            UIAccessibility.post(notification: .announcement, argument: "\(s.title), \(ReaderBody.position(i, of: sections.count))")
        }
    }

    private func pageButton(_ title: String, _ symbol: String, enabled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(title, systemImage: symbol)
                .font(PlayscribeFont.headline)
                .frame(maxWidth: .infinity, minHeight: 52)
                .background(PlayscribeColor.ink700, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(title + " section")
        .disabled(!enabled)
        .opacity(enabled ? 1 : 0.4)
        .tappableFrame()
    }
}

extension Array {
    subscript(safe i: Int) -> Element? { indices.contains(i) ? self[i] : nil }
}

/// The Tabletop stage's trailer tile: the poster at 16:9, uncropped, a play glyph for orientation, and "Trailer" under it on
/// the stage's ink panel. View only. VoiceOver reads one element, "Trailer"; the action is "Play trailer" in the lower half.
struct StageTrailerTile: View {
    var youtubeID: String
    var width: CGFloat
    /// Set for the stacked variant: the poster alone in a fixed box (width x posterHeight), no label, the whole 16:9 frame inside it.
    var posterHeight: CGFloat? = nil

    var body: some View {
        Group {
            if let posterHeight { stackedPoster(posterHeight) } else { sideTile }
        }
        .allowsHitTesting(false)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Trailer")
        .accessibilityAddTraits(.isStaticText)
        .accessibilityIdentifier("stageTrailerTile")
    }

    private func image() -> some View {
        AsyncImage(url: URL(string: "https://i.ytimg.com/vi/\(youtubeID)/mqdefault.jpg")) { $0.resizable().aspectRatio(16 / 9, contentMode: .fit) } placeholder: { Color.ink1 }
    }

    private func glyph() -> some View {
        Image(systemName: "play.fill").font(.system(size: 28)).foregroundStyle(.white)
            .padding(12).background(PlayscribeColor.ink950.opacity(0.6), in: Circle())
    }

    private func stackedPoster(_ height: CGFloat) -> some View {
        image()
            .frame(width: width, height: height)
            .background(Color.ink1)
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            .overlay { glyph() }
    }

    private var sideTile: some View {
        VStack(alignment: .leading, spacing: 6) {
            image()
                .frame(width: width, height: width * 9 / 16)
                .background(Color.ink1)
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                .overlay { glyph() }
            Text("Trailer").font(PlayscribeFont.subheadline.weight(.semibold)).foregroundStyle(PlayscribeColor.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(width: width, alignment: .leading)
        .padding(8)
        .background(PlayscribeColor.ink950.opacity(0.7), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}
