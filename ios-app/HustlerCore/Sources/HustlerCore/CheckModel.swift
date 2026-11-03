import Foundation

/// The Check screen's one-off offer check, ported from `#calc`
/// (`index.html:147`, `index.html:542`).
///
/// Fields are re-parsed with `num()` on read, as the web app does: no payout or
/// miles means nothing to judge, unreadable minutes go to `VerdictEngine` (which
/// derives them), and gas today replaces the stored price for this check only.
public struct CheckModel: Equatable, Sendable {

    public enum Field: String, CaseIterable, Equatable, Sendable {
        case payout, miles, items, minutes, gasToday, rate
    }

    /// Which acceptance number judged the offer, in precedence order: typed
    /// field, newest logged row, log-implied, stored setting.
    public enum RateSource: String, Equatable, Sendable {
        case typed, newestLogged, logImplied, settings
    }

    public struct ResolvedRate: Equatable, Sendable {
        public let rate: Double
        public let source: RateSource
    }

    public struct Verdict: Equatable, Sendable {
        public struct Stat: Equatable, Sendable, Identifiable {
            public let label: String
            public let value: String
            public var id: String { label }
        }

        public let result: VerdictResult
        public var headline: String { result.takeIt ? "TAKE IT" : "SKIP" }

        /// `Math.round(minutes)`, without a trailing `.0`.
        public var minutesText: String {
            let rounded = result.minutes.rounded()
            guard rounded.isFinite, abs(rounded) < 9e15 else { return JsNumber.description(rounded) }
            return String(Int(rounded))
        }

        /// The web card's four stats, worded as `#c_out` writes them.
        public var stats: [Stat] {
            [
                Stat(label: "Net after car", value: Money.format(result.net)),
                Stat(label: "Net $/hr (need \(Money.format(result.requiredHour)))", value: Money.format(result.netPerHour)),
                Stat(label: "Payout $/mile (need \(Money.format(result.requiredMile)))", value: Money.format(result.payoutPerMile)),
                Stat(label: "Minutes", value: minutesText)
            ]
        }
    }

    public enum Outcome: Equatable, Sendable {
        case needsPayoutAndMiles
        case verdict(Verdict)
    }

    private var texts: [Field: String]
    public let settings: VerdictSettings
    public let settingsRate: Double
    public let newestLoggedRate: Double?
    public let logRate: Int?

    /// Rows must be in analysis order; the rate field starts at the stored
    /// setting, 89 on a fresh install.
    public init(settings: VerdictSettings = VerdictSettings(),
                settingsRate: Double = HomeFloat.defaultSettingsRate,
                rows: [LogRow] = []) {
        self.settings = settings
        self.settingsRate = settingsRate
        self.newestLoggedRate = AcceptanceLogic.newestLoggedRate(rows)
        self.logRate = AcceptanceLogic.logRate(rows)
        self.texts = [.rate: JsNumber.description(settingsRate)]
    }

    public func text(for field: Field) -> String { texts[field] ?? "" }
    public mutating func setText(_ text: String, for field: Field) { texts[field] = text }

    /// `showLR()`'s line, or nil when the log implies no rate.
    public var logRateHint: String? { logRate.map { "Your log shows \($0)%." } }

    /// `useLR()`; persisting the rate is the app's job.
    public mutating func useLogRate() {
        guard let logRate else { return }
        texts[.rate] = String(logRate)
    }

    /// A typed 0 counts as unset, like the `num(x) > 0` checks the web app uses.
    public var resolvedRate: ResolvedRate {
        let typed = Money.parse(text(for: .rate))
        if typed > 0 { return ResolvedRate(rate: typed, source: .typed) }
        if let logged = newestLoggedRate, logged > 0 {
            return ResolvedRate(rate: logged, source: .newestLogged)
        }
        if let logRate { return ResolvedRate(rate: Double(logRate), source: .logImplied) }
        return ResolvedRate(rate: settingsRate, source: .settings)
    }

    /// `verdict()` plus the `#c_go` guard: payout and miles must both be non-zero.
    public func outcome() -> Outcome {
        let payout = Money.parse(text(for: .payout))
        let miles = Money.parse(text(for: .miles))
        guard payout != 0, miles != 0 else { return .needsPayoutAndMiles }

        var effective = settings
        let gasToday = Money.parse(text(for: .gasToday))
        if gasToday > 0 { effective.gas = gasToday }

        let offer = VerdictOffer(
            payout: payout, miles: miles,
            items: Money.parse(text(for: .items)),
            minutes: Money.parse(text(for: .minutes))
        )
        return .verdict(Verdict(
            result: VerdictEngine.evaluate(offer, settings: effective, rate: resolvedRate.rate)
        ))
    }
}
