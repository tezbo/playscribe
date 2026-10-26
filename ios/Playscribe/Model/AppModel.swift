import Foundation
import Observation
import SwiftUI

enum AppTab: String, Codable, Hashable { case library, updates, search }

enum Chapter: String, Codable, CaseIterable, Hashable, Identifiable {
    case updates, world, companion, gallery, mybook
    var id: String { rawValue }
    var title: String {
        switch self {
        case .updates: "Updates"
        case .world: "World"
        case .companion: "Companion"
        case .gallery: "Gallery"
        case .mybook: "My book"
        }
    }
    var symbol: String {
        switch self {
        case .updates: "list.bullet.rectangle.portrait"
        case .world: "globe.europe.africa"
        case .companion: "lightbulb"
        case .gallery: "photo.on.rectangle"
        case .mybook: "book"
        }
    }
}

enum LibraryFilter: String, Codable, CaseIterable, Hashable, Identifiable {
    case all, owned, wishlist, watching
    var id: String { rawValue }
    var label: String { self == .all ? "All" : OwnershipStatus(rawValue: rawValue)!.label }
    var status: OwnershipStatus? { OwnershipStatus(rawValue: rawValue) }
}

enum LibrarySort: String, Codable, CaseIterable, Hashable, Identifiable {
    case updated, name
    var id: String { rawValue }
    var label: String { self == .updated ? "Recently updated on PS5" : "Name" }
}

struct Bookmark: Codable, Hashable {
    enum Kind: String, Codable { case release, entry }
    var kind: Kind
    var id: String
    var gameID: String
    var at: Date
}

struct Note: Codable, Hashable, Identifiable {
    var id: String
    var gameID: String
    var text: String
    var updatedAt: Date
}

struct NotifyPref: Codable, Hashable {
    var level: NotifyLevel
}

/// Navigation and reading state. Persisted so later launches restore it (L-2) and kept in one
/// place so every pose change rebuilds views from the same values (P-1).
struct NavState: Codable, Hashable {
    var tab: AppTab = .library
    var gameID: String?
    var chapter: Chapter = .updates {
        didSet { if let g = gameID { chapters = (chapters ?? [:]).merging([g: chapter]) { $1 } } }
    }
    var expanded: [String: Bool] = [:]
    /// The id of the first visible row per scroll view.
    var anchors: [String: String] = [:]
    var query: String = ""
    var filter: LibraryFilter = .all
    var sort: LibrarySort = .updated
    var lastGameID: String?
    var noteDraft: [String: String] = [:]
    /// D-2: the release the Page shows, per game. Optional so older saved state still decodes.
    var selected: [String: String]?
    /// D-13: the chapter last opened, per game.
    var chapters: [String: Chapter]?
}

struct PersistedState: Codable {
    var version = 1
    var collection: [CollectionEntry]
    var customGames: [CatalogGame] = []
    var read: [String: Date] = [:]
    var bookmarks: [Bookmark] = []
    var notes: [Note] = []
    var notify: [String: NotifyPref] = [:]
    var spoilersShown: [String: Bool] = [:]
    var revealed: [String: Bool] = [:]
    var simulated: [Release] = []
    var selectedArtwork: [String: String] = [:]
    var nav = NavState()
    var pauseAll = false
    var notificationCardShows = 0
    var notificationCardDismissed = false
    /// Releases already announced by a notification, so a release never pushes twice (N-3).
    var notified: [String: Date] = [:]
    /// Releases already seen On PS5, so only newly confirmed ones notify (V-1). nil until first run.
    var knownOnPS5: Set<String>?
    /// N-11: releases already announced quietly as Reported on PS5.
    var knownReported: Set<String>?
}

struct Toast: Equatable {
    var text: String
    var undo: (@MainActor () -> Void)?
    var token = UUID()
    static func == (a: Toast, b: Toast) -> Bool { a.token == b.token }
}

/// One application model shared by every presentation: outer, inner, folded, any orientation.
@Observable
final class AppModel {
    var data: PersistedState { didSet { scheduleSave() } }

    // Transient
    var toast: Toast?
    var pill: (gameID: String, releaseID: String)?
    var addSheetOpen = false
    var settingsOpen = false
    var player: (gameID: String, releaseID: String)?
    var highlight: String?
    /// GR-4: the in-book and Search tab note query, and its scope. Kept across pose changes (P-1).
    var noteQuery = ""
    /// D-13: the notes-search scope persists.
    var noteScope: NoteScope = NoteScope(rawValue: UserDefaults.standard.string(forKey: "noteScope") ?? "") ?? .thisGame {
        didSet { UserDefaults.standard.set(noteScope.rawValue, forKey: "noteScope") }
    }
    var recentSearches: [String] = []
    /// GR-7: games just added together, highlighted in the Library.
    var highlightSet: Set<String> = []
    /// Set when a deep link asks the journal to bring a release to the top.
    var focusReleaseID: String?
    var focusToken = 0
    var showDebugOverlay = false
    /// The pose being laid out right now, written by RootView as it renders. Lets navigation
    /// bindings tell a user's Back from a container being torn down by a pose change. Not observed.
    @ObservationIgnored var livePose: Pose = .closed
    /// Tabletop Reader: the section shown per game (TT-2). Transient.
    var readerIndex: [String: Int] = [:]
    var feedStatus: FeedStatus = .idle
    /// Releases from the feed, merged over the curated fixtures.
    var feedReleases: [Release] = [] { didSet { rebuildMerged() } }
    private(set) var allReleasesMerged: [Release] = []

    let fixtures = Fixtures.shared
    private let storeURL: URL
    private var saveTask: Task<Void, Never>?
    private var clock: Date = .now

    init(storeURL: URL = AppModel.defaultStoreURL) {
        self.storeURL = storeURL
        if let raw = try? Data(contentsOf: storeURL),
           let decoded = try? JSONCoding.decoder.decode(PersistedState.self, from: raw) {
            data = decoded
        } else {
            data = PersistedState(collection: Fixtures.shared.seedCollection)
        }
        rebuildMerged()
    }

    private func rebuildMerged() {
        let curated = Dictionary(fixtures.releases.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        var seen = Set<String>()
        var out: [Release] = []
        for f in feedReleases {
            out.append(curated[f.id].map { $0.merged(withFeed: f) } ?? f)
            seen.insert(f.id)
        }
        out += fixtures.releases.filter { !seen.contains($0.id) }
        allReleasesMerged = out
    }

    static var defaultStoreURL: URL {
        let dir = URL.applicationSupportDirectory
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appending(path: "playscribe-state.json")
    }

    private func scheduleSave() {
        saveTask?.cancel()
        saveTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(150))
            guard !Task.isCancelled else { return }
            self?.saveNow()
        }
    }

    func saveNow() {
        guard let raw = try? JSONCoding.encoder.encode(data) else { return }
        try? raw.write(to: storeURL, options: .atomic)
    }

    /// Re-evaluates time-gated releases (simulated arrivals).
    func tick() { clock = .now }

    // MARK: - Selectors

    var nav: NavState {
        get { data.nav }
        set { data.nav = newValue }
    }

    var games: [String: CatalogGame] {
        var map = Dictionary(uniqueKeysWithValues: fixtures.games.map { ($0.id, $0) })
        for g in data.customGames { map[g.id] = g }
        return map
    }

    func game(_ id: String) -> CatalogGame? { games[id] }

    func entry(_ gameID: String) -> CollectionEntry? { data.collection.first { $0.gameID == gameID } }

    /// Every visible release for a game, newest first. Pending releases are never shown.
    func releases(_ gameID: String) -> [Release] {
        let now = clock
        return (data.simulated + allReleasesMerged)
            .filter { $0.gameID == gameID && $0.ps5State != .pending && ($0.arrivesAt ?? .distantPast) <= now }
            .sorted { $0.latestDate > $1.latestDate }
    }

    func release(_ gameID: String, _ releaseID: String) -> Release? {
        releases(gameID).first { $0.id == releaseID }
    }

    func ps5Releases(_ gameID: String) -> [Release] {
        releases(gameID).filter(\.isPS5Listed).sorted { $0.ps5Date > $1.ps5Date }
    }

    func pcOnlyReleases(_ gameID: String) -> [Release] {
        releases(gameID).filter { !$0.isPS5Listed }
    }

    func isUnread(_ r: Release) -> Bool { r.ps5State == .onPS5 && data.read[r.id] == nil }

    func unreadCount(_ gameID: String) -> Int { releases(gameID).filter(isUnread).count }

    func latestOnPS5(_ gameID: String) -> Release? {
        ps5Releases(gameID).first { $0.ps5State == .onPS5 }
    }

    func notifyLevel(_ gameID: String) -> NotifyLevel { data.notify[gameID]?.level ?? .all }

    /// App icon badge (N-8): unread On PS5 releases for games whose notifications are not Off.
    var badgeCount: Int {
        data.collection.filter { notifyLevel($0.gameID) != .off }.reduce(0) { $0 + unreadCount($1.gameID) }
    }

    var totalUnread: Int { data.collection.reduce(0) { $0 + unreadCount($1.gameID) } }

    struct LibraryRow: Identifiable, Hashable {
        var game: CatalogGame
        var status: OwnershipStatus
        var addedAt: Date
        var unread: Int
        var latest: Release?
        var id: String { game.id }
    }

    var libraryRows: [LibraryRow] {
        let all = games
        return data.collection.compactMap { c in
            guard let g = all[c.gameID] else { return nil }
            return LibraryRow(game: g, status: c.status, addedAt: c.addedAt, unread: unreadCount(c.gameID), latest: latestOnPS5(c.gameID))
        }
    }

    func shownRows() -> [LibraryRow] {
        let q = nav.query.trimmingCharacters(in: .whitespaces).lowercased()
        let rows = libraryRows.filter { r in
            (nav.filter.status == nil || r.status == nav.filter.status) && (q.isEmpty || r.game.name.lowercased().contains(q))
        }
        switch nav.sort {
        case .name:
            return rows.sorted { $0.game.name.localizedCaseInsensitiveCompare($1.game.name) == .orderedAscending }
        case .updated:
            return rows.sorted { ($0.latest?.ps5Date ?? $0.addedAt) > ($1.latest?.ps5Date ?? $1.addedAt) }
        }
    }

    /// The Continue tile (B-4): the game with the most recent unread On PS5 release.
    var continueItem: (game: CatalogGame, release: Release)? {
        let candidates = data.collection.compactMap { c -> (CatalogGame, Release)? in
            guard let g = game(c.gameID), let r = ps5Releases(c.gameID).first(where: isUnread) else { return nil }
            return (g, r)
        }
        return candidates.max { $0.1.ps5Date < $1.1.ps5Date }.map { ($0.0, $0.1) }
    }

    /// The game whose art fronts the Library: Continue first, then the last opened game (L13).
    var featuredGame: CatalogGame? {
        if let c = continueItem { return c.game }
        let ids = [nav.lastGameID].compactMap { $0 } + data.collection.map(\.gameID)
        return ids.lazy.compactMap { id in self.entry(id) != nil ? self.game(id) : nil }.first
    }

    func chapters(_ gameID: String) -> [Chapter] {
        Chapter.allCases.filter { c in
            switch c {
            case .updates, .mybook, .gallery: true
            case .world: fixtures.book.contains { $0.gameID == gameID && $0.chapter == .world }
            case .companion: fixtures.book.contains { $0.gameID == gameID && $0.chapter == .companion }
            }
        }
    }

    func gallery(_ gameID: String) -> [GalleryItem] {
        let items = fixtures.gallery.filter { $0.gameID == gameID }
        if !items.isEmpty { return items }
        guard let g = game(gameID) else { return [] }
        var out: [GalleryItem] = []
        if let h = g.heroAsset { out.append(GalleryItem(id: "\(gameID)-hero", gameID: gameID, kind: .artwork, asset: h, title: "Key art", alt: "\(g.name) key art")) }
        if let c = g.coverAsset { out.append(GalleryItem(id: "\(gameID)-cover", gameID: gameID, kind: .artwork, asset: c, title: "Cover", alt: "\(g.name) cover")) }
        return out
    }

    /// The artwork behind the game book: the reader's pick, else the chapter's art.
    func backdrop(_ gameID: String, chapter: Chapter, tall: Bool) -> String? {
        if let picked = data.selectedArtwork[gameID], let item = gallery(gameID).first(where: { $0.id == picked }) {
            return item.asset
        }
        guard let g = game(gameID) else { return nil }
        if let art = g.chapterArt?[chapter.rawValue] ?? g.chapterArt?["default"], art.count == 2 {
            return tall ? art[1] : art[0]
        }
        return tall ? (g.coverAsset ?? g.heroAsset) : (g.heroAsset ?? g.coverAsset)
    }

    // MARK: - Navigation

    func openGame(_ gameID: String, chapter: Chapter? = nil, releaseID: String? = nil) {
        var n = nav
        let sameGame = n.gameID == gameID
        n.tab = .library
        n.gameID = gameID
        n.lastGameID = gameID
        // D-13: each game reopens on the chapter last opened in it.
        n.chapter = chapter ?? (sameGame ? n.chapter : (n.chapters?[gameID] ?? .updates))
        if let releaseID {
            n.selected = (n.selected ?? [:]).merging([gameID: releaseID]) { $1 }
            n.expanded["rel:\(releaseID)"] = true
            n.anchors[Self.bookKey(gameID, .updates)] = "rel-\(releaseID)"
        } else if !sameGame, let first = ps5Releases(gameID).first {
            // R-1: newest On PS5 release expanded, at the top.
            if n.expanded["rel:\(first.id)"] == nil { n.expanded["rel:\(first.id)"] = true }
        }
        nav = n
        readerIndex[gameID] = 0
        if pill?.gameID == gameID { pill = nil }
        focusReleaseID = releaseID
        focusToken += 1
    }

    /// D-2/D-3: the release the Page shows: the one picked, else the newest On PS5 release.
    func selectedRelease(_ gameID: String) -> Release? {
        if let id = nav.selected?[gameID], let r = release(gameID, id) { return r }
        return ps5Releases(gameID).first ?? releases(gameID).first
    }

    /// D-4: picking a release in the Contents changes the Page in place; no navigation.
    func select(_ gameID: String, releaseID: String) {
        nav.selected = (nav.selected ?? [:]).merging([gameID: releaseID]) { $1 }
        readerIndex[gameID] = 0
        if let r = release(gameID, releaseID), isUnread(r) { markRead(r.id) }
    }

    static func bookKey(_ gameID: String, _ chapter: Chapter) -> String { "book-\(gameID)-\(chapter.rawValue)" }

    func closeGame() {
        nav.gameID = nil
    }

    /// Deep link from a notification or URL (N-6, N-9).
    func openRelease(gameID: String, releaseID: String) {
        tick()
        player = nil
        addSheetOpen = false
        if release(gameID, releaseID) == nil {
            openGame(gameID, chapter: .updates)
            show(Toast(text: "That update is no longer available"))
        } else {
            openGame(gameID, chapter: .updates, releaseID: releaseID)
        }
    }

    func handle(url: URL) {
        // playscribe://release/<gameID>/<releaseID>
        guard url.scheme == "playscribe" else { return }
        let parts = url.pathComponents.filter { $0 != "/" }
        if url.host() == "release", parts.count == 2 {
            openRelease(gameID: parts[0], releaseID: parts[1])
        } else if url.host() == "game", let id = parts.first {
            openGame(id)
        }
        #if INTERNAL
        // Internal routes so QA can script every screen in every pose with `simctl openurl`.
        switch url.host() {
        case "add": addSheetOpen = true
        case "settings": settingsOpen = true
        case "library": nav.tab = .library; nav.gameID = nil
        case "updates": nav.tab = .updates
        case "search": nav.tab = .search
        case "video" where parts.count == 2: openGame(parts[0], releaseID: parts[1]); player = (parts[0], parts[1])
        case "chapter" where parts.count == 2: openGame(parts[0], chapter: Chapter(rawValue: parts[1]))
        case "first-run": resetToFirstRun()
        case "demo": resetDemo()
        case "overlay": showDebugOverlay.toggle()
        case "simulate" where parts.count == 2:
            Task {
                if NotificationService.shared.authorization == .notDetermined { await NotificationService.shared.requestAuthorization() }
                simulateUpdate(gameID: parts[0], kind: parts[1] == "hotfix" ? .hotfix : .major, delay: 3)
            }
        case "close": player = nil; addSheetOpen = false; settingsOpen = false
        case "add-game" where parts.count == 1:
            // Adds a game from the PS5 index by IGDB id, as the Add button does (A-5, F-5, N-1).
            if let id = Int(parts[0]), let e = PS5Index.shared.entries.first(where: { $0.i == id }) {
                addGame(PS5Index.shared.game(e), status: .owned)
            }
        case "remove-game" where parts.count == 1: removeGame(parts[0])
        case "ask-notifications": Task { await NotificationService.shared.requestAuthorization() }
        default: break
        }
        #endif
    }

    // MARK: - Reading

    func isExpanded(_ key: String, default value: Bool = false) -> Bool { nav.expanded[key] ?? value }

    func setExpanded(_ key: String, _ value: Bool) { nav.expanded[key] = value }

    func markRead(_ releaseID: String, _ read: Bool = true) {
        if read { data.read[releaseID] = .now } else { data.read[releaseID] = nil }
        if read, pill?.releaseID == releaseID { pill = nil }
        NotificationService.shared.updateBadge(badgeCount)
    }

    func markAllRead(_ gameID: String) {
        let ids = releases(gameID).filter(isUnread).map(\.id)
        for id in ids { data.read[id] = .now }
        NotificationService.shared.updateBadge(badgeCount)
        show(Toast(text: "\(ids.count) update\(ids.count == 1 ? "" : "s") marked read", undo: { [weak self] in
            guard let self else { return }
            for id in ids { self.data.read[id] = nil }
            NotificationService.shared.updateBadge(self.badgeCount)
        }))
    }

    func toggleBookmark(kind: Bookmark.Kind, id: String, gameID: String) {
        if data.bookmarks.contains(where: { $0.kind == kind && $0.id == id }) {
            data.bookmarks.removeAll { $0.kind == kind && $0.id == id }
            show(Toast(text: "Bookmark removed"))
        } else {
            data.bookmarks.insert(Bookmark(kind: kind, id: id, gameID: gameID, at: .now), at: 0)
            show(Toast(text: "Bookmarked. Find it in My book"))
        }
    }

    func isBookmarked(kind: Bookmark.Kind, id: String) -> Bool {
        data.bookmarks.contains { $0.kind == kind && $0.id == id }
    }

    func spoilersShown(_ gameID: String) -> Bool { data.spoilersShown[gameID] ?? false }

    func setSpoilersShown(_ gameID: String, _ shown: Bool) { data.spoilersShown[gameID] = shown }

    func isRevealed(_ key: String, gameID: String) -> Bool { spoilersShown(gameID) || data.revealed[key] == true }

    func reveal(_ key: String) { data.revealed[key] = true }

    func saveNote(_ note: Note) {
        if let i = data.notes.firstIndex(where: { $0.id == note.id }) { data.notes[i] = note } else { data.notes.insert(note, at: 0) }
    }

    func deleteNote(_ id: String) {
        guard let note = data.notes.first(where: { $0.id == id }) else { return }
        data.notes.removeAll { $0.id == id }
        show(Toast(text: "Note deleted", undo: { [weak self] in self?.saveNote(note) }))
    }

    func selectArtwork(_ gameID: String, _ itemID: String) { data.selectedArtwork[gameID] = itemID }

    // MARK: - Library

    func addGame(_ game: CatalogGame, status: OwnershipStatus) {
        addGames([game], status: status)
    }

    /// GR-7: add one or more games with a single Undo. A future game defaults to Wishlist (GR-5).
    func addGames(_ list: [CatalogGame], status: OwnershipStatus) {
        let new = list.filter { entry($0.id) == nil }
        guard !new.isEmpty else { return }
        for g in new { insertGame(g, status: status == .owned && g.isUpcoming ? .wishlist : status) }
        let ids = new.map(\.id)
        nav.filter = .all
        highlight = new.count == 1 ? ids[0] : nil
        highlightSet = Set(ids)
        nav.anchors["library"] = "lib-\(ids[0])"
        let text = new.count == 1 ? "Added \(new[0].name)" : "Added \(new.count) games"
        show(Toast(text: text, undo: { [weak self] in ids.forEach { self?.removeGame($0, toast: false) } }))
        NotificationService.shared.updateBadge(badgeCount)
    }

    private func insertGame(_ game: CatalogGame, status: OwnershipStatus) {
        guard entry(game.id) == nil else { return }
        let isFirst = data.collection.isEmpty
        if fixtures.games.first(where: { $0.id == game.id }) == nil, !data.customGames.contains(where: { $0.id == game.id }) {
            data.customGames.append(game)
        }
        data.collection.insert(CollectionEntry(gameID: game.id, status: status, addedAt: .now), at: 0)
        // A-9: Owned follows all updates; Wishlist and Watching follow major ones.
        if data.notify[game.id] == nil { data.notify[game.id] = NotifyPref(level: status == .owned ? .all : .major) }
        if isFirst { data.notificationCardShows = max(data.notificationCardShows, 0) }
    }

    func setStatus(_ gameID: String, _ status: OwnershipStatus) {
        guard let i = data.collection.firstIndex(where: { $0.gameID == gameID }) else { return }
        data.collection[i].status = status
    }

    func setNotify(_ gameID: String, _ level: NotifyLevel) {
        data.notify[gameID] = NotifyPref(level: level)
        NotificationService.shared.updateBadge(badgeCount)
    }

    /// B-8: removal is immediate; Undo restores status, notification level, bookmarks and notes.
    func removeGame(_ gameID: String, toast: Bool = true) {
        guard let index = data.collection.firstIndex(where: { $0.gameID == gameID }) else { return }
        let name = game(gameID)?.name ?? "game"
        let saved = (entry: data.collection[index], notify: data.notify[gameID],
                     bookmarks: data.bookmarks.filter { $0.gameID == gameID }, notes: data.notes.filter { $0.gameID == gameID })
        data.collection.remove(at: index)
        data.bookmarks.removeAll { $0.gameID == gameID }
        data.notes.removeAll { $0.gameID == gameID }
        if nav.gameID == gameID { nav.gameID = nil }
        NotificationService.shared.updateBadge(badgeCount)
        guard toast else { toastClear(); return }
        show(Toast(text: "Removed \(name)", undo: { [weak self] in
            guard let self else { return }
            self.data.collection.insert(saved.entry, at: min(index, self.data.collection.count))
            self.data.notify[gameID] = saved.notify
            self.data.bookmarks += saved.bookmarks
            self.data.notes += saved.notes
            NotificationService.shared.updateBadge(self.badgeCount)
        }))
    }

    // MARK: - Toasts

    func show(_ t: Toast) {
        toast = t
        let token = t.token
        if UIAccessibility.isVoiceOverRunning {
            // Under VoiceOver the toast stays until dismissed, and is announced with its action.
            AccessibilityNotification.Announcement(t.undo == nil ? t.text : "\(t.text). Undo available.").post()
            if t.undo != nil { return }
        }
        Task { [weak self] in
            try? await Task.sleep(for: .seconds(t.undo == nil ? 2.6 : 8))
            if self?.toast?.token == token { self?.toast = nil }
        }
    }

    func toastClear() { toast = nil }

    // MARK: - First run and notification invitation

    /// N-1: the invitation card shows after the first game is added, at most twice, never after a decision.
    var showsNotificationCard: Bool {
        !data.collection.isEmpty && !data.notificationCardDismissed && data.notificationCardShows < 2
            && NotificationService.shared.authorization == .notDetermined
    }

    func resetToFirstRun() {
        data = PersistedState(collection: [])
        UserDefaults.standard.set(false, forKey: "didOnboard")
        toast = nil
        pill = nil
        NotificationService.shared.updateBadge(0)
    }

    func resetDemo() {
        data = PersistedState(collection: fixtures.seedCollection)
        UserDefaults.standard.set(true, forKey: "didOnboard")
        NotificationService.shared.updateBadge(badgeCount)
    }

    // MARK: - Simulated updates (internal builds)

    enum SimKind: String, CaseIterable, Identifiable {
        case hotfix, major
        var id: String { rawValue }
        var label: String { self == .hotfix ? "Hotfix" : "Major update" }
    }

    /// Creates a clearly labelled simulated PS5 release and schedules its notification.
    func simulateUpdate(gameID: String, kind: SimKind, delay: TimeInterval) {
        let n = data.simulated.count + 1
        let latest = ps5Releases(gameID).first?.ps5Version
        let version = Self.bumpConsoleVersion(latest, major: kind == .major)
        let arrives = Date.now.addingTimeInterval(delay)
        let major = kind == .major
        let display = major ? "Update \(n + 1).0 (simulated)" : "Hotfix \(n) (simulated)"
        let release = Release(
            id: "sim-\(gameID)-\(Int(arrives.timeIntervalSince1970))", gameID: gameID, displayName: display,
            kind: major ? .major : .hotfix, kindBasis: .studio, announcedAt: arrives,
            notes: [NoteSection(title: major ? "Changes (simulated)" : "Fixes (simulated)", items: (major
                ? ["Added a performance mode option.", "Reduced loading times between areas.", "Map markers can be filtered."]
                : ["Fixed a crash when loading a save.", "Fixed autosaves sometimes not appearing in the list."]).map {
                    NoteItem(text: "\($0) (Simulated)", platforms: nil, ps5ProOnly: false)
                })],
            sourceIDs: [],
            platforms: [PlatformRelease(platform: .ps5, status: .live,
                                        version: Field(value: version, verification: .official, sourceID: "simulated", checkedAt: arrives),
                                        liveAt: Field(value: arrives, verification: .official, sourceID: "simulated", checkedAt: arrives),
                                        bundles: [], verification: .official)],
            headline: major ? "Simulated update: performance mode and faster loading" : "Simulated hotfix: stability and save fixes",
            summary: "This release was created by Simulate update to test notifications. It is not a real release.",
            keyChanges: major ? ["a new performance mode option", "faster loading between areas"] : ["fixed a crash when loading a save", "fixed missing autosaves"],
            simulated: true, arrivesAt: arrives
        )
        data.simulated.insert(release, at: 0)
        NotificationService.shared.schedule(release: release, game: game(gameID), level: notifyLevel(gameID), pauseAll: data.pauseAll, delay: delay, model: self)
        show(Toast(text: "Simulated \(kind.label.lowercased()) arrives in \(Int(delay)) s"))
    }

    static func bumpConsoleVersion(_ v: String?, major: Bool) -> String {
        guard let v else { return major ? "01.001.000" : "01.000.001" }
        var parts = v.split(separator: ".").map { Int($0) ?? 0 }
        while parts.count < 3 { parts.append(0) }
        if major { parts[1] += 1; parts[2] = 0 } else { parts[2] += 1 }
        return String(format: "%02d.%03d.%03d", parts[0], parts[1], parts[2])
    }

    /// N-7: a release that arrived while the app is open: no banner, insert and show a pill.
    func releaseArrivedInForeground(gameID: String, releaseID: String) {
        tick()
        highlight = releaseID
        if nav.gameID != gameID { pill = (gameID, releaseID) }
        NotificationService.shared.updateBadge(badgeCount)
    }
}
