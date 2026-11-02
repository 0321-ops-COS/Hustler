import Foundation

/// One parsed earnings statement, ported from `stmParse()` (`index.html:453`).
///
/// Only three things are extracted, because only three are read from page one:
/// the statement month, the total payout and the payout count. `month` is the
/// web app's `yyyy-MM` key.
public struct EarningsStatement: Codable, Equatable, Sendable {
    public let month: String
    public let total: Double
    public let payouts: Int

    public init(month: String, total: Double, payouts: Int) {
        self.month = month
        self.total = total
        self.payouts = payouts
    }
}

/// One entry of the web app's `settings.monthly` map, which is stored as
/// `[total, miles]`.
///
/// `miles` is a statement mileage figure when the user has one. The app keeps
/// the previous value when a statement for the same month is imported again, and
/// `0` means "no mileage figure", in which case reconciliation leaves the log's
/// miles untouched.
public struct StatementMonth: Codable, Equatable, Sendable {
    public var total: Double
    public var miles: Double

    public init(total: Double, miles: Double = 0) {
        self.total = total
        self.miles = miles
    }
}

/// `stmParse()`: the web app's three regular expressions, unchanged.
///
/// Compatibility details that are part of the contract, not accidents:
/// - month names are case-sensitive and exactly one space is required before the
///   year, so `October  2026 Statement` and `october 2026 Statement` do not parse;
/// - the total needs exactly two decimals, so `$1,234` and `$1,234.5` do not parse;
/// - `Payouts (n)` is optional; without it a statement parses with `payouts: 0`;
/// - the first match of each pattern wins, wherever it sits on the page.
public enum StatementParser {

    static let monthNames = [
        "January", "February", "March", "April", "May", "June",
        "July", "August", "September", "October", "November", "December"
    ]

    // Constant patterns; a failure here is a programming error, and the tests
    // exercise every branch.
    private static let monthExpression = try! NSRegularExpression(
        pattern: "(" + monthNames.joined(separator: "|") + ") ([0-9]{4}) Statement"
    )
    private static let totalExpression = try! NSRegularExpression(
        pattern: "Total Payouts\\s*\\$([0-9,]+\\.[0-9]{2})"
    )
    private static let countExpression = try! NSRegularExpression(
        pattern: "Payouts \\(([0-9]+)\\)"
    )

    public static func parse(_ text: String) -> EarningsStatement? {
        guard let monthMatch = firstMatch(monthExpression, in: text),
              let nameRange = Range(monthMatch.range(at: 1), in: text),
              let yearRange = Range(monthMatch.range(at: 2), in: text),
              let totalMatch = firstMatch(totalExpression, in: text),
              let totalRange = Range(totalMatch.range(at: 1), in: text)
        else { return nil }

        let name = String(text[nameRange])
        guard let index = monthNames.firstIndex(of: name) else { return nil }

        var payouts = 0
        if let countMatch = firstMatch(countExpression, in: text),
           let countRange = Range(countMatch.range(at: 1), in: text),
           let count = Int(String(text[countRange])) {
            payouts = count
        }

        let number = index + 1
        let month = String(text[yearRange]) + "-" + (number < 10 ? "0\(number)" : "\(number)")
        return EarningsStatement(
            month: month,
            total: Money.parse(String(text[totalRange])),
            payouts: payouts
        )
    }

    private static func firstMatch(_ expression: NSRegularExpression, in text: String) -> NSTextCheckingResult? {
        expression.firstMatch(in: text, options: [], range: NSRange(text.startIndex..., in: text))
    }
}

/// `takeStm()`: the statement store plus its `settings.monthly` write-through.
///
/// The web app keeps a statement month in two places: the statement record
/// (`STM`, month → total + payout count) and the settings map
/// (`S.monthly`, month → `[total, miles]`) that reconciliation reads. Importing
/// writes both, and re-importing a month keeps whatever miles were already in
/// settings. If nothing parses, nothing is written at all and the caller should
/// offer the paste box.
///
/// Everything here is in-memory: this type performs no file or network I/O, so
/// statement data stays wherever the caller stores it.
public struct StatementBook: Equatable, Sendable {
    public private(set) var statements: [String: EarningsStatement]
    public private(set) var monthly: [String: StatementMonth]

    public init(
        statements: [String: EarningsStatement] = [:],
        monthly: [String: StatementMonth] = [:]
    ) {
        self.statements = statements
        self.monthly = monthly
    }

    /// Parses every text, then writes all known statements into `monthly`.
    /// Returns how many texts parsed (`got` in `takeStm`); `0` means the book
    /// was not modified.
    @discardableResult
    public mutating func take(_ texts: [String]) -> Int {
        var parsed: [EarningsStatement] = []
        for text in texts {
            if let statement = StatementParser.parse(text) {
                parsed.append(statement)
            }
        }
        guard !parsed.isEmpty else { return 0 }

        for statement in parsed {
            statements[statement.month] = statement
        }
        // `Object.values(STM).forEach(...)` — every known month is refreshed,
        // not only the ones in this import.
        for statement in statements.values {
            let existingMiles = monthly[statement.month]?.miles ?? 0
            monthly[statement.month] = StatementMonth(total: statement.total, miles: existingMiles)
        }
        return parsed.count
    }
}
