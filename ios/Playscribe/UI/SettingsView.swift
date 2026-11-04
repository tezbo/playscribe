import SwiftUI

struct SettingsView: View {
    /// "0.2.0, build 12, abc1234", from the bundle, so it always matches the build.
    static var version: String {
        let info = Bundle.main.infoDictionary
        let v = info?["CFBundleShortVersionString"] as? String ?? ""
        let b = info?["CFBundleVersion"] as? String ?? ""
        let sha = info?["PlayscribeGitSHA"] as? String ?? ""
        return [v, b.isEmpty ? "" : "build \(b)", sha].filter { !$0.isEmpty }.joined(separator: ", ")
    }

    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var systemDismiss
    @Environment(\.panelClose) private var panelClose
    /// In Tabletop the sheet is the lower-half panel, which is not presented, so it closes itself.
    private func dismiss() { if let panelClose { panelClose() } else { systemDismiss() } }
    @Environment(\.duo) private var duo
    @State private var simGame: String = ""
    @State private var simKind: AppModel.SimKind = .major
    @State private var simDelay: Double = 10

    /// Quiet hours (0.5.0): off by default; the pickers sit inline in Tabletop, never a popover into the upper half.
    @ViewBuilder private var quietHoursRows: some View {
        let on = model.data.quietHours != nil
        Toggle("Quiet hours", isOn: Binding(get: { on }, set: { model.data.quietHours = $0 ? QuietHours() : nil }))
            .accessibilityValue(model.data.quietHours.map { "on, \($0.label)" } ?? "off")
            .accessibilityIdentifier("quietHours")
            // Tell the push relay when the window changes, so a push inside it is delivered passively.
            .onChange(of: model.data.quietHours) { _, new in PushRegistrar.syncQuietHours(new) }
        if let q = model.data.quietHours {
            quietPicker("From", minutes: q.from) { model.data.quietHours?.from = $0 }
            quietPicker("Until", minutes: q.until) { model.data.quietHours?.until = $0 }
        }
    }

    @ViewBuilder private func quietPicker(_ title: String, minutes: Int, set: @escaping (Int) -> Void) -> some View {
        let binding = Binding<Date>(get: { QuietHours.date(minutes: minutes) }, set: { set(QuietHours.minutes(of: $0)) })
        Group {
        if duo.pose == .tabletop {
            VStack(alignment: .leading) {
                Text(title)
                DatePicker(title, selection: binding, displayedComponents: .hourAndMinute)
                    .datePickerStyle(.wheel).labelsHidden().frame(height: 120).clipped()
            }
        } else {
            DatePicker(title, selection: binding, displayedComponents: .hourAndMinute).frame(minHeight: 44)
        }
        }
        .accessibilityHint(title == "From" ? "Sets when quiet hours start" : "Sets when quiet hours end")
    }

    var body: some View {
        @Bindable var model = model
        NavigationStack {
            Form {
                // Tabletop's panel is half a screen: the build version leads, so it is on screen
                // without scrolling (Terry checks it to verify the build).
                if duo.pose == .tabletop {
                    Section { LabeledContent("Version", value: Self.version).accessibilityIdentifier("appVersion") }
                }
                // One default for every game (Terry, 0.2.0); a game's own setting lives on its bell.
                Section {
                    Picker("Notify me about", selection: Binding(get: { model.notifyDefault }, set: { model.data.notifyDefault = $0 })) {
                        ForEach(NotifyLevel.allCases) { Text($0.label).tag($0) }
                    }
                    Toggle("Pause all", isOn: $model.data.pauseAll)
                    quietHoursRows
                    let overrides = model.notifyOverrides
                    if !overrides.isEmpty {
                        NavigationLink("\(overrides.count) game\(overrides.count == 1 ? " has its" : "s have their") own setting") {
                            List(overrides, id: \.game.id) { o in
                                LabeledContent(o.game.name, value: o.level.label)
                            }
                            .navigationTitle("Own settings")
                        }
                    }
                } header: {
                    Text("Notifications")
                } footer: {
                    Text(NotificationService.shared.authorization == .denied
                         ? "Notifications are off for \(Brand.name) in iOS Settings."
                         : model.data.quietHours.map({ $0.from == $0.until }) == true
                            ? "These hours are empty, so nothing is quiet. Choose different times, or turn quiet hours off."
                         : model.data.quietHours != nil
                            // Honest scope until a push path honours the window (r050-quiet-hours-push).
                            ? "Alerts scheduled on this device arrive silently during these hours. Updates sent while the app is closed may still make a sound."
                            : "Change a single game from the bell on its page.")
                }
                Section {
                    Toggle("Sounds", isOn: Binding(get: { model.data.soundsOff != true }, set: { model.data.soundsOff = $0 ? nil : true }))
                        .accessibilityHint("Plays a soft pop when games are added")
                        .accessibilityIdentifier("sounds")
                } footer: {
                    Text("A soft pop when you add games. Never plays while you are listening to something else.")
                }

                #if INTERNAL
                if BuildChannel.showsInternalTools {
                Section {
                    Picker("Game", selection: $simGame) {
                        ForEach(model.libraryRows) { Text($0.game.name).tag($0.id) }
                    }
                    Picker("Kind", selection: $simKind) {
                        ForEach(AppModel.SimKind.allCases) { Text($0.label).tag($0) }
                    }
                    Stepper("Arrives in \(Int(simDelay)) s", value: $simDelay, in: 3...120, step: 1)
                    Button("Simulate update") {
                        guard !simGame.isEmpty else { return }
                        model.simulateUpdate(gameID: simGame, kind: simKind, delay: simDelay)
                        dismiss()
                    }
                    .disabled(simGame.isEmpty)
                } header: {
                    Text("Simulate an update (internal builds)")
                } footer: {
                    Text("Creates a release marked Simulated and schedules its notification. Close or lock the device to see it arrive on the outer display.")
                }

                Section("Testing") {
                    Toggle("Show tappable frames and reserved regions", isOn: Binding(
                        get: { model.showDebugOverlay },
                        set: { model.showDebugOverlay = $0; if $0 { FoldAuditSwitch.enabled = true } }))
                    Button("Reset to first run", role: .destructive) { model.resetToFirstRun(); dismiss() }
                    Button("Reset to demo library") { model.resetDemo(); dismiss() }
                    LabeledContent("Pose", value: duo.pose.rawValue)
                    if let token = NotificationService.shared.deviceToken {
                        LabeledContent("APNs token", value: String(token.prefix(12)) + "…")
                    }
                }
                }
                #endif

                Section {
                    if duo.pose != .tabletop {
                        LabeledContent("Version", value: Self.version)
                            .accessibilityIdentifier("appVersion")
                    }
                } footer: {
                    Text("Artwork and trailers belong to their publishers. \(Brand.trademarkNotice)")
                }
            }
            .navigationTitle("Settings")
            .toolbarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button { dismiss() } label: { Label("Close", systemImage: "xmark") }
                }
            }
            .onAppear { if simGame.isEmpty { simGame = model.libraryRows.first?.id ?? "" } }
        }
        .presentationPlacement(duo.pose == .closed ? .automatic : .trailing)
    }
}
