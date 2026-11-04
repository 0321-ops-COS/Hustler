import XCTest
@testable import HustlerCore

/// The store read the Scoreboard now does off the main thread, and the rule that
/// lets a freshly signed-in phone adopt its account data without the replace tap.
/// Fixtures use invented values only: no real earnings or personal data.
final class HomeLoadTests: XCTestCase {

    private func scratch() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("HomeLoadTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: url) }
        return url
    }

    private var csv: String {
        MasterLog.normalize(Fixtures.headerLiteral + "\n"
            + Fixtures.shortcutLine("2026-10-26", payout: "8.00"))
    }

    // MARK: - HomeSnapshot

    /// Compiles only while the snapshot can cross the detached boundary the view
    /// model reads it on.
    private func requireSendable<T: Sendable>(_: T.Type) {}

    func testSnapshotCanCrossAnIsolationBoundary() {
        requireSendable(HomeSnapshot.self)
    }

    func testMissingStoreIsAnEmptyFirstRun() throws {
        let snapshot = HomeLoader.snapshot(in: try scratch())
        XCTAssertNil(snapshot.logUnavailable)
        XCTAssertFalse(snapshot.hasLog)
        XCTAssertEqual(snapshot.rows.count, 0)
        XCTAssertEqual(snapshot.statementMonths, [])
        XCTAssertEqual(snapshot.settings, AppSettings())
    }

    func testSavedLogAndSettingsAreRead() throws {
        let directory = try scratch()
        let store = LocalStore(directory: directory)
        try LocalLibrary(store: store).saveLog(csv)

        var settings = AppSettings()
        settings.gas = 6.25
        try SettingsStore(store: store).save(settings)

        let snapshot = HomeLoader.snapshot(in: directory)
        XCTAssertTrue(snapshot.hasLog)
        XCTAssertNil(snapshot.logUnavailable)
        XCTAssertEqual(snapshot.rows.count, MasterLog.rowCount(csv))
        XCTAssertEqual(snapshot.settings.gas, 6.25)
    }

    /// A file that exists but cannot be read is reported, never shown as "no log
    /// yet" and never dropped to an empty screen.
    func testUnreadableLogIsReported() throws {
        let directory = try scratch()
        let store = LocalStore(directory: directory)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try Data("not json".utf8).write(to: store.url(.masterLog))

        let snapshot = HomeLoader.snapshot(in: directory)
        XCTAssertNotNil(snapshot.logUnavailable)
        XCTAssertEqual(snapshot.rows.count, 0)
        XCTAssertFalse(snapshot.hasLog)
    }

    // MARK: - Store changes reach the screens

    func testSavingTheLogAnnouncesTheChange() throws {
        let directory = try scratch()
        let library = LocalLibrary(store: LocalStore(directory: directory))
        let note = expectation(forNotification: Notification.Name.hustlerStoreDidChange,
                               object: nil, handler: nil)
        try library.saveLog(csv)
        wait(for: [note], timeout: 1)
    }

    // MARK: - Adopting the account without the replace tap

    func testFreshPhoneAdopts() {
        XCTAssertTrue(AccountPull.canAdoptWithoutAsking(currentSettings: AppSettings(), currentLog: ""))
    }

    func testPhoneWithALogIsNeverOverwrittenWithoutAsking() {
        XCTAssertFalse(AccountPull.canAdoptWithoutAsking(currentSettings: AppSettings(),
                                                         currentLog: csv))
    }

    func testChangedSettingsStopTheAdopt() {
        var settings = AppSettings()
        settings.gas = 6.25
        XCTAssertFalse(AccountPull.canAdoptWithoutAsking(currentSettings: settings, currentLog: ""))
    }

    /// The exact path the gate takes after signing in on a fresh phone: the
    /// account's log lands in the phone's log and the settings apply.
    func testFreshPhonePlanWritesTheAccountsLog() throws {
        let accountCSV = MasterLog.normalize(Fixtures.headerLiteral + "\n"
            + Fixtures.shortcutLine("2026-10-27", payout: "26.50"))
        let logValue = try JSONSerialization.data(withJSONObject: ["csv": accountCSV, "v": 1])
        let settingsValue = try JSONSerialization.data(withJSONObject: ["gas": 5.75])
        let rows = [AccountStoreRow(key: "settings", updatedAt: nil, value: settingsValue),
                    AccountStoreRow(key: "log", updatedAt: nil, value: logValue)]

        let plan = try AccountPull.plan(rows: rows, currentSettings: AppSettings(), currentLog: "")
        XCTAssertTrue(plan.logChanged)
        XCTAssertEqual(plan.accountRows, MasterLog.rowCount(accountCSV))
        XCTAssertEqual(plan.log, accountCSV)
    }
}
