import XCTest
@testable import HustlerCore

/// Reconciliation values captured by running the web app's own `adjust()` over
/// the same rows and statement totals in the parity oracle
/// (`expectations.json`, section `statements.allocations`).
///
/// These tests are a compatibility contract. They pin defect **B1** as it exists
/// today: a statement month's total is allocated to archive rows only, so logged
/// shortcut pay in the same month is added on top rather than subtracted.
final class StatementReconcilerTests: XCTestCase {

    private struct StatementCase {
        let id: String
        let monthly: [String: StatementMonth]
        let rows: [String]
        let payouts: [String]
        let miles: [String]
    }

    private let cases: [StatementCase] = [
        StatementCase(
            id: "three_rows",
            monthly: ["2026-09": StatementMonth(total: 100)],
            rows: [
                Fixtures.archiveLine("2026-09-05 18:00", minutes: "10"),
                Fixtures.archiveLine("2026-09-06 12:00", minutes: "20"),
                Fixtures.archiveLine("2026-09-07 09:00", minutes: "30")
            ],
            payouts: ["16.67", "33.33", "50.00"],
            miles: ["5.0", "5.0", "5.0"]
        ),
        StatementCase(
            id: "miles_split",
            monthly: ["2026-10": StatementMonth(total: 250.50, miles: 40)],
            rows: [
                Fixtures.archiveLine("2026-10-02 10:00", minutes: "15"),
                Fixtures.archiveLine("2026-10-03 11:00", minutes: "45")
            ],
            payouts: ["62.63", "187.87"],
            miles: ["10.0", "30.0"]
        ),
        StatementCase(
            id: "no_statement",
            monthly: [:],
            rows: [
                Fixtures.archiveLine("2026-09-05 18:00", minutes: "10"),
                Fixtures.archiveLine("2026-09-06 12:00", minutes: "20")
            ],
            payouts: ["7.00", "7.00"],
            miles: ["5.0", "5.0"]
        ),
        StatementCase(
            id: "b1_shortcut_ignored",
            monthly: ["2026-09": StatementMonth(total: 1000)],
            rows: [
                Fixtures.archiveLine("2026-09-05 18:00", minutes: "10"),
                Fixtures.archiveLine("2026-09-06 12:00", minutes: "20"),
                Fixtures.shortcutLine("2026-09-06", payout: "250.00")
            ],
            payouts: ["333.33", "666.67", "250.00"],
            miles: ["5.0", "5.0", "5.0"]
        ),
        StatementCase(
            id: "tie_remainder",
            monthly: ["2026-09": StatementMonth(total: 100)],
            rows: [
                Fixtures.archiveLine("2026-09-05 18:00", minutes: "20"),
                Fixtures.archiveLine("2026-09-06 12:00", minutes: "20"),
                Fixtures.archiveLine("2026-09-07 09:00", minutes: "20")
            ],
            payouts: ["33.34", "33.33", "33.33"],
            miles: ["5.0", "5.0", "5.0"]
        ),
        StatementCase(
            id: "two_months_one_statement",
            monthly: ["2026-09": StatementMonth(total: 100)],
            rows: [
                Fixtures.archiveLine("2026-09-05 18:00", minutes: "10"),
                Fixtures.archiveLine("2026-10-03 11:00", minutes: "30")
            ],
            payouts: ["100.00", "7.00"],
            miles: ["5.0", "5.0"]
        ),
        StatementCase(
            id: "miles_zero",
            monthly: ["2026-09": StatementMonth(total: 50.01)],
            rows: [
                Fixtures.archiveLine("2026-09-05 18:00", minutes: "10"),
                Fixtures.archiveLine("2026-09-06 12:00", minutes: "30")
            ],
            payouts: ["12.50", "37.51"],
            miles: ["5.0", "5.0"]
        ),
        StatementCase(
            id: "shortcut_only_month",
            monthly: ["2026-09": StatementMonth(total: 100)],
            rows: [
                Fixtures.shortcutLine("2026-09-06", payout: "12.00")
            ],
            payouts: ["12.00"],
            miles: ["5.0"]
        ),
        StatementCase(
            id: "blank_minutes_derived",
            monthly: ["2026-09": StatementMonth(total: 100, miles: 20)],
            rows: [
                Fixtures.archiveLine("2026-09-05 18:00", minutes: ""),
                Fixtures.archiveLine("2026-09-06 12:00", minutes: "30")
            ],
            payouts: ["46.90", "53.10"],
            miles: ["9.4", "10.6"]
        )
    ]

    func testAllocationMatchesObservedWebBehaviour() {
        for c in cases {
            let before = MasterLogParser.parse(Fixtures.statementLog(c.rows))
            XCTAssertEqual(before.count, c.payouts.count, c.id)
            let after = StatementReconciler.allocate(before, monthly: c.monthly)
            XCTAssertEqual(after.map(\.payout), c.payouts, c.id)
            XCTAssertEqual(after.map(\.miles), c.miles, c.id)
        }
    }

    func testAllocatedCentsAddUpToTheStatementTotal() {
        let c = cases.first { $0.id == "three_rows" }!
        let before = MasterLogParser.parse(Fixtures.statementLog(c.rows))
        let after = StatementReconciler.allocate(before, monthly: c.monthly)
        let cents = after.map { Int(($0.numericPayout * 100).rounded()) }.reduce(0, +)
        XCTAssertEqual(cents, 10_000)
    }

    /// Characterization of defect B1. If statement reconciliation is ever fixed
    /// (shortcut pay subtracted before allocation), this test must change as an
    /// approved behaviour change — not be deleted.
    func testB1ShortcutPayIsNotSubtractedFromTheStatementTotal() {
        let c = cases.first { $0.id == "b1_shortcut_ignored" }!
        let before = MasterLogParser.parse(Fixtures.statementLog(c.rows))
        let after = StatementReconciler.allocate(before, monthly: c.monthly)

        let archivePay = after.filter(\.isArchive).map(\.numericPayout).reduce(0, +)
        let shortcutPay = after.filter { !$0.isArchive }.map(\.numericPayout).reduce(0, +)

        XCTAssertEqual(archivePay, 1000, accuracy: 0.001)
        XCTAssertEqual(shortcutPay, 250, accuracy: 0.001)
        XCTAssertEqual(archivePay + shortcutPay, 1250, accuracy: 0.001)
    }

    func testMonthWithoutStatementKeepsEstimatedPay() {
        let c = cases.first { $0.id == "no_statement" }!
        let before = MasterLogParser.parse(Fixtures.statementLog(c.rows))
        let after = StatementReconciler.allocate(before, monthly: c.monthly)
        XCTAssertEqual(after.map(\.payout), before.map(\.payout))
    }

    func testNonArchiveRowsAreNeverRepriced() {
        let c = cases.first { $0.id == "b1_shortcut_ignored" }!
        let before = MasterLogParser.parse(Fixtures.statementLog(c.rows))
        let after = StatementReconciler.allocate(before, monthly: c.monthly)
        let shortcutBefore = before.filter { !$0.isArchive }
        let shortcutAfter = after.filter { !$0.isArchive }
        XCTAssertEqual(shortcutAfter.map(\.payout), shortcutBefore.map(\.payout))
    }

    func testJavaScriptRoundingTiesGoUp() {
        XCTAssertEqual(StatementReconciler.jsRound(2.5), 3)
        XCTAssertEqual(StatementReconciler.jsRound(-0.5), 0)
        XCTAssertEqual(StatementReconciler.jsRound(267.49999999999997), 267)
    }
}
