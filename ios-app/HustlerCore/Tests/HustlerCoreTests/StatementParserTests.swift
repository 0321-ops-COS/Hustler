import XCTest
@testable import HustlerCore

/// Parsing and import values captured by running the web app's own `stmParse()`
/// and `takeStm()` over the same texts in the parity oracle
/// (`expectations.json`, section `statements.parse` and `statements.store`).
final class StatementParserTests: XCTestCase {

    private struct StatementParseCase {
        let id: String
        let text: String
        let month: String
        let total: Double
        let payouts: Int
    }

    private struct StatementNilCase {
        let id: String
        let text: String
    }

    private struct StoreCase {
        let id: String
        let seed: [String: StatementMonth]
        let texts: [String]
        let statements: [String]
        let monthly: [String]
    }

    private let parsedCases: [StatementParseCase] = [
        StatementParseCase(id: "canonical", text: Fixtures.statementCanonical, month: "2026-10", total: 1234.56, payouts: 123),
        StatementParseCase(id: "no_count", text: Fixtures.statementNoCount, month: "2026-11", total: 88, payouts: 0),
        StatementParseCase(id: "total_on_next_line", text: Fixtures.statementTotalOnNextLine, month: "2027-01", total: 1000, payouts: 7),
        StatementParseCase(id: "december", text: Fixtures.statementDecember, month: "2026-12", total: 0.99, payouts: 0),
        StatementParseCase(id: "large_count", text: Fixtures.statementLargeCount, month: "2026-10", total: 10, payouts: 10000),
        StatementParseCase(id: "reordered", text: Fixtures.statementReordered, month: "2026-05", total: 55.55, payouts: 9),
        StatementParseCase(id: "trailing_text", text: Fixtures.statementTrailingText, month: "2026-10", total: 1234.56, payouts: 123),
        StatementParseCase(id: "month_january", text: Fixtures.statementMonth("January"), month: "2026-01", total: 1, payouts: 0),
        StatementParseCase(id: "month_february", text: Fixtures.statementMonth("February"), month: "2026-02", total: 1, payouts: 0),
        StatementParseCase(id: "month_march", text: Fixtures.statementMonth("March"), month: "2026-03", total: 1, payouts: 0),
        StatementParseCase(id: "month_april", text: Fixtures.statementMonth("April"), month: "2026-04", total: 1, payouts: 0),
        StatementParseCase(id: "month_may", text: Fixtures.statementMonth("May"), month: "2026-05", total: 1, payouts: 0),
        StatementParseCase(id: "month_june", text: Fixtures.statementMonth("June"), month: "2026-06", total: 1, payouts: 0),
        StatementParseCase(id: "month_july", text: Fixtures.statementMonth("July"), month: "2026-07", total: 1, payouts: 0),
        StatementParseCase(id: "month_august", text: Fixtures.statementMonth("August"), month: "2026-08", total: 1, payouts: 0),
        StatementParseCase(id: "month_september", text: Fixtures.statementMonth("September"), month: "2026-09", total: 1, payouts: 0),
        StatementParseCase(id: "month_october", text: Fixtures.statementMonth("October"), month: "2026-10", total: 1, payouts: 0),
        StatementParseCase(id: "month_november", text: Fixtures.statementMonth("November"), month: "2026-11", total: 1, payouts: 0),
        StatementParseCase(id: "month_december", text: Fixtures.statementMonth("December"), month: "2026-12", total: 1, payouts: 0)
    ]

    private let nilCases: [StatementNilCase] = [
        StatementNilCase(id: "missing_total", text: Fixtures.statementMissingTotal),
        StatementNilCase(id: "missing_month", text: Fixtures.statementMissingMonth),
        StatementNilCase(id: "lowercase_month", text: Fixtures.statementLowercaseMonth),
        StatementNilCase(id: "month_without_year", text: Fixtures.statementMonthWithoutYear),
        StatementNilCase(id: "double_space_month", text: Fixtures.statementDoubleSpaceMonth),
        StatementNilCase(id: "total_one_decimal", text: Fixtures.statementTotalOneDecimal),
        StatementNilCase(id: "total_whole_dollars", text: Fixtures.statementTotalWholeDollars)
    ]

    // `statements` and `monthly` use the compact form `month:cents:payouts` and
    // `month:cents:miles`, which `drift.mjs` compares with the oracle.
    private let storeCases: [StoreCase] = [
        StoreCase(id: "fresh_two_statements", seed: [:],
                  texts: [Fixtures.statementCanonical, Fixtures.statementDecember],
                  statements: ["2026-10:123456:123", "2026-12:99:0"],
                  monthly: ["2026-10:123456:0", "2026-12:99:0"]),
        StoreCase(id: "reimport_preserves_miles",
                  seed: ["2026-10": StatementMonth(total: 50, miles: 42)],
                  texts: [Fixtures.statementCanonical],
                  statements: ["2026-10:123456:123"],
                  monthly: ["2026-10:123456:42"]),
        StoreCase(id: "unreadable_changes_nothing",
                  seed: ["2026-10": StatementMonth(total: 50, miles: 42)],
                  texts: ["not a statement"],
                  statements: [],
                  monthly: ["2026-10:5000:42"])
    ]

    func testParsedStatementsMatchObservedValues() {
        for c in parsedCases {
            guard let statement = StatementParser.parse(c.text) else {
                XCTFail("\(c.id) did not parse")
                continue
            }
            XCTAssertEqual(statement.month, c.month, c.id)
            XCTAssertEqual(statement.total, c.total, accuracy: 1e-9, c.id)
            XCTAssertEqual(statement.payouts, c.payouts, c.id)
        }
    }

    func testRejectedTextsMatchObservedNonParses() {
        for c in nilCases {
            XCTAssertNil(StatementParser.parse(c.text), c.id)
        }
    }

    func testImportMatchesObservedWebBehaviour() {
        for c in storeCases {
            var book = StatementBook(monthly: c.seed)
            var read = 0
            for text in c.texts {
                read += book.take([text])
            }
            XCTAssertEqual(read, c.statements.count, c.id)

            let statements = book.statements.keys.sorted().map { key -> String in
                let statement = book.statements[key]!
                return "\(key):\(Int((statement.total * 100).rounded())):\(statement.payouts)"
            }
            let monthly = book.monthly.keys.sorted().map { key -> String in
                let month = book.monthly[key]!
                return "\(key):\(Int((month.total * 100).rounded())):\(JsNumber.description(month.miles))"
            }
            XCTAssertEqual(statements, c.statements, c.id)
            XCTAssertEqual(monthly, c.monthly, c.id)
        }
    }

    func testUnreadableImportLeavesTheBookUntouched() {
        var book = StatementBook(
            statements: ["2026-10": EarningsStatement(month: "2026-10", total: 50, payouts: 2)],
            monthly: ["2026-10": StatementMonth(total: 50, miles: 42)]
        )
        let before = book
        XCTAssertEqual(book.take(["not a statement"]), 0)
        XCTAssertEqual(book, before)
    }

    func testReimportKeepsExistingMiles() {
        var book = StatementBook(monthly: ["2026-10": StatementMonth(total: 50, miles: 42)])
        XCTAssertEqual(book.take([Fixtures.statementCanonical]), 1)
        XCTAssertEqual(book.monthly["2026-10"]?.miles, 42)
        XCTAssertEqual(book.monthly["2026-10"]?.total ?? 0, 1234.56, accuracy: 1e-9)
    }
}
