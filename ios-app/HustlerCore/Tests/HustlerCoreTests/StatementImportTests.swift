import XCTest
@testable import HustlerCore

/// Tests for the import state machine, the month summaries the screen shows,
/// and the versioned documents the app writes. The allocation and parsing
/// numbers themselves are already pinned against the web app in
/// `StatementReconcilerTests` and `StatementParserTests`; these tests only
/// assert how they are classified and presented.
final class StatementImportTests: XCTestCase {

    // MARK: - Outcome classification

    func testValidTextParses() {
        let outcome = StatementImporter.outcome(text: Fixtures.statementCanonical, source: .pdf)
        XCTAssertEqual(
            outcome,
            .parsed(EarningsStatement(month: "2026-10", total: 1234.56, payouts: 123))
        )
    }

    func testBlankAndWhitespaceTextIsEmpty() {
        XCTAssertEqual(StatementImporter.outcome(text: "", source: .paste), .emptyText(.paste))
        XCTAssertEqual(StatementImporter.outcome(text: "  \n\t\n ", source: .pdf), .emptyText(.pdf))
    }

    func testTextWithoutStatementFieldsIsUnreadable() {
        XCTAssertEqual(
            StatementImporter.outcome(text: "DoorDash earnings summary, no totals here", source: .paste),
            .unreadable(.paste)
        )
        // The parser's own strict rejections still classify as unreadable.
        XCTAssertEqual(
            StatementImporter.outcome(text: Fixtures.statementTotalOneDecimal, source: .pdf),
            .unreadable(.pdf)
        )
    }

    func testTheSourceSurvivesAnEmptyResult() {
        // The screen tells a scan apart from a bad paste; that only works if the
        // source is not lost on the empty branch.
        guard case let .emptyText(source) = StatementImporter.outcome(text: " ", source: .pdf) else {
            return XCTFail("expected empty text")
        }
        XCTAssertEqual(source, .pdf)
    }

    // MARK: - Month summaries

    /// Seeds a book the way `takeStm()` leaves it: a statement record plus a
    /// `monthly` total for each month. Constructed through the initialiser
    /// because the stores are read-only from outside the module's own type.
    private func book(_ statements: [EarningsStatement]) -> StatementBook {
        var records: [String: EarningsStatement] = [:]
        var months: [String: StatementMonth] = [:]
        for statement in statements {
            records[statement.month] = statement
            months[statement.month] = StatementMonth(
                total: statement.total,
                miles: months[statement.month]?.miles ?? 0
            )
        }
        return StatementBook(statements: records, monthly: months)
    }

    func testSummaryShowsAllocationAndTheB1OverCount() {
        let rows = MasterLogParser.parse(Fixtures.statementLog([
            Fixtures.archiveLine("2026-09-05 18:00", minutes: "10"),
            Fixtures.archiveLine("2026-09-06 12:00", minutes: "20"),
            Fixtures.shortcutLine("2026-09-06", payout: "250.00"),
            Fixtures.archiveLine("2026-10-03 11:00", minutes: "30")
        ]))
        let summaries = StatementImporter.summaries(
            book: book([EarningsStatement(month: "2026-09", total: 1000, payouts: 42)]),
            rows: rows
        )

        XCTAssertEqual(summaries.count, 1)
        let summary = summaries[0]
        XCTAssertEqual(summary.month, "2026-09")
        XCTAssertEqual(summary.total, 1000, accuracy: 1e-9)
        XCTAssertEqual(summary.payouts, 42)
        XCTAssertEqual(summary.archiveRows, 2)
        XCTAssertEqual(summary.loggedRows, 1)
        // The statement total lands entirely on the archive rows...
        XCTAssertEqual(summary.allocatedPay, 1000, accuracy: 0.001)
        // ...and the logged shortcut pay sits on top: B1, shown not fixed.
        XCTAssertEqual(summary.loggedLivePay, 250, accuracy: 0.001)
    }

    func testSummaryCountsOnlyAcceptedLoggedRows() {
        let declined = "| 2026-09-07 08:00 | 9.00 | 4.0 | 2 | 2.25 | 6.66 | 20.00 | SKIP | 89.00 | Declined | 0 |"
        let rows = MasterLogParser.parse(Fixtures.statementLog([
            Fixtures.archiveLine("2026-09-05 18:00", minutes: "10"),
            declined
        ]))
        let summaries = StatementImporter.summaries(
            book: book([EarningsStatement(month: "2026-09", total: 100, payouts: 1)]),
            rows: rows
        )
        XCTAssertEqual(summaries[0].loggedRows, 0)
        XCTAssertEqual(summaries[0].loggedLivePay, 0)
        XCTAssertEqual(summaries[0].archiveRows, 1)
        XCTAssertEqual(summaries[0].allocatedPay, 100, accuracy: 0.001)
    }

    func testMonthsWithoutArchiveRowsHaveNothingToAllocate() {
        let summaries = StatementImporter.summaries(
            book: book([EarningsStatement(month: "2026-11", total: 88, payouts: 3)]),
            rows: []
        )
        XCTAssertEqual(summaries.count, 1)
        XCTAssertEqual(summaries[0].archiveRows, 0)
        XCTAssertEqual(summaries[0].allocatedPay, 0)
    }

    func testMonthsAreNewestFirst() {
        let summaries = StatementImporter.summaries(
            book: book([
                EarningsStatement(month: "2026-09", total: 1, payouts: 0),
                EarningsStatement(month: "2026-10", total: 2, payouts: 0),
                EarningsStatement(month: "2025-12", total: 3, payouts: 0)
            ]),
            rows: []
        )
        XCTAssertEqual(summaries.map(\.month), ["2026-10", "2026-09", "2025-12"])
    }

    // MARK: - Store documents

    func testStatementDocumentRoundTripsThroughJSON() throws {
        var book = StatementBook(monthly: ["2026-10": StatementMonth(total: 0, miles: 321.4)])
        XCTAssertEqual(book.take([Fixtures.statementCanonical]), 1)

        let document = StatementStoreDocument(book: book)
        let data = try JSONEncoder().encode(document)
        let decoded = try JSONDecoder().decode(StatementStoreDocument.self, from: data)

        XCTAssertEqual(decoded, document)
        XCTAssertEqual(decoded.book, book)
        XCTAssertEqual(decoded.monthly["2026-10"]?.miles, 321.4)
    }

    func testStatementDocumentEncodesItsVersion() throws {
        let data = try JSONEncoder().encode(StatementStoreDocument())
        let json = try XCTUnwrap(
            JSONSerialization.jsonObject(with: data) as? [String: Any]
        )
        XCTAssertEqual(json["schemaVersion"] as? Int, StatementStoreDocument.currentVersion)
    }

    func testNewerStatementDocumentIsRejected() {
        let json = Data(#"{"schemaVersion":2,"statements":{},"monthly":{}}"#.utf8)
        XCTAssertThrowsError(try JSONDecoder().decode(StatementStoreDocument.self, from: json)) { error in
            XCTAssertEqual(error as? StoreDocumentError, .unsupportedVersion(2))
        }
    }

    func testUnreadableStatementDocumentThrows() {
        XCTAssertThrowsError(try JSONDecoder().decode(StatementStoreDocument.self, from: Data("nope".utf8)))
    }

    func testMasterLogDocumentNormalisesAndCounts() {
        let document = MasterLogDocument(text: Fixtures.statementLog([
            Fixtures.archiveLine("2026-09-05 18:00", minutes: "10"),
            Fixtures.shortcutLine("2026-09-06", payout: "250.00")
        ]))
        XCTAssertEqual(document.rowCount, 2)
        XCTAssertEqual(document.archiveRowCount, 1)
        XCTAssertTrue(document.text.hasPrefix(MasterLog.header))
    }

    func testEmptyMasterLogKeepsOnlyTheHeader() {
        let document = MasterLogDocument(text: "")
        XCTAssertEqual(document.text, MasterLog.header)
        XCTAssertEqual(document.rowCount, 0)
        XCTAssertEqual(document.archiveRowCount, 0)
    }

    func testSavingTheSameLogTwiceIsIdempotent() {
        let once = MasterLogDocument(text: Fixtures.statementLog([
            Fixtures.archiveLine("2026-09-05 18:00", minutes: "10")
        ]))
        let twice = MasterLogDocument(text: once.text)
        XCTAssertEqual(twice.text, once.text)
        XCTAssertEqual(twice.rowCount, once.rowCount)
    }

    func testMasterLogDocumentRoundTripsAndRejectsNewerVersions() throws {
        let document = MasterLogDocument(text: Fixtures.twoRows)
        let data = try JSONEncoder().encode(document)
        XCTAssertEqual(try JSONDecoder().decode(MasterLogDocument.self, from: data), document)

        let newer = Data(#"{"schemaVersion":9,"text":""}"#.utf8)
        XCTAssertThrowsError(try JSONDecoder().decode(MasterLogDocument.self, from: newer)) { error in
            XCTAssertEqual(error as? StoreDocumentError, .unsupportedVersion(9))
        }
    }

    func testFailedImportLeavesTheDocumentIdentical() {
        var book = StatementBook()
        XCTAssertEqual(book.take([Fixtures.statementCanonical]), 1)
        let before = StatementStoreDocument(book: book)
        XCTAssertEqual(book.take(["DoorDash earnings, no totals"]), 0)
        XCTAssertEqual(StatementStoreDocument(book: book), before)
    }
}
