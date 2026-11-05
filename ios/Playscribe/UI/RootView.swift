import SwiftUI

/// Width the tabletop rail takes from the lower half's trailing edge.
private struct RailWidthKey: EnvironmentKey { static let defaultValue: CGFloat = 0 }
extension EnvironmentValues {
    var railWidth: CGFloat {
        get { self[RailWidthKey.self] }
        set { self[RailWidthKey.self] = newValue }
    }
}

/// Tabletop: a sheet's controls must sit in the lower half (the upper half is view only), so
/// sheets there are this panel, bottom-aligned under the division, instead of a presented sheet.
private struct PanelCloseKey: EnvironmentKey { static let defaultValue: (() -> Void)? = nil }
extension EnvironmentValues {
    var panelClose: (() -> Void)? {
        get { self[PanelCloseKey.self] }
        set { self[PanelCloseKey.self] = newValue }
    }
}

struct LowerHalfPanel: View {
    @Environment(AppModel.self) private var model
    var duo: DuoContext
    var fold: CGRect

    private var open: Bool { model.addSheetOpen || model.settingsOpen || model.trailer != nil || model.linksSheetOpen || model.tagExplainer != nil }

    var body: some View {
        if open {
            let height = max(0, duo.size.height - fold.maxY)
            ZStack(alignment: .bottom) {
                // The stage above stays view only: a dimmer that takes no touches.
                Color.black.opacity(0.4).ignoresSafeArea().allowsHitTesting(false)
                Group {
                    if model.addSheetOpen { AddGameSheet() }
                    else if model.settingsOpen { SettingsView() }
                    else if let t = model.trailer { TrailerView(videoID: t.videoID, name: t.name) }
                    else if model.linksSheetOpen, let id = model.nav.gameID { LinksSheet(gameID: id) }
                    else if let k = model.tagExplainer { VerificationExplainer(kind: k) }
                }
                .environment(\.panelClose, { model.addSheetOpen = false; model.settingsOpen = false; model.trailer = nil; model.linksSheetOpen = false; model.tagExplainer = nil })
                .environment(\.railWidth, 0)
                .frame(width: duo.size.width, height: height)
                .background(Color.ink0)
                .clipShape(UnevenRoundedRectangle(topLeadingRadius: 20, topTrailingRadius: 20))
                .accessibilityAddTraits(.isModal)
            }
            .transition(.move(edge: .bottom))
            .zIndex(5)
        }
    }
}

struct RootView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// T-2: one spring for every pose change; T-4: a short cross-fade under Reduce Motion.
    private var poseAnimation: Animation {
        reduceMotion ? .easeInOut(duration: 0.2) : .spring(duration: 0.45, bounce: 0.12)
    }
    @AppStorage("didShowSplash") private var didShowSplash = false
    @State private var splashVisible = false
    @State private var frames: [CGRect] = []

    var body: some View {
        DuoReader { duo in
            let _ = { model.livePose = duo.pose }()
            ZStack {
                TabRoot(duo: duo)
                    .environment(\.railWidth, duo.pose == .tabletop ? TabletopRail.width : 0)
                    .auditActive(!model.addSheetOpen && !model.settingsOpen && !model.linksSheetOpen && model.tagExplainer == nil && model.player == nil)

                if duo.pose == .tabletop, let fold = duo.division {
                    TabletopRail(duo: duo)
                        .auditActive(!model.addSheetOpen && !model.settingsOpen && !model.linksSheetOpen && model.tagExplainer == nil && model.player == nil)
                        .frame(width: TabletopRail.width, height: max(0, duo.size.height - fold.maxY))
                        .position(x: duo.size.width - TabletopRail.width / 2, y: fold.maxY + (duo.size.height - fold.maxY) / 2)
                }

                LowerMessages(duo: duo)

                if duo.pose == .tabletop, let fold = duo.division { LowerHalfPanel(duo: duo, fold: fold) }

                if splashVisible {
                    SplashView(duo: duo) { splashVisible = false }
                        .transition(.opacity)
                        .zIndex(10)
                }
            }
            .animation(poseAnimation, value: duo.pose)
            .environment(\.qaSolid, BuildChannel.showsInternalTools && UserDefaults.standard.bool(forKey: "qaReduceTransparency"))
            .onPreferenceChange(TappableFrameKey.self) { frames = $0 }
            .overlay {
                if model.showDebugOverlay { DebugOverlay(frames: frames, duo: duo) }
                #if INTERNAL
                FoldAudit(frames: frames, duo: duo)
                #endif
            }
        }
        .background(Color.ink0)
        .onAppear {
            // §2: the branded splash plays only on the first launch, never from a notification (L-3).
            // Terry, 2 Nov: every cold launch, not only the first.
            if !NotificationService.shared.launchedFromNotification {
                splashVisible = true
                didShowSplash = true
            }
        }
        .onChange(of: NotificationService.shared.launchedFromNotification) { _, fromNotification in
            if fromNotification { splashVisible = false }
        }
        .sheet(isPresented: Binding(get: { model.addSheetOpen && model.livePose != .tabletop }, set: { if !$0 && model.livePose != .tabletop { model.addSheetOpen = false } })) {
            AddGameSheet()
        }
        .sheet(isPresented: Binding(get: { model.settingsOpen && model.livePose != .tabletop }, set: { if !$0 && model.livePose != .tabletop { model.settingsOpen = false } })) {
            SettingsView()
        }
        .sheet(item: Binding(get: { model.livePose == .tabletop ? nil : model.tagExplainer }, set: { if $0 == nil && model.livePose != .tabletop { model.tagExplainer = nil } })) { kind in
            VerificationExplainer(kind: kind).presentationDetents([.medium])
        }
        .fullScreenCover(isPresented: Binding(get: { model.player != nil }, set: { if !$0 { model.player = nil } })) {
            if let p = model.player { PlayerView(gameID: p.gameID, releaseID: p.releaseID) }
        }
        .fullScreenCover(isPresented: Binding(get: { model.trailer != nil && model.livePose != .tabletop }, set: { if !$0 && model.livePose != .tabletop { model.trailer = nil } })) {
            if let t = model.trailer { TrailerView(videoID: t.videoID, name: t.name) }
        }
    }
}

struct TabRoot: View {
    @Environment(AppModel.self) private var model
    var duo: DuoContext

    var body: some View {
        @Bindable var model = model
        TabView(selection: $model.data.nav.tab) {
            Tab("Library", systemImage: "books.vertical", value: AppTab.library) {
                LibraryRoot(duo: duo).auditActive(model.nav.tab == .library)
            }
            .badge(model.totalUnread)

            Tab("Updates", systemImage: "newspaper", value: AppTab.updates) {
                NavigationStack { UpdatesView().tabletopChrome(duo) }.auditActive(model.nav.tab == .updates)
            }

            Tab(value: AppTab.search, role: .search) {
                NavigationStack { SearchView().tabletopChrome(duo) }.auditActive(model.nav.tab == .search)
            }
        }
        .onChange(of: model.data.nav.tab) { old, new in if new == .search && old != .search { model.searchReturnTab = old } }
    }
}

extension View {
    /// Tabletop: the system's horizontal bars would put controls in the upper half, so they are
    /// hidden and the lower rail carries them instead (G-4).
    /// Apply to each screen inside a navigation stack: bar visibility is read from the visible
    /// screen, not from the stack or the TabView.
    func tabletopChrome(_ duo: DuoContext) -> some View {
        toolbarVisibility(duo.pose == .tabletop ? .hidden : .automatic, for: .navigationBar, .tabBar)
    }
}

/// D-1: one navigation in every pose: the Library, then the game book, in one stack. No split
/// view, no sidebar; Back (top of the rail) returns to the Library everywhere.
struct LibraryRoot: View {
    @Environment(AppModel.self) private var model
    var duo: DuoContext

    var body: some View {
        NavigationStack(path: Binding(
            get: { (model.nav.gameID.map { [$0] } ?? []) + (model.nav.gameID != nil ? model.nav.detailReleaseID.map { ["release:" + $0] } ?? [] : []) },
            set: { path in
                model.nav.gameID = path.first
                model.nav.detailReleaseID = path.count > 1 ? String(path[1].dropFirst("release:".count)) : nil
            }
        )) {
            LibraryView()
                .auditActive(model.nav.gameID == nil)
                .tabletopChrome(duo)
                .navigationDestination(for: String.self) { id in
                    if id.hasPrefix("release:"), let gameID = model.nav.gameID {
                        ReleaseDetailView(gameID: gameID, releaseID: String(id.dropFirst("release:".count))).tabletopChrome(duo)
                    } else {
                        GameBookView(gameID: id).tabletopChrome(duo).auditActive(model.nav.detailReleaseID == nil)
                    }
                }
        }
        // J-1: a pushed release only exists where pushing is the layout (Closed, open portrait).
        // Unfolding to side by side or Tabletop pops it; the Page already shows it, because the
        // push selected it. Here, not in the game book, which is hidden under the push.
        .onChange(of: duo.pose != .closed && (duo.isLandscape || duo.pose == .tabletop), initial: true) { _, onPage in
            if onPage { model.nav.detailReleaseID = nil }
        }
    }
}

/// Tabletop's lower trailing rail: Back first, then the screen's actions, then the tabs.
struct TabletopRail: View {
    static let width: CGFloat = 56
    @Environment(AppModel.self) private var model
    var duo: DuoContext

    var body: some View {
        VStack(spacing: 4) {
            // The screen's controls scroll when they outgrow the lower half (a centred overflow pushed the first
            // button above the fold, 468 vs 474.5: G-4); the tabs stay pinned below.
            ScrollView {
              VStack(spacing: 4) {
            if let id = model.nav.gameID, model.nav.tab == .library {
                RailButton(action: ScreenAction(id: "back", title: "Library", systemImage: "chevron.backward",
                                                kind: .button { model.closeGame() }))
                ForEach(model.gameActions(id)) { RailButton(action: $0) }
                if LinksSheet.hasLinks(model, id) {
                    RailButton(action: ScreenAction(id: "links", title: "Links", systemImage: "link", kind: .button { model.linksSheetOpen = true }))
                        .accessibilityLabel("Links, opens a list")
                }
                // Share the open update as a card (lower rail, 44 pt target; TT-0).
                if let r = model.readerRelease(id), r.isPS5Listed { ShareUpdateButton(release: r) }
            } else if model.nav.tab == .search {
                // Search is a dead end without this: Back to where it was opened from (Terry, 0.2.0 build 5).
                RailButton(action: ScreenAction(id: "back", title: "Back", systemImage: "chevron.backward",
                                                kind: .button { model.leaveSearch() }))
            } else if model.nav.tab == .library {
                if !model.addSheetOpen {
                    RailButton(action: ScreenAction(id: "add", title: "Add game", systemImage: "plus", kind: .button { model.addSheetOpen = true }))
                }
                // D-12: the View menu under Add.
                if !model.data.collection.isEmpty {
                    LibraryViewMenu()
                        .labelStyle(.iconOnly)
                        .font(PlayscribeFont.title3)
                        .frame(width: 48, height: 48)
                        .tappableFrame()
                }
                // Settings has its own cog on the rail, not inside the View menu (Terry, 0.2.0 build 5).
                RailButton(action: ScreenAction(id: "settings", title: "Settings", systemImage: "gearshape", kind: .button { model.settingsOpen = true }))
                    .accessibilityIdentifier("settingsButton")
                // 0.5.0: Playing and Upcoming on the rail (Tabletop's lower half), not above the fold.
                if !model.data.collection.isEmpty {
                    RailButton(action: ScreenAction(id: "playing", title: "Playing",
                                                    systemImage: model.libraryTab == .playing ? "gamecontroller.fill" : "gamecontroller",
                                                    kind: .button { model.libraryTab = .playing }, selected: model.libraryTab == .playing))
                        .accessibilityAddTraits(model.libraryTab == .playing ? .isSelected : [])
                        .accessibilityIdentifier("playingRail")
                    RailButton(action: ScreenAction(id: "upcoming", title: "Upcoming",
                                                    systemImage: model.libraryTab == .upcoming ? "calendar.badge.clock" : "calendar",
                                                    kind: .button { model.libraryTab = .upcoming }, selected: model.libraryTab == .upcoming))
                        .accessibilityAddTraits(model.libraryTab == .upcoming ? .isSelected : [])
                        .accessibilityIdentifier("upcomingRail")
                }
            }
              }
            }
            .scrollBounceBehavior(.basedOnSize)
            .scrollIndicators(.hidden)
            Divider().frame(width: 28)
            tab(.library, "Library", "books.vertical", badge: model.totalUnread)
            tab(.updates, "Updates", "newspaper")
            tab(.search, "Search", "magnifyingglass")
        }
        .padding(.vertical, 8)
        .frame(maxHeight: .infinity)
        .background(.bar)
    }

    private func tab(_ t: AppTab, _ title: String, _ symbol: String, badge: Int = 0) -> some View {
        Button {
            model.nav.tab = t
        } label: {
            Image(systemName: symbol)
                .font(PlayscribeFont.title3)
                .symbolVariant(model.nav.tab == t ? .fill : .none)
                .foregroundStyle(model.nav.tab == t ? PlayscribeColor.accent : .secondary)
                .frame(width: 48, height: 48)
                // The same selected treatment as the rail's action buttons (RailButton), so the rail reads as one style.
                .background(Circle().fill(PlayscribeColor.accent.opacity(model.nav.tab == t ? 0.18 : 0)))
                .overlay(alignment: .topTrailing) {
                    if badge > 0 {
                        Text("\(badge)").font(PlayscribeFont.caption2.bold()).padding(.horizontal, 4)
                            .background(Color.red, in: Capsule()).foregroundStyle(.white)
                    }
                }
                .contentShape(Rectangle())
        }
        .buttonStyle(RailPressStyle())
        .buttonStyle(RailPressStyle())
        .accessibilityLabel(title)
        .accessibilityValue(badge > 0 ? "\(badge) unread" : "")
        .accessibilityAddTraits(model.nav.tab == t ? .isSelected : [])
        .tappableFrame()
    }
}

/// The "New on PS5" pill (N-7) and toasts with Undo (B-8), above the tab bar or in the lower half.
struct LowerMessages: View {
    @Environment(AppModel.self) private var model
    var duo: DuoContext

    var body: some View {
        VStack(spacing: 8) {
            Spacer()
            if let pill = model.pill, let game = model.game(pill.gameID), let r = model.release(pill.gameID, pill.releaseID) {
                Button {
                    model.openRelease(gameID: pill.gameID, releaseID: pill.releaseID)
                } label: {
                    HStack(spacing: 8) {
                        UnreadDot()
                        Text("New on PS5: \(game.name) \(r.displayName)")
                            .font(PlayscribeFont.subheadline.weight(.semibold))
                            .lineLimit(2)
                        Image(systemName: "chevron.forward").font(PlayscribeFont.caption)
                    }
                    .padding(.horizontal, 16)
                    .frame(minHeight: 44)
                    // A solid pill: nothing shows through it (Iris, 6589abf: it ghosted over the date pills).
                    .background(Capsule().fill(PlayscribeColor.ink700))
                    .adaptiveGlass(in: Capsule(), interactive: true)
                }
                .buttonStyle(.plain)
                .tappableFrame()
                .accessibilityIdentifier("newOnPS5Pill")
                .highPriorityGesture(DragGesture(minimumDistance: 20).onEnded { _ in model.pill = nil })
                .accessibilityAction(named: "Dismiss") { model.pill = nil }
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }
            if let toast = model.toast {
                HStack(spacing: 12) {
                    // Wraps to two lines at large sizes instead of shrinking (Iris, AX3).
                    Text(toast.text).font(PlayscribeFont.subheadline).lineLimit(2).fixedSize(horizontal: false, vertical: true)
                    if let undo = toast.undo {
                        Button(toast.actionLabel) { undo(); model.toastClear() }
                            .font(PlayscribeFont.subheadline.weight(.semibold))
                            .hitTarget()
                            .tappableFrame()
                    }
                }
                .padding(.horizontal, 16)
                .frame(minHeight: 44)
                .background(PlayscribeColor.ink700, in: Capsule())
                .overlay(Capsule().strokeBorder(PlayscribeColor.vellum300.opacity(0.2)))
                .shadow(color: .black.opacity(0.5), radius: 12, y: 4)
                // Clear of the rows' trailing menu buttons.
                .padding(.trailing, duo.pose == .closed ? 56 : 0)
                .frame(maxWidth: .infinity, alignment: .leading)
                .transition(.opacity)
                .accessibilityElement(children: .combine)
                .accessibilityActions {
                    if let undo = toast.undo { Button(toast.actionLabel) { undo(); model.toastClear() } }
                    Button("Dismiss") { model.toastClear() }
                }
            }
        }
        // Above the bottom tab bar only where the bars are horizontal (open portrait).
        .padding(.bottom, duo.pose == .flat && !duo.isLandscape ? 96 : 16)
        .padding(.trailing, duo.pose == .tabletop ? TabletopRail.width : 0)
        .padding(.horizontal, 16)
        // Book: the pill and toasts stay on the left page; they never straddle the fold.
        .frame(maxWidth: duo.pose == .book ? max(0, (duo.division?.minX ?? 0) - 8) : .infinity)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .animation(.snappy, value: model.toast)
        .animation(.snappy, value: model.pill?.releaseID)
    }
}
