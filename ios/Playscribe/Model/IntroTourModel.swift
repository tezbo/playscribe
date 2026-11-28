import Foundation

/// 6b intro tour state changes (handoff/0.6.0-intro-tour.md). The views live in UI/IntroTour.swift.
extension AppModel {
    /// UI tests and stills launch with `-qaRoute`: the tour never offers itself there, only from a `tour/…` route.
    static var isQALaunch: Bool { ProcessInfo.processInfo.arguments.contains("-qaRoute") }

    /// A fresh install: nothing added, the old guided welcome not used, the tour neither taken nor skipped.
    var offersTourAtLaunch: Bool {
        !Self.isQALaunch && data.tourDone == nil && data.welcomeDone == nil && data.collection.isEmpty
    }

    /// "Take the tour", or Settings > Replay tour: back to the Library, then step 1. The empty Library then shows its
    /// Popular on PS5 row, which is step 1's anchor when there is no game yet.
    func startTour() {
        tourWelcome = false
        if data.welcomeDone == nil { data.welcomeDone = true }
        nav.tab = .library
        nav.gameID = nil
        nav.detailReleaseID = nil
        nav.returnTab = nil
        tourStep = .openGame
    }

    /// Next, or the person did what the step points at.
    func advanceTour() {
        guard let step = tourStep else { return }
        guard let next = step.next else { finishTour(); return }
        if next == .spoiler, let r = tourSpoilerRelease() { openRelease(gameID: r.gameID, releaseID: r.id) }
        tourStep = next
    }

    /// Skip (welcome) or Skip tour (any step): ends it for good, where the person is.
    func endTour() {
        tourWelcome = false
        tourStep = nil
        data.tourDone = true
    }

    /// Done: back to the Library, where the alerts soft-ask (N-1) shows by its own rule. No extra popover.
    func finishTour() {
        endTour()
        nav.detailReleaseID = nil
        nav.updatesRelease = nil
        closeGame()
        nav.tab = .library
    }

    /// Step 3 needs a reader with the spoiler switch, which shows only on an update with spoiler-tagged notes: the newest such
    /// update of a Library game, else of any game. None (offline, no feed): the step is the text-only card.
    func tourSpoilerRelease() -> Release? {
        let hasSpoilers: (Release) -> Bool = { $0.notes.contains { $0.items.contains { $0.spoiler == true } } }
        for entry in data.collection {
            if let r = releases(entry.gameID).first(where: hasSpoilers) { return r }
        }
        let games = Set(allReleasesMerged.filter(hasSpoilers).map(\.gameID))
        return games.compactMap { releases($0).first(where: hasSpoilers) }.min { Self.newer($0, $1, by: \.latestDate) }
    }

    /// bug-077: while the tour runs (its welcome card or any step), the empty Library's game row offers only games whose newest
    /// PS5 update has notes, so the first game a new player opens reads well (Jun's blind playtest: GTA V opened on an update
    /// with no notes). Outside the tour the Popular strip is unfiltered: any game can still be found and added (Nadia).
    var tourActive: Bool { tourWelcome || tourStep != nil }

    /// The tour's row: Popular on PS5 in its own order, keeping the games whose newest PS5 update the app has, from the feed or
    /// the bundled data, has a notes body. A game with no update the app knows of is skipped, as is one only listed by IGDB.
    func tourPopular(limit: Int) -> [CatalogGame] {
        let known = Set((data.simulated + allReleasesMerged).map(\.gameID))
        var byIGDB: [Int: String] = [:]
        for g in feedIndexGames ?? [] { if let i = g.igdbId, byIGDB[i] == nil { byIGDB[i] = g.id } }
        for g in games.values { if let i = g.igdbID { byIGDB[i] = g.id } }   // the catalogue's own id wins
        return Self.tourGames(PS5Index.shared.popular(limit: Self.tourSearchDepth), limit: limit) { g in
            guard let i = g.igdbID, let id = byIGDB[i], known.contains(id) else { return false }
            return Self.newestPS5HasNotes(releases(id))
        }
    }

    /// How far down Popular the tour looks for games with notes.
    static let tourSearchDepth = 400

    /// The fewest games the tour's row may offer; below it the row falls back to plain Popular (Quinn on #677).
    static let tourMinimum = 3

    /// The first `limit` games of `popular`, in order, that qualify. When fewer than `tourMinimum` qualify (a first launch
    /// before the feed has synced, or offline), the first `limit` of Popular unfiltered, so the tour never comes up empty.
    static func tourGames(_ popular: [CatalogGame], limit: Int, qualifies: (CatalogGame) -> Bool) -> [CatalogGame] {
        var out: [CatalogGame] = []
        for g in popular where out.count < limit && qualifies(g) { out.append(g) }
        return out.count < min(tourMinimum, limit) ? Array(popular.prefix(limit)) : out
    }

    /// Whether the newest PS5 update among `releases` (newest by its PS5 date, any order in) has a notes body.
    static func newestPS5HasNotes(_ releases: [Release]) -> Bool {
        guard let newest = releases.filter(\.isPS5Listed).sorted(by: { newer($0, $1, by: \.ps5Date) }).first else { return false }
        return newest.notes.contains { !$0.items.isEmpty }
    }

    /// A step also advances when the person does the thing it points at (opens a game, opens Updates, flips the switch).
    func tourNoticed(openedGame: Bool = false, tab: AppTab? = nil, spoilersToggled: Bool = false) {
        switch tourStep {
        case .openGame where openedGame: advanceTour()
        case .updates where tab == .updates: advanceTour()
        case .spoiler where spoilersToggled: advanceTour()
        default: break
        }
    }
}
