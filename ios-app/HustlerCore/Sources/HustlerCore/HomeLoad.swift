import Foundation

/// Everything the Scoreboard reads from disk, gathered in one pass.
///
/// The app builds this inside a detached task and only touches its published
/// state afterwards, so the frame after sign-in is drawn before any file is
/// opened. Every field is a value type, so it can cross that boundary safely.
public struct HomeSnapshot: Equatable, Sendable {
    /// The saved log exists but cannot be read, so the screen says so instead of
    /// claiming there is no log.
    public let logUnavailable: String?
    /// False before the first master log exists.
    public let hasLog: Bool
    /// Parsed rows; empty when the log is missing or unreadable.
    public let rows: [LogRow]
    /// Months with a saved statement, for the "Start here" card.
    public let statementMonths: [String]
    /// Saved settings, or the defaults on a first run. The CA card needs them.
    public let settings: AppSettings

    public init(logUnavailable: String?, hasLog: Bool, rows: [LogRow],
                statementMonths: [String], settings: AppSettings) {
        self.logUnavailable = logUnavailable
        self.hasLog = hasLog
        self.rows = rows
        self.statementMonths = statementMonths
        self.settings = settings
    }
}

/// One read of the store, with no UI and no awaiting, so callers decide which
/// thread it runs on. Reads are side-effect free apart from a blocked artefact
/// being recorded on that store instance.
public enum HomeLoader {
    public static func snapshot(in directory: URL) -> HomeSnapshot {
        let store = LocalStore(directory: directory)
        let library = LocalLibrary(store: store)

        var problem: String?
        if case let .unavailable(reason) = library.status(of: .masterLog) {
            problem = reason
        }

        return HomeSnapshot(
            logUnavailable: problem,
            hasLog: library.log.rowCount > 0,
            rows: problem == nil ? MasterLogParser.parse(library.log.text) : [],
            statementMonths: Array(library.statements.statements.keys),
            settings: SettingsStore(store: store).settings
        )
    }
}
