import SwiftUI

/// Add a game (A-1 to A-9). Manual add only: PlayStation account import is a later milestone and
/// nothing here asks for credentials.
struct AddGameSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var systemDismiss
    @Environment(\.panelClose) private var panelClose
    /// In Tabletop the sheet is the lower-half panel, which is not presented, so it closes itself.
    private func dismiss() { if let panelClose { panelClose() } else { systemDismiss() } }
    @Environment(\.duo) private var duo
    @State private var status: OwnershipStatus = .owned
    @State private var query = ""
    @State private var debounced = ""
    /// Tabletop: first-letter filter instead of typing (the keyboard never opens there).
    @State private var letter: String?
    @State private var hintShown = false
    @State private var custom = false
    @State private var customName = ""
    @State private var customPlatform: Platform = .ps5
    /// GR-7: games picked so far; kept while the query changes.
    @State private var picked: [String: CatalogGame] = [:]
    @State private var pickOrder: [String] = []
    /// nil shows the entry sheet; `matches` non-nil shows the shared results list.
    @State private var method: AddMethod?
    @State private var matches: [AddMatch]?
    /// Keyboard height while it is up (Iris, 0.5.0 Tabletop sheets: if the lower half minus the
    /// keyboard leaves under 200 pt, hide the title and keep Done and search only).
    @State private var keyboardHeight: CGFloat = 0
    @FocusState private var searchFocused: Bool
    /// TEMPORARY (v0.5.3 testPinnedAddBar diagnosis, remove with the fix): one ADDFOCUS line per event.
    @State private var focusProbe = ""
    @State private var focusGainedAt = Date.distantPast
    @State private var reasserts = 0
    private func probe(_ event: String) {
        let fr = AddFocusProbe.firstResponder()
        let line = "ADDFOCUS \(event) focused=\(searchFocused) firstResponder=\(fr) placement=\(AddFocusProbe.placementName(duo.pose)) pose=\(duo.pose) landscape=\(duo.isLandscape)"
        NSLog("%@", line)
        focusProbe = line
    }
    private var titleHidden: Bool {
        guard duo.pose == .tabletop, keyboardHeight > 0 else { return false }
        let lowerHalf = duo.size.height - (duo.division?.maxY ?? duo.size.height / 2)
        return lowerHalf - keyboardHeight < 200
    }

    var body: some View {
        NavigationStack {
            Group {
                if custom { customForm }
                else if let matches {
                    AddResultsView(matches: matches, status: status, picked: picked, toggle: tap) { self.matches = nil }
                } else if let method {
                    switch method {
                    case .typeIt: list
                    case .sayIt: SayItView(find: { showMatches(AddMatcher.titles(from: $0)) }, typeInstead: { self.method = .typeIt })
                    case .camera: CameraAddView(find: { showMatches($0, sureOnly: true) }, typeInstead: { self.method = .typeIt }, photoInstead: { self.method = .photo })
                    case .photo: PhotoAddView(find: { showMatches($0, sureOnly: true) }, typeInstead: { self.method = .typeIt })
                    default: list
                    }
                } else { AddEntryView { method = $0 } }
            }
            .onAppear {
                if let m = model.addSheetMethod { method = m; model.addSheetMethod = nil }
                if model.addSearchFocus {
                    model.addSearchFocus = false
                    // The field appears only after the method switch above, and in Open portrait the sheet is still settling at 600 ms
                    // (7161347 gate: the one request was lost, the field never took focus). Ask again until it holds, up to 5 s.
                    Task {
                        for i in 0..<10 {
                            try? await Task.sleep(for: .milliseconds(500))
                            probe("route-try\(i)")
                            if searchFocused { break }
                            searchFocused = true
                        }
                    }
                }
            }
            .onAppear { probe("sheet-onAppear") }
            .onDisappear { probe("sheet-onDisappear") }
            .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardDidShowNotification)) { _ in probe("kb-didShow") }
            .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardDidHideNotification)) { _ in probe("kb-didHide") }
            .onReceive(NotificationCenter.default.publisher(for: UITextField.textDidEndEditingNotification)) { _ in probe("textfield-endEditing") }
            .onReceive(NotificationCenter.default.publisher(for: UIApplication.willResignActiveNotification)) { _ in probe("app-willResignActive") }
            .onReceive(NotificationCenter.default.publisher(for: UIWindow.didBecomeKeyNotification)) { _ in probe("window-didBecomeKey") }
            .onReceive(NotificationCenter.default.publisher(for: UIWindow.didResignKeyNotification)) { _ in probe("window-didResignKey") }
            .navigationTitle(titleHidden || duo.pose == .tabletop ? "" : sheetTitle)
            .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillChangeFrameNotification)) { note in
                let end = (note.userInfo?[UIResponder.keyboardFrameEndUserInfoKey] as? CGRect) ?? .zero
                keyboardHeight = end.minY >= UIScreen.main.bounds.height ? 0 : end.height
            }
            .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillHideNotification)) { _ in keyboardHeight = 0 }
            .toolbarTitleDisplayMode(.inline)
            // Tabletop (0.2.0 gate): the empty nav bar cost about 100 pt of the lower half, so the
            // bar is hidden and Close sits in the search row instead; three rows then fit.
            .toolbar(duo.pose == .tabletop && !custom ? .hidden : .automatic, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    if duo.pose == .tabletop {
                        Button { dismiss() } label: { Text("Done").frame(minWidth: 44, minHeight: 44).contentShape(Rectangle()) }.accessibilityIdentifier("close")
                    } else {
                        Button { dismiss() } label: { Label("Close", systemImage: "xmark") }
                    }
                }
                if method != nil && !custom {
                    ToolbarItem(placement: .navigation) {
                        Button { if matches != nil { matches = nil } else { method = nil } } label: { Label("Back", systemImage: "chevron.backward") }
                    }
                }
            }
            .safeAreaInset(edge: .top, spacing: 0) { tabletopHeader }
            // One confirm bar pinned to the bottom of the sheet (Terry, 0.2.0): no scrolling back
            // up to add. The sheet's bottom is the lower half in Tabletop and clear of the hinge.
            .safeAreaInset(edge: .bottom) {
                if !picked.isEmpty && !custom {
                    Button(action: addPicked) {
                        Text("Add \(picked.count) game\(picked.count == 1 ? "" : "s")")
                            .font(PlayscribeFont.headline)
                            .foregroundStyle(PlayscribeColor.onAccent)
                            .frame(maxWidth: .infinity, minHeight: 56)
                            .background(PlayscribeColor.accent, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("addPicked")
                    .padding(.horizontal, 16)
                    // Tabletop (Iris): 56 pt button in a 72 pt strip pinned to the bottom of the panel.
                    .frame(minHeight: 72)
                    .background(.bar)
                    .tappableFrame()
                }
            }
        }
        // Trailing placement on the inner display keeps the sheet's bar vertical and in the
        // lower-trailing region when folded; the outer display uses the system default.
        .presentationPlacement(AddFocusProbe.automatic(duo.pose) ? .automatic : .trailing)
        .overlay(alignment: .bottomLeading) {
            if AddFocusProbe.enabled {
                Text(focusProbe).font(.system(size: 9, design: .monospaced)).padding(2).background(.yellow).foregroundStyle(.black)
                    .accessibilityIdentifier("addFocusProbe").allowsHitTesting(false)
            }
        }
        .task(id: query) {
            try? await Task.sleep(for: .milliseconds(250))
            if !Task.isCancelled { debounced = query }
        }
    }

    private var sheetTitle: String {
        custom ? "Add your own game" : matches != nil ? "Found games" : method == nil ? "Add games" : method!.title
    }

    /// Tabletop (Quinn, Iris, ca940e5): the nav bar is hidden to keep the lower half roomy, so the
    /// title, Back and Close live in this row: 24 pt under the fold band, Close 44 pt at the
    /// trailing edge. Nothing here is above the fold (G-4).
    @ViewBuilder private var tabletopHeader: some View {
        if duo.pose == .tabletop && !custom {
            HStack(spacing: 8) {
                if method != nil {
                    Button { if matches != nil { matches = nil } else { method = nil } } label: {
                        Image(systemName: "chevron.backward").frame(minWidth: 44, minHeight: 44).contentShape(Rectangle())
                    }
                    .accessibilityLabel("Back")
                    .accessibilityIdentifier("back")
                    .tappableFrame()
                }
                if !titleHidden { Text(sheetTitle).font(PlayscribeFont.title3).lineLimit(1) }
                Spacer(minLength: 0)
                Button { dismiss() } label: {
                    Image(systemName: "xmark").frame(minWidth: 44, minHeight: 44).contentShape(Rectangle())
                }
                .accessibilityLabel("Close")
                .accessibilityIdentifier("close")
                .tappableFrame()
            }
            .padding(.horizontal, 16)
            .frame(height: 56)
            .background(Color.ink0)
        }
    }

    private var statusPicker: some View {
        Picker("Add as", selection: $status) {
            ForEach(OwnershipStatus.allCases) { Text($0.label).tag($0) }
        }
        .pickerStyle(.segmented)
    }

    /// A-3: one row per IGDB id; the curated record (with art) wins; added games go last.
    private var results: [CatalogGame] {
        if duo.pose == .tabletop, let letter {
            let all = PS5Index.shared.titles(startingWith: letter)
            return all.filter { model.entry($0.id) == nil } + all.filter { model.entry($0.id) != nil }
        }
        let q = debounced.trimmingCharacters(in: .whitespaces)
        let curated = model.fixtures.games
        let curatedByIGDB = Dictionary(curated.compactMap { g in g.igdbID.map { ($0, g) } }, uniquingKeysWith: { a, _ in a })
        var seen = Set<String>()
        var seenIGDB = Set<Int>()
        var out: [CatalogGame] = []
        func take(_ g: CatalogGame) {
            let g = g.igdbID.flatMap { curatedByIGDB[$0] } ?? g
            if seen.contains(g.id) { return }
            if let i = g.igdbID, seenIGDB.contains(i) { return }
            seen.insert(g.id)
            if let i = g.igdbID { seenIGDB.insert(i) }
            out.append(g)
        }
        if q.count >= 2 {
            curated.filter { PS5Index.fold($0.name).contains(PS5Index.fold(q)) }.forEach(take)
            PS5Index.shared.search(q).forEach(take)
            return out.filter { model.entry($0.id) == nil } + out.filter { model.entry($0.id) != nil }
        }
        // Popular on PS5, excluding games already in the library (A-2).
        PS5Index.shared.popular(limit: 40).forEach(take)
        return Array(out.filter { model.entry($0.id) == nil }.prefix(20))
    }

    private var list: some View {
        List {
            Section {
                if duo.pose == .tabletop {
                    // Tabletop (0.2.0 gate): the status control sits beside the search field in one row so
                    // at least three results stay visible in the lower half.
                    VStack(alignment: .leading, spacing: 4) {
                        HStack(spacing: 8) {
                            Button { dismiss() } label: {
                                Image(systemName: "xmark").font(PlayscribeFont.headline)
                                    .frame(width: 44, height: 44).contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            .foregroundStyle(PlayscribeColor.accent)
                            .accessibilityLabel("Close")
                            .tappableFrame()
                            Picker("Add as", selection: $status) {
                                ForEach(OwnershipStatus.allCases) { Text($0.label).tag($0) }
                            }
                            .pickerStyle(.menu)
                            .fixedSize()
                            .frame(minHeight: 44)
                            TabletopSearchButton(letter: letter, prompt: "Search PS5 games", hintShown: $hintShown)
                        }
                        TabletopSearchHint(shown: hintShown)
                        TabletopLetterStrip(letter: $letter)
                    }
                    .listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 4, trailing: 16))
                } else {
                    statusPicker
                    TextField("Search \(PS5Index.shared.count.formatted()) PS5 games", text: $query)
                        .autocorrectionDisabled()
                        .submitLabel(.search)
                        .focused($searchFocused)
                        .frame(minHeight: 44)
                        // The whole 44 pt row asks for focus, not only the glyphs: a tap in the row's padding did nothing.
                        .contentShape(Rectangle())
                        .onTapGesture {
                            probe("tap-before")
                            searchFocused = true
                            Task { @MainActor in
                                for ms in [100, 600] { try? await Task.sleep(for: .milliseconds(ms)); probe("tap-after\(ms)ms") }
                            }
                        }
                        .onChange(of: searchFocused) { _, now in
                            probe("focus-changed-\(now)")
                            if now { focusGainedAt = Date(); return }
                            // Open portrait (4e6e38c Mac log): focus is resigned ~1.2 s after it is gained, by something other than the user.
                            // If nothing else holds the keyboard and the loss is that early, ask again (at most 3 times a sheet).
                            guard Date().timeIntervalSince(focusGainedAt) < 3, reasserts < 3, AddFocusProbe.firstResponder() == "none" else { return }
                            reasserts += 1
                            Task { @MainActor in
                                try? await Task.sleep(for: .milliseconds(200))
                                probe("reassert\(reasserts)")
                                searchFocused = true
                            }
                        }
                }
                // Offline state 7: rows keep their placeholder covers; say why.
                if case .failed(offline: true) = model.checkState {
                    Label("Covers need a connection", systemImage: "wifi.slash")
                        .font(PlayscribeFont.footnote).foregroundStyle(.secondary)
                }
            }
            let rows = results
            Section(letter != nil && duo.pose == .tabletop ? "Starting with \(letter ?? "")" : debounced.count >= 2 ? "Best matches" : "Popular on PS5") {
                if rows.isEmpty {
                    Text("No PS5 game matches '\(debounced)'").foregroundStyle(.secondary)
                    Button("Add '\(debounced)' yourself") { customName = debounced; custom = true }.hitTarget()
                }
                ForEach(rows) { g in AddRow(game: g, status: status, selected: picked[g.id] != nil) { tap(g) } }
            }
            Section {
                Button { customName = query; custom = true } label: {
                    Label("Add a game that isn't listed", systemImage: "plus")
                }
                .hitTarget()
            } footer: {
                Text("PlayStation account import is planned for a later version. \(Brand.name) never asks for your PlayStation password.")
            }
        }
    }

    private var customForm: some View {
        Form {
            Section { statusPicker }
            Section {
                TextField("Game name", text: $customName).frame(minHeight: 44)
                Picker("Platform", selection: $customPlatform) {
                    ForEach([Platform.ps5, .xboxSeries, .switch2, .pc], id: \.self) { Text($0.label).tag($0) }
                }
            } footer: {
                Text("\(Brand.name) won't invent patch information for this game. Its journal stays empty until coverage exists.")
            }
            Section {
                Button("Add as \(status.label)") {
                    let name = customName.trimmingCharacters(in: .whitespaces)
                    add(CatalogGame(id: "custom-\(Int(Date.now.timeIntervalSince1970))", name: name, platforms: [customPlatform],
                                    coverage: .none, custom: true))
                }
                .disabled(customName.trimmingCharacters(in: .whitespaces).isEmpty)
                Button("Back to list") { custom = false }
            }
        }
    }

    /// Every method lands here: sure matches not yet in the library are pre-ticked, the rest wait.
    /// `sureOnly` (photos): a picture is full of other words, so unsure lines are dropped unless
    /// nothing at all matched.
    private func showMatches(_ titles: [String], sureOnly: Bool = false) {
        var found = AddMatcher.match(titles, curated: model.fixtures.games)
        if sureOnly, found.contains(where: \.sure) { found = found.filter(\.sure) }
        for m in found { if let g = m.best, model.entry(g.id) == nil, picked[g.id] == nil { toggle(g) } }
        matches = found
        if found.isEmpty { Haptics.warning() }
    }

    private func add(_ g: CatalogGame) {
        model.addGame(g, status: status)
        dismiss()
    }

    /// A person's own tick (not the pre-ticked sure matches).
    private func tap(_ g: CatalogGame) { Haptics.selection(); toggle(g) }

    private func toggle(_ g: CatalogGame) {
        if picked[g.id] != nil { picked[g.id] = nil; pickOrder.removeAll { $0 == g.id } } else { picked[g.id] = g; pickOrder.append(g.id) }
    }

    private func addPicked() {
        model.addGames(pickOrder.compactMap { picked[$0] }, status: status)
        dismiss()
    }
}

struct AddRow: View {
    @Environment(AppModel.self) private var model
    var game: CatalogGame
    var status: OwnershipStatus
    var selected = false
    var onAdd: () -> Void

    var body: some View {
        let added = model.entry(game.id) != nil
        Button(action: onAdd) {
            HStack(spacing: 12) {
                // One mark per row: the circle on the right becomes a tick (no badge on the cover).
                CoverView(game: game, cornerRadius: 4).frame(width: 40)
                VStack(alignment: .leading, spacing: 2) {
                    Text(game.name).font(PlayscribeFont.subheadline.weight(.semibold)).fixedSize(horizontal: false, vertical: true)
                    Text(added ? "In library" : subtitle).font(PlayscribeFont.caption).foregroundStyle(.secondary)
                }
                Spacer(minLength: 8)
                Image(systemName: added ? "checkmark" : selected ? "checkmark.circle.fill" : "circle")
                    .font(.title3)
                    .foregroundStyle(added ? .secondary : PlayscribeColor.accent)
                    .frame(width: 44, height: 44)
            }
            .frame(minHeight: 64)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(added)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(added ? "\(game.name), in your library" : "\(game.name), \(subtitle)")
        .accessibilityIdentifier("addRow")
        .accessibilityAddTraits(selected ? [.isButton, .isSelected] : .isButton)
        .tappableFrame()
    }

    private var subtitle: String {
        switch game.coverage {
        case .full: "Full PS5 update coverage"
        case .partial: "Latest official posts"
        case .none: game.ps5DateLine ?? "Release date TBA"
        }
    }
}

/// F-1: the empty Library is the onboarding screen.
/// First run (Iris, 0.2.0): never blank. The brand's header art, one line on what Playscribe does,
/// one ember button and six popular PS5 games to tap. Tabletop: art and headline on the standing
/// half (display only), the button and covers on the flat half.
struct OnboardingView: View {
    @Environment(\.duo) private var duo
    @Environment(\.railWidth) private var railWidth

    /// Content width of the left page in Book (clear of the fold), nil in other poses.
    private var pageWidth: CGFloat? {
        guard duo.pose == .book, let fold = duo.division else { return nil }
        return max(0, fold.minX - 24 - 32)
    }

    var body: some View {
        if duo.pose == .tabletop {
            ArrangementView {
                OnboardingStage().allowsHitTesting(false)
            } secondary: {
                // The trailing rail sits over the lower half: keep the actions clear of it (0.2.0 gate).
                ScrollView { OnboardingActions().padding(16) }
                    .contentMargins(.trailing, railWidth, for: .scrollContent)
            }
            .arrangementViewStyle(.split)
        } else {
            HStack(alignment: .top, spacing: 0) {
                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        OnboardingStage().frame(height: duo.pose == .closed ? 220 : 280)
                        OnboardingActions(pageWidth: pageWidth, bookLeft: pageWidth != nil).padding(.horizontal, 16)
                    }
                    .padding(.bottom, 24)
                }
                // Book: one page wide, so nothing crosses the fold (0.2.0 gate, first-run Library).
                .frame(width: pageWidth.map { $0 + 32 })
                if let fold = duo.division, duo.pose == .book {
                    // The right page is never blank (Iris, book-first-run): Popular on PS5 as a grid,
                    // 24 pt clear of the hinge.
                    let start = fold.maxX + 24
                    let width = max(0, duo.size.width - railWidth - start - 16)
                    OnboardingRightPage(width: width)
                        .frame(width: width)
                        .padding(.leading, max(0, start - (fold.minX - 24 - 32 + 32)))
                    Spacer(minLength: 0)
                } else {
                    Spacer(minLength: 0)
                }
            }
            .overlay(alignment: .topLeading) {
                if FoldAuditSwitch.enabled {
                    let fold = duo.division.map { "fold \(Int($0.minX))-\(Int($0.maxX))" } ?? "no fold"
                    let label = "library-duo pose: \(duo.pose.rawValue); \(fold); width \(Int(duo.size.width)); onboarding page \(Int(pageWidth ?? -1))"
                    Text(label).font(.system(size: 1)).opacity(0.01).allowsHitTesting(false)
                        .accessibilityIdentifier("libraryDuo").accessibilityLabel(label)
                }
            }
        }
    }
}

struct OnboardingStage: View {
    @Environment(AppModel.self) private var model
    private var welcomeDone: Bool { model.data.welcomeDone ?? false }
    @Environment(\.duo) private var duo
    /// The stage's bottom edge in screen space, before any clearance is applied.
    @State private var bottom: CGFloat = 0

    /// Tabletop: the stage ends at least 24 pt above the division band, never across it (the
    /// headline's accessibility frame is the stage, so the stage itself must clear). The frame is
    /// read in screen space: the old local-height check ignored the stage's own top offset (0.2.0 gate).
    private var clearance: CGFloat {
        guard duo.pose == .tabletop, let d = duo.division, bottom > 0 else { return 0 }
        return max(0, bottom - (d.minY - 24))
    }

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            ArtView(asset: nil, game: nil)
            LinearGradient(colors: [.clear, .black.opacity(0.7)], startPoint: .center, endPoint: .bottom)
            Text(welcomeDone ? "Follow a game to get its PS5 patch notes in one place." : "Add your games to see every update")
                .font(PlayscribeFont.title)
                .foregroundStyle(PlayscribeColor.textPrimary)
                .padding(20)
        }
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .accessibilityElement(children: .combine)
        .padding(.bottom, clearance)
        .onGeometryChange(for: CGFloat.self) { $0.frame(in: .global).maxY } action: { new in
            // The padding shrinks the stage inside this frame, so the frame's bottom is unchanged.
            bottom = new
        }
        .padding(.horizontal, 16)
    }
}

struct OnboardingActions: View {
    @Environment(AppModel.self) private var model
    @Environment(\.duo) private var duo
    /// Book: the width of one page; only whole covers that fit are shown.
    var pageWidth: CGFloat?
    /// Book left page: the covers and the footer move to the right page.
    var bookLeft = false

    var body: some View {
        if !(model.data.welcomeDone ?? false) {
            welcome
        } else {
            plain
        }
    }

    /// 0.5.0 guided welcome (first run only): the four ways to add, then Skip for now.
    private var welcome: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Tell Playscribe what you play and it keeps every update in one place.")
                .font(PlayscribeFont.body).foregroundStyle(.secondary)
            ForEach(AddMethod.available) { m in
                Button {
                    model.data.welcomeDone = true
                    model.addSheetMethod = m
                    model.addSheetOpen = true
                } label: {
                    HStack(spacing: 14) {
                        Image(systemName: m.symbol).font(.title3).frame(width: 32)
                            .foregroundStyle(PlayscribeColor.accent)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(m.title).font(PlayscribeFont.headline)
                            Text(m.detail).font(PlayscribeFont.footnote).foregroundStyle(.secondary)
                        }
                        Spacer(minLength: 0)
                    }
                    .frame(maxWidth: .infinity, minHeight: 52, alignment: .leading)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("\(m.title), \(m.detail.lowercasedFirst)")
                .tappableFrame()
            }
            Button("Skip for now") { model.data.welcomeDone = true }
                .font(PlayscribeFont.headline)
                .frame(maxWidth: .infinity, minHeight: 44)
                .accessibilityHint("Goes to your empty Library")
                .tappableFrame()
        }
    }

    private var plain: some View {
        VStack(alignment: .leading, spacing: 16) {
            Button { model.addSheetOpen = true } label: {
                Text("Add your first game")
                    .font(PlayscribeFont.headline)
                    .foregroundStyle(PlayscribeColor.onAccent)
                    .frame(maxWidth: .infinity, minHeight: 52)
                    .background(PlayscribeColor.accent, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            }
            .buttonStyle(.plain)
            .tappableFrame()
            if !bookLeft { Text("Popular on PS5").font(PlayscribeFont.headline) }
            let size: CGFloat = duo.pose == .closed ? 96 : 108
            let fit = pageWidth.map { max(1, Int(($0 + 10) / (size + 10))) } ?? 6
            if !bookLeft {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    ForEach(PS5Index.shared.popular(limit: fit)) { g in
                        Button { model.addGame(g, status: .owned) } label: {
                            TileCover(game: g).frame(width: size, height: (size * 4 / 3).rounded())
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Add \(g.name)")
                        .tappableFrame()
                    }
                }
            }
            .edgeFade(40)
            Text("PlayStation account import is planned for a later version.")
                .font(PlayscribeFont.footnote).foregroundStyle(.secondary)
            }
        }
    }
}

/// Book first-run, right page: Popular on PS5 as a 3-column grid of 3:4 tiles (10 pt gap), scrolling,
/// with the account-import line at the foot. Tapping a cover adds it, as the strip does elsewhere.
struct OnboardingRightPage: View {
    @Environment(AppModel.self) private var model
    var width: CGFloat

    var body: some View {
        let tile = max(40, ((width - 20) / 3).rounded(.down))
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                Text("Popular on PS5").font(PlayscribeFont.title3)
                LazyVGrid(columns: Array(repeating: GridItem(.fixed(tile), spacing: 10, alignment: .top), count: 3), alignment: .leading, spacing: 10) {
                    ForEach(PS5Index.shared.popular(limit: 18)) { g in
                        Button { model.addGame(g, status: .owned) } label: {
                            TileCover(game: g).frame(width: tile, height: (tile * 4 / 3).rounded())
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Add \(g.name)")
                        .tappableFrame()
                    }
                }
                Text("PlayStation account import is planned for a later version.")
                    .font(PlayscribeFont.footnote).foregroundStyle(.secondary)
            }
            .padding(.top, 16).padding(.bottom, 24)
        }
        .scrollIndicators(.hidden)
    }
}


/// TEMPORARY diagnosis aid (v0.5.3, testPinnedAddBar in Open portrait). Launch with `-addFocusProbe` to see and log
/// where the add search loses focus, and add `-addPlacementAutomatic` to take `.presentationPlacement(.trailing)` out.
enum AddFocusProbe {
    static var enabled: Bool { ProcessInfo.processInfo.arguments.contains("-addFocusProbe") }
    static func automatic(_ pose: Pose) -> Bool {
        pose == .closed || ProcessInfo.processInfo.arguments.contains("-addPlacementAutomatic")
    }
    static func placementName(_ pose: Pose) -> String { automatic(pose) ? "automatic" : "trailing" }
    static func firstResponder() -> String {
        let windows = UIApplication.shared.connectedScenes.compactMap { ($0 as? UIWindowScene)?.windows }.flatMap { $0 }
        func find(_ v: UIView) -> UIView? { v.isFirstResponder ? v : v.subviews.lazy.compactMap(find).first }
        for w in windows { if let r = find(w) { return "\(type(of: r))" } }
        return "none"
    }
}
