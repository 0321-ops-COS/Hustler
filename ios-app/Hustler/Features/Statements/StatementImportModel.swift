import Foundation
import SwiftUI
import HustlerCore

/// Screen state for statement import. It owns no arithmetic: parsing,
/// allocation and month summaries all come from `HustlerCore`, and the store
/// only reads or writes whole documents.
@MainActor
final class StatementImportModel: ObservableObject {

    struct Notice: Equatable {
        let text: String
        let isFailure: Bool
    }

    @Published private(set) var log: MasterLogDocument
    @Published private(set) var book: StatementBook
    @Published var logDraft: String
    @Published var pasteDraft: String = ""
    @Published private(set) var notice: Notice?

    private let store: LocalStore
    private static let logName = "master-log.json"
    private static let statementsName = "statements.json"

    init(store: LocalStore = LocalStore()) {
        self.store = store

        var loadedLog = MasterLogDocument(text: "")
        var loadedBook = StatementBook()
        var failures: [String] = []

        do {
            if let stored = try store.load(MasterLogDocument.self, from: Self.logName) {
                loadedLog = stored
            }
        } catch {
            failures.append(error.localizedDescription)
        }

        do {
            if let stored = try store.load(StatementStoreDocument.self, from: Self.statementsName) {
                loadedBook = stored.book
            }
        } catch {
            failures.append(error.localizedDescription)
        }

        self.log = loadedLog
        self.book = loadedBook
        self.logDraft = loadedLog.rowCount > 0 ? loadedLog.text : ""
        self.notice = failures.isEmpty ? nil : Notice(text: failures.joined(separator: " "), isFailure: true)
    }

    // MARK: - Derived state

    var summaries: [StatementMonthSummary] {
        StatementImporter.summaries(book: book, rows: parsedRows)
    }

    var logRowCount: Int { log.rowCount }

    var logArchiveRowCount: Int { log.archiveRowCount }

    private var parsedRows: [LogRow] { MasterLogParser.parse(log.text) }

    // MARK: - Master log

    /// Saves the draft through `masterLog()`, so the stored text is canonical and
    /// the counts on screen describe what was actually kept.
    func saveLog() {
        let document = MasterLogDocument(text: logDraft)
        do {
            try store.save(document, as: Self.logName)
            log = document
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
        switch StatementImporter.outcome(text: text, source: source) {
        case let .parsed(statement):
            var updated = book
            guard updated.take([text]) > 0 else {
                notice = Notice(text: "Nothing was imported.", isFailure: true)
                return
            }
            do {
                try store.save(StatementStoreDocument(book: updated), as: Self.statementsName)
                book = updated
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
