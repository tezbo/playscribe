import Testing
@testable import Playscribe

/// N-9, one ask per screen: the follow-list card waits for the alerts card's answer and for the next Library appearance.
struct KeepCurrentAskTests {
    private func shows(games: Bool = true, on: Bool = false, dismissed: Bool = false, alertsCard: Bool = false,
                       answered: Bool = true, thisSession: Bool = false) -> Bool {
        KeepCurrentAsk.shows(hasGames: games, on: on, dismissed: dismissed, alertsCardShows: alertsCard,
                             alertsAnswered: answered, answeredThisSession: thisSession)
    }

    @Test func showsAloneOnceAlertsWereAnsweredEarlier() { #expect(shows()) }

    @Test func neverStacksOnTheAlertsCard() { #expect(!shows(alertsCard: true)) }

    @Test func waitsForTheAlertsAnswerAndTheNextAppearance() {
        #expect(!shows(answered: false))
        #expect(!shows(thisSession: true))
    }

    @Test func goneOnceAnsweredOrOn() {
        #expect(!shows(on: true))
        #expect(!shows(dismissed: true))
        #expect(!shows(games: false))
    }
}
