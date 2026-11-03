import XCTest
@testable import HustlerCore

/// Hand-checked expectations. Labels, week keys, counts and the save splice were
/// confirmed by running the web app's own `scKey()`, `scLabel()` and `scSave()`
/// loop from `index.html` in the oracle sandbox before these were written.
final class LogScopeTests: XCTestCase {

    private let oct27First = Fixtures.analyticsMurrieta    // 2026-10-27 14:46
    private let oct25Archive = Fixtures.analyticsArchive   // 2026-10-25 18:00, archive
    private let oct27Second = Fixtures.analyticsDeclined   // 2026-10-27 15:10
    private let oct20NoTime = Fixtures.analyticsNoTime     // 2026-10-20, no time
    private let dec31 = "| 2026-12-31 09:00 | 5.00 | 2.0 | 1 | 2.50 | 1.00 | 5.00 | SKIP | 89.00 | Decline | 0 |"
    private let nov01 = "| 2026-11-01 10:00 | 6.00 | 3.0 | 1 | 2.00 | 2.00 | 6.00 | SKIP | 89.00 | Decline | 0 |"
    private let oct01Edit = "| 2026-10-01 09:00 | 3.00 | 1.0 | 1 | 3.00 | 1.00 | 6.00 | SKIP | 89.00 | Decline | 0 |"

    /// Two rows share a day and a week and are not adjacent, so the save has to
    /// move the second one's position.
    private var whole: String {
        file([oct27First, oct25Archive, oct27Second, oct20NoTime, dec31, nov01])
    }

    private func file(_ rows: [String]) -> String {
        Fixtures.headerLiteral + "\n" + rows.joined(separator: "\n")
    }

    func testDayScopesListNewestFirst() {
        let scopes = LogScope.scopes(in: whole, mode: .day)
        XCTAssertEqual(scopes.map(\.key), ["2026-12-31", "2026-11-01", "2026-10-27", "2026-10-25", "2026-10-20"])
        XCTAssertEqual(scopes.map(\.count), [1, 1, 2, 1, 1])
        XCTAssertEqual(scopes.map(\.label), [
            "Thu Dec 31, 2026 (1)", "Sun Nov 1, 2026 (1)", "Tue Oct 27, 2026 (2)",
            "Sun Oct 25, 2026 (1)", "Tue Oct 20, 2026 (1)"
        ])
    }

    func testWeekScopesAnchorOnMonday() {
        let scopes = LogScope.scopes(in: whole, mode: .week)
        XCTAssertEqual(scopes.map(\.key), ["2026-12-28", "2026-10-26", "2026-10-19"])
        XCTAssertEqual(scopes.map(\.count), [1, 3, 2])
        XCTAssertEqual(scopes.map(\.label), [
            "Week of Dec 28 to Jan 3 (1)", "Week of Oct 26 to Nov 1 (3)", "Week of Oct 19 to Oct 25 (2)"
        ])
    }

    func testLabelsMatchTheWebApp() {
        XCTAssertEqual(LogScope.label(forKey: "2026-10-27", count: 2, mode: .day), "Tue Oct 27, 2026 (2)")
        XCTAssertEqual(LogScope.label(forKey: "2026-02-23", count: 1, mode: .day), "Mon Feb 23, 2026 (1)")
        XCTAssertEqual(LogScope.label(forKey: "2026-10-26", count: 3, mode: .week), "Week of Oct 26 to Nov 1 (3)")
        XCTAssertEqual(LogScope.label(forKey: "2026-02-23", count: 1, mode: .week), "Week of Feb 23 to Mar 1 (1)")
        XCTAssertEqual(LogScope.label(forKey: "2026-12-28", count: 1, mode: .week), "Week of Dec 28 to Jan 3 (1)")
        XCTAssertEqual(LogScope.label(forKey: "not-a-day", count: 1, mode: .day), "")
    }

    func testSelectionPrefersPreviousThenTodayThenNewest() {
        let days = LogScope.scopes(in: whole, mode: .day)
        XCTAssertEqual(
            LogScope.selection(in: days, mode: .day, previous: "2026-10-25", today: "2026-10-20"),
            "2026-10-25"
        )
        XCTAssertEqual(
            LogScope.selection(in: days, mode: .day, previous: "2026-01-01", today: "2026-10-20"),
            "2026-10-20"
        )
        XCTAssertEqual(
            LogScope.selection(in: days, mode: .day, previous: nil, today: "2026-11-02"),
            "2026-12-31"
        )
        let weeks = LogScope.scopes(in: whole, mode: .week)
        XCTAssertEqual(
            LogScope.selection(in: weeks, mode: .week, previous: nil, today: "2026-10-31"),
            "2026-10-26"
        )
    }

    func testScopeTextIsOnlyThatScopesRowsInFileOrder() {
        XCTAssertEqual(
            LogScope.text(in: whole, mode: .day, key: "2026-10-27"),
            oct27First + "\n" + oct27Second
        )
        XCTAssertEqual(
            LogScope.text(in: whole, mode: .week, key: "2026-10-26"),
            [oct27First, oct27Second, nov01].joined(separator: "\n")
        )
        XCTAssertEqual(LogScope.text(in: whole, mode: .day, key: "2026-01-01"), "")
    }

    func testReplacingADayKeepsEveryOtherRow() {
        let edited = "| 2026-10-27 09:00 | 12.00 | 4.0 | 2 | 3.00 | 9.00 | 27.00 | TAKE IT | 89.00 | Accept | 5 |"
        XCTAssertEqual(
            LogScope.replacing(text: whole, mode: .day, key: "2026-10-27", with: edited),
            file([edited, oct25Archive, oct20NoTime, dec31, nov01])
        )
    }

    /// The scope's rows are collapsed into its first position, so the edited
    /// week's three rows become one and Nov 1's row is no longer there.
    func testReplacingAWeekCollapsesItsRowsIntoTheFirstPosition() {
        let edited = "| 2026-10-28 09:00 | 4.00 | 1.0 | 1 | 4.00 | 3.00 | 18.00 | TAKE IT | 89.00 | Accept | 0 |"
        XCTAssertEqual(
            LogScope.replacing(text: whole, mode: .week, key: "2026-10-26", with: edited),
            file([edited, oct25Archive, oct20NoTime, dec31])
        )
    }

    func testBlankAndUnreadableEditedLinesAreDropped() {
        let edited = "\n  \n" + Fixtures.headerLiteral
            + "\n| not-a-date | 5 | 3 | 1 | 1 | 1 | 1 | SKIP | 89 | Accept | 0 |\n\n"
            + oct01Edit + "\n\n"
        XCTAssertEqual(
            LogScope.replacing(text: whole, mode: .day, key: "2026-10-20", with: edited),
            file([oct27First, oct25Archive, oct27Second, oct01Edit, dec31, nov01])
        )
    }

    func testKeyWithNoRowsAppendsAtTheEnd() {
        XCTAssertEqual(
            LogScope.replacing(text: Fixtures.twoRows, mode: .day, key: "2026-10-01", with: oct01Edit),
            file([Fixtures.firstShortcutRow, Fixtures.secondShortcutRow, oct01Edit])
        )
    }

    func testHeaderOnlyFileHasNoScopesOrSelection() {
        XCTAssertEqual(LogScope.rows(in: Fixtures.headerLiteral), [])
        XCTAssertEqual(LogScope.scopes(in: Fixtures.headerLiteral, mode: .day), [])
        XCTAssertEqual(LogScope.scopes(in: Fixtures.headerLiteral, mode: .week), [])
        XCTAssertNil(LogScope.selection(in: [], mode: .day, previous: nil, today: "2026-10-27"))
        XCTAssertEqual(LogScope.text(in: Fixtures.headerLiteral, mode: .day, key: "2026-10-27"), "")
        // logSplit() normalises first, so a file without a header still lists rows.
        XCTAssertEqual(LogScope.rows(in: Fixtures.twoRows).count, 2)
    }

    /// Blank and dateless rows belong to no scope and do not survive the file's
    /// normalisation, so they can neither be selected nor counted.
    func testBlankAndDatelessRowsBelongToNoScope() {
        let messy = Fixtures.headerLiteral + "\n\n"
            + "| not-a-date | 5 | 3 | 1 | 1 | 1 | 1 | SKIP | 89 | Accept | 0 |\n"
            + oct27First + "\n\n"
        XCTAssertEqual(LogScope.rows(in: messy), [oct27First])
        XCTAssertEqual(LogScope.scopes(in: messy, mode: .day).map(\.key), ["2026-10-27"])
    }
}
