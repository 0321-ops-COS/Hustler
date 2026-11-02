import XCTest
@testable import HustlerCore

/// Store tests go through `SettingsStore`/`LocalStore` on a temporary directory;
/// the view model tests pin the strings `renderCA()` shows.
final class CAEntriesTests: XCTestCase {
    private let weekKey = "2026-10-26", today = "2026-10-29"
    private let fileManager = FileManager.default

    /// Week of Monday 2026-10-26: two accepted rows (30 pay, 1.5 h, 15 mi) and one declined row.
    private var rows: [LogRow] {
        [
            LogRow(date: "2026-10-27", payout: "20.00", miles: "10", choice: "Accepted", minutes: "60"),
            LogRow(date: "2026-10-28", payout: "10.00", miles: "5", choice: "Accepted", minutes: "30"),
            LogRow(date: "2026-10-29", payout: "99.00", miles: "20", choice: "Declined", minutes: "60")
        ]
    }

    private func settings(_ entries: [String: CAWeekEntry] = [:]) -> AppSettings {
        var settings = AppSettings(); settings.caEntries = entries; return settings
    }

    private func model(_ logRows: [LogRow] = [], entries: [String: CAWeekEntry] = [:],
                       extra: Int? = nil) -> CAGuaranteeViewModel {
        CAGuaranteeViewModel.make(rows: logRows, settings: settings(entries), today: today, extraHours: extra)
    }

    private func makeStore() throws -> LocalStore {
        let directory = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent("hustler-ca-\(UUID().uuidString)", isDirectory: true)
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: directory) }
        return LocalStore(directory: directory)
    }

    func testEntriesSaveReloadAndInputParsing() throws {
        let store = try makeStore()
        try SettingsStore(store: store).save(settings([weekKey: CAWeekEntry(pay: 120.5, hours: 4, miles: 30)]))
        let relaunched = SettingsStore(store: LocalStore(directory: store.directory))
        XCTAssertEqual(relaunched.settings.caEntries[weekKey], CAWeekEntry(pay: 120.5, hours: 4, miles: 30))
        XCTAssertEqual(CAEntryInput(pay: " $1,234.56 ", hours: "4", miles: "3.5mi").entry,
                       CAWeekEntry(pay: 1234.56, hours: 4, miles: 3.5))
        XCTAssertEqual(CAEntryInput(pay: "", hours: "abc", miles: ".").entry, CAWeekEntry(pay: 0, hours: 0, miles: 0))
    }
    func testUnreadableStoreBlocksWritesAndDropsOnlyBadWeeks() throws {
        let store = try makeStore()
        let corrupt = Data(#"{"schemaVersion":1"#.utf8)
        try corrupt.write(to: store.url(.settings))
        let blocked = SettingsStore(store: store)
        XCTAssertTrue(blocked.isUnavailable)
        XCTAssertThrowsError(try blocked.save(settings([weekKey: CAWeekEntry(pay: 10)]))) { error in
            XCTAssertEqual(error as? LocalStore.Failure, .blocked(.settings))
        }
        XCTAssertEqual(try Data(contentsOf: store.url(.settings)), corrupt)

        let lenient = try makeStore()
        let json = #"{"schemaVersion":1,"caEntries":{"2026-10-26":{"pay":30,"hours":2},"2026-10-19":{"pay":"oops"}}}"#
        try Data(json.utf8).write(to: lenient.url(.settings))
        let loaded = SettingsStore(store: lenient)
        XCTAssertEqual(loaded.settings.caEntries[weekKey], CAWeekEntry(pay: 30, hours: 2))
        XCTAssertNil(loaded.settings.caEntries["2026-10-19"])
    }

    func testNotEnoughDataAndTheNoPaceBranch() {
        let empty = model()
        XCTAssertTrue(empty.isNotEnoughData)
        XCTAssertEqual([empty.weekStart, empty.weekEnd, "\(empty.daysLeft)"], ["Oct 26", "Nov 1", "3"])
        XCTAssertEqual(empty.headerHint, "Pay week Oct 26 to Nov 1 (Monday to Sunday). 3 days left after today.")
        XCTAssertTrue(empty.tableRows.isEmpty)
        XCTAssertEqual(empty.maxExtraHours, 0)
        XCTAssertNil(empty.pace)
        XCTAssertEqual(CAGuaranteeViewModel.notEnoughDataTitle, "Not enough data")

        let entered = model(entries: [weekKey: CAWeekEntry(pay: 50, hours: 2, miles: 8)], extra: 5)
        XCTAssertNil(entered.pace)
        XCTAssertEqual([entered.extraHours, entered.maxExtraHours], [0, 0])
        XCTAssertEqual(entered.tableRows.map(\.added), ["--", "--", "--", "", "", ""])
        XCTAssertEqual(entered.tableRows.map(\.total), ["2h 00m", "8", "$50.00", "$43.52", "$0.00", "$50.00"])
        XCTAssertEqual(entered.paceHint, CAGuaranteeViewModel.noPaceHint)
    }
    func testThisWeekTableAndExtraHours() {
        let base = model(rows)
        XCTAssertFalse(base.isNotEnoughData)
        XCTAssertEqual([base.maxExtraHours, base.extraHours], [48, 0])
        XCTAssertEqual(base.thisWeek.merged,
                       CAPayGuarantee.Merged(pay: 30, hours: 1.5, miles: 15, acceptedOffers: 2,
                                             payFromLog: true, hoursFromLog: true, milesFromLog: true))
        XCTAssertEqual(base.tableRows.map(\.label),
                       ["Active time", "Miles", "DoorDash pay", "Guarantee level", "Adjustment", "Pay + adjustment"])
        XCTAssertEqual(base.tableRows.map(\.soFar), ["1h 30m", "15", "$30.00", "$35.97", "$5.97", "$35.97"])
        XCTAssertEqual(base.tableRows.map(\.added), ["+0h 00m", "+0", "+$0.00", "", "", ""])
        XCTAssertEqual(base.tableRows.map(\.total), ["1h 30m", "15", "$30.00", "$35.97", "$5.97", "$35.97"])
        XCTAssertEqual(base.offersHint, "So far: 2 accepted offers this week; active time and miles from your log, time is estimated.")
        XCTAssertEqual(base.thisWeek.estimate.milesSource, .fromLog)
        XCTAssertEqual(base.equation, "($20.28 × 1.5 h) + ($0.37 × 15 mi) = $35.97<br>"
                       + "$35.97 − $30.00 pay = $5.97 adjustment (never below $0)")

        let projected = model(rows, extra: 10)
        XCTAssertEqual([projected.extraHours, projected.maxExtraHours], [10, 48])
        XCTAssertEqual(projected.sliderLabel, "+10 h")
        XCTAssertEqual(projected.tableRows.map(\.added), ["+10h 00m", "+100", "+$200.00", "", "", ""])
        XCTAssertEqual(projected.tableRows.map(\.total), ["11h 30m", "115", "$230.00", "$275.77", "$45.77", "$275.77"])
        XCTAssertEqual(projected.paceHint, "Rest of the week: move the slider to try different extra active hours. "
                       + "Pace used: $20.00 pay and 10.0 miles per active hour (1 week of your log). "
                       + "The slider tops out at 48 h: 84 h a week and 12 h a day.")
        XCTAssertEqual(model(rows, extra: 999).extraHours, 48)
    }
    func testEnteredFiguresBeatTheLogAndChangeTheWording() {
        let entered = model(rows, entries: [weekKey: CAWeekEntry(pay: 100, hours: 5, miles: 40)])
        XCTAssertEqual(entered.thisWeek.merged.pay, 100)
        XCTAssertFalse(entered.thisWeek.merged.payFromLog)
        XCTAssertFalse(entered.thisWeek.merged.hoursFromLog)
        XCTAssertEqual(entered.thisWeek.estimate.milesSource, .entered)
        XCTAssertEqual(entered.thisWeek.estimate.guarantee, 116.2, accuracy: 1e-9)
        XCTAssertEqual(entered.offersHint, "So far: 2 accepted offers this week; active time and miles entered by you.")
        XCTAssertEqual([entered.tableRows[3].soFar, entered.tableRows[4].soFar], ["$116.20", "$16.20"])
    }
    func testRecentWeeksAreThePaceWindowWithAutoAndEnteredFigures() {
        let previous = "2026-10-19"
        let history = [
            LogRow(date: "2026-10-20", payout: "100", miles: "50", choice: "Accepted", minutes: "120"),
            LogRow(date: "2026-10-27", payout: "20", miles: "10", choice: "Accepted", minutes: "60")
        ]
        let model = CAGuaranteeViewModel.make(
            rows: history, settings: settings([previous: CAWeekEntry(hours: 3)]), today: "2026-10-28")
        XCTAssertEqual(model.recentWeeks.map(\.weekKey), [previous, weekKey])
        XCTAssertEqual(model.recentWeeks[0].merged.pay, 100)
        XCTAssertTrue(model.recentWeeks[0].merged.payFromLog)
        XCTAssertEqual(model.recentWeeks[0].merged.hours, 3)
        XCTAssertFalse(model.recentWeeks[0].merged.hoursFromLog)
        XCTAssertEqual(model.recentWeeks.last, model.thisWeek)
    }
}
