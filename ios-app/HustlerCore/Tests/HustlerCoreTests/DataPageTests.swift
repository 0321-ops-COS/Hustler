import XCTest
@testable import HustlerCore

/// Each delete runs against a real temporary directory, so these check the bytes
/// on disk as well as the result.
final class DataPageTests: XCTestCase {
    private func makeStore() throws -> LocalStore {
        let directory = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent("hustler-data-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: directory) }
        return LocalStore(directory: directory)
    }

    /// Two shortcut rows plus one archive row, one statement month, one CA week.
    private func seed(_ store: LocalStore) throws {
        let library = LocalLibrary(store: store)
        try library.saveLog(Fixtures.twoRows + "\n" + Fixtures.archiveRow)
        try library.addStatement(
            EarningsStatement(month: "2026-10", total: 1234.56, payouts: 123),
            text: Fixtures.statementCanonical
        )
        var settings = AppSettings()
        settings.gas = 6.25
        settings.caEntries = ["2026-10-26": CAWeekEntry(pay: 120, hours: 4, miles: 30)]
        try SettingsStore(store: store).save(settings)
    }

    private func log(_ store: LocalStore) throws -> MasterLogDocument {
        try XCTUnwrap(try store.load(MasterLogDocument.self, from: .masterLog))
    }
    private func book(_ store: LocalStore) throws -> StatementStoreDocument {
        try XCTUnwrap(try store.load(StatementStoreDocument.self, from: .statements))
    }
    private func bytes(_ store: LocalStore, _ artefact: StoreArtefact) throws -> Data {
        try Data(contentsOf: store.url(artefact))
    }

    // MARK: - Each delete on its own temporary store

    func testEachDeleteTouchesOnlyItsOwnArtefact() throws {
        for action in [DataDeleteAction.masterLog, .archive, .statements, .caEntries] {
            let store = try makeStore(); try seed(store)
            let result = DataWipe(store: store).perform(action)
            XCTAssertTrue(result.isComplete, "\(action.title): \(result.message)")
            switch action {
            case .masterLog:
                XCTAssertEqual(try log(store).rowCount, 0)
                XCTAssertEqual(try book(store).statements.count, 1)
                XCTAssertEqual(SettingsStore(store: store).settings.caEntries.count, 1)
            case .archive:
                XCTAssertEqual(try log(store).rowCount, 2)
                XCTAssertEqual(try log(store).archiveRowCount, 0)
                XCTAssertEqual(try book(store).statements.count, 1)
            case .statements:
                XCTAssertEqual(try book(store), StatementStoreDocument())
                XCTAssertEqual(try log(store).rowCount, 3)
                XCTAssertEqual(SettingsStore(store: store).settings.caEntries.count, 1)
            case .caEntries:
                XCTAssertTrue(SettingsStore(store: store).settings.caEntries.isEmpty)
                XCTAssertEqual(SettingsStore(store: store).settings.gas, 6.25)
                XCTAssertEqual(try log(store).rowCount, 3)
            case .everything:
                XCTFail("covered separately")
            }
        }
    }

    func testWipeEverythingEmptiesEveryLocalArtefact() throws {
        let store = try makeStore(); try seed(store)
        let result = DataWipe(store: store).perform(.everything)
        XCTAssertTrue(result.isComplete, result.message)
        XCTAssertEqual(try log(store).rowCount, 0)
        XCTAssertEqual(try book(store), StatementStoreDocument())
        XCTAssertEqual(SettingsStore(store: store).settings, AppSettings())
    }

    // MARK: - A blocked file is never overwritten by another delete

    func testDeletingStatementsNeverOverwritesABlockedLog() throws {
        let store = try makeStore(); try seed(store)
        let corrupt = Data("not json".utf8); try corrupt.write(to: store.url(.masterLog))
        let result = DataWipe(store: store).perform(.statements)
        XCTAssertTrue(result.isComplete, result.message)
        XCTAssertEqual(try book(store), StatementStoreDocument())
        XCTAssertEqual(try bytes(store, .masterLog), corrupt)
        XCTAssertEqual(SettingsStore(store: store).settings.caEntries.count, 1)
    }

    func testClearingTheLogNeverOverwritesBlockedStatements() throws {
        let store = try makeStore(); try seed(store)
        let corrupt = Data(#"{"schemaVersion":1,"statements":{"#.utf8)
        try corrupt.write(to: store.url(.statements))
        let result = DataWipe(store: store).perform(.masterLog)
        XCTAssertTrue(result.isComplete, result.message)
        XCTAssertEqual(try log(store).rowCount, 0)
        XCTAssertEqual(try bytes(store, .statements), corrupt)
    }

    func testClearingCANeverOverwritesBlockedSettings() throws {
        let store = try makeStore(); try seed(store)
        let corrupt = Data(#"{"schemaVersion":1"#.utf8); try corrupt.write(to: store.url(.settings))
        let result = DataWipe(store: store).perform(.caEntries)
        XCTAssertFalse(result.isComplete)
        XCTAssertEqual(try bytes(store, .settings), corrupt)
        XCTAssertEqual(try log(store).rowCount, 3)
    }

    func testWipeEverythingKeepsABlockedLogAndClearsTheRest() throws {
        let store = try makeStore(); try seed(store)
        let corrupt = Data("garbage".utf8); try corrupt.write(to: store.url(.masterLog))
        let result = DataWipe(store: store).perform(.everything)
        XCTAssertFalse(result.isComplete)
        XCTAssertTrue(result.message.contains("Nothing unreadable was overwritten"))
        XCTAssertEqual(try bytes(store, .masterLog), corrupt)
        XCTAssertEqual(try book(store), StatementStoreDocument())
        XCTAssertEqual(SettingsStore(store: store).settings, AppSettings())
    }
}
