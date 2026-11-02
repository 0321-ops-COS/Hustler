import XCTest
@testable import HustlerCore

/// The card is presentation only: it follows `DeclineFloat` exactly and colours
/// `.none` and `.past` the same way.
final class HomeFloatTests: XCTestCase {

    private func card(rate: Double?, target: Double = 85) -> HomeFloat.Card {
        HomeFloat.card(from: DeclineFloat.compute(loggedRate: rate, settingsRate: 89, target: target))
    }

    func testOkIsCalm() {
        let card = card(rate: 95)
        XCTAssertEqual(card.state, .ok)
        XCTAssertEqual(card.severity, .calm)
        XCTAssertEqual(card.title, "Decline float")
        XCTAssertEqual(card.value, "10 left")
        XCTAssertEqual(card.message, "OK. You can pass on 10 more before you drop under 85%.")
    }

    func testLowIsWarning() {
        let card = card(rate: 87.5)
        XCTAssertEqual(card.state, .low)
        XCTAssertEqual(card.severity, .warning)
        XCTAssertEqual(card.value, "2 left")
        XCTAssertEqual(card.message, "LOW. 2 declines left before you drop under 85%.")
    }

    /// Both exhausted states are red, and neither reports a negative figure.
    func testExhaustedStatesAreCritical() {
        let none = card(rate: 85)
        XCTAssertEqual(none.state, .none)
        XCTAssertEqual(none.severity, .critical)
        XCTAssertEqual(none.value, "None left")

        let past = card(rate: 80)
        XCTAssertEqual(past.state, .past)
        XCTAssertEqual(past.severity, .critical)
        XCTAssertEqual(past.value, "5 past")
    }

    /// Every state the core can report has exactly one severity, so the view has
    /// nothing left to decide.
    func testEveryCoreStateIsMapped() {
        XCTAssertEqual(HomeFloat.severity(for: .ok), .calm)
        XCTAssertEqual(HomeFloat.severity(for: .low), .warning)
        XCTAssertEqual(HomeFloat.severity(for: .none), .critical)
        XCTAssertEqual(HomeFloat.severity(for: .past), .critical)
    }

    /// Home passes rows, not a rate: the newest logged rate (87.5) wins over the
    /// stored 89, so the card reports 2 left rather than 4.
    func testRowsUseNewestLoggedRate() {
        let rows = MasterLogParser.parse(Fixtures.rateOlderAndNewest)
        let card = HomeFloat.card(rows: rows, settingsRate: 89, target: 85)
        XCTAssertEqual(card.state, .low)
        XCTAssertEqual(card.value, "2 left")
    }

    /// B11 is preserved: with no acceptance data the card still reports a float
    /// from the stored rate rather than asking for one.
    func testNoRowsStillReportsADefaultFloat() {
        let card = HomeFloat.card(rows: [], settingsRate: 89, target: 85)
        XCTAssertEqual(card.state, .ok)
        XCTAssertEqual(card.value, "4 left")
    }
}
