import XCTest
import HustlerCore
@testable import HustlerArchive

/// The Settings "Rebuild archive rows" rule. Archive rows come back from the
/// saved archive, every other row is kept, and a missing, unusable or unwritable
/// archive changes nothing.
final class ArchiveRebuildTests: XCTestCase {

    /// The archive stores instants; fixtures write them as UTC, which is what
    /// the web app's literal-`Z` conversion reads.
    private func utc(_ text: String) -> Date {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        return formatter.date(from: text)!
    }

    private func row(_ pickup: String?, _ delivered: String, items: Double = 2) -> ArchiveRow {
        ArchiveRow(
            createdAt: utc("2026-03-08 10:00:00"),
            pickupAt: pickup.map(utc),
            deliveredAt: utc(delivered),
            store: "Chipotle (Murrieta)",
            items: items
        )
    }

    /// The line `prepare` writes for this delivery, asserted in full.
    private let rebuiltLine = "| 2026-03-08 03:10 | 7.00 | 12.7 | 2 |  |  |  |  |  | "
        + "Accepted |  | Murrieta | 38 | archive |"

    /// A master log with two live shortcut rows and one stale archive row.
    private var log: String {
        MasterLog.normalize(
            Fixtures.firstShortcutRow + "\n" + Fixtures.secondShortcutRow + "\n"
                + Fixtures.archiveLine("2025-01-05 10:00", minutes: "30", payout: "9.00")
        )
    }

    private func makeStore() throws -> LocalStore {
        let directory = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent("hustler-rebuild-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: directory) }
        return LocalStore(directory: directory)
    }

    func testArchiveRowsAreReplacedAndShortcutRowsAreKept() throws {
        let outcome = try ArchiveImporter.rebuild(
            log: log,
            archive: [row("2026-03-08 10:10:00", "2026-03-08 10:40:00")]
        )

        XCTAssertTrue(outcome.log.contains(Fixtures.firstShortcutRow))
        XCTAssertTrue(outcome.log.contains(Fixtures.secondShortcutRow))
        XCTAssertFalse(outcome.log.contains("2025-01-05 10:00"), "the old archive row must be replaced")
        XCTAssertTrue(outcome.log.contains(rebuiltLine))
        XCTAssertEqual(MasterLog.rowCount(outcome.log), 3)
        XCTAssertEqual(outcome.archiveRows, 1)
        XCTAssertEqual(outcome.keptRows, 2)
        XCTAssertEqual(
            outcome.message,
            "Archive rows rebuilt. 1 archive row from the saved archive; 2 other rows kept."
        )
    }

    func testMissingArchiveThrowsAndNeverClearsTheLog() {
        let unchanged = log

        XCTAssertThrowsError(try ArchiveImporter.rebuild(log: unchanged, archive: [])) { error in
            XCTAssertEqual(error as? ArchiveRebuild.Failure, .missingArchive)
            XCTAssertEqual(error.localizedDescription, "No saved archive found. Your master log was not changed.")
        }
        XCTAssertThrowsError(try ArchiveRebuild.replacingArchiveRows(in: unchanged, with: [])) { error in
            XCTAssertEqual(error as? ArchiveRebuild.Failure, .missingArchive)
        }
        XCTAssertEqual(unchanged, log)
    }

    func testArchiveWithNoUsableRowThrowsInsteadOfDeletingRows() {
        // Delivery before its eight-minute window opens: `toLog` drops it.
        let backwards = row("2026-03-08 10:10:00", "2026-03-08 10:00:00")

        XCTAssertThrowsError(try ArchiveImporter.rebuild(log: log, archive: [backwards])) { error in
            XCTAssertEqual(error as? ArchiveRebuild.Failure, .unreadableArchive)
            XCTAssertEqual(
                error.localizedDescription,
                "The saved archive could not be read. Your master log was not changed."
            )
        }
    }

    func testABlockedMasterLogRefusesTheRebuiltLog() throws {
        let store = try makeStore()
        let corrupt = Data("not json".utf8)
        try corrupt.write(to: store.url(.masterLog))
        let library = LocalLibrary(store: store)

        let outcome = try ArchiveImporter.rebuild(
            log: library.log.text,
            archive: [row("2026-03-08 10:10:00", "2026-03-08 10:40:00")]
        )

        XCTAssertThrowsError(try library.saveLog(outcome.log)) { error in
            XCTAssertEqual(error as? LocalStore.Failure, .blocked(.masterLog))
        }
        XCTAssertEqual(try Data(contentsOf: store.url(.masterLog)), corrupt)
        XCTAssertEqual(library.log.rowCount, 0)
    }

    func testRebuildingTwiceGivesTheSameLog() throws {
        let archive = [
            row("2026-03-08 10:10:00", "2026-03-08 10:40:00"),
            row("2026-03-08 11:10:00", "2026-03-08 11:40:00", items: 3)
        ]
        let once = try ArchiveImporter.rebuild(log: log, archive: archive)
        let twice = try ArchiveImporter.rebuild(log: once.log, archive: archive)

        XCTAssertEqual(twice.log, once.log)
        XCTAssertEqual(twice.archiveRows, 2)
        XCTAssertEqual(twice.keptRows, 2)
        XCTAssertEqual(MasterLog.rowCount(twice.log), 4)
    }
}
