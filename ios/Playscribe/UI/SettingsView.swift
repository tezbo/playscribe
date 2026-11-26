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
    /// Every pose but Closed: the title and Close sit in Settings' own header, not the navigation bar. Open landscape's
    /// trailing sheet showed no Close at all from the bar (Iris on #611, Mac 955129c8), so it carries its own, as Tabletop does.
    private var ownHeader: Bool { duo.pose != .closed }
    @Environment(\.duo) private var duo
    @Environment(\.colorScheme) private var scheme
    @AppStorage(YouTubeController.autoplayKey) private var autoplayVideos = false
    @AppStorage(VideoReflection.key) private var reflectionMode = VideoReflection.defaultOn
    @AppStorage(PushRegistrar.teamKey) private var teamAlerts = false
    @AppStorage(VideoReflection.idleKey) private var tallIdleReflection = false
    @State private var simGame: String = ""
    @State private var simKind: AppModel.SimKind = .major
    @State private var simDelay: Double = 10

    /// Quiet hours (0.5.0): off by default; the pickers sit inline in Tabletop, never a popover into the upper half.
    @ViewBuilder private var quietHoursRows: some View {
        let on = model.data.quietHours != nil
        Toggle("Quiet hours", isOn: Binding(get: { on }, set: { model.data.quietHours = $0 ? QuietHours() : nil }))
            .accessibilityValue(model.data.quietHours.map { "on, \($0.label)" } ?? "off")
            .frame(minHeight: 52)
            .accessibilityIdentifier("quietHours")
            // Tell the push relay when the window changes, so a push inside it is delivered passively.
            .onChange(of: model.data.quietHours) { _, new in if PushRegistrar.appCallsEnabled { PushRegistrar.syncQuietHours(new) } }
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
            VStack(spacing: 0) {
            // Tabletop: the title and Close sit in a plain header above the form, not in the navigation bar. With the bar,
            // rows scrolled up under it and a tap meant for a row (Video lab at std, y 527, Mac at c1c1191e) went to the bar
            // and closed Settings. Here the form starts below the header, so no row is ever under it or above the fold (G-4, TT-1).
            if ownHeader {
                PanelHeader(title: "Settings", close: dismiss)
            }
            Form {
                // Light: the app's cream (bg) behind surface cards, not the system grey and white (Iris, beta 4). Dark is unchanged.
                CardSections(rowFill: scheme == .light ? PlayscribeRole.surface : nil) {
                    // Tabletop's panel is half a screen: the build version leads, so it is on screen
                    // without scrolling (Terry checks it to verify the build).
                    if duo.pose == .tabletop {
                        Section { LabeledContent("Version", value: Self.version).accessibilityElement(children: .combine).accessibilityIdentifier("appVersion") }
                    }
                    // One default for every game (Terry, 0.2.0); a game's own setting lives on its bell.
                    Section {
                        // N-1: a way back after "Not now" or a denial, always one tap from Settings.
                        switch NotificationService.shared.authorization {
                        case .notDetermined:
                            Button("Turn on alerts") { Task { await NotificationService.shared.requestAuthorization() } }
                                .frame(minHeight: 52)
                                .accessibilityIdentifier("turnOnAlerts")
                        case .denied:
                            Button {
                                if let url = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(url) }
                            } label: {
                                // The arrow reads as a link out of the app (Iris).
                                HStack { Text("Open iOS Settings"); Spacer(minLength: 8); Image(systemName: "arrow.up.forward").font(PlayscribeFont.footnote) }
                            }
                            .frame(minHeight: 52)
                            .accessibilityIdentifier("openIOSSettings")
                        default: EmptyView()
                        }
                        Picker("Notify me about", selection: Binding(get: { model.notifyDefault }, set: { model.data.notifyDefault = $0 })) {
                            ForEach(NotifyLevel.allCases) { Text($0.label).tag($0) }
                        }
                        .opacity(NotificationService.shared.authorization == .denied ? 0.5 : 1)
                        let overrides = model.notifyOverrides
                        if !overrides.isEmpty {
                            NavigationLink("\(overrides.count) game\(overrides.count == 1 ? " has its" : "s have their") own setting") {
                                List(overrides, id: \.game.id) { o in
                                    LabeledContent(o.game.name, value: o.level.label)
                                }
                                .navigationTitle("Own settings")
                                .toolbar(.visible, for: .navigationBar)
                            }
                            .accessibilityIdentifier("settingsOwnSettings")
                        }
                    } header: {
                        Text("Notifications")
                    } footer: {
                        // The footer explains the row above it (0.5.1 spec 1).
                        // Said once (Quinn, Iris): the footer carries the denied message.
                        Text(NotificationService.shared.authorization == .denied
                             ? "Notifications are off for \(Brand.name) in iOS Settings."
                             : "Change a single game from the bell on its page.")
                    }
                    Section {
                        Toggle("Pause all", isOn: $model.data.pauseAll).frame(minHeight: 52)
                        quietHoursRows
                    } footer: {
                        if let q = model.data.quietHours {
                            // The relay honours the window too (#198), so the plain promise is true again.
                            Text(q.from == q.until
                                 ? "These hours are empty, so nothing is quiet. Choose different times, or turn quiet hours off."
                                 : "Alerts arrive silently during these hours.")
                        }
                    }
                    // 0.5.4, N-9: the follow list without alerts. Off until the player chooses; the copy is KeepCurrentCopy (Ezra).
                    Section {
                        Toggle(KeepCurrentCopy.settingsTitle, isOn: Binding(get: { model.data.keepCurrent == true }, set: { model.setKeepCurrent($0) }))
                            .frame(minHeight: 52)
                            .accessibilityValue(model.data.keepCurrent == true ? "on. \(KeepCurrentCopy.settingsOnVoiceOver)" : "off")
                            .accessibilityHint(KeepCurrentCopy.settingsHint)
                            .accessibilityIdentifier("keepCurrent")
                        NavigationLink(KeepCurrentCopy.whatIsSent) { KeepCurrentDetailsView().toolbar(.visible, for: .navigationBar) }
                            .frame(minHeight: 44)
                            .accessibilityIdentifier("keepCurrentWhatIsSent")
                    } header: {
                        Text("Keep my games up to date")
                    } footer: {
                        VStack(alignment: .leading, spacing: 6) {
                            Text(KeepCurrentCopy.settingsCaption)
                            // "Last sent: today", so you can see it working; nothing before the first follow is sent.
                            if model.data.keepCurrent == true, let line = KeepCurrentCopy.lastSent(PushRegistrar.keepCurrentLastSent) {
                                Text(line).accessibilityIdentifier("keepCurrentLastSent")
                            }
                        }
                    }
                    Section {
                        // Not everyone has PS Plus: the Library card is on by default and can be hidden. Off also stops the reminder.
                        Toggle("PS Plus card in Library", isOn: Binding(get: { model.data.plusCardOff != true }, set: { model.data.plusCardOff = $0 ? nil : true }))
                            .frame(minHeight: 52)
                            .accessibilityHint("Shows this month’s PS Plus games in the Library, with a reminder before they leave")
                            .accessibilityIdentifier("plusCardToggle")
                            .onChange(of: model.data.plusCardOff) { _, _ in NotificationService.shared.syncPlusLeavingSoon() }
                        // Shown only while a PS Plus month exists and the card is on, the same condition as the Library card.
                        if model.data.plusCardOff != true, PlusLogic.current(PlusStore.shared.months) != nil {
                            // PS Plus: a reminder in the last three days a month's games can be claimed.
                            Toggle(isOn: Binding(get: { model.data.plusLeavingSoonOff != true }, set: { model.data.plusLeavingSoonOff = $0 ? nil : true })) {
                                VStack(alignment: .leading, spacing: 6) {
                                    PlusBadge(height: 20)
                                    Text("Games leaving soon")
                                }
                                .frame(minHeight: 52, alignment: .leading)
                            }
                                .accessibilityLabel("PS Plus games leaving soon")
                                .accessibilityHint("A reminder in the last three days before this month’s PS Plus games leave")
                                .accessibilityIdentifier("plusLeavingSoon")
                                .onChange(of: model.data.plusLeavingSoonOff) { _, _ in NotificationService.shared.syncPlusLeavingSoon() }
                                .onChange(of: model.data.pauseAll) { _, _ in NotificationService.shared.syncPlusLeavingSoon() }
                        }
                    } footer: {
                        Text("PS Plus reminders are separate from game notifications.")
                    }
                    Section {
                        Picker("Appearance", selection: Binding(get: { model.data.appearance ?? .system },
                                                                set: { model.data.appearance = $0 == .system ? nil : $0 })) {
                            ForEach(AppAppearance.allCases) { Text($0.title).tag($0) }
                        }
                        .frame(minHeight: 52)
                        .accessibilityIdentifier("appearance")
                    } footer: {
                        Text("System follows your phone’s Light and Dark setting. The video player and the cover stay dark.")
                    }
                    Section {
                        Toggle("Sounds", isOn: Binding(get: { model.data.soundsOff != true }, set: { model.data.soundsOff = $0 ? nil : true }))
                            .frame(minHeight: 52)
                            .accessibilityHint("Plays a soft pop when games are added")
                            .accessibilityIdentifier("sounds")
                    } footer: {
                        Text("A soft pop when you add games. Never plays while you are listening to something else.")
                    }

                    // 6b: the tour never replays by itself; this is the way back to it.
                    Section {
                        Button {
                            dismiss()
                            // Once the sheet or panel has gone, so step 1 lands on the Library, not under Settings.
                            Task { @MainActor in
                                try? await Task.sleep(for: .milliseconds(400))
                                model.startTour()
                            }
                        } label: {
                            Text(TourCopy.replay).frame(maxWidth: .infinity, minHeight: 52, alignment: .leading).contentShape(Rectangle())
                        }
                        .accessibilityLabel("\(TourCopy.replay), starts the tour again")
                        .accessibilityIdentifier("replayTour")
                        .tappableFrame()
                    } footer: {
                        Text(TourCopy.replayFooter)
                    }

                    Section {
                        Toggle("Autoplay videos", isOn: $autoplayVideos).frame(minHeight: 52)
                            .accessibilityHint("Videos start as soon as they open. Off when Reduce Motion is on.")
                        Toggle("Reflection mode", isOn: $reflectionMode).frame(minHeight: 52)
                            .accessibilityHint("A soft mirror of the video under the controls when the Duo stands folded. Off when Reduce Motion or Reduce Transparency is on.")
                    } header: {
                        Text("Video")
                    } footer: {
                        Text("Trailers and update videos start as soon as they open. Reflection mode mirrors the playing video under the controls when the Duo stands folded like a laptop. With Reduce Motion on, videos never start on their own and there’s no mirror.")
                    }

                    #if INTERNAL
                    // Next to Video, so it is a short scroll at the default size (Mac at 6bc9f703: below the team sections it was
                    // hard to reach). TestFlight and development builds only.
                    if BuildChannel.showsTeamAlerts {
                    // Iris's idle-band variant, for Terry to compare on his Duo (21 Nov). TestFlight and development builds only.
                    Section {
                        Toggle("Taller reflection while controls are hidden", isOn: $tallIdleReflection)
                            .frame(minHeight: 52)
                            .accessibilityIdentifier("tallIdleReflection")
                    } header: {
                        Text("Video lab (TestFlight and development builds)")
                    } footer: {
                        Text("In Tabletop, while a video plays and its controls have faded, the reflection grows to about twice its height. It returns to normal when the controls show.")
                    }
                    }
                    #endif

                    // 0.7 front cover (duo-closed-cover): internal preview only until the Library wraps it.
                    CoverMotionSection()

                    #if INTERNAL
                    if BuildChannel.showsTeamAlerts {
                    Section {
                        Toggle("Team alerts", isOn: $teamAlerts)
                            .frame(minHeight: 52)
                            .accessibilityIdentifier("teamAlerts")
                            .onChange(of: teamAlerts) { _, on in if PushRegistrar.appCallsEnabled { PushRegistrar.syncTeam(on) } }
                    } header: {
                        Text("Team alerts (TestFlight and development builds)")
                    } footer: {
                        Text("Also receive the team’s test notifications from the push relay. Off by default; it never appears in an App Store build.")
                    }

                    }
                    #endif

                    #if INTERNAL
                    if BuildChannel.showsInternalTools {
                    Section {
                        Picker("Game", selection: $simGame) {
                            ForEach(model.libraryRows) { Text($0.game.name.gluingTrailingNumeral).tag($0.id) }
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
                        // The app's pose, from the root container: a sheet is outside the reader, so its own `duo` is the default (closed).
                        LabeledContent("Pose", value: model.livePose.label)
                        if let token = NotificationService.shared.deviceToken {
                            LabeledContent("APNs token", value: String(token.prefix(12)) + "…")
                        }
                    }
                    }
                    #endif

                    Section {
                        if duo.pose != .tabletop {
                            LabeledContent("Version", value: Self.version)
                                .accessibilityElement(children: .combine)
                                .accessibilityIdentifier("appVersion")
                        }
                    } footer: {
                        VStack(alignment: .leading, spacing: 12) {
                            // s-06-brand-swap: the Warm refresh mark signs off the page, lit while an update is unread.
                            SettingsSignature(lit: BrandMark.isLit(totalUnread: model.totalUnread))
                            Text("Artwork and trailers belong to their publishers. \(Brand.trademarkNotice)")
                                // The form's last line: the UI tests scroll to it to prove every row above is reachable.
                                .accessibilityIdentifier("settingsLastLine")
                        }
                    }
                }
            }
            // 24 pt between a footer and the next section's title (Iris, 0.5.1 spec 1).
            .listSectionSpacing(24)
            // Tabletop: the page surface under the rows, the same as the header above, so there is no seam (Iris, #556).
            .scrollContentBackground(ownHeader || scheme == .light ? .hidden : .automatic)
            .navigationTitle("Settings")
            .toolbarTitleDisplayMode(.inline)
            // The root page has its own header (above) outside Closed; pushed pages show the bar again for Back.
            .toolbar(ownHeader ? .hidden : .automatic, for: .navigationBar)
            .toolbar {
                if !ownHeader {
                    ToolbarItem(placement: .cancellationAction) {
                        Button { dismiss() } label: {
                            Label("Close", systemImage: "xmark").labelStyle(.iconOnly)
                                .frame(minWidth: 44, minHeight: 44).contentShape(Rectangle())
                        }
                    }
                }
            }
            .onAppear { if simGame.isEmpty { simGame = model.libraryRows.first?.id ?? "" } }
            // 0.7 front cover preview (internal): opened by -qaRoute cover or the button in the cover section.
            .frontCoverPreview()
            }
            .background(PlayscribeRole.bg)
        }
        .presentationPlacement(duo.pose == .closed ? .automatic : .trailing)
    }
}

/// Tabletop's lower-half panels: the title and Close in a plain row above the content, so nothing scrolls under them.
/// Close is a 44 pt target at top trailing, clear of the rail (0.5.1 spec 1).
struct PanelHeader: View {
    var title: String
    var close: () -> Void

    var body: some View {
        ZStack {
            Text(title).font(PlayscribeFont.headline)
                .lineLimit(1).minimumScaleFactor(0.7)
                .padding(.horizontal, 64)
                .accessibilityAddTraits(.isHeader)
            HStack {
                Spacer()
                Button(action: close) {
                    Label("Close", systemImage: "xmark").labelStyle(.iconOnly)
                        .font(PlayscribeFont.headline)
                        .foregroundStyle(PlayscribeRole.action)
                        .frame(width: 44, height: 44)
                        .background(Circle().fill(PlayscribeRole.chipFill))
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Close")
                .accessibilityIdentifier("panelClose")
                // 20 pt, the form rows' own inset, so Close ends where the rows do (x 593 in the sim), well clear of the rail.
                .padding(.trailing, 20)
            }
        }
        .frame(minHeight: 60)
        .padding(.top, 6)
        .background(PlayscribeRole.bg)
    }
}

/// The Settings footer's lockup (s-06-brand-swap): the mark beside the name, scaling with the text like the cover lockup.
struct SettingsSignature: View {
    var lit: Bool
    @ScaledMetric(relativeTo: .footnote) private var glyph: CGFloat = 28
    var body: some View {
        HStack(spacing: 8) {
            BrandMark(size: min(glyph, 56), lit: lit)
            Text(Brand.name).font(PlayscribeFont.subheadline.weight(.semibold)).foregroundStyle(PlayscribeRole.textPrimary)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Brand.name)
        .accessibilityIdentifier("settingsSignature")
    }
}
