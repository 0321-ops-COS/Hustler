import XCTest
@testable import HustlerCore

/// Every expectation was produced by calling the web app's own `keyOf()` in the
/// parity oracle, so a failure means the port diverged rather than that a
/// hand-written guess was wrong.
final class PeriodGroupingTests: XCTestCase {

    private struct PeriodCase {
        let date: String
        let day: String
        let week: String
        let month: String
        let year: String
    }

    private let cases: [PeriodCase] = [
        PeriodCase(date: "2026-10-27", day: "2026-10-27", week: "2026-10-26", month: "2026-10", year: "2026"),
        PeriodCase(date: "2026-10-25", day: "2026-10-25", week: "2026-10-19", month: "2026-10", year: "2026"),
        PeriodCase(date: "2026-10-26", day: "2026-10-26", week: "2026-10-26", month: "2026-10", year: "2026"),
        PeriodCase(date: "2026-03-01", day: "2026-03-01", week: "2026-02-23", month: "2026-03", year: "2026"),
        PeriodCase(date: "2026-01-01", day: "2026-01-01", week: "2025-12-29", month: "2026-01", year: "2026"),
        PeriodCase(date: "2026-12-31", day: "2026-12-31", week: "2026-12-28", month: "2026-12", year: "2026"),
        PeriodCase(date: "2026-11-01", day: "2026-11-01", week: "2026-10-26", month: "2026-11", year: "2026"),
        PeriodCase(date: "2026-02-28", day: "2026-02-28", week: "2026-02-23", month: "2026-02", year: "2026"),
        PeriodCase(date: "2026-10-31", day: "2026-10-31", week: "2026-10-26", month: "2026-10", year: "2026"),
        PeriodCase(date: "2026-10-01", day: "2026-10-01", week: "2026-09-28", month: "2026-10", year: "2026")
    ]

    func testPeriodKeysMatchWebApp() {
        for testCase in cases {
            XCTAssertEqual(PeriodGrouping.key(for: testCase.date, period: .day), testCase.day, testCase.date)
            XCTAssertEqual(PeriodGrouping.key(for: testCase.date, period: .week), testCase.week, testCase.date)
            XCTAssertEqual(PeriodGrouping.key(for: testCase.date, period: .month), testCase.month, testCase.date)
            XCTAssertEqual(PeriodGrouping.key(for: testCase.date, period: .year), testCase.year, testCase.date)
        }
    }

    /// Weeks start on Monday, so a Sunday belongs to the week that began six
    /// days earlier — not to the following Monday.
    func testWeeksStartOnMonday() {
        XCTAssertEqual(PeriodGrouping.monday(ofISO: "2026-10-26"), "2026-10-26")
        XCTAssertEqual(PeriodGrouping.monday(ofISO: "2026-10-29"), "2026-10-26")
        XCTAssertEqual(PeriodGrouping.monday(ofISO: "2026-11-01"), "2026-10-26")
        XCTAssertEqual(PeriodGrouping.monday(ofISO: "2026-11-02"), "2026-11-02")
    }

    /// A y-m-d input carries its own weekday, so the result cannot depend on the
    /// device timezone. This guards the reason `keyOf` anchors at noon.
    func testCrossYearAndLeapDayBoundaries() {
        XCTAssertEqual(PeriodGrouping.key(for: "2024-02-29", period: .week), "2024-02-26")
        XCTAssertEqual(PeriodGrouping.key(for: "2025-01-01", period: .week), "2024-12-30")
        XCTAssertEqual(PeriodGrouping.key(for: "2026-01-04", period: .week), "2025-12-29")
    }

    /// The web app reaches its own guard first (`/^\d{4}-\d\d-\d\d/`), so this
    /// port returns `""` rather than reproducing its `"NaN-NaN-NaN"`.
    func testInvalidDatesReturnEmptyWeek() {
        XCTAssertEqual(PeriodGrouping.key(for: "", period: .week), "")
        XCTAssertEqual(PeriodGrouping.key(for: "not-a-date", period: .week), "")
        XCTAssertEqual(PeriodGrouping.key(for: "2026-1-5", period: .week), "")
    }
}
