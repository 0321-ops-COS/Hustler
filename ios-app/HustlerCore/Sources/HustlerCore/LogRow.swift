import Foundation

/// One parsed master-log row, in the web app's field names.
///
/// Values stay as text because the web app keeps the raw cells and re-parses
/// them with `num()` at each use; keeping that split is what makes round-trips
/// and handoff compatibility byte-identical.
public struct LogRow: Equatable, Sendable {
    public var date: String
    public var time: String
    public var zone: String
    public var payout: String
    public var miles: String
    public var items: String
    public var perMile: String
    public var net: String
    public var hourly: String
    public var verdict: String
    public var rate: String
    public var choice: String
    public var slack: String
    public var minutes: String
    public var source: String

    public init(
        date: String = "",
        time: String = "",
        zone: String = "",
        payout: String = "",
        miles: String = "",
        items: String = "",
        perMile: String = "",
        net: String = "",
        hourly: String = "",
        verdict: String = "",
        rate: String = "",
        choice: String = "",
        slack: String = "",
        minutes: String = "",
        source: String = ""
    ) {
        self.date = date
        self.time = time
        self.zone = zone
        self.payout = payout
        self.miles = miles
        self.items = items
        self.perMile = perMile
        self.net = net
        self.hourly = hourly
        self.verdict = verdict
        self.rate = rate
        self.choice = choice
        self.slack = slack
        self.minutes = minutes
        self.source = source
    }

    public var numericPayout: Double { Money.parse(payout) }
    public var numericMiles: Double { Money.parse(miles) }
    public var numericItems: Double { Money.parse(items) }
    public var numericMinutes: Double { Money.parse(minutes) }
    public var numericRate: Double { Money.parse(rate) }
    public var numericNet: Double { Money.parse(net) }
    public var numericHourly: Double { Money.parse(hourly) }

    public var isArchive: Bool { source == "archive" }
    public var verdictIsYes: Bool { TextPredicates.yes(verdict) }
    public var choiceTook: Bool { TextPredicates.took(choice) }

    /// `"date time"`, with no trailing space when the time is absent.
    public var dateWithTime: String {
        time.isEmpty ? date : date + " " + time
    }

    /// The 14 cells in `MasterLog.header` order.
    public var cells: [String] {
        [dateWithTime, payout, miles, items, perMile, net, hourly, verdict,
         rate, choice, slack, zone, minutes, source]
    }

    /// Serialises to one pipe-table row, matching the web app's `toLog` shape.
    public var serializedLine: String {
        "| " + cells.joined(separator: " | ") + " |"
    }
}
