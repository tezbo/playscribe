import Foundation
import Testing
@testable import Playscribe

/// PS Plus card and "Leaving soon" (r050-plus-card): which month shows, when it is the last chance, when the reminder fires.
@MainActor
struct PlusLogicTests {
    private var cal: Calendar { var c = Calendar(identifier: .gregorian); c.timeZone = .gmt; return c }
    private func day(_ s: String, hour: Int = 12) -> Date {
        let p = s.split(separator: "-").compactMap { Int($0) }
        return cal.date(from: DateComponents(year: p[0], month: p[1], day: p[2], hour: hour))!
    }
    private let nov = PlusMonth(month: "2026-11", from: "2026-11-04", until: "2026-12-01", games: [.init(name: "A", gameId: nil), .init(name: "B", gameId: "kcd2")])
    private let dec = PlusMonth(month: "2026-12", from: "2026-12-02", until: "2027-01-05", games: [.init(name: "C", gameId: nil)])

    @Test func showsTheMonthWhoseWindowHoldsToday() {
        let r = PlusLogic.current([dec, nov], now: day("2026-11-10"), calendar: cal)
        #expect(r?.month.month == "2026-11")
        #expect(r?.lastChance == false)
    }

    @Test func windowIsInclusiveOnBothDays() {
        #expect(PlusLogic.current([nov], now: day("2026-11-04"), calendar: cal) != nil)
        #expect(PlusLogic.current([nov], now: day("2026-12-01"), calendar: cal) != nil)
        #expect(PlusLogic.current([nov], now: day("2026-11-03"), calendar: cal) == nil)
        #expect(PlusLogic.current([nov], now: day("2026-12-02"), calendar: cal) == nil)
    }

    @Test func lastChanceIsTheLastThreeClaimDays() {
        #expect(PlusLogic.current([nov], now: day("2026-11-29"), calendar: cal)?.lastChance == true)
        #expect(PlusLogic.current([nov], now: day("2026-12-01"), calendar: cal)?.lastChance == true)
        #expect(PlusLogic.current([nov], now: day("2026-11-28"), calendar: cal)?.lastChance == false)
    }

    /// Terry 2026-11-05: the Settings switch hides the card; on by default (nil).
    @Test func cardOffHidesTheCardAndDefaultShowsIt() {
        let now = day("2026-11-10")
        #expect(PlusLogic.visibleMonth([nov], cardOff: nil, now: now, calendar: cal) != nil)
        #expect(PlusLogic.visibleMonth([nov], cardOff: false, now: now, calendar: cal) != nil)
        #expect(PlusLogic.visibleMonth([nov], cardOff: true, now: now, calendar: cal) == nil)
    }

    @Test func noMonthsOrNoGamesHidesTheCard() {
        #expect(PlusLogic.current([], now: day("2026-11-10"), calendar: cal) == nil)
        var empty = nov; empty.games = []
        #expect(PlusLogic.current([empty], now: day("2026-11-10"), calendar: cal) == nil)
    }

    @Test func reminderFiresAtTenOnTheFirstOfTheLastThreeDays() {
        let fire = PlusLogic.leavingSoonFire(nov, now: day("2026-11-10"), calendar: cal)
        #expect(fire == day("2026-11-29", hour: 10))
        #expect(PlusLogic.leavingSoonFire(nov, now: day("2026-11-29", hour: 11), calendar: cal) == nil, "already past")
    }

    @Test func decodingIgnoresUnknownKeys() throws {
        let json = #"{"version":1,"extra":true,"months":[{"month":"2026-11","from":"2026-11-04","until":"2026-12-01","note":"x","games":[{"name":"A","extra":1},{"name":"B","gameId":"kcd2"}]}]}"#
        let f = try JSONDecoder().decode(PlusFile.self, from: Data(json.utf8))
        #expect(f.months.first?.games.count == 2)
        #expect(f.months.first?.games.last?.gameId == "kcd2")
    }
}

/// The PS Plus card's cover art: a lineup name resolves to a catalogue game only on an exact title match.
@MainActor
struct PlusCoverTests {
    @Test func unknownTitleDrawsThePlateNotAWrongCover() {
        let g = PlusMonth.Game(name: "Zzzz Not A Real Game Title 9999", gameId: nil)
        #expect(PlusCard.resolve(g, tracked: { _ in nil }) == nil)
    }

    @Test func aTrackedGameIdWinsOverTheIndex() {
        let tracked = CatalogGame(id: "kcd2", name: "Kingdom Come: Deliverance II", platforms: [.ps5], coverage: .none)
        let g = PlusMonth.Game(name: "Anything", gameId: "kcd2")
        #expect(PlusCard.resolve(g, tracked: { $0 == "kcd2" ? tracked : nil })?.id == "kcd2")
    }

    @Test func romanAndArabicNumeralsMatchTheSameTitle() {
        #expect(PlusCard.matchKey("Alan Wake 2") == PlusCard.matchKey("Alan Wake II"))
        #expect(PlusCard.matchKey("The Last of Us Part II") == PlusCard.matchKey("Last of Us Part 2"))
        #expect(PlusCard.matchKey("Alan Wake 2") != PlusCard.matchKey("Alan Wake Remastered"))
    }

    @Test func alanWake2FindsTheIndexCoverNotAPlate() {
        let g = PlusMonth.Game(name: "Alan Wake 2", gameId: nil)
        #expect(PlusCard.resolve(g, tracked: { _ in nil })?.igdbID == 185246)
    }

    @Test func anUntrackedPlusTitleOpensItsPageWithoutJoiningTheLibrary() {
        let m = AppModel(storeURL: URL.temporaryDirectory.appending(path: "plus-\(UUID().uuidString).json"))
        let g = PlusMonth.Game(name: "Zzzz Not In The Index 9999", gameId: nil, coverId: "co1abc")
        let game = PlusCard.resolve(g, tracked: { m.game($0) })!
        let before = m.data.collection.count
        m.browseGame(game)                       // what a Plus cover or name row calls
        #expect(m.nav.gameID == game.id)
        #expect(m.game(game.id)?.name == g.name)
        #expect(m.data.collection.count == before)
        #expect(PlusCard.resolve(.init(name: "Zzzz Nothing 9999", gameId: nil), tracked: { _ in nil }) == nil)
    }

    @Test func aFeedCoverIdFillsAGapInTheIndexButNeverReplacesAMatch() {
        let missing = PlusMonth.Game(name: "Zzzz Not In The Index 9999", gameId: nil, coverId: "co1abc")
        let hit = PlusCard.resolve(missing, tracked: { _ in nil })
        #expect(hit?.coverImageID == "co1abc")
        #expect(hit?.coverURL?.absoluteString.hasSuffix("/co1abc.jpg") == true)
        let indexed = PlusMonth.Game(name: "Alan Wake 2", gameId: nil, coverId: "co9wrong")
        #expect(PlusCard.resolve(indexed, tracked: { _ in nil })?.igdbID == 185246)
    }

    @Test func extraNamesReadAsOnePlusLine() {
        #expect(PlusCard.plusLine([]) == nil)
        #expect(PlusCard.plusLine(["Returnal"]) == "Plus Returnal")
        #expect(PlusCard.plusLine(["Returnal", "Astro Bot"]) == "Plus Returnal and Astro Bot")
        #expect(PlusCard.plusLine(["A", "B", "C"]) == "Plus A, B and C")
    }

    @Test func atMostThreeCoversShow() {
        #expect(PlusCard.coverLimit(accessibility: false) == 3)
    }

    @Test func accessibilitySizesShowTwoCovers() {
        #expect(PlusCard.coverLimit(accessibility: true) == 2)
    }
}

/// The Settings debug Pose row uses the gate's names, not the enum's (Mac QA, #242).
struct PoseLabelTests {
    @Test func everyPoseHasTheGateName() {
        #expect(Pose.closed.label == "Closed")
        #expect(Pose.flat.label == "Open")
        #expect(Pose.book.label == "Book")
        #expect(Pose.tabletop.label == "Tabletop")
    }
}
