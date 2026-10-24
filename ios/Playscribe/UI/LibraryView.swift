import SwiftUI

struct LibraryView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.duo) private var duo

    var body: some View {
        Group {
            if model.data.collection.isEmpty {
                OnboardingView()
            } else if duo.isFolded {
                // Book and tabletop: the fold splits the shelf from its stage (B-5, B-6).
                ArrangementView {
                    LibraryShelf()
                } secondary: {
                    LibraryStage()
                }
                .arrangementViewStyle(.split)
            } else {
                LibraryShelf()
            }
        }
        .background(Color.ink0)
        .navigationTitle("Library")
        .toolbarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarPinnedTrailing) {
                Button { model.addSheetOpen = true } label: { Label("Add game", systemImage: "plus") }
                    .disabled(model.addSheetOpen)
            }
            ToolbarItem(placement: .secondaryAction) {
                Button { model.settingsOpen = true } label: { Label("Settings", systemImage: "gearshape") }
            }
        }
    }
}

/// The stage beside or above the shelf when folded: key art and title. In tabletop it is view
/// only (G-4); on the book's left page it also offers Continue (B-6).
struct LibraryStage: View {
    @Environment(AppModel.self) private var model
    @Environment(\.duo) private var duo

    var body: some View {
        let game = model.featuredGame
        ZStack(alignment: .bottomLeading) {
            ArtView(asset: game?.keyArtAsset, game: game, drift: true)
            LinearGradient(colors: [.clear, .black.opacity(0.75)], startPoint: .center, endPoint: .bottom)
            VStack(alignment: .leading, spacing: 8) {
                Wordmark()
                if let game {
                    Text(game.name).font(PlayscribeFont.title2.bold()).lineLimit(3)
                    if let c = model.continueItem, c.game.id == game.id {
                        Text("New on PS5: \(c.release.displayName)").font(PlayscribeFont.subheadline).foregroundStyle(.secondary)
                        if duo.pose == .book {
                            Button("Continue reading") { model.openGame(c.game.id, chapter: .updates, releaseID: c.release.id) }
                                .buttonStyle(.borderedProminent).foregroundStyle(PlayscribeColor.onAccent)
                                .hitTarget()
                                .tappableFrame()
                        }
                    }
                }
            }
            .padding(20)
        }
        .allowsHitTesting(duo.pose != .tabletop)
        .accessibilityElement(children: .contain)
    }
}

struct LibraryShelf: View {
    @Environment(AppModel.self) private var model
    @Environment(\.duo) private var duo
    @Environment(\.railWidth) private var railWidth
    @Environment(\.dynamicTypeSize) private var typeSize

    /// B-1: one fixed cover size per pose.
    private var tileSize: CGFloat {
        switch duo.pose {
        case .closed: 44
        case .flat: 112
        case .book: 100
        case .tabletop: 84
        }
    }

    var body: some View {
        @Bindable var model = model
        let rows = model.shownRows()
        let all = model.libraryRows
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 12) {
                if !duo.isFolded, duo.pose != .closed, let featured = model.featuredGame {
                    FeatureBanner(game: featured)
                }
                if let line = model.feedStatusLine {
                    HStack {
                        Text(line).font(PlayscribeFont.footnote).foregroundStyle(.secondary)
                        if case .failed = model.feedStatus {
                            Button("Retry") { Task { await model.refreshFeed() } }.font(PlayscribeFont.footnote).hitTarget()
                        }
                    }
                }
                if model.showsNotificationCard, let first = all.first {
                    NotificationInviteCard(gameName: first.game.name)
                }
                if all.count >= 6 {
                    TextField("Search your library", text: $model.data.nav.query)
                        .textFieldStyle(.roundedBorder)
                        .submitLabel(.search)
                        .frame(minHeight: 44)
                }
                if all.count >= 2 { FilterBar() }

                if rows.isEmpty {
                    VStack(spacing: 12) {
                        Text("No \(model.nav.filter == .all ? "" : model.nav.filter.label.lowercased() + " ")games").font(PlayscribeFont.headline)
                        Button("Show all") { model.nav.filter = .all; model.nav.query = "" }.hitTarget()
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 40)
                }

                if duo.pose == .closed {
                    if let c = model.continueItem { ContinueRow(game: c.game, release: c.release) }
                    ForEach(rows) { row in
                        GameRow(row: row).id("lib-\(row.id)")
                    }
                } else {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: tileSize, maximum: tileSize), spacing: 14, alignment: .top)],
                              alignment: .leading, spacing: 16) {
                        if let c = model.continueItem {
                            ContinueTile(game: c.game, release: c.release, size: tileSize)
                        }
                        ForEach(rows) { row in
                            GameTile(row: row, size: tileSize).id("lib-\(row.id)")
                        }
                    }
                }
            }
            .scrollTargetLayout()
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .padding(.trailing, railWidth)
        }
        .scrollPosition(id: Binding(get: { model.nav.anchors["library"] }, set: { model.nav.anchors["library"] = $0 }), anchor: .top)
        .contentMargins(.bottom, model.pill == nil && model.toast == nil ? 0 : 72, for: .scrollContent)
        .refreshable { await model.refreshFeed() }
    }
}

struct FilterBar: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        let rows = model.libraryRows
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(LibraryFilter.allCases) { f in
                    let n = f.status.map { s in rows.filter { $0.status == s }.count } ?? rows.count
                    let on = model.nav.filter == f
                    Button { model.nav.filter = f } label: {
                        Text("\(f.label) \(n)")
                            .font(PlayscribeFont.subheadline.weight(on ? .semibold : .regular))
                            .padding(.horizontal, 12)
                            .frame(minHeight: 44)
                            .background(on ? Color.accentColor.opacity(0.22) : Color.ink3, in: Capsule())
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(on ? .isSelected : [])
                    .tappableFrame()
                }
                Menu {
                    Picker("Sort by", selection: Binding(get: { model.nav.sort }, set: { model.nav.sort = $0 })) {
                        ForEach(LibrarySort.allCases) { Text($0.label).tag($0) }
                    }
                } label: {
                    Label(model.nav.sort.label, systemImage: "arrow.up.arrow.down")
                        .font(PlayscribeFont.subheadline)
                        .padding(.horizontal, 12)
                        .frame(minHeight: 44)
                        .background(Color.ink3, in: Capsule())
                }
                .tappableFrame()
            }
            .padding(.trailing, 24)
        }
        .edgeFade()
    }
}

extension View {
    /// R-7: a scrolling chip row fades at its edges instead of clipping hard.
    func edgeFade(_ width: CGFloat = 24) -> some View {
        mask {
            HStack(spacing: 0) {
                LinearGradient(colors: [.clear, .black], startPoint: .leading, endPoint: .trailing).frame(width: 8)
                Rectangle()
                LinearGradient(colors: [.black, .clear], startPoint: .leading, endPoint: .trailing).frame(width: width)
            }
        }
    }
}

/// B-4 on the closed display: the Continue game's key art leads the list, full-bleed, with the
/// hero badge (brand README, "Splash and closed Library hero"). Tapping the art opens the book.
struct ContinueRow: View {
    @Environment(AppModel.self) private var model
    var game: CatalogGame
    var release: Release

    var body: some View {
        Button { model.openGame(game.id, chapter: .updates, releaseID: release.id) } label: {
            ZStack(alignment: .bottomLeading) {
                ArtView(asset: game.keyArtAsset, game: game)
                LinearGradient(colors: [.clear, .black.opacity(0.8)], startPoint: .top, endPoint: .bottom)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Continue").font(PlayscribeFont.caption.weight(.semibold)).foregroundStyle(PlayscribeColor.accent)
                    Text(release.displayName).font(PlayscribeFont.headline)
                    Text(game.name).font(PlayscribeFont.footnote).foregroundStyle(.secondary).lineLimit(1)
                }
                .padding(.leading, 14)
                .padding(.bottom, 12 + 40 + 10)
                HeroBadge()
                    .padding(.leading, 14)
                    .padding(.bottom, 12)
            }
            .frame(height: 176)
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
        .buttonStyle(.plain)
        .tappableFrame()
        .accessibilityLabel("Continue: \(game.name), \(release.displayName)")
    }
}

/// The glass badge on the closed Library hero: mark and wordmark for 2 s the first time it
/// appears each launch, then the mark alone. Decorative, so hidden from accessibility.
struct HeroBadge: View {
    private static var shownThisLaunch = false
    @State private var open = !HeroBadge.shownThisLaunch
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        HStack(spacing: 6) {
            BrandMark(size: 24)
            if open {
                Text(Brand.name).font(PlayscribeFont.subheadline.weight(.semibold))
                    .transition(.opacity.combined(with: .move(edge: .leading)))
            }
        }
        .padding(.horizontal, 10)
        .frame(height: 40)
        .glassEffect(.regular, in: Capsule())
        .accessibilityHidden(true)
        .task {
            guard open else { return }
            HeroBadge.shownThisLaunch = true
            try? await Task.sleep(for: .seconds(2))
            withAnimation(reduceMotion ? .easeOut(duration: 0.2) : .spring(response: 0.35, dampingFraction: 0.85)) { open = false }
        }
    }
}

/// Closed display row (B-1): 44 pt cover, name up to two lines, status, latest On PS5 release, unread count.
struct GameRow: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dynamicTypeSize) private var typeSize
    var row: AppModel.LibraryRow

    var body: some View {
        let stacked = typeSize.isAccessibilitySize
        HStack(spacing: 0) {
            Button { model.openGame(row.id) } label: {
                let layout = stacked ? AnyLayout(VStackLayout(alignment: .leading, spacing: 8)) : AnyLayout(HStackLayout(spacing: 12))
                layout {
                    CoverView(game: row.game, cornerRadius: 6).frame(width: 44)
                    VStack(alignment: .leading, spacing: 4) {
                        Text(row.game.name).font(PlayscribeFont.headline).lineLimit(stacked ? nil : 2).multilineTextAlignment(.leading)
                        HStack(spacing: 6) {
                            StatusPill(status: row.status)
                            if let r = row.latest {
                                Text("\(r.displayName) · \(r.ps5Date.dayMonth)").font(PlayscribeFont.footnote).foregroundStyle(.secondary)
                            } else {
                                Text("No PS5 notes yet").font(PlayscribeFont.footnote).foregroundStyle(.secondary)
                            }
                        }
                    }
                    if !stacked { Spacer(minLength: 0) }
                    if row.unread > 0 { UnreadBadge(count: row.unread) }
                }
                .padding(.vertical, 6)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .tappableFrame()
            .background(model.highlight == row.id ? Color.accentColor.opacity(0.15) : .clear)
            GameMenuButton(gameID: row.id)
        }
        .accessibilityElement(children: .contain)
        .task(id: model.highlight) { await clearHighlight() }
    }

    private func clearHighlight() async {
        guard model.highlight == row.id else { return }
        try? await Task.sleep(for: .seconds(1))
        model.highlight = nil
    }
}

struct UnreadBadge: View {
    var count: Int
    var body: some View {
        Text("\(count)")
            .font(PlayscribeFont.caption2.bold())
            .monospacedDigit()
            .padding(.horizontal, 6)
            .frame(minWidth: 20, minHeight: 20)
            .background(Color.accentColor, in: Capsule())
            .foregroundStyle(.white)
            .accessibilityLabel("\(count) unread")
    }
}

struct GameMenuButton: View {
    @Environment(AppModel.self) private var model
    var gameID: String
    var body: some View {
        Menu { ActionMenuContent(sections: model.statusMenu(gameID)) } label: {
            Image(systemName: "ellipsis").frame(width: 44, height: 44).contentShape(Rectangle())
        }
        .accessibilityLabel("Options for \(model.game(gameID)?.name ?? "game")")
        .tappableFrame()
    }
}

/// Inner display tile: a fixed-size cover, name, a status dot and the unread count.
struct GameTile: View {
    @Environment(AppModel.self) private var model
    var row: AppModel.LibraryRow
    var size: CGFloat

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Button { model.openGame(row.id) } label: {
                CoverView(game: row.game)
                    .frame(width: size)
                    .overlay(alignment: .topTrailing) {
                        if row.unread > 0 { UnreadBadge(count: row.unread).padding(4) }
                    }
            }
            .buttonStyle(.plain)
            .tappableFrame()
            Text(row.game.name).font(PlayscribeFont.footnote.weight(.semibold)).lineLimit(2)
            HStack(spacing: 4) {
                Circle().fill(row.status.tint).frame(width: 6, height: 6)
                Text(row.latest?.displayName ?? "No PS5 notes yet").font(PlayscribeFont.caption2).foregroundStyle(.secondary).lineLimit(1)
                Spacer(minLength: 0)
            }
            .overlay(alignment: .trailing) { GameMenuButton(gameID: row.id).offset(x: 12) }
        }
        .frame(width: size)
        .background(model.highlight == row.id ? Color.accentColor.opacity(0.15) : .clear)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("\(row.game.name), \(row.status.label)\(row.unread > 0 ? ", \(row.unread) unread" : "")")
    }
}

/// B-4: the game with the most recent unread On PS5 release, first in the grid, with key art.
struct ContinueTile: View {
    @Environment(AppModel.self) private var model
    var game: CatalogGame
    var release: Release
    var size: CGFloat

    var body: some View {
        Button { model.openGame(game.id, chapter: .updates, releaseID: release.id) } label: {
            VStack(alignment: .leading, spacing: 6) {
                ArtView(asset: game.keyArtAsset, game: game)
                    .frame(width: size, height: size * 4 / 3)
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                    .overlay(alignment: .bottomLeading) {
                        Text("Continue").font(PlayscribeFont.caption2.bold()).padding(6)
                            .background(.ultraThinMaterial, in: Capsule()).padding(6)
                    }
                Text(release.displayName).font(PlayscribeFont.footnote.weight(.semibold)).lineLimit(2)
                Text(game.name).font(PlayscribeFont.caption2).foregroundStyle(.secondary).lineLimit(1)
            }
            .frame(width: size)
        }
        .buttonStyle(.plain)
        .tappableFrame()
        .accessibilityLabel("Continue: \(game.name), \(release.displayName)")
    }
}

/// The open-flat banner: the featured game's art with the wordmark, so it reads as the app.
struct FeatureBanner: View {
    @Environment(AppModel.self) private var model
    var game: CatalogGame
    var body: some View {
        ZStack(alignment: .bottomLeading) {
            ArtView(asset: game.keyArtAsset, game: game)
            LinearGradient(colors: [.clear, .black.opacity(0.7)], startPoint: .top, endPoint: .bottom)
            VStack(alignment: .leading, spacing: 4) {
                Wordmark()
                Text(game.name).font(PlayscribeFont.title3.bold())
            }
            .padding(16)
        }
        .frame(height: 160)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .accessibilityElement(children: .combine)
    }
}

/// N-1: asked in context after the first game is added. One Continue button, swipe to dismiss.
struct NotificationInviteCard: View {
    @Environment(AppModel.self) private var model
    var gameName: String
    @State private var counted = false

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "bell.badge").font(PlayscribeFont.title2).foregroundStyle(Color.accentColor)
            VStack(alignment: .leading, spacing: 8) {
                Text("Get a note when \(gameName) updates on PS5").font(PlayscribeFont.headline)
                Button("Continue") {
                    model.data.notificationCardDismissed = true
                    Task { await NotificationService.shared.requestAuthorization() }
                }
                .buttonStyle(.borderedProminent).foregroundStyle(PlayscribeColor.onAccent)
                .hitTarget()
                .tappableFrame()
            }
            Spacer(minLength: 0)
        }
        .padding(16)
        .background(Color.ink2, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .gesture(DragGesture(minimumDistance: 30).onEnded { v in
            if abs(v.translation.width) > 60 { model.data.notificationCardDismissed = true }
        })
        .accessibilityAction(named: "Dismiss") { model.data.notificationCardDismissed = true }
        .onAppear {
            guard !counted else { return }
            counted = true
            model.data.notificationCardShows += 1
        }
    }
}

/// Open landscape sidebar (G-1).
struct LibrarySidebar: View {
    @Environment(AppModel.self) private var model
    var body: some View {
        List(selection: Binding(get: { model.nav.gameID }, set: { if let id = $0 { model.openGame(id) } })) {
            ForEach(model.shownRows()) { row in
                HStack(spacing: 12) {
                    CoverView(game: row.game, cornerRadius: 4).frame(width: 36)
                    VStack(alignment: .leading) {
                        Text(row.game.name).font(PlayscribeFont.subheadline.weight(.semibold)).lineLimit(2)
                        Text(row.latest?.displayName ?? "No PS5 notes yet").font(PlayscribeFont.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                    if row.unread > 0 { UnreadBadge(count: row.unread) }
                }
                .tag(row.id)
            }
        }
        .navigationTitle("Library")
        .toolbar {
            ToolbarItem(placement: .topBarPinnedTrailing) {
                Button { model.addSheetOpen = true } label: { Label("Add game", systemImage: "plus") }
            }
        }
    }
}
