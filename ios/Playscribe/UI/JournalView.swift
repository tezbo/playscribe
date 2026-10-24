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

        VStack(alignment: .leading, spacing: 14) {
            if !announced.isEmpty {
                SectionHeader(title: "Coming to PS5")
                ForEach(announced) { ReleaseEntry(release: $0, defaultOpen: false).id("rel-\($0.id)") }
            }

            SectionHeader(title: "On PS5")
            if mine.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    Text("No PS5 notes yet").font(.headline)
                    Text(pc.isEmpty
                         ? "\(Brand.name) doesn't have verified patch notes for this game yet, so nothing is shown rather than guessed."
                         : "This game has official notes for its PC build only. They're kept below and don't count as new until they're confirmed on PS5.")
                        .font(.subheadline).foregroundStyle(.secondary)
                }
                .padding(.vertical, 8)
            }
            ForEach(Array(mine.enumerated()), id: \.element.id) { i, r in
                ReleaseEntry(release: r, defaultOpen: i == 0).id("rel-\(r.id)")
            }

            if !pc.isEmpty {
                Button { model.setExpanded(groupKey, !groupOpen) } label: {
                    HStack {
                        Text("PC only so far").font(.headline)
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
                    Text("The developer's official notes for these describe the PC build. They may reach PS5 later, under a different version number. \(Brand.name) counts them as yours only once that's confirmed.")
                        .font(.footnote).foregroundStyle(.secondary)
                    ForEach(pc) { ReleaseEntry(release: $0, defaultOpen: false).id("rel-\($0.id)") }
                }
            }
        }
    }
}

struct SectionHeader: View {
    var title: String
    var body: some View {
        Text(title).font(.title3.weight(.semibold)).fontDesign(.serif).padding(.top, 4)
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
                        Text(r.displayName).font(.headline)
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
                    .font(.subheadline).foregroundStyle(.secondary)
                    if !open, let h = r.headline { Text(h).font(.subheadline).lineLimit(2) }
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
        .background(model.highlight == r.id ? Color.accentColor.opacity(0.18) : Color.ink2, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
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

struct ReleaseBody: View {
    @Environment(AppModel.self) private var model
    var release: Release

    var body: some View {
        let r = release
        VStack(alignment: .leading, spacing: 14) {
            if let h = r.headline { Text(h).font(.body.weight(.semibold)) }
            Facts(release: r)
            if let summary = r.summary {
                VStack(alignment: .leading, spacing: 8) {
                    Label("\(Brand.name) summary", systemImage: "sparkles").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                    Text(summary)
                    ForEach(r.keyChanges ?? [], id: \.self) { k in
                        Label { Text(k) } icon: { Image(systemName: "circle.fill").font(.system(size: 5)) }
                            .font(.subheadline)
                    }
                }
                .padding(12)
                .background(Color.ink3.opacity(0.6), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            }
            if r.isSilent && r.notes.isEmpty {
                Text("No official notes").font(.subheadline).foregroundStyle(.secondary)
            }
            if !r.notes.isEmpty {
                Text("Official notes · \(r.noteCount) items").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                ForEach(Array(r.notes.enumerated()), id: \.offset) { _, section in
                    NoteSectionView(release: r, section: section)
                }
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
                        Label(unread ? "Mark as read" : "Mark as unread", systemImage: unread ? "checkmark.circle" : "circle")
                    }
                    .buttonStyle(.bordered)
                    .hitTarget()
                    .tappableFrame()
                }
            }
        }
    }
}

/// R-3 facts.
struct Facts: View {
    @Environment(AppModel.self) private var model
    var release: Release

    var body: some View {
        let r = release
        let p = r.ps5
        Grid(alignment: .topLeading, horizontalSpacing: 12, verticalSpacing: 8) {
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
                row("Checked", Text(checked.shortDay).font(.footnote).foregroundStyle(.secondary))
            }
        }
        .font(.subheadline)
        Text("\(Brand.name) can't see what's installed on your console.").font(.footnote).foregroundStyle(.secondary)
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

    private func row(_ label: String, _ value: some View) -> some View {
        GridRow {
            Text(label).foregroundStyle(.secondary).gridColumnAlignment(.leading)
            value
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
                        Image(systemName: "play.fill").font(.caption).padding(8).background(.ultraThinMaterial, in: Circle())
                    }
                    .frame(width: 88, height: 50)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                    VStack(alignment: .leading, spacing: 2) {
                        Text(v.label).font(.subheadline.weight(.semibold))
                        Text([v.duration, v.posted.isoDay.map { "Posted \($0.shortDay)" }].compactMap { $0 }.joined(separator: " · "))
                            .font(.caption).foregroundStyle(.secondary)
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
        let ps5Items = section.items.filter { $0.platforms == nil || $0.platforms!.contains(.ps5) }
        let pcOnly = section.items.filter { $0.platforms != nil && !$0.platforms!.contains(.ps5) }
        let hidden = section.items.filter { $0.spoiler == true }.count
        VStack(alignment: .leading, spacing: 8) {
            Button { model.setExpanded(key, !open) } label: {
                HStack {
                    Text(section.title).font(.subheadline.weight(.semibold))
                    Text("\(section.items.count)\(hidden > 0 && !model.spoilersShown(release.gameID) ? " · \(hidden) hidden for spoilers" : "")")
                        .font(.caption).foregroundStyle(.secondary)
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
                        .font(.footnote).hitTarget()
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
        .font(.subheadline)
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
                        .font(.caption.weight(.semibold))
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
