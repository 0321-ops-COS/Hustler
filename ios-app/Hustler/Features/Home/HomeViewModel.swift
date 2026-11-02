import Foundation
import Combine
import HustlerCore

/// The view model's only source of "now", so a test can pin the current day,
/// week, month and year instead of reading the wall clock.
struct HomeClock: Sendable {
    var now: @Sendable () -> Date

    static let live = HomeClock(now: { Date() })

    static func fixed(_ date: Date) -> HomeClock {
        HomeClock(now: { date })
    }
}

/// Home-screen state. No SwiftUI: the choices (which period, which buckets, what
/// each row says) are all computed here, so they can be tested without a view.
///
/// Money and hours come from `Scoreboard.periodTotals`, the same `keyOf()` /
/// `analyze()` port the web app uses, so a statement import is reflected as soon
/// as `reload()` runs. Offers is counted separately: as in the Scoreboard, money
/// and hours cover accepted rows only while offers cover every dated row.
@MainActor
final class HomeViewModel: ObservableObject {

    struct Bucket: Identifiable, Equatable {
        let key: String
        let label: String
        let totals: PeriodTotals
        let offers: Int
        let isCurrent: Bool

        var id: String { key }

        var hoursText: String { JsNumber.toFixed(totals.minutes / 60, places: 1) + " h" }

        /// `--` when the bucket has no hours to divide by, as the web app shows.
        var netPerHourText: String { totals.netPerHour.map { Money.format($0) } ?? "--" }
    }

    /// Default Day, then Week, Month, Year — the segmented control's order.
    @Published var period: PeriodGrouping.Period = .day {
        didSet { rebuild() }
    }

    /// Newest first, including the period containing `now` even when it is empty.
    @Published private(set) var buckets: [Bucket] = []

    /// False before the first master log exists, which is the empty state.
    @Published private(set) var hasLog = false

    /// A saved log that exists but cannot be read. Never shown as "no log".
    @Published private(set) var logUnavailable: String?

    private let store: LocalStore
    private let clock: HomeClock
    private let settings: VerdictSettings
    private var rows: [LogRow] = []

    init(
        store: LocalStore = LocalStore(),
        clock: HomeClock = .live,
        settings: VerdictSettings = VerdictSettings()
    ) {
        self.store = store
        self.clock = clock
        self.settings = settings
        reload()
    }

    /// Re-reads the stored log. A fresh `LocalLibrary` is used because the
    /// Statements screen may have saved since this model was built; reads are
    /// side-effect free apart from marking an unreadable file blocked.
    func reload() {
        let library = LocalLibrary(store: store)

        var problem: String?
        if case let .unavailable(reason) = library.status(of: .masterLog) {
            problem = reason
        }

        logUnavailable = problem
        hasLog = library.log.rowCount > 0
        rows = problem == nil ? MasterLogParser.parse(library.log.text) : []
        rebuild()
    }

    private func rebuild() {
        guard logUnavailable == nil else {
            buckets = []
            return
        }

        let totals = Scoreboard.periodTotals(rows, period: period, settings: settings)

        var offers: [String: Int] = [:]
        for row in rows where MasterLog.startsWithISODate(row.date) {
            let key = PeriodGrouping.key(for: row.date, period: period)
            if !key.isEmpty { offers[key, default: 0] += 1 }
        }

        var keys = Set(offers.keys).union(totals.keys)
        let currentKey = PeriodGrouping.key(for: Self.dateText(clock.now()), period: period)
        // Only once the log has dated rows: an undated log has nothing to list.
        if !keys.isEmpty { keys.insert(currentKey) }

        buckets = keys.sorted(by: >).map { key in
            Bucket(
                key: key,
                label: Self.label(for: key, period: period),
                totals: totals[key] ?? PeriodTotals(),
                offers: offers[key] ?? 0,
                isCurrent: key == currentKey
            )
        }
    }

    // MARK: - Text

    /// `now` as the local calendar date, which is the date the log records.
    private static func dateText(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = .current
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: date)
    }

    private static func label(for key: String, period: PeriodGrouping.Period) -> String {
        switch period {
        case .day: return formatted(key, from: "yyyy-MM-dd", to: "EEE d MMM yyyy")
        case .week: return "Week of " + formatted(key, from: "yyyy-MM-dd", to: "d MMM yyyy")
        case .month: return formatted(key, from: "yyyy-MM", to: "MMMM yyyy")
        case .year: return key
        }
    }

    /// Bucket keys are zone-free date text, so both ends of the swap are UTC.
    private static func formatted(_ text: String, from: String, to: String) -> String {
        guard let date = formatter(from).date(from: text) else { return text }
        return formatter(to).string(from: date)
    }

    private static var formatters: [String: DateFormatter] = [:]

    private static func formatter(_ format: String) -> DateFormatter {
        if let cached = formatters[format] { return cached }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = format
        formatters[format] = formatter
        return formatter
    }
}
