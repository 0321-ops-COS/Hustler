import Foundation

/// Totals for one day, week, month or year — the Period table in `renderGame()`.
public struct PeriodTotals: Equatable, Sendable {
    public var gross: Double
    public var net: Double
    public var taken: Int
    public var minutes: Double

    public init(gross: Double = 0, net: Double = 0, taken: Int = 0, minutes: Double = 0) {
        self.gross = gross
        self.net = net
        self.taken = taken
        self.minutes = minutes
    }

    /// `g.m ? $f(g.n / (g.m / 60)) : "--"` — `nil` renders as `"--"`.
    public var netPerHour: Double? {
        minutes > 0 ? net / (minutes / 60) : nil
    }
}

/// The Scoreboard totals, ported from `analyze()` (`index.html:360-420`).
///
/// The web app deliberately measures two different populations:
/// - **money, miles, hours** are summed over *accepted* rows only, so a
///   declined offer contributes nothing to earnings;
/// - **Acceptance** and the followed-verdict percentage are computed over
///   *non-archive* rows only, because archive deliveries carry no verdict.
///
/// `Offers` is every row in the log, archive included. None of that is
/// interchangeable, so the two populations are kept as separate counts here
/// rather than being folded into one "count".
public struct ScoreboardTotals: Equatable, Sendable {
    public var gross: Double
    public var net: Double
    public var miles: Double
    public var minutes: Double
    public var offers: Int
    public var loggedOffers: Int
    public var loggedAccepted: Int
    public var acceptancePercent: Int?
    public var followedPercent: Int

    public var hours: Double { minutes / 60 }

    /// `hrs ? $f(net / hrs) : "--"`
    public var netPerHour: Double? { hours > 0 ? net / hours : nil }

    /// `mi ? $f(net / mi) : "--"`
    public var netPerMile: Double? { miles > 0 ? net / miles : nil }
}

public enum Scoreboard {

    /// Per-row net: the row's own `Net` cell when it has one, otherwise
    /// `payout - miles * (gas/mpg + wear)` with per-zone gas.
    ///
    /// Archive rows written by the importer leave `Net` blank, which is why the
    /// fallback is the common path for them.
    public static func net(for row: LogRow, settings: VerdictSettings) -> Double {
        if !row.net.isEmpty { return Money.parse(row.net) }
        let gasPrice = settings.zoneGas[row.zone] ?? settings.gas
        return row.numericPayout - row.numericMiles * (gasPrice / settings.mpg + settings.wear)
    }

    public static func totals(_ rows: [LogRow], settings: VerdictSettings) -> ScoreboardTotals {
        var gross = 0.0
        var netTotal = 0.0
        var miles = 0.0
        var minutes = 0.0

        for row in rows where row.choiceTook {
            gross += row.numericPayout
            netTotal += net(for: row, settings: settings)
            miles += row.numericMiles
            minutes += row.numericMinutes
        }

        let logged = rows.filter { !$0.isArchive }
        let loggedAccepted = logged.filter { $0.choiceTook }.count
        let followed = logged.filter { $0.verdictIsYes == $0.choiceTook }.count

        return ScoreboardTotals(
            gross: gross,
            net: netTotal,
            miles: miles,
            minutes: minutes,
            offers: rows.count,
            loggedOffers: logged.count,
            loggedAccepted: loggedAccepted,
            acceptancePercent: logged.isEmpty
                ? nil
                : Int((100.0 * Double(loggedAccepted) / Double(logged.count)).rounded()),
            followedPercent: logged.isEmpty
                ? 0
                : Int((100.0 * Double(followed) / Double(logged.count)).rounded())
        )
    }

    /// Accepted, dated rows bucketed by `keyOf(date, period)`.
    ///
    /// Rows without a `yyyy-MM-dd` date are skipped, exactly as the web app's
    /// period block filters them. Net uses `net(for:settings:)`, not the raw
    /// cell: archive rows written without a Net figure still contribute their
    /// payout minus car cost, which is what `analyze()` puts in each row first.
    public static func periodTotals(
        _ rows: [LogRow],
        period: PeriodGrouping.Period,
        settings: VerdictSettings
    ) -> [String: PeriodTotals] {
        var totals: [String: PeriodTotals] = [:]

        for row in rows where row.choiceTook {
            guard MasterLog.startsWithISODate(row.date) else { continue }
            let key = PeriodGrouping.key(for: row.date, period: period)
            guard !key.isEmpty else { continue }
            var bucket = totals[key] ?? PeriodTotals()
            bucket.gross += row.numericPayout
            bucket.net += net(for: row, settings: settings)
            bucket.taken += 1
            bucket.minutes += row.numericMinutes
            totals[key] = bucket
        }

        return totals
    }
}
