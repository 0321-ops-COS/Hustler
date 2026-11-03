import Foundation

/// The What-if replay: every log row judged twice, once under the stored
/// settings and once under the numbers typed into the form.
///
/// Ported from `drawWf()`, `draft()` and the `#runWf` handler (`index.html:432-438`).
/// Nothing here writes: the log and both settings sets are inputs, and the
/// result is what the web app displays. The tests' values were produced by
/// running that handler in a stubbed DOM, not by re-deriving its arithmetic.
public enum WhatIf {
    /// One numeric field the form offers, in the web app's `DEF` order.
    ///
    /// The web form draws all 21 `DEF` keys; only these 14 feed `verdict()`, so
    /// est. pay/speed, tax rate, float target and the California rates stay on
    /// the Settings tab rather than appearing here doing nothing.
    public struct Field: Identifiable, Hashable {
        public let id: String, label: String
        private let keyPath: WritableKeyPath<AppSettings, Double>

        public func value(in settings: AppSettings) -> Double { settings[keyPath: keyPath] }
        public func set(_ value: Double, in settings: inout AppSettings) { settings[keyPath: keyPath] = value }
        /// `${S[k]}`: JavaScript's `String(number)`, so 20 prints without `.0`.
        public func text(in settings: AppSettings) -> String { JsNumber.description(value(in: settings)) }

        public static let accept = Field(id: "accept", label: "Acceptance rate (%)", keyPath: \.accept)
        public static let mpg = Field(id: "mpg", label: "MPG", keyPath: \.mpg)
        public static let wear = Field(id: "wear", label: "Wear cost per mile ($)", keyPath: \.wear)
        public static let gas = Field(id: "gas", label: "Gas price ($/gal)", keyPath: \.gas)
        public static let rampTop = Field(id: "rampTop", label: "Ramp top (% acceptance)", keyPath: \.rampTop)
        public static let rampLow = Field(id: "rampLow", label: "Ramp low (% acceptance)", keyPath: \.rampLow)
        public static let floorMile = Field(id: "floorMile", label: "Floor $/mile", keyPath: \.floorMile)
        public static let floorHour = Field(id: "floorHour", label: "Floor $/hour", keyPath: \.floorHour)
        public static let baseMile = Field(id: "baseMile", label: "Base $/mile", keyPath: \.baseMile)
        public static let baseHour = Field(id: "baseHour", label: "Base $/hour", keyPath: \.baseHour)
        public static let bigItems = Field(id: "bigItems", label: "Big order: items over", keyPath: \.bigItems)
        public static let bigMile = Field(id: "bigMile", label: "Big order $/mile", keyPath: \.bigMile)
        public static let bigHour = Field(id: "bigHour", label: "Big order $/hour", keyPath: \.bigHour)
        public static let emergency = Field(id: "emergency", label: "Emergency rate (%)", keyPath: \.emergency)
        public static let all: [Field] = [
            accept, mpg, wear, gas, rampTop, rampLow, floorMile, floorHour,
            baseMile, baseHour, bigItems, bigMile, bigHour, emergency
        ]
    }

    /// One row judged under both setting sets.
    public struct Decision: Equatable, Sendable {
        public var row: LogRow, current: VerdictResult, changed: VerdictResult
        public var flipped: Bool { current.takeIt != changed.takeIt }
    }

    /// `sum("a")` / `sum("b")`: taken rows only, hours summed before dividing.
    public struct Totals: Equatable, Sendable {
        public var taken: Int, net: Double, hours: Double
        /// `h ? net / h : 0`
        public var netPerHour: Double

        public var takenText: String { String(taken) }
        public var netText: String { Money.format(net, decimals: 0) }
        public var netPerHourText: String { Money.format(netPerHour) }
    }

    /// One flipped-offer row, with the web app's own columns.
    public struct Flip: Equatable, Sendable {
        public var offer: String, payout: String, miles: String
        public var currentText: String, changedText: String
        public var changedTook: Bool
    }

    /// One row of the Replay results table.
    public struct TableRow: Equatable, Sendable {
        public var label: String, currentText: String, changedText: String
    }

    public struct Replay: Equatable, Sendable {
        public var decisions: [Decision]
        public var current: Totals, changed: Totals
        public var netDifference: Double
        /// The web app's `d >= 0`, which colours the summary line.
        public var isGain: Bool
        public var tableRows: [TableRow]
        public var flippedCount: Int
        /// The first 12 flips, as `fl.slice(0, 12)` shows.
        public var flipped: [Flip]
        public var acceptanceLine: String, summaryLine: String
        public var hasRows: Bool { !decisions.isEmpty }
    }

    public static let emptyLogMessage = "Load a log first."
    public static let resultsTitle = "Replay results"
    public static let flippedTitle = "Flipped offers"

    public static func replay(rows: [LogRow], settings: AppSettings, change: AppSettings) -> Replay {
        let currentSettings = settings.verdictSettings()
        let changedSettings = change.verdictSettings()
        let decisions = rows.map { row -> Decision in
            let offer = VerdictOffer(
                payout: row.numericPayout, miles: row.numericMiles,
                items: row.numericItems, minutes: row.numericMinutes, zone: row.zone
            )
            // `num(r.rate) || S.accept`: a blank or zero cell defers to the field.
            let rate = row.numericRate
            return Decision(
                row: row,
                current: VerdictEngine.evaluate(offer, settings: currentSettings, rate: rate != 0 ? rate : settings.accept),
                changed: VerdictEngine.evaluate(offer, settings: changedSettings, rate: rate != 0 ? rate : change.accept)
            )
        }
        let current = totals(decisions.map(\.current))
        let changed = totals(decisions.map(\.changed))
        let difference = changed.net - current.net
        let flips = decisions.filter(\.flipped)
        let shown = flips.prefix(12).map { decision -> Flip in
            // The web app rebuilds the payout from the *stored* global gas price,
            // so a zone-gas row shows a payout the row never earned.
            let payout = decision.current.net
                + decision.row.numericMiles * (settings.gas / settings.mpg + settings.wear)
            return Flip(
                offer: decision.row.date + " " + decision.row.zone,
                payout: Money.format(payout),
                miles: JsNumber.description(decision.row.numericMiles),
                currentText: decision.current.takeIt ? "Take" : "Pass",
                changedText: decision.changed.takeIt ? "Take" : "Pass",
                changedTook: decision.changed.takeIt
            )
        }
        return Replay(
            decisions: decisions, current: current, changed: changed,
            netDifference: difference, isGain: difference >= 0,
            tableRows: [
                TableRow(label: "Offers you'd take", currentText: current.takenText, changedText: changed.takenText),
                TableRow(label: "Net total", currentText: current.netText, changedText: changed.netText),
                TableRow(label: "Net $/hr", currentText: current.netPerHourText, changedText: changed.netPerHourText)
            ],
            flippedCount: flips.count, flipped: shown,
            acceptanceLine: "Acceptance rate used: " + JsNumber.description(settings.accept)
                + "% now, " + JsNumber.description(change.accept)
                + "% in your change. Assumes you follow each verdict.",
            summaryLine: String(flips.count) + " verdicts flipped, "
                + (difference >= 0 ? "+" : "-")
                + Money.format(abs(difference), decimals: 0) + " net"
        )
    }

    private static func totals(_ results: [VerdictResult]) -> Totals {
        let taken = results.filter(\.takeIt)
        let net = taken.reduce(0.0) { $0 + $1.net }
        let hours = taken.reduce(0.0) { $0 + $1.hours }
        return Totals(taken: taken.count, net: net, hours: hours, netPerHour: hours != 0 ? net / hours : 0)
    }
}
