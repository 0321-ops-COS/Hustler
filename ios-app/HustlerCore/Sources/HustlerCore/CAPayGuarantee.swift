import Foundation

/// California pay-guarantee maths, ported from `caAuto()`, `caMerge()`,
/// `caEst()`, `caPace()` and `caProject()` (`index.html:606-618`). Weeks are
/// `PeriodGrouping` week keys (the Monday); only accepted rows count, and an
/// entered value wins only when above zero.
public enum CAPayGuarantee {
    /// `S.caWage`, `S.caPct`, `S.caMile`; defaults are the web app's `DEF`.
    public struct Rates: Equatable, Sendable {
        public var wage: Double, percent: Double, mile: Double
        public init(wage: Double = 16.90, percent: Double = 120, mile: Double = 0.37) {
            self.wage = wage; self.percent = percent; self.mile = mile
        }
        public init(_ settings: AppSettings) {
            self.init(wage: settings.caWage, percent: settings.caPct, mile: settings.caMile)
        }
        /// `S.caPct/100*S.caWage`: the guarantee per active hour.
        public var perHour: Double { percent / 100 * wage }
    }
    public struct AutoFigures: Equatable, Sendable {
        public var pay: Double, hours: Double, miles: Double
        public var acceptedOffers: Int
        public init(pay: Double = 0, hours: Double = 0, miles: Double = 0, acceptedOffers: Int = 0) {
            self.pay = pay; self.hours = hours; self.miles = miles
            self.acceptedOffers = acceptedOffers
        }
    }
    public struct Entry: Equatable, Sendable {
        public var pay: Double?, hours: Double?, miles: Double?
        public init(pay: Double? = nil, hours: Double? = nil, miles: Double? = nil) {
            self.pay = pay; self.hours = hours; self.miles = miles
        }
    }
    /// `caMerge(k)`; the `…FromLog` flags are the web app's `au` flags.
    public struct Merged: Equatable, Sendable {
        public var pay: Double, hours: Double, miles: Double
        public var acceptedOffers: Int
        public var payFromLog: Bool, hoursFromLog: Bool, milesFromLog: Bool
    }
    /// `caEst(e, logMiles)`.
    public struct Estimate: Equatable, Sendable {
        public enum MilesSource: String, Sendable { case entered, fromLog }
        public var guarantee: Double, miles: Double, adjustment: Double
        public var milesSource: MilesSource
    }
    /// `caPace(wk)`.
    public struct Pace: Equatable, Sendable {
        public var payPerHour: Double, milesPerHour: Double
        public var weeks: Int
        public var averageHours: Double
    }
    /// `caProject(A, pace, h, rate, mile)`.
    public struct Projection: Equatable, Sendable {
        public var addedPay: Double, addedMiles: Double, hours: Double, miles: Double
        public var pay: Double, guarantee: Double, adjustment: Double, total: Double
        public var soFarGuarantee: Double, soFarAdjustment: Double
    }

    /// `caAuto(k)`. Unlike `caPace()` the web app re-checks nothing, but an
    /// unreadable date never matches a Monday key anyway.
    public static func autoFigures(rows: [LogRow], weekKey: String) -> AutoFigures {
        var figures = AutoFigures()
        for row in rows where row.choiceTook && PeriodGrouping.key(for: row.date, period: .week) == weekKey {
            figures.pay += row.numericPayout; figures.hours += row.numericMinutes / 60
            figures.miles += row.numericMiles; figures.acceptedOffers += 1
        }
        return figures
    }
    /// `caMerge(k)` for one already-collected week.
    public static func merged(_ auto: AutoFigures, entry: Entry?) -> Merged {
        func pick(_ entered: Double?, _ automatic: Double) -> (Double, Bool) {
            if let entered, entered > 0 { return (entered, false) }
            return (automatic, true)
        }
        let pay = pick(entry?.pay, auto.pay), hours = pick(entry?.hours, auto.hours)
        let miles = pick(entry?.miles, auto.miles)
        return Merged(
            pay: pay.0, hours: hours.0, miles: miles.0, acceptedOffers: auto.acceptedOffers,
            payFromLog: pay.1, hoursFromLog: hours.1, milesFromLog: miles.1
        )
    }
    /// `caMerge(k)` reading that week's entry out of `CA`.
    public static func merged(rows: [LogRow], weekKey: String, entries: [String: Entry]) -> Merged {
        merged(autoFigures(rows: rows, weekKey: weekKey), entry: entries[weekKey])
    }
    /// `caEst(e, logMiles)`. Miles fall back to `loggedMiles` when the merged
    /// figure is not above zero; the adjustment never drops below zero.
    public static func estimate(_ merged: Merged, loggedMiles: Double, rates: Rates) -> Estimate {
        let miles = merged.miles > 0 ? merged.miles : loggedMiles
        let guarantee = rates.perHour * merged.hours + rates.mile * miles
        return Estimate(
            guarantee: guarantee, miles: miles, adjustment: max(0, guarantee - merged.pay),
            milesSource: merged.miles > 0 && !merged.milesFromLog ? .entered : .fromLog
        )
    }
    /// `caPace(wk)`: the last four weeks at or before `weekKey` with at least
    /// one active hour, summed. Keys are compared as text, as the web app does.
    public static func pace(rows: [LogRow], weekKey: String) -> Pace? {
        var buckets: [String: (pay: Double, hours: Double, miles: Double)] = [:]
        for row in rows where row.choiceTook {
            guard MasterLog.startsWithISODate(row.date) else { continue }
            let key = PeriodGrouping.key(for: row.date, period: .week)
            var bucket = buckets[key] ?? (0, 0, 0)
            bucket.pay += row.numericPayout; bucket.hours += row.numericMinutes / 60
            bucket.miles += row.numericMiles
            buckets[key] = bucket
        }
        let keys = buckets.keys
            .filter { $0 <= weekKey && (buckets[$0]?.hours ?? 0) >= 1 }.sorted().suffix(4)
        guard !keys.isEmpty else { return nil }
        var pay = 0.0, hours = 0.0, miles = 0.0
        for key in keys {
            let bucket = buckets[key] ?? (0, 0, 0)
            pay += bucket.pay; hours += bucket.hours; miles += bucket.miles
        }
        return Pace(
            payPerHour: pay / hours, milesPerHour: miles / hours,
            weeks: keys.count, averageHours: hours / Double(keys.count)
        )
    }
    /// `caProject(A, pace, h, rate, mile)`. With no pace the extra hours add no
    /// pay and no miles but still raise the guarantee's hour term; `renderCA()`
    /// never shows that because it passes zero extra hours without a pace.
    public static func project(
        _ merged: Merged, pace: Pace?, extraHours: Double, rates: Rates
    ) -> Projection {
        let addedPay = pace.map { $0.payPerHour * extraHours } ?? 0
        let addedMiles = pace.map { $0.milesPerHour * extraHours } ?? 0
        let hours = merged.hours + extraHours, miles = merged.miles + addedMiles
        let pay = merged.pay + addedPay, guarantee = rates.perHour * hours + rates.mile * miles
        let adjustment = max(0, guarantee - pay)
        let soFarGuarantee = rates.perHour * merged.hours + rates.mile * merged.miles
        return Projection(
            addedPay: addedPay, addedMiles: addedMiles, hours: hours, miles: miles,
            pay: pay, guarantee: guarantee, adjustment: adjustment, total: pay + adjustment,
            soFarGuarantee: soFarGuarantee, soFarAdjustment: max(0, soFarGuarantee - merged.pay)
        )
    }
}
