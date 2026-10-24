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
    /// Higher stays visible longer (visibilityPriority).
    var priority: ToolbarItemVisibilityPriority = .automatic
}

struct ActionMenuContent: View {
    var sections: [ScreenAction.MenuSection]
    var body: some View {
        ForEach(sections) { section in
            Section(section.title ?? "") {
                ForEach(section.items) { item in
                    Button(role: item.destructive ? .destructive : nil, action: item.action) {
                        if item.checked { Label(item.title, systemImage: "checkmark") } else { Text(item.title) }
                    }
                }
            }
        }
    }
}

/// A rail button: icon with the title as its accessibility label, 44 pt hit target.
struct RailButton: View {
    var action: ScreenAction
    var body: some View {
        Group {
            switch action.kind {
            case .button(let run):
                Button(action: run) { icon }
            case .menu(let sections):
                Menu { ActionMenuContent(sections: sections) } label: { icon }
            }
        }
        .accessibilityLabel(action.title)
        .tappableFrame()
    }

    private var icon: some View {
        Image(systemName: action.systemImage)
            .font(PlayscribeFont.title3)
            .frame(width: 48, height: 48)
            .contentShape(Rectangle())
    }
}

extension AppModel {
    func notifyMenu(_ gameID: String) -> [ScreenAction.MenuSection] {
        let level = notifyLevel(gameID)
        var sections = [ScreenAction.MenuSection(title: "Notify me about", items: NotifyLevel.allCases.map { l in
            .init(id: l.rawValue, title: l.label, checked: l == level) { [weak self] in
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

    func statusMenu(_ gameID: String) -> [ScreenAction.MenuSection] {
        let current = entry(gameID)?.status
        let name = game(gameID)?.name ?? "game"
        return [
            .init(title: "Status", items: OwnershipStatus.allCases.map { s in
                .init(id: s.rawValue, title: s.label, checked: s == current) { [weak self] in self?.setStatus(gameID, s) }
            }),
            .init(title: "Notifications", items: NotifyLevel.allCases.map { l in
                .init(id: "n-" + l.rawValue, title: l.label, checked: l == notifyLevel(gameID)) { [weak self] in self?.setNotify(gameID, l) }
            }),
            .init(items: [.init(id: "remove", title: "Remove \(name)", destructive: true) { [weak self] in self?.removeGame(gameID) }]),
        ]
    }

    /// R-8: the game book's actions, toolbar only.
    func gameActions(_ gameID: String) -> [ScreenAction] {
        var out: [ScreenAction] = []
        let level = notifyLevel(gameID)
        out.append(ScreenAction(id: "notify", title: "Notifications", systemImage: level == .off ? "bell.slash" : "bell",
                                kind: .menu(notifyMenu(gameID)), priority: .high))
        let shown = spoilersShown(gameID)
        out.append(ScreenAction(id: "spoilers", title: shown ? "Hide spoilers" : "Show spoilers", systemImage: shown ? "eye" : "eye.slash",
                                kind: .button { [weak self] in self?.setSpoilersShown(gameID, !shown) }, priority: .high))
        if entry(gameID) != nil {
            out.append(ScreenAction(id: "status", title: "Library status", systemImage: "tag", kind: .menu(statusMenu(gameID)), priority: .automatic))
        }
        if unreadCount(gameID) > 0 {
            out.append(ScreenAction(id: "readall", title: "Mark all read", systemImage: "checkmark.circle",
                                    kind: .button { [weak self] in self?.markAllRead(gameID) }, priority: .low))
        }
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
                case .menu(let sections):
                    Menu { ActionMenuContent(sections: sections) } label: { Label(a.title, systemImage: a.systemImage) }
                }
            }
            .visibilityPriority(a.priority)
        }
    }
}
