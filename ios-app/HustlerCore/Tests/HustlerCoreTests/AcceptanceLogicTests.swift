import XCTest
@testable import HustlerCore

/// `LOGACC` and `LOGRATE` expectations come from running the web app's
/// `analyze()` over the same fixtures inside the parity oracle.
final class AcceptanceLogicTests: XCTestCase {

    func testRateFromDoorDashCounts() {
        XCTAssertEqual(AcceptanceLogic.fromCounts(accepted: 89, declined: 11), 89)
        XCTAssertEqual(AcceptanceLogic.fromCounts(accepted: 1, declined: 2), 33)
        XCTAssertEqual(AcceptanceLogic.fromCounts(accepted: 2, declined: 1), 67)
        XCTAssertNil(AcceptanceLogic.fromCounts(accepted: 0, declined: 0))
    }

    func testLogRate() {
        XCTAssertEqual(AcceptanceLogic.logRate(MasterLogParser.parse(Fixtures.twoRows)), 50)
        XCTAssertEqual(AcceptanceLogic.logRate(MasterLogParser.parse(Fixtures.rowNumbered)), 100)
        XCTAssertNil(AcceptanceLogic.logRate(MasterLogParser.parse(Fixtures.archiveDupes)))
    }

    func testNewestLoggedRate() {
        let older = MasterLog.orderedForAnalysis(MasterLogParser.parse(Fixtures.rateOlderAndNewest))
        XCTAssertEqual(AcceptanceLogic.newestLoggedRate(older), 87.5)

        let blank = MasterLog.orderedForAnalysis(MasterLogParser.parse(Fixtures.rateBlankNewest))
        XCTAssertEqual(AcceptanceLogic.newestLoggedRate(blank), 91)

        let archiveNewest = MasterLog.orderedForAnalysis(MasterLogParser.parse(Fixtures.rateArchiveNewest))
        XCTAssertEqual(AcceptanceLogic.newestLoggedRate(archiveNewest), 91)

        XCTAssertNil(AcceptanceLogic.newestLoggedRate(MasterLogParser.parse(Fixtures.archiveDupes)))
    }

    func testEffectiveRatePrefersLogRate() {
        XCTAssertEqual(AcceptanceLogic.effectiveRate(settings: 89, logged: nil), 89)
        XCTAssertEqual(AcceptanceLogic.effectiveRate(settings: 89, logged: 87.5), 87.5)
    }

    func testOrderingIsAscendingAndStable() {
        let rows = [
            LogRow(date: "2026-10-27", time: "10:00", payout: "9"),
            LogRow(date: "2026-10-20", time: "10:00", payout: "10"),
            LogRow(date: "2026-10-20", time: "10:00", payout: "11")
        ]
        let ordered = MasterLog.orderedForAnalysis(rows)
        XCTAssertEqual(ordered.map { $0.date }, ["2026-10-20", "2026-10-20", "2026-10-27"])
        XCTAssertEqual(ordered[0].payout, "10", "ties must keep arrival order")
        XCTAssertEqual(ordered[1].payout, "11")
    }
}
