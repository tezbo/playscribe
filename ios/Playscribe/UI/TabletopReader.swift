import SwiftUI

/// Tabletop reading (TT-2): the standing half shows one section of the release at a time in
/// large type over the game's art; the flat half holds the chapter switcher, the outline,
/// Previous and Next, and the rail. Nothing scrolls on the standing half.
struct ReaderSection: Identifiable, Hashable {
    var id: String
    var title: String
    var body: String
}

extension AppModel {
    /// The release the Reader shows: the focused one, else the newest On PS5 release.
    func readerRelease(_ gameID: String) -> Release? {
        if let id = focusReleaseID, let r = release(gameID, id) { return r }
        // J-1: the release picked in the list, as on every other Page.
        return selectedRelease(gameID) ?? releases(gameID).first
    }

    /// Overview, each key change, Fixes, then PS5 facts and video.
    func readerSections(_ r: Release) -> [ReaderSection] {
        var out = [ReaderSection(id: "overview", title: r.headline ?? r.displayName, body: r.summary ?? "")]
        for (i, k) in (r.keyChanges ?? []).enumerated() {
            let parts = k.split(separator: ":", maxSplits: 1).map { $0.trimmingCharacters(in: .whitespaces) }
            out.append(ReaderSection(id: "key-\(i)", title: parts.count == 2 ? parts[0] : "Change \(i + 1)",
                                     body: parts.count == 2 ? parts[1].prefix(1).uppercased() + parts[1].dropFirst() : k))
        }
        if r.noteCount > 0 {
            let first = r.notes.flatMap(\.items).filter { $0.spoiler != true }.prefix(3).map(\.text)
            out.append(ReaderSection(id: "fixes", title: "Fixes",
                                     body: "\(r.noteCount) listed changes, including: " + first.joined(separator: " ")))
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

struct TabletopReaderStage: View {
    @Environment(AppModel.self) private var model
    @Environment(\.duo) private var duo
    /// The stage's bottom edge in screen space; the text ends 24 pt above the division.
    @State private var stageBottom: CGFloat = 0
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
            if let section = sections[safe: index] {
                VStack(alignment: .leading, spacing: 14) {
                    // Eyebrow: the game and the date; the release itself is the title below.
                    HStack(spacing: 8) {
                        Text(model.game(gameID)?.name ?? "")
                        if let r = release { Text((r.isPS5Listed ? r.ps5Date : r.latestDate).dayMonthOrYear).foregroundStyle(.secondary) }
                    }
                    .font(PlayscribeFont.subheadline.weight(.semibold))
                    .foregroundStyle(PlayscribeColor.accent)
                    // The release name for VoiceOver (and J-4), when the title is a headline.
                    Color.clear.frame(width: 1, height: 1)
                        .accessibilityElement()
                        .accessibilityLabel(release?.displayName ?? "")
                        .accessibilityAddTraits(.isStaticText)
                        .accessibilityIdentifier("releaseTitle")
                    Text(section.title)
                        .font(PlayscribeFont.title)
                        .lineLimit(3)
                        .minimumScaleFactor(0.8)
                    Text(section.body)
                        .font(PlayscribeFont.body)
                        .foregroundStyle(PlayscribeColor.textPrimary.opacity(0.92))
                        .lineSpacing(4)
                        .minimumScaleFactor(0.7)
                        .accessibilityIdentifier("readerBody")
                    Spacer(minLength: 0)
                }
                // About 34 characters per line at 19 pt.
                .frame(maxWidth: 380, maxHeight: .infinity, alignment: .topLeading)
                .padding(.horizontal, 28)
                .padding(.vertical, 24)
                .padding(.bottom, duo.clearance(forBottom: stageBottom))
                .frame(maxWidth: .infinity, alignment: .leading)
                .id(section.id)
                .transition(.opacity)
            }
        }
        .onGeometryChange(for: CGFloat.self) { $0.frame(in: .global).maxY } action: { stageBottom = $0 }
        .animation(.easeInOut(duration: 0.2), value: index)
        // Its parts stay separate elements, so the release title is findable (J-4).
        .accessibilityElement(children: .contain)
    }
}

struct TabletopReaderControls: View {
    @Environment(AppModel.self) private var model
    @Environment(\.railWidth) private var railWidth
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
                            .accessibilityAddTraits(i == index ? .isSelected : [])
                            .tappableFrame()
                            .id(i)
                        }
                    }
                }
                .onChange(of: index) { _, i in withAnimation { proxy.scrollTo(i, anchor: .center) } }
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
    }

    private func pageButton(_ title: String, _ symbol: String, enabled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(title, systemImage: symbol)
                .font(PlayscribeFont.headline)
                .frame(maxWidth: .infinity, minHeight: 52)
                .background(PlayscribeColor.ink700, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
        .opacity(enabled ? 1 : 0.4)
        .tappableFrame()
    }
}

extension Array {
    subscript(safe i: Int) -> Element? { indices.contains(i) ? self[i] : nil }
}
