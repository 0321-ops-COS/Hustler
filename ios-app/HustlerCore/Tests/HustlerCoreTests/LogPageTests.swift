import XCTest
@testable import HustlerCore
/// The Log page's buttons against a real temporary store: "saved" means the next
/// `LocalLibrary` reads it back, "blocked" means the bytes are still unreadable.
final class LogPageTests: XCTestCase {
    private func makeStore() throws -> LocalStore {
        let directory = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent("hustler-logpage-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: directory) }
        return LocalStore(directory: directory)
    }
    private func reloaded(_ store: LocalStore) -> LocalLibrary {
        LocalLibrary(store: LocalStore(directory: store.directory))
    }
    func testAnalyzeAndSaveNormalisesThenScopeSaveReplacesOneDay() throws {
        let store = try makeStore()
        let model = LogPageModel(store: store, today: "2026-10-27")
        model.draft = Fixtures.twoRows + "\n" + Fixtures.firstShortcutRow // duplicate dropped
        model.analyzeAndSave()
        XCTAssertEqual(model.rows, 2)
        XCTAssertFalse(model.noticeIsFailure)
        XCTAssertEqual(model.columns.map(\.name), ["payout", "miles", "items", "minutes"])
        model.setMode(.day)
        XCTAssertEqual(model.key, "2026-10-27")
        model.draft = "| 2026-10-27 09:00 | 12.00 | 4.0 | 2 | 3.00 | 9.00 | 27.00 | TAKE IT | 89.00 | Accept | 5 |"
        model.analyzeAndSave()
        XCTAssertEqual(model.rows, 1)
        XCTAssertEqual(reloaded(store).log.rowCount, 1)
        XCTAssertEqual(model.columns.first?.type, "float")
    }
    func testClearForTodayAndAnotherDayFollowTheWebRules() throws {
        let store = try makeStore()
        try LocalLibrary(store: store).saveLog(Fixtures.twoRows + "\n" + Fixtures.archiveRow)
        let model = LogPageModel(store: store, today: "2026-10-27")
        model.clearForToday()
        XCTAssertEqual(model.rows, 1)
        XCTAssertEqual(model.notice, "2 entries for today cleared.")
        let other = LogPageModel(store: store, today: "2026-10-26")
        other.setMode(.day)
        XCTAssertEqual(other.key, "2026-10-25")
        XCTAssertTrue(other.needsClearConfirmation)
        other.clearForToday()
        XCTAssertEqual(other.rows, 1)
        other.clearForToday(confirmed: true)
        XCTAssertEqual(reloaded(store).log.rowCount, 0)
    }
    func testDemoIsNeverSavedAndADuplicatePasteWarns() throws {
        let store = try makeStore()
        let model = LogPageModel(store: store, today: "2026-10-27")
        model.tryDemo()
        XCTAssertEqual(model.demoRows, 4)
        XCTAssertEqual(model.notice, "Demo data, not saved.")
        XCTAssertFalse(FileManager.default.fileExists(atPath: store.url(.masterLog).path))
        try LocalLibrary(store: store).saveLog(Fixtures.firstShortcutRow)
        let second = LogPageModel(store: store, today: "2026-10-27")
        second.pasteRows(Fixtures.firstShortcutRow)
        XCTAssertEqual(second.notice, "This row is already in your log. Nothing was saved or counted.")
        XCTAssertEqual(second.rows, 1)
        second.pasteRows(Fixtures.secondShortcutRow)
        XCTAssertEqual(reloaded(store).log.rowCount, 2)
    }
    func testBlockedLogIsNeverReplacedAndRecoversExplicitly() throws {
        let store = try makeStore()
        let corrupt = Data("{not json".utf8)
        try corrupt.write(to: store.url(.masterLog))
        let model = LogPageModel(store: store, today: "2026-10-27")
        XCTAssertNotNil(model.problem)
        model.draft = Fixtures.twoRows
        model.analyzeAndSave()
        model.pasteRows(Fixtures.secondShortcutRow)
        XCTAssertTrue(model.noticeIsFailure)
        XCTAssertTrue(store.isBlocked(.masterLog))
        XCTAssertEqual(try Data(contentsOf: store.url(.masterLog)), corrupt)
        model.recover()
        XCTAssertNil(model.problem)
        XCTAssertFalse(FileManager.default.fileExists(atPath: store.url(.masterLog).path))
    }
    func testCheckSummaryCountsBadCellsLikeShowCheck() {
        var row = MasterLogParser.parse(Fixtures.headerLiteral + "\n" + Fixtures.firstShortcutRow)[0]
        row.payout = "$12.00"; row.miles = "n/a"
        let columns = LogCheck.columns(for: [row])
        XCTAssertEqual(columns[0].type, "float")
        XCTAssertEqual(columns[1].check, "1 bad (rows 2)")
        XCTAssertEqual(columns[2].type, "whole numbers")
        XCTAssertEqual(columns[3].check, "all clean")
    }
}
