import XCTest
@testable import HustlerCore

final class SettingsEditingTests: XCTestCase {

    func testTextUsesTheWebNumParsing() {
        var edit = SettingsEdit()
        XCTAssertTrue(edit.apply("$6.50", to: .gas))
        XCTAssertEqual(edit.settings.gas, 6.5)
        XCTAssertTrue(edit.apply(" 7.25 ", to: .gas))
        XCTAssertEqual(edit.settings.gas, 7.25)
        XCTAssertTrue(edit.apply("0.185abc", to: .wear))
        XCTAssertEqual(edit.settings.wear, 0.185, "parseFloat keeps the leading number")
        XCTAssertTrue(edit.apply("$5,75", to: .gas))
        XCTAssertEqual(edit.settings.gas, 575, "num() strips commas, as the web app does")
        XCTAssertTrue(edit.messages.isEmpty)
    }

    func testRejectedInputKeepsTheOldValueAndExplains() {
        var edit = SettingsEdit()
        XCTAssertFalse(edit.apply("", to: .gas))
        XCTAssertFalse(edit.apply("abc", to: .gas))
        XCTAssertFalse(edit.apply("0", to: .gas), "the web loader refuses a zero gas price")
        XCTAssertEqual(edit.settings.gas, 5.75)
        XCTAssertEqual(edit.messages[.gas], "Enter a number above zero. Kept 5.75.")

        XCTAssertFalse(edit.apply("nope", to: .taxRate))
        XCTAssertEqual(edit.settings.taxRate, 0.70)
        XCTAssertEqual(edit.messages[.taxRate], "Enter a number. Kept 0.7.")

        XCTAssertTrue(edit.apply("6", to: .gas))
        XCTAssertNil(edit.messages[.gas], "a good value clears the message")
    }

    func testEditSavesAndReloadsThroughATemporaryStore() throws {
        let directory = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent("hustler-settings-edit-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: directory) }
        let store = LocalStore(directory: directory)

        var edit = SettingsEdit(SettingsStore(store: store).settings)
        XCTAssertTrue(edit.apply("7.10", to: .gas))
        XCTAssertTrue(edit.apply("0.65", to: .taxRate))
        XCTAssertTrue(edit.apply("17.5", to: .caWage))
        edit.setPinned(.log, true)
        edit.setPinned(.data, false)
        try SettingsStore(store: store).save(edit.settings)

        let reloaded = SettingsEdit(SettingsStore(store: LocalStore(directory: directory)).settings)
        XCTAssertEqual(reloaded.settings.gas, 7.1)
        XCTAssertEqual(reloaded.settings.taxRate, 0.65)
        XCTAssertEqual(reloaded.settings.caWage, 17.5)
        XCTAssertTrue(reloaded.isPinned(.log))
        XCTAssertFalse(reloaded.isPinned(.data))
    }

    func testEmptyNamesHaveNoURLAndPagesMatchPGS() {
        var edit = SettingsEdit()
        XCTAssertNotNil(edit.runShortcutURL)
        edit.setShortcutName("   ")
        XCTAssertNil(edit.runShortcutURL)
        edit.setShortcutName("DoorDash Offer Analyzer")
        XCTAssertEqual(
            edit.runShortcutURL?.absoluteString,
            "shortcuts://run-shortcut?name=DoorDash%20Offer%20Analyzer"
        )
        edit.setShortcutName("A&B")
        XCTAssertEqual(edit.runShortcutURL?.absoluteString, "shortcuts://run-shortcut?name=A%26B")

        XCTAssertNil(edit.shortcutLinkURL)
        edit.setShortcutLink("https://www.icloud.com/shortcuts/example")
        XCTAssertNotNil(edit.shortcutLinkURL)
        edit.setShortcutLink("not a link")
        XCTAssertNil(edit.shortcutLinkURL)

        XCTAssertEqual(AppPage.all.map(\.title), ["Master file", "Data", "Earnings", "History", "Handoff"])
        var pins = PagePins()
        XCTAssertTrue(AppPage.data.isPinned(in: pins), "Data is on by default")
        AppPage.data.setPinned(false, in: &pins)
        AppPage.hist.setPinned(true, in: &pins)
        XCTAssertEqual(pins, PagePins(log: false, data: false, earn: false, hist: true, sync: false))
    }
}
