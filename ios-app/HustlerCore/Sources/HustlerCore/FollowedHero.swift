import Foundation

/// The "Followed the call" hero card from `analyze()` (`index.html:136, 388-389`).
///
/// Non-archive rows only, the same population the Scoreboard's followed tile
/// uses: archive deliveries carry no verdict, so counting them would invent
/// agreement. The ring shows the rounded percent, or `--` when nothing is
/// logged, and fills to the same fraction as the web app's arc.
public struct FollowedHero: Equatable, Sendable {
    public let followed: Int
    public let loggedOffers: Int
    public let percent: Int
    public let message: String

    /// `fp + "%"`, or `"--"` when the web leaves the placeholder.
    public var ringText: String { loggedOffers > 0 ? String(percent) + "%" : "--" }

    /// `352 * (1 - fp / 100)` expressed as the fraction of the ring filled.
    public var arcFraction: Double { Double(percent) / 100 }

    public static func compute(_ rows: [LogRow]) -> FollowedHero {
        let logged = rows.filter { !$0.isArchive }
        guard !logged.isEmpty else {
            return FollowedHero(
                followed: 0, loggedOffers: 0, percent: 0,
                message: rows.isEmpty
                    ? "Load your log to see how often your choices matched the shortcut's verdict."
                    : "Archive rows have no verdicts. Log offers with the shortcut to see this."
            )
        }

        let followed = logged.filter { $0.verdictIsYes == $0.choiceTook }.count
        let percent = Int((100.0 * Double(followed) / Double(logged.count)).rounded())
        let status = percent >= 85 ? "Locked in." : "Room to tighten up."
        return FollowedHero(
            followed: followed, loggedOffers: logged.count, percent: percent,
            message: "\(followed) of \(logged.count) logged offers matched the verdict. " + status
        )
    }
}
