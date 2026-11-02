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
