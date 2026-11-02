import Foundation

/// Presentation for the Home screen's decline-float card. No arithmetic: the
/// rate comes from `AcceptanceLogic` (`LOGACC`, else the stored setting) and the
/// numbers from `DeclineFloat`; this type only names the state, its severity and
/// the card's wording, so the card cannot disagree with the float elsewhere.
public enum HomeFloat {

    /// `.ok` is green, `.low` orange, exhausted red. Grouped here so the view has
    /// no state of its own to decide.
    public enum Severity: String, Equatable, Sendable {
        case calm      // ok
        case warning   // low
        case critical  // none, past
    }

    public struct Card: Equatable, Sendable {
        public let state: DeclineFloat.State
        public let severity: Severity
        public let title: String
        /// Short figure line: `4 left`, `None left`, `5 past`.
        public let value: String
        /// The web app's sentence from `DeclineFloat`, unchanged.
        public let message: String
    }

    public static let title = "Decline float"

    public static func severity(for state: DeclineFloat.State) -> Severity {
        switch state {
        case .ok: return .calm
        case .low: return .warning
        case .none, .past: return .critical
        }
    }

    public static func card(from result: DeclineFloat.Result) -> Card {
        let value: String
        switch result.state {
        case .ok, .low: value = JsNumber.description(result.declinesLeft) + " left"
        case .none: value = "None left"
        case .past: value = JsNumber.description(-result.declinesLeft) + " past"
        }
        return Card(
            state: result.state,
            severity: severity(for: result.state),
            title: Self.title,
            value: value,
            message: result.message
        )
    }

    /// Home passes rows: the newest logged rate wins over the stored setting, as
    /// `AcceptanceLogic` decides. B11 is unchanged — no acceptance data still
    /// reports a float.
    public static func card(rows: [LogRow], settingsRate: Double, target: Double) -> Card {
        card(from: DeclineFloat.compute(
            loggedRate: AcceptanceLogic.newestLoggedRate(rows),
            settingsRate: settingsRate,
            target: target
        ))
    }
}
