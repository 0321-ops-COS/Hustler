import Foundation

/// One delivery from the web app's `ARCH` store. The master log keeps only the
/// pickup stamp, rounded minutes and city, so History needs this separately.
public struct ArchiveRow: Equatable, Hashable, Sendable, Codable {
    public var createdAt: Date
    public var pickupAt: Date?
    public var deliveredAt: Date
    public var store: String
    public var items: Double

    public init(createdAt: Date, pickupAt: Date?, deliveredAt: Date, store: String, items: Double) {
        self.createdAt = createdAt
        self.pickupAt = pickupAt
        self.deliveredAt = deliveredAt
        self.store = store
        self.items = items
    }
}

/// `renderArch()`'s output: tiles, then the month, hour, weekday and store
/// tables, in the web app's wording and order.
public struct HistoryPage: Equatable, Sendable {
    public struct Tile: Equatable, Sendable { public let value: String; public let label: String }
    public struct Month: Equatable, Sendable { public let key: String; public let deliveries: Int; public let averagePickupToDrop: String }
    public struct Bar: Equatable, Sendable { public let label: String; public let deliveries: Int; public let fractionOfMax: Double }
    public struct Store: Equatable, Sendable { public let name: String; public let deliveries: Int }

    public var tiles: [Tile] = []
    public var months: [Month] = []
    public var hours: [Bar] = []
    public var weekdays: [Bar] = []
    public var stores: [Store] = []
    /// Archive deliveries hidden by the duplicate rule. Hidden, never deleted.
    public var duplicatesHidden = 0
    /// `renderArch()` draws nothing at all with no rows left.
    public var isEmpty: Bool { tiles.isEmpty }
}

/// The fixed wording `renderArch()` writes above each table, pinned here so the
/// screen only draws strings it is given.
public enum HistoryCopy {
    public static let monthTitle = "By month"
    public static let monthHeaders = ["Month", "Deliveries", "Avg pickup to drop"]
    public static let hourTitle = "By hour (your device time)"
    public static let hourHeaders = ["Hour", "Deliveries", ""]
    public static let dayTitle = "By day of week"
    public static let dayHeaders = ["Day", "Deliveries", ""]
    public static let storeTitle = "Top stores"
    public static let storeHeaders = ["Store", "Deliveries"]
}

/// `renderArch()` plus the archive half of `dedupeArch()`, which the web app
/// runs inside `analyze()`. A delivery an accepted shortcut row covers is hidden
/// from the totals, never deleted. Buckets use `calendar`, defaulting to the
/// device zone like `getHours()` / `getDay()` do in the browser.
public enum HistoryViewModel {

    public static func build(
        archive: [ArchiveRow],
        logRows: [LogRow] = [],
        calendar: Calendar = .current
    ) -> HistoryPage {
        // Count accepted shortcut rows per day + item count, then consume one
        // archive row per count.
        var needed: [DedupeKey: Int] = [:]
        for row in logRows where !row.isArchive && row.choiceTook {
            needed[DedupeKey(day: String(row.date.prefix(10)), items: row.numericItems), default: 0] += 1
        }

        var visible: [ArchiveRow] = []
        var hidden = 0
        for row in archive {
            // `o.i || 1`: a zero item count is written to the log as one item.
            let key = DedupeKey(day: pacificDay(row.deliveredAt), items: row.items == 0 ? 1 : row.items)
            if let remaining = needed[key], remaining > 0 {
                needed[key] = remaining - 1
                hidden += 1
                continue
            }
            visible.append(row)
        }

        guard !visible.isEmpty else { return HistoryPage(duplicatesHidden: hidden) }

        var months: [String: [ArchiveRow]] = [:]
        var hours = [Int](repeating: 0, count: 24)
        var weekdays = [Int](repeating: 0, count: 7)
        var storeCounts: [String: Int] = [:]
        var storeOrder: [String] = []
        var first = visible[0].createdAt

        for row in visible {
            let parts = calendar.dateComponents([.year, .month, .hour, .weekday], from: row.deliveredAt)
            months[String(format: "%04d-%02d", parts.year ?? 0, parts.month ?? 0), default: []].append(row)
            hours[parts.hour ?? 0] += 1
            // `getDay()` is Sunday 0; Calendar's weekday is Sunday 1.
            weekdays[max(0, min(6, (parts.weekday ?? 1) - 1))] += 1
            first = min(first, row.createdAt)
            let name = storeName(row.store)
            if storeCounts[name] == nil { storeOrder.append(name) }
            storeCounts[name, default: 0] += 1
        }

        let busiest = hours.firstIndex(of: hours.max() ?? 0) ?? 0
        let tiles = [
            HistoryPage.Tile(value: visible.count.formatted(.number.locale(Locale(identifier: "en_US"))), label: "Lifetime deliveries"),
            HistoryPage.Tile(value: monthYear(first, calendar: calendar), label: "First order"),
            HistoryPage.Tile(value: minutesText(averageDuration(visible)), label: "Avg pickup to drop"),
            HistoryPage.Tile(value: hourLabel(busiest), label: "Busiest hour")
        ]
        let monthRows = months.keys.sorted(by: >).map { key -> HistoryPage.Month in
            let rows = months[key] ?? []
            return HistoryPage.Month(key: key, deliveries: rows.count, averagePickupToDrop: minutesText(averageDuration(rows)))
        }
        let maxHour = hours.max() ?? 0
        let hourRows = hours.enumerated().filter { $0.element > 0 }.map {
            HistoryPage.Bar(label: hourLabel($0.offset), deliveries: $0.element, fractionOfMax: fraction($0.element, of: maxHour))
        }
        let dayNames = ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"]
        let maxDay = weekdays.max() ?? 0
        let weekdayRows = weekdays.enumerated().map {
            HistoryPage.Bar(label: dayNames[$0.offset], deliveries: $0.element, fractionOfMax: fraction($0.element, of: maxDay))
        }

        // The web sort is stable, so equal counts keep first-seen order, and
        // `.prefix(10)` is its cut.
        let rank = Dictionary(uniqueKeysWithValues: storeOrder.enumerated().map { ($1, $0) })
        let storeRows = storeOrder.sorted {
            let left = storeCounts[$0] ?? 0
            let right = storeCounts[$1] ?? 0
            return left == right ? (rank[$0] ?? 0) < (rank[$1] ?? 0) : left > right
        }.prefix(10).map { HistoryPage.Store(name: $0, deliveries: storeCounts[$0] ?? 0) }

        return HistoryPage(tiles: tiles, months: monthRows, hours: hourRows,
                           weekdays: weekdayRows, stores: storeRows, duplicatesHidden: hidden)
    }

    private struct DedupeKey: Hashable { var day: String; var items: Double }

    /// `toLog()` stamps archive rows in Pacific time, so that is the day the
    /// duplicate rule compares, even though the tables use the device zone.
    private static let pacific: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/Los_Angeles") ?? .current
        return calendar
    }()

    private static func pacificDay(_ date: Date) -> String {
        let parts = pacific.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", parts.year ?? 0, parts.month ?? 0, parts.day ?? 0)
    }

    /// `r[1] ? (delivered - pickup) / 60000 : 0`, kept when `0 < dur < 180`.
    private static func duration(_ row: ArchiveRow) -> Double? {
        guard let pickup = row.pickupAt else { return nil }
        let minutes = row.deliveredAt.timeIntervalSince(pickup) / 60
        return minutes > 0 && minutes < 180 ? minutes : nil
    }

    private static func averageDuration(_ rows: [ArchiveRow]) -> Double {
        let values = rows.compactMap(duration)
        return values.isEmpty ? 0 : values.reduce(0, +) / Double(values.count)
    }

    private static func minutesText(_ value: Double) -> String {
        value > 0 ? JsNumber.toFixed(value, places: 0) + " min" : "--"
    }

    /// `r.s.replace(/\s*[\(#-].*$/, "").trim() || r.s`
    private static func storeName(_ store: String) -> String {
        let cut = store.firstIndex { $0 == "(" || $0 == "#" || $0 == "-" }
        let base = cut.map { String(store[..<$0]) } ?? store
        let trimmed = base.trimmingCharacters(in: .whitespaces)
        return trimmed.isEmpty ? store : trimmed
    }

    /// `(h % 12 || 12) + (h < 12 ? "am" : "pm")`
    private static func hourLabel(_ hour: Int) -> String {
        "\(hour % 12 == 0 ? 12 : hour % 12)" + (hour < 12 ? "am" : "pm")
    }

    private static func fraction(_ value: Int, of maximum: Int) -> Double {
        maximum > 0 ? Double(value) / Double(maximum) : 0
    }

    /// `toLocaleDateString(undefined, {month:"short", year:"numeric"})`.
    private static func monthYear(_ date: Date, calendar: Calendar) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US")
        formatter.calendar = calendar
        formatter.timeZone = calendar.timeZone
        formatter.dateFormat = "MMM yyyy"
        return formatter.string(from: date)
    }
}
