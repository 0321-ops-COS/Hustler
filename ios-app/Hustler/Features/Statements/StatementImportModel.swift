import Foundation
import SwiftUI
import HustlerCore
import HustlerArchive

/// Screen state for statement import. It owns no arithmetic and no durability
/// rules: parsing, allocation and month summaries come from `HustlerCore`, and
/// `LocalLibrary` decides what may be read or written. This type only turns
/// results into sentences.
///
/// A file that exists but cannot be read is surfaced as an unavailable artefact,
/// not as an empty one: the drafts stay blank, the buttons that would write are
/// disabled, and the only way forward is the explicit "keep a copy and start
/// fresh" recovery, which never deletes the original file.
@MainActor
final class StatementImportModel: ObservableObject {

    struct Notice: Equatable {
        let text: String
        let isFailure: Bool
    }

    @Published private(set) var log: MasterLogDocument
    @Published private(set) var statements: StatementBook
    @Published private(set) var unavailable: [StoreArtefact: String]
    @Published var logDraft: String
    @Published var pasteDraft: String = ""
    @Published private(set) var notice: Notice?
    @Published private(set) var archiveCounts: ArchiveImportCounts?
    @Published private(set) var isImportingArchive = false

    private let library: LocalLibrary

    init(store: LocalStore = LocalStore()) {
        let library = LocalLibrary(store: store)
        let problems = Self.problems(in: library)

        self.library = library
        self.log = library.log
        self.statements = library.statements
        self.unavailable = problems
        self.logDraft = library.log.rowCount > 0 ? library.log.text : ""
        self.notice = problems.isEmpty
            ? nil
            : Notice(
                text: "Saved data could not be read. Nothing has been replaced or deleted; "
                    + "read the note below before saving.",
                isFailure: true
            )
    }

    // MARK: - Derived state

    var summaries: [StatementMonthSummary] {
        library.summaries(rows: parsedRows)
    }

    var logRowCount: Int { log.rowCount }

    var logArchiveRowCount: Int { log.archiveRowCount }

    var logProblem: String? { unavailable[.masterLog] }

    var statementsProblem: String? { unavailable[.statements] }

    private var parsedRows: [LogRow] { MasterLogParser.parse(log.text) }

    // MARK: - Master log

    /// Saves the draft through `masterLog()`, so the stored text is canonical and
    /// the counts on screen describe what was actually kept. The draft is only
    /// replaced when the write succeeded.
    func saveLog() {
        do {
            let document = try library.saveLog(logDraft)
            refresh()
            logDraft = document.rowCount > 0 ? document.text : ""
            notice = Notice(
                text: "Saved \(document.rowCount) rows, \(document.archiveRowCount) of them from the archive.",
                isFailure: false
            )
        } catch {
            notice = Notice(text: error.localizedDescription, isFailure: true)
        }
    }

    // MARK: - Statements

    func importPaste() {
        importText(pasteDraft, source: .paste)
    }

    /// Reads page one through `StatementPDFText`; `nil` there is the documented
    /// "no text on page one" case, which points the user at the paste box rather
    /// than retrying silently.
    func importPDF(data: Data) {
        guard let text = StatementPDFText.pageOne(from: data) else {
            notice = Notice(
                text: "That PDF has no readable text on page one. If it is a scan, paste the statement text instead.",
                isFailure: true
            )
            return
        }
        importText(text, source: .pdf)
    }

    func importPDF(at url: URL) {
        let scoped = url.startAccessingSecurityScopedResource()
        defer {
            if scoped { url.stopAccessingSecurityScopedResource() }
        }
        do {
            importPDF(data: try Data(contentsOf: url))
        } catch {
            notice = Notice(text: "That file could not be read.", isFailure: true)
        }
    }

    func reportFailure(_ error: Error) {
        notice = Notice(text: error.localizedDescription, isFailure: true)
    }

    private func importText(_ text: String, source: StatementImportSource) {
        if let problem = statementsProblem {
            notice = Notice(text: problem, isFailure: true)
            return
        }

        switch StatementImporter.outcome(text: text, source: source) {
        case let .parsed(statement):
            do {
                try library.addStatement(statement, text: text)
                refresh()
                if source == .paste { pasteDraft = "" }
                notice = Notice(
                    text: "Imported \(Self.monthLabel(statement.month)): "
                        + "\(Money.format(statement.total)) over \(statement.payouts) payouts.",
                    isFailure: false
                )
            } catch {
                notice = Notice(text: error.localizedDescription, isFailure: true)
            }

        case .emptyText:
            notice = Notice(
                text: source == .pdf
                    ? "That PDF has no text on page one."
                    : "The paste box is empty.",
                isFailure: true
            )

        case .unreadable:
            notice = Notice(
                text: "No statement month and total were found. Page one needs the month, "
                    + "a line like \"October 2026 Statement\", and \"Total Payouts $1,234.56\".",
                isFailure: true
            )
        }
    }

    // MARK: - DoorDash archive

    /// Reads and converts the ZIP off the main thread, then persists the merged
    /// log through `LocalLibrary`. Success is reported only after the write
    /// succeeded, and a failed write leaves the in-memory log as it was.
    func importArchive(at url: URL) {
        if let problem = logProblem {
            notice = Notice(text: problem, isFailure: true)
            return
        }

        let scoped = url.startAccessingSecurityScopedResource()
        defer {
            if scoped { url.stopAccessingSecurityScopedResource() }
        }

        let data: Data
        do {
            data = try Data(contentsOf: url)
        } catch {
            notice = Notice(text: "That archive could not be read.", isFailure: true)
            return
        }

        let existing = log.text
        archiveCounts = nil
        isImportingArchive = true

        Task {
            let prepared: Result<ArchiveImportResult, Error>
            do {
                let result = try await Task.detached(priority: .userInitiated) {
                    try ArchiveImporter.prepare(archiveData: data, existingLog: existing)
                }.value
                prepared = .success(result)
            } catch {
                prepared = .failure(error)
            }

            isImportingArchive = false

            switch prepared {
            case let .success(result):
                do {
                    try library.saveLog(result.mergedLog)
                    refresh()
                    archiveCounts = result.counts
                    notice = Notice(
                        text: "Added \(result.counts.newlyAdded) rows from the archive; "
                            + "\(result.counts.alreadyPresent) were already in your log.",
                        isFailure: false
                    )
                } catch {
                    archiveCounts = nil
                    notice = Notice(text: error.localizedDescription, isFailure: true)
                }
            case let .failure(error):
                notice = Notice(text: error.localizedDescription, isFailure: true)
            }
        }
    }

    // MARK: - Explicit recovery

    func recoverLog() {
        recover(.masterLog)
    }

    func recoverStatements() {
        recover(.statements)
    }

    private func recover(_ artefact: StoreArtefact) {
        do {
            let copy = try library.recover(artefact)
            refresh()
            if artefact == .masterLog { logDraft = "" }

            let kept = copy.map { "The unreadable file is kept as \($0.lastPathComponent). " } ?? ""
            let reset = artefact == .masterLog
                ? "The master log now starts empty."
                : "The statements now start empty."
            notice = Notice(text: kept + reset, isFailure: false)
        } catch {
            notice = Notice(text: error.localizedDescription, isFailure: true)
        }
    }

    // MARK: - Helpers

    /// Copies durable state into the published properties; it deliberately does
    /// not touch `logDraft`, so unsaved edits survive an import.
    private func refresh() {
        log = library.log
        statements = library.statements
        unavailable = Self.problems(in: library)
    }

    private static func problems(in library: LocalLibrary) -> [StoreArtefact: String] {
        var problems: [StoreArtefact: String] = [:]
        for artefact in StoreArtefact.allCases {
            if case let .unavailable(reason) = library.status(of: artefact) {
                problems[artefact] = reason
            }
        }
        return problems
    }

    /// `2026-10` → `October 2026`, display only; the stored key stays `yyyy-MM`.
    static func monthLabel(_ key: String) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyy-MM"
        guard let date = formatter.date(from: key) else { return key }
        formatter.dateFormat = "MMMM yyyy"
        return formatter.string(from: date)
    }
}
