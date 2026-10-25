import SwiftUI

/// GR-4: "did they fix X?" Search inside PS5 notes, scoped to this game or all my games.
enum NoteScope: String, CaseIterable, Hashable {
    case thisGame, allGames
    var label: String { self == .thisGame ? "This game" : "All my games" }
}

struct NoteHit: Identifiable {
    var id: String
    var release: Release
    var line: String
    var section: String
    var pcOnly: Bool
}

extension AppModel {
    func noteHits(_ query: String, scope: NoteScope, gameID: String?) -> [NoteHit] {
        let q = PS5Index.fold(query)
        guard q.count >= 2 else { return [] }
        let games = scope == .thisGame ? [gameID].compactMap { $0 } : data.collection.map(\.gameID)
        var hits: [NoteHit] = []
        for g in games {
            for r in releases(g) {
                let ps5 = r.isPS5Listed
                for (si, section) in r.notes.enumerated() {
                    for (ii, item) in section.items.enumerated() where item.spoiler != true {
                        guard PS5Index.fold(item.text + " " + section.title).contains(q) else { continue }
                        hits.append(NoteHit(id: "\(r.id)#\(si).\(ii)", release: r, line: item.text, section: section.title,
                                            pcOnly: !ps5 || item.isPCOnly))
                    }
                }
                for (ki, k) in (r.keyChanges ?? []).enumerated() where PS5Index.fold(k).contains(q) {
                    hits.append(NoteHit(id: "\(r.id)#k\(ki)", release: r, line: k, section: "Key changes", pcOnly: !ps5 || PCOnly.matches(k)))
                }
            }
        }
        return hits.sorted { $0.release.latestDate > $1.release.latestDate }
    }

    func rememberSearch(_ q: String) {
        let t = q.trimmingCharacters(in: .whitespaces)
        guard t.count >= 2 else { return }
        recentSearches.removeAll { $0.caseInsensitiveCompare(t) == .orderedSame }
        recentSearches.insert(t, at: 0)
        recentSearches = Array(recentSearches.prefix(6))
    }
}

/// Results grouped by release, newest first; PC-only matches last under "PC only".
struct NoteSearchResults: View {
    @Environment(AppModel.self) private var model
    var query: String
    var scope: NoteScope
    var gameID: String?
    var onSwitchScope: () -> Void

    var body: some View {
        let hits = model.noteHits(query, scope: scope, gameID: gameID)
        let ps5 = hits.filter { !$0.pcOnly }
        let pc = hits.filter(\.pcOnly)
        List {
            if hits.isEmpty {
                let name = gameID.flatMap { model.game($0)?.name } ?? "your games"
                VStack(alignment: .leading, spacing: 10) {
                    Text(scope == .thisGame ? "No mention of '\(query)' in \(name)'s PS5 notes" : "No mention of '\(query)' in your games' PS5 notes")
                        .font(PlayscribeFont.headline)
                    if scope == .thisGame {
                        Button("Search all my games", action: onSwitchScope).hitTarget()
                    }
                }
            }
            group(ps5)
            if !pc.isEmpty {
                Section("PC only") { rows(pc) }
            }
        }
        .scrollContentBackground(.hidden)
        .background(Color.ink0)
    }

    @ViewBuilder private func group(_ hits: [NoteHit]) -> some View {
        let byRelease = Dictionary(grouping: hits, by: \.release.id)
        let order = hits.map(\.release.id).reduce(into: [String]()) { if !$0.contains($1) { $0.append($1) } }
        ForEach(order, id: \.self) { id in
            if let rs = byRelease[id], let r = rs.first?.release {
                Section {
                    rows(rs)
                } header: {
                    HStack(spacing: 6) {
                        Text("\(r.displayName) · \(model.game(r.gameID)?.name ?? "")")
                        Text("· " + (r.isPS5Listed ? r.ps5Date : r.latestDate).dayMonth)
                        ReleaseTag(release: r)
                    }
                }
            }
        }
    }

    private func rows(_ hits: [NoteHit]) -> some View {
        ForEach(hits) { h in
            Button {
                model.rememberSearch(query)
                model.openGame(h.release.gameID, chapter: .updates, releaseID: h.release.id)
                model.highlight = h.release.id
                model.noteQuery = ""
            } label: {
                VStack(alignment: .leading, spacing: 3) {
                    Text(bolded(h.line)).font(PlayscribeFont.subheadline)
                    Text(h.section).font(PlayscribeFont.caption).foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .tappableFrame()
        }
    }

    private func bolded(_ line: String) -> AttributedString {
        var a = AttributedString(line)
        if let r = a.range(of: query, options: [.caseInsensitive, .diacriticInsensitive]) {
            a[r].font = PlayscribeFont.subheadline.bold()
            a[r].foregroundColor = PlayscribeColor.accent
        }
        return a
    }
}
