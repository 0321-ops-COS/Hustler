import XCTest
@testable import HustlerCore

/// Wording here is transcribed from `renderStart()` and `renderMaster()` in
/// `index.html`; the comments name the state each case pins.
final class HomeHeaderCardsTests: XCTestCase {

    private func archive(_ date: String) -> LogRow {
        LogRow(date: date, time: "", payout: "7.00", miles: "5.0", items: "2",
               choice: "Accepted", minutes: "30", source: "archive")
    }

    // MARK: - Master file tile

    func testEmptyLog() {
        let card = HomeMasterTile.card(rows: [])
        XCTAssertEqual(card.title, "Master file")
        XCTAssertEqual(card.text, "Empty. Add rows or files to start it.")
    }

    func testLogWithOneRow() {
        let rows = MasterLogParser.parse(Fixtures.headerLiteral + "\n" + Fixtures.scoreboardFirstRow)
        XCTAssertEqual(HomeMasterTile.card(rows: rows).text, "1 row. Newest: 2026-10-27 14:46.")
    }

    func testLogWithRowsShowsTheNewestLastRow() {
        let rows = MasterLog.orderedForAnalysis(MasterLogParser.parse(Fixtures.scoreboardMixed))
        XCTAssertEqual(rows.count, 6)
        let card = HomeMasterTile.card(rows: rows)
        XCTAssertEqual(card.text, "6 rows. Newest: 2026-10-27 15:10.")
    }

    /// A row without a time keeps the web's `date + " " + time` spacing, which
    /// leaves one space before the full stop.
    func testNewestRowWithoutATime() {
        let rows = MasterLogParser.parse(Fixtures.headerLiteral + "\n" + Fixtures.analyticsNoTime)
        XCTAssertEqual(HomeMasterTile.card(rows: rows).text, "1 row. Newest: 2026-10-20 .")
    }

    // MARK: - Start card

    func testFreshInstallStartsHere() {
        let card = HomeStartCard.card(rows: [], statementMonths: [],
                                      hasAcceptanceRate: false, acceptanceRate: 89)
        XCTAssertEqual(card.title, "Start here")
        XCTAssertFalse(card.isComplete)
        XCTAssertEqual(card.lead, "Bring in your real history first so every number builds on your account, not a blank page.")
        XCTAssertEqual(card.steps.map(\.title),
                       ["DoorDash data_archive.zip", "Monthly statement PDFs", "Your acceptance rate"])
        XCTAssertEqual(card.steps.map(\.isDone), [false, false, false])
        XCTAssertEqual(card.steps.map(\.action), ["Add", "Add", ""])
        XCTAssertEqual(card.steps[0].detail, "Gives every delivery's date, time, store and item count.")
        XCTAssertEqual(card.steps[1].detail, "Sets exact monthly pay. Without them, pay is only a flat estimate.")
        XCTAssertEqual(card.steps[2].detail, "In DoorDash, open Ratings > Acceptance rate and copy the Accepted and Declined counts from Last 100 offers.")
        XCTAssertNil(card.note)
    }

    func testArchiveOnlyCountsDeliveries() {
        let rows = [archive("2026-10-25"), archive("2026-10-24")]
        let card = HomeStartCard.card(rows: rows, statementMonths: [],
                                      hasAcceptanceRate: false, acceptanceRate: 89)
        XCTAssertTrue(card.steps[0].isDone)
        XCTAssertEqual(card.steps[0].detail, "2 deliveries loaded")
        XCTAssertEqual(card.steps[0].action, "Open")
        XCTAssertFalse(card.steps[1].isDone)
        XCTAssertFalse(card.isComplete)
        XCTAssertNil(card.note, "no archive month has a statement, so nothing is exact yet")
    }

    /// Only archive rows contribute months; a shortcut-only log leaves the step open.
    func testShortcutRowsDoNotCountAsAnArchive() {
        let shortcut = LogRow(date: "2026-11-02", payout: "10.00", choice: "Accept")
        let card = HomeStartCard.card(rows: [shortcut], statementMonths: [],
                                      hasAcceptanceRate: false, acceptanceRate: 89)
        XCTAssertFalse(card.steps[0].isDone)
        XCTAssertEqual(card.steps[0].action, "Add")
        XCTAssertEqual(card.steps[0].detail, "Gives every delivery's date, time, store and item count.")
    }

    func testOneStatementReadKeepsTheWebPlural() {
        let rows = [archive("2026-10-25")]
        let card = HomeStartCard.card(rows: rows, statementMonths: ["2026-10"],
                                      hasAcceptanceRate: false, acceptanceRate: 89)
        XCTAssertTrue(card.steps[1].isDone)
        XCTAssertEqual(card.steps[1].detail, "1 months read. These set your exact monthly pay.")
        XCTAssertEqual(card.steps[1].action, "Open")
        XCTAssertEqual(card.note, "Exact: 2026-10 (monthly total is your statement). Per-delivery pay and miles are always estimates that add up to the statement total.")
    }

    /// Months at or after the first statement month are estimated; earlier
    /// months are dropped, exactly as `k>=ex[0]` filters them.
    func testMonthsAfterTheFirstStatementAreEstimated() {
        let rows = [archive("2026-08-15"), archive("2026-09-30"), archive("2026-10-25")]
        let card = HomeStartCard.card(rows: rows, statementMonths: ["2026-09"],
                                      hasAcceptanceRate: false, acceptanceRate: 89)
        XCTAssertEqual(card.note, "Exact: 2026-09 (monthly total is your statement). Estimated: 2026-10 (no statement yet, pay uses your per-delivery estimate). Per-delivery pay and miles are always estimates that add up to the statement total.")
    }

    /// A statement for a month with no archive rows is not exact, and with no
    /// exact month the web shows no month sentence at all.
    func testStatementForNoArchiveMonthHasNoSentence() {
        let rows = [archive("2026-10-25")]
        let card = HomeStartCard.card(rows: rows, statementMonths: ["2026-11"],
                                      hasAcceptanceRate: false, acceptanceRate: 89)
        XCTAssertTrue(card.steps[1].isDone)
        XCTAssertNil(card.note)
        XCTAssertFalse(card.isComplete)
    }

    func testAllThreeStepsShowYourNumbers() {
        let rows = [archive("2026-10-25")]
        let card = HomeStartCard.card(rows: rows, statementMonths: ["2026-10"],
                                      hasAcceptanceRate: true, acceptanceRate: 89)
        XCTAssertTrue(card.isComplete)
        XCTAssertEqual(card.title, "Your numbers")
        XCTAssertNil(card.lead)
        XCTAssertTrue(card.steps.isEmpty)
        XCTAssertEqual(card.note, "Exact: 2026-10 (monthly total is your statement). Per-delivery pay and miles are always estimates that add up to the statement total.")
    }

    func testSavedRateIsReportedInTheStep() {
        let card = HomeStartCard.card(rows: [], statementMonths: [],
                                      hasAcceptanceRate: true, acceptanceRate: 87.5)
        XCTAssertEqual(card.steps[2].detail, "Saved at 87.5%.")
        XCTAssertTrue(card.steps[2].isDone)
        XCTAssertEqual(card.steps[2].action, "")
        XCTAssertEqual(card.title, "Start here", "a rate alone does not finish the card")
    }
}
