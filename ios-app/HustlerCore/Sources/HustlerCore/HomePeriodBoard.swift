import Foundation

public struct HomeClock: Sendable {
    public var now: @Sendable () -> Date
    public init(now: @escaping @Sendable () -> Date) { self.now = now }
    public static let live = HomeClock(now: { Date() })
    public static func fixed(_ date: Date) -> HomeClock { HomeClock(now: { date }) }

    public func dateText() -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = .current
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: now())
    }
}

public struct HomePeriodBucket: Identifiable, Equatable, Sendable {
    public let key: String
    public let totals: ScoreboardTotals
    public let taken: Int

    public var id: String { key }
}

public struct HomePeriodBoard: Equatable, Sendable {
    public let buckets: [HomePeriodBucket]
    public private(set) var selectedKey: String

    public init(
        rows: [LogRow],
        period: PeriodGrouping.Period,
        clock: HomeClock = .live,
        settings: VerdictSettings = VerdictSettings()
    ) {
        let nowKey = PeriodGrouping.key(for: clock.dateText(), period: period)

        var taken: [String: Int] = [:]
        for row in rows where row.choiceTook && MasterLog.startsWithISODate(row.date) {
            let key = PeriodGrouping.key(for: row.date, period: period)
            if !key.isEmpty { taken[key, default: 0] += 1 }
        }
        var keys = Array(taken.keys.sorted(by: >).prefix(Self.limit(for: period)))
        if !keys.contains(nowKey) { keys.insert(nowKey, at: 0) }

        buckets = keys.map { key in
            HomePeriodBucket(
                key: key,
                totals: HomeTiles.totals(rows, period: period, key: key, settings: settings),
                taken: taken[key] ?? 0
            )
        }
        selectedKey = nowKey
    }

    /// `renderGame()` keeps 10 days, 8 weeks, 12 of everything else (Year too).
    public static func limit(for period: PeriodGrouping.Period) -> Int {
        switch period {
        case .day: return 10
        case .week: return 8
        case .month, .year: return 12
        }
    }

    public var selected: HomePeriodBucket? { buckets.first { $0.key == selectedKey } }

    public var tiles: [HomeTiles.Tile] { selected.map { HomeTiles.tiles($0.totals) } ?? [] }

    /// Tapping a row; a key outside the table keeps the selection.
    public mutating func select(_ key: String) {
        guard buckets.contains(where: { $0.key == key }) else { return }
        selectedKey = key
    }
}
