import XCTest
@testable import HustlerCore

/// The card only colours and labels what `DeclineFloat` already decided, so the
/// numbers here are the same `DeclineFloatTests` cases, reached through
/// `HomeFloat`.
final class HomeFloatTests: XCTestCase {

    func testEveryStateMapsToItsColour() {
        XCTAssertEqual(HomeFloat.tone(for: .ok), .green)
        XCTAssertEqual(HomeFloat.tone(for: .low), .orange)
        XCTAssertEqual(HomeFloat.tone(for: .none), .red, "none and past are both stop states")
        XCTAssertEqual(HomeFloat.tone(for: .past), .red)
    }

    func testOkCardIsGreenWithDeclinesLeft() {
        let card = HomeFloat.card(rows: [], settingsRate: 89, target: 85)
        XCTAssertEqual(card.state, .ok)
        XCTAssertEqual(card.tone, .green)
        XCTAssertEqual(card.title, "Decline float")
        XCTAssertEqual(card.value, "4 declines left")
        XCTAssertEqual(card.message, "OK. You can pass on 4 more before you drop under 85%.")
        XCTAssertEqual(card.caption, "From 89% acceptance, 85% target.")
    }

    func testLowCardIsOrange() {
        let card = HomeFloat.card(rows: [], settingsRate: 87.5, target: 85)
        XCTAssertEqual(card.state, .low)
        XCTAssertEqual(card.tone, .orange)
        XCTAssertEqual(card.value, "2 declines left", "whole declines, as DeclineFloat counts them")
        XCTAssertEqual(card.message, "LOW. 2 declines left before you drop under 85%.")
        XCTAssertEqual(card.caption, "From 87.5% acceptance, 85% target.")
    }

    func testNoneCardIsRed() {
        let card = HomeFloat.card(rows: [], settingsRate: 85, target: 85)
        XCTAssertEqual(card.state, .none)
        XCTAssertEqual(card.tone, .red)
        XCTAssertEqual(card.value, "No float")
        XCTAssertEqual(card.message, "NO FLOAT. Your next decline drops you under 85%. Take what comes.")
    }

    func testPastCardIsRedAndCountsPastDeclines() {
        let card = HomeFloat.card(rows: [], settingsRate: 80, target: 85)
        XCTAssertEqual(card.state, .past)
        XCTAssertEqual(card.tone, .red)
        XCTAssertEqual(card.value, "5 past")
        XCTAssertEqual(card.message, "NO FLOAT. You are 5 declines past your 85% target. Accept offers until old declines roll off the last 100.")
    }

    /// The log's newest rate wins over the stored setting, and the state follows
    /// it: 87.5% with an 85% target is low, not the ok the default 89% would give.
    func testNewestLoggedRateOverridesTheSetting() {
        let rows = MasterLog.orderedForAnalysis(MasterLogParser.parse(Fixtures.rateOlderAndNewest))
        let card = HomeFloat.card(rows: rows, settingsRate: 89, target: 85)
        XCTAssertEqual(card.state, .low)
        XCTAssertEqual(card.tone, .orange)
        XCTAssertEqual(card.caption, "From 87.5% acceptance, 85% target.")
    }

    /// A log whose newest rate cell is blank keeps the last logged rate, so the
    /// card agrees with `AcceptanceLogic.newestLoggedRate`.
    func testBlankNewestRateFallsBackToTheNewestLoggedOne() {
        let rows = MasterLog.orderedForAnalysis(MasterLogParser.parse(Fixtures.rateBlankNewest))
        let card = HomeFloat.card(rows: rows, settingsRate: 89, target: 85)
        XCTAssertEqual(card.caption, "From 91% acceptance, 85% target.")
        XCTAssertEqual(card.state, .ok)
        XCTAssertEqual(card.value, "6 declines left")
    }

    /// Documented defect B11 is carried over unchanged: with no acceptance data
    /// at all the card still reports a float from the default 89% rate instead of
    /// asking for one. Pinned so a fix is a deliberate change.
    func testB11WithNoLogDataStillUsesTheDefaultRate() {
        let card = HomeFloat.card(rows: [])
        XCTAssertEqual(card.state, .ok)
        XCTAssertEqual(card.value, "4 declines left")
        XCTAssertEqual(card.caption, "From 89% acceptance, 85% target.")
    }

    /// A zero target falls back to 85 inside `DeclineFloat`, and the card must
    /// show the target actually used rather than the raw setting.
    func testCaptionShowsTheTargetActuallyUsed() {
        let card = HomeFloat.card(rows: [], settingsRate: 89, target: 0)
        XCTAssertEqual(card.caption, "From 89% acceptance, 85% target.")
    }
}
