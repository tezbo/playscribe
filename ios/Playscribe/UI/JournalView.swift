import SwiftUI

/// The Updates chapter: PS5 releases first, newest expanded; PC-only notes in a collapsed group.
struct JournalView: View {
    @Environment(AppModel.self) private var model
    var gameID: String

    var body: some View {
        let listed = model.ps5Releases(gameID)
        let announced = listed.filter { $0.ps5State == .announced }
        let mine = listed.filter { $0.ps5State != .announced }
        let pc = model.pcOnlyReleases(gameID)
        let groupKey = "pconly:\(gameID)"
        let groupOpen = model.isExpanded(groupKey, default: pc.contains { $0.id == model.focusReleaseID })

        // A Group, not a stack: each release is a direct child of the reading panel's lazy stack,
        // so deep links can scroll it to the top (R-1, N-6).
        Group {
            if !announced.isEmpty {
                SectionHeader(title: "Coming to PS5")
                ForEach(announced) { ReleaseEntry(release: $0, defaultOpen: false).id("rel-\($0.id)") }
            }

            SectionHeader(title: "On PS5")
            if mine.isEmpty, let game = model.game(gameID) {
                // GR-1: never an empty game. When it's out, and that we're watching for notes.
                VStack(alignment: .leading, spacing: 6) {
                    Text(game.ps5AvailabilityLine).font(PlayscribeFont.headline)
                    Text("Watching for PS5 notes · checked \(model.lastChecked.formatted(.relative(presentation: .named)))")
                        .font(PlayscribeFont.subheadline).foregroundStyle(.secondary)
                }
                .padding(.vertical, 8)
            }
            ForEach(Array(mine.enumerated()), id: \.element.id) { i, r in
                ReleaseEntry(release: r, defaultOpen: i == 0).id("rel-\(r.id)")
            }

            if !pc.isEmpty {
                Button { model.setExpanded(groupKey, !groupOpen) } label: {
                    HStack {
                        Text("PC only so far").font(PlayscribeFont.headline)
                        Text("· \(pc.count) update\(pc.count == 1 ? "" : "s")").foregroundStyle(.secondary)
                        Spacer()
                        Image(systemName: "chevron.down").rotationEffect(.degrees(groupOpen ? 180 : 0))
                    }
                    .frame(minHeight: 44)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .tappableFrame()
                .id("pconly")
                if groupOpen {
                    ForEach(pc) { ReleaseEntry(release: $0, defaultOpen: false).id("rel-\($0.id)") }
                }
            }
        }
    }
}

struct SectionHeader: View {
    var title: String
    var body: some View {
        Text(title).font(PlayscribeFont.title3.weight(.semibold)).padding(.top, 4)
            .accessibilityAddTraits(.isHeader)
    }
}

struct ReleaseEntry: View {
    @Environment(AppModel.self) private var model
    var release: Release
    var defaultOpen: Bool
    @State private var readTask: Task<Void, Never>?

    var body: some View {
        let r = release
        let key = "rel:\(r.id)"
        let open = model.isExpanded(key, default: defaultOpen)
        let unread = model.isUnread(r)

        VStack(alignment: .leading, spacing: 10) {
            Button { model.setExpanded(key, !open) } label: {
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 8) {
                        if unread { UnreadDot() }
                        Text(r.displayName).font(PlayscribeFont.headline)
                        ReleaseTag(release: r)
                        Spacer(minLength: 0)
                        Image(systemName: "chevron.down").rotationEffect(.degrees(open ? 180 : 0)).foregroundStyle(.secondary)
                    }
                    HStack(spacing: 6) {
                        Text(r.kind.label)
                        Text("·")
                        Text(r.isPS5Listed ? r.ps5Date.shortDay : r.latestDate.shortDay)
                        // R-2 / V-2: the PS5 version exactly as the console shows it; never a PC number.
                        if let v = r.ps5Version { Text("·"); Text(v).monospacedDigit() }
                    }
                    .font(PlayscribeFont.subheadline).foregroundStyle(.secondary)
                    if !open, let h = r.isPS5Listed ? r.ps5Headline : r.headline { Text(h).font(PlayscribeFont.subheadline).lineLimit(2) }
                }
                .contentShape(Rectangle())
                .frame(minHeight: 44)
            }
            .buttonStyle(.plain)
            .tappableFrame()
            .accessibilityHint(open ? "Collapses the update" : "Expands the update")

            if open {
                ReleaseBody(release: r)
                    .onScrollVisibilityChange(threshold: 0.5) { visible in
                        // R-6: read once the body has been at least half on screen for a second.
                        readTask?.cancel()
                        guard visible, model.isUnread(r) else { return }
                        readTask = Task {
                            try? await Task.sleep(for: .seconds(1))
                            if !Task.isCancelled { model.markRead(r.id) }
                        }
                    }
            }
        }
        .padding(14)
        .background(model.highlight == r.id ? PlayscribeColor.accent.opacity(0.18) : Color.ink2, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .task(id: model.highlight) {
            guard model.highlight == r.id else { return }
            try? await Task.sleep(for: .milliseconds(300))
            withAnimation { model.highlight = nil }
        }
    }
}

struct ReleaseTag: View {
    var release: Release
    var body: some View {
        switch release.ps5State {
        case .onPS5: if release.simulated == true { Tag(text: "Simulated", tint: .simulated) }
        case .announced: Tag(text: "Announced", tint: .ember)
        case .reported: Tag(text: release.isSilent ? "Reported · Silent update" : "Reported", tint: .secondary)
                .accessibilityLabel("Reported on PS5")
        case .pcOnly: Tag(text: "PC", tint: .secondary)
        case .notPlanned: Tag(text: "Not planned for PS5", tint: .secondary)
        case .pending: EmptyView()
        }
    }
}

/// The release whose facts the Spread shows in its Margin column (O-4), if any.
private struct MarginReleaseKey: EnvironmentKey { static let defaultValue: String? = nil }
extension EnvironmentValues {
    var marginReleaseID: String? {
        get { self[MarginReleaseKey.self] }
        set { self[MarginReleaseKey.self] = newValue }
    }
}

/// GR-3: story first. Headline, a short summary, the key changes, one line of facts that
/// expands in place, then the full notes. Tags are the only provenance signal.
struct ReleaseBody: View {
    @Environment(AppModel.self) private var model
    @Environment(\.marginReleaseID) private var marginReleaseID
    var release: Release
    @State private var factsOpen = false
    @State private var summaryOpen = false

    var body: some View {
        let r = release
        let ps5Page = r.isPS5Listed
        VStack(alignment: .leading, spacing: 14) {
            if let h = ps5Page ? r.ps5Headline : r.headline {
                Text(h).font(PlayscribeFont.title3)
            }
            if let summary = ps5Page ? r.ps5Summary : r.summary {
                VStack(alignment: .leading, spacing: 4) {
                    Text(summary)
                        .lineLimit(summaryOpen ? nil : 3)
                    // GR-3: a truncated summary always says how to read the rest.
                    if summary.count > 120 {
                        Button(summaryOpen ? "Less" : "More") { withAnimation(.snappy) { summaryOpen.toggle() } }
                            .font(PlayscribeFont.subheadline.weight(.semibold))
                            .frame(minHeight: 44)
                            .accessibilityHint(summaryOpen ? "Shows less of the summary" : "Shows the full summary")
                            .tappableFrame()
                    }
                }
            }
            let keys = ps5Page ? r.ps5KeyChanges : (r.keyChanges ?? [])
            if !keys.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(keys, id: \.self) { k in
                        HStack(alignment: .firstTextBaseline, spacing: 10) {
                            Circle().fill(PlayscribeColor.accent).frame(width: 6, height: 6)
                            Text(k).font(PlayscribeFont.subheadline)
                        }
                    }
                }
            }
            if marginReleaseID != r.id {
                Button { withAnimation(.snappy) { factsOpen.toggle() } } label: {
                    HStack {
                        Text(FactsLine.text(for: r)).font(PlayscribeFont.subheadline).foregroundStyle(.secondary)
                        Spacer()
                        Image(systemName: "chevron.down").rotationEffect(.degrees(factsOpen ? 180 : 0)).foregroundStyle(.secondary)
                    }
                    .frame(minHeight: 44)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityHint(factsOpen ? "Hides the PS5 facts" : "Shows the PS5 facts")
                .tappableFrame()
                if factsOpen { FactsCard(release: r) }
            }
            if r.isSilent && r.notes.isEmpty {
                Text("No official notes").font(PlayscribeFont.subheadline).foregroundStyle(.secondary)
            }
            ForEach(Array(r.notes.enumerated()), id: \.offset) { _, section in
                NoteSectionView(release: r, section: section)
            }
            HStack(spacing: 10) {
                let marked = model.isBookmarked(kind: .release, id: r.id)
                Button { model.toggleBookmark(kind: .release, id: r.id, gameID: r.gameID) } label: {
                    Label(marked ? "Bookmarked" : "Bookmark", systemImage: marked ? "bookmark.fill" : "bookmark")
                }
                .buttonStyle(.bordered)
                .hitTarget()
                .tappableFrame()
                if r.ps5State == .onPS5 {
                    let unread = model.isUnread(r)
                    Button { model.markRead(r.id, unread) } label: {
                        Label(unread ? "Mark as read" : "Mark as unread", systemImage: unread ? "envelope.open" : "envelope.badge")
                    }
                    .buttonStyle(.bordered)
                    .hitTarget()
                    .tappableFrame()
                }
            }
        }
    }
}

/// "Live on PS5 · 13 GB · 22 Oct" (GR-3).
enum FactsLine {
    static func text(for r: Release) -> String {
        var parts: [String] = []
        switch r.ps5State {
        case .onPS5: parts.append("Live on PS5")
        case .announced: parts.append("Announced for PS5")
        case .reported: parts.append("Reported on PS5")
        case .notPlanned: parts.append("Not planned for PS5")
        case .pcOnly, .pending: parts.append("PC only so far")
        }
        if let v = r.ps5Version { parts.append(v) }
        if let size = r.ps5?.sizeBytes { parts.append(ByteCountFormatter.string(fromByteCount: size.value, countStyle: .decimal)) }
        parts.append((r.isPS5Listed ? r.ps5Date : r.latestDate).dayMonth)
        return parts.joined(separator: " · ")
    }
}

/// The facts card (the Margin's inline form, O-4).
struct FactsCard: View {
    var release: Release
    var body: some View {
        VStack(alignment: .leading, spacing: 8) { Facts(release: release) }
            .padding(12)
            .background(Color.ink1.opacity(0.7), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}

/// R-3 facts.
struct Facts: View {
    @Environment(AppModel.self) private var model
    var release: Release
    /// The Margin column stacks each label over its value; the inline card uses two columns.
    var stacked = false

    var body: some View {
        if stacked {
            VStack(alignment: .leading, spacing: 14) { rows }
        } else {
            Grid(alignment: .topLeading, horizontalSpacing: 12, verticalSpacing: 8) { rows }
        }
    }

    @ViewBuilder private var rows: some View {
        let r = release
        let p = r.ps5
        Group {
            row("Status", Text(status))
            if r.isPS5Listed {
                row("PS5 version", Text(p?.version?.value ?? "Not published yet").foregroundStyle(p?.version == nil ? .secondary : .primary))
            }
            if let size = p?.sizeBytes {
                row("Download", HStack(spacing: 6) {
                    Text(ByteCountFormatter.string(fromByteCount: size.value, countStyle: .decimal))
                    if size.verification == .reported { Tag(text: "Reported") }
                })
            } else if !r.isPS5Listed, let size = r.platforms.first(where: { $0.platform == .pc })?.sizeBytes {
                row("Download", Text("\(ByteCountFormatter.string(fromByteCount: size.value, countStyle: .decimal)) on PC"))
            }
            if let bundles = p?.bundles, !bundles.isEmpty {
                row("Includes", VStack(alignment: .leading) {
                    ForEach(bundles, id: \.self) { id in
                        Button(model.release(r.gameID, id)?.displayName ?? id) {
                            model.setExpanded("pconly:\(r.gameID)", true)
                            model.openGame(r.gameID, chapter: .updates, releaseID: id)
                        }
                    }
                })
            }
            row("Video", VideoFact(release: r))
            if let checked = p?.liveAt?.checkedAt, Date.now.timeIntervalSince(checked) > 86_400 {
                row("Checked", Text(checked.shortDay).font(PlayscribeFont.footnote).foregroundStyle(.secondary))
            }
        }
        .font(PlayscribeFont.subheadline)
        Text("\(Brand.name) can't see what's installed on your console.").font(PlayscribeFont.footnote).foregroundStyle(.secondary)
    }

    private var status: String {
        switch release.ps5State {
        case .onPS5: "Live on PS5"
        case .announced: "Announced for PS5"
        case .reported: "Reported on PS5"
        case .notPlanned: "Not planned for PS5"
        case .pcOnly, .pending:
            "Live on " + release.platforms.filter { $0.status == .live }.map(\.platform.label).joined(separator: ", ") + ". Not confirmed on PS5."
        }
    }

    @ViewBuilder private func row(_ label: String, _ value: some View) -> some View {
        if stacked {
            VStack(alignment: .leading, spacing: 3) {
                Text(label).font(PlayscribeFont.caption).foregroundStyle(PlayscribeColor.textTertiary)
                value
            }
        } else {
            GridRow {
                Text(label).foregroundStyle(.secondary).gridColumnAlignment(.leading)
                value
            }
        }
    }
}

struct VideoFact: View {
    @Environment(AppModel.self) private var model
    @Environment(\.openURL) private var openURL
    var release: Release

    var body: some View {
        if let v = release.video {
            Button { model.player = (release.gameID, release.id) } label: {
                HStack(spacing: 10) {
                    ZStack {
                        if let poster = v.posterAsset { Image(poster).resizable().scaledToFill() } else { Color.ink3 }
                        Image(systemName: "play.fill").font(PlayscribeFont.caption).padding(8).background(.ultraThinMaterial, in: Circle())
                    }
                    .frame(width: 88, height: 50)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                    VStack(alignment: .leading, spacing: 2) {
                        Text(v.label).font(PlayscribeFont.subheadline.weight(.semibold))
                        Text([v.duration, v.posted.isoDay.map { "Posted \($0.shortDay)" }].compactMap { $0 }.joined(separator: " · "))
                            .font(PlayscribeFont.caption).foregroundStyle(.secondary)
                    }
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Play \(v.label)")
            .tappableFrame()
        } else {
            Text(release.videoNote ?? "No official video for this update").foregroundStyle(.secondary)
        }
    }
}

struct NoteSectionView: View {
    @Environment(AppModel.self) private var model
    var release: Release
    var section: NoteSection
    @State private var showPC = false

    var body: some View {
        let key = "cat:\(release.id):\(section.title)"
        let open = model.isExpanded(key)
        let ps5Items = release.isPS5Listed ? section.items.filter { !$0.isPCOnly } : section.items
        let pcOnly = release.isPS5Listed ? section.items.filter(\.isPCOnly) : []
        let hidden = section.items.filter { $0.spoiler == true }.count
        VStack(alignment: .leading, spacing: 8) {
            Button { model.setExpanded(key, !open) } label: {
                HStack {
                    Text(section.title).font(PlayscribeFont.subheadline.weight(.semibold))
                    Text("\(section.items.count)\(hidden > 0 && !model.spoilersShown(release.gameID) ? " · \(hidden) hidden for spoilers" : "")")
                        .font(PlayscribeFont.caption).foregroundStyle(.secondary)
                    Spacer()
                    Image(systemName: "chevron.down").rotationEffect(.degrees(open ? 180 : 0)).foregroundStyle(.secondary)
                }
                .frame(minHeight: 44)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .tappableFrame()
            if open {
                ForEach(Array(ps5Items.enumerated()), id: \.offset) { i, item in
                    NoteItemView(item: item, gameID: release.gameID, key: "\(key):\(i)")
                }
                if !pcOnly.isEmpty {
                    Button(showPC ? "Hide PC-only changes" : "Show PC-only changes (\(pcOnly.count))") { showPC.toggle() }
                        .font(PlayscribeFont.footnote).hitTarget()
                    if showPC {
                        ForEach(Array(pcOnly.enumerated()), id: \.offset) { i, item in
                            NoteItemView(item: item, gameID: release.gameID, key: "\(key):pc:\(i)")
                        }
                    }
                }
            }
        }
        .padding(.horizontal, 10)
        .background(Color.ink1.opacity(0.6), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }
}

struct NoteItemView: View {
    @Environment(AppModel.self) private var model
    var item: NoteItem
    var gameID: String
    var key: String

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text("•").foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 4) {
                if item.spoiler == true { SpoilerText(text: item.text, gameID: gameID, key: key) } else { Text(item.text) }
                if item.ps5ProOnly { Tag(text: "PS5 Pro") }
            }
        }
        .font(PlayscribeFont.subheadline)
        .padding(.bottom, 4)
    }
}

/// R-5: blurred until tapped, or until the game's spoiler switch is on.
struct SpoilerText: View {
    @Environment(AppModel.self) private var model
    var text: String
    var gameID: String
    var key: String

    var body: some View {
        if model.isRevealed(key, gameID: gameID) {
            Text(text)
        } else {
            Button { model.reveal(key) } label: {
                ZStack(alignment: .leading) {
                    Text(text).blur(radius: 6).accessibilityHidden(true)
                    Label("Spoiler · tap to show", systemImage: "eye.slash")
                        .font(PlayscribeFont.caption.weight(.semibold))
                        .padding(.horizontal, 8).padding(.vertical, 4)
                        .background(.ultraThinMaterial, in: Capsule())
                }
                .frame(minHeight: 44)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Story spoiler. Double-tap to show.")
            .tappableFrame()
        }
    }
}
