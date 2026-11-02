import Foundation
import Combine
import HustlerCore

/// Home-screen state. The buckets, the slicing and the selection are
/// `HomePeriodBoard` results; this class only owns the loaded rows and period.
@MainActor
final class HomeViewModel: ObservableObject {

    struct Bucket: Identifiable, Equatable {
        let key: String
        let label: String
        let totals: ScoreboardTotals
        let taken: Int

        var id: String { key }
        var bigNetText: String { Money.format(totals.net, decimals: 0) }
        var rowGrossText: String { Money.format(totals.gross) }
        var rowNetText: String { Money.format(totals.net) }
        var takenText: String { "\(taken)" }
        var netPerHourText: String { totals.netPerHour.map { Money.format($0) } ?? "--" }
        var tiles: [HomeTiles.Tile] { HomeTiles.tiles(totals) }
    }

    /// Default Day, then Week, Month, Year — the segmented control's order.
    @Published var period: PeriodGrouping.Period = .day {
        didSet { rebuild() }
    }

    /// Newest first, including the period containing `now` even when it is empty.
    @Published private(set) var buckets: [Bucket] = []

    /// The period-table row the big number and tiles belong to.
    @Published private(set) var selectedKey = ""

    /// The decline-float card, or nil when the log is unreadable.
    @Published private(set) var floatCard: HomeFloat.Card?

    /// The "Start here" card above the Scoreboard, or nil when the log is unreadable.
    @Published private(set) var startCard: HomeStartCard.Card?

    /// The master-file tile above the Scoreboard; shown even with no log yet.
    @Published private(set) var masterCard: HomeMasterTile.Card?

    /// False before the first master log exists, which is the empty state.
    @Published private(set) var hasLog = false

    /// A saved log that exists but cannot be read. Never shown as "no log".
    @Published private(set) var logUnavailable: String?

    private let store: LocalStore
    private let clock: HomeClock
    private let settings: VerdictSettings
    private var rows: [LogRow] = []
    private var statementMonths: [String] = []
    private var board: HomePeriodBoard?

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

    var selectedBucket: Bucket? { buckets.first { $0.key == selectedKey } }
    var tiles: [HomeTiles.Tile] { selectedBucket?.tiles ?? [] }

    /// The period table's first column title, from `renderGame()`.
    var tableHeader: String { period == .week ? "Week of" : "Period" }

    /// Tapping a period-table row. An unknown key keeps the current selection.
    func select(_ key: String) {
        guard var board else { return }
        board.select(key)
        self.board = board
        selectedKey = board.selectedKey
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
        statementMonths = Array(library.statements.statements.keys)
        rebuild()
    }

    private func rebuild() {
        guard logUnavailable == nil else {
            board = nil
            buckets = []
            selectedKey = ""
            floatCard = nil
            startCard = nil
            masterCard = nil
            return
        }

        let ordered = MasterLog.orderedForAnalysis(rows)
        floatCard = HomeFloat.card(rows: ordered)
        masterCard = HomeMasterTile.card(rows: ordered)
        // No acceptance rate is stored yet, so that step stays open.
        startCard = HomeStartCard.card(
            rows: ordered,
            statementMonths: statementMonths,
            hasAcceptanceRate: false,
            acceptanceRate: HomeFloat.defaultSettingsRate
        )

        let next = HomePeriodBoard(rows: rows, period: period, clock: clock, settings: settings)
        board = next
        buckets = next.buckets.map { bucket in
            Bucket(
                key: bucket.key,
                label: Self.label(for: bucket.key, period: period),
                totals: bucket.totals,
                taken: bucket.taken
            )
        }
        selectedKey = next.selectedKey
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
