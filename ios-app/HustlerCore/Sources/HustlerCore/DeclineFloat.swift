import Foundation

/// The decline-float card, ported from `renderFloat()` (`index.html:526`).
///
/// The web app never observes individual declines. It derives them from an
/// acceptance rate over the last 100 offers:
///
///     rate     = LOGACC ?? settings.accept
///     declined = max(0, round(100 - rate))
///     left     = (100 - target) - declined
///
/// `left` equals `rate - target` only for a whole-numbered rate: `100 - rate` is
/// rounded to whole declines first, so a logged 87.5% shows 2 left, not 2.5.
/// It only moves when a newer row's acceptance-rate cell is written, which is
/// why the copy says declines "roll off the last 100".
///
/// Two quirks are preserved rather than corrected:
/// - `target` falls back to 85 when it is zero/unparseable (`num(S.target) || 85`).
/// - With no acceptance data at all the card still reports a float from the
///   default 89% settings rate. That is defect **B11**; it is documented and
///   left alone here, because hiding it changes what the app tells the user.
public enum DeclineFloat {

    public enum State: String, Equatable, Sendable {
        /// `left > 3`
        case ok
        /// `1...3`
        case low
        /// `left == 0`
        case none
        /// `left < 0`
        case past
    }

    public struct Result: Equatable, Sendable {
        /// The acceptance rate the calculation used.
        public let rate: Double
        /// The target after the `|| 85` fallback.
        public let target: Double
        /// `declined` tile: declines within the last 100 offers.
        public let declinedInLast100: Int
        /// `left` tile. Kept fractional because the target may be fractional.
        public let declinesLeft: Double
        public let state: State
        public let message: String
    }

    public static let defaultTarget: Double = 85

    /// - Parameters:
    ///   - loggedRate: `LOGACC`, the newest logged acceptance rate, if any.
    ///   - settingsRate: `S.accept`, used when no log rate exists.
    ///   - target: `S.target`; zero or non-finite means 85.
    public static func compute(
        loggedRate: Double?,
        settingsRate: Double,
        target: Double
    ) -> Result {
        let rate = loggedRate ?? settingsRate
        let goal = (target.isFinite && target != 0) ? target : defaultTarget

        let declined = max(0, Int((100 - rate).rounded()))
        let left = (100 - goal) - Double(declined)

        let state: State
        let message: String
        if left <= 0 {
            if left < 0 {
                state = .past
                let past = -left
                message = "NO FLOAT. You are " + JsNumber.description(past)
                    + " decline" + (past == 1 ? "" : "s")
                    + " past your " + JsNumber.description(goal)
                    + "% target. Accept offers until old declines roll off the last 100."
            } else {
                state = .none
                message = "NO FLOAT. Your next decline drops you under "
                    + JsNumber.description(goal) + "%. Take what comes."
            }
        } else if left <= 3 {
            state = .low
            message = "LOW. " + JsNumber.description(left)
                + " decline" + (left == 1 ? "" : "s")
                + " left before you drop under " + JsNumber.description(goal) + "%."
        } else {
            state = .ok
            message = "OK. You can pass on " + JsNumber.description(left)
                + " more before you drop under " + JsNumber.description(goal) + "%."
        }

        return Result(
            rate: rate,
            target: goal,
            declinedInLast100: declined,
            declinesLeft: left,
            state: state,
            message: message
        )
    }
}
