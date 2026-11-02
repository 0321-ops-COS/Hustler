import Foundation

/// Which input produced the text being parsed.
///
/// The source is kept because the same empty result means different things: a
/// PDF with no page-one text is the documented scan/image-only case, while
/// pasted text that does not parse is usually a wrong paste. The UI explains
/// each with its own message, and neither is an error in the calculation.
public enum StatementImportSource: String, Equatable, Sendable {
    case pdf
    case paste
}

/// The three things that can happen when statement text is submitted.
///
/// `emptyText` and `unreadable` are deliberately distinct: the first means
/// there was no text at all to parse, the second means there was text but it did
/// not match `stmParse`'s three patterns. Both leave the stored statements
/// untouched, exactly as the web app writes nothing when `takeStm` finds
/// nothing.
public enum StatementImportOutcome: Equatable, Sendable {
    case parsed(EarningsStatement)
    case emptyText(StatementImportSource)
    case unreadable(StatementImportSource)

    public var statement: EarningsStatement? {
        if case let .parsed(statement) = self { return statement }
        return nil
    }
}

/// What one imported statement month looks like against the master log.
///
/// `allocatedPay` is the sum of that month's archive payouts **after**
/// `StatementReconciler` has spread the statement total over them, so when the
/// month has archive rows it equals `total`. `loggedLivePay` is the accepted
/// shortcut pay logged in the same month, which the web app adds on top of the
/// statement total instead of subtracting it — documented defect **B1**, shown
/// here rather than corrected.
public struct StatementMonthSummary: Equatable, Sendable {
    public var month: String
    public var total: Double
    public var payouts: Int
    public var archiveRows: Int
    public var loggedRows: Int
    public var allocatedPay: Double
    public var loggedLivePay: Double

    public init(
        month: String,
        total: Double,
        payouts: Int,
        archiveRows: Int,
        loggedRows: Int,
        allocatedPay: Double,
        loggedLivePay: Double
    ) {
        self.month = month
        self.total = total
        self.payouts = payouts
        self.archiveRows = archiveRows
        self.loggedRows = loggedRows
        self.allocatedPay = allocatedPay
        self.loggedLivePay = loggedLivePay
    }
}

/// The pure half of the statement-import screen: classify submitted text and
/// describe what each statement month did to the log.
///
/// No file access, no PDFKit, no clock, no network — the app layer reads the
/// PDF and writes the file, this decides what the screen should say.
public enum StatementImporter {

    /// `stmParse()`, plus the two failure states the web app reports with a
    /// toast. Whitespace-only text counts as empty, so a blank paste never
    /// reaches the parser.
    public static func outcome(text: String, source: StatementImportSource) -> StatementImportOutcome {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return .emptyText(source) }
        guard let statement = StatementParser.parse(text) else { return .unreadable(source) }
        return .parsed(statement)
    }

    /// One row per stored statement month, newest first.
    ///
    /// Uses the same `adjust()` port the rest of the pipeline uses, so the
    /// allocated figures here cannot drift from what the analytics consume.
    public static func summaries(book: StatementBook, rows: [LogRow]) -> [StatementMonthSummary] {
        let allocated = StatementReconciler.allocate(rows, monthly: book.monthly)

        return book.statements.keys.sorted(by: >).compactMap { month -> StatementMonthSummary? in
            guard let statement = book.statements[month] else { return nil }

            var archiveRows = 0
            var loggedRows = 0
            var allocatedPay = 0.0
            var loggedLivePay = 0.0

            for (index, row) in rows.enumerated() where String(row.date.prefix(7)) == month {
                if row.isArchive {
                    archiveRows += 1
                    allocatedPay += allocated[index].numericPayout
                } else if row.choiceTook {
                    loggedRows += 1
                    loggedLivePay += row.numericPayout
                }
            }

            return StatementMonthSummary(
                month: month,
                total: statement.total,
                payouts: statement.payouts,
                archiveRows: archiveRows,
                loggedRows: loggedRows,
                allocatedPay: allocatedPay,
                loggedLivePay: loggedLivePay
            )
        }
    }
}

/// Raised when a stored document was written by a newer app version.
///
/// Fail-closed on purpose: the caller must not rewrite a file it cannot read,
/// because that would silently discard earnings history.
public enum StoreDocumentError: Error, Equatable {
    case unsupportedVersion(Int)
}

/// The on-disk shape of the statement store: `{schemaVersion, statements,
/// monthly}`.
///
/// It mirrors `StatementBook` exactly — the statement records and the web app's
/// `settings.monthly` map — because `takeStm()` writes both and reconcile reads
/// the second. Decoding an unknown `schemaVersion` throws rather than guessing.
public struct StatementStoreDocument: Equatable, Sendable {
    public static let currentVersion = 1

    public var statements: [String: EarningsStatement]
    public var monthly: [String: StatementMonth]

    public init(
        statements: [String: EarningsStatement] = [:],
        monthly: [String: StatementMonth] = [:]
    ) {
        self.statements = statements
        self.monthly = monthly
    }

    public init(book: StatementBook) {
        self.statements = book.statements
        self.monthly = book.monthly
    }

    public var book: StatementBook {
        StatementBook(statements: statements, monthly: monthly)
    }
}

extension StatementStoreDocument: Codable {
    private enum CodingKeys: String, CodingKey {
        case schemaVersion
        case statements
        case monthly
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let version = try container.decode(Int.self, forKey: .schemaVersion)
        guard version == Self.currentVersion else {
            throw StoreDocumentError.unsupportedVersion(version)
        }
        self.statements = try container.decode([String: EarningsStatement].self, forKey: .statements)
        self.monthly = try container.decode([String: StatementMonth].self, forKey: .monthly)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(Self.currentVersion, forKey: .schemaVersion)
        try container.encode(statements, forKey: .statements)
        try container.encode(monthly, forKey: .monthly)
    }
}

/// The on-disk shape of the master log: `{schemaVersion, text}`.
///
/// The log stays a pipe table (a decision already made for this app), and it is
/// normalised through the web app's own `masterLog()` on the way in, so saving
/// the same text twice is idempotent and unreadable rows are dropped at the
/// boundary rather than at read time.
public struct MasterLogDocument: Equatable, Sendable {
    public static let currentVersion = 1

    public private(set) var text: String

    public init(text: String) {
        self.text = MasterLog.normalize(text)
    }

    /// `logRows()`.
    public var rowCount: Int {
        MasterLog.rowCount(text)
    }

    /// Rows the reconciler can re-price (Source is `archive`).
    public var archiveRowCount: Int {
        text
            .components(separatedBy: "\n")
            .dropFirst(2)
            .filter { MasterLog.isArchiveLine($0) }
            .count
    }
}

extension MasterLogDocument: Codable {
    private enum CodingKeys: String, CodingKey {
        case schemaVersion
        case text
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let version = try container.decode(Int.self, forKey: .schemaVersion)
        guard version == Self.currentVersion else {
            throw StoreDocumentError.unsupportedVersion(version)
        }
        self.text = try container.decode(String.self, forKey: .text)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(Self.currentVersion, forKey: .schemaVersion)
        try container.encode(text, forKey: .text)
    }
}
