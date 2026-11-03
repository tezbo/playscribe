import SwiftUI

struct SettingsView: View {
    /// "0.2.0 (12)", from the bundle, so it always matches the build.
    static var version: String {
        let info = Bundle.main.infoDictionary
        let v = info?["CFBundleShortVersionString"] as? String ?? ""
        let b = info?["CFBundleVersion"] as? String ?? ""
        return b.isEmpty ? v : "\(v) (\(b))"
    }

    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @Environment(\.duo) private var duo
    @State private var simGame: String = ""
    @State private var simKind: AppModel.SimKind = .major
    @State private var simDelay: Double = 10

    var body: some View {
        @Bindable var model = model
        NavigationStack {
            Form {
                // N-10: per-game levels plus Pause all.
                Section {
                    Toggle("Pause all", isOn: $model.data.pauseAll)
                    ForEach(model.libraryRows) { row in
                        Picker(row.game.name, selection: Binding(get: { model.notifyLevel(row.id) }, set: { model.setNotify(row.id, $0) })) {
                            ForEach(NotifyLevel.allCases) { Text($0.label).tag($0) }
                        }
                    }
                } header: {
                    Text("Notifications")
                } footer: {
                    Text(NotificationService.shared.authorization == .denied
                         ? "Notifications are off for \(Brand.name) in iOS Settings."
                         : "You're told when an update is live on PS5. Hotfixes arrive quietly.")
                }

                #if INTERNAL
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
                    Toggle("Quiet Unconfirmed alerts (V-4)", isOn: Binding(
                        get: { NotificationService.reportedAlertsEnabled },
                        set: { UserDefaults.standard.set($0, forKey: "reportedAlerts") }))
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
                #endif

                Section {
                    LabeledContent("Version", value: Self.version)
                        .accessibilityIdentifier("appVersion")
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
