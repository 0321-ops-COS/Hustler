import Foundation

/// One JSON file per artefact under `Application Support/Hustler/`.
///
/// Writes are atomic and carry complete file protection; this is earnings
/// history, not cache. Each document carries its own `schemaVersion` and throws
/// on a version it does not know, so a newer or unreadable file is reported to
/// the user and left alone instead of being overwritten with defaults.
struct LocalStore {

    enum Failure: LocalizedError {
        case unreadable(name: String)
        case unwritable(name: String)

        var errorDescription: String? {
            switch self {
            case let .unreadable(name):
                return "Saved data in \(name) could not be read. It has not been changed."
            case let .unwritable(name):
                return "Could not save \(name)."
            }
        }
    }

    static let directoryName = "Hustler"

    let directory: URL

    /// `directory` exists so tests and previews can point at a temporary folder;
    /// the app passes nothing and gets Application Support.
    init(directory: URL? = nil) {
        if let directory {
            self.directory = directory
        } else {
            let base = FileManager.default
                .urls(for: .applicationSupportDirectory, in: .userDomainMask)
                .first ?? URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            self.directory = base.appendingPathComponent(Self.directoryName, isDirectory: true)
        }
    }

    func url(_ name: String) -> URL {
        directory.appendingPathComponent(name, isDirectory: false)
    }

    /// `nil` when the file does not exist yet; throws when it exists but cannot
    /// be read or decoded.
    func load<T: Decodable>(_ type: T.Type, from name: String) throws -> T? {
        let file = url(name)
        guard FileManager.default.fileExists(atPath: file.path) else { return nil }
        do {
            return try JSONDecoder().decode(T.self, from: Data(contentsOf: file))
        } catch {
            throw Failure.unreadable(name: name)
        }
    }

    func save<T: Encodable>(_ value: T, as name: String) throws {
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.sortedKeys]
            let data = try encoder.encode(value)
            try data.write(to: url(name), options: [.atomic, .completeFileProtection])
        } catch {
            throw Failure.unwritable(name: name)
        }
    }
}
