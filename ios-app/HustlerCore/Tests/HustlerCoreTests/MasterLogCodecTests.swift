import XCTest
@testable import HustlerCore

/// Expected strings are copied from `expectations.json`, which the oracle wrote
/// by calling the web app's own `masterLog`, `mergeLog`, `csvToPipe`,
/// `isArchLine` and `logRows`.
final class MasterLogCodecTests: XCTestCase {

    private let header = Fixtures.headerLiteral

    func testHeaderMatchesWebApp() {
        XCTAssertEqual(MasterLog.header, Fixtures.headerLiteral)
    }

    func testNormalizeAddsHeaderAndKeepsRows() {
        XCTAssertEqual(MasterLog.normalize(Fixtures.twoRows), header + "\n" + Fixtures.twoRows)
        XCTAssertEqual(MasterLog.normalize(""), header)
        XCTAssertEqual(MasterLog.normalize(Fixtures.headerOnly), header)
    }

    func testNormalizeDropsDuplicateShortcutRows() {
        XCTAssertEqual(MasterLog.normalize(Fixtures.duplicatedRows), header + "\n" + Fixtures.firstShortcutRow)
    }

    func testNormalizeKeepsDuplicateArchiveRows() {
        XCTAssertEqual(
            MasterLog.normalize(Fixtures.archiveDupes),
            header + "\n" + Fixtures.archiveRow + "\n" + Fixtures.archiveRow
        )
    }

    func testNormalizeConvertsCSVRows() {
        let expected = header + "\n"
            + "| 2026-10-24 12:10 | 8.50 | 3.2 | 2 |  |  |  | Accept |  | Accepted |  | Murrieta | 18 |  |\n"
            + "| 2026-10-24 12:40 | 4.00 | 5.1 | 1 |  |  |  | Decline |  | Declined |  | Murrieta | 22 |  |"
        XCTAssertEqual(MasterLog.normalize(Fixtures.csvRows), expected)
    }

    func testNormalizeDropsUnreadableRows() {
        XCTAssertEqual(MasterLog.normalize(Fixtures.malformed), header)
    }

    func testNormalizeKeepsMoneyCells() {
        XCTAssertEqual(MasterLog.normalize(Fixtures.moneyCells), header + "\n" + Fixtures.moneyCells)
    }

    func testRowCounts() {
        XCTAssertEqual(MasterLog.rowCount(Fixtures.empty), 0)
        XCTAssertEqual(MasterLog.rowCount(Fixtures.headerOnly), 0)
        XCTAssertEqual(MasterLog.rowCount(Fixtures.twoRows), 2)
        XCTAssertEqual(MasterLog.rowCount(Fixtures.duplicatedRows), 1)
        XCTAssertEqual(MasterLog.rowCount(Fixtures.archiveDupes), 2)
        XCTAssertEqual(MasterLog.rowCount(Fixtures.csvRows), 2)
        XCTAssertEqual(MasterLog.rowCount(Fixtures.moneyCells), 1)
        XCTAssertEqual(MasterLog.rowCount(Fixtures.malformed), 0)
        XCTAssertEqual(MasterLog.rowCount(Fixtures.derivedMinutes), 1)
        // Documented asymmetry: parse() accepts this row, masterLog() drops it.
        XCTAssertEqual(MasterLog.rowCount(Fixtures.rowNumbered), 0)
    }

    func testArchiveLineDetection() {
        XCTAssertFalse(MasterLog.isArchiveLine(Fixtures.csvLinePlain))
        XCTAssertFalse(MasterLog.isArchiveLine(Fixtures.csvLineShortcut))
        XCTAssertFalse(MasterLog.isArchiveLine(Fixtures.csvLineInvalid))
        XCTAssertTrue(MasterLog.isArchiveLine(Fixtures.archiveRow))
    }

    func testCsvToPipeMatchesWebApp() {
        XCTAssertEqual(
            MasterLog.csvToPipe(Fixtures.csvLinePlain),
            "| 2026-10-27 14:46 | 26.50 | 9.1 | 6 |  |  |  | TAKE IT |  | Accept |  | Murrieta | 30 |  |"
        )
        // 15-column shortcut rows keep the 11-column shape and lose zone/minutes
        // (defect B6, preserved rather than "fixed").
        XCTAssertEqual(
            MasterLog.csvToPipe(Fixtures.csvLineShortcut),
            "| 2026-10-27 14:46 | 26.50 | 9.1 | 6 | 2.91 | 22.42 | 30.06 | TAKE IT | x | Accept | 15.25 |"
        )
        XCTAssertNil(MasterLog.csvToPipe(Fixtures.csvLineInvalid))
        XCTAssertNil(MasterLog.csvToPipe(Fixtures.archiveRow))
    }

    func testMergeIsIdempotentForArchives() {
        let merged = MasterLog.merge(current: Fixtures.archiveDupes, adding: Fixtures.archiveDupes)
        XCTAssertEqual(MasterLog.rowCount(merged), 2)
        XCTAssertEqual(merged, MasterLog.normalize(Fixtures.archiveDupes))
    }

    func testMergeAddsNewRows() {
        XCTAssertEqual(MasterLog.rowCount(MasterLog.merge(current: Fixtures.headerOnly, adding: Fixtures.twoRows)), 2)
        XCTAssertEqual(MasterLog.rowCount(MasterLog.merge(current: Fixtures.twoRows, adding: Fixtures.twoRows)), 2)
    }
}
