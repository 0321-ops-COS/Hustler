import XCTest
@testable import HustlerCore

final class HomePeriodBoardTests: XCTestCase {
    private var settings: VerdictSettings { VerdictSettings() }
    private func rows(_ dates: [String]) -> [LogRow] {
        dates.map { LogRow(date: $0, payout: "10.00", miles: "4.0", net: "7.00",
                           verdict: "TAKE IT", choice: "Accept", minutes: "30") }
    }

    /// Local noon on the given date, so `dateText()` is that date in any zone.
    private func clock(_ text: String) -> HomeClock {
        let parts = text.split(separator: "-").compactMap { Int($0) }
        var components = DateComponents()
        components.year = parts[0]; components.month = parts[1]
        components.day = parts[2]; components.hour = 12
        return .fixed(Calendar.current.date(from: components)!)
    }
    func testSlicingBoundaries() {
        let days = (2...11).map { String(format: "2026-01-%02d", $0) }
        let ten = HomePeriodBoard(rows: rows(days), period: .day, clock: clock("2026-01-11"), settings: settings)
        XCTAssertEqual(ten.buckets.map(\.key), Array(days.reversed()))
        let eleven = HomePeriodBoard(rows: rows(["2026-01-01"] + days), period: .day,
                                     clock: clock("2026-01-11"), settings: settings)
        XCTAssertEqual(eleven.buckets.map(\.key), Array(days.reversed()), "an eleventh day drops off")

        let weeks = ["2026-01-12", "2026-01-19", "2026-01-26", "2026-02-02",
                     "2026-02-09", "2026-02-16", "2026-02-23", "2026-03-02"]
        let eight = HomePeriodBoard(rows: rows(weeks), period: .week, clock: clock("2026-03-02"), settings: settings)
        XCTAssertEqual(eight.buckets.map(\.key), Array(weeks.reversed()))
        let nine = HomePeriodBoard(rows: rows(["2026-01-05"] + weeks), period: .week,
                                   clock: clock("2026-03-02"), settings: settings)
        XCTAssertEqual(nine.buckets.map(\.key), Array(weeks.reversed()), "a ninth week drops off")

        let months = (1...12).map { String(format: "2026-%02d-15", $0) }
        let monthKeys = Array(months.map { String($0.prefix(7)) }.reversed())
        let twelve = HomePeriodBoard(rows: rows(months), period: .month, clock: clock("2026-12-15"), settings: settings)
        XCTAssertEqual(twelve.buckets.map(\.key), monthKeys)
        let thirteen = HomePeriodBoard(rows: rows(["2025-12-15"] + months), period: .month,
                                       clock: clock("2026-12-15"), settings: settings)
        XCTAssertEqual(thirteen.buckets.map(\.key), monthKeys, "a thirteenth month drops off")
        let years = (2015...2027).map { "\($0)-06-15" }
        let year = HomePeriodBoard(rows: rows(years), period: .year, clock: clock("2027-06-15"), settings: settings)
        XCTAssertEqual(year.buckets.map(\.key), (2016...2027).reversed().map(String.init), "Year shares Month's 12 cap")
    }

    func testCurrentBucketIsAlwaysIncluded() {
        let board = HomePeriodBoard(rows: rows(["2026-10-30", "2026-10-31"]), period: .day,
                                    clock: clock("2026-11-02"), settings: settings)
        XCTAssertEqual(board.buckets.first?.key, "2026-11-02")
        XCTAssertEqual(board.buckets.first?.taken, 0)
        XCTAssertEqual(board.selectedKey, "2026-11-02", "the default selection")
        XCTAssertEqual(board.tiles.map(\.value), ["$0", "$0", "--", "--", "0", "0", "0.0", "--", "--"])
        let empty = HomePeriodBoard(rows: [], period: .month, clock: clock("2026-11-02"), settings: settings)
        XCTAssertEqual(empty.buckets.map(\.key), ["2026-11"])
    }

    func testSelectionSwitchesTheTiles() {
        let inputs = [("2026-10-25", "10.00"), ("2026-10-26", "20.00"), ("2026-10-27", "30.00")].map {
            LogRow(date: $0.0, payout: $0.1, miles: "4.0", net: $0.1,
                   verdict: "TAKE IT", choice: "Accept", minutes: "30")
        }
        var board = HomePeriodBoard(rows: inputs, period: .day, clock: clock("2026-10-27"), settings: settings)
        XCTAssertEqual(board.tiles.first { $0.kind == .net }?.value, "$30")
        board.select("2026-10-26")
        XCTAssertEqual(board.selectedKey, "2026-10-26")
        XCTAssertEqual(board.tiles.first { $0.kind == .net }?.value, "$20")
        board.select("2026-10-01")
        XCTAssertEqual(board.selectedKey, "2026-10-26", "a key outside the table keeps the selection")
    }
    func testTilesEqualScoreboardTotals() {
        let mixed = MasterLog.orderedForAnalysis(MasterLogParser.parse(Fixtures.scoreboardMixed))
        for key in ["2026-10-27", "2026-10-26", "2026-10-25", "2026-10-24"] {
            let sameRows = mixed.filter { $0.date.hasPrefix(key) }
            XCTAssertEqual(
                HomeTiles.tiles(HomeTiles.totals(mixed, period: .day, key: key, settings: settings)),
                HomeTiles.tiles(Scoreboard.totals(sameRows, settings: settings)),
                key
            )
        }
        let board = HomePeriodBoard(rows: mixed, period: .day, clock: clock("2026-10-27"), settings: settings)
        XCTAssertEqual(board.tiles.map(\.value), ["$27", "$22", "$30.03", "$2.46", "2", "9", "0.7", "50%", "100%"])
    }
}
