import Foundation

/// Endless weekly quests, ported from `weekAggs()`, `QDEF`, `questState()`,
/// `NICE()` and `renderQuests()` in `index.html:573-601`. Targets come from the
/// user's four most recent *existing* weeks before this one; nothing resets.
public enum Quests {

    public enum ID: String, CaseIterable, Sendable { case net, npm, nph, fol, pick }
    /// `"measured"` counts straight from the log; `"estimate"` uses net or settings.
    public enum Kind: String, Equatable, Sendable { case estimate, measured }

    /// One week of `weekAggs()`. `accepted` is the web's `n` (archive included),
    /// `logged` its `off` (non-archive). The web's `pay` and `acc` are unused.
    public struct WeekAggregate: Equatable, Sendable {
        public var accepted = 0, net = 0.0, miles = 0.0, minutes = 0.0
        public var archive = 0, logged = 0, followed = 0, yes = 0, yesAccepted = 0
    }

    /// `questState()` for one quest in one week: the web's `b`, `t`, `has`, `v`.
    public struct State: Equatable, Sendable {
        public let baseline: Double?
        public let target: Double?
        public let hasData: Bool
        public let value: Double?
    }

    /// `weekAggs(R, RL)`, keyed by Monday; undated rows bucket nowhere.
    public static func weekAggs(
        _ rows: [LogRow], settings: VerdictSettings = VerdictSettings()
    ) -> [String: WeekAggregate] {
        var weeks: [String: WeekAggregate] = [:]
        for row in rows {
            guard MasterLog.startsWithISODate(row.date) else { continue }
            let key = PeriodGrouping.key(for: row.date, period: .week)
            guard !key.isEmpty else { continue }
            var week = weeks[key] ?? WeekAggregate()
            if row.choiceTook {
                week.accepted += 1
                week.net += Scoreboard.net(for: row, settings: settings)
                week.miles += row.numericMiles
                week.minutes += row.numericMinutes
                if row.isArchive { week.archive += 1 }
            }
            if !row.isArchive {
                week.logged += 1
                if row.verdictIsYes == row.choiceTook { week.followed += 1 }
                if row.verdictIsYes {
                    week.yes += 1
                    if row.choiceTook { week.yesAccepted += 1 }
                }
            }
            weeks[key] = week
        }
        return weeks
    }

    /// `questState(W, wk)`: the baseline uses the last four weeks that exist
    /// before `week`, by key — not four calendar weeks.
    public static func questState(
        _ weeks: [String: WeekAggregate], week: String
    ) -> [ID: State] {
        let prior = weeks.keys.sorted().filter { $0 < week }.suffix(4).compactMap { weeks[$0] }
        var states: [ID: State] = [:]
        for id in ID.allCases { states[id] = state(id, week: weeks[week], prior: prior) }
        return states
    }

    static func state(_ id: ID, week: WeekAggregate?, prior: [WeekAggregate]) -> State {
        switch id {
        case .net:
            let base = prior.filter { $0.accepted >= 5 }
            let baseline = base.isEmpty ? nil : base.reduce(0.0) { $0 + $1.net } / Double(base.count)
            let has = (week?.accepted ?? 0) >= 3
            return State(baseline: baseline, target: baseline.map { max(50, $0 * 1.05) }, hasData: has, value: has ? week?.net : nil)
        case .npm:
            let base = prior.filter { $0.miles >= 20 }
            let miles = base.reduce(0.0) { $0 + $1.miles }
            let baseline = miles == 0 ? nil : base.reduce(0.0) { $0 + $1.net } / miles
            let has = (week?.miles ?? 0) >= 10
            return State(baseline: baseline, target: baseline.map { $0 * 1.02 }, hasData: has, value: has ? week.map { $0.net / $0.miles } : nil)
        case .nph:
            let base = prior.filter { $0.minutes >= 240 }
            let hours = base.reduce(0.0) { $0 + $1.minutes / 60 }
            let baseline = hours == 0 ? nil : base.reduce(0.0) { $0 + $1.net } / hours
            let has = (week?.minutes ?? 0) >= 180
            return State(baseline: baseline, target: baseline.map { $0 * 1.02 }, hasData: has, value: has ? week.map { $0.net / ($0.minutes / 60) } : nil)
        case .fol:
            let has = (week?.logged ?? 0) >= 8
            return State(baseline: 85, target: 85, hasData: has, value: has ? week.map { 100 * Double($0.followed) / Double($0.logged) } : nil)
        case .pick:
            let has = (week?.yes ?? 0) >= 6
            return State(baseline: 90, target: 90, hasData: has, value: has ? week.map { 100 * Double($0.yesAccepted) / Double($0.yes) } : nil)
        }
    }

    /// `st`/`best` from `renderGame()`: non-archive rows where verdict matched choice.
    public static func streak(_ rows: [LogRow]) -> (current: Int, best: Int) {
        let logged = rows.filter { !$0.isArchive }
        var run = 0, best = 0
        for row in logged {
            if row.verdictIsYes == row.choiceTook { run += 1; best = max(best, run) } else { run = 0 }
        }
        var current = 0
        for row in logged.reversed() {
            guard row.verdictIsYes == row.choiceTook else { break }
            current += 1
        }
        return (current, best)
    }

    /// `NICE(v)`: the next 1, 2.5 or 5 × 10^k above `v`, from 100 up.
    public static func nice(_ value: Double) -> Double {
        var scale = 100.0
        for _ in 2...11 {
            for multiple in [1.0, 2.5, 5.0] where multiple * scale > value { return multiple * scale }
            scale *= 10
        }
        return value * 2
    }

    /// Everything `renderQuests()` writes, as values. The view draws the kind
    /// label, the checkmark and the bars; all wording is decided here.
    public struct Card: Equatable, Sendable {
        public struct Row: Identifiable, Equatable, Sendable {
            public enum State: Equatable, Sendable { case notEnoughData, buildingBaseline, tracked(done: Bool) }
            public let id: ID
            public let name: String
            public let kind: Kind
            public let state: State
            /// `"--"`, the value, or `"value / target"`.
            public let valueText: String
            public let hint: String?
            /// `min(1, value / target)`; `nil` when the web draws no bar.
            public let progress: Double?
        }
        public let title, summary: String
        public let rows: [Row]
        public let lifetimeLabel, lifetimeText: String
        public let lifetimeProgress: Double
        public let footer: String
    }

    public static func card(
        rows: [LogRow], settings: VerdictSettings = VerdictSettings(), clock: HomeClock = .live
    ) -> Card {
        let weeks = weekAggs(rows, settings: settings)
        let week = PeriodGrouping.key(for: clock.dateText(), period: .week)
        let current = questState(weeks, week: week)
        // `life` is the web's `acc.reduce(net)`: accepted rows, dated or not.
        let life = rows.filter { $0.choiceTook }.reduce(0.0) { $0 + Scoreboard.net(for: $1, settings: settings) }
        let ceiling = nice(life)

        // Every finished week is re-scored with the same rules, so this grows.
        var cleared = 0, counted = 0
        for past in weeks.keys.filter({ $0 < week }).sorted() {
            let states = questState(weeks, week: past)
            var any = false
            for id in ID.allCases {
                guard let state = states[id], state.hasData, let target = state.target else { continue }
                any = true
                if let value = state.value, value >= target { cleared += 1 }
            }
            if any { counted += 1 }
        }

        let streak = streak(rows)
        var summary = "Targets are set from your own last 4 weeks, so they rise as you improve and refresh every Monday. Streak: \(streak.current) followed in a row. Best: \(streak.best)."
        if (weeks[week]?.archive ?? 0) > 0 { summary += " This week includes archive deliveries, so net figures use estimated pay and miles." }

        let questRows = ID.allCases.map { id -> Card.Row in
            let state = current[id]!
            let kind: Kind = id == .fol || id == .pick ? .measured : .estimate
            guard state.hasData, let value = state.value else {
                return Card.Row(id: id, name: names[id]!, kind: kind, state: .notEnoughData, valueText: "--", hint: "Not enough logged this week yet.", progress: nil)
            }
            guard let target = state.target else {
                return Card.Row(id: id, name: names[id]!, kind: kind, state: .buildingBaseline, valueText: text(id, value), hint: "Building your baseline: needs a finished prior week.", progress: nil)
            }
            return Card.Row(id: id, name: names[id]!, kind: kind, state: .tracked(done: value >= target), valueText: text(id, value) + " / " + text(id, target), hint: nil, progress: min(1, value / target))
        }

        return Card(
            title: "This week's quests", summary: summary, rows: questRows,
            lifetimeLabel: "Lifetime net (estimate)",
            lifetimeText: Money.format(life, decimals: 0) + " / " + Money.format(ceiling, decimals: 0),
            lifetimeProgress: min(1, life / ceiling),
            footer: "Lifetime: \(cleared) weekly quest\(cleared == 1 ? "" : "s") cleared over \(counted) week\(counted == 1 ? "" : "s"). Lifetime totals never reset. Measured = counted straight from your log. Estimate = uses your car-cost settings and offer or archive time and miles, so tips and final pay can differ."
        )
    }

    static let names: [ID: String] = [
        .net: "Net earnings", .npm: "Net $ per mile", .nph: "Net $ per active hour",
        .fol: "Followed the verdict", .pick: "Took the offers it said yes to"
    ]

    static func text(_ id: ID, _ value: Double) -> String {
        if id == .fol || id == .pick { return JsNumber.toFixed(value, places: 0) + "%" }
        return Money.format(value, decimals: id == .net ? 0 : 2)
    }
}
