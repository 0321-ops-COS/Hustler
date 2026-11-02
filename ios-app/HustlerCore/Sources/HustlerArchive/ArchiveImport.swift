import Foundation
import HustlerCore

/// Everything that can go wrong before a single row reaches the master log.
///
/// Each case is a distinct user-facing sentence: the caller never has to guess
/// whether a failure was the archive, the delivery file, or the data inside it.
public enum ArchiveImportError: LocalizedError, Equatable {
    case archiveTooLarge(bytes: Int, limit: Int)
    case tooManyEntries(limit: Int)
    case unreadableArchive(reason: String)
    case deliveryFileMissing
    case entryTooLarge(bytes: Int, limit: Int)
    case deliveryFileUnreadable(reason: String)
    case notADeliveryFile(missing: [String])
    case timeZoneUnavailable
    case nothingToImport

    public var errorDescription: String? {
        switch self {
        case let .archiveTooLarge(bytes, limit):
            return "That archive is \(bytes) bytes, over the \(limit)-byte limit this app will read."
        case let .tooManyEntries(limit):
            return "That archive has more than \(limit) entries. This app only reads DoorDash data archives."
        case let .unreadableArchive(reason):
            return "That file is not a readable ZIP archive. It may be corrupt or encrypted. (\(reason))"
        case .deliveryFileMissing:
            return "No delivery_information.csv in that archive. Pick the DoorDash data_archive.zip."
        case let .entryTooLarge(bytes, limit):
            return "The delivery file is \(bytes) bytes, over the \(limit)-byte limit this app will read."
        case let .deliveryFileUnreadable(reason):
            return "The delivery file could not be read. It may be encrypted or corrupt. (\(reason))"
        case let .notADeliveryFile(missing):
            return "That file is not a DoorDash delivery file: it is missing "
                + missing.joined(separator: ", ") + "."
        case .timeZoneUnavailable:
            return "The America/Los_Angeles time zone is unavailable on this device, so archive times "
                + "cannot be converted the way the web app converts them."
        case .nothingToImport:
            return "No usable deliveries were found, so your master log was left unchanged."
        }
    }
}

/// Guard rails for untrusted input. The archive is a ZIP from outside the app,
/// so both the container and the one entry that is read are size-capped, and the
/// entry count is capped before any extraction happens.
public struct ArchiveLimits: Equatable, Sendable {
    public var maxArchiveBytes: Int
    public var maxEntries: Int
    public var maxEntryBytes: Int

    public init(
        maxArchiveBytes: Int = 64 * 1024 * 1024,
        maxEntries: Int = 1_000,
        maxEntryBytes: Int = 32 * 1024 * 1024
    ) {
        self.maxArchiveBytes = maxArchiveBytes
        self.maxEntries = maxEntries
        self.maxEntryBytes = maxEntryBytes
    }

    public static let standard = ArchiveLimits()
}

/// What an import did, in categories that do not overlap.
///
/// `rowsInspected == validRows + cancelledSkipped + missingDeliverySkipped +
/// invalidSkipped + droppedNonPositiveIntervals`, and
/// `validRows == alreadyPresent + newlyAdded`. `droppedNonPositiveIntervals` is
/// reported separately from `invalidSkipped` (unreadable timestamps) rather than
/// being folded into it, so neither count double-counts a row.
///
/// `retainedRows` is the number of rows the log had before the import; every one
/// of them is still there afterwards, because archive import merges and never
/// replaces.
public struct ArchiveImportCounts: Equatable, Sendable {
    public var rowsInspected: Int
    public var validRows: Int
    public var cancelledSkipped: Int
    public var missingDeliverySkipped: Int
    public var invalidSkipped: Int
    public var droppedNonPositiveIntervals: Int
    public var alreadyPresent: Int
    public var newlyAdded: Int
    public var retainedRows: Int

    public init(
        rowsInspected: Int = 0,
        validRows: Int = 0,
        cancelledSkipped: Int = 0,
        missingDeliverySkipped: Int = 0,
        invalidSkipped: Int = 0,
        droppedNonPositiveIntervals: Int = 0,
        alreadyPresent: Int = 0,
        newlyAdded: Int = 0,
        retainedRows: Int = 0
    ) {
        self.rowsInspected = rowsInspected
        self.validRows = validRows
        self.cancelledSkipped = cancelledSkipped
        self.missingDeliverySkipped = missingDeliverySkipped
        self.invalidSkipped = invalidSkipped
        self.droppedNonPositiveIntervals = droppedNonPositiveIntervals
        self.alreadyPresent = alreadyPresent
        self.newlyAdded = newlyAdded
        self.retainedRows = retainedRows
    }
}

/// The complete, already-merged log text plus the counts. Nothing here has been
/// written anywhere: the caller persists `mergedLog` through `LocalLibrary`,
/// which is what makes a failed save leave both memory and disk untouched.
public struct ArchiveImportResult: Equatable, Sendable {
    public var mergedLog: String
    public var counts: ArchiveImportCounts

    public init(mergedLog: String, counts: ArchiveImportCounts) {
        self.mergedLog = mergedLog
        self.counts = counts
    }
}
