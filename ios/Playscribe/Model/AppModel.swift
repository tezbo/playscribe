import Foundation
import Observation
import SwiftUI
import UserNotifications

enum AppTab: String, Codable, Hashable { case library, updates, search }

enum Chapter: String, Codable, CaseIterable, Hashable, Identifiable {
    case updates, news, world, companion, gallery, mybook
    var id: String { rawValue }
    var title: String {
        switch self {
        case .updates: "What's new"
        case .news: "News"
        case .world: "World"
        case .companion: "Companion"
        case .gallery: "Gallery"
        case .mybook: "My book"
        }
    }
    var symbol: String {
        switch self {
        case .updates: "list.bullet.rectangle.portrait"
        case .news: "newspaper"
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
    /// J-1: a release pushed as its own screen (Closed and open portrait).
    var detailReleaseID: String?
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
    /// Per-game overrides of the default (Settings, 0.2.0).
    var notify: [String: NotifyPref] = [:]
    /// "Notify me about": the level for every game without its own setting. nil = All updates.
    var notifyDefault: NotifyLevel?
    var spoilersShown: [String: Bool] = [:]
    var revealed: [String: Bool] = [:]
    var simulated: [Release] = []
    var selectedArtwork: [String: String] = [:]
    var nav = NavState()
    var pauseAll = false
    /// Quiet hours (0.5.0, Iris): nil = off, the default. Local scheduling only.
    var quietHours: QuietHours?
    /// nil = on. Off silences the add pop.
    var soundsOff: Bool?
    /// The PS Plus card and its "Leaving soon" reminder (Terry, 2026-11-05): nil = on. Off hides both.
    var plusCardOff: Bool?
    /// The PS Plus "Leaving soon" reminder (0.5.0): nil = on.
    var plusLeavingSoonOff: Bool?
    var notificationCardShows = 0
    var notificationCardDismissed = false
    /// N-1 re-ask: how many times "Not now" was chosen, and until when the card rests. Optional so older saved state decodes.
    var notificationAsks: Int?
    var notificationSnoozedUntil: Date?
    /// How often the "press and hold" Library tip has shown (it stops after two). Optional so older saved state still decodes.
    var pressTipShows: Int?
    /// Releases already announced by a notification, so a release never pushes twice (N-3).
    var notified: [String: Date] = [:]
    /// Releases already seen On PS5, so only newly confirmed ones notify (V-1). nil until first run.
    var knownOnPS5: Set<String>?
    /// N-11: releases already announced quietly as Reported on PS5.
    var knownReported: Set<String>?
    /// Upcoming date moves already announced ("igdbId:movedAt"), so one change alerts once.
    var notifiedMoves: Set<String>?
    /// When the app was last opened (A6): the catch-up card lists what arrived after it.
    var lastOpenedAt: Date?
    /// Known issues the person follows, and those already alerted as fixed (0.5.0 item 19).
    var followedIssues: Set<String>?
    var alertedIssues: Set<String>?
    /// The first-run welcome was used or skipped; the plain empty Library shows after that.
    var welcomeDone: Bool?
}

struct Toast: Equatable {
    var text: String
    var undo: (@MainActor () -> Void)?
    /// The button's label: "Undo" by default, "Open My book" on a new bookmark.
    var actionLabel = "Undo"
    var token = UUID()
    /// How long the toast stays; nil uses the default (2.6 s, or 8 s with an action).
    var seconds: Double?
    static func == (a: Toast, b: Toast) -> Bool { a.token == b.token }
}

/// One application model shared by every presentation: outer, inner, folded, any orientation.
@Observable
final class AppModel {
    var data: PersistedState { didSet { scheduleSave() } }

    // Transient
    var toast: Toast?
    /// Height the pill and toasts take at the bottom of the screen (0 when none): the Library reserves it as a bottom inset.
    var messageInset: CGFloat = 0
    /// Frame of the pill and toasts in global coordinates, nil while none shows. A Library page that the frame overlaps ends
    /// its scroll view 12 pt above its top edge.
    var messageFrame: CGRect?
    /// The tab Search was opened from, so Search can go back to it (Terry, 0.2.0 build 5).
    var searchReturnTab: AppTab = .library
    func leaveSearch() { if nav.tab == .search { nav.tab = searchReturnTab == .search ? .library : searchReturnTab } }
    var pill: (gameID: String, releaseID: String)?
    var addSheetOpen = false
    /// QA (route add/scan): the camera scan shows a fixed feed, since simulators have no camera.
    var simulatedScan = false
    /// Opens the Add games sheet straight on this method (first-run welcome rows).
    var addSheetMethod: AddMethod?
    /// QA: route add/keyboard focuses the Add search field so the keyboard is up.
    var addSearchFocus = false
    var settingsOpen = false
    var player: (gameID: String, releaseID: String)?
    /// A game's trailer from its basics (no release).
    var trailer: (videoID: String, name: String)?
    var highlight: String?
    /// GR-4: the in-book and Search tab note query, and its scope. Kept across pose changes (P-1).
    var noteQuery = ""
    /// Tabletop: first-letter filter for the notes search (the keyboard never opens there).
    var noteLetter: String?
    /// D-13: the notes-search scope persists.
    var noteScope: NoteScope = NoteScope(rawValue: UserDefaults.standard.string(forKey: "noteScope") ?? "") ?? .thisGame {
        didSet { UserDefaults.standard.set(noteScope.rawValue, forKey: "noteScope") }
    }
    var recentSearches: [String] = []
    /// The Latest updates deck's current card (not persisted); Tabletop's page edge drives the standing half with it.
    var deckSelection: String?
    /// Tabletop's Links sheet (J-11).
    var linksSheetOpen = false
    /// The verification tag whose explainer is open (0.5.0).
    var tagExplainer: Verification?
    var libraryTab: LibraryTab = .playing
    /// GR-7: games just added together, highlighted in the Library.
    var highlightSet: Set<String> = []
    /// Order games were just added in, for the pop stagger.
    var addedOrder: [String] = []
    /// Set when a deep link asks the journal to bring a release to the top.
    var focusReleaseID: String?
    var focusToken = 0
    var showDebugOverlay = false
    /// QA (route "many-updates"): pad the deck with copies of its cards (distinct ids) up to 12, so the Open
    /// portrait "+N more updates" chip shows whatever the library holds.
    var qaPadDeck = false
    /// QA (routes "one-update", "two-update") and tests: how many fresh unread updates the demo has; 0 is the normal demo.
    var qaUpdateCount = 0
    var qaSingleUpdate: Bool {
        get { qaUpdateCount > 0 }
        set { qaUpdateCount = newValue ? 1 : 0 }
    }
    /// QA: the internal route last applied (host of the URL), shown on the Library probe so the Mac can
    /// confirm a `-qaRoute` took effect.
    var qaRoute: String?
    /// QA (INTERNAL, `-qaRoute long-text`): a long overview body, to show the Tabletop stage cap and the Full text row.
    var qaLongText = false
    /// QA: the newest On PS5 update of the first `qaUpdateCount` different games are the only unread ones. Chosen
    /// when first asked (not at launch, when releases may not be merged yet), so a later feed refresh or the 72 hour
    /// rule cannot take them away.
    @ObservationIgnored private var qaFreshCache: Set<String>?
    private func qaFreshIDs() -> Set<String> {
        if let ids = qaFreshCache { return ids }
        var newestPerGame: [Release] = []
        for entry in data.collection {
            let best = releases(entry.gameID).filter { $0.ps5State == .onPS5 }.max { $0.ps5Date < $1.ps5Date }
            if let best { newestPerGame.append(best) }
        }
        newestPerGame.sort { $0.ps5Date > $1.ps5Date }
        let ids = Set(newestPerGame.prefix(qaUpdateCount).map(\.id))
        qaFreshCache = ids
        return ids
    }
    /// The pose being laid out right now, written by RootView as it renders. Lets navigation
    /// bindings tell a user's Back from a container being torn down by a pose change. Not observed.
    @ObservationIgnored var livePose: Pose = .closed
    /// Book, or Open in landscape: two pages side by side, so the Add sheet is a right-page panel, not a system sheet.
    @ObservationIgnored var liveRightPage = false
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
            // A real first launch starts empty, on onboarding: demo games never appear in a
            // player's library. QA launches (-qaRoute, other than first-run) still seed the demo set;
            // real installs never pass -qaRoute.
            let args = ProcessInfo.processInfo.arguments
            if args.contains("-qaRoute") && !args.contains("first-run") {
                data = PersistedState(collection: Fixtures.shared.seedCollection)
            } else {
                data = PersistedState(collection: [])
            }
        }
        // A6: remember the previous open for the catch-up card, then stamp this one.
        catchUpSince = data.lastOpenedAt
        data.lastOpenedAt = .now
        rebuildMerged()
    }

    /// The previous launch's open time (nil on a first launch); the catch-up card's cut-off.
    @ObservationIgnored var catchUpSince: Date?
    /// The card is shown once per launch; marking read or dismissing hides it.
    var catchUpHidden = false

    /// Unread On PS5 updates that arrived since the last open, newest first.
    var catchUpItems: [(game: CatalogGame, release: Release)] {
        guard !catchUpHidden, let since = catchUpSince else { return [] }
        let cutoff = Date.now.addingTimeInterval(-72 * 3600)
        return data.collection.flatMap { c -> [(CatalogGame, Release)] in
            guard let g = game(c.gameID) else { return [] }
            return ps5Releases(c.gameID).filter { isUnread($0) && $0.ps5Date > since && $0.alertDate > cutoff }.map { (g, $0) }
        }
        .sorted { $0.1.ps5Date > $1.1.ps5Date }
        .map { (game: $0.0, release: $0.1) }
    }

    func markCatchUpRead() {
        let ids = catchUpItems.map(\.release.id)
        for id in ids { data.read[id] = .now }
        catchUpHidden = true
        NotificationService.shared.updateBadge(badgeCount)
    }

    /// Full per-game histories (games/<id>.json), keyed by the app's game id.
    var gameReleases: [String: [Release]] = [:] { didSet { rebuildMerged() } }
    @ObservationIgnored var historyStamps: [String: String] = [:]
    /// Known issues per game from games/<id>.json.
    var gameIssues: [String: [KnownIssue]] = [:]

    private func rebuildMerged() {
        let curated = Dictionary(fixtures.releases.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        var seen = Set<String>()
        var out: [Release] = []
        // A game's own history is the fullest copy; latest.json fills in the rest.
        let histories = gameReleases.values.flatMap { $0 }
        let historyIDs = Set(histories.map(\.id))
        for f in histories + feedReleases.filter({ !historyIDs.contains($0.id) }) {
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
            // Only the app's own model speaks for this device; a model on a scratch store (tests, previews) never does.
            if let self, self.storeURL == AppModel.defaultStoreURL, PushRegistrar.appCallsEnabled { PushRegistrar.syncFollows(self.follows) }
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

    /// Games opened from Upcoming without being filed anywhere. Memory only: never in the library or the saved data.
    var browsedGames: [String: CatalogGame] = [:]

    /// Opens a game page without adding it to the library (opening is not a watchlist action).
    func browseGame(_ game: CatalogGame) {
        if entry(game.id) == nil { browsedGames[game.id] = game }
        openGame(game.id)
    }

    var games: [String: CatalogGame] {
        var map = Dictionary(uniqueKeysWithValues: fixtures.games.map { ($0.id, $0) })
        for g in browsedGames.values { map[g.id] = g }
        for g in data.customGames { map[g.id] = g }
        return map
    }

    func game(_ id: String) -> CatalogGame? { games[id] }

    func entry(_ gameID: String) -> CollectionEntry? { data.collection.first { $0.gameID == gameID } }

    /// Every visible release for a game, newest first. Pending releases are never shown.
    func releases(_ gameID: String) -> [Release] {
        let now = clock
        return (data.simulated + allReleasesMerged)
            // Steam is the source of truth (Terry, 26 Oct): a release only the press reports is not shown.
            // A PS4 patch is the exception (Terry, 6 Nov: PS4 history counts): it has no Steam post, so it shows,
            // tagged Reported, and never alerts or counts as unread.
            .filter { $0.gameID == gameID && $0.ps5State != .pending && ($0.ps5State != .reported || $0.ps4 == true) && ($0.arrivesAt ?? .distantPast) <= now }
            .sorted { Self.newer($0, $1, by: \.latestDate) }
    }

    /// Newest first by a date, ties broken by when the update was announced, then by id, so equal PS5 dates
    /// (a launch batch) never leave an old patch in front of the latest (Terry, 0.2.0 build 5: Enshrouded opened on patch 1).
    static func newer(_ a: Release, _ b: Release, by date: KeyPath<Release, Date>) -> Bool {
        if a[keyPath: date] != b[keyPath: date] { return a[keyPath: date] > b[keyPath: date] }
        if a.announcedAt != b.announcedAt { return a.announcedAt > b.announcedAt }
        return a.id > b.id
    }

    func release(_ gameID: String, _ releaseID: String) -> Release? {
        releases(gameID).first { $0.id == releaseID }
    }

    func ps5Releases(_ gameID: String) -> [Release] {
        releases(gameID).filter(\.isPS5Listed).sorted { Self.newer($0, $1, by: \.ps5Date) }
    }

    func pcOnlyReleases(_ gameID: String) -> [Release] {
        releases(gameID).filter { !$0.isPS5Listed }
    }

    func isUnread(_ r: Release) -> Bool {
        if qaUpdateCount > 0 { return r.ps5State == .onPS5 && qaFreshIDs().contains(r.id) }
        return r.ps5State == .onPS5 && data.read[r.id] == nil
    }

    func unreadCount(_ gameID: String) -> Int { releases(gameID).filter(isUnread).count }

    func latestOnPS5(_ gameID: String) -> Release? {
        ps5Releases(gameID).first { $0.ps5State == .onPS5 }
    }

    func notifyLevel(_ gameID: String) -> NotifyLevel { data.notify[gameID]?.level ?? notifyDefault }
    var notifyDefault: NotifyLevel { data.notifyDefault ?? .all }
    func hasOwnNotify(_ gameID: String) -> Bool { data.notify[gameID] != nil }
    /// Library games with their own setting, for Settings' plain list.
    var notifyOverrides: [(game: CatalogGame, level: NotifyLevel)] {
        libraryRows.compactMap { r in data.notify[r.id].map { (r.game, $0.level) } }
    }

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
            case .updates, .news, .mybook, .gallery: true
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
        if !sameGame { n.detailReleaseID = nil }
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
        // N-7: the pill goes only when the page it points to is the one now showing.
        if let p = pill, isViewing(p.gameID, p.releaseID) { pill = nil }
        focusReleaseID = releaseID
        focusToken += 1
    }

    /// True when the update page for this release is the one on screen: its game is open and the release is the one
    /// the Page shows or the pushed detail screen.
    func isViewing(_ gameID: String, _ releaseID: String) -> Bool {
        guard nav.tab == .library, nav.gameID == gameID else { return false }
        if nav.detailReleaseID != nil { return nav.detailReleaseID == releaseID }
        return nav.chapter == .updates && selectedRelease(gameID)?.id == releaseID
    }

    /// D-2/D-3: the release the Page shows: the one picked, else the newest On PS5 release.
    func selectedRelease(_ gameID: String) -> Release? {
        if let id = nav.selected?[gameID], let r = release(gameID, id) { return r }
        // With no PS5 release the Page leads with the game's release and basics, not a PC patch.
        return ps5Releases(gameID).first
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
            // A cold launch from a notification can beat the game's history: fetch it, then re-resolve
            // before deciding the update is gone.
            Task {
                await refreshHistories([gameID])
                if release(gameID, releaseID) != nil {
                    openGame(gameID, chapter: .updates, releaseID: releaseID)
                } else {
                    show(Toast(text: "That update is no longer available"))
                }
            }
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
        // The Release configuration also defines INTERNAL, so a TestFlight or App Store build
        // (which carries a receipt) must still ignore them: any app or web page could send the URL.
        guard BuildChannel.showsInternalTools else { return }
        qaRoute = url.host()
        switch url.host() {
        case "add":
            addSheetOpen = true
            if parts.first == "scan" { addSheetMethod = .camera; simulatedScan = true }
            if parts.first == "keyboard" { addSheetMethod = .typeIt; addSearchFocus = true }
        case "settings":
            settingsOpen = true
            if parts.first == "quiet" { data.quietHours = QuietHours() }
        case "tag" where parts.count == 1: if let v = Verification(rawValue: parts[0]) { tagExplainer = v }
        case "library":
            nav.tab = .library; nav.gameID = nil
            // QA: `library/upcoming` and `library/playing` pick the Library's Playing / Upcoming switch;
            // `library/upcoming-seeded` also watches five upcoming games (3 out this week, 2 later) so the short sections pack.
            if parts.first == "upcoming-seeded" { resetDemo(); seedUpcomingWatchlist(); libraryTab = .upcoming }
            else if let t = parts.first.flatMap(LibraryTab.init(rawValue:)) { libraryTab = t }
        case "updates": nav.tab = .updates
        case "search": nav.tab = .search
        case "video" where parts.count == 2: openGame(parts[0], releaseID: parts[1]); player = (parts[0], parts[1])
        case "chapter" where parts.count == 2: openGame(parts[0], chapter: Chapter(rawValue: parts[1]))
        case "first-run": resetToFirstRun()
        case "demo": resetDemo()
        case "store-set":
            loadStoreSet(plus: parts.first == "plus")
            // "store-set/end": the Library scrolled as far as it goes, to check the last row clears the tab bar.
            if parts.first == "end", let last = StoreSet.gameIDs.last { nav.anchors["library"] = "lib-\(last)" }
        case "one-update": resetToOneUpdateDemo(); if parts.first == "updates" { nav.tab = .updates }   // e.g. two-update/updates: unread rows, Updates tab
        case "two-update": resetToTwoUpdateDemo(); if parts.first == "updates" { nav.tab = .updates }   // e.g. two-update/updates: unread rows, Updates tab
        case "many-updates": resetToManyUpdatesDemo(); if parts.first == "updates" { nav.tab = .updates }   // e.g. two-update/updates: unread rows, Updates tab
        case "three-update": resetToUpdateDemo(count: 3); if parts.first == "updates" { nav.tab = .updates }   // e.g. two-update/updates: unread rows, Updates tab
        case "four-update": resetToUpdateDemo(count: 4); if parts.first == "updates" { nav.tab = .updates }   // e.g. two-update/updates: unread rows, Updates tab
        case "caught-up": resetToCaughtUpDemo()
        case "plus-demo": resetDemo(); PlusStore.shared.qaShowDemoMonth()
        case "pill": holdQAPill()
        // QA (INTERNAL, B-10): "quick/tip" shows the press-and-hold tip; "quick/undo" removes the first game so the
        // 6 s Undo toast shows. The long-press menu and the yellow Wishlist disc show on the demo library as is.
        case "quick" where parts.first == "tip": resetDemo(); nav.anchors["library"] = "lib-kcd2"; showPressTipIfNeeded(force: true)
        // QA (INTERNAL): "upcoming-demo" opens Library > Upcoming with watched games, one with a long name, so the AX rows can be judged.
        case "upcoming-demo": resetDemo(); seedUpcomingDemo()
        case "quick" where parts.first == "wishlist":
            resetDemo()
            setStatus("kcd2", .wishlist); setStatus("control-resonant", .wishlist)
            nav.anchors["library"] = "lib-kcd2"   // scroll the grid into view, clear of the tab capsule
        case "quick" where parts.first == "undo":
            resetDemo()
            nav.anchors["library"] = "lib-kcd2"
            if let id = data.collection.first(where: { $0.status == .wishlist })?.gameID ?? data.collection.first?.gameID { removeGame(id) }
        case "long-text": qaLongText = true
        case "plus": nav.tab = .library; nav.gameID = nil; PlusStore.shared.setQA(parts.first ?? "3")
        case "spoiler-demo": openSpoilerDemo(shown: parts.first == "shown")
        case "overlay": showDebugOverlay.toggle(); FoldAuditSwitch.enabled = true
        case "simulate" where parts.count == 2:
            Task {
                // Never wait on the permission prompt for good: f526773, a fresh sim, locked screen: no prompt was presented, the
                // request never returned and nothing was scheduled in 40 s ("qa-schedule: none"). Ask, give the prompt 8 s, then
                // schedule anyway: a pending request is delivered once permission is granted, and the test reports the status.
                if NotificationService.shared.authorization == .notDetermined {
                    Task { _ = await NotificationService.shared.requestAuthorization() }
                    for _ in 0..<16 where NotificationService.shared.authorization == .notDetermined { try? await Task.sleep(for: .milliseconds(500)) }
                }
                // QA: earlier runs leave their notifications in Notification Center and on the lock screen; the test taps
                // "the Dawnwalker row", so sweep them first and there is exactly one (e411c788: taps landed on a stale pile).
                UNUserNotificationCenter.current().removeAllDeliveredNotifications()
                simulateUpdate(gameID: parts[0], kind: parts[1] == "hotfix" ? .hotfix : .major, delay: 3)
            }
        case "links" where parts.count == 1: openGame(parts[0]); linksSheetOpen = true
        // QA (INTERNAL): a PS5 update with a very long invented title, to exercise the share-button guard on the release page
        // (r054: a title past 4 lines at AX drops the button to its own row).
        case "long-title" where parts.count == 1:
            let gameID = parts[0]
            let now = Date.now
            let release = Release(
                id: "qa-long-title-\(gameID)", gameID: gameID,
                displayName: "The Grand Autumn Rebalancing, Quality of Life and Stability Update, Including Every Hotfix Since Launch",
                kind: .major, kindBasis: .studio, announcedAt: now, notes: [], sourceIDs: [],
                platforms: [PlatformRelease(platform: .ps5, status: .live,
                                            version: Field(value: "9.9", verification: .official, sourceID: "simulated", checkedAt: now),
                                            liveAt: Field(value: now, verification: .official, sourceID: "simulated", checkedAt: now),
                                            bundles: [], verification: .official)],
                headline: "A long invented title for layout checks", summary: "QA fixture. Not a real release.", keyChanges: [],
                simulated: true, arrivesAt: now)
            data.simulated.removeAll { $0.id == release.id }
            data.simulated.insert(release, at: 0)
            openRelease(gameID: gameID, releaseID: release.id)
        // QA (INTERNAL): a PS5 update whose headline holds one word wider than the AX5 column, shown in the Updates tab
        // (WholeWordText must cut before that word, never mid-word).
        case "long-word" where parts.count == 1:
            let gameID = parts[0]
            let now = Date.now
            let release = Release(
                id: "qa-long-word-\(gameID)", gameID: gameID, displayName: "Patch 9.9",
                kind: .major, kindBasis: .studio, announcedAt: now, notes: [], sourceIDs: [],
                platforms: [PlatformRelease(platform: .ps5, status: .live,
                                            version: Field(value: "9.9", verification: .official, sourceID: "simulated", checkedAt: now),
                                            liveAt: Field(value: now, verification: .official, sourceID: "simulated", checkedAt: now),
                                            bundles: [], verification: .official)],
                headline: "Reworked Weapon Rebalancing, Counterbalanced Overencumberment and Quality of Life",
                summary: "QA fixture. Not a real release.", keyChanges: [], simulated: true, arrivesAt: now)
            data.simulated.removeAll { $0.id == release.id }
            data.simulated.insert(release, at: 0)
            nav.tab = .updates
        // QA (INTERNAL): the game page itself (Contents in Open portrait and Book, the Page in Closed), never a pushed release.
        case "gamepage" where parts.count == 1:
            openGame(parts[0], chapter: .updates)
            nav.detailReleaseID = nil
            linksSheetOpen = false
        case "close": player = nil; addSheetOpen = false; simulatedScan = false; settingsOpen = false; linksSheetOpen = false; tagExplainer = nil; addSearchFocus = false
        case "fill-library" where parts.count == 1:
            // QA: a library of N games (the demo set plus popular PS5 games), for layout tests.
            if let n = Int(parts[0]) {
                let missing = PS5Index.shared.popular(limit: 60).filter { g in !data.collection.contains { $0.gameID == g.id } }
                for g in missing.prefix(max(0, n - data.collection.count)) { insertGame(g, status: .owned) }
                nav.anchors["library"] = nil   // QA: a persisted scroll position from an earlier run must not open the Library at the bottom
            }
        case "side" where parts.count == 1: UserDefaults.standard.set(parts[0] == "left", forKey: ReadingSide.key)
        case "add-game" where parts.count == 1:
            // Adds a game from the PS5 index by IGDB id, as the Add button does (A-5, F-5, N-1).
            if let id = Int(parts[0]), let e = PS5Index.shared.entries.first(where: { $0.i == id }) {
                addGame(PS5Index.shared.game(e), status: .owned)
            }
        case "remove-game" where parts.count == 1: removeGame(parts[0])
        case "alerts", "alerts-denied":
            // QA: the Library with the alerts card showing, undecided or denied (N-1).
            resetDemo()
            NotificationService.shared.qaForcedAuthorization = url.host() == "alerts" ? .notDetermined : .denied
        case "ask-notifications": Task { await NotificationService.shared.requestAuthorization() }
        default: break
        }
        #endif
    }

    // MARK: - Reading

    func isExpanded(_ key: String, default value: Bool = false) -> Bool { nav.expanded[key] ?? value }

    func setExpanded(_ key: String, _ value: Bool) { nav.expanded[key] = value }

    /// A cold launch opens on the Library, not the last screen.
    func startFresh() {
        nav.gameID = nil
        nav.detailReleaseID = nil
        nav.tab = .library
        addSheetOpen = false
        settingsOpen = false
    }

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
            // The destination is one tap away (Terry, 0.2.0 build 5: "there is no My Book").
            show(Toast(text: "Bookmarked", undo: { [weak self] in self?.openGame(gameID, chapter: .mybook) }, actionLabel: "Open My book"))
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
        // Adding a game never floods the badge: whatever it already has before today's news is the past.
        markPastAsRead(new.flatMap { releases($0.id) }, backCatalogue: true)
        let ids = new.map(\.id)
        nav.filter = .all
        highlight = new.count == 1 ? ids[0] : nil
        highlightSet = Set(ids)
        addedOrder = ids
        nav.anchors["library"] = "lib-\(ids[0])"
        let text = new.count == 1 ? "Added \(new[0].name)" : "Added \(new.count) games"
        show(Toast(text: text, undo: { [weak self] in ids.forEach { self?.removeGame($0, toast: false) } }))
        if data.soundsOff != true { PopSound.play(count: new.count, quiet: data.quietHours) }
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
        // New games follow the default; a per-game level is only set from the game's bell.
        if isFirst { data.notificationCardShows = max(data.notificationCardShows, 0) }
    }

    /// QA only: watched, unreleased games (one this week, two later, one with a very long name) and the Upcoming tab selected.
    func seedUpcomingDemo() {
        let day = ISO8601DateFormatter(); day.formatOptions = [.withFullDate]
        func iso(_ days: Int) -> String { day.string(from: Date().addingTimeInterval(Double(days) * 86400)) }
        let samples: [(String, String, Int)] = [("qa-up-1", "The Long Quiet Orchard of Wending Hollow", 3), ("qa-up-2", "Ash and Ember", 40),
                                                ("qa-up-3", "Mortal Shell: Hollow Bells", 90)]
        for (i, s) in samples.enumerated() {
            insertGame(CatalogGame(id: s.0, name: s.1, platforms: [.ps5], releaseDate: iso(s.2), releasePrecision: .day,
                                   igdbID: 990000 + i, coverage: .none), status: .watching)
        }
        libraryTab = .upcoming
        nav.tab = .library; nav.gameID = nil
    }

    /// QA (INTERNAL, route `library/upcoming-seeded`): five watched games dated 1, 2 and 4 days out, then 30 and 60.
    private func seedUpcomingWatchlist() {
        let offsets = [1, 2, 4, 30, 60]
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = .gmt
        for (source, days) in zip(upcomingMore.prefix(5), offsets) {
            var g = source
            if let d = cal.date(byAdding: .day, value: days, to: .now) {
                g.releaseDate = d.formatted(Date.ISO8601FormatStyle(timeZone: .gmt).year().month().day())
                g.releasePrecision = .day
            }
            insertGame(g, status: .wishlist)
        }
    }

    func setStatus(_ gameID: String, _ status: OwnershipStatus) {
        guard let i = data.collection.firstIndex(where: { $0.gameID == gameID }), data.collection[i].status != status else { return }
        data.collection[i].status = status
        Haptics.selection()
    }

    /// Quick actions tip (Iris): one line the first two times the Library shows, then never again.
    func showPressTipIfNeeded(force: Bool = false) {
        guard !data.collection.isEmpty, force || (data.pressTipShows ?? 0) < 2, toast == nil || force, pill == nil,
              force || (!FoldAuditSwitch.enabled && !UIAccessibility.isVoiceOverRunning) else { return }
        data.pressTipShows = (data.pressTipShows ?? 0) + 1
        show(Toast(text: "Press and hold a game to change or remove it"))
    }

    /// nil: use the default.
    func setNotify(_ gameID: String, _ level: NotifyLevel?) {
        data.notify[gameID] = level.map { NotifyPref(level: $0) }
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
        }, seconds: 6))
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
            try? await Task.sleep(for: .seconds(t.seconds ?? (t.undo == nil ? 2.6 : 8)))
            if self?.toast?.token == token { self?.toast = nil }
        }
    }

    func toastClear() { toast = nil }

    // MARK: - First run and notification invitation

    /// N-1: the invitation card shows once a game is in the library, until the person decides. "Not now" snoozes it
    /// for a week, three times at most. If iOS notifications are denied it offers Open Settings, on the same schedule.
    var showsNotificationCard: Bool {
        NotificationAsk.shows(hasGames: !data.collection.isEmpty, status: NotificationService.shared.authorization,
                              asks: data.notificationAsks ?? 0, snoozedUntil: data.notificationSnoozedUntil)
    }

    /// "Not now", a swipe, or a declined system prompt: ask again in a week (N-1).
    func snoozeNotificationCard() {
        data.notificationAsks = (data.notificationAsks ?? 0) + 1
        data.notificationSnoozedUntil = Calendar.current.date(byAdding: .day, value: NotificationAsk.snoozeDays, to: .now)
    }

    func resetToFirstRun() {
        data = PersistedState(collection: [])
        UserDefaults.standard.set(false, forKey: "didOnboard")
        toast = nil
        pill = nil
        NotificationService.shared.updateBadge(0)
    }

    func resetDemo() {
        qaPadDeck = false
        qaUpdateCount = 0
        qaFreshCache = nil
        data = PersistedState(collection: fixtures.seedCollection)
        UserDefaults.standard.set(true, forKey: "didOnboard")
        NotificationService.shared.updateBadge(badgeCount)
    }

    /// QA (INTERNAL, `-qaRoute pill`): hold the "New on PS5" pill on screen (no 4 s timeout) so a swipe-dismiss
    /// can be tested. Uses the newest On PS5 release in the collection. Nothing user-facing changes.
    func holdQAPill() {
        var newest: Release?
        var gameID = ""
        for entry in data.collection {
            for r in releases(entry.gameID) where r.ps5State == .onPS5 {
                if let n = newest, n.ps5Date >= r.ps5Date { continue }
                newest = r
                gameID = entry.gameID
            }
        }
        guard let r = newest else { return }
        showPill(gameID: gameID, releaseID: r.id, after: 3600)
    }

    /// QA and tests: the full demo library with exactly one fresh, unread On PS5 update (so the Library
    /// hero shows) and every other update read.
    func resetToOneUpdateDemo() {
        resetDemo()
        qaUpdateCount = 1
    }

    /// QA (route "caught-up"): every update read, so the Library has no hero (Book shows the caught-up card).
    func resetToCaughtUpDemo() {
        resetDemo()
        qaUpdateCount = 1
        qaFreshCache = []
    }

    /// QA and tests (route "two-update"): as the one-update demo with two fresh updates, from different games.
    func resetToTwoUpdateDemo() {
        resetDemo()
        qaUpdateCount = 2
    }

    /// QA (route "many-updates"): every catalog game with an On PS5 update joins the library, so the deck is full
    /// and the Open portrait "+N more updates" chip shows when more than 8 updates qualify.
    func resetToManyUpdatesDemo() {
        resetDemo()
        let have = Set(data.collection.map(\.gameID))
        let more = fixtures.games.filter { !have.contains($0.id) && !ps5Releases($0.id).filter { $0.ps5State == .onPS5 }.isEmpty }
        addGames(more, status: .owned)
        qaPadDeck = true
    }

    /// QA (routes "three-update", "four-update"): `count` fresh updates from different games, so the deck
    /// has that many unread cards.
    func resetToUpdateDemo(count: Int) {
        resetDemo()
        qaUpdateCount = count
    }

    #if INTERNAL
    /// The `-qaRoute` / `-qaOverlay` launch arguments. Ignored in a distribution build (one with a
    /// TestFlight or App Store receipt), exactly like the playscribe:// QA routes.
    func applyQALaunch(route: String?, overlay: Bool) {
        guard BuildChannel.showsInternalTools else { return }
        if overlay { showDebugOverlay = true; FoldAuditSwitch.enabled = true }
        if let route, let url = URL(string: "playscribe://\(route)") { handle(url: url) }
    }

    /// QA (INTERNAL, route "spoiler-demo"): opens a bundled-game patch dated 19 Apr 2025 whose notes
    /// open with a greeting and a spoiler warning, as Blue Prince 1.2 does in the live feed, so the
    /// reader's spoiler switch, counts and year can be stilled in the simulator with no network.
    func openSpoilerDemo(shown: Bool = false) {
        resetDemo()
        guard let gameID = fixtures.games.first?.id else { return }
        let when = Date(timeIntervalSince1970: 1_745_020_800)
        var pcLine = NoteItem(text: "PC only: fixed a window mode crash.")
        pcLine.pcOnly = true
        let items = ["Hello!", "Be advised, the following notes contain spoilers so browse at your own peril:",
                     "Fixed the final door staying shut after the lab sequence.",
                     "Fixed the lab camera lock when the machine is reactivated on later days.",
                     "Fixed the ending letter not appearing for players who skipped the parlour scene.",
                     "Fixed a story note that could be read twice in the archive room.",
                     "Fixed the keeper's dialogue repeating after the second reveal.",
                     "Fixed the epilogue map not showing the secret room.",
                     "Misc. typo and text format fixes."].map { NoteItem(text: $0) } + [pcLine]
        let release = Release(
            id: "qa-spoiler-demo", gameID: gameID, displayName: "Patch 1.2", kind: .hotfix, kindBasis: .studio, announcedAt: when,
            notes: [NoteSection(title: "Changes", items: items)], sourceIDs: [],
            platforms: [PlatformRelease(platform: .ps5, status: .live,
                                        version: Field(value: "01.002.000", verification: .official, sourceID: "qa", checkedAt: when),
                                        liveAt: Field(value: when, verification: .official, sourceID: "qa", checkedAt: when),
                                        bundles: [], verification: .official)],
            headline: "Patch 1.2 (QA)", summary: "QA fixture for the spoiler warning reader.", simulated: true, arrivesAt: when)
        setSpoilersShown(gameID, shown)
        data.simulated.removeAll { $0.id == release.id }
        data.simulated.insert(release, at: 0)
        tick()
        openRelease(gameID: gameID, releaseID: release.id)
        // Tabletop's standing half pages through sections: land on "Fixes", where the spoiler lines are.
        if let i = readerSections(release).firstIndex(where: { $0.id == "fixes" }) { readerIndex[gameID] = i }
    }
    #endif

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
        // N-7: shown on every page except the exact update it points to, other pages of the same game included.
        if !isViewing(gameID, releaseID) { showPill(gameID: gameID, releaseID: releaseID) }
        NotificationService.shared.updateBadge(badgeCount)
    }

    /// The "New on PS5" pill dismisses itself after 4 s (Iris, 0.2.0 gate); a swipe also dismisses it.
    /// Under VoiceOver it stays until dismissed.
    func showPill(gameID: String, releaseID: String, after seconds: Double = 4) {
        pill = (gameID, releaseID)
        guard !UIAccessibility.isVoiceOverRunning else { return }
        Task { [weak self] in
            try? await Task.sleep(for: .seconds(seconds))
            if self?.pill?.releaseID == releaseID { self?.pill = nil }
        }
    }
}
