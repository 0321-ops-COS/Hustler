import Foundation

/// `adjust()` from `index.html:474`: a statement's monthly total replaces the
/// estimated pay of that month's archive rows.
///
/// This is a faithful port, quirks included:
///
/// - **Only `archive` rows are re-priced.** Accepted shortcut rows keep their own
///   pay, so a month's full statement total is spread over its archive rows even
///   when shortcut deliveries for the same month are in the log. That is
///   documented defect **B1**: summed month gross can exceed the statement
///   (statement $1,000 + shortcut pay $250 → $1,250). The port preserves it
///   deliberately and does not subtract shortcut pay.
/// - The month key is the first seven characters of the row's date, so a row
///   with a malformed date forms its own key and normally goes untouched.
/// - Allocation is in integer cents by minutes, using the largest-remainder
///   method, so the parts always add up to the statement total exactly.
/// - Remainder ties keep log order, matching JavaScript's stable sort.
/// - Miles are re-split by the same proportions only when the statement carries
///   a mileage figure greater than zero; otherwise the log's miles are kept.
/// - `Net` and `Hourly` cells are not rewritten. Archive rows leave `Net` blank,
///   so the renderer recomputes net from the adjusted payout.
public enum StatementReconciler {

    public static func allocate(_ rows: [LogRow], monthly: [String: StatementMonth]) -> [LogRow] {
        var minutesByMonth: [String: Double] = [:]
        var indicesByMonth: [String: [Int]] = [:]

        for (index, row) in rows.enumerated() where row.isArchive {
            let key = monthKey(row.date)
            minutesByMonth[key, default: 0] += row.numericMinutes
            indicesByMonth[key, default: []].append(index)
        }

        var centsByIndex: [Int: Int] = [:]

        for key in indicesByMonth.keys {
            guard let statement = monthly[key],
                  let totalMinutes = minutesByMonth[key],
                  totalMinutes != 0,
                  statement.total.isFinite
            else { continue }

            let indices = indicesByMonth[key] ?? []
            let totalCents = jsRound(statement.total * 100)
            guard totalCents.isFinite, abs(totalCents) < 9e15 else { continue }

            let exact: [Double] = indices.map { totalCents * rows[$0].numericMinutes / totalMinutes }
            guard exact.allSatisfy({ $0.isFinite && abs($0) < 9e15 }) else { continue }

            var cents: [Int] = []
            cents.reserveCapacity(exact.count)
            for value in exact {
                cents.append(Int(value.rounded(.down)))
            }
            let allocated = cents.reduce(0, +)
            let remainder = Int(max(0, totalCents - Double(allocated)))

            // Descending fractional part, original order on a tie.
            //
            // This is written out step by step because the chained
            // `enumerated().map().sorted()` form exhausted the type checker's
            // budget on the Apple toolchain (Swift 6.3.3) even though it built
            // with the local 6.0.3 Linux toolchain. Keep it explicit.
            var order: [(fraction: Double, offset: Int)] = []
            order.reserveCapacity(exact.count)
            for (offset, value) in exact.enumerated() {
                let floorValue = value.rounded(.down)
                order.append((fraction: value - floorValue, offset: offset))
            }
            order.sort { left, right in
                if left.fraction == right.fraction { return left.offset < right.offset }
                return left.fraction > right.fraction
            }

            for entry in order.prefix(min(indices.count, remainder)) {
                cents[entry.offset] += 1
            }
            for (offset, index) in indices.enumerated() {
                centsByIndex[index] = cents[offset]
            }
        }

        var output = rows
        for (index, cents) in centsByIndex {
            let key = monthKey(rows[index].date)
            guard let statement = monthly[key],
                  let totalMinutes = minutesByMonth[key],
                  totalMinutes != 0
            else { continue }

            output[index].payout = JsNumber.toFixed(Double(cents) / 100, places: 2)
            if statement.miles > 0 {
                let share = rows[index].numericMinutes / totalMinutes
                output[index].miles = JsNumber.toFixed(statement.miles * share, places: 1)
            }
        }
        return output
    }

    static func monthKey(_ date: String) -> String {
        String(date.prefix(7))
    }

    /// `Math.round`: ties go up, unlike Swift's `.rounded()`, which goes away
    /// from zero (`Math.round(-0.5)` is `0`, `.rounded()` is `-1`).
    static func jsRound(_ value: Double) -> Double {
        guard value.isFinite else { return value }
        return (value + 0.5).rounded(.down)
    }
}
