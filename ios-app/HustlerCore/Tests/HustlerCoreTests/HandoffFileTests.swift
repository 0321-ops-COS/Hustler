import XCTest
@testable import HustlerCore
/// Invented fixtures only: one synthetic row, no real earnings or personal data.
final class HandoffFileTests: XCTestCase {
    private let webLog = Fixtures.headerLiteral + "\n" + Fixtures.shortcutLine("2026-10-27", payout: "26.50")

    /// Written the way `#exp` writes it, with a `brief` and a `settings.monthly`
    /// map this app does not import.
    private var webFileText: String {
        let csv = webLog.replacingOccurrences(of: "\n", with: "\\n")
        return """
        {"app":"Hustle HQ","version":1,
         "settings":{"accept":92,"estPay":8.25,"gas":6.05,"zoneGas":{"Temecula":6.4},
                     "accSet":true,"pins":{"log":true,"data":false},
                     "monthly":{"2026-10":[1234.56,321.4]},"notASetting":42},
         "csv":"\(csv)","brief":"HUSTLE HQ HANDOFF"}
        """
    }
    func testExportUsesTheWebShapeAndRoundTrips() throws {
        var settings = AppSettings(accept: 91, mpg: 21, gas: 6.05)
        settings.zoneGas = ["Temecula": 6.4]
        settings.accSet = true
        settings.pins = PagePins(log: true, data: false)
        let data = try HandoffFile.export(settings: settings, log: webLog)
        let root = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertEqual(root["app"] as? String, "Hustle HQ")
        XCTAssertEqual(root["version"] as? Int, 1)
        XCTAssertEqual(root["csv"] as? String, webLog)
        // The keys `draft()` reads (`DEF`) are the ones that must be there.
        let json = try XCTUnwrap(root["settings"] as? [String: Any])
        for key in ["accept", "estPay", "estMph", "mpg", "wear", "gas", "rampTop", "floorHour",
                    "bigItems", "taxRate", "caWage", "zoneGas", "accSet", "pins"] {
            XCTAssertNotNil(json[key], "missing settings key \(key)")
        }
        XCTAssertEqual(json["accept"] as? Double, 91)
        let decoded = try XCTUnwrap(HandoffFile.decode(data))
        XCTAssertEqual(decoded.settings, settings)
        XCTAssertEqual(decoded.log, webLog)
    }
    func testWebFileDecodesItsKeysAndDefaultsTheRest() throws {
        let file = try XCTUnwrap(HandoffFile.decode(webFileText))
        XCTAssertEqual(file.settings.accept, 92)
        XCTAssertEqual(file.settings.estPay, 8.25)
        XCTAssertEqual(file.settings.gas, 6.05)
        XCTAssertEqual(file.settings.zoneGas, ["Temecula": 6.4])
        XCTAssertTrue(file.settings.accSet)
        XCTAssertEqual(file.settings.pins, PagePins(log: true, data: false))
        XCTAssertEqual(file.settings.mpg, 17.5, "a missing key is the default, not zero")
        XCTAssertEqual(file.log, webLog)
        // `monthly` belongs to the statement store here, and a key with no setting
        // behind it changes nothing.
        let unknownOnly = try XCTUnwrap(HandoffFile.decode(
            #"{"settings":{"monthly":{"2026-10":[1,2]},"notASetting":42}}"#
        ))
        XCTAssertEqual(unknownOnly.mergedSettings(into: AppSettings(accept: 70)), AppSettings(accept: 70))
    }
    func testImportKeepsSettingsTheFileDoesNotCarry() throws {
        let file = try XCTUnwrap(HandoffFile.decode(webFileText))
        let current = AppSettings(accept: 70, mpg: 22, gas: 6.10, emergency: 75)
        let plan = file.importPlan(currentSettings: current, currentLog: Fixtures.headerOnly)
        XCTAssertEqual(plan.settings.accept, 92, "a key in the file is applied")
        XCTAssertEqual(plan.settings.gas, 6.05)
        XCTAssertEqual(plan.settings.zoneGas, ["Temecula": 6.4])
        XCTAssertEqual(plan.settings.mpg, 22, "a key absent from the file keeps the device value")
        XCTAssertEqual(plan.settings.emergency, 75)
    }
    func testImportAddsRowsWithoutReplacingTheLog() throws {
        let existing = Fixtures.headerLiteral + "\n" + Fixtures.shortcutLine("2026-10-26", payout: "8.00")
        let file = try XCTUnwrap(HandoffFile.decode(webFileText))
        let plan = file.importPlan(currentSettings: AppSettings(), currentLog: existing)
        XCTAssertEqual(plan.rowsAdded, 1)
        XCTAssertEqual(MasterLog.rowCount(plan.log), 2)
        XCTAssertTrue(plan.log.contains("2026-10-26"), "the device's own row is kept")
        XCTAssertTrue(plan.log.contains("2026-10-27"))
        // Importing the same file again adds nothing and changes nothing.
        let again = file.importPlan(currentSettings: plan.settings, currentLog: plan.log)
        XCTAssertEqual(again.rowsAdded, 0)
        XCTAssertEqual(again.log, plan.log)
    }
    func testGarbageAndEmptyFilesAreRefused() {
        for text in ["", "   ", "not json", #"{"settings":"#, "[]", "42",
                     #"{"app":"Hustle HQ"}"#, #"{"settings":"nope","csv":5}"#] {
            XCTAssertNil(HandoffFile.decode(text), "should refuse \(text.debugDescription)")
        }
        XCTAssertNil(HandoffFile.decode(Data()))
    }
    func testUnreadableSettingsDoNotOverwriteTheStoredOnes() throws {
        let row = Fixtures.shortcutLine("2026-10-27", payout: "26.50")
        let current = AppSettings(accept: 70, mpg: 22)
        // A newer settings version is ignored; the log still imports.
        let newer = try XCTUnwrap(HandoffFile.decode(
            #"{"settings":{"schemaVersion":2,"accept":10},"csv":"\#(row)"}"#
        ))
        XCTAssertTrue(newer.settingsKeys.isEmpty)
        let plan = newer.importPlan(currentSettings: current, currentLog: Fixtures.headerOnly)
        XCTAssertEqual(plan.settings, current, "unreadable settings must not reset the device's")
        XCTAssertEqual(plan.rowsAdded, 1)
        // Same for a `settings` value that is not an object.
        let wrongType = try XCTUnwrap(HandoffFile.decode(#"{"settings":[1,2],"csv":"\#(row)"}"#))
        XCTAssertEqual(wrongType.importPlan(currentSettings: current, currentLog: "").settings, current)
    }
}
