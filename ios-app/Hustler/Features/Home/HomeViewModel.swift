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

    /// The "Followed the call" ring card for the whole log, or nil when unreadable.
    @Published private(set) var followCard: HomeFollowCard.Card?

    /// The weekly-quests card, between the float card and the period block.
    @Published private(set) var questCard: Quests.Card?

    /// The California pay-guarantee card, drawn after the period table.
    @Published private(set) var caCard: CAGuaranteeViewModel?

    /// The entry sheet's three fields for this week; `beginCAEntry()` prefills them.
    @Published var caDraft = CAEntryInput()

    /// A refused California-entry write, cleared by the next successful one.
    @Published private(set) var caError: String?

    /// The "Start here" card above the Scoreboard, or nil when the log is unreadable.
    @Published private(set) var startCard: HomeStartCard.Card?

    /// The master-file tile above the Scoreboard; shown even with no log yet.
    @Published private(set) var masterCard: HomeMasterTile.Card?

    /// False before the first master log exists, which is the empty state.
    @Published private(set) var hasLog = false

    /// A saved log that exists but cannot be read. Never shown as "no log".
    @Published private(set) var logUnavailable: String?

    /// True until the first read finishes. The screen draws a spinner instead of
    /// blocking the first frame after sign-in on file IO and log parsing.
    @Published private(set) var isLoading = true

    private let store: LocalStore
    private let clock: HomeClock
    private let settings: VerdictSettings
    private var rows: [LogRow] = []
    private var statementMonths: [String] = []
    private var storedSettings = AppSettings()
    private var board: HomePeriodBoard?
    /// `nil` starts the slider at the pace's average week, as `renderCA()` does.
    private var caExtraHours: Int?

    init(
        store: LocalStore = LocalStore(),
        clock: HomeClock = .live,
        settings: VerdictSettings = VerdictSettings()
    ) {
        self.store = store
        self.clock = clock
        self.settings = settings
    }

    var selectedBucket: Bucket? { buckets.first { $0.key == selectedKey } }
    var tiles: [HomeTiles.Tile] { selectedBucket?.tiles ?? [] }

    /// The week the entry sheet writes.
    var caWeekKey: String { PeriodGrouping.key(for: clock.dateText(), period: .week) }

    /// The period table's first column title, from `renderGame()`.
    var tableHeader: String { period == .week ? "Week of" : "Period" }

    /// Tapping a period-table row. An unknown key keeps the current selection.
    func select(_ key: String) {
        guard var board else { return }
        board.select(key)
        self.board = board
        selectedKey = board.selectedKey
    }

    /// The first read, off the main thread: the frame after sign-in is drawn
    /// before any file is opened, so a big log cannot stall the screen.
    @discardableResult
    func load() async -> HomeSnapshot {
        let directory = store.directory
        let snapshot = await Task.detached(priority: .userInitiated) {
            HomeLoader.snapshot(in: directory)
        }.value
        apply(snapshot)
        return snapshot
    }

    /// Re-reads the stored log on the calling thread. Used for refreshes a tap
    /// triggers, where a turn of the run loop is not worth splitting out.
    func reload() {
        apply(HomeLoader.snapshot(in: store.directory))
    }

    private func apply(_ snapshot: HomeSnapshot) {
        logUnavailable = snapshot.logUnavailable
        hasLog = snapshot.hasLog
        storedSettings = snapshot.settings
        rows = snapshot.rows
        statementMonths = snapshot.statementMonths
        isLoading = false
        rebuild()
    }

    private func rebuild() {
        guard logUnavailable == nil else {
            board = nil
            buckets = []
            selectedKey = ""
            floatCard = nil
            followCard = nil
            startCard = nil
            masterCard = nil
            questCard = nil
            caCard = nil
            return
        }

        let ordered = MasterLog.orderedForAnalysis(rows)
        floatCard = HomeFloat.card(rows: ordered)
        followCard = HomeFollowCard.card(rows: ordered)
        masterCard = HomeMasterTile.card(rows: ordered)
        questCard = Quests.card(rows: ordered, settings: settings, clock: clock)
        caCard = CAGuaranteeViewModel.make(
            rows: ordered,
            settings: storedSettings,
            today: clock.dateText(),
            extraHours: caExtraHours
        )
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

    // MARK: - California entries

    /// Opens the sheet on this week's stored values.
    func beginCAEntry() {
        caError = nil
        let stored = SettingsStore(store: store).settings
        caDraft = CAEntryDraft(weekKey: caWeekKey, entry: stored.caEntries[caWeekKey]).input
    }

    /// Stores the three fields for this week; false means the write was refused.
    @discardableResult
    func saveCAEntry() -> Bool {
        writeCA { CAEntryDraft(weekKey: caWeekKey, input: caDraft).applied(to: $0) }
    }

    /// Removes this week's entry, so the card uses the log's figures again.
    @discardableResult
    func clearCAWeek() -> Bool {
        writeCA { CAEntryDraft.cleared(caWeekKey, in: $0) }
    }

    func setCAExtraHours(_ hours: Int) {
        caExtraHours = hours
        rebuild()
    }

    private func writeCA(_ change: (AppSettings) -> AppSettings) -> Bool {
        let settingsStore = SettingsStore(store: store)
        do {
            try settingsStore.save(change(settingsStore.settings))
            caError = nil
            caExtraHours = nil
            reload()
            return true
        } catch {
            caError = error.localizedDescription
            return false
        }
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
