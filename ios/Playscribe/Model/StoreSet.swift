import Foundation

#if INTERNAL
/// App Store screenshot content (r052-store-set-content): five invented games with plate-only covers and neutral hero art,
/// in mixed states, so the Mac can capture store frames without real game names or marks. Internal builds only: the route
/// that loads it (`-qaRoute store-set`, or playscribe://store-set) sits behind the same `showsInternalTools` guard as every
/// other QA route (#231). Release also defines INTERNAL, so this file is compiled into every build, TestFlight included; the guard, not the compile flag, keeps the set out of distribution.
enum StoreSet {
    struct Entry {
        var id: String; var name: String; var slug: String; var status: OwnershipStatus
        var releaseDate: String?; var update: (name: String, headline: String, summary: String, changes: [String], unread: Bool)?
    }

    static let entries: [Entry] = [
        Entry(id: "store-lantern-reach", name: "Lantern Reach", slug: "lantern-reach", status: .owned, releaseDate: "2026-02-10",
              update: ("Update 1.3", "Night expeditions, a steadier frame rate and a rebuilt map",
                       "After dark you can sail to the far shore. The new map reads faster at a glance, and crowded harbours no longer stutter.",
                       ["night expeditions to the far shore", "a rebuilt, quicker map", "steadier frame rate in busy harbours"], unread: true)),
        Entry(id: "store-hollow-meridian", name: "Hollow Meridian", slug: "hollow-meridian", status: .watching, releaseDate: "2026-05-21",
              update: ("Hotfix 1.1.2", "Fixes for saves and a camera that drifted",
                       "A small fix: saves load reliably after a long session and the camera no longer drifts in tight corridors.",
                       ["saves load reliably after long sessions", "the camera no longer drifts in corridors"], unread: false)),
        Entry(id: "store-saltmarsh-cadence", name: "Saltmarsh Cadence", slug: "saltmarsh-cadence", status: .wishlist, releaseDate: "2026-08-04", update: nil),
        Entry(id: "store-ember-tides", name: "Ember Tides", slug: "ember-tides", status: .wishlist, releaseDate: "2027-03-12", update: nil),
        Entry(id: "store-long-quiet-orchard", name: "The Long Quiet Orchard of Wending Hollow", slug: "long-quiet-orchard", status: .owned, releaseDate: "2025-10-30",
              update: ("Update 2.0", "A second season of quiet seasons, new trails and calmer menus",
                       "Autumn gives way to winter between the old trees, three trails open above the wall, and the menus finally read at a glance.",
                       ["seasons that turn in the orchard", "three new trails", "calmer, easier-to-read menus"], unread: false)),
    ]

    static var gameIDs: [String] { entries.map(\.id) }

    static func games() -> [CatalogGame] {
        entries.map { e in
            CatalogGame(id: e.id, name: e.name, developer: nil, publisher: nil, platforms: [.ps5], releaseDate: e.releaseDate,
                        releasePrecision: .day, coverAsset: "store-\(e.slug)-cover", heroAsset: "store-\(e.slug)-hero", coverage: .full)
        }
    }

    /// The PS Plus lineup (store-set/plus): designed covers for invented titles, never tracked, so tiles are not tappable.
    static func plusGames() -> [CatalogGame] {
        PlusStore.storeSetLineup.map { g in
            CatalogGame(id: g.id, name: g.name, platforms: [.ps5], coverAsset: "\(g.id)-cover", coverage: .none, custom: true)
        }
    }

    static func releases(now: Date = .now) -> [Release] {
        entries.compactMap { e in
            guard let u = e.update else { return nil }
            let at = now.addingTimeInterval(e.status == .owned && u.unread ? -2 * 3600 : -9 * 86400)
            let id = "\(e.id)@\(u.name.lowercased().replacingOccurrences(of: " ", with: "-"))"
            return Release(
                id: id, gameID: e.id, displayName: u.name, kind: u.name.hasPrefix("Hotfix") ? .hotfix : .major, kindBasis: .studio,
                announcedAt: at,
                notes: [NoteSection(title: "What’s changed", items: u.changes.map { NoteItem(text: $0.prefix(1).uppercased() + $0.dropFirst() + ".") })],
                sourceIDs: [],
                platforms: [PlatformRelease(platform: .ps5, status: .live,
                                            version: Field(value: "01.00\(u.unread ? 3 : 1).000", verification: .official, sourceID: "store-set", checkedAt: at),
                                            liveAt: Field(value: at, verification: .official, sourceID: "store-set", checkedAt: at),
                                            bundles: [], verification: .official)],
                headline: u.headline, summary: u.summary, keyChanges: u.changes)
        }
    }
}

extension AppModel {
    /// QA (INTERNAL, route "store-set"): replaces the library with the store set. Only the lantern-reach update is unread.
    /// `plus: true` (route `store-set/plus`) keeps the PS Plus card, with invented plates; by default it is off so the update hero is the first thing in the frame.
    func loadStoreSet(plus: Bool = false) {
        guard BuildChannel.showsInternalTools else { return }
        qaUpdateCount = 0
        var state = PersistedState(collection: StoreSet.entries.map { CollectionEntry(gameID: $0.id, status: $0.status, addedAt: .now.addingTimeInterval(-30 * 86400)) })
        state.customGames = StoreSet.games() + StoreSet.plusGames()
        let releases = StoreSet.releases()
        state.simulated = releases
        for r in releases where !(StoreSet.entries.first { $0.id == r.gameID }?.update?.unread ?? false) { state.read[r.id] = .now }
        data = state
        PlusStore.shared.setQA("store")   // the PS Plus card shows invented plates, never real covers
        data.plusCardOff = plus ? nil : true
        // Alerts are treated as decided, so the invitation card never sits above the story.
        NotificationService.shared.qaForcedAuthorization = .authorized
        UserDefaults.standard.set(true, forKey: "didOnboard")
        NotificationService.shared.updateBadge(badgeCount)
    }
}
#endif
