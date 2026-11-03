import XCTest
@testable import HustlerCore

/// The ring card and the archive note are `renderGame()`'s `#follow`,
/// `#followTxt` and `#estNote`. The fixtures are the ones `ScoreboardTests`
/// pins, so the card and the tiles are checked against the same log.
final class HomeFollowCardTests: XCTestCase {

    private var settings: VerdictSettings { VerdictSettings() }

    private func rows(_ text: String) -> [LogRow] {
        MasterLog.orderedForAnalysis(MasterLogParser.parse(text))
    }

    /// A shortcut row that either followed its verdict or went against it.
    private func live(followed: Bool) -> LogRow {
        LogRow(
            date: "2026-10-27",
            time: "12:00",
            payout: "10.00",
            miles: "4.0",
            verdict: "TAKE IT",
            choice: followed ? "Accept" : "Declined"
        )
    }

    private func card(followed: Int, of total: Int) -> HomeFollowCard.Card {
        HomeFollowCard.card(rows: (0..<total).map { live(followed: $0 < followed) })
    }

    /// No archive rows: the ring is over the whole log and the note is empty.
    func testAllLiveRows() {
        let log = rows(Fixtures.headerLiteral + "\n" + [
            Fixtures.scoreboardFirstRow,
            Fixtures.scoreboardSecondRow,
            Fixtures.scoreboardThirdRow
        ].joined(separator: "\n"))

        let card = HomeFollowCard.card(rows: log)
        XCTAssertEqual(card.totalOffers, 3)
        XCTAssertEqual(card.loggedOffers, 3)
        XCTAssertEqual(card.followedOffers, 3)
        XCTAssertEqual(card.percent, 100)
        XCTAssertEqual(card.percentText, "100%")
        XCTAssertEqual(card.ringFill, 1.0, accuracy: 1e-12)
        XCTAssertEqual(card.text, "3 of 3 logged offers matched the verdict. Locked in.")
        XCTAssertEqual(card.note, "")
    }

    /// Archive rows count as offers but never as logged offers, so they move the
    /// note and not the percentage.
    func testMixedArchiveAndLiveRows() {
        let log = rows(Fixtures.scoreboardMixed)
        let card = HomeFollowCard.card(rows: log)

        XCTAssertEqual(card.totalOffers, 6)
        XCTAssertEqual(card.loggedOffers, 4)
        XCTAssertEqual(card.followedOffers, 4)
        XCTAssertEqual(card.percent, 100)
        XCTAssertEqual(card.percentText, "100%")
        XCTAssertEqual(card.text, "4 of 4 logged offers matched the verdict. Locked in.")
        XCTAssertEqual(card.note, "2 deliveries come from your DoorDash archive, with estimated pay and miles.")
        XCTAssertEqual(card.percent, Scoreboard.totals(log, settings: settings).followedPercent)
        XCTAssertEqual(card.loggedOffers, Scoreboard.totals(log, settings: settings).loggedOffers)
        XCTAssertEqual(card.totalOffers, Scoreboard.totals(log, settings: settings).offers)
    }

    /// Archive-only: no verdicts, so the ring is empty, the number is `0%` and
    /// the sentence explains why. The note still names every row.
    func testOnlyArchiveRows() {
        let card = HomeFollowCard.card(rows: rows(Fixtures.scoreboardArchiveOnly))

        XCTAssertEqual(card.totalOffers, 2)
        XCTAssertEqual(card.loggedOffers, 0)
        XCTAssertEqual(card.followedOffers, 0)
        XCTAssertEqual(card.percent, 0)
        XCTAssertEqual(card.percentText, "0%", "only an empty log shows --")
        XCTAssertEqual(card.ringFill, 0)
        XCTAssertEqual(card.text, "Archive rows have no verdicts. Log offers with the shortcut to see this.")
        XCTAssertEqual(card.note, "2 deliveries come from your DoorDash archive, with estimated pay and miles.")
    }

    /// No rows at all: an empty ring, `--` instead of a number, no note.
    func testNoRows() {
        let card = HomeFollowCard.card(rows: [])

        XCTAssertEqual(card.totalOffers, 0)
        XCTAssertEqual(card.loggedOffers, 0)
        XCTAssertEqual(card.percent, 0)
        XCTAssertEqual(card.percentText, "--")
        XCTAssertEqual(card.ringFill, 0)
        XCTAssertEqual(card.text, "Archive rows have no verdicts. Log offers with the shortcut to see this.")
        XCTAssertEqual(card.note, "")
    }

    /// 85% is the last "Locked in." step; the comparison is on the rounded
    /// percent, as `fp>=85` is on the web.
    func testExactlyEightyFivePercentIsLockedIn() {
        let card = self.card(followed: 17, of: 20)

        XCTAssertEqual(card.percent, 85)
        XCTAssertEqual(card.percentText, "85%")
        XCTAssertEqual(card.ringFill, 0.85, accuracy: 1e-12)
        XCTAssertEqual(card.text, "17 of 20 logged offers matched the verdict. Locked in.")
    }

    func testEightyFourPercentHasRoomToTighten() {
        let card = self.card(followed: 21, of: 25)

        XCTAssertEqual(card.percent, 84)
        XCTAssertEqual(card.text, "21 of 25 logged offers matched the verdict. Room to tighten up.")
    }

    /// `Math.round` on the web: 12.5 becomes 13, and 66.66… becomes 67.
    func testPercentRoundsLikeTheWeb() {
        XCTAssertEqual(self.card(followed: 1, of: 8).percent, 13)
        XCTAssertEqual(self.card(followed: 2, of: 3).percent, 67)
        XCTAssertEqual(self.card(followed: 1, of: 3).percent, 33)
        XCTAssertEqual(self.card(followed: 1, of: 8).ringFill, 0.13, accuracy: 1e-12)
    }
}
