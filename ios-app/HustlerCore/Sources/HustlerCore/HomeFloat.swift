import Foundation

/// The Home screen's decline-float card.
///
/// Presentation only: `DeclineFloat.compute` owns the numbers and the state, and
/// `AcceptanceLogic` owns which rate wins. `HomeFloat` adds the two things the
/// web app keeps outside `renderFloat()` — the colour class the panel gets
/// (green / orange / red) and the short text the card shows — so neither is
/// decided inside a SwiftUI view.
public enum HomeFloat {

    /// The card's colour, named as the web app's three classes are. Keeping the
    /// names here lets a test pin the colour without importing SwiftUI; the view
    /// maps them straight to `Color`.
    public enum Tone: String, Equatable, Sendable {
        case green
        case orange
        case red
    }

    public struct Card: Equatable, Sendable {
        /// The `DeclineFloat` state this card was built from, unchanged.
        public let state: DeclineFloat.State
        public let tone: Tone
        public let title: String
        /// Short value for the card's right-hand side, e.g. `4 declines left`.
        public let value: String
        /// `DeclineFloat`'s own message, passed through untouched.
        public let message: String
        /// Which rate and target the numbers came from.
        public let caption: String
    }

    /// `S.accept` and `S.target` from the web app's `DEF`. Settings persistence
    /// is not ported, so a fresh install uses the same defaults the web app does.
    public static let defaultSettingsRate: Double = 89
    public static let defaultTarget: Double = 85

    /// The card for one already-computed `DeclineFloat.Result`.
    public static func card(for result: DeclineFloat.Result) -> Card {
        Card(
            state: result.state,
            tone: tone(for: result.state),
            title: "Decline float",
            value: valueText(for: result),
            message: result.message,
            caption: "From " + JsNumber.description(result.rate) + "% acceptance, "
                + JsNumber.description(result.target) + "% target."
        )
    }

    /// Reads the newest logged rate (`LOGACC`) from `rows` and, when there is
    /// none, falls back to the stored rate — `LOGACC ?? S.accept` — before
    /// handing both to `DeclineFloat`. Pass rows in analysis order
    /// (`MasterLog.orderedForAnalysis`), as the web app's `renderFloat()` sees them.
    public static func card(
        rows: [LogRow],
        settingsRate: Double = defaultSettingsRate,
        target: Double = defaultTarget
    ) -> Card {
        let logged = AcceptanceLogic.newestLoggedRate(rows)
        return card(for: DeclineFloat.compute(
            loggedRate: AcceptanceLogic.effectiveRate(settings: settingsRate, logged: logged),
            settingsRate: settingsRate,
            target: target
        ))
    }

    /// `ok` → green, `low` → orange, `none` and `past` → red.
    public static func tone(for state: DeclineFloat.State) -> Tone {
        switch state {
        case .ok: return .green
        case .low: return .orange
        case .none, .past: return .red
        }
    }

    private static func valueText(for result: DeclineFloat.Result) -> String {
        switch result.state {
        case .ok, .low:
            let left = result.declinesLeft
            return JsNumber.description(left) + (left == 1 ? " decline left" : " declines left")
        case .none:
            return "No float"
        case .past:
            return JsNumber.description(-result.declinesLeft) + " past"
        }
    }
}
