import Foundation

/// Home's "Followed the call" ring card and the archive note under the tiles,
/// ported from the Scoreboard half of `renderGame()` (`index.html:386-389`).
///
/// The web app measures the ring over *logged* offers only — rows the shortcut
/// wrote, never archive deliveries, because an archive row carries no verdict.
/// The note under the tiles then says how many of the counted rows came from
/// the archive instead.
///
/// That is the same population `Scoreboard.totals` uses for `followedPercent`,
/// so this card and the existing "Followed verdict" tile cannot disagree.
public enum HomeFollowCard {

    public struct Card: Equatable, Sendable {
        /// Every row the Scoreboard counted, archive included.
        public let totalOffers: Int
        /// Rows the shortcut logged: the population the percentage is over.
        public let loggedOffers: Int
        /// Logged rows whose verdict matched what was actually done.
        public let followedOffers: Int
        /// `Math.round(100 * followed / logged)`, or 0 with no logged rows.
        public let percent: Int
        /// `"85%"`, or `"--"` when the log has no rows at all.
        public let percentText: String
        /// The sentence beside the ring.
        public let text: String
        /// The archive sentence under the tiles; empty when nothing is archive.
        public let note: String

        /// `percent / 100` — the ring's filled fraction, so the view only strokes it.
        public var ringFill: Double { Double(percent) / 100 }
    }

    /// The card's heading, `renderGame()`'s `<h2>`.
    public static let title = "Followed the call"

    /// The percentage at or above which the card says "Locked in.".
    public static let lockedInPercent = 85

    /// The card for a whole log. `rows` is the same array `Scoreboard.totals`
    /// reads, so pass it in analysis order (`MasterLog.orderedForAnalysis`).
    public static func card(rows: [LogRow]) -> Card {
        let logged = rows.filter { !$0.isArchive }
        let followed = logged.filter { $0.verdictIsYes == $0.choiceTook }.count
        let percent = logged.isEmpty
            ? 0
            : Int((100.0 * Double(followed) / Double(logged.count)).rounded())

        let text: String
        if logged.isEmpty {
            text = "Archive rows have no verdicts. Log offers with the shortcut to see this."
        } else {
            text = "\(followed) of \(logged.count) logged offers matched the verdict. "
                + (percent >= lockedInPercent ? "Locked in." : "Room to tighten up.")
        }

        return Card(
            totalOffers: rows.count,
            loggedOffers: logged.count,
            followedOffers: followed,
            percent: percent,
            percentText: rows.isEmpty ? "--" : "\(percent)%",
            text: text,
            note: noteText(total: rows.count, logged: logged.count)
        )
    }

    private static func noteText(total: Int, logged: Int) -> String {
        total > logged
            ? "\(total - logged) deliveries come from your DoorDash archive, with estimated pay and miles."
            : ""
    }
}
