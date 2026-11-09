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
            FollowingList(gameID: gameID)
            if !announced.isEmpty {
                SectionHeader(title: "Coming to PS5")
                ForEach(announced) { ReleaseEntry(release: $0, defaultOpen: false).id("rel-\($0.id)") }
            }

            SectionHeader(title: "On PS5")
            if mine.isEmpty, let game = model.game(gameID) {
                // GR-1: never an empty game. When it's out, and that we're watching for notes.
                VStack(alignment: .leading, spacing: 6) {
                    Text(game.ps5AvailabilityLine).font(PlayscribeFont.headline)
                    NoUpdatesLine(gameID: gameID)
                }
                .padding(.vertical, 8)
            }
            ForEach(Array(mine.enumerated()), id: \.element.id) { i, r in
                ReleaseEntry(release: r, defaultOpen: i == 0).id("rel-\(r.id)")
            }

            if !pc.isEmpty {
                Button { model.setExpanded(groupKey, !groupOpen) } label: {
                    HStack {
                        Text("Other updates").font(PlayscribeFont.headline)
                        Text("\(pc.count) update\(pc.count == 1 ? "" : "s")").foregroundStyle(.secondary)
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
    @Environment(\.dynamicTypeSize) private var typeSize

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
                        TitleWithTags(release: r) { Text(r.displayName).font(PlayscribeFont.headline) }
                        Spacer(minLength: 0)
                        Image(systemName: "chevron.down").rotationEffect(.degrees(open ? 180 : 0)).foregroundStyle(.secondary)
                    }
                    // At accessibility sizes the facts stack, each on its own full-width line, so the date never wraps by letter.
                    let facts = Group {
                        Text(r.kind.label)
                        Text(r.isPS5Listed ? r.ps5Date.shortDay : r.latestDate.shortDay)
                        // R-2 / V-2: the PS5 version exactly as the console shows it; never a PC number.
                        if let v = r.ps5Version { Text(v).monospacedDigit() }
                    }
                    Group {
                        if typeSize.isAccessibilitySize { VStack(alignment: .leading, spacing: 2) { facts } }
                        else { HStack(spacing: 8) { facts } }
                    }
                    .font(PlayscribeFont.subheadline).foregroundStyle(.secondary)
                    if !open, let h = r.isPS5Listed ? r.ps5Headline : r.headline {
                        if typeSize.isAccessibilitySize { WholeWordText(text: h, font: PlayscribeFont.subheadline, lines: 4) }
                        else { Text(h).font(PlayscribeFont.subheadline).lineLimit(2) }
                    }
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
        HStack(spacing: 6) {
            // Every PS4 patch says so, whatever its state; the patch name stays the title (R-2).
            if let l = release.ps4Label { Tag(text: l, tint: .secondary) }
            state
        }
    }

    @ViewBuilder private var state: some View {
        switch release.ps5State {
        case .onPS5: if release.simulated == true { Tag(text: "Simulated", tint: .simulated) }
        case .announced: Tag(text: "Announced", tint: .ember)
        case .reported: if release.ps4 == true { Tag(text: "Reported", tint: .secondary) }
        case .notPlanned: Tag(text: "Not planned for PS5", tint: .secondary)
        case .pending: EmptyView()
        }
    }
}

/// An update's title with its tags: beside it at standard sizes, stacked under it at accessibility sizes, so
/// neither the title truncates nor a tag breaks mid-word.
struct TitleWithTags<Title: View>: View {
    var release: Release
    @ViewBuilder var title: Title
    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        if typeSize.isAccessibilitySize {
            VStack(alignment: .leading, spacing: 4) { title; ReleaseTag(release: release) }
        } else {
            // The title never truncates: when the tags don't fit beside it they drop under it.
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 8) { title.lineLimit(1).fixedSize(horizontal: true, vertical: false); ReleaseTag(release: release) }
                VStack(alignment: .leading, spacing: 4) { title; ReleaseTag(release: release) }
            }
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
    @Environment(\.dynamicTypeSize) private var typeSize
    var release: Release
    /// D-13: facts expanded or collapsed persists.
    @AppStorage("factsOpen") private var factsOpen = false
    @State private var summaryOpen = false

    var body: some View {
        let r = release
        let ps5Page = r.isPS5Listed
        VStack(alignment: .leading, spacing: 14) {
            if let h = ps5Page ? r.ps5Headline : r.headline {
                // At accessibility sizes: the standing 4 whole-word line cap, "…" only when it still overflows.
                if typeSize.isAccessibilitySize { WholeWordText(text: h, font: PlayscribeFont.title3, lines: 4) }
                else { Text(h).font(PlayscribeFont.title3) }
            } else if !r.notes.isEmpty {
                Text("Fixes and tuning").font(PlayscribeFont.title3)
            }
            if let summary = ps5Page ? r.ps5Summary : r.summary {
                VStack(alignment: .leading, spacing: 4) {
                    if summaryOpen {
                        LinkedTextView(text: summary)
                    } else {
                        // Collapsed: three lines ending on a whole word, never a cut one ("co…"); More shows it all, with links.
                        WholeWordText(text: LinkedText.clean(summary), font: PlayscribeFont.body, lines: 3)
                    }
                    // GR-3: a truncated summary always says how to read the rest.
                    if summary.count > 120 {
                        Button(summaryOpen ? "Less" : "More") { withAnimation(.snappy) { summaryOpen.toggle() } }
                            .font(PlayscribeFont.subheadline.weight(.semibold))
                            .frame(minWidth: 44, minHeight: 44)
                            .contentShape(Rectangle())
                            .accessibilityHint(summaryOpen ? "Shows less of the summary" : "Shows the full summary")
                            .tappableFrame()
                    }
                }
            }
            if let minutes = r.readMinutes {
                Text("\(minutes) min read").font(PlayscribeFont.footnote.weight(.semibold)).foregroundStyle(.secondary)
                    .accessibilityLabel("About \(minutes) minute\(minutes == 1 ? "" : "s") to read")
            }
            let keys = ps5Page ? r.ps5KeyChanges : (r.keyChanges ?? [])
            if !keys.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text("What's new").font(PlayscribeFont.headline).accessibilityAddTraits(.isHeader)
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
                    let chevron = Image(systemName: "chevron.down").rotationEffect(.degrees(factsOpen ? 180 : 0)).foregroundStyle(.secondary)
                    if typeSize.isAccessibilitySize {
                        // AX: one block, "Released ...", then the size, then the chevron, full width (R-2, Iris on #288 at AX3).
                        VStack(alignment: .leading, spacing: 4) {
                            Text(FactsLine.text(for: r)).font(PlayscribeFont.subheadline).fixedSize(horizontal: false, vertical: true)
                            if let d = FactsLine.detail(for: r) {
                                Text(d).font(PlayscribeFont.subheadline).monospacedDigit().foregroundStyle(.secondary)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                            HStack { Spacer(minLength: 0); chevron }
                        }
                        .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                        .contentShape(Rectangle())
                    } else {
                        HStack {
                            Text(FactsLine.text(for: r)).font(PlayscribeFont.subheadline)
                            if let d = FactsLine.detail(for: r) { Text(d).font(PlayscribeFont.subheadline).monospacedDigit().foregroundStyle(.secondary) }
                            Spacer()
                            chevron
                        }
                        .frame(minHeight: 44)
                        .contentShape(Rectangle())
                    }
                }
                .buttonStyle(.plain)
                .accessibilityHint(factsOpen ? "Hides the PS5 facts" : "Shows the PS5 facts")
                .tappableFrame()
                if factsOpen { FactsCard(release: r) }
            }
            if r.isSilent && r.notes.isEmpty {
                Text("No official notes").font(PlayscribeFont.subheadline).foregroundStyle(.secondary)
            }
            // A-reader: changes grouped New, Fixed, Balance; the heading has no count, the sub-sections keep theirs (Terry, 0.5.4).
            let groups = ChangeKind.grouped(r.notes, ps5Only: ps5Page)
            ForEach(groups, id: \.kind) { g in
                Text(g.kind.rawValue).font(PlayscribeFont.title3).padding(.top, 6)
                    .accessibilityAddTraits(.isHeader)
                ForEach(Array(g.sections.enumerated()), id: \.offset) { _, section in
                    NoteSectionView(release: r, section: section)
                }
            }
            // Accessibility sizes: the Bookmark and Mark as read buttons stack, each the full width, so a label wraps on
            // whole words ("Bookmar / k" at AX5, c240de9).
            let actions = typeSize.isAccessibilitySize
                ? AnyLayout(VStackLayout(alignment: .leading, spacing: 10)) : AnyLayout(HStackLayout(spacing: 10))
            actions {
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

/// "Released 22 Oct" (GR-3), with the version and size as secondary detail.
enum FactsLine {
    static func text(for r: Release) -> String {
        // "19 Apr 2025" once the year is not this one, so an old update never reads as recent.
        let date = (r.isPS5Listed ? r.ps5Date : r.latestDate).dayMonthOrYear
        switch r.ps5State {
        case .onPS5, .pending: return "Released \(date)"
        case .announced: return "Announced for PS5, \(date)"
        case .reported: return "Released \(date)"
        case .notPlanned: return "Not planned for PS5"
        }
    }

    static func detail(for r: Release) -> String? {
        var parts: [String] = []
        if let v = r.ps5Version { parts.append(v) }
        if let size = r.ps5?.sizeBytes {
            let text = ByteCountFormatter.string(fromByteCount: size.value, countStyle: .decimal)
            parts.append(text)
        }
        return parts.isEmpty ? nil : parts.joined(separator: ", ")
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
            if r.isPS5Listed, let v = p?.version?.value {
                row("PS5 version", Text(v))
            }
            if let size = p?.sizeBytes {
                row("Download", HStack(spacing: 6) {
                    Text(ByteCountFormatter.string(fromByteCount: size.value, countStyle: .decimal))
                    if size.verification == .reported { VerificationTag(kind: .reported) }
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
                row("Checked", Text(checked.localShortDay).font(PlayscribeFont.footnote).foregroundStyle(.secondary))
            }
        }
        .font(PlayscribeFont.subheadline)
    }

    private var status: String {
        switch release.ps5State {
        case .onPS5: "Released"
        case .announced: "Announced for PS5"
        case .reported: "Reported on PS5"
        case .notPlanned: "Not planned for PS5"
        case .pending: "Released"
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
                        Text([v.duration, v.posted.isoDay.map { "Posted \($0.shortDay)" }].compactMap { $0 }.joined(separator: ", "))
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
        // Kept in the model, not @State, so a re-created page never snaps it shut (TestFlight #302).
        let allShown = model.isExpanded("\(key):more")
        // Only items with something to show count, so the number matches the bullets (TestFlight #301).
        let shown = section.items.filter { !ChangeKind.isPreamble($0.text) && !LinkedText.clean($0.text).isEmpty }
        let ps5Items = release.isPS5Listed ? shown.filter { !$0.isPCOnly } : shown
        let pcOnly = release.isPS5Listed ? shown.filter(\.isPCOnly) : []
        let hidden = ps5Items.filter { $0.spoiler == true }.count
        VStack(alignment: .leading, spacing: 8) {
            Button { model.setExpanded(key, !open) } label: {
                HStack {
                    Text(LinkedText.clean(section.title)).font(PlayscribeFont.subheadline.weight(.semibold))
                    Text("\(ps5Items.count)\(hidden > 0 && !model.spoilersShown(release.gameID) ? ", \(hidden) hidden for spoilers" : "")")
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
                let visible = allShown ? ps5Items.count : min(5, ps5Items.count)
                ForEach(Array(ps5Items.prefix(visible).enumerated()), id: \.offset) { i, item in
                    NoteItemView(item: item, gameID: release.gameID, key: "\(key):\(i)")
                }
                if ps5Items.count > 5 {
                    Button(allShown ? "Show fewer" : "Show \(ps5Items.count - 5) more") { model.setExpanded("\(key):more", !allShown) }
                        .font(PlayscribeFont.footnote).hitTarget()
                }
                if !pcOnly.isEmpty {
                    Button(showPC ? "Hide PC only" : "Show PC only (\(pcOnly.count))") { showPC.toggle() }
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
                if item.spoiler == true { SpoilerText(text: item.text, gameID: gameID, key: key) } else { LinkedTextView(text: item.text) }
                if item.ps5ProOnly { Tag(text: "PS5 Pro") }
            }
            if let issue = model.knownIssue(for: item, in: gameID) {
                Spacer(minLength: 0)
                FollowIssueButton(issue: issue)
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
            LinkedTextView(text: text)
        } else {
            Button { model.reveal(key) } label: {
                ZStack(alignment: .leading) {
                    Text(LinkedText.clean(text)).blur(radius: 6).accessibilityHidden(true)
                    Label("Spoiler. Tap to show", systemImage: "eye.slash")
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

/// Links back to where the notes came from: the studio's PS5 page first, then the Steam post.
struct SourceLinks: View {
    var release: Release
    var body: some View {
        HStack(spacing: 16) {
            if let url = release.links?.ps5Page {
                Link(destination: url) { Label(LinkHost.label("PS5 update page", url), systemImage: "arrow.up.right.square") }
                    .frame(minHeight: 44).tappableFrame()
                    .accessibilityHint("Opens in browser")
            }
            if let url = release.links?.steamNotes {
                Link(destination: url) { Label(LinkHost.label("Read full notes", url), systemImage: "arrow.up.right.square").frame(minHeight: 44).contentShape(Rectangle()) }
                    .padding(.trailing, 8)
                    .tappableFrame()
                    .accessibilityHint("Opens in browser")
            }
        }
        .font(PlayscribeFont.subheadline)
        .foregroundStyle(PlayscribeColor.accent)
    }
}

/// New, Fixed and Balance: the reader's change groups, chosen from the section title.
enum ChangeKind: String, CaseIterable {
    case new = "New", fixed = "Fixed", balance = "Balance", other = "Other changes"

    /// Keywords in the section title; a title the guess cannot place goes under Other changes,
    /// never into a wrong group (Iris). Replace with the feed's category field when it lands.
    static func of(_ title: String) -> ChangeKind {
        let t = title.lowercased()
        if t.contains("fix") || t.contains("bug") || t.contains("crash") || t.contains("stabil") { return .fixed }
        if t.contains("balanc") || t.contains("tuning") || t.contains("adjust") || t.contains("tweak") { return .balance }
        if t.contains("new") || t.contains("add") || t.contains("feature") || t.contains("introduc") { return .new }
        return .other
    }

    /// The feed's category when present, else the keyword guess on the section title.
    static func of(_ item: NoteItem, in title: String) -> ChangeKind {
        switch item.category {
        case "new": .new
        case "fixed": .fixed
        case "balance": .balance
        case "other": .other
        default: of(title)
        }
    }

    /// A greeting or the spoiler warning itself is not a change: never a bullet or part of a count.
    /// The warning's job is done by the spoiler switch it turns on for the lines after it.
    static func isPreamble(_ text: String) -> Bool { NoteItem.isGreeting(text) || NoteItem.isSpoilerWarning(text) }

    /// Non-empty groups in New, Fixed, Balance, Other order; the count leaves out PC-only lines on a PS5 page.
    static func grouped(_ notes: [NoteSection], ps5Only: Bool) -> [(kind: ChangeKind, sections: [NoteSection], count: Int)] {
        allCases.compactMap { kind in
            let sections = notes.compactMap { sec -> NoteSection? in
                let items = sec.items.filter { of($0, in: sec.title) == kind && !isPreamble($0.text) }
                // On a PS5 page a section with nothing for PS5 (only PC-only or blank lines) is left out, never "0".
                let shows = items.contains { !(ps5Only && $0.isPCOnly) && !LinkedText.clean($0.text).isEmpty }
                return items.isEmpty || !shows ? nil : NoteSection(title: sec.title, items: items)
            }
            guard !sections.isEmpty else { return nil }
            let count = sections.reduce(0) { total, sec in total + sec.items.filter { item in !(ps5Only && item.isPCOnly) && !LinkedText.clean(item.text).isEmpty }.count }
            return (kind, sections, count)
        }
    }
}

/// Where an external link goes, as a brand name, so a tap never surprises: "Read full notes on Steam",
/// "All patch notes on Remedy". A host we don't know is "on the developer's site", never an address or a
/// raw domain word (V-3).
enum LinkHost {
    private static let brands = [
        "steampowered": "Steam", "steamcommunity": "Steam", "playstation": "PlayStation",
        "ea": "EA", "xbox": "Xbox", "nintendo": "Nintendo", "gog": "GOG", "epicgames": "Epic Games",
        "ubisoft": "Ubisoft", "remedygames": "Remedy", "deepsilver": "Deep Silver", "gamesci": "Game Science",
        "dawnwalkergame": "Rebel Wolves", "bandainamcoent": "Bandai Namco", "bandainamco": "Bandai Namco",
        "capcom": "Capcom", "square-enix": "Square Enix", "square-enix-games": "Square Enix", "sega": "Sega",
        "bethesda": "Bethesda", "cdprojektred": "CD PROJEKT RED", "rockstargames": "Rockstar Games",
        "activision": "Activision", "2k": "2K", "warhorsestudios": "Warhorse Studios", "konami": "Konami",
        "pushsquare": "Push Square", "playstationlifestyle": "PlayStation LifeStyle"
    ]
    static let unknown = "the developer's site"

    /// The brand for a known host; nil for one we don't know or a URL with no host.
    static func name(_ url: URL) -> String? {
        guard let host = url.host()?.lowercased(), !host.isEmpty else { return nil }
        var parts = host.split(separator: ".").map(String.init)
        // The label before the public suffix: "co.uk" and "com.au" take two parts.
        if parts.count >= 3, ["co", "com", "org", "net", "gov"].contains(parts[parts.count - 2]) { parts.removeLast(2) }
        else if parts.count >= 2 { parts.removeLast() }
        guard let label = parts.last else { return nil }
        return brands[label]
    }

    static func label(_ base: String, _ url: URL) -> String {
        guard url.host()?.isEmpty == false else { return base }
        return "\(base) on \(name(url) ?? unknown)"
    }
}
