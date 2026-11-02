import Foundation

/// The two files the app keeps. The raw value is the file name on disk, so the
/// store and the code that names a file cannot disagree.
public enum StoreArtefact: String, CaseIterable, Sendable {
    case masterLog = "master-log.json"
    case statements = "statements.json"

    /// Lower-case noun used in messages.
    public var label: String {
        switch self {
        case .masterLog: return "master log"
        case .statements: return "statements"
        }
    }
}

/// One JSON file per artefact under `Application Support/Hustler/`.
///
/// The rules here are about not losing earnings history, so they are enforced at
/// the layer that touches the file rather than left to each caller:
///
/// - a **missing** file reads as `nil` — a first run, not an error;
/// - a file that **exists but cannot be decoded** (corrupt, unreadable, or a
///   newer `schemaVersion`) puts that artefact into a blocked state. Every later
///   `save` to it throws, so an unreadable file can never be quietly replaced by
///   an empty document;
/// - the block is per artefact, so a bad statements file does not stop the
///   master log from saving;
/// - the block is lifted only by `quarantine`, which moves the unreadable file
///   aside under a free name. That file is never deleted or overwritten;
/// - writes stay atomic, and carry complete file protection on Apple platforms.
///
/// This is a class because the blocked set is per-store state that must outlive
/// any one call; one instance is created per app launch.
public final class LocalStore {

    public enum Failure: LocalizedError, Equatable {
        case unreadable(StoreArtefact)
        case unsupportedVersion(StoreArtefact, Int)
        case unwritable(StoreArtefact)
        case blocked(StoreArtefact)

        public var errorDescription: String? {
            switch self {
            case let .unreadable(artefact):
                return "Saved \(artefact.label) could not be read. The file has not been changed, "
                    + "and saving is blocked until you keep a copy and start fresh."
            case let .unsupportedVersion(artefact, version):
                return "Saved \(artefact.label) use format \(version), which this version of Hustler "
                    + "does not know. Nothing was changed. Update the app, or keep a copy and start fresh."
            case let .unwritable(artefact):
                return "Could not save the \(artefact.label). The existing file was left alone."
            case let .blocked(artefact):
                return "Saving the \(artefact.label) is blocked because the existing file could not be "
                    + "read. Nothing was overwritten."
            }
        }
    }

    public static let directoryName = "Hustler"

    public let directory: URL

    /// Artefacts whose stored file exists but could not be decoded. Writes to
    /// these are refused until `quarantine` is called for them.
    private var blocked: Set<StoreArtefact> = []

    /// `directory` exists so tests and previews can point at a temporary folder;
    /// the app passes nothing and gets Application Support.
    public init(directory: URL? = nil) {
        if let directory {
            self.directory = directory
        } else {
            let base = FileManager.default
                .urls(for: .applicationSupportDirectory, in: .userDomainMask)
                .first ?? URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            self.directory = base.appendingPathComponent(Self.directoryName, isDirectory: true)
        }
    }

    public func url(_ artefact: StoreArtefact) -> URL {
        directory.appendingPathComponent(artefact.rawValue, isDirectory: false)
    }

    public func isBlocked(_ artefact: StoreArtefact) -> Bool {
        blocked.contains(artefact)
    }

    public var blockedArtefacts: Set<StoreArtefact> {
        blocked
    }

    /// `nil` when the file does not exist yet; throws — and blocks further writes
    /// to that artefact — when it exists but cannot be decoded.
    public func load<T: Decodable>(_ type: T.Type, from artefact: StoreArtefact) throws -> T? {
        let file = url(artefact)
        guard FileManager.default.fileExists(atPath: file.path) else { return nil }

        do {
            return try JSONDecoder().decode(T.self, from: Data(contentsOf: file))
        } catch let error as StoreDocumentError {
            blocked.insert(artefact)
            switch error {
            case let .unsupportedVersion(version):
                throw Failure.unsupportedVersion(artefact, version)
            }
        } catch {
            blocked.insert(artefact)
            throw Failure.unreadable(artefact)
        }
    }

    /// Refuses to write an artefact whose existing file could not be read, so a
    /// failed load can never turn into data loss.
    public func save<T: Encodable>(_ value: T, as artefact: StoreArtefact) throws {
        guard !blocked.contains(artefact) else { throw Failure.blocked(artefact) }

        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.sortedKeys]
            let data = try encoder.encode(value)
            try data.write(to: url(artefact), options: Self.writeOptions)
        } catch {
            throw Failure.unwritable(artefact)
        }
    }

    /// The explicit recovery path: move the unreadable file aside under a free
    /// name and lift the block. Returns the copy it kept, or `nil` when there was
    /// no file left to move. Nothing is deleted.
    @discardableResult
    public func quarantine(_ artefact: StoreArtefact) throws -> URL? {
        let file = url(artefact)
        var kept: URL?

        if FileManager.default.fileExists(atPath: file.path) {
            let destination = freeQuarantineURL(for: artefact)
            do {
                try FileManager.default.moveItem(at: file, to: destination)
            } catch {
                throw Failure.unwritable(artefact)
            }
            kept = destination
        }

        blocked.remove(artefact)
        return kept
    }

    private func freeQuarantineURL(for artefact: StoreArtefact) -> URL {
        let base = artefact.rawValue + ".unreadable"
        var candidate = directory.appendingPathComponent(base, isDirectory: false)
        var counter = 2
        while FileManager.default.fileExists(atPath: candidate.path) {
            candidate = directory.appendingPathComponent("\(base)-\(counter)", isDirectory: false)
            counter += 1
        }
        return candidate
    }

    /// Atomic on every platform; complete file protection where the platform has
    /// it, because this is earnings history rather than cache.
    private static var writeOptions: Data.WritingOptions {
        #if os(iOS) || os(macOS) || os(tvOS) || os(watchOS) || os(visionOS)
        return [.atomic, .completeFileProtection]
        #else
        return [.atomic]
        #endif
    }
}

/// The in-memory state of both artefacts, and the only place that decides when a
/// change becomes durable.
///
/// Load failures are held per artefact, so one bad file cannot reset or block the
/// other. A save is committed to memory only after the write succeeded: if the
/// write throws, `log` / `statements` keep their previous value and the caller
/// can say so without having to undo anything.
public final class LocalLibrary {

    public enum Status: Equatable, Sendable {
        /// Nothing on disk yet: a new, empty document is the correct state.
        case missing
        /// Read from disk successfully.
        case loaded
        /// A file exists but cannot be read. Writes to it are blocked until
        /// `recover` is called.
        case unavailable(String)
    }

    public let store: LocalStore

    public private(set) var log: MasterLogDocument
    public private(set) var statements: StatementBook

    private var statuses: [StoreArtefact: Status]

    public init(store: LocalStore = LocalStore()) {
        self.store = store

        var statuses: [StoreArtefact: Status] = [:]

        // Loaded one at a time and caught separately: a statements failure must
        // not leave the master log looking unreadable, or the reverse.
        var log = MasterLogDocument(text: "")
        do {
            if let stored = try store.load(MasterLogDocument.self, from: .masterLog) {
                log = stored
                statuses[.masterLog] = .loaded
            } else {
                statuses[.masterLog] = .missing
            }
        } catch {
            statuses[.masterLog] = .unavailable(error.localizedDescription)
        }

        var statements = StatementBook()
        do {
            if let stored = try store.load(StatementStoreDocument.self, from: .statements) {
                statements = stored.book
                statuses[.statements] = .loaded
            } else {
                statuses[.statements] = .missing
            }
        } catch {
            statuses[.statements] = .unavailable(error.localizedDescription)
        }

        self.log = log
        self.statements = statements
        self.statuses = statuses
    }

    public func status(of artefact: StoreArtefact) -> Status {
        statuses[artefact] ?? .missing
    }

    public func isUnavailable(_ artefact: StoreArtefact) -> Bool {
        if case .unavailable = status(of: artefact) { return true }
        return false
    }

    /// Saves the draft through the web app's `masterLog()` and adopts it only
    /// after the write succeeded.
    @discardableResult
    public func saveLog(_ draft: String) throws -> MasterLogDocument {
        let document = MasterLogDocument(text: draft)
        try store.save(document, as: .masterLog)
        log = document
        statuses[.masterLog] = .loaded
        return document
    }

    /// `takeStm()` and the write, committed together: the in-memory book moves
    /// only when the file did.
    @discardableResult
    public func addStatement(_ statement: EarningsStatement, text: String) throws -> StatementBook {
        if isUnavailable(.statements) {
            throw LocalStore.Failure.blocked(.statements)
        }

        var updated = statements
        guard updated.take([text]) > 0 else {
            throw ImportError.notApplied(statement.month)
        }

        try store.save(StatementStoreDocument(book: updated), as: .statements)
        statements = updated
        statuses[.statements] = .loaded
        return updated
    }

    public enum ImportError: LocalizedError, Equatable {
        /// The text parsed, but `takeStm` then found nothing to store. Surfaced
        /// rather than swallowed, because it means the two disagree.
        case notApplied(String)

        public var errorDescription: String? {
            switch self {
            case let .notApplied(month):
                return "The statement for \(month) was not applied. The stored statements were left alone."
            }
        }
    }

    /// Moves the unreadable file aside, clears that artefact back to an empty
    /// document and lifts the write block. The other artefact is untouched.
    @discardableResult
    public func recover(_ artefact: StoreArtefact) throws -> URL? {
        let kept = try store.quarantine(artefact)

        switch artefact {
        case .masterLog:
            log = MasterLogDocument(text: "")
        case .statements:
            statements = StatementBook()
        }
        statuses[artefact] = .missing

        return kept
    }

    public func summaries(rows: [LogRow]) -> [StatementMonthSummary] {
        StatementImporter.summaries(book: statements, rows: rows)
    }
}
