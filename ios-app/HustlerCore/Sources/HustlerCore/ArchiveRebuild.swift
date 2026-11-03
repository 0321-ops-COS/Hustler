import Foundation

/// The Settings "Rebuild archive rows" rule — `#rebuildArch` plus `toLog()`'s
/// log half: replace every archive row with rows built from the saved archive
/// and keep every other row. Shortcut rows are never touched; duplicates between
/// the two are hidden in totals by `HistoryViewModel`, never deleted.
///
/// The archive-to-line conversion is `ArchiveImporter`'s, not duplicated here:
/// `HustlerArchive` depends on `HustlerCore`, never the reverse.
public enum ArchiveRebuild {

    public enum Failure: LocalizedError, Equatable {
        case missingArchive, unreadableArchive

        public var errorDescription: String? {
            switch self {
            case .missingArchive: return "No saved archive found. Your master log was not changed."
            case .unreadableArchive: return "The saved archive could not be read. Your master log was not changed."
            }
        }
    }

    /// The rebuilt log plus what the screen reports.
    public struct Outcome: Equatable, Sendable {
        public let log: String
        public let archiveRows: Int
        public let keptRows: Int

        public var message: String {
            "Archive rows rebuilt. \(archiveRows) archive row\(archiveRows == 1 ? "" : "s") from "
                + "the saved archive; \(keptRows) other row\(keptRows == 1 ? "" : "s") kept."
        }
    }

    /// Throws rather than writing an empty archive section, so a missing or
    /// unusable archive cannot delete the rows it was meant to rebuild.
    public static func replacingArchiveRows(in log: String, with lines: [String]) throws -> Outcome {
        guard !lines.isEmpty else { throw Failure.missingArchive }
        let base = MasterLog.normalize(log)
        let kept = base.components(separatedBy: "\n").dropFirst(2).filter { !MasterLog.isArchiveLine($0) }
        let rebuilt = MasterLog.normalize((kept + lines).joined(separator: "\n"))
        let rows = rebuilt.components(separatedBy: "\n").dropFirst(2)
        let archiveRows = rows.filter { MasterLog.isArchiveLine($0) }.count
        guard archiveRows > 0 else { throw Failure.unreadableArchive }
        return Outcome(log: rebuilt, archiveRows: archiveRows, keptRows: rows.count - archiveRows)
    }
}

/// The card's wording, copied from `index.html` so the view draws fixed strings.
public enum ArchiveRebuildCopy {
    public static let title = "Rebuild archive rows"
    public static let hint = "Rebuilds every DoorDash archive row in your master log from your saved archive. "
        + "Live shortcut rows are not touched. Duplicates between the archive and shortcut rows are hidden "
        + "in the totals, never deleted."
    public static let button = "Rebuild archive rows"
    public static let confirmation = "Rebuild all archive rows from your saved DoorDash archive? "
        + "Live shortcut rows are not touched."
}
