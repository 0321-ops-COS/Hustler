import XCTest
@testable import HustlerCore

/// Fixtures use the shapes the web app really stores in `hh_store`
/// (`index.html`): `settings` is the bare settings object and `log` is
/// `{csv, v}`. Invented values only: no real earnings or personal data.
final class AccountPullTests: XCTestCase {
    private let accountSettings: [String: Any] = [
        "accept": 89, "estPay": 8.5, "mpg": 17.5, "gas": 5.75,
        "zoneGas": ["Temecula": 6.4], "accSet": 1
    ]

    private func logValue(_ csv: String) throws -> String {
        let object: [String: Any] = ["csv": csv, "v": 1]
        return String(decoding: try JSONSerialization.data(withJSONObject: object), as: UTF8.self)
    }

    private func settingsValue(_ settings: [String: Any]) throws -> String {
        String(decoding: try JSONSerialization.data(withJSONObject: settings), as: UTF8.self)
    }

    private func row(_ key: String, _ value: String, updatedAt: String? = "2026-11-02T10:00:00Z") -> AccountStoreRow {
        AccountStoreRow(key: key, updatedAt: updatedAt, value: Data(value.utf8))
    }

    private var phoneLog: String {
        MasterLog.normalize(Fixtures.headerLiteral + "\n" + Fixtures.shortcutLine("2026-10-26", payout: "8.00"))
    }

    private var accountLog: String {
        MasterLog.normalize(Fixtures.headerLiteral + "\n" + Fixtures.shortcutLine("2026-10-27", payout: "26.50"))
    }

    private func accountRows() throws -> [AccountStoreRow] {
        [row("settings", try settingsValue(accountSettings)),
         row("log", try logValue(accountLog))]
    }

    // MARK: - Preview

    func testPreviewShowsAccountAndPhoneItemsForEachKey() throws {
        let sets = AccountPull.preview(rows: try accountRows(),
                                       currentSettings: AppSettings(),
                                       currentLog: phoneLog)

        XCTAssertEqual(sets.map(\.key), ["settings", "log", "archive", "statements", "ca"])
        XCTAssertTrue(sets[0].isImported)
        XCTAssertEqual(sets[0].accountItems, 6)
        XCTAssertNotNil(sets[0].phoneItems)
        XCTAssertEqual(sets[0].updatedAt, "2026-11-02T10:00:00Z")
        XCTAssertNil(sets[0].note)

        // Log items are rows, not the `{csv, v}` wrapper.
        XCTAssertEqual(sets[1].accountItems, 1)
        XCTAssertEqual(sets[1].phoneItems, 1)

        // Keys this build does not import advertise no phone number.
        for set in sets[2...] {
            XCTAssertFalse(set.isImported)
            XCTAssertNil(set.phoneItems)
            XCTAssertEqual(set.accountItems, 0)
            XCTAssertEqual(set.note, "missing from the account")
        }
        XCTAssertTrue(sets[0].summary.contains("account 6"))
        XCTAssertTrue(sets[0].summary.contains("updated 2026-11-02T10:00:00Z"))
    }

    func testPreviewMarksKeysItDoesNotImportYet() throws {
        var rows = try accountRows()
        rows.append(row("archive", #"{"v":1,"r":[[1,2],[3,4]]}"#))

        let sets = AccountPull.preview(rows: rows, currentSettings: AppSettings(), currentLog: phoneLog)
        let archive = try XCTUnwrap(sets.first { $0.key == "archive" })

        XCTAssertEqual(archive.accountItems, 2)
        XCTAssertEqual(archive.note, "not imported yet")
        XCTAssertFalse(archive.isImported)
    }

    // MARK: - The import plan

    func testPlanReplacesTheLogAndAppliesAccountSettings() throws {
        let current = AppSettings(accept: 70, mpg: 22, emergency: 75)

        let plan = try AccountPull.plan(rows: try accountRows(),
                                        currentSettings: current,
                                        currentLog: phoneLog)

        XCTAssertEqual(plan.log, accountLog, "the account's log replaces the phone's")
        XCTAssertTrue(plan.logChanged)
        XCTAssertEqual(plan.accountRows, 1)
        XCTAssertEqual(plan.phoneRows, 1)
        XCTAssertEqual(plan.settings.accept, 89)
        XCTAssertEqual(plan.settings.gas, 5.75)
        XCTAssertEqual(plan.settings.zoneGas, ["Temecula": 6.4])
        XCTAssertEqual(plan.settings.emergency, 75, "a key the account does not carry keeps the phone's value")
        XCTAssertTrue(plan.settingsChanged)
    }

    func testPlanIsAPlanAndWritesNothing() throws {
        let store = LocalStore(directory: FileManager.default.temporaryDirectory
            .appendingPathComponent("hustler-pull-plan-\(UUID().uuidString)"))
        let before = LocalLibrary(store: store).log.text

        _ = try AccountPull.plan(rows: try accountRows(), currentSettings: AppSettings(),
                                 currentLog: before)

        XCTAssertEqual(LocalLibrary(store: store).log.text, before)
        XCTAssertFalse(FileManager.default.fileExists(atPath: store.url(.masterLog).path))
    }

    func testEmptyAccountLogNeverWipesThePhoneLog() throws {
        let rows = [row("settings", try settingsValue(["accept": 92])),
                    row("log", try logValue(""))]

        let plan = try AccountPull.plan(rows: rows, currentSettings: AppSettings(accept: 70),
                                        currentLog: phoneLog)

        XCTAssertEqual(plan.accountRows, 0)
        XCTAssertFalse(plan.logChanged)
        XCTAssertEqual(plan.log, MasterLog.normalize(phoneLog))
        XCTAssertEqual(plan.settings.accept, 92)
    }

    func testAccountThatMatchesThePhoneHasNothingToPull() throws {
        let settings = AppSettings()
        let settingsRow = String(decoding: try JSONEncoder().encode(settings), as: UTF8.self)
        let rows = [row("settings", settingsRow), row("log", try logValue(accountLog))]

        XCTAssertThrowsError(try AccountPull.plan(rows: rows, currentSettings: settings,
                                                  currentLog: accountLog)) { error in
            XCTAssertEqual(error as? AccountPullError, .nothingNew)
        }
    }

    // MARK: - Plain errors

    func testEmptyAccountIsAPlainError() throws {
        let rows = [row("archive", #"{"v":1,"r":[]}"#)]

        XCTAssertThrowsError(try AccountPull.plan(rows: rows, currentSettings: AppSettings(),
                                                  currentLog: phoneLog)) { error in
            XCTAssertEqual(error as? AccountPullError, .emptyAccount)
            XCTAssertEqual(error.localizedDescription, AccountPullError.emptyAccount.errorDescription)
        }
    }

    func testUnreadableLogValueIsRefused() throws {
        for value in [#"{"v":1}"#, #"{"csv":42}"#, "null", "[]"] {
            XCTAssertThrowsError(try AccountPull.plan(rows: [row("log", value)],
                                                      currentSettings: AppSettings(),
                                                      currentLog: phoneLog)) { error in
                XCTAssertEqual(error as? AccountPullError, .unreadableValue("log"),
                               "should refuse \(value)")
            }
        }
    }

    func testUnreadableSettingsValueIsRefused() throws {
        for value in ["42", #"["accept"]"#, "null"] {
            XCTAssertThrowsError(try AccountPull.plan(rows: [row("settings", value)],
                                                      currentSettings: AppSettings(),
                                                      currentLog: phoneLog)) { error in
                XCTAssertEqual(error as? AccountPullError, .unreadableValue("settings"),
                               "should refuse \(value)")
            }
        }
    }

    // MARK: - Reading the REST response

    func testRowParsingKeepsEveryKeyAndTimestamp() throws {
        let body = try JSONSerialization.data(withJSONObject: [
            ["k": "settings", "updated_at": "2026-11-02T10:00:00Z", "v": accountSettings],
            ["k": "log", "updated_at": NSNull(), "v": ["csv": accountLog, "v": 1]],
            ["k": "ca", "updated_at": NSNull(), "v": ["v": 1, "w": [:]]]
        ])

        let rows = try SupabaseStoreRows.parse(body)

        XCTAssertEqual(rows.map(\.key), ["settings", "log", "ca"])
        XCTAssertEqual(rows[0].updatedAt, "2026-11-02T10:00:00Z")
        XCTAssertNil(rows[1].updatedAt)
        XCTAssertEqual(AccountPull.count(for: "log", value: rows[1].value), 1)
    }

    func testMalformedResponseIsRefused() throws {
        for body in [#"{"k":"settings"}"#, #"[{"v":{}}]"#, "not json", "null"] {
            XCTAssertThrowsError(try SupabaseStoreRows.parse(Data(body.utf8))) { error in
                XCTAssertEqual(error as? SupabaseAccountError, .unexpectedResponse)
            }
        }
    }

    /// The summary and the pull read the response the same way.
    func testSummaryStillCountsFromTheSameRows() throws {
        let body = try JSONSerialization.data(withJSONObject: [
            ["k": "settings", "updated_at": "2026-11-02T10:00:00Z", "v": accountSettings],
            ["k": "log", "updated_at": NSNull(), "v": ["csv": accountLog, "v": 1]]
        ])

        let summary = try SupabaseStoreSummary.parse(body)

        XCTAssertEqual(summary.map(\.key), SupabaseStoreSummary.keys)
        XCTAssertEqual(summary.map(\.exists), [true, true, false, false, false])
        XCTAssertEqual(summary[0].itemCount, 6)
        XCTAssertEqual(summary[1].itemCount, 2, "the raw `v` object's key count")
    }

    // MARK: - Backup

    func testBackupIsAHandoffFileTheAppCanReadBack() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("hustler-backup-\(UUID().uuidString)")
        let settings = AppSettings(accept: 88, mpg: 21)
        let now = Date(timeIntervalSince1970: 1_800_000_000)

        let url = try AccountPullBackup.write(settings: settings, log: phoneLog,
                                              into: directory, now: now)

        XCTAssertEqual(url.lastPathComponent, "handoff-before-pull-20270115-080000.json")
        let file = try XCTUnwrap(HandoffFile.decode(try Data(contentsOf: url)))
        XCTAssertEqual(file.settings, settings)
        XCTAssertEqual(file.log, phoneLog)
        try? FileManager.default.removeItem(at: directory)
    }

    func testBackupNamesAreUniquePerSecond() {
        let now = Date(timeIntervalSince1970: 1_800_000_000)

        XCTAssertEqual(AccountPullBackup.fileName(now: now), AccountPullBackup.fileName(now: now))
        XCTAssertNotEqual(AccountPullBackup.fileName(now: now),
                          AccountPullBackup.fileName(now: now.addingTimeInterval(1)))
    }
}
