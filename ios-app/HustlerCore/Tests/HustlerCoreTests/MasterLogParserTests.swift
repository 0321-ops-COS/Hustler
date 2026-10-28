import XCTest
@testable import HustlerCore

final class MasterLogParserTests: XCTestCase {

    func testParsesShortcutRows() {
        let rows = MasterLogParser.parse(Fixtures.twoRows)
        XCTAssertEqual(rows.count, 2)

        XCTAssertEqual(rows[0].date, "2026-10-27")
        XCTAssertEqual(rows[0].time, "14:46")
        XCTAssertEqual(rows[0].payout, "26.50")
        XCTAssertEqual(rows[0].miles, "9.1")
        XCTAssertEqual(rows[0].items, "6")
        XCTAssertEqual(rows[0].rate, "80.00")
        XCTAssertEqual(rows[0].choice, "Accept")
        XCTAssertEqual(rows[0].source, "")
        XCTAssertEqual(rows[0].minutes, "44.8")
        XCTAssertTrue(rows[0].verdictIsYes)
        XCTAssertTrue(rows[0].choiceTook)

        XCTAssertEqual(rows[1].minutes, "29.5")
        XCTAssertEqual(rows[1].choice, "Declined")
        XCTAssertFalse(rows[1].verdictIsYes)
        XCTAssertFalse(rows[1].choiceTook)
    }

    /// `parse()` accepts a row-numbered line; `masterLog()` rejects it. The web
    /// app really behaves this way, so the port keeps both.
    func testRowNumberedColumnIsStrippedButRowIsDroppedByNormalize() {
        let rows = MasterLogParser.parse(Fixtures.rowNumbered)
        XCTAssertEqual(rows.count, 1)
        XCTAssertEqual(rows[0].date, "2026-10-26")
        XCTAssertEqual(rows[0].time, "09:00")
        XCTAssertEqual(rows[0].minutes, "20")
        XCTAssertEqual(MasterLog.rowCount(Fixtures.rowNumbered), 0)
    }

    func testMinutesAreDerivedWhenAbsent() {
        XCTAssertEqual(MasterLogParser.parse(Fixtures.derivedMinutes).first?.minutes, "20")
        // net 1200 / hourly 100 * 60 = 720
        XCTAssertEqual(MasterLogParser.parse(Fixtures.moneyCells).first?.minutes, "720")
    }

    func testMoneyCellsStayTextual() {
        let row = MasterLogParser.parse(Fixtures.moneyCells).first
        XCTAssertEqual(row?.payout, "$1,234.50")
        XCTAssertEqual(row?.net, "1,200.00")
        XCTAssertEqual(row?.numericPayout ?? 0, 1234.5, accuracy: 1e-9)
    }

    /// `parse()` is not a validator; `normalize()` is. Preserved deliberately.
    func testParserDoesNotValidateAndNormalizeDrops() {
        let rows = MasterLogParser.parse(Fixtures.malformed)
        XCTAssertEqual(rows.count, 2)
        XCTAssertEqual(rows[0].payout, "n/a")
        XCTAssertEqual(rows[1].date, "not-a-date")
        XCTAssertEqual(MasterLog.rowCount(Fixtures.malformed), 0)
    }

    func testParsesCSVByHeaderName() {
        let rows = MasterLogParser.parse(Fixtures.csvRows)
        XCTAssertEqual(rows.count, 2)
        XCTAssertEqual(rows[0].date, "2026-10-24")
        XCTAssertEqual(rows[0].time, "12:10")
        XCTAssertEqual(rows[0].zone, "Murrieta")
        XCTAssertEqual(rows[0].minutes, "18")
        XCTAssertEqual(rows[0].choice, "Accepted")
        XCTAssertEqual(rows[1].minutes, "22")
        XCTAssertFalse(rows[1].choiceTook)
    }

    func testEmptyAndHeaderOnly() {
        XCTAssertTrue(MasterLogParser.parse(Fixtures.empty).isEmpty)
        XCTAssertTrue(MasterLogParser.parse(Fixtures.headerOnly).isEmpty)
    }

    func testSerializedLineRoundTrips() {
        let row = MasterLogParser.parse(Fixtures.archiveRow).first
        XCTAssertEqual(row?.serializedLine, Fixtures.archiveRow)

        // An 11-column shortcut row widens to the 14-column shape when
        // serialised; the cells it does carry are unchanged.
        let shortcut = MasterLogParser.parse(Fixtures.firstShortcutRow).first
        let widened = shortcut?.serializedLine ?? ""
        let reparsed = MasterLogParser.parse(widened).first
        XCTAssertEqual(reparsed?.payout, "26.50")
        XCTAssertEqual(reparsed?.minutes, "44.8")
        XCTAssertEqual(reparsed?.dateWithTime, "2026-10-27 14:46")
        XCTAssertEqual(reparsed?.choice, "Accept")
    }
}
