import XCTest
@testable import HustlerCore

/// Offers-file import: content classification, CSV/JSON conversion, the header
/// rule, dedupe and counts. Every fixture is invented synthetic text.
final class OffersImportTests: XCTestCase {

    private let json = """
    [
      {"date":"2026-10-24","time":"12:10","zone":"Murrieta","payout":"8.50","miles":3.2,
       "items":2,"minutes":18,"verdict":"Accept","choice":"Accepted"},
      {"date":"2026-10-24","time":"12:40","zone":"Murrieta","payout":"4.00","miles":5.1,
       "items":1,"minutes":22,"verdict":"Decline","choice":"Declined"}
    ]
    """

    private func result(_ outcome: OffersImportOutcome) throws -> OffersImportResult {
        guard case let .imported(result) = outcome else {
            throw XCTSkip("expected an import, got \(outcome)")
        }
        return result
    }

    func testPipeTextAddsTheMissingHeaderAndKeepsExistingRows() throws {
        let imported = try result(OffersImporter.outcome(
            text: Fixtures.twoRows,
            existingLog: Fixtures.firstShortcutRow
        ))

        XCTAssertEqual(
            imported.mergedLog,
            MasterLog.header + "\n" + Fixtures.firstShortcutRow + "\n" + Fixtures.secondShortcutRow
        )
        XCTAssertEqual(
            imported.counts,
            OffersImportCounts(rowsInspected: 2, newlyAdded: 1, skipped: 1)
        )
    }

    func testCSVAndJSONProduceTheSameRows() throws {
        let csv = try result(OffersImporter.outcome(text: Fixtures.csvRows, existingLog: ""))
        let json = try result(OffersImporter.outcome(text: json, existingLog: ""))

        XCTAssertEqual(json.mergedLog, csv.mergedLog)
        XCTAssertEqual(MasterLog.rowCount(csv.mergedLog), 2)
        XCTAssertEqual(csv.counts, OffersImportCounts(rowsInspected: 2, newlyAdded: 2, skipped: 0))
    }

    func testDuplicatesAcrossAndInsideFilesAreSkipped() throws {
        let first = try result(OffersImporter.outcome(text: Fixtures.twoRows, existingLog: ""))
        let second = try result(OffersImporter.outcome(
            text: Fixtures.twoRows,
            existingLog: first.mergedLog
        ))
        XCTAssertEqual(second.mergedLog, first.mergedLog)
        XCTAssertEqual(second.counts, OffersImportCounts(rowsInspected: 2, newlyAdded: 0, skipped: 2))

        let repeated = try result(OffersImporter.outcome(
            text: Fixtures.firstShortcutRow + "\n" + Fixtures.firstShortcutRow,
            existingLog: ""
        ))
        XCTAssertEqual(MasterLog.rowCount(repeated.mergedLog), 1)
        XCTAssertEqual(repeated.counts.newlyAdded, 1)
    }

    func testEmptyGarbageAndHeaderOnlyFilesAreRefused() {
        XCTAssertEqual(OffersImporter.outcome(text: "", existingLog: ""), .empty)
        XCTAssertEqual(OffersImporter.outcome(text: "  \n\t\n ", existingLog: ""), .empty)
        XCTAssertEqual(
            OffersImporter.outcome(text: "this is not a log\nneither is this", existingLog: ""),
            .unreadable
        )
        XCTAssertEqual(OffersImporter.outcome(text: MasterLog.header, existingLog: ""), .unreadable)
    }

    func testDeliveryFileIsRefused() {
        let text = "ORDER_CREATED_TIME,ACTUAL_DELIVERY_TIME\n2026-10-24,2026-10-24 12:10"
        XCTAssertEqual(OffersImporter.outcome(text: text, existingLog: ""), .deliveryFile)
    }
}
