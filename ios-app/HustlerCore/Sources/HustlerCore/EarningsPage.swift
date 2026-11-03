import Foundation

/// `renderEarn()` (`index.html:458`), built from the stored statements and the
/// master log. Only `archive` rows count, after `StatementReconciler` has run.
/// `Paid` is the statement total and accepted shortcut pay is neither subtracted
/// nor shown, so defect **B1** stays as the web app has it. Wording, ordering and
/// number formats are the web app's.
public struct EarningsPage: Equatable, Sendable {
    public struct Tile: Identifiable, Equatable, Sendable {
        public let label, value: String
        public let isMoney: Bool
        public var id: String { label }
    }
    public struct MonthRow: Identifiable, Equatable, Sendable {
        public let month, paid, payouts, deliveries, perDelivery, perActiveHour: String
        public var id: String { month }
        public var cells: [String] { [month, paid, payouts, deliveries, perDelivery, perActiveHour] }
    }
    public struct DayRow: Identifiable, Equatable, Sendable {
        public let day: String
        public let deliveries: Int
        /// `bar(v, max)`'s width as a fraction; zero when nothing was delivered.
        public let share: Double
        public var id: String { day }
    }

    public static let title = "Monthly statements"
    public static let hint = "Add statement PDFs on the Data page."
    public static let monthsTitle = "By month"
    public static let daysTitle = "Deliveries by day"
    public static let notesTitle = "What stands out"
    public static let monthHeaders = ["Month", "Paid", "Payouts", "Deliveries", "Per delivery", "Per active hr"]
    public static let monthHint = "Per active hour counts time from pickup to drop-off only, so it runs higher than your real hourly rate. Statements are by deposit date, so a few days of pay can land in the next month."
    public static let dayNames = ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"]

    public let tiles: [Tile], months: [MonthRow], days: [DayRow], notes: [String]

    public init(statements: StatementBook, rows: [LogRow]) {
        let keys = statements.statements.keys.sorted()
        guard !keys.isEmpty else { tiles = []; months = []; days = []; notes = []; return }

        var counts: [String: Int] = [:], minutes: [String: Double] = [:], weekdays = [Int](repeating: 0, count: 7)
        for row in StatementReconciler.allocate(rows, monthly: statements.monthly) where row.isArchive {
            let key = String(row.date.prefix(7))
            counts[key, default: 0] += 1
            minutes[key, default: 0] += row.numericMinutes
            if statements.statements[key] != nil, let day = Self.weekday(row.date) { weekdays[day] += 1 }
        }

        var total = 0.0, payouts = 0, deliveries = 0, hours = 0.0
        months = keys.compactMap { key in
            guard let statement = statements.statements[key] else { return nil }
            let count = counts[key] ?? 0, active = (minutes[key] ?? 0) / 60
            total += statement.total; payouts += statement.payouts
            deliveries += count; hours += active
            return MonthRow(
                month: key, paid: Money.format(statement.total), payouts: "\(statement.payouts)",
                deliveries: "\(count)",
                perDelivery: count > 0 ? Money.format(statement.total / Double(count)) : "--",
                perActiveHour: active > 0 ? Money.format(statement.total / active) : "--"
            )
        }

        tiles = [
            Tile(label: "Earned, \(keys.count) months", value: Money.format(total, decimals: 0), isMoney: true),
            Tile(label: "Payouts", value: "\(payouts)", isMoney: false),
            Tile(label: "Per delivery", value: deliveries > 0 ? Money.format(total / Double(deliveries)) : "--", isMoney: true),
            Tile(label: "Per active hour", value: hours > 0 ? Money.format(total / hours) : "--", isMoney: true)
        ]

        let peak = weekdays.max() ?? 0
        days = Self.dayNames.enumerated().map { index, name in
            DayRow(day: name, deliveries: weekdays[index],
                   share: peak > 0 ? Double(weekdays[index]) / Double(peak) : 0)
        }

        let ranked = keys.compactMap { key -> (String, Double)? in
            let count = counts[key] ?? 0
            guard let statement = statements.statements[key], count >= 30 else { return nil }
            return (key, statement.total / Double(count))
        }.enumerated().sorted {
            $0.element.1 == $1.element.1 ? $0.offset < $1.offset : $0.element.1 > $1.element.1
        }.map(\.element)
        var notes: [String] = []
        if ranked.count > 1 {
            notes.append("Best pay per delivery: \(ranked[0].0) at \(Money.format(ranked[0].1)). "
                + "Lowest: \(ranked[ranked.count - 1].0) at \(Money.format(ranked[ranked.count - 1].1)). "
                + "The gap is what a better offer mix is worth.")
        }
        if deliveries > 0 {
            let hi = weekdays.firstIndex(of: peak) ?? 0, lo = weekdays.firstIndex(of: weekdays.min() ?? 0) ?? 0
            notes.append("\(Self.dayNames[hi]) is your busiest day with \(weekdays[hi]) deliveries, "
                + "and \(Self.dayNames[lo]) is your quietest with \(weekdays[lo]).")
        }
        notes.append("Statements show total pay only. They don't split base pay, tips and peak pay, "
            + "and they have no miles. Logging offers with the shortcut is what shows which zones and offer types pay.")
        self.notes = notes
    }

    /// `new Date(date + "T12:00:00").getDay()`; an impossible date is `nil`, as
    /// `NaN` skips the row on the web.
    static func weekday(_ date: String) -> Int? {
        guard MasterLog.startsWithISODate(date) else { return nil }
        let parts = date.prefix(10).split(separator: "-").compactMap { Int($0) }
        guard parts.count == 3 else { return nil }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let components = DateComponents(year: parts[0], month: parts[1], day: parts[2], hour: 12)
        guard let day = calendar.date(from: components) else { return nil }
        let check = calendar.dateComponents([.year, .month, .day], from: day)
        guard check.year == parts[0], check.month == parts[1], check.day == parts[2] else { return nil }
        return calendar.component(.weekday, from: day) - 1
    }
}
