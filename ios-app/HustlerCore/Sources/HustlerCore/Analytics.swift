import Foundation

/// One row of the Zone table.
public struct ZoneTotals: Equatable, Sendable {
    public var zone: String
    public var orders: Int
    public var net: Double
    public var minutes: Double
    public var miles: Double

    /// `h ? $f(net / h) : "--"`
    public var netPerHour: Double? { minutes > 0 ? net / (minutes / 60) : nil }

    /// `m ? $f(net / m) : "--"`
    public var netPerMile: Double? { miles > 0 ? net / miles : nil }
}

/// One row of the Hour table. `hour` is the 24-hour value parsed from the row's
/// time; `label` is what the table shows (`12am`, `9am`, `12pm`, `2pm`).
public struct HourTotals: Equatable, Sendable {
    public var hour: Int
    public var orders: Int
    public var net: Double
    public var minutes: Double

    /// `h ? $f(net / h) : "--"`
    public var netPerHour: Double? { minutes > 0 ? net / (minutes / 60) : nil }

    /// `(h % 12 || 12) + (h < 12 ? "am" : "pm")`
    public var label: String {
        let display = hour % 12 == 0 ? 12 : hour % 12
        return String(display) + (hour < 12 ? "am" : "pm")
    }
}

/// One row of the Month table. Months are keyed by `yyyy-MM`, newest first.
public struct MonthTotals: Equatable, Sendable {
    public var month: String
    public var orders: Int
    public var gross: Double
    public var miles: Double
    public var net: Double
    /// `miles * taxRate` — the same figure the tax panel deducts.
    public var mileageDeduction: Double
}

/// The tax panel's four figures.
///
/// This is a **mileage deduction estimate from the log**, not tax advice and not
/// a filing calculation. It carries the web app's existing assumptions forward
/// unchanged:
/// - miles are the accepted rows' miles, so unpaid deadhead mileage is absent;
/// - the rate is a single flat dollars-per-mile setting (`taxRate`, default
///   0.70 in the app's `DEF`), never the current IRS rate;
/// - only the standard mileage deduction is modelled — no fuel, phone or other
///   expenses, no self-employment tax, no brackets, no credits;
/// - gross is accepted payouts only, so any tips bundled into a payout count as
///   income, which pushes the estimate in both directions.
public struct TaxEstimate: Equatable, Sendable {
    public var gross: Double
    public var miles: Double
    public var mileageDeduction: Double
    public var taxable: Double
}

/// The remaining read-only analytics from `analyze()` (`index.html:360-420`).
///
/// All four use **accepted** rows only and the same per-row net as the
/// Scoreboard (the row's `Net` cell when present, otherwise payout minus car
/// cost), which is why they take the settings.
public enum Analytics {

    /// Zones are ordered by net per active hour, descending, dividing by
    /// `max(1, minutes)` — the app's guard against a zero-minute zone. Ties keep
    /// first appearance, matching the web app's stable sort.
    public static func zones(_ rows: [LogRow], settings: VerdictSettings) -> [ZoneTotals] {
        var buckets: [String: (orders: Int, net: Double, minutes: Double, miles: Double)] = [:]
        var order: [String] = []

        for row in rows where row.choiceTook {
            let zone = row.zone
            guard !zone.isEmpty else { continue }
            if buckets[zone] == nil { order.append(zone) }
            var bucket = buckets[zone] ?? (0, 0, 0, 0)
            bucket.orders += 1
            bucket.net += Scoreboard.net(for: row, settings: settings)
            bucket.minutes += row.numericMinutes
            bucket.miles += row.numericMiles
            buckets[zone] = bucket
        }

        let ranked = order.enumerated().sorted { lhs, rhs in
            let left = buckets[lhs.element]!
            let right = buckets[rhs.element]!
            let leftRate = left.net / max(1, left.minutes)
            let rightRate = right.net / max(1, right.minutes)
            if leftRate == rightRate { return lhs.offset < rhs.offset }
            return leftRate > rightRate
        }

        return ranked.map { entry in
            let bucket = buckets[entry.element]!
            return ZoneTotals(
                zone: entry.element,
                orders: bucket.orders,
                net: bucket.net,
                minutes: bucket.minutes,
                miles: bucket.miles
            )
        }
    }

    /// Hour buckets, ascending. Rows whose time does not begin with an integer
    /// are skipped, matching `parseInt` returning NaN in the web app; that is
    /// why a row with no time contributes to no hour.
    public static func hours(_ rows: [LogRow], settings: VerdictSettings) -> [HourTotals] {
        var buckets: [Int: (orders: Int, net: Double, minutes: Double)] = [:]

        for row in rows where row.choiceTook {
            guard let hour = hourOf(row.time) else { continue }
            var bucket = buckets[hour] ?? (0, 0, 0)
            bucket.orders += 1
            bucket.net += Scoreboard.net(for: row, settings: settings)
            bucket.minutes += row.numericMinutes
            buckets[hour] = bucket
        }

        return buckets.keys.sorted().map { hour in
            let bucket = buckets[hour]!
            return HourTotals(hour: hour, orders: bucket.orders, net: bucket.net, minutes: bucket.minutes)
        }
    }

    /// Month buckets, newest first. Rows without a `yyyy-MM-dd` date are skipped.
    public static func months(
        _ rows: [LogRow],
        settings: VerdictSettings,
        taxRate: Double
    ) -> [MonthTotals] {
        var buckets: [String: MonthTotals] = [:]

        for row in rows where row.choiceTook {
            guard MasterLog.startsWithISODate(row.date) else { continue }
            let key = String(row.date.prefix(7))
            var bucket = buckets[key] ?? MonthTotals(
                month: key, orders: 0, gross: 0, miles: 0, net: 0, mileageDeduction: 0
            )
            bucket.orders += 1
            bucket.gross += row.numericPayout
            bucket.miles += row.numericMiles
            bucket.net += Scoreboard.net(for: row, settings: settings)
            bucket.mileageDeduction = bucket.miles * taxRate
            buckets[key] = bucket
        }

        return buckets.keys.sorted(by: >).map { buckets[$0]! }
    }

    /// `ded = miles * taxRate`, `taxable = gross - ded`.
    public static func taxEstimate(
        _ rows: [LogRow],
        settings: VerdictSettings,
        taxRate: Double
    ) -> TaxEstimate {
        var gross = 0.0
        var miles = 0.0
        for row in rows where row.choiceTook {
            gross += row.numericPayout
            miles += row.numericMiles
        }
        let deduction = miles * taxRate
        return TaxEstimate(
            gross: gross,
            miles: miles,
            mileageDeduction: deduction,
            taxable: gross - deduction
        )
    }

    /// `parseInt(time.split(":")[0])`, or `nil` where that is NaN.
    static func hourOf(_ time: String) -> Int? {
        let head = time.split(separator: ":", maxSplits: 1, omittingEmptySubsequences: false).first ?? ""
        let trimmed = head.trimmingCharacters(in: .whitespaces)
        guard let value = Int(trimmed) else { return nil }
        return value
    }
}
