import Foundation

/// One row of the "Verdict vs. what you did" table (`#matrix` on the web).
///
/// Every non-archive row counts, accepted or not, because the table is about
/// whether the choice matched the verdict. Net is the Scoreboard's per-row net,
/// so a declined row keeps its negative figure. Archive rows have no verdict
/// and never appear.
public struct MatrixCell: Equatable, Sendable {
    public var verdictYes: Bool
    public var accepted: Bool
    public var orders: Int
    public var net: Double
    public var minutes: Double

    /// `good` on the web when the choice matched the verdict, `bad` otherwise.
    public var agrees: Bool { verdictYes == accepted }

    /// `h ? $f(net / h) : "--"` — `nil` renders as `"--"`.
    public var netPerHour: Double? { minutes > 0 ? net / (minutes / 60) : nil }

    public var label: String {
        switch (verdictYes, accepted) {
        case (true, true): return "Said yes, you accepted"
        case (true, false): return "Said yes, you declined"
        case (false, true): return "Said no, you accepted"
        case (false, false): return "Said no, you declined"
        }
    }
}

public enum VerdictMatrix {

    /// The four cells in the web table's fixed order: yes/accepted,
    /// yes/declined, no/accepted, no/declined.
    public static func cells(_ rows: [LogRow], settings: VerdictSettings) -> [MatrixCell] {
        var cells = [(true, true), (true, false), (false, true), (false, false)].map {
            MatrixCell(verdictYes: $0.0, accepted: $0.1, orders: 0, net: 0, minutes: 0)
        }

        for row in rows where !row.isArchive {
            let index = (row.verdictIsYes ? 0 : 2) + (row.choiceTook ? 0 : 1)
            cells[index].orders += 1
            cells[index].net += Scoreboard.net(for: row, settings: settings)
            cells[index].minutes += row.numericMinutes
        }
        return cells
    }
}
