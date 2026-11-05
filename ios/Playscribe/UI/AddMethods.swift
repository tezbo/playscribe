import SwiftUI

/// The ways to build a library (0.5.0 "Build your library in seconds"). Every method ends on the
/// same results list and the pinned "Add N games" bar; nothing is added without that tap.
enum AddMethod: String, CaseIterable, Identifiable {
    case typeIt, sayIt, photo, camera
    var id: String { rawValue }

    var title: String {
        switch self {
        case .typeIt: "Type it"
        case .sayIt: "Say it"
        case .photo: "From a photo"
        case .camera: "Scan with camera"
        }
    }
    var symbol: String {
        switch self {
        case .typeIt: "keyboard"
        case .sayIt: "mic"
        case .photo: "photo"
        case .camera: "camera.viewfinder"
        }
    }
    var detail: String {
        switch self {
        case .typeIt: "Search by name"
        case .sayIt: "List your games out loud"
        case .photo: "Pick a picture of your games or your shelf"
        case .camera: "Point at a box or a shelf"
        }
    }

    /// Methods in this build, in the order the entry sheet shows them.
    static var available: [AddMethod] { [.typeIt, .sayIt, .photo, .camera] }
}

/// One spoken, typed or scanned title and what it matched.
struct AddMatch: Identifiable, Hashable {
    var id: String { title }
    var title: String
    var best: CatalogGame?
    var guesses: [CatalogGame]
    var sure: Bool { best != nil }
}

enum AddMatcher {
    /// Splits "Elden Ring and Astro Bot, Returnal" into titles: "and", commas, semicolons, new lines.
    static func titles(from text: String) -> [String] {
        var t = text.replacingOccurrences(of: "\n", with: ",").replacingOccurrences(of: ";", with: ",")
        t = t.replacingOccurrences(of: " and ", with: ",", options: .caseInsensitive)
        var seen = Set<String>()
        return t.split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { PS5Index.fold($0).count >= 2 && seen.insert(PS5Index.fold($0)).inserted }
    }

    /// Matches each title to the catalogue. A near-whole-name hit is sure; anything else keeps its
    /// top three guesses for "Is this it?".
    @MainActor static func match(_ titles: [String], curated: [CatalogGame]) -> [AddMatch] {
        titles.map { title in
            let q = PS5Index.fold(title)
            let curatedHits = curated.filter { PS5Index.fold($0.name).contains(q) }
            var seen = Set<String>()
            let hits = (curatedHits + PS5Index.shared.search(title, limit: 6)).filter { seen.insert($0.id).inserted }
            let guesses = Array(hits.prefix(3))
            if let first = guesses.first {
                let n = PS5Index.fold(first.name)
                let close = n == q || (n.hasPrefix(q) && Double(q.count) / Double(n.count) > 0.7)
                if close { return AddMatch(title: title, best: first, guesses: guesses) }
            }
            return AddMatch(title: title, best: nil, guesses: guesses)
        }
    }
}

/// The entry sheet: one 52 pt row per method.
struct AddEntryView: View {
    var choose: (AddMethod) -> Void

    var body: some View {
        List {
            Section {
                ForEach(AddMethod.available) { m in
                    Button { choose(m) } label: {
                        HStack(spacing: 14) {
                            Image(systemName: m.symbol).font(.title3).frame(width: 32)
                                .foregroundStyle(PlayscribeColor.accent)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(m.title).font(PlayscribeFont.headline)
                                Text(m.detail).font(PlayscribeFont.footnote).foregroundStyle(.secondary)
                            }
                            Spacer(minLength: 0)
                            Image(systemName: "chevron.forward").font(.footnote).foregroundStyle(.secondary)
                        }
                        .frame(minHeight: 52)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("\(m.title), \(m.detail.lowercasedFirst)")
                    .accessibilityAddTraits(.isButton)
                    .tappableFrame()
                }
            }
        }
        // Pinned in the sheet's own bottom inset so nothing behind or below can run into it.
        .safeAreaInset(edge: .bottom, spacing: 0) {
            Text("PlayStation account import is planned for a later version. \(Brand.name) never asks for your PlayStation password.")
                .font(PlayscribeFont.footnote).foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 20).padding(.top, 10).padding(.bottom, 16)
                .background(Color.ink0)
        }
    }
}

/// The one results list every method lands on: sure matches are pre-ticked by the sheet, unsure
/// ones show "Is this it?" with their top guesses, unticked.
struct AddResultsView: View {
    var matches: [AddMatch]
    var status: OwnershipStatus
    var picked: [String: CatalogGame]
    var toggle: (CatalogGame) -> Void
    var tryAgain: () -> Void

    var body: some View {
        List {
            if matches.isEmpty {
                Section {
                    Text("Nothing recognised yet").font(PlayscribeFont.headline)
                    Button("Try again", action: tryAgain).hitTarget()
                }
            }
            let sure = matches.filter(\.sure)
            if !sure.isEmpty {
                Section("Found \(sure.count)") {
                    ForEach(sure) { m in
                        if let g = m.best { AddRow(game: g, status: status, selected: picked[g.id] != nil) { toggle(g) } }
                    }
                }
            }
            ForEach(matches.filter { !$0.sure }) { m in
                Section {
                    if m.guesses.isEmpty {
                        Text("No PS5 game matches '\(m.title)'").foregroundStyle(.secondary)
                    }
                    ForEach(m.guesses) { g in AddRow(game: g, status: status, selected: picked[g.id] != nil) { toggle(g) } }
                } header: {
                    Text("Is this it? \(m.title)")
                }
            }
        }
    }
}

extension String {
    var lowercasedFirst: String { prefix(1).lowercased() + dropFirst() }
}
