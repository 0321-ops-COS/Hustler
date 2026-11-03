import XCTest
@testable import HustlerCore

/// The History page is `renderArch()` ported: same tiles, same table order, same
/// wording. Every fixture is invented; no real delivery data is used.
final class HistoryTests: XCTestCase {

    private func date(_ text: String) -> Date {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyy-MM-dd HH:mm"
        return formatter.date(from: text)!
    }

    private func row(_ created: String, _ pickup: String, _ delivered: String, _ store: String, _ items: Double) -> ArchiveRow {
        ArchiveRow(createdAt: date(created), pickupAt: date(pickup), deliveredAt: date(delivered), store: store, items: items)
    }

    private func fixture() -> [ArchiveRow] {
        [
            row("2026-10-05 17:00", "2026-10-05 18:00", "2026-10-05 18:30", "Chipotle (Murrieta)", 2),
            row("2026-10-06 17:00", "2026-10-06 18:00", "2026-10-06 18:45", "Sun City - Main", 1),
            row("2026-10-20 17:00", "2026-10-20 18:00", "2026-10-20 18:20", "Chipotle (Murrieta)", 3),
            row("2026-11-02 17:00", "2026-11-02 18:00", "2026-11-02 18:10", "Pizza #2", 2),
            row("2026-11-02 16:00", "2026-11-02 18:00", "2026-11-02 18:00", "Pizza #2", 0)
        ]
    }

    private func shortcut(_ day: String, items: String, choice: String) -> LogRow {
        LogRow(date: day, items: items, choice: choice, minutes: "10", source: "")
    }

    private func calendar() -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        return calendar
    }

    func testPageMatchesRenderArchWithDuplicatesHidden() {
        let archive = fixture()
        let log = [
            shortcut("2026-10-06 11:00", items: "1", choice: "Accepted"), // hides 6 Oct
            shortcut("2026-10-07 11:00", items: "2", choice: "Declined"), // covers nothing
            shortcut("2026-11-02 10:00", items: "1", choice: "Accepted")  // hides the zero-item row
        ]

        let page = HistoryViewModel.build(archive: archive, logRows: log, calendar: calendar())

        XCTAssertEqual(page.tiles.map(\.label), ["Lifetime deliveries", "First order", "Avg pickup to drop", "Busiest hour"])
        XCTAssertEqual(
            [HistoryCopy.monthTitle, HistoryCopy.hourTitle, HistoryCopy.dayTitle, HistoryCopy.storeTitle],
            ["By month", "By hour (your device time)", "By day of week", "Top stores"]
        )
        XCTAssertEqual(page.tiles.map(\.value), ["3", "Oct 2026", "20 min", "6pm"])

        XCTAssertEqual(page.months.map(\.key), ["2026-11", "2026-10"])
        XCTAssertEqual(page.months.map(\.deliveries), [1, 2])
        XCTAssertEqual(page.months.map(\.averagePickupToDrop), ["10 min", "25 min"])
        XCTAssertEqual(page.hours.map(\.label), ["6pm"])
        XCTAssertEqual(page.hours.map(\.deliveries), [3])
        XCTAssertEqual(page.hours.map(\.fractionOfMax), [1])
        XCTAssertEqual(page.weekdays.map(\.label), ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"])
        XCTAssertEqual(page.weekdays.map(\.deliveries), [0, 2, 1, 0, 0, 0, 0])
        XCTAssertEqual(page.weekdays.map(\.fractionOfMax), [0, 1, 0.5, 0, 0, 0, 0])

        XCTAssertEqual(page.stores.map(\.name), ["Chipotle", "Pizza"])
        XCTAssertEqual(page.stores.map(\.deliveries), [2, 1])

        XCTAssertEqual(archive, fixture(), "the duplicate rule hides rows, it never deletes them")
        XCTAssertTrue(HistoryViewModel.build(archive: []).isEmpty, "no archive draws nothing")
    }

    /// The screen's empty state: when the duplicate rule covers every archive
    /// row, there is nothing to draw and `isEmpty` is what the view checks.
    func testEveryRowHiddenDrawsNothingButStillCountsDuplicates() {
        let archive = [row("2026-10-05 17:00", "2026-10-05 18:00", "2026-10-05 18:30", "Chipotle", 2)]
        let log = [shortcut("2026-10-05 11:00", items: "2", choice: "Accepted")]

        let page = HistoryViewModel.build(archive: archive, logRows: log, calendar: calendar())

        XCTAssertTrue(page.isEmpty)
        XCTAssertEqual(page.duplicatesHidden, 1)
        XCTAssertTrue(page.tiles.isEmpty)
        XCTAssertTrue(page.months.isEmpty)
        XCTAssertTrue(page.hours.isEmpty)
        XCTAssertTrue(page.weekdays.isEmpty)
        XCTAssertTrue(page.stores.isEmpty)
    }

    func testTopStoresKeepFirstSeenOrderOnATieAndStopAtTen() {
        let names = ["B", "A", "C", "D", "E", "F", "G", "H", "I", "J", "K"]
        let rows = names.map { row("2026-10-05 17:00", "2026-10-05 18:00", "2026-10-05 18:10", $0, 1) }

        let page = HistoryViewModel.build(archive: rows)

        XCTAssertEqual(page.stores.map(\.name), Array(names.prefix(10)))
        XCTAssertEqual(page.stores.map(\.deliveries), Array(repeating: 1, count: 10))
    }

    func testArchiveStoreRoundTripsAppendsAndClears() throws {
        let directory = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent("hustler-history-\(UUID().uuidString)", isDirectory: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: directory) }
        let library = LocalLibrary(store: LocalStore(directory: directory))
        let all = fixture()

        try library.saveArchive(Array(all.prefix(2)))
        try library.appendArchive(all)
        XCTAssertEqual(library.archive, all)

        // A relaunch reads the same rows back from disk.
        let relaunched = LocalLibrary(store: LocalStore(directory: directory))
        XCTAssertEqual(relaunched.archive, all)

        try relaunched.removeArchiveRows()
        XCTAssertTrue(relaunched.archive.isEmpty)
        XCTAssertTrue(LocalLibrary(store: LocalStore(directory: directory)).archive.isEmpty)
    }
}
