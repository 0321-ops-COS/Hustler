import Foundation

/// The web app's parsed monthly DoorDash statement, keyed by YYYY-MM.
public struct MonthlyStatement: Codable, Equatable, Sendable {
    public let month: String
    public let totalPayouts: Double
    public let payoutCount: Int

    public init(month: String, totalPayouts: Double, payoutCount: Int) {
        self.month = month
        self.totalPayouts = totalPayouts
        self.payoutCount = payoutCount
    }
}

/// Parses the same fields as the web app's stmParse(): statement month,
/// "Total Payouts $x.xx", and optional "Payouts (n)" from page-one text.
public enum StatementParser {
    private static let monthPattern = "(January|February|March|April|May|June|July|August|September|October|November|December) (\\d{4}) Statement"
    private static let totalPattern = "Total Payouts\\s*\\$([\\d,]+\\.\\d\\d)"
    private static let countPattern = "Payouts \\((\\d+)\\)"
    private static let months = [
        "January", "February", "March", "April", "May", "June",
        "July", "August", "September", "October", "November", "December"
    ]

    public static func parse(_ text: String) -> MonthlyStatement? {
        guard let monthMatch = firstMatch(monthPattern, in: text),
              monthMatch.count > 2,
              let monthIndex = months.firstIndex(of: monthMatch[1]),
              let year = Int(monthMatch[2]),
              let totalMatch = firstMatch(totalPattern, in: text),
              totalMatch.count > 1,
              let total = Money.parseOptional(totalMatch[1])
        else { return nil }

        let count = firstMatch(countPattern, in: text).flatMap { $0.count > 1 ? Int($0[1]) : nil } ?? 0
        let month = String(format: "%04d-%02d", year, monthIndex + 1)
        return MonthlyStatement(month: month, totalPayouts: total, payoutCount: count)
    }

    private static func firstMatch(_ pattern: String, in text: String) -> [String]? {
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text))
        else { return nil }
        return (0..<match.numberOfRanges).compactMap { index in
            guard let range = Range(match.range(at: index), in: text) else { return nil }
            return String(text[range])
        }
    }
}

/// Ports the web app's adjust(statements) allocation. Statement totals are
/// distributed only across archive rows in the matching month, weighted by
/// minutes. Integer cents are floored first; leftover cents go to the largest
/// fractional remainders, with original row order breaking ties. A positive
/// monthly miles value is allocated with the same minute weights to one decimal.
public enum StatementReconciler {
    public static func adjustedRows(
        _ rows: [LogRow],
        statements: [String: MonthlyStatement],
        monthlyMiles: [String: Double] = [:]
    ) -> [LogRow] {
        var minutesByMonth: [String: Double] = [:]
        var indexesByMonth: [String: [Int]] = [:]

        for (index, row) in rows.enumerated() where row.isArchive {
            let month = String(row.date.prefix(7))
            guard isMonthKey(month) else { continue }
            minutesByMonth[month, default: 0] += Money.parse(row.minutes)
            indexesByMonth[month, default: []].append(index)
        }

        var payoutByIndex: [Int: Int] = [:]
        for (month, indexes) in indexesByMonth {
            guard let statement = statements[month],
                  let totalMinutes = minutesByMonth[month],
                  totalMinutes != 0
            else { continue }

            let totalCents = Int(floor(statement.totalPayouts * 100 + 0.5))
            let exactCents = indexes.map { Double(totalCents) * Money.parse(rows[$0].minutes) / totalMinutes }
            let flooredCents = exactCents.map { Int(floor($0)) }
            var remainder = totalCents - flooredCents.reduce(0, +)
            let priority = exactCents.indices.sorted {
                let left = exactCents[$0] - Double(flooredCents[$0])
                let right = exactCents[$1] - Double(flooredCents[$1])
                return left == right ? $0 < $1 : left > right
            }
            var allocated = flooredCents
            for slot in priority where remainder > 0 {
                allocated[slot] += 1
                remainder -= 1
            }
            for (slot, index) in indexes.enumerated() {
                payoutByIndex[index] = allocated[slot]
            }
        }

        return rows.enumerated().map { index, original in
            guard original.isArchive else { return original }
            let month = String(original.date.prefix(7))
            guard let totalMinutes = minutesByMonth[month],
                  totalMinutes != 0,
                  statements[month] != nil
            else { return original }

            var row = original
            if let cents = payoutByIndex[index] {
                row.payout = JsNumber.toFixed(Double(cents) / 100, places: 2)
            }
            if let miles = monthlyMiles[month], miles > 0 {
                let fraction = Money.parse(original.minutes) / totalMinutes
                row.miles = JsNumber.toFixed(miles * fraction, places: 1)
            }
            return row
        }
    }

    private static func isMonthKey(_ value: String) -> Bool {
        let parts = value.split(separator: "-", omittingEmptySubsequences: false)
        guard parts.count == 2, parts[0].count == 4, parts[1].count == 2,
              let month = Int(parts[1]) else { return false }
        return parts[0].allSatisfy(\.isNumber) && (1...12).contains(month)
    }
}
