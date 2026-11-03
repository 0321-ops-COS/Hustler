import XCTest
@testable import HustlerCore

/// Settings storage against a real temporary directory: real bytes, real
/// decoder, nothing under Application Support touched.
final class AppSettingsTests: XCTestCase {

    private let fileManager = FileManager.default

    private func makeStore() throws -> LocalStore {
        let directory = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent("hustler-settings-\(UUID().uuidString)", isDirectory: true)
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: directory) }
        return LocalStore(directory: directory)
    }

    private func bytes(_ url: URL) throws -> Data { try Data(contentsOf: url) }

    func testFirstRunGivesTheWebDefaultsAndWritesNothing() throws {
        let store = try makeStore()
        let settings = SettingsStore(store: store)

        XCTAssertEqual(settings.settings, AppSettings())
        XCTAssertEqual(settings.status, .missing)
        XCTAssertFalse(settings.isUnavailable)
        XCTAssertFalse(fileManager.fileExists(atPath: store.url(.settings).path))
        XCTAssertEqual(store.url(.settings).lastPathComponent, "settings.json")

        // Spot-check `DEF`: a default of 0 would look plausible in a diff but
        // change every verdict.
        XCTAssertEqual(settings.settings.accept, 89)
        XCTAssertEqual(settings.settings.gas, 5.75)
        XCTAssertEqual(settings.settings.mpg, 17.5)
        XCTAssertEqual(settings.settings.emergency, 80)
        XCTAssertEqual(settings.settings.taxRate, 0.70)
        XCTAssertEqual(settings.settings.target, 85)
        XCTAssertEqual(settings.settings.caWage, 16.90)
        XCTAssertEqual(settings.settings.caPct, 120)
        XCTAssertEqual(settings.settings.caMile, 0.37)
        XCTAssertEqual(settings.settings.shortcutName, "DoorDash Offer Analyzer")
        XCTAssertEqual(settings.settings.pins, PagePins(log: false, data: true, earn: false, hist: false, sync: false))
    }

    func testRoundTripKeepsEveryKeyAndTheVersionField() throws {
        let store = try makeStore()
        var expected = AppSettings()
        expected.accept = 93
        expected.target = 80
        expected.taxRate = 0.67
        expected.caPct = 110
        expected.zoneGas = ["Temecula": 6.5, "Murrieta": 6.1]
        expected.accSet = true
        expected.shortcutLink = "https://www.icloud.com/shortcuts/example"
        expected.pins = PagePins(log: true, data: true, hist: true)

        try SettingsStore(store: store).save(expected)
        let relaunched = SettingsStore(store: LocalStore(directory: store.directory))
        XCTAssertEqual(relaunched.status, .loaded)
        XCTAssertEqual(relaunched.settings, expected)

        let json = try XCTUnwrap(
            JSONSerialization.jsonObject(with: try bytes(store.url(.settings))) as? [String: Any]
        )
        XCTAssertEqual(json["schemaVersion"] as? Int, AppSettings.currentVersion)
        XCTAssertEqual(json["accept"] as? Double, 93)
        XCTAssertNil(json["notASetting"])

        // The stored values reach the engines unchanged.
        var zoned = AppSettings()
        zoned.zoneGas = ["Temecula": 6.5]
        XCTAssertEqual(zoned.verdictSettings().gas, 5.75)
        let verdict = VerdictEngine.evaluate(
            VerdictOffer(payout: 12.50, miles: 4.2, items: 3, minutes: 25, zone: "Temecula"),
            settings: zoned.verdictSettings(), rate: 89
        )
        XCTAssertEqual(Money.format(verdict.net), "$10.44")
    }

    func testMissingAndUnknownKeysUseDefaultsNotZero() throws {
        let store = try makeStore()
        let partial = #"""
        {"schemaVersion":1,"accept":95,"gas":0,"target":0,
         "zoneGas":{"Temecula":6.5,"Broken":"nope"},
         "shortcutName":"Mine","notASetting":42,"pins":{"log":true}}
        """#
        try Data(partial.utf8).write(to: store.url(.settings))

        let settings = SettingsStore(store: store).settings
        XCTAssertEqual(settings.accept, 95, "a present value is kept")
        XCTAssertEqual(settings.target, 0, "a present zero is a real value, as in the web loader")
        XCTAssertEqual(settings.gas, 5.75, "the web loader refuses a non-positive gas price")
        XCTAssertEqual(settings.mpg, 17.5, "absent falls back to the default, not 0")
        XCTAssertEqual(settings.emergency, 80)
        XCTAssertEqual(settings.taxRate, 0.70)
        XCTAssertEqual(settings.caWage, 16.90)
        XCTAssertEqual(settings.zoneGas, ["Temecula": 6.5])
        XCTAssertEqual(settings.shortcutName, "Mine")
        XCTAssertEqual(settings.shortcutLink, "")
        XCTAssertFalse(settings.accSet)
        XCTAssertEqual(settings.pins, PagePins(log: true, data: true))
    }

    func testCorruptFileBlocksWritesAndIsNeverOverwritten() throws {
        let store = try makeStore()
        let corrupt = Data(#"{"schemaVersion":1,"accept":"#.utf8)
        try corrupt.write(to: store.url(.settings))

        let settings = SettingsStore(store: store)
        XCTAssertTrue(settings.isUnavailable)
        XCTAssertEqual(settings.settings, AppSettings(), "memory shows defaults, the file is untouched")

        XCTAssertThrowsError(try settings.save(AppSettings())) { error in
            XCTAssertEqual(error as? LocalStore.Failure, .blocked(.settings))
        }
        XCTAssertEqual(try bytes(store.url(.settings)), corrupt)

        let kept = try XCTUnwrap(try settings.recover())
        XCTAssertEqual(try bytes(kept), corrupt)
        XCTAssertEqual(kept.lastPathComponent, "settings.json.unreadable")
        XCTAssertEqual(settings.status, .missing)
        XCTAssertEqual(settings.settings, AppSettings())
        XCTAssertNoThrow(try settings.save(AppSettings()))
        XCTAssertEqual(try store.load(AppSettings.self, from: .settings), AppSettings())
    }

    func testNewerVersionIsRefusedAndBlocksWrites() throws {
        let store = try makeStore()
        let newer = Data(#"{"schemaVersion":2,"accept":50}"#.utf8)
        try newer.write(to: store.url(.settings))

        let settings = SettingsStore(store: store)
        XCTAssertEqual(
            settings.status,
            .unavailable(LocalStore.Failure.unsupportedVersion(.settings, 2).localizedDescription)
        )
        XCTAssertThrowsError(try settings.save(AppSettings())) { error in
            XCTAssertEqual(error as? LocalStore.Failure, .blocked(.settings))
        }
        XCTAssertEqual(try bytes(store.url(.settings)), newer)
    }
}
