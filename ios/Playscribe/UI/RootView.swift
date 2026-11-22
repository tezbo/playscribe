import SwiftUI

/// Width the tabletop rail takes from the lower half's trailing edge.
private struct RailWidthKey: EnvironmentKey { static let defaultValue: CGFloat = 0 }
extension EnvironmentValues {
    var railWidth: CGFloat {
        get { self[RailWidthKey.self] }
        set { self[RailWidthKey.self] = newValue }
    }
}

/// Tabletop: run before any rail button's own action, so a rail tap closes an open lower-half panel and then does what the
/// button says (Iris, #556 at 894ee2c3, J-20). Nil elsewhere.
private struct RailPreActionKey: EnvironmentKey { static let defaultValue: (() -> Void)? = nil }
extension EnvironmentValues {
    var railPreAction: (() -> Void)? {
        get { self[RailPreActionKey.self] }
        set { self[RailPreActionKey.self] = newValue }
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

/// Book: Settings is a panel on the left page, not a system sheet, so its edge never runs into the hinge band
/// (Quinn, 6b01082; no chrome on the hinge). The right page is dimmed and takes no touches.
struct BookPagePanel: View {
    @Environment(AppModel.self) private var model
    var duo: DuoContext
    var fold: CGRect

    var body: some View {
        if model.settingsOpen {
            ZStack(alignment: .leading) {
                Color.black.opacity(0.4).ignoresSafeArea()
                SettingsView()
                    .environment(\.panelClose, { model.settingsOpen = false })
                    .environment(\.railWidth, 0)
                    .frame(width: max(0, fold.minX), height: duo.size.height)
                    .background(PlayscribeRole.bg)
                    .clipShape(UnevenRoundedRectangle(bottomTrailingRadius: 20, topTrailingRadius: 20))
                    .accessibilityAddTraits(.isModal)
            }
            .transition(.move(edge: .leading))
            .zIndex(5)
        }
    }
}

/// Open (landscape) and Book: the Add sheet is a panel on the right page, one page's column wide less 24 pt clear of
/// the hinge, never a system sheet that runs across it. The left page is dimmed and takes no touches.
struct RightPagePanel: View {
    @Environment(AppModel.self) private var model
    var duo: DuoContext

    /// The container the pose is read from (`duo.size`) stops at the trailing rail; the window runs on 84 pt or so past it.
    /// Both edges below are in container coordinates. Leading edge: 24 pt right of the division in Book; in Open, which has
    /// none, 24 pt right of the hinge, the centre of the whole window (container plus rail), not of the container.
    /// Trailing edge: 16 pt clear of the rail. Container-based throughout, no device checks (Iris, #306).
    private var trailingInset: CGFloat { duo.safeArea.trailing + 16 }
    private var leadingEdge: CGFloat {
        if let d = duo.division { return d.maxX + 24 }
        return (duo.size.width + duo.safeArea.leading + duo.safeArea.trailing) / 2 + 24
    }
    private var panelWidth: CGFloat { duo.size.width - 16 - leadingEdge }

    var body: some View {
        if model.addSheetOpen && !model.addIsSystemSheet {
            ZStack(alignment: .trailing) {
                Color.black.opacity(0.4).ignoresSafeArea()
                AddGameSheet()
                    .environment(\.panelClose, { model.addSheetOpen = false })
                    .environment(\.railWidth, 0)
                    .frame(width: max(0, panelWidth), height: duo.size.height)
                    .background(PlayscribeRole.bg)
                    .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
                    .padding(.trailing, trailingInset)
                    .accessibilityAddTraits(.isModal)
            }
            // The panel is placed against the whole container, not the safe area: the trailing rail's inset is applied
            // once, by hand, so it is not counted twice (the sheet sat about 84 pt too far left, over the hinge).
            .ignoresSafeArea(.container)
            .transition(.move(edge: .trailing))
            .zIndex(5)
        }
    }
}

struct LowerHalfPanel: View {
    @Environment(AppModel.self) private var model
    var duo: DuoContext
    var fold: CGRect

    private var open: Bool { model.addSheetOpen || model.settingsOpen || model.linksSheetOpen || model.tagExplainer != nil || model.keepCurrentDetailsOpen }

    var body: some View {
        if open {
            let height = max(0, duo.size.height - fold.maxY)
            // Beside the rail, never under it (Mac at 86a4b104: Settings rows ran to x 649 under the rail at 619 to 663, so a tap
            // on the Video lab switch hit the rail's Library button). The rail stays visible and works while a panel is open.
            let width = max(0, duo.size.width - TabletopRail.width)
            ZStack(alignment: .bottomLeading) {
                // The stage above stays view only: a dimmer that takes no touches.
                Color.black.opacity(0.4).ignoresSafeArea().allowsHitTesting(false)
                Group {
                    if model.addSheetOpen { AddGameSheet() }
                    else if model.settingsOpen { SettingsView() }
                    else if model.linksSheetOpen, let id = model.nav.gameID { LinksSheet(gameID: id) }
                    else if let k = model.tagExplainer { VerificationExplainer(kind: k) }
                    else if model.keepCurrentDetailsOpen { KeepCurrentDetailsSheet() }
                }
                .environment(\.panelClose, { model.addSheetOpen = false; model.settingsOpen = false; model.trailer = nil; model.linksSheetOpen = false; model.tagExplainer = nil; model.keepCurrentDetailsOpen = false })
                .environment(\.railWidth, 0)
                .frame(width: width, height: height)
                // Solid through the bottom safe area too: the Library's tiles used to show, and take
                // taps, in the strip under the sheet.
                .background(PlayscribeRole.bg.ignoresSafeArea(edges: .bottom))
                .clipShape(UnevenRoundedRectangle(topLeadingRadius: 20, topTrailingRadius: 20))
                // Every touch inside the panel's frame is the panel's, never the page's beneath it.
                .contentShape(Rectangle())
                .accessibilityAddTraits(.isModal)
            }
            // The panel stops at the bottom safe area, so the Library's chips showed, and took taps,
            // in the strip below it. A solid filler hangs below the panel's bottom edge (outside the
            // clip) to cover it; the panel itself still starts exactly at the fold.
            .overlay(alignment: .bottomLeading) { PlayscribeRole.bg.frame(width: width, height: 120).offset(y: 120) }
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
    @State private var unlatchTask: Task<Void, Never>?
    @State private var frames: [CGRect] = []
    @State private var named: [String: CGRect] = [:]
    @State private var tourLane: CGRect?

    var body: some View {
        DuoReader { duo in
            let _ = { model.livePose = duo.pose; model.liveRightPage = duo.pose == .book || (duo.pose == .flat && duo.isLandscape) }()
            ZStack {
                TabRoot(duo: duo)
                    .environment(\.railWidth, duo.pose == .tabletop ? TabletopRail.width : 0)
                    .auditActive(!model.addSheetOpen && !model.settingsOpen && !model.linksSheetOpen && model.tagExplainer == nil && !model.keepCurrentDetailsOpen && model.player == nil)

                if duo.pose == .tabletop, let fold = duo.division {
                    TabletopRail(duo: duo)
                        .auditActive(!model.addSheetOpen && !model.settingsOpen && !model.linksSheetOpen && model.tagExplainer == nil && !model.keepCurrentDetailsOpen && model.player == nil)
                        .frame(width: TabletopRail.width, height: max(0, duo.size.height - fold.maxY))
                        .position(x: duo.size.width - TabletopRail.width / 2, y: fold.maxY + (duo.size.height - fold.maxY) / 2)
                }

                LowerMessages(duo: duo)

                if duo.pose == .tabletop, let fold = duo.division { LowerHalfPanel(duo: duo, fold: fold) }
                if duo.pose == .book, let fold = duo.division { BookPagePanel(duo: duo, fold: fold) }
                if duo.pose == .book || (duo.pose == .flat && duo.isLandscape) { RightPagePanel(duo: duo) }

                if splashVisible {
                    SplashView(duo: duo) { splashVisible = false }
                        .transition(.opacity)
                        .zIndex(10)
                }
            }
            .animation(poseAnimation, value: duo.pose)
            // More > Share (0.5.6 hotfix): half height, so in Tabletop the sheet stays in the lower half.
            .sheet(isPresented: Binding(get: { model.shareReleaseID != nil }, set: { if !$0 { model.shareReleaseID = nil } })) {
                if let gameID = model.nav.gameID, let id = model.shareReleaseID, let r = model.release(gameID, id) {
                    ShareActivitySheet(items: ([model.shareCardImage(for: r), model.shareText(r)] as [Any?]).compactMap { $0 })
                        .presentationDetents([.medium])
                }
            }
            // The sheet keeps its form while the launch pose settles, but a real change still switches it: folding into Book
            // at once, Open landscape once it has held for 10 s (the launch settling showed it for about 5 s).
            .onChange(of: duo.pose == .book) { _, book in
                if book && model.addSheetOpen { model.addIsSystemSheet = false }
            }
            .onChange(of: duo.pose == .flat && duo.isLandscape, initial: true) { _, wide in
                unlatchTask?.cancel()
                guard wide else { return }
                unlatchTask = Task { @MainActor in
                    try? await Task.sleep(for: .seconds(10))
                    // Not while the person has the keyboard up: moving the form rebuilds the sheet and drops the field's focus
                    // (probe log bc6bd42: the yield at 25.35 s was the focus loss; wanted was true). Wait until they put it away.
                    while !Task.isCancelled && model.addSheetOpen && model.addKeyboardWanted {
                        try? await Task.sleep(for: .seconds(1))
                    }
                    if !Task.isCancelled && model.addSheetOpen { model.addIsSystemSheet = false }
                }
            }
            .environment(\.qaSolid, BuildChannel.showsInternalTools && UserDefaults.standard.bool(forKey: "qaReduceTransparency"))
            .onPreferenceChange(TappableFrameKey.self) { frames = $0 }
            .onPreferenceChange(NamedFrameKey.self) { named = $0 }
            .onPreferenceChange(TourLaneKey.self) { tourLane = $0 }
            // 6b: the intro tour's ring and card, over everything but the splash; anchors report only while their step shows.
            .overlayPreferenceValue(TourAnchorKey.self) { anchors in
                if !splashVisible { TourOverlay(duo: duo, anchors: anchors, lane: tourLane) }
            }
            .overlay {
                if model.showDebugOverlay { DebugOverlay(frames: frames, duo: duo) }
                #if INTERNAL
                FoldAudit(frames: frames, duo: duo, named: named)
                Text("qa-response: \(NotificationService.shared.qaLastResponse ?? "none")")
                    .font(.system(size: 1)).opacity(0.01).accessibilityIdentifier("qaNotificationResponse")
                    .allowsHitTesting(false)
                Text("qa-schedule: \(NotificationService.shared.qaScheduleLog)")
                    .font(.system(size: 1)).opacity(0.01).accessibilityIdentifier("qaScheduleLog")
                    .allowsHitTesting(false)
                #endif
            }
        }
        .background(PlayscribeRole.bg)
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
        // 6b: a fresh install gets the welcome once the splash has gone; a step advances when the person does what it points at.
        .onChange(of: splashVisible, initial: true) { _, visible in
            if !visible && model.offersTourAtLaunch && model.tourStep == nil { model.tourWelcome = true }
        }
        .onChange(of: model.nav.gameID) { _, id in if id != nil { model.tourNoticed(openedGame: true) } }
        .onChange(of: model.data.nav.tab) { _, tab in model.tourNoticed(tab: tab) }
        .sheet(isPresented: Binding(get: { model.addSheetOpen && model.livePose != .tabletop && (model.addIsSystemSheet || !model.liveRightPage) }, set: { if !$0 && model.livePose != .tabletop && (model.addIsSystemSheet || !model.liveRightPage) { model.addSheetOpen = false } })) {
            // Full height: a shorter sheet left the Library's first-run strip showing, inert, beneath it.
            AddGameSheet().presentationDetents([.large])
        }
        .sheet(isPresented: Binding(get: { model.settingsOpen && model.livePose != .tabletop && model.livePose != .book }, set: { if !$0 && model.livePose != .tabletop && model.livePose != .book { model.settingsOpen = false } })) {
            SettingsView()
        }
        .sheet(item: Binding(get: { model.livePose == .tabletop ? nil : model.tagExplainer }, set: { if $0 == nil && model.livePose != .tabletop { model.tagExplainer = nil } })) { kind in
            VerificationExplainer(kind: kind).presentationDetents([.medium])
        }
        // N-9's "What is sent" (Iris, #455): a system sheet, except Tabletop, where the lower-half panel shows it.
        .sheet(isPresented: Binding(get: { model.keepCurrentDetailsOpen && model.livePose != .tabletop }, set: { if !$0 && model.livePose != .tabletop { model.keepCurrentDetailsOpen = false } })) {
            KeepCurrentDetailsSheet().presentationDetents([.medium, .large])
        }
        .fullScreenCover(isPresented: Binding(get: { model.player != nil }, set: { if !$0 { model.player = nil } })) {
            // The player is dark in light and dark mode. Its cover is its own presentation, so pinning its scheme here (not
            // only the environment) gives it a light status bar too: in light mode the clock and Wi-Fi drew dark over the dark
            // player and all but vanished (Quinn, 9ef14784-light-video-playing).
            if let p = model.player { PlayerView(gameID: p.gameID, releaseID: p.releaseID).preferredColorScheme(.dark) }
        }
        // Trailers and Gallery videos: one cover in every pose, Tabletop included (TT-4, P-2). Dark, status bar included, as above.
        .fullScreenCover(isPresented: Binding(get: { model.trailer != nil }, set: { if !$0 { model.trailer = nil } })) {
            if let t = model.trailer { TrailerView(videoID: t.videoID, name: t.name, gameID: t.gameID).preferredColorScheme(.dark) }
        }
        // bug-064: in light mode the status bar is light over art and the player, dark over the cream page (StatusBarTone).
        .background(StatusBarToneAnchor().frame(width: 0, height: 0).accessibilityHidden(true))
        .onChange(of: model.player != nil || model.trailer != nil, initial: true) { _, up in StatusBarTone.shared.setCover(up) }
        // R-11: every link the app opens passes here, sheets and covers included; a YouTube video plays in our player.
        .environment(\.openURL, OpenURLAction { url in model.playVideoLink(url) ? .handled : .systemAction })
    }
}

struct TabRoot: View {
    @Environment(AppModel.self) private var model
    var duo: DuoContext

    var body: some View {
        @Bindable var model = model
        TabView(selection: $model.data.nav.tab) {
            Tab("Library", systemImage: "books.vertical", value: AppTab.library) {
                LibraryRoot(duo: duo).auditActive(model.nav.tab == .library).underLowerPanel(duo)
                    .tourLane(model.nav.tab == .library && model.nav.gameID == nil && (model.tourWelcome || model.tourStep != nil))
            }
            .badge(model.totalUnread)

            Tab("Updates", systemImage: "newspaper", value: AppTab.updates) {
                // D-1 (0.5.6, Card D): an update pushed from a row; Back pops to the list at the same scroll.
                NavigationStack(path: Binding(get: { model.nav.updatesRelease.map { [$0] } ?? [] },
                                              set: { model.nav.updatesRelease = $0.last })) {
                    UpdatesView().tabletopChrome(duo)
                        .navigationDestination(for: ReleaseRef.self) { ref in
                            ReleaseDetailView(gameID: ref.gameID, releaseID: ref.releaseID).tabletopChrome(duo)
                        }
                }
                .auditActive(model.nav.tab == .updates)
                .underLowerPanel(duo)
                // J-1 (0.5.7 gate): an update the fold moved onto the game's Page comes back as this tab's push once the tab is
                // showing and the pose change has settled; pushed in the same update as the tab switch, it drew blank.
                .task(id: model.pendingUpdatesRelease) {
                    guard model.pendingUpdatesRelease != nil else { return }
                    try? await Task.sleep(for: .milliseconds(500))
                    model.applyPendingUpdatesPush()
                }
            }

            Tab("News", systemImage: "megaphone", value: AppTab.news) {
                NavigationStack { NewsView().tabletopChrome(duo) }.auditActive(model.nav.tab == .news).underLowerPanel(duo)
            }

            Tab(value: AppTab.search, role: .search) {
                NavigationStack { SearchView().tabletopChrome(duo) }.auditActive(model.nav.tab == .search).underLowerPanel(duo)
            }
        }
        // J-1: a pushed update only exists where pushing is the layout (one column: Closed, Open both ways). Folding to Book or
        // Tabletop moves it onto the game's Page; unfolding back to one column pushes it again (AppModel). Here, once for both
        // stacks, not in the game book, which is hidden under the push.
        .onChange(of: duo.oneColumn, initial: true) { _, one in
            if one { model.enterOneColumn() } else { model.leaveOneColumn() }
        }
        .onChange(of: model.data.nav.tab) { old, new in
            if new == .search && old != .search { model.searchReturnTab = old }
            // D-1: leaving the Library by its tab drops the open game's way back, so a later Back goes to the Library.
            if new != .library { model.nav.returnTab = nil }
        }
    }
}

enum TopBarFade { static let height: CGFloat = 16 }

extension View {
    /// Tabletop: the system's horizontal bars would put controls in the upper half, so they are
    /// hidden and the lower rail carries them instead (G-4).
    /// Apply to each screen inside a navigation stack: bar visibility is read from the visible
    /// screen, not from the stack or the TabView.
    /// Open portrait (Iris, 19 Nov, on Terry's "scrolling behind another menu"): the top bar (Back, Notifications, Status, More
    /// on a game) and the bottom tab bar are solid bg, so nothing scrolls under either bar. The other poses keep the system's.
    /// One modifier chain in every pose, so a pose change never swaps the screen's identity (and its scroll and focus state).
    /// Scroll edges fade (Quinn, on #541): under the solid top bar, a 16 pt band from bg to clear, so content fades out instead of
    /// being cut at the bar's edge. A safe-area inset, so the page's rest position starts below it and only scrolled content passes
    /// under; 0 pt in the other poses (the same view, so identity holds).
    /// While a Tabletop lower-half panel is open, the tab's page under it takes no touches and is hidden from VoiceOver: the
    /// Library's A to Z strip read out over the rail (x 592 to 636, Mac at c1c1191e), and a tap that misses the panel must never
    /// act on the page beneath it. Applied inside each tab, so the hiding reaches the tab's hosted content, and never to the
    /// rail, which stays live (J-20).
    func underLowerPanel(_ duo: DuoContext) -> some View { modifier(UnderLowerPanel(duo: duo)) }

    func tabletopChrome(_ duo: DuoContext) -> some View {
        let solid = duo.pose == .flat && !duo.isLandscape
        return toolbarVisibility(duo.pose == .tabletop ? .hidden : .automatic, for: .navigationBar, .tabBar)
            .toolbarBackground(PlayscribeRole.bg, for: .navigationBar, .tabBar)
            .toolbarBackgroundVisibility(solid ? .visible : .automatic, for: .navigationBar, .tabBar)
            .safeAreaInset(edge: .top, spacing: 0) {
                LinearGradient(colors: [PlayscribeRole.bg, PlayscribeRole.bg.opacity(0)], startPoint: .top, endPoint: .bottom)
                    .frame(height: solid ? TopBarFade.height : 0)
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
            }
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
                // A swipe back from the game leaves it the way the Back button does (D-1: to where it was opened from).
                if path.isEmpty, model.nav.gameID != nil { model.closeGame(); return }
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
    }
}

/// Tabletop's lower trailing rail: Back first, then the screen's actions, then the tabs.
struct TabletopRail: View {
    static let width: CGFloat = 56
    @Environment(AppModel.self) private var model
    var duo: DuoContext
    /// True only while the actions overflow and more lies below the visible part (Iris: no fade at rest).
    @State private var moreBelow = false

    var body: some View {
        VStack(spacing: 6) {
            // The screen's controls scroll when they outgrow the lower half (a centred overflow pushed the first
            // button above the fold, 468 vs 474.5: G-4); the tabs stay pinned below.
            ScrollView {
              VStack(spacing: 6) {
            if let id = model.nav.gameID, model.nav.tab == .library {
                // Iris (0.5.6 hotfix): Back, Notifications, Status, More, the same set and order as every other pose's bar, and
                // few enough to fit the lower half on any fold without scrolling. Share and Check for updates are behind More, and
                // so is Companion's Bookmarks (its stage cards carry no glyph in Tabletop). Back keeps the other poses' id.
                RailButton(action: ScreenAction(id: "back", title: model.backTitle, systemImage: "chevron.backward",
                                                kind: .button { model.closeGame() }))
                    .accessibilityIdentifier("gameBack")
                ForEach(model.gameActions(id, bookmarks: true)) { RailButton(action: $0) }
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
                        .frame(width: 44, height: 44)
                        .background(Circle().fill(.regularMaterial))
                        // A Menu has no action of ours to run first: close any open panel as the tap lands.
                        .simultaneousGesture(TapGesture().onEnded { model.closeLowerPanels() })
                        .tappableFrame()
                }
                // Settings has its own cog on the rail, not inside the View menu (Terry, 0.2.0 build 5).
                // The gear toggles: tapped while Settings is open, it closes it (Iris, #556). The pre-action has already closed
                // every panel, so this reads whether Settings was open before the tap.
                RailButton(action: ScreenAction(id: "settings", title: "Settings", systemImage: "gearshape",
                                                kind: .button { [settingsWasOpen = model.settingsOpen] in if !settingsWasOpen { model.settingsOpen = true } }))
                    .accessibilityIdentifier("settingsButton")
                // Playing / Upcoming is the page's own switch, in the lower half like every other pose; not repeated here (Iris,
                // 0.5.7 gate: with it the rail needed five actions, scrolled, and cut the fifth at the tab group).
            }
              }
            }
            .scrollBounceBehavior(.basedOnSize)
            .scrollIndicators(.hidden)
            // When the lower half is short the controls scroll: fade the edge so a cut-off button reads as "more",
            // and leave room so the last one (More) rests fully clear of the tab capsule and of the edge fade at the end of the scroll
            // (Iris, bug-tabletop-rail-more-hidden: 8 pt left More under the fade on KCD II).
            .contentMargins(.bottom, 8, for: .scrollContent)
            .onScrollGeometryChange(for: Bool.self) { g in
                g.contentSize.height - g.contentOffset.y > g.containerSize.height + 1
            } action: { _, more in moreBelow = more }
            .mask(LinearGradient(stops: [.init(color: .black, location: moreBelow ? 0.9 : 1), .init(color: moreBelow ? .clear : .black, location: 1)],
                                 startPoint: .top, endPoint: .bottom))
            .namedFrame("tabletopRailActions")
            // Iris: the same floating capsule as Closed's tab bar, no full-height strip or hairline.
            VStack(spacing: 0) {
                tab(.library, "Library", "books.vertical", badge: model.totalUnread)
                tab(.updates, "Updates", "newspaper")
                tab(.news, "News", "megaphone")
                tab(.search, "Search", "magnifyingglass")
            }
            .padding(.vertical, 4)
            .background(Capsule().fill(.regularMaterial))
            .accessibilitySortPriority(2)   // VoiceOver: tabs first, then actions
        }
        .padding(.vertical, 8)
        .frame(maxHeight: .infinity)
        // A rail tap closes an open lower-half panel first, then does what the button says (Iris, #556; J-20).
        .environment(\.railPreAction, { model.closeLowerPanels() })
        // The rail's buttons are 44 pt and do not grow with text (0.5.1 spec 3): at AX sizes the icons overlapped.
        .dynamicTypeSize(...DynamicTypeSize.large)
    }

    private func tab(_ t: AppTab, _ title: String, _ symbol: String, badge: Int = 0) -> some View {
        Button {
            model.closeLowerPanels()
            model.nav.tab = t
        } label: {
            Image(systemName: symbol)
                .font(PlayscribeFont.title3)
                .symbolVariant(model.nav.tab == t ? .fill : .none)
                .foregroundStyle(model.nav.tab == t ? PlayscribeRole.action : Color.primary)
                .frame(width: 44, height: 44)
                // The same selected treatment as the rail's action buttons (RailButton), so the rail reads as one style.
                .background(Circle().fill(PlayscribeRole.action.opacity(model.nav.tab == t ? 0.18 : 0)))
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
        .tourAnchor(t == .updates ? .updates : nil)
    }
}

extension View {
    /// A scrolling page ends above the pill and toasts instead of under them (N-7, B-8, 0.5.1 spec 2): one mechanism for the
    /// Library, Updates, the game Page, Contents and release detail. Apply it to the scroll view.
    func clearsMessages() -> some View { modifier(MessageClearance()) }
}

/// The page ends 12 pt above the pill (or toast) wherever it actually sits, and only where the pill overlaps the page sideways
/// (Book's right page gets none while the pill is on the left). The pad is worked out from measured edges (this view's frame
/// without the pad, the pill's frame), not from heights and offsets, so it cannot leave a dead band or run under the pill in
/// any pose (ae0a608, Open portrait).
private struct MessageClearance: ViewModifier {
    @Environment(AppModel.self) private var model
    @Environment(\.duo) private var duo
    @State private var pad: CGFloat = 0
    /// This view's frame in global coordinates. The pad sits inside it, so its bottom edge does not move with the pad.
    @State private var frame: CGRect = .zero

    private func update() {
        var next: CGFloat = 0
        if let m = model.messageFrame, frame.minX < m.maxX, frame.maxX > m.minX {
            next = max(0, frame.maxY - (m.minY - 12))
        }
        // Open portrait: the tab bar floats over the page and gives it no bottom inset, so the last row ended under it
        // (r053-open-portrait-tabbar-covers-last-row). Measured, not assumed: only what still reaches into the band the bar
        // occupies is padded, so a screen the system already insets gets nothing. The band is the one the pill sits above.
        if duo.pose == .flat && !duo.isLandscape {
            let windowBottom = duo.size.height + duo.safeArea.top + duo.safeArea.bottom
            next = max(next, frame.maxY - (windowBottom - LowerMessages.bottomPadding(duo)))
        }
        if abs(next - pad) > 0.5 { pad = next }
    }

    func body(content: Content) -> some View {
        content
            // No `.mask` soft edge: a masked scroll view is no longer the one the navigation bar tracks, and from #246 the Open
            // portrait large "Library" title vanished (354d15c, 9914a80). The soft edge returns once a Mac still shows it safe.
            .padding(.bottom, pad)
            .onGeometryChange(for: CGRect.self) { $0.frame(in: .global) } action: { frame = $0; update() }
            .onChange(of: model.messageFrame) { _, _ in update() }
            .onChange(of: duo) { _, _ in update() }
            // The pad changes the moment the pill shows. It must not ride a running pose animation, or the old arrangement
            // lingers faintly under the new one (Book, ad54f44 stills).
            .transaction(value: pad) { $0.animation = nil }
    }
}

/// The "New on PS5" pill (N-7) and toasts with Undo (B-8), above the tab bar or in the lower half.
struct LowerMessages: View {
    @Environment(AppModel.self) private var model
    var duo: DuoContext

    static func bottomPadding(_ duo: DuoContext) -> CGFloat {
        duo.pose == .flat && !duo.isLandscape ? 96 : duo.pose == .tabletop ? 12 : 16
    }

    var body: some View {
        VStack(spacing: 0) {
            Spacer()
            VStack(spacing: 8) {
            if let pill = model.pill, let game = model.game(pill.gameID), let r = model.release(pill.gameID, pill.releaseID) {
                Button {
                    model.openRelease(gameID: pill.gameID, releaseID: pill.releaseID)
                } label: {
                    HStack(spacing: 8) {
                        UnreadDot()
                        Text("New on PS5: \(game.name.gluingTrailingNumeral) \(r.displayName)")
                            .font(PlayscribeFont.subheadline.weight(.semibold))
                            // Never cut: up to three lines at the capped size (Iris, 0.5.1 spec 2).
                            .lineLimit(3)
                            .fixedSize(horizontal: false, vertical: true)
                            .multilineTextAlignment(.leading)
                        Image(systemName: "chevron.forward").font(PlayscribeFont.caption)
                    }
                    // Transient chrome stops scaling at AX1 before the page does; VoiceOver still reads all of it (Iris).
                    .dynamicTypeSize(...DynamicTypeSize.accessibility1)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                    .frame(minHeight: 44)
                    // A solid pill: nothing shows through it (Iris, 6589abf: it ghosted over the date pills).
                    // A 24 pt corner: a full capsule on one line, a rounded rectangle on two or more.
                    .background(RoundedRectangle(cornerRadius: 24, style: .continuous).fill(PlayscribeRole.chipFill))
                    .adaptiveGlass(in: RoundedRectangle(cornerRadius: 24, style: .continuous), interactive: true)
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
                    // Wraps instead of shrinking or truncating (Iris, AX3; up to four lines at AX5 for the check result).
                    Text(toast.text).font(PlayscribeFont.subheadline).lineLimit(4).fixedSize(horizontal: false, vertical: true)
                    if let undo = toast.undo {
                        Button(toast.actionLabel) { undo(); model.toastClear() }
                            .font(PlayscribeFont.subheadline.weight(.semibold))
                            .hitTarget()
                            .tappableFrame()
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .frame(minHeight: 44)
                // 22 pt corners: a capsule on one line, and wrapped text at AX5 stays off the curved ends (Iris).
                .background(PlayscribeRole.chipFill, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous).strokeBorder(PlayscribeColor.vellum300.opacity(0.2)))
                .shadow(color: .black.opacity(0.5), radius: 12, y: 4)
                // Clear of the rows' trailing menu buttons.
                .padding(.trailing, duo.pose == .closed ? 56 : 0)
                .frame(maxWidth: .infinity, alignment: .leading)
                .transition(.opacity)
                // A toast with nothing to press (the tip, "Added") never blocks the chips or tiles under it.
                .allowsHitTesting(toast.undo != nil)
                // A swipe dismisses it early (Iris, #244); the 20 pt threshold leaves a tap on Undo alone.
                .highPriorityGesture(DragGesture(minimumDistance: 20).onEnded { _ in model.toastClear() })
                .accessibilityElement(children: .combine)
                .accessibilityActions {
                    if let undo = toast.undo { Button(toast.actionLabel) { undo(); model.toastClear() } }
                    Button("Dismiss") { model.toastClear() }
                }
            }
            }
            // The Library reserves this much at its bottom edge (a safe-area inset), so the pill never covers its
            // top-of-page controls: the content reflows above it (0.5.1 spec 2, Iris).
            .onGeometryChange(for: CGRect.self) { $0.frame(in: .global) } action: { frame in
                let h = frame.height
                // Everything from the bottom edge up to the top of the messages, plus 8 pt of air.
                let inset = h > 0 ? h + Self.bottomPadding(duo) + 8 : 0
                if model.messageInset != inset { model.messageInset = inset }
                let shown: CGRect? = h > 0 ? frame : nil
                if model.messageFrame != shown { model.messageFrame = shown }
            }
        }
        // Above the bottom tab bar only where the bars are horizontal (open portrait).
        // Tabletop: 12 pt above the bottom, left of the rail (0.5.1 spec 2).
        .padding(.bottom, Self.bottomPadding(duo))
        .padding(.trailing, duo.pose == .tabletop ? TabletopRail.width : 0)
        .padding(.horizontal, 16)
        // Book: the pill and toasts stay on the left page; they never straddle the fold.
        .frame(maxWidth: duo.pose == .book ? max(0, (duo.division?.minX ?? 0) - 8) : .infinity)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .animation(.snappy, value: model.toast)
        .animation(.snappy, value: model.pill?.releaseID)
    }
}

private struct UnderLowerPanel: ViewModifier {
    @Environment(AppModel.self) private var model
    var duo: DuoContext

    func body(content: Content) -> some View {
        let covered = duo.pose == .tabletop
            && (model.addSheetOpen || model.settingsOpen || model.linksSheetOpen || model.tagExplainer != nil || model.keepCurrentDetailsOpen)
        content
            .allowsHitTesting(!covered)
            .accessibilityHidden(covered)
    }
}
