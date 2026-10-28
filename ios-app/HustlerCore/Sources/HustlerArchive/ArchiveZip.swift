import Foundation
import ZIPFoundation

/// Reads exactly one member out of a DoorDash `data_archive.zip`.
///
/// The web app's rule is kept: the first entry whose name ends in
/// `delivery_information.csv` (case-insensitive, any directory prefix) is the
/// only thing read. Nothing is extracted to disk, so the archive's personal
/// information files are never written anywhere.
public enum DeliveryArchiveFile {

    public static let entrySuffix = "delivery_information.csv"

    public static func deliveryCSV(in archiveData: Data, limits: ArchiveLimits = .standard) throws -> Data {
        guard archiveData.count <= limits.maxArchiveBytes else {
            throw ArchiveImportError.archiveTooLarge(bytes: archiveData.count, limit: limits.maxArchiveBytes)
        }

        let archive: Archive
        do {
            archive = try Archive(data: archiveData, accessMode: .read)
        } catch {
            throw ArchiveImportError.unreadableArchive(reason: error.localizedDescription)
        }

        var inspected = 0
        var match: Entry?
        for entry in archive {
            inspected += 1
            guard inspected <= limits.maxEntries else {
                throw ArchiveImportError.tooManyEntries(limit: limits.maxEntries)
            }
            guard entry.type == .file else { continue }
            if entry.path.lowercased().hasSuffix(entrySuffix) {
                match = entry
                break
            }
        }

        guard let entry = match else {
            throw ArchiveImportError.deliveryFileMissing
        }

        guard entry.uncompressedSize <= UInt64(limits.maxEntryBytes) else {
            throw ArchiveImportError.entryTooLarge(bytes: Int(entry.uncompressedSize), limit: limits.maxEntryBytes)
        }

        var payload = Data()
        do {
            _ = try archive.extract(entry) { chunk in
                payload.append(chunk)
                if payload.count > limits.maxEntryBytes {
                    throw ArchiveImportError.entryTooLarge(
                        bytes: payload.count,
                        limit: limits.maxEntryBytes
                    )
                }
            }
        } catch let error as ArchiveImportError {
            throw error
        } catch {
            // ZIPFoundation has no public "encrypted" flag; an encrypted member
            // fails here (its bytes never decompress), so the message names both
            // possibilities rather than guessing.
            throw ArchiveImportError.deliveryFileUnreadable(reason: error.localizedDescription)
        }

        return payload
    }
}
