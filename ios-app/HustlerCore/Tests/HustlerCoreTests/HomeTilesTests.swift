import XCTest
@testable import HustlerCore

/// The day/week/month/year numbers here are the same fixtures and the same
/// displayed values `ScoreboardTests` pins from the web app, reached through
/// `HomeTiles` instead of directly.
final class HomeTilesTests: XCTestCase {

    private var settings: VerdictSettings { VerdictSettings() }

    private lazy var mixed = MasterLog.orderedForAnalysis(MasterLogParser.parse(Fixtures.scoreboardMixed))

    private func totals(_ period: PeriodGrouping.Period, _ key: String) -> ScoreboardTotals {
        HomeTiles.totals(mixed, period: period, key: key, settings: settings)
    }

    /// The `mixed` fixture spans 2026-09-30 to 2026-10-27, so 2026-10-26 is the
    /// Monday of the week holding the three October shortcut rows.
    func testDayKeyKeepsOnlyThatDay() {
        let day = totals(.day, "2026-10-27")
        XCTAssertEqual(Money.format(day.gross), "$26.50")
        XCTAssertEqual(Money.format(day.net), "$22.42")
        XCTAssertEqual(day.miles, 9.1, accuracy: 1e-9)
        XCTAssertEqual(day.offers, 2, "the declined row is still an offer")
        XCTAssertEqual(day.acceptancePercent, 50, "one of two logged offers accepted")
    }

    func testWeekKeyStartsOnMonday() {
        XCTAssertEqual(PeriodGrouping.key(for: "2026-10-27", period: .week), "2026-10-26")
        let week = totals(.week, "2026-10-26")
        XCTAssertEqual(Money.format(week.gross), "$38.50")
        XCTAssertEqual(Money.format(week.net), "$31.48")
        XCTAssertEqual(week.offers, 3)
        XCTAssertEqual(week.netPerHour.map { Money.format($0) }, "$29.15")
    }

    func testMonthKeySpansTheWholeMonth() {
        let month = totals(.month, "2026-10")
        XCTAssertEqual(Money.format(month.gross), "$54.50")
        XCTAssertEqual(Money.format(month.net), "$41.34")
        XCTAssertEqual(month.offers, 5, "two archive rows join the three shortcut rows")
    }

    func testYearKeyCoversEveryMonth() {
        let year = totals(.year, "2026")
        XCTAssertEqual(Money.format(year.gross), "$64.50")
        XCTAssertEqual(Money.format(year.net), "$49.00")
        XCTAssertEqual(year.offers, 6)
        XCTAssertEqual(year.acceptancePercent, 75)
    }

    /// Every tile is zero, and the two derived rates stay `nil` so the UI can
    /// show `--` rather than `$0.00/hr`.
    func testPeriodWithNoRowsReturnsZeroTotals() {
        let empty = totals(.day, "2026-10-01")
        XCTAssertEqual(empty.gross, 0)
        XCTAssertEqual(empty.net, 0)
        XCTAssertEqual(empty.miles, 0)
        XCTAssertEqual(empty.minutes, 0)
        XCTAssertEqual(empty.hours, 0)
        XCTAssertEqual(empty.offers, 0)
        XCTAssertEqual(empty.loggedOffers, 0)
        XCTAssertNil(empty.acceptancePercent)
        XCTAssertNil(empty.netPerHour)
        XCTAssertNil(empty.netPerMile)
        XCTAssertEqual(empty, Scoreboard.totals([], settings: settings))
    }

    func testRowsFromOtherPeriodsAreExcluded() {
        let month = totals(.month, "2026-10")
        let year = totals(.year, "2026")
        XCTAssertEqual(year.offers - month.offers, 1, "only the 2026-09-30 row joins the year")
        XCTAssertEqual(Money.format(year.gross - month.gross), "$10.00")
        XCTAssertEqual(totals(.month, "2026-09").offers, 1)
        XCTAssertEqual(totals(.week, "2026-09-28").offers, 1)
        XCTAssertEqual(totals(.day, "2026-10-25").offers, 1)
        XCTAssertEqual(totals(.day, "2026-10-24").offers, 1)
    }

    /// Money and hours come from accepted rows only, and the period split adds
    /// up: day totals inside one week total that week.
    func testMoneyAndHoursAggregateAcceptedRowsOnly() {
        let monday = totals(.day, "2026-10-26")
        let tuesday = totals(.day, "2026-10-27")
        let week = totals(.week, "2026-10-26")

        XCTAssertEqual(week.gross, monday.gross + tuesday.gross, accuracy: 1e-9)
        XCTAssertEqual(week.net, monday.net + tuesday.net, accuracy: 1e-9)
        XCTAssertEqual(week.minutes, monday.minutes + tuesday.minutes, accuracy: 1e-9)
        XCTAssertEqual(week.hours, week.minutes / 60, accuracy: 1e-12)
        XCTAssertEqual(week.hours, 1.08, accuracy: 0.005)
        XCTAssertEqual(tuesday.minutes, 44.8, accuracy: 0.005, "derived from Net and Hourly")

        XCTAssertEqual(monday.miles, 4.0, accuracy: 1e-9)
        XCTAssertEqual(tuesday.miles, 9.1, accuracy: 1e-9, "the declined 6.2 miles do not count")
        XCTAssertEqual(week.miles, monday.miles + tuesday.miles, accuracy: 1e-9)
    }

    /// The filter only ever reorders the same rows, so the tiles agree with the
    /// per-period table the Scoreboard already renders.
    func testTilesAgreeWithScoreboardPeriodTotals() {
        let buckets = Scoreboard.periodTotals(mixed, period: .week, settings: settings)
        for (key, bucket) in buckets {
            let tiles = totals(.week, key)
            XCTAssertEqual(tiles.gross, bucket.gross, accuracy: 1e-9, key)
            XCTAssertEqual(tiles.net, bucket.net, accuracy: 1e-9, key)
            XCTAssertEqual(tiles.minutes, bucket.minutes, accuracy: 1e-9, key)
            XCTAssertEqual(bucket.taken, mixed.filter {
                $0.choiceTook && PeriodGrouping.key(for: $0.date, period: .week) == key
            }.count, key)
        }
    }
}
