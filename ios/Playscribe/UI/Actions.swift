import SwiftUI

/// One description of a screen's actions, rendered either as system toolbar items or, in
/// tabletop, on the lower trailing rail (Terry's rule: nothing tappable above the fold).
struct ScreenAction: Identifiable {
    enum Kind {
        case button(() -> Void)
        case menu([MenuSection])
    }
    struct MenuSection: Identifiable {
        var id = UUID()
        var title: String?
        var items: [MenuItem]
    }
    struct MenuItem: Identifiable {
        var id: String
        var title: String
        var checked = false
        var destructive = false
        var action: () -> Void
    }

    var id: String
    var title: String
    var systemImage: String
    var kind: Kind
    /// Shown as the current choice: accent colour and a tinted backing, the same in every pose.
    var selected = false
    /// Higher stays visible longer (visibilityPriority).
    var priority: ToolbarItemVisibilityPriority = .automatic
}

extension Array where Element == ScreenAction.MenuSection {
    /// Which items are ticked. Keying a Menu on this rebuilds it when a choice changes, so a toolbar or rail menu never
    /// shows the old tick (Terry, 0.2.0 build 5: Major only reverted to All updates on return).
    var tickKey: String { flatMap(\.items).filter(\.checked).map(\.id).joined(separator: ",") }
}

struct ActionMenuContent: View {
    var sections: [ScreenAction.MenuSection]
    /// A confirmation dialog drops button icons, so the tick is drawn in the title there and also set as the selected trait.
    var inDialog = false
    var body: some View {
        ForEach(sections) { section in
            Section(section.title ?? "") {
                ForEach(section.items) { item in
                    Button(role: item.destructive ? .destructive : nil, action: item.action) {
                        if item.checked && inDialog { Text("\u{2713} \(item.title)") }
                        else if item.checked { Label(item.title, systemImage: "checkmark") } else { Text(item.title) }
                    }
                    // A system dialog drops the selected trait (Mac, 3bb7345c), so in the dialog the label says it; menus keep the trait.
                    .accessibilityLabel(item.checked && inDialog ? "\(item.title), selected" : item.title)
                    .accessibilityAddTraits(item.checked ? .isSelected : [])
                }
            }
        }
    }
}

/// Long press opens the status menu; VoiceOver gets the same choices as custom actions. Nothing here is
/// a swipe: swipe Remove lives only on list rows. Attach after the view's own accessibility modifiers.
struct GameQuickActions: ViewModifier {
    @Environment(AppModel.self) private var model
    var game: CatalogGame

    func body(content: Content) -> some View {
        let sections = model.quickMenu(game)
        let inLibrary = model.entry(game.id) != nil
        content
            .contextMenu { ActionMenuContent(sections: sections) }
            .accessibilityActions {
                ForEach(sections.flatMap(\.items)) { item in
                    if !item.checked {
                        Button(item.destructive ? item.title : "\(inLibrary ? "Set to" : "Add as") \(item.title)", action: item.action)
                    }
                }
            }
    }
}

extension View {
    func gameQuickActions(_ game: CatalogGame) -> some View { modifier(GameQuickActions(game: game)) }
}

/// Pressed feedback for rail buttons: a visible dim in every pose (the default plain style showed none).
struct RailPressStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.opacity(configuration.isPressed ? 0.45 : 1)
    }
}

/// A rail button: icon with the title as its accessibility label, 44 pt hit target.
struct RailButton: View {
    var action: ScreenAction
    /// A rail menu is a plain labelled Button that presents a dialog with the same choices. A SwiftUI Menu always exposed a second,
    /// unlabelled button to XCUITest and VoiceOver (Mac frame dumps at f78ee25, 40c142a and cc89583, and no accessibility modifier
    /// removed it), so there is one element here by construction (bug-rail-menu-unlabelled-buttons).
    @State private var choosing = false
    var body: some View {
        Group {
            switch action.kind {
            case .button(let run):
                Button(action: run) { icon }
                    .buttonStyle(RailPressStyle())
            case .menu(let sections):
                Button { choosing = true } label: { icon }
                    .buttonStyle(RailPressStyle())
                    .confirmationDialog(action.title, isPresented: $choosing, titleVisibility: .visible) {
                        ActionMenuContent(sections: sections, inDialog: true)
                    }
                    .id(sections.tickKey)
            }
        }
        .accessibilityLabel(action.title)
        .tappableFrame()
    }

    private var icon: some View {
        Image(systemName: action.systemImage)
            .font(PlayscribeFont.title3)
            .foregroundStyle(action.selected ? PlayscribeColor.accent : Color.primary)
            .frame(width: 44, height: 44)
            // Round buttons like Closed's rail: a material disc, tinted when selected.
            .background(Circle().fill(.regularMaterial))
            .background(Circle().fill(PlayscribeColor.accent.opacity(action.selected ? 0.18 : 0)))
            .contentShape(Rectangle())
    }
}

extension AppModel {
    func notifyMenu(_ gameID: String, header: String = "Notify me about") -> [ScreenAction.MenuSection] {
        let level = notifyLevel(gameID), own = hasOwnNotify(gameID)
        let useDefault = ScreenAction.MenuItem(id: "default", title: "Use default (\(notifyDefault.label))", checked: !own) { [weak self] in
            self?.setNotify(gameID, nil)
        }
        var sections = [ScreenAction.MenuSection(title: header, items: [useDefault] + NotifyLevel.allCases.map { l in
            .init(id: l.rawValue, title: l.label, checked: own && l == level) { [weak self] in
                self?.setNotify(gameID, l)
                // N-2: the bell before a decision opens the system prompt directly.
                if l != .off, NotificationService.shared.authorization == .notDetermined {
                    Task { await NotificationService.shared.requestAuthorization() }
                }
            }
        })]
        if NotificationService.shared.authorization == .denied {
            sections.append(.init(title: "Notifications are off for \(Brand.name)", items: [
                .init(id: "settings", title: "Open Settings") {
                    if let url = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(url) }
                },
            ]))
        }
        return sections
    }

    /// Status and Remove only. Notifications have their own bell menu (Terry, 0.2.0 build 5: the controller icon showed both).
    func statusMenu(_ gameID: String) -> [ScreenAction.MenuSection] {
        let current = entry(gameID)?.status
        let name = game(gameID)?.name ?? "game"
        return [
            .init(title: "Status", items: OwnershipStatus.allCases.map { s in
                .init(id: s.rawValue, title: s.label, checked: s == current) { [weak self] in self?.setStatus(gameID, s) }
            }),
            .init(items: [.init(id: "remove", title: "Remove \(name)", destructive: true) { [weak self] in self?.removeGame(gameID) }]),
        ]
    }

    /// Quick actions on a game anywhere it appears (Terry, 0.5.1; Iris's call): in the library it is the status menu
    /// (ticked current, Remove in red); outside it, the ways to add it.
    func quickMenu(_ game: CatalogGame) -> [ScreenAction.MenuSection] {
        if entry(game.id) != nil {
            var menu = statusMenu(game.id)
            // Accessibility text sizes on a short screen (Closed landscape AX3, 20d340f): the system menu ran off the
            // bottom and Remove never showed. Drop the header and the game's name from Remove so every row fits.
            if UIApplication.shared.preferredContentSizeCategory.isAccessibilityCategory {
                for i in menu.indices {
                    menu[i].title = nil
                    for j in menu[i].items.indices where menu[i].items[j].destructive { menu[i].items[j].title = "Remove" }
                }
            }
            return menu
        }
        let options = OwnershipStatus.allCases.filter { !(game.isUpcoming && $0 == .owned) }
        return [.init(title: "Add to your library as…", items: options.map { s in
            .init(id: s.rawValue, title: s.label) { [weak self] in self?.addGame(game, status: s) }
        })]
    }

    /// D-6: the rail holds only actions that visibly do something: Notifications and Status.
    /// Spoilers live inline on the Page; Mark read lives in the Contents next to the unread rows.
    func gameActions(_ gameID: String) -> [ScreenAction] {
        let name = game(gameID)?.name ?? "this game"
        let level = notifyLevel(gameID)
        var out = [ScreenAction(id: "notify", title: "Notifications", systemImage: level == .off ? "bell.slash" : "bell",
                                kind: .menu(notifyMenu(gameID, header: "Notify me about \(name)")), priority: .high)]
        if let status = entry(gameID)?.status {
            var menu = statusMenu(gameID)
            if !menu.isEmpty { menu[0].title = "\(name) is in your library as…" }
            out.append(ScreenAction(id: "status", title: "Status: \(status.label)", systemImage: status.symbol, kind: .menu(menu), priority: .high))
        }
        // A way to ask for an update check from the game itself (Terry): the same refresh as the Library's pull.
        out.append(ScreenAction(id: "refresh", title: "Check for updates", systemImage: "arrow.clockwise",
                                kind: .button { [weak self] in Task {
                                    await self?.refreshFeed(); await self?.refreshHistories([gameID])
                                    // Tabletop's News page is view only, so this is also its retry.
                                    await NewsStore.shared.load(gameID: gameID, igdbID: self?.game(gameID)?.igdbID)
                                } }))
        return out
    }
}

/// System toolbar items for a list of actions.
struct ActionToolbar: ToolbarContent {
    var actions: [ScreenAction]
    var body: some ToolbarContent {
        ForEach(actions) { a in
            ToolbarItem(placement: .primaryAction) {
                switch a.kind {
                case .button(let run):
                    Button(action: run) { Label(a.title, systemImage: a.systemImage) }
                        .accessibilityShowsLargeContentViewer()
                case .menu(let sections):
                    Menu { ActionMenuContent(sections: sections) } label: { Label(a.title, systemImage: a.systemImage) }
                        .accessibilityShowsLargeContentViewer()
                }
            }
            .visibilityPriority(a.priority)
        }
    }
}
