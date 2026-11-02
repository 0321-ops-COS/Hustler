import Foundation

/// Acceptance-rate rules, ported from the web app.
///
/// The web app has three related numbers and they are not interchangeable:
/// - the rate the user enters from DoorDash's Accepted/Declined counts
///   (`S.accept`, `Math.round(100 * a / (a + d))`),
/// - the rate implied by the log (`LOGRATE`, non-archive rows only),
/// - the newest rate written in the log (`LOGACC`), which takes precedence when
///   judging offers and computing the decline float.
public enum AcceptanceLogic {

    /// `S.accept = Math.round(100 * a / (a + d))`; `nil` when both are zero.
    public static func fromCounts(accepted: Double, declined: Double) -> Int? {
        let total = accepted + declined
        guard total > 0 else { return nil }
        return Int((100 * accepted / total).rounded())
    }

    /// `LOGRATE`: acceptance implied by logged offers, excluding archive rows.
    public static func logRate(_ rows: [LogRow]) -> Int? {
        let logged = rows.filter { !$0.isArchive }
        guard !logged.isEmpty else { return nil }
        let accepted = logged.filter { $0.choiceTook }.count
        return Int((100.0 * Double(accepted) / Double(logged.count)).rounded())
    }

    /// `LOGACC`: the newest non-archive row carrying a positive rate.
    /// Pass rows in analysis order (see `MasterLog.orderedForAnalysis`).
    public static func newestLoggedRate(_ rows: [LogRow]) -> Double? {
        for row in rows.reversed() where !row.isArchive {
            if !row.rate.isEmpty, Money.parse(row.rate) > 0 {
                return Money.parse(row.rate)
            }
        }
        return nil
    }

    /// `LOGACC != null ? LOGACC : num(S.accept)`
    public static func effectiveRate(settings: Double, logged: Double?) -> Double {
        logged ?? settings
    }
}
