import XCTest
@testable import HustlerCore

/// Values come from rendering the web app's own `renderFloat()` across a grid of
/// acceptance rates and targets, with the panel's HTML parsed back
/// (`tools/parity/expectations.json`, section `float`).
final class DeclineFloatTests: XCTestCase {

    private struct FloatCase {
        let rate: Double?
        let target: Double
        let declined: Int
        let left: Double
        let state: String
        let message: String
    }

    private let settingsRate: Double = 89

    private let cases: [FloatCase] = [
        FloatCase(rate: nil, target: 85, declined: 11, left: 4, state: "ok", message: "OK. You can pass on 4 more before you drop under 85%."),
        FloatCase(rate: nil, target: 90, declined: 11, left: -1, state: "past", message: "NO FLOAT. You are 1 decline past your 90% target. Accept offers until old declines roll off the last 100."),
        FloatCase(rate: nil, target: 0, declined: 11, left: 4, state: "ok", message: "OK. You can pass on 4 more before you drop under 85%."),

        FloatCase(rate: 100, target: 85, declined: 0, left: 15, state: "ok", message: "OK. You can pass on 15 more before you drop under 85%."),
        FloatCase(rate: 100, target: 90, declined: 0, left: 10, state: "ok", message: "OK. You can pass on 10 more before you drop under 90%."),
        FloatCase(rate: 100, target: 0, declined: 0, left: 15, state: "ok", message: "OK. You can pass on 15 more before you drop under 85%."),

        FloatCase(rate: 95, target: 85, declined: 5, left: 10, state: "ok", message: "OK. You can pass on 10 more before you drop under 85%."),
        FloatCase(rate: 95, target: 90, declined: 5, left: 5, state: "ok", message: "OK. You can pass on 5 more before you drop under 90%."),
        FloatCase(rate: 95, target: 0, declined: 5, left: 10, state: "ok", message: "OK. You can pass on 10 more before you drop under 85%."),

        FloatCase(rate: 90, target: 85, declined: 10, left: 5, state: "ok", message: "OK. You can pass on 5 more before you drop under 85%."),
        FloatCase(rate: 90, target: 90, declined: 10, left: 0, state: "none", message: "NO FLOAT. Your next decline drops you under 90%. Take what comes."),
        FloatCase(rate: 90, target: 0, declined: 10, left: 5, state: "ok", message: "OK. You can pass on 5 more before you drop under 85%."),

        FloatCase(rate: 89, target: 85, declined: 11, left: 4, state: "ok", message: "OK. You can pass on 4 more before you drop under 85%."),
        FloatCase(rate: 89, target: 90, declined: 11, left: -1, state: "past", message: "NO FLOAT. You are 1 decline past your 90% target. Accept offers until old declines roll off the last 100."),
        FloatCase(rate: 89, target: 0, declined: 11, left: 4, state: "ok", message: "OK. You can pass on 4 more before you drop under 85%."),

        FloatCase(rate: 87.5, target: 85, declined: 13, left: 2, state: "low", message: "LOW. 2 declines left before you drop under 85%."),
        FloatCase(rate: 87.5, target: 90, declined: 13, left: -3, state: "past", message: "NO FLOAT. You are 3 declines past your 90% target. Accept offers until old declines roll off the last 100."),
        FloatCase(rate: 87.5, target: 0, declined: 13, left: 2, state: "low", message: "LOW. 2 declines left before you drop under 85%."),

        FloatCase(rate: 85, target: 85, declined: 15, left: 0, state: "none", message: "NO FLOAT. Your next decline drops you under 85%. Take what comes."),
        FloatCase(rate: 85, target: 90, declined: 15, left: -5, state: "past", message: "NO FLOAT. You are 5 declines past your 90% target. Accept offers until old declines roll off the last 100."),
        FloatCase(rate: 85, target: 0, declined: 15, left: 0, state: "none", message: "NO FLOAT. Your next decline drops you under 85%. Take what comes."),

        FloatCase(rate: 80, target: 85, declined: 20, left: -5, state: "past", message: "NO FLOAT. You are 5 declines past your 85% target. Accept offers until old declines roll off the last 100."),
        FloatCase(rate: 80, target: 90, declined: 20, left: -10, state: "past", message: "NO FLOAT. You are 10 declines past your 90% target. Accept offers until old declines roll off the last 100."),
        FloatCase(rate: 80, target: 0, declined: 20, left: -5, state: "past", message: "NO FLOAT. You are 5 declines past your 85% target. Accept offers until old declines roll off the last 100."),

        FloatCase(rate: 70, target: 85, declined: 30, left: -15, state: "past", message: "NO FLOAT. You are 15 declines past your 85% target. Accept offers until old declines roll off the last 100."),
        FloatCase(rate: 70, target: 90, declined: 30, left: -20, state: "past", message: "NO FLOAT. You are 20 declines past your 90% target. Accept offers until old declines roll off the last 100."),
        FloatCase(rate: 70, target: 0, declined: 30, left: -15, state: "past", message: "NO FLOAT. You are 15 declines past your 85% target. Accept offers until old declines roll off the last 100.")
    ]

    func testDepletionMatchesWebApp() {
        for testCase in cases {
            let result = DeclineFloat.compute(
                loggedRate: testCase.rate,
                settingsRate: settingsRate,
                target: testCase.target
            )
            let label = "rate=\(String(describing: testCase.rate)) target=\(testCase.target)"
            XCTAssertEqual(result.declinedInLast100, testCase.declined, label)
            XCTAssertEqual(result.declinesLeft, testCase.left, label)
            XCTAssertEqual(result.state.rawValue, testCase.state, label)
            XCTAssertEqual(result.message, testCase.message, label)
            XCTAssertEqual(result.target, testCase.target == 0 ? 85 : testCase.target, label)
        }
    }

    /// The log's own rate wins over the stored setting, which is why the card can
    /// disagree with the Scoreboard's Acceptance tile.
    func testLoggedRateTakesPrecedence() {
        let withLog = DeclineFloat.compute(loggedRate: 87.5, settingsRate: 89, target: 85)
        XCTAssertEqual(withLog.rate, 87.5)
        XCTAssertEqual(withLog.declinesLeft, 2)

        let withoutLog = DeclineFloat.compute(loggedRate: nil, settingsRate: 89, target: 85)
        XCTAssertEqual(withoutLog.rate, 89)
        XCTAssertEqual(withoutLog.declinesLeft, 4)
    }

    /// Documented defect B11: with no acceptance data the card still reports a
    /// float from the default rate instead of asking for the rate. Preserved
    /// here so a future fix is a deliberate, visible change.
    func testB11MissingRateStillReportsAFloat() {
        let result = DeclineFloat.compute(loggedRate: nil, settingsRate: 89, target: 85)
        XCTAssertEqual(result.declinesLeft, 4)
        XCTAssertEqual(result.state, .ok)
    }

    /// The card counts whole declines first:
    /// `left = (100 - target) - round(100 - rate)`. That equals `rate - target`
    /// only for a whole-numbered rate, so a 87.5% rate reports 2, not 2.5.
    func testLeftCountsWholeDeclines() {
        for rate in stride(from: 60.0, through: 100.0, by: 0.5) {
            let result = DeclineFloat.compute(loggedRate: rate, settingsRate: 89, target: 85)
            XCTAssertEqual(result.declinesLeft, (100 - 85) - Double(result.declinedInLast100), accuracy: 1e-9)
            if rate == rate.rounded() {
                XCTAssertEqual(result.declinesLeft, rate - 85, accuracy: 1e-9)
            }
        }
        XCTAssertEqual(DeclineFloat.compute(loggedRate: 87.5, settingsRate: 89, target: 85).declinesLeft, 2)
    }
}
