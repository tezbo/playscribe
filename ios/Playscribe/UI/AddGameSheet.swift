import SwiftUI

/// Add a game (A-1 to A-9). Manual add only: PlayStation account import is a later milestone and
/// nothing here asks for credentials.
struct AddGameSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @Environment(\.duo) private var duo
    @State private var status: OwnershipStatus = .owned
    @State private var query = ""
    @State private var debounced = ""
    @State private var custom = false
    @State private var customName = ""
    @State private var customPlatform: Platform = .ps5
    /// GR-7: games picked so far; kept while the query changes.
    @State private var picked: [String: CatalogGame] = [:]
    @State private var pickOrder: [String] = []

    var body: some View {
        NavigationStack {
            Group {
                if custom { customForm } else { list }
            }
            .navigationTitle(custom ? "Add your own game" : "Add game")
            .toolbarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button { dismiss() } label: { Label("Close", systemImage: "xmark") }
                }
            }
            // One confirm bar pinned to the bottom of the sheet (Terry, 0.2.0): no scrolling back
            // up to add. The sheet's bottom is the lower half in Tabletop and clear of the hinge.
            .safeAreaInset(edge: .bottom) {
                if !picked.isEmpty && !custom {
                    Button(action: addPicked) {
                        Text("Add \(picked.count) game\(picked.count == 1 ? "" : "s")")
                            .font(PlayscribeFont.headline)
                            .foregroundStyle(PlayscribeColor.onAccent)
                            .frame(maxWidth: .infinity, minHeight: 50)
                            .background(PlayscribeColor.accent, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("addPicked")
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .background(.bar)
                    .tappableFrame()
                }
            }
        }
        // Trailing placement on the inner display keeps the sheet's bar vertical and in the
        // lower-trailing region when folded; the outer display uses the system default.
        .presentationPlacement(duo.pose == .closed ? .automatic : .trailing)
        .task(id: query) {
            try? await Task.sleep(for: .milliseconds(250))
            if !Task.isCancelled { debounced = query }
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
                statusPicker
                TextField("Search \(PS5Index.shared.count.formatted()) PS5 games", text: $query)
                    .autocorrectionDisabled()
                    .submitLabel(.search)
                    .frame(minHeight: 44)
            }
            let rows = results
            Section(debounced.count >= 2 ? "Best matches" : "Popular on PS5") {
                if rows.isEmpty {
                    Text("No PS5 game matches '\(debounced)'").foregroundStyle(.secondary)
                    Button("Add '\(debounced)' yourself") { customName = debounced; custom = true }.hitTarget()
                }
                ForEach(rows) { g in AddRow(game: g, status: status, selected: picked[g.id] != nil) { toggle(g) } }
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

    private func add(_ g: CatalogGame) {
        model.addGame(g, status: status)
        dismiss()
    }

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
                    Text(game.name).font(PlayscribeFont.subheadline.weight(.semibold)).lineLimit(2)
                    Text(added ? "In library" : subtitle).font(PlayscribeFont.caption).foregroundStyle(.secondary)
                }
                Spacer(minLength: 8)
                Image(systemName: added ? "checkmark" : selected ? "checkmark.circle.fill" : "circle")
                    .font(.title3)
                    .foregroundStyle(added ? .secondary : PlayscribeColor.accent)
                    .frame(width: 44, height: 44)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(added)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(added ? "\(game.name), in your library" : "\(game.name), \(subtitle)")
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

    var body: some View {
        if duo.pose == .tabletop {
            ArrangementView {
                OnboardingStage().allowsHitTesting(false)
            } secondary: {
                ScrollView { OnboardingActions().padding(16) }
            }
            .arrangementViewStyle(.split)
        } else {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    OnboardingStage().frame(height: duo.pose == .closed ? 220 : 280)
                    OnboardingActions().padding(.horizontal, 16)
                }
                .padding(.bottom, 24)
            }
        }
    }
}

struct OnboardingStage: View {
    var body: some View {
        ZStack(alignment: .bottomLeading) {
            ArtView(asset: nil, game: nil)
            LinearGradient(colors: [.clear, .black.opacity(0.7)], startPoint: .center, endPoint: .bottom)
            Text("Follow a game to get its PS5 patch notes in one place.")
                .font(PlayscribeFont.title)
                .foregroundStyle(PlayscribeColor.textPrimary)
                .padding(20)
        }
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .padding(.horizontal, 16)
        .accessibilityElement(children: .combine)
    }
}

struct OnboardingActions: View {
    @Environment(AppModel.self) private var model
    @Environment(\.duo) private var duo

    var body: some View {
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
            Text("Popular on PS5").font(PlayscribeFont.headline)
            let size: CGFloat = duo.pose == .closed ? 96 : 108
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    ForEach(PS5Index.shared.popular(limit: 6)) { g in
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
