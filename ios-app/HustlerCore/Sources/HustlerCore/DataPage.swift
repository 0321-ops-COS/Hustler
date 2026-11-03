import Foundation

/// The web `#data` card wording; saved-original-files is absent because this app
/// never keeps the uploaded file.
public enum DataPageCopy {
    public static let introTitle = "Add your files"
    public static let intro = "Every file goes into the one master log. Nothing is saved anywhere else."
    public static let offersTitle = "Offers log"
    public static let offersHint = "New rows are added to your saved log. A missing header row is added for you."
    public static let statementsTitle = "Monthly statements"
    public static let statementsHint = "Reads each month's total and payout count on this device. Each month also sets your real pay."
    public static let archiveTitle = "DoorDash archive"
    public static let archiveHint = "Only the delivery file is read, on this device. Your personal info file is ignored and never saved. Pay and miles are estimated from your settings. Drop your statement PDFs in Earn to correct them."
    public static let masterHint = "The one table the whole app reads."
    public static let deleteTitle = "Delete data"
    public static let deleteHint = "Removes it from this device. This cannot be undone."
}

/// The web app's Delete data buttons, in order, with its `WIPE` nouns.
public enum DataDeleteAction: String, CaseIterable, Identifiable, Sendable {
    case masterLog, archive, statements, caEntries, everything
    public var id: String { rawValue }
    public var title: String {
        switch self {
        case .masterLog: return "Clear master log"
        case .archive: return "Remove archive"
        case .statements: return "Remove statements"
        case .caEntries: return "Clear CA entries"
        case .everything: return "Wipe everything"
        }
    }
    public var what: String {
        switch self {
        case .masterLog: return "your master log"
        case .archive: return "the DoorDash archive and the deliveries it added"
        case .statements: return "all monthly statements"
        case .caEntries: return "your California guarantee entries"
        case .everything: return "EVERYTHING: master log, archive, statements, CA entries and settings"
        }
    }
    public var confirmation: String { "Delete \(what)? This cannot be undone." }
    public var doneMessage: String {
        switch self {
        case .masterLog: return "Master log cleared."
        case .archive: return "Archive rows removed from the master log."
        case .statements: return "Statements removed."
        case .caEntries: return "CA entries cleared."
        case .everything: return "Everything wiped."
        }
    }
}

public struct DataWipeResult: Equatable, Sendable {
    public let action: DataDeleteAction
    public let failures: [String]
    public var isComplete: Bool { failures.isEmpty }
    public var message: String {
        failures.isEmpty ? action.doneMessage
            : ([action.title + " did not finish. Nothing unreadable was overwritten."] + failures).joined(separator: " ")
    }
}

/// Each delete acts only through `LocalStore`, so an unreadable artefact is never
/// overwritten. `Wipe everything` runs each part separately for the same reason.
public final class DataWipe {
    public let store: LocalStore
    public init(store: LocalStore = LocalStore()) { self.store = store }

    @discardableResult
    public func perform(_ action: DataDeleteAction) -> DataWipeResult {
        var failures: [String] = []
        func attempt(_ label: String, _ body: () throws -> Void) {
            do { try body() } catch { failures.append("\(label): \(error.localizedDescription)") }
        }
        let library = LocalLibrary(store: store), settings = SettingsStore(store: store)
        if action == .masterLog || action == .everything { attempt("your master log") { try library.clearLog() } }
        if action == .archive || action == .everything { attempt("the archive") { try library.removeArchiveRows() } }
        if action == .statements || action == .everything { attempt("the statements") { try library.clearStatements() } }
        if action == .caEntries || action == .everything { attempt("the CA entries") { try clearCA(settings) } }
        if action == .everything { attempt("the settings") { _ = try settings.save(AppSettings()) } }
        return DataWipeResult(action: action, failures: failures)
    }

    /// Loading is what marks an artefact blocked; nothing here writes.
    public func blockedArtefacts() -> [StoreArtefact: String] {
        var found: [StoreArtefact: String] = [:]
        let library = LocalLibrary(store: store)
        for artefact in StoreArtefact.allCases {
            if case let .unavailable(reason) = library.status(of: artefact) { found[artefact] = reason }
        }
        if case let .unavailable(reason) = SettingsStore(store: store).status { found[.settings] = reason }
        return found
    }

    @discardableResult
    public func recover(_ artefact: StoreArtefact) throws -> URL? {
        artefact == .settings ? try SettingsStore(store: store).recover() : try LocalLibrary(store: store).recover(artefact)
    }

    private func clearCA(_ settings: SettingsStore) throws {
        var updated = settings.settings
        updated.caEntries = [:]
        try settings.save(updated)
    }
}
