import Foundation

/// The Home screen's Scoreboard tiles for one bucket of one period.
///
/// This is a filter, not new maths: rows are kept only when
/// `PeriodGrouping.key(for:period:)` equals the requested key, and the
/// survivors go through `Scoreboard.totals`, so a tile can never disagree with
/// the Scoreboard it sits beside. Week keys are the Monday of the week, as
/// `PeriodGrouping` produces them.
///
/// `key` is expected to be a bucket key from `PeriodGrouping`, not a date to be
/// looked up; a key no row falls into returns zero totals. Rows whose date is
/// not `yyyy-MM-dd` bucket to `""` and so match only an empty key.
public enum HomeTiles {

    /// One tile in Home's stats grid, already formatted for display.
    public struct Tile: Identifiable, Equatable, Sendable {
        public enum Kind: String, CaseIterable, Sendable {
            case gross, net, netPerHour, netPerMile, offers, miles, hours, acceptance, followed
        }

        public let kind: Kind
        public let label: String
        public let value: String
        /// Money tiles are tinted, as `.money` is on the web.
        public let isMoney: Bool

        public var id: Kind { kind }
    }

    /// The nine tiles, in the web app's order and formatting. A rate with
    /// nothing to divide by is `"--"` rather than a zero, as `renderGame()`
    /// writes it.
    public static func tiles(_ totals: ScoreboardTotals) -> [Tile] {
        [
            Tile(kind: .gross, label: "Gross", value: Money.format(totals.gross, decimals: 0), isMoney: true),
            Tile(kind: .net, label: "Net after car", value: Money.format(totals.net, decimals: 0), isMoney: true),
            Tile(kind: .netPerHour, label: "Net $/hr", value: totals.netPerHour.map { Money.format($0) } ?? "--", isMoney: true),
            Tile(kind: .netPerMile, label: "Net $/mile", value: totals.netPerMile.map { Money.format($0) } ?? "--", isMoney: true),
            Tile(kind: .offers, label: "Offers", value: "\(totals.offers)", isMoney: false),
            Tile(kind: .miles, label: "Miles driven", value: JsNumber.toFixed(totals.miles, places: 0), isMoney: false),
            Tile(kind: .hours, label: "Hours", value: JsNumber.toFixed(totals.hours, places: 1), isMoney: false),
            Tile(kind: .acceptance, label: "Acceptance", value: totals.acceptancePercent.map { "\($0)%" } ?? "--", isMoney: false),
            Tile(kind: .followed, label: "Followed verdict", value: totals.loggedOffers > 0 ? "\(totals.followedPercent)%" : "--", isMoney: false)
        ]
    }

    /// `Scoreboard.totals` for the rows in `key` of `period`.
    public static func totals(
        _ rows: [LogRow],
        period: PeriodGrouping.Period,
        key: String,
        settings: VerdictSettings
    ) -> ScoreboardTotals {
        Scoreboard.totals(
            rows.filter { PeriodGrouping.key(for: $0.date, period: period) == key },
            settings: settings
        )
    }
}
