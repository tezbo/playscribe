import SwiftUI

/// Width the tabletop rail takes from the lower half's trailing edge.
private struct RailWidthKey: EnvironmentKey { static let defaultValue: CGFloat = 0 }
extension EnvironmentValues {
    var railWidth: CGFloat {
        get { self[RailWidthKey.self] }
        set { self[RailWidthKey.self] = newValue }
    }
}

struct RootView: View {
    @Environment(AppModel.self) private var model
    @AppStorage("didShowSplash") private var didShowSplash = false
    @State private var splashVisible = false
    @State private var frames: [CGRect] = []

    var body: some View {
        DuoReader { duo in
            ZStack {
                TabRoot(duo: duo)
                    .environment(\.railWidth, duo.pose == .tabletop ? TabletopRail.width : 0)

                if duo.pose == .tabletop, let fold = duo.division {
                    TabletopRail(duo: duo)
                        .frame(width: TabletopRail.width, height: max(0, duo.size.height - fold.maxY))
                        .position(x: duo.size.width - TabletopRail.width / 2, y: fold.maxY + (duo.size.height - fold.maxY) / 2)
                }

                LowerMessages(duo: duo)

                if splashVisible {
                    SplashView(duo: duo) { splashVisible = false }
                        .transition(.opacity)
                        .zIndex(10)
                }
            }
            .onPreferenceChange(TappableFrameKey.self) { frames = $0 }
            .overlay {
                if model.showDebugOverlay { DebugOverlay(frames: frames, duo: duo) }
            }
        }
        .background(Color.ink0)
        .onAppear {
            // §2: the branded splash plays only on the first launch, never from a notification (L-3).
            if !didShowSplash && !NotificationService.shared.launchedFromNotification {
                splashVisible = true
                didShowSplash = true
            }
        }
        .onChange(of: NotificationService.shared.launchedFromNotification) { _, fromNotification in
            if fromNotification { splashVisible = false }
        }
        .sheet(isPresented: Binding(get: { model.addSheetOpen }, set: { model.addSheetOpen = $0 })) {
            AddGameSheet()
        }
        .sheet(isPresented: Binding(get: { model.settingsOpen }, set: { model.settingsOpen = $0 })) {
            SettingsView()
        }
        .fullScreenCover(isPresented: Binding(get: { model.player != nil }, set: { if !$0 { model.player = nil } })) {
            if let p = model.player { PlayerView(gameID: p.gameID, releaseID: p.releaseID) }
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
                LibraryRoot(duo: duo)
            }
            .badge(model.totalUnread)

            Tab("Updates", systemImage: "clock.arrow.circlepath", value: AppTab.updates) {
                NavigationStack { UpdatesView() }
                    .tabletopChrome(duo)
            }

            Tab(value: AppTab.search, role: .search) {
                NavigationStack { SearchView() }
                    .tabletopChrome(duo)
            }
        }
        .toolbarVisibility(duo.pose == .tabletop ? .hidden : .automatic, for: .tabBar)
    }
}

extension View {
    /// Tabletop: the system's horizontal bars would put controls in the upper half, so they are
    /// hidden and the lower rail carries them instead (G-4).
    func tabletopChrome(_ duo: DuoContext) -> some View {
        toolbarVisibility(duo.pose == .tabletop ? .hidden : .automatic, for: .navigationBar)
    }
}

/// Library tab: a stack everywhere except the open inner display in landscape, where it is a
/// split view with the library as sidebar (G-1).
struct LibraryRoot: View {
    @Environment(AppModel.self) private var model
    var duo: DuoContext

    var body: some View {
        if duo.pose == .flat && duo.isLandscape {
            NavigationSplitView {
                LibrarySidebar()
            } detail: {
                if let id = model.nav.gameID {
                    NavigationStack { GameBookView(gameID: id) }
                } else {
                    ContentUnavailableView("Choose a game", systemImage: "book", description: Text("Its patch journal and game book open here."))
                }
            }
        } else {
            NavigationStack(path: Binding(
                get: { model.nav.gameID.map { [$0] } ?? [] },
                set: { model.nav.gameID = $0.last }
            )) {
                LibraryView()
                    .navigationDestination(for: String.self) { id in GameBookView(gameID: id) }
            }
            .tabletopChrome(duo)
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
            if let id = model.nav.gameID, model.nav.tab == .library {
                RailButton(action: ScreenAction(id: "back", title: "Library", systemImage: "chevron.backward",
                                                kind: .button { model.closeGame() }))
                ForEach(model.gameActions(id)) { RailButton(action: $0) }
            } else if model.nav.tab == .library {
                if !model.addSheetOpen {
                    RailButton(action: ScreenAction(id: "add", title: "Add game", systemImage: "plus", kind: .button { model.addSheetOpen = true }))
                }
                RailButton(action: ScreenAction(id: "settings", title: "Settings", systemImage: "gearshape", kind: .button { model.settingsOpen = true }))
            }
            Spacer(minLength: 8)
            Divider().frame(width: 28)
            tab(.library, "Library", "books.vertical", badge: model.totalUnread)
            tab(.updates, "Updates", "clock.arrow.circlepath")
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
                .font(.title3)
                .symbolVariant(model.nav.tab == t ? .fill : .none)
                .foregroundStyle(model.nav.tab == t ? Color.accentColor : .secondary)
                .frame(width: 48, height: 48)
                .overlay(alignment: .topTrailing) {
                    if badge > 0 {
                        Text("\(badge)").font(.caption2.bold()).padding(.horizontal, 4)
                            .background(Color.red, in: Capsule()).foregroundStyle(.white)
                    }
                }
                .contentShape(Rectangle())
        }
        .accessibilityLabel(title)
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
                            .font(.subheadline.weight(.semibold))
                            .lineLimit(2)
                        Image(systemName: "chevron.forward").font(.caption)
                    }
                    .padding(.horizontal, 16)
                    .frame(minHeight: 44)
                    .glassEffect(.regular.interactive(), in: Capsule())
                }
                .buttonStyle(.plain)
                .tappableFrame()
                .gesture(DragGesture(minimumDistance: 20).onEnded { _ in model.pill = nil })
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }
            if let toast = model.toast {
                HStack(spacing: 12) {
                    Text(toast.text).font(.subheadline)
                    if let undo = toast.undo {
                        Button("Undo") { undo(); model.toastClear() }
                            .font(.subheadline.weight(.semibold))
                            .hitTarget()
                            .tappableFrame()
                    }
                }
                .padding(.horizontal, 16)
                .frame(minHeight: 44)
                .glassEffect(.regular, in: Capsule())
                .transition(.opacity)
                .accessibilityElement(children: .contain)
            }
        }
        .padding(.bottom, duo.pose == .tabletop ? 16 : 96)
        .padding(.trailing, duo.pose == .tabletop ? TabletopRail.width : 0)
        .padding(.horizontal, 16)
        .animation(.snappy, value: model.toast)
        .animation(.snappy, value: model.pill?.releaseID)
    }
}
