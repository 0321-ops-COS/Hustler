import XCTest
import ZIPFoundation
import HustlerCore
@testable import HustlerArchive

/// Archive import tests against real ZIP bytes and real CSV text.
///
/// Every fixture is generated during the test: synthetic delivery rows only, no
/// real DoorDash export, no personal data. The expected pipe rows are written out
/// in full so a change in conversion, rounding or time-zone handling shows up as
/// a diff rather than as a loose assertion.
final class ArchiveImportTests: XCTestCase {

    private let fileManager = FileManager.default

    private static let header = "ORDER_CREATED_TIME,ACTUAL_PICKUP_TIME,ACTUAL_DELIVERY_TIME,"
        + "STORE_NAME,TOTAL_ITEM_COUNT,ORDER_STATUS"

    // MARK: - Fixtures

    private func csv(_ rows: [String], header: String = ArchiveImportTests.header) -> String {
        ([header] + rows).joined(separator: "\n") + "\n"
    }

    /// A real ZIP, built by ZIPFoundation into a temporary directory.
    private func zip(
        _ files: [(path: String, text: String)],
        compression: CompressionMethod = .deflate
    ) throws -> Data {
        let directory = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent("hustler-zip-\(UUID().uuidString)", isDirectory: true)
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: directory) }

        let url = directory.appendingPathComponent("archive.zip")
        let archive = try Archive(url: url, accessMode: .create)
        for file in files {
            let payload = Data(file.text.utf8)
            try archive.addEntry(
                with: file.path,
                type: .file,
                uncompressedSize: Int64(payload.count),
                compressionMethod: compression
            ) { position, size in
                let start = Int(position)
                let end = min(start + size, payload.count)
                return payload.subdata(in: start..<end)
            }
        }
        return try Data(contentsOf: url)
    }

    private func archive(_ rows: [String], entry: String = "delivery_information.csv") throws -> Data {
        try zip([(entry, csv(rows))])
    }

    private func importArchive(_ data: Data, existing: String = "") throws -> ArchiveImportResult {
        try ArchiveImporter.prepare(archiveData: data, existingLog: existing)
    }

    private func makeStore() throws -> LocalStore {
        let directory = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent("hustler-archive-store-\(UUID().uuidString)", isDirectory: true)
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        addTeardownBlock {
            try? FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: directory.path)
            try? FileManager.default.removeItem(at: directory)
        }
        return LocalStore(directory: directory)
    }

    private func makeDirectoryUnwritable(_ directory: URL) throws {
        try fileManager.setAttributes([.posixPermissions: 0o500], ofItemAtPath: directory.path)
        let probe = directory.appendingPathComponent("permission-probe")
        defer { try? fileManager.removeItem(at: probe) }
        if (try? Data("x".utf8).write(to: probe)) != nil {
            try? fileManager.setAttributes([.posixPermissions: 0o700], ofItemAtPath: directory.path)
            throw XCTSkip("directory permissions are not enforced here (running as root?)")
        }
    }

    // MARK: - Field mapping and exact output

    func testConversionProducesTheExpectedPipeRow() throws {
        let data = try archive([
            "2026-03-08 10:00:00,2026-03-08 10:10:00,2026-03-08 10:40:00,Chipotle (Murrieta),2,Delivered"
        ])

        let result = try importArchive(data)

        XCTAssertEqual(
            result.mergedLog,
            MasterLog.header + "\n"
                + "| 2026-03-08 03:10 | 7.00 | 12.7 | 2 |  |  |  |  |  | Accepted |  | Murrieta | 38 | archive |"
        )
        XCTAssertEqual(result.counts.rowsInspected, 1)
        XCTAssertEqual(result.counts.validRows, 1)
        XCTAssertEqual(result.counts.newlyAdded, 1)
        XCTAssertEqual(result.counts.alreadyPresent, 0)
        XCTAssertEqual(result.counts.retainedRows, 0)
        XCTAssertEqual(MasterLog.rowCount(result.mergedLog), 1)
    }

    func testEstimateParametersAreInjectable() throws {
        let data = try archive([
            "2026-03-08 10:00:00,2026-03-08 10:10:00,2026-03-08 10:40:00,Chipotle (Murrieta),2,Delivered"
        ])

        let result = try ArchiveImporter.prepare(
            archiveData: data,
            existingLog: "",
            estimatedPay: 12.5,
            estimatedMilesPerHour: 18
        )

        // 38 minutes at 18 mph = 11.4 miles; pay comes straight from the setting.
        XCTAssertTrue(result.mergedLog.contains("| 12.50 | 11.4 | 2 |"))
    }

    func testMissingItemCountBecomesOneItem() throws {
        let data = try archive([
            "2026-03-08 10:00:00,2026-03-08 10:10:00,2026-03-08 10:40:00,Chipotle (Murrieta),,Delivered"
        ])

        let result = try importArchive(data)

        XCTAssertTrue(result.mergedLog.contains("| 12.7 | 1 |"))
    }

    func testZoneIsTheFirstCityMatchedInTheWebAppsOrder() throws {
        let data = try archive([
            // Both Menifee and Sun City appear; Menifee comes first in CITIES.
            "2026-03-08 10:00:00,2026-03-08 10:10:00,2026-03-08 10:40:00,Sun City Menifee,2,Delivered",
            "2026-03-08 11:00:00,2026-03-08 11:10:00,2026-03-08 11:40:00,Unknown Store,2,Delivered"
        ])

        let result = try importArchive(data)

        XCTAssertEqual(MasterLogParser.parse(result.mergedLog).map(\.zone), ["Menifee", ""])
    }

    func testEntryNameIsMatchedCaseInsensitivelyIncludingNestedPaths() throws {
        let data = try zip([
            ("data_archive/notes.csv", "a,b\n1,2\n"),
            ("data_archive/DELIVERY_INFORMATION.CSV", csv([
                "2026-03-08 10:00:00,2026-03-08 10:10:00,2026-03-08 10:40:00,Chipotle (Murrieta),2,Delivered"
            ]))
        ])

        let result = try importArchive(data)
        XCTAssertEqual(result.counts.newlyAdded, 1)
    }

    func testStoredCompressionAlsoReads() throws {
        let data = try zip(
            [("delivery_information.csv", csv([
                "2026-03-08 10:00:00,2026-03-08 10:10:00,2026-03-08 10:40:00,Chipotle (Murrieta),2,Delivered"
            ]))],
            compression: .none
        )

        let result = try importArchive(data)
        XCTAssertEqual(result.counts.newlyAdded, 1)
    }

    func testUTF8BOMDoesNotBreakTheHeader() throws {
        let data = try zip([("delivery_information.csv", "\u{FEFF}" + csv([
            "2026-03-08 10:00:00,2026-03-08 10:10:00,2026-03-08 10:40:00,Chipotle (Murrieta),2,Delivered"
        ]))])

        let result = try importArchive(data)
        XCTAssertEqual(result.counts.newlyAdded, 1)
    }

    // MARK: - Failure cases

    func testMissingDeliveryFileIsReported() throws {
        let data = try zip([("something_else.csv", "a,b\n1,2\n")])

        XCTAssertThrowsError(try importArchive(data)) { error in
            XCTAssertEqual(error as? ArchiveImportError, .deliveryFileMissing)
        }
    }

    func testMalformedZipIsReported() throws {
        let data = Data("this is not a zip file at all".utf8)

        XCTAssertThrowsError(try importArchive(data)) { error in
            guard let archiveError = error as? ArchiveImportError else {
                return XCTFail("expected an ArchiveImportError, got \(error)")
            }
            guard case .unreadableArchive = archiveError else {
                return XCTFail("expected unreadableArchive, got \(archiveError)")
            }
        }
    }

    func testMissingRequiredColumnsIsReported() throws {
        let header = "ORDER_CREATED_TIME,ACTUAL_PICKUP_TIME,STORE_NAME,TOTAL_ITEM_COUNT"
        let data = try zip([("delivery_information.csv", csv([
            "2026-03-08 10:00:00,2026-03-08 10:10:00,Chipotle,2"
        ], header: header))])

        XCTAssertThrowsError(try importArchive(data)) { error in
            XCTAssertEqual(
                error as? ArchiveImportError,
                .notADeliveryFile(missing: ["actual_delivery_time"])
            )
        }
    }

    func testMalformedCSVRowIsRejectedNotInvented() throws {
        let data = try archive([
            "2026-03-08 10:00:00",
            "2026-03-08 10:00:00,2026-03-08 10:10:00,2026-03-08 10:40:00,Chipotle (Murrieta),2,Delivered"
        ])

        let result = try importArchive(data)

        // The short row has no delivery time, so it is counted, never emitted.
        XCTAssertEqual(result.counts.rowsInspected, 2)
        XCTAssertEqual(result.counts.missingDeliverySkipped, 1)
        XCTAssertEqual(result.counts.validRows, 1)
        XCTAssertEqual(result.mergedLog.components(separatedBy: "\n").filter { $0.hasPrefix("| 2026") }.count, 1)
    }

    func testQuotedCommasInStoreNameSurvive() throws {
        let data = try archive([
            "2026-03-08 10:00:00,2026-03-08 10:10:00,2026-03-08 10:40:00,\"Chipotle, Murrieta\",2,Delivered"
        ])

        let result = try importArchive(data)
        XCTAssertTrue(result.mergedLog.contains("| Murrieta |"))
        XCTAssertEqual(result.counts.rowsInspected, 1)
    }

    func testArchiveWithNoUsableDeliveriesLeavesTheLogAlone() throws {
        let data = try archive([
            "2026-03-08 10:00:00,2026-03-08 10:10:00,2026-03-08 10:40:00,Chipotle,2,Cancelled"
        ])

        XCTAssertThrowsError(try importArchive(data, existing: Fixtures.twoRows)) { error in
            XCTAssertEqual(error as? ArchiveImportError, .nothingToImport)
        }
    }

    // MARK: - Limits

    func testArchiveSizeLimitIsEnforced() throws {
        let data = try archive([
            "2026-03-08 10:00:00,2026-03-08 10:10:00,2026-03-08 10:40:00,Chipotle,2,Delivered"
        ])

        XCTAssertThrowsError(
            try ArchiveImporter.prepare(
                archiveData: data,
                existingLog: "",
                limits: ArchiveLimits(maxArchiveBytes: 10, maxEntries: 10, maxEntryBytes: 1_000)
            )
        ) { error in
            guard let archiveError = error as? ArchiveImportError else {
                return XCTFail("expected an ArchiveImportError, got \(error)")
            }
            guard case .archiveTooLarge = archiveError else {
                return XCTFail("expected archiveTooLarge, got \(archiveError)")
            }
        }
    }

    func testEntryCountLimitIsEnforced() throws {
        let data = try zip([
            ("one.csv", "a\n1\n"),
            ("two.csv", "a\n1\n"),
            ("delivery_information.csv", csv([
                "2026-03-08 10:00:00,2026-03-08 10:10:00,2026-03-08 10:40:00,Chipotle,2,Delivered"
            ]))
        ])

        XCTAssertThrowsError(
            try ArchiveImporter.prepare(
                archiveData: data,
                existingLog: "",
                limits: ArchiveLimits(maxArchiveBytes: 1_000_000, maxEntries: 2, maxEntryBytes: 1_000)
            )
        ) { error in
            XCTAssertEqual(error as? ArchiveImportError, .tooManyEntries(limit: 2))
        }
    }

    func testEntrySizeLimitIsEnforced() throws {
        let data = try archive([
            "2026-03-08 10:00:00,2026-03-08 10:10:00,2026-03-08 10:40:00,Chipotle,2,Delivered"
        ])

        XCTAssertThrowsError(
            try ArchiveImporter.prepare(
                archiveData: data,
                existingLog: "",
                limits: ArchiveLimits(maxArchiveBytes: 1_000_000, maxEntries: 10, maxEntryBytes: 16)
            )
        ) { error in
            guard let archiveError = error as? ArchiveImportError else {
                return XCTFail("expected an ArchiveImportError, got \(error)")
            }
            guard case .entryTooLarge = archiveError else {
                return XCTFail("expected entryTooLarge, got \(archiveError)")
            }
        }
    }

    // MARK: - Timestamps, DST and boundaries

    func testSpringForwardKeepsWallClockHoursOnBothSides() throws {
        let data = try archive([
            // 09:40 and 09:50 UTC are still PST (UTC-8): 01:40 local.
            "2026-03-08 09:30:00,2026-03-08 09:40:00,2026-03-08 09:50:00,Chipotle (Murrieta),2,Delivered",
            // 10:10 UTC is after the 10:00 UTC transition, so PDT (UTC-7): 03:10.
            "2026-03-08 10:00:00,2026-03-08 10:10:00,2026-03-08 10:30:00,Chipotle (Murrieta),2,Delivered"
        ])

        let result = try importArchive(data)

        XCTAssertTrue(result.mergedLog.contains(
            "| 2026-03-08 01:40 | 7.00 | 6.0 | 2 |  |  |  |  |  | Accepted |  | Murrieta | 18 | archive |"
        ))
        XCTAssertTrue(result.mergedLog.contains(
            "| 2026-03-08 03:10 | 7.00 | 9.3 | 2 |  |  |  |  |  | Accepted |  | Murrieta | 28 | archive |"
        ))
    }

    func testMidnightRollsBackIntoThePreviousMonth() throws {
        let data = try archive([
            // 06:20 UTC on 1 Nov is 23:20 PDT on 31 Oct: both the date and the
            // month in the log differ from the archive's own timestamp.
            "2026-11-01 06:10:00,2026-11-01 06:20:00,2026-11-01 06:30:00,Chipotle (Murrieta),2,Delivered"
        ])

        let result = try importArchive(data)

        XCTAssertTrue(result.mergedLog.contains(
            "| 2026-10-31 23:20 | 7.00 | 6.0 | 2 |  |  |  |  |  | Accepted |  | Murrieta | 18 | archive |"
        ))
    }

    func testFallBackHourIsFormattedOnce() throws {
        let data = try archive([
            // 08:10 UTC on 1 Nov is 01:10 PST, after the 09:00 UTC transition.
            "2026-11-01 08:00:00,2026-11-01 08:10:00,2026-11-01 08:40:00,Chipotle (Murrieta),2,Delivered"
        ])

        let result = try importArchive(data)

        XCTAssertTrue(result.mergedLog.contains(
            "| 2026-11-01 01:10 | 7.00 | 12.7 | 2 |  |  |  |  |  | Accepted |  | Murrieta | 38 | archive |"
        ))
    }

    // MARK: - Overlap and intervals

    func testOverlappingDeliveriesShareTheBlockEqually() throws {
        let data = try archive([
            "2026-10-24 11:55:00,2026-10-24 12:00:00,2026-10-24 12:30:00,Chipotle (Murrieta),2,Delivered",
            "2026-10-24 12:05:00,2026-10-24 12:10:00,2026-10-24 12:40:00,Chipotle (Murrieta),2,Delivered"
        ])

        let result = try importArchive(data)

        // Block 11:52 -> 12:40 is 48 minutes, split two ways.
        XCTAssertTrue(result.mergedLog.contains(
            "| 2026-10-24 05:00 | 7.00 | 8.0 | 2 |  |  |  |  |  | Accepted |  | Murrieta | 24 | archive |"
        ))
        XCTAssertTrue(result.mergedLog.contains(
            "| 2026-10-24 05:10 | 7.00 | 8.0 | 2 |  |  |  |  |  | Accepted |  | Murrieta | 24 | archive |"
        ))
    }

    func testDeliveryBeforePickupIsDroppedAndCounted() throws {
        let data = try archive([
            // Pickup 13:00 is later than delivery 12:50, so the interval is negative.
            "2026-10-24 12:40:00,2026-10-24 13:00:00,2026-10-24 12:50:00,Chipotle (Murrieta),2,Delivered",
            "2026-10-24 14:00:00,2026-10-24 14:10:00,2026-10-24 14:40:00,Chipotle (Murrieta),2,Delivered"
        ])

        let result = try importArchive(data)

        XCTAssertEqual(result.counts.rowsInspected, 2)
        XCTAssertEqual(result.counts.droppedNonPositiveIntervals, 1)
        XCTAssertEqual(result.counts.validRows, 1)
        XCTAssertEqual(MasterLog.rowCount(result.mergedLog), 1)
    }

    // MARK: - Counts

    func testCountsPartitionEveryRowWithoutOverlap() throws {
        let data = try archive([
            "2026-10-24 10:00:00,2026-10-24 10:05:00,2026-10-24 10:30:00,Chipotle,2,Cancelled",
            "2026-10-24 11:00:00,2026-10-24 11:05:00,,Chipotle,2,Delivered",
            "2026-10-24 12:00:00,2026-10-24 12:05:00,not-a-date,Chipotle,2,Delivered",
            "2026-10-24 13:00:00,garbage,2026-10-24 13:30:00,Chipotle,2,Delivered",
            "2026-10-24 13:30:00,2026-10-24 14:00:00,2026-10-24 13:50:00,Chipotle,2,Delivered",
            "2026-10-24 15:00:00,2026-10-24 15:05:00,2026-10-24 15:30:00,Chipotle,2,Delivered"
        ])

        let result = try importArchive(data)
        let counts = result.counts

        XCTAssertEqual(counts.rowsInspected, 6)
        XCTAssertEqual(counts.cancelledSkipped, 1)
        XCTAssertEqual(counts.missingDeliverySkipped, 1)
        XCTAssertEqual(counts.invalidSkipped, 2)          // bad delivery date, bad pickup
        XCTAssertEqual(counts.droppedNonPositiveIntervals, 1)
        XCTAssertEqual(counts.validRows, 1)
        XCTAssertEqual(
            counts.rowsInspected,
            counts.validRows + counts.cancelledSkipped + counts.missingDeliverySkipped
                + counts.invalidSkipped + counts.droppedNonPositiveIntervals
        )
        XCTAssertEqual(counts.validRows, counts.alreadyPresent + counts.newlyAdded)
    }

    // MARK: - Merging, duplicates and preservation

    func testDuplicateRowsInsideOneArchiveAreBothKept() throws {
        let row = "2026-10-24 12:00:00,2026-10-24 12:10:00,2026-10-24 12:40:00,Chipotle,2,Delivered"
        let data = try archive([row, row])

        let result = try importArchive(data)

        // Two stacked deliveries can look identical; archive rows are never
        // deduplicated against each other, matching the web app's rule.
        XCTAssertEqual(MasterLog.rowCount(result.mergedLog), 2)
        XCTAssertEqual(result.counts.validRows, 2)
        XCTAssertEqual(result.counts.newlyAdded, 2)
    }

    func testReimportingTheSameArchiveAddsNothing() throws {
        let data = try archive([
            "2026-10-24 12:00:00,2026-10-24 12:10:00,2026-10-24 12:40:00,Chipotle (Murrieta),2,Delivered",
            "2026-10-25 09:00:00,2026-10-25 09:10:00,2026-10-25 09:40:00,Chipotle (Temecula),3,Delivered"
        ])

        let first = try importArchive(data)
        let second = try importArchive(data, existing: first.mergedLog)

        XCTAssertEqual(second.counts.newlyAdded, 0)
        XCTAssertEqual(second.counts.alreadyPresent, 2)
        XCTAssertEqual(second.counts.retainedRows, 2)
        XCTAssertEqual(second.mergedLog, first.mergedLog)
        XCTAssertEqual(MasterLog.rowCount(second.mergedLog), 2)
    }

    func testSupersetArchiveAddsOnlyTheNewRows() throws {
        let earlier = try archive([
            "2026-10-24 12:00:00,2026-10-24 12:10:00,2026-10-24 12:40:00,Chipotle (Murrieta),2,Delivered"
        ])
        let merged = try importArchive(earlier)

        let superset = try archive([
            "2026-10-24 12:00:00,2026-10-24 12:10:00,2026-10-24 12:40:00,Chipotle (Murrieta),2,Delivered",
            "2026-10-26 08:00:00,2026-10-26 08:10:00,2026-10-26 08:40:00,Chipotle (Menifee),2,Delivered"
        ])
        let second = try importArchive(superset, existing: merged.mergedLog)

        XCTAssertEqual(second.counts.newlyAdded, 1)
        XCTAssertEqual(second.counts.alreadyPresent, 1)
        XCTAssertEqual(second.counts.retainedRows, 1)
        XCTAssertEqual(MasterLog.rowCount(second.mergedLog), 2)
        // The earlier export's row is still there: merge never removes.
        XCTAssertTrue(second.mergedLog.contains("| Murrieta |"))
        XCTAssertTrue(second.mergedLog.contains("| Menifee |"))
    }

    func testShortcutRowsAndOtherArchiveRowsSurvive() throws {
        let existing = MasterLog.normalize(
            Fixtures.firstShortcutRow + "\n"
                + Fixtures.archiveLine("2025-01-05 10:00", minutes: "30", payout: "9.00")
        )
        let data = try archive([
            "2026-10-24 12:00:00,2026-10-24 12:10:00,2026-10-24 12:40:00,Chipotle (Murrieta),2,Delivered"
        ])

        let result = try importArchive(data, existing: existing)

        XCTAssertEqual(result.counts.newlyAdded, 1)
        XCTAssertEqual(result.counts.retainedRows, 2)
        XCTAssertEqual(MasterLog.rowCount(result.mergedLog), 3)
        XCTAssertTrue(result.mergedLog.contains(Fixtures.firstShortcutRow))
        XCTAssertTrue(result.mergedLog.contains("| 2025-01-05 10:00 |"))
        XCTAssertTrue(result.mergedLog.contains("| 2026-10-24 05:10 |"))
    }

    // MARK: - Persistence safety

    func testAnUnavailableMasterLogBlocksArchiveWrites() throws {
        let store = try makeStore()
        let corrupt = Data("not json".utf8)
        try corrupt.write(to: store.url(.masterLog))

        let library = LocalLibrary(store: store)
        XCTAssertTrue(library.isUnavailable(.masterLog))

        let data = try archive([
            "2026-10-24 12:00:00,2026-10-24 12:10:00,2026-10-24 12:40:00,Chipotle,2,Delivered"
        ])
        let result = try importArchive(data)

        XCTAssertThrowsError(try library.saveLog(result.mergedLog)) { error in
            XCTAssertEqual(error as? LocalStore.Failure, .blocked(.masterLog))
        }
        XCTAssertEqual(try Data(contentsOf: store.url(.masterLog)), corrupt)
        XCTAssertEqual(library.log.rowCount, 0)
    }

    func testFailedPersistenceLeavesMemoryAndTheFileUnchanged() throws {
        let store = try makeStore()
        let library = LocalLibrary(store: store)
        try library.saveLog(Fixtures.twoRows)
        let before = try Data(contentsOf: store.url(.masterLog))

        let data = try archive([
            "2026-10-24 12:00:00,2026-10-24 12:10:00,2026-10-24 12:40:00,Chipotle,2,Delivered"
        ])
        let result = try importArchive(data)
        try makeDirectoryUnwritable(store.directory)

        XCTAssertThrowsError(try library.saveLog(result.mergedLog)) { error in
            XCTAssertEqual(error as? LocalStore.Failure, .unwritable(.masterLog))
        }
        XCTAssertEqual(try Data(contentsOf: store.url(.masterLog)), before)
        XCTAssertEqual(library.log.rowCount, 2, "a failed write must not look like a successful import")
    }

    func testSuccessfulImportPersistsThroughTheLibraryAndReloads() throws {
        let store = try makeStore()
        let library = LocalLibrary(store: store)
        let data = try archive([
            "2026-10-24 12:00:00,2026-10-24 12:10:00,2026-10-24 12:40:00,Chipotle (Murrieta),2,Delivered"
        ])

        let result = try importArchive(data)
        try library.saveLog(result.mergedLog)

        let reloaded = LocalLibrary(store: LocalStore(directory: store.directory))
        XCTAssertEqual(reloaded.status(of: .masterLog), .loaded)
        XCTAssertEqual(reloaded.log.text, result.mergedLog)
        XCTAssertEqual(reloaded.log.archiveRowCount, 1)
    }
}
