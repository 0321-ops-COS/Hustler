import Foundation

/// One week's California entry (`CA[k]`): missing or non-positive means "not entered".
public struct CAWeekEntry: Codable, Equatable, Sendable {
    public var pay: Double?
    public var hours: Double?
    public var miles: Double?
    public init(pay: Double? = nil, hours: Double? = nil, miles: Double? = nil) {
        self.pay = pay; self.hours = hours; self.miles = miles
    }
    public var mergedEntry: CAPayGuarantee.Entry { .init(pay: pay, hours: hours, miles: miles) }
}

/// The entry form's text fields, parsed with the web app's `num()`.
public struct CAEntryInput: Equatable, Sendable {
    public var pay: String, hours: String, miles: String
    public init(pay: String = "", hours: String = "", miles: String = "") {
        self.pay = pay; self.hours = hours; self.miles = miles
    }
    public var entry: CAWeekEntry {
        CAWeekEntry(pay: Money.parse(pay), hours: Money.parse(hours), miles: Money.parse(miles))
    }
}

/// `renderCA()` (`index.html:619-648`) as values instead of HTML; `CAPayGuarantee` does the maths.
public struct CAGuaranteeViewModel: Equatable, Sendable {
    public struct TableRow: Equatable, Sendable {
        public var label, soFar, added, total: String
    }
    public struct Week: Equatable, Sendable {
        public var weekKey: String
        public var merged: CAPayGuarantee.Merged
        public var estimate: CAPayGuarantee.Estimate
    }

    public static let heading = "California pay guarantee"
    public static let notEnoughDataTitle = "Not enough data"
    public static let notEnoughDataHint = "No accepted offers with active time in your log yet, so there is nothing to project. Enter this week's hours and pay under your California entries, or log offers."
    public static let disclaimer = "Offer payouts can include tips, which makes any figure here a little high or low. Everything below is an estimate, not a guaranteed payout."
    public static let noPaceHint = "Not enough history to project a pace yet, so only the actual so far is shown."
    public static let tableHeaders = ["", "So far", "Added", "Week total"]
    public static let tableSubheaders = ["", "actual", "projected", "estimate"]
    public static let maxWeekHours = 84.0  // CAMAX
    public var isNotEnoughData: Bool
    public var weekKey, weekStart, weekEnd: String
    public var daysLeft: Int
    public var headerHint: String
    public var tableRows: [TableRow]
    public var offersHint: String, paceHint: String, equation: String, sliderLabel: String
    public var extraHours: Int, maxExtraHours: Int
    public var thisWeek: Week
    /// The weeks `caPace()` counts, oldest first; the current week is included.
    public var recentWeeks: [Week]
    public var pace: CAPayGuarantee.Pace?
    /// `renderCA()` for `today` (`yyyy-MM-dd`); `extraHours` stands in for the
    /// slider and defaults to the pace's average week, capped by `CAMAX`.
    public static func make(
        rows: [LogRow], settings: AppSettings, today: String, extraHours: Int? = nil
    ) -> CAGuaranteeViewModel {
        let rates = CAPayGuarantee.Rates(settings)
        let weekKey = PeriodGrouping.key(for: today, period: .week)
        let entries = settings.caEntries.mapValues { $0.mergedEntry }
        let auto = CAPayGuarantee.autoFigures(rows: rows, weekKey: weekKey)
        let merged = CAPayGuarantee.merged(auto, entry: entries[weekKey])
        let pace = CAPayGuarantee.pace(rows: rows, weekKey: weekKey)
        let start = PeriodGrouping.parse(weekKey)
        let end = start.map { PeriodGrouping.civilFromDays(PeriodGrouping.daysFromCivil($0.year, $0.month, $0.day) + 6) }
        let weekStart = start.map(shortDate) ?? weekKey, weekEnd = end.map(shortDate) ?? weekKey
        let daysLeft = daysBetween(today, and: end)
        let headerHint = "Pay week \(weekStart) to \(weekEnd) (Monday to Sunday). \(daysLeft) day\(daysLeft == 1 ? "" : "s") left after today."
        let ready = merged.hours > 0 || pace != nil
        let remMax = ready && pace != nil ? max(0, Int(floor(min(Self.maxWeekHours - merged.hours, 12 * Double(daysLeft + 1))))) : 0
        let slider: Int = {
            guard let pace, remMax > 0 else { return 0 }
            let start = min(remMax, max(0, Int((pace.averageHours - merged.hours).rounded())))
            return min(remMax, max(0, extraHours ?? start))
        }()
        let projection = CAPayGuarantee.project(merged, pace: pace, extraHours: Double(slider), rates: rates)
        func money(_ value: Double) -> String { Money.format(value) }
        var tableRows: [TableRow] = []
        if ready {
            // Without a pace the web app draws no slider, so the added column is `--`.
            func added(_ text: String) -> String { pace == nil ? "--" : "+" + text }
            tableRows = [
                TableRow(label: "Active time", soFar: clock(merged.hours), added: added(clock(Double(slider))), total: clock(projection.hours)),
                TableRow(label: "Miles", soFar: whole(merged.miles), added: added(whole(projection.addedMiles)), total: whole(projection.miles)),
                TableRow(label: "DoorDash pay", soFar: money(merged.pay), added: added(money(projection.addedPay)), total: money(projection.pay)),
                TableRow(label: "Guarantee level", soFar: money(projection.soFarGuarantee), added: "", total: money(projection.guarantee)),
                TableRow(label: "Adjustment", soFar: money(projection.soFarAdjustment), added: "", total: money(projection.adjustment)),
                TableRow(label: "Pay + adjustment", soFar: money(merged.pay + projection.soFarAdjustment), added: "", total: money(projection.total))
            ]
        }
        let offersHint = "So far: \(merged.acceptedOffers) accepted offer\(merged.acceptedOffers == 1 ? "" : "s") this week; active time and miles \(merged.hoursFromLog ? "from your log, time is estimated" : "entered by you")."
        let paceHint = pace.map {
            "Rest of the week: move the slider to try different extra active hours. Pace used: \(money($0.payPerHour)) pay and "
                + "\(JsNumber.toFixed($0.milesPerHour, places: 1)) miles per active hour (\($0.weeks) week\($0.weeks == 1 ? "" : "s") of your log). "
                + "The slider tops out at \(remMax) h: \(Int(Self.maxWeekHours)) h a week and 12 h a day."
        } ?? Self.noPaceHint
        let equation = "(\(money(rates.perHour)) × \(JsNumber.toFixed(projection.hours, places: 1)) h) + "
            + "(\(money(rates.mile)) × \(JsNumber.toFixed(projection.miles, places: 0)) mi) = \(money(projection.guarantee))<br>"
            + "\(money(projection.guarantee)) − \(money(projection.pay)) pay = \(money(projection.adjustment)) adjustment (never below $0)"
        let weeks = recentWeekKeys(rows: rows, weekKey: weekKey).map { key -> Week in
            let weekAuto = CAPayGuarantee.autoFigures(rows: rows, weekKey: key)
            let weekMerged = CAPayGuarantee.merged(weekAuto, entry: entries[key])
            return Week(weekKey: key, merged: weekMerged,
                        estimate: CAPayGuarantee.estimate(weekMerged, loggedMiles: weekAuto.miles, rates: rates))
        }
        return CAGuaranteeViewModel(
            isNotEnoughData: !ready, weekKey: weekKey, weekStart: weekStart, weekEnd: weekEnd,
            daysLeft: daysLeft, headerHint: headerHint, tableRows: tableRows, offersHint: offersHint,
            paceHint: paceHint, equation: equation, sliderLabel: "+\(slider) h",
            extraHours: slider, maxExtraHours: remMax,
            thisWeek: Week(weekKey: weekKey, merged: merged,
                           estimate: CAPayGuarantee.estimate(merged, loggedMiles: auto.miles, rates: rates)),
            recentWeeks: weeks, pace: pace
        )
    }

    private static func daysBetween(_ today: String, and end: PeriodGrouping.YMD?) -> Int {
        guard let todayDate = PeriodGrouping.parse(today), let end else { return 0 }
        return max(0, PeriodGrouping.daysFromCivil(end.year, end.month, end.day) - PeriodGrouping.daysFromCivil(todayDate.year, todayDate.month, todayDate.day))
    }
    private static let months = ["Jan", "Feb", "Mar", "Apr", "May", "Jun",
                                 "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"]

    private static func shortDate(_ date: PeriodGrouping.YMD) -> String {
        "\(months[min(max(date.month - 1, 0), 11)]) \(date.day)"
    }
    private static func clock(_ hours: Double) -> String {
        let wholeHours = floor(hours)
        let minutes = Int(((hours - wholeHours) * 60).rounded())
        return "\(Int(wholeHours))h \(minutes < 10 ? "0\(minutes)" : "\(minutes)")m"
    }
    private static func whole(_ value: Double) -> String { JsNumber.toFixed(value, places: 0) }

    private static func recentWeekKeys(rows: [LogRow], weekKey: String) -> [String] {
        var hours: [String: Double] = [:]
        for row in rows where row.choiceTook {
            guard MasterLog.startsWithISODate(row.date) else { continue }
            hours[PeriodGrouping.key(for: row.date, period: .week), default: 0] += row.numericMinutes / 60
        }
        return Array(hours.keys.filter { $0 <= weekKey && (hours[$0] ?? 0) >= 1 }.sorted().suffix(4))
    }
}
