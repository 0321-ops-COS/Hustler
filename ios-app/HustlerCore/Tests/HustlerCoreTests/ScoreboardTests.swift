import XCTest
@testable import HustlerCore

/// Tile values and period rows were captured by rendering the web app's own
/// Scoreboard with a fixed clock and parsing the HTML it produced
/// (`tools/parity/expectations.json`, sections `scoreboard` and `periods`).
final class ScoreboardTests: XCTestCase {

    private struct StatCase {
        let fixture: String
        let label: String
        let value: String
    }

    private struct PeriodTotalsCase {
        let fixture: String
        let period: String
        let key: String
        let gross: String
        let net: String
        let taken: Int
        let netPerHour: String
    }

    private var settings: VerdictSettings { VerdictSettings() }

    private func rows(_ text: String) -> [LogRow] {
        MasterLog.orderedForAnalysis(MasterLogParser.parse(text))
    }

    private func tiles(_ rows: [LogRow]) -> [String: String] {
        let totals = Scoreboard.totals(rows, settings: settings)
        return [
            "Acceptance": totals.acceptancePercent.map { "\($0)%" } ?? "--",
            "Gross": Money.format(totals.gross, decimals: 0),
            "Net after car": Money.format(totals.net, decimals: 0),
            "Net $/hr": totals.netPerHour.map { Money.format($0) } ?? "--",
            "Net $/mile": totals.netPerMile.map { Money.format($0) } ?? "--",
            "Offers": "\(totals.offers)",
            "Miles driven": JsNumber.toFixed(totals.miles, places: 0),
            "Hours": JsNumber.toFixed(totals.hours, places: 1)
        ]
    }

    private let statCases: [StatCase] = [
        StatCase(fixture: "mixed", label: "Acceptance", value: "75%"),
        StatCase(fixture: "mixed", label: "Gross", value: "$65"),
        StatCase(fixture: "mixed", label: "Net after car", value: "$49"),
        StatCase(fixture: "mixed", label: "Net $/hr", value: "$21.81"),
        StatCase(fixture: "mixed", label: "Net $/mile", value: "$1.74"),
        StatCase(fixture: "mixed", label: "Offers", value: "6"),
        StatCase(fixture: "mixed", label: "Miles driven", value: "28"),
        StatCase(fixture: "mixed", label: "Hours", value: "2.2"),

        StatCase(fixture: "archive_only", label: "Acceptance", value: "--"),
        StatCase(fixture: "archive_only", label: "Gross", value: "$16"),
        StatCase(fixture: "archive_only", label: "Net after car", value: "$10"),
        StatCase(fixture: "archive_only", label: "Net $/hr", value: "$10.75"),
        StatCase(fixture: "archive_only", label: "Net $/mile", value: "$0.90"),
        StatCase(fixture: "archive_only", label: "Offers", value: "2"),
        StatCase(fixture: "archive_only", label: "Miles driven", value: "11"),
        StatCase(fixture: "archive_only", label: "Hours", value: "0.9")
    ]

    private let periodCases: [PeriodTotalsCase] = [
        PeriodTotalsCase(fixture: "mixed", period: "day", key: "2026-10-27", gross: "$26.50", net: "$22.42", taken: 1, netPerHour: "$30.03"),
        PeriodTotalsCase(fixture: "mixed", period: "day", key: "2026-10-26", gross: "$12.00", net: "$9.06", taken: 1, netPerHour: "$27.18"),
        PeriodTotalsCase(fixture: "mixed", period: "day", key: "2026-10-25", gross: "$7.00", net: "$4.76", taken: 1, netPerHour: "$9.51"),
        PeriodTotalsCase(fixture: "mixed", period: "day", key: "2026-10-24", gross: "$9.00", net: "$5.10", taken: 1, netPerHour: "$12.24"),
        PeriodTotalsCase(fixture: "mixed", period: "day", key: "2026-09-30", gross: "$10.00", net: "$7.66", taken: 1, netPerHour: "$30.64"),

        PeriodTotalsCase(fixture: "mixed", period: "week", key: "2026-10-26", gross: "$38.50", net: "$31.48", taken: 2, netPerHour: "$29.15"),
        PeriodTotalsCase(fixture: "mixed", period: "week", key: "2026-10-19", gross: "$16.00", net: "$9.86", taken: 2, netPerHour: "$10.75"),
        PeriodTotalsCase(fixture: "mixed", period: "week", key: "2026-09-28", gross: "$10.00", net: "$7.66", taken: 1, netPerHour: "$30.64"),

        PeriodTotalsCase(fixture: "mixed", period: "month", key: "2026-10", gross: "$54.50", net: "$41.34", taken: 4, netPerHour: "$20.70"),
        PeriodTotalsCase(fixture: "mixed", period: "month", key: "2026-09", gross: "$10.00", net: "$7.66", taken: 1, netPerHour: "$30.64"),

        PeriodTotalsCase(fixture: "mixed", period: "year", key: "2026", gross: "$64.50", net: "$49.00", taken: 5, netPerHour: "$21.81"),

        PeriodTotalsCase(fixture: "archive_only", period: "day", key: "2026-10-25", gross: "$7.00", net: "$4.76", taken: 1, netPerHour: "$9.51"),
        PeriodTotalsCase(fixture: "archive_only", period: "day", key: "2026-10-24", gross: "$9.00", net: "$5.10", taken: 1, netPerHour: "$12.24"),
        PeriodTotalsCase(fixture: "archive_only", period: "week", key: "2026-10-19", gross: "$16.00", net: "$9.86", taken: 2, netPerHour: "$10.75"),
        PeriodTotalsCase(fixture: "archive_only", period: "month", key: "2026-10", gross: "$16.00", net: "$9.86", taken: 2, netPerHour: "$10.75"),
        PeriodTotalsCase(fixture: "archive_only", period: "year", key: "2026", gross: "$16.00", net: "$9.86", taken: 2, netPerHour: "$10.75")
    ]

    func testScoreboardTilesMatchWebApp() {
        let fixtures = ["mixed": rows(Fixtures.scoreboardMixed), "archive_only": rows(Fixtures.scoreboardArchiveOnly)]
        for testCase in statCases {
            guard let input = fixtures[testCase.fixture] else {
                XCTFail("unknown fixture \(testCase.fixture)")
                continue
            }
            XCTAssertEqual(tiles(input)[testCase.label], testCase.value, "\(testCase.fixture)/\(testCase.label)")
        }
    }

    func testPeriodTotalsMatchWebApp() {
        let fixtures = ["mixed": rows(Fixtures.scoreboardMixed), "archive_only": rows(Fixtures.scoreboardArchiveOnly)]
        for testCase in periodCases {
            guard let input = fixtures[testCase.fixture],
                  let period = PeriodGrouping.Period(rawValue: testCase.period) else {
                XCTFail("unknown case \(testCase.fixture)/\(testCase.period)")
                continue
            }
            guard let bucket = Scoreboard.periodTotals(input, period: period, settings: settings)[testCase.key] else {
                XCTFail("no bucket \(testCase.fixture)/\(testCase.period)/\(testCase.key)")
                continue
            }
            let label = "\(testCase.fixture)/\(testCase.period)/\(testCase.key)"
            XCTAssertEqual(Money.format(bucket.gross), testCase.gross, label)
            XCTAssertEqual(Money.format(bucket.net), testCase.net, label)
            XCTAssertEqual(bucket.taken, testCase.taken, label)
            XCTAssertEqual(bucket.netPerHour.map { Money.format($0) } ?? "--", testCase.netPerHour, label)
        }
    }

    /// Only accepted offers carry earnings, but acceptance itself is measured
    /// over logged offers: archive rows have no verdict, so including them would
    /// quietly inflate the rate.
    func testPopulationsAreNotInterchangeable() {
        let mixed = rows(Fixtures.scoreboardMixed)
        let totals = Scoreboard.totals(mixed, settings: settings)
        XCTAssertEqual(totals.offers, 6, "every row counts as an offer")
        XCTAssertEqual(totals.loggedOffers, 4, "archive rows are excluded from the rate")
        XCTAssertEqual(totals.loggedAccepted, 3)
        XCTAssertEqual(totals.acceptancePercent, 75)
        XCTAssertEqual(totals.followedPercent, 100)
    }

    /// A declined offer must not contribute pay, miles or time.
    func testDeclinedRowsContributeNothingToEarnings() {
        let accepted = rows(Fixtures.headerLiteral + "\n" + Fixtures.scoreboardFirstRow)
        let both = rows(Fixtures.scoreboardMixed)
        let a = Scoreboard.totals(accepted, settings: settings)
        let b = Scoreboard.totals(both, settings: settings)
        XCTAssertLessThan(a.gross, b.gross)
        XCTAssertEqual(a.offers, 1)
        XCTAssertGreaterThan(b.offers, a.offers)
        XCTAssertEqual(Scoreboard.totals(rows(Fixtures.headerLiteral + "\n" + Fixtures.scoreboardSecondRow), settings: settings).gross, 0)
    }

    /// Archive rows written by the importer have no Net cell, so their net comes
    /// from payout minus car cost; rows that carry one keep their own figure.
    func testNetFallsBackToCarCostWhenCellIsBlank() {
        let row = LogRow(date: "2026-10-25", payout: "7.00", miles: "5.0", net: "", minutes: "30", source: "archive")
        XCTAssertEqual(Scoreboard.net(for: row, settings: settings), 7.00 - 5.0 * (5.75 / 17.5 + 0.12), accuracy: 1e-12)

        let explicit = LogRow(date: "2026-10-24", payout: "9.00", miles: "6.0", net: "5.10", minutes: "25", source: "archive")
        XCTAssertEqual(Scoreboard.net(for: explicit, settings: settings), 5.10, accuracy: 1e-12)

        let zoned = LogRow(date: "2026-10-25", zone: "Temecula", payout: "7.00", miles: "5.0", net: "", minutes: "30", source: "archive")
        let zonedSettings = VerdictSettings(zoneGas: ["Temecula": 6.5])
        XCTAssertEqual(Scoreboard.net(for: zoned, settings: zonedSettings), 7.00 - 5.0 * (6.5 / 17.5 + 0.12), accuracy: 1e-12)
    }
}
