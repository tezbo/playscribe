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
                         : "Change a single game from the bell on its page.")
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
