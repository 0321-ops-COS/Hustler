import XCTest
@testable import HustlerCore

/// The Earnings page's numbers and wording. Every statement and delivery here is
/// invented; no real statement text or earnings figure appears.
final class EarningsPageTests: XCTestCase {
    private enum Fixture {
        static let book: StatementBook = {
            var book = StatementBook()
            _ = book.take(["March 2026 Statement Total Payouts $3,000.00 Payouts (150)",
                           "April 2026 Statement Total Payouts $1,000.00 Payouts (20)"])
            return book
        }()
        static func archive(_ date: String, minutes: String = "30") -> LogRow {
            LogRow(date: date, payout: "7.00", miles: "5.0", items: "2",
                   choice: "Accepted", minutes: minutes, source: "archive")
        }
        /// 30 March deliveries (a Monday), 30 April deliveries (a Friday).
        static let rows = (1...30).map { _ in archive("2026-03-02") }
            + (1...30).map { _ in archive("2026-04-03") }
    }
    func testNoStatementsRendersNothing() {
        let page = EarningsPage(statements: StatementBook(), rows: Fixture.rows)
        XCTAssertTrue(page.months.isEmpty)
        XCTAssertEqual(page.tiles.count + page.months.count + page.days.count + page.notes.count, 0)
    }
    func testPageMatchesTheWeb() {
        let page = EarningsPage(statements: Fixture.book, rows: Fixture.rows)
        XCTAssertEqual(page.tiles.map(\.label),
                       ["Earned, 2 months", "Payouts", "Per delivery", "Per active hour"])
        // $4000 over 60 deliveries and 30 active hours. `$f()` has no commas.
        XCTAssertEqual(page.tiles.map(\.value), ["$4000", "170", "$66.67", "$133.33"])
        XCTAssertEqual(page.months.map(\.cells), [
            ["2026-03", "$3000.00", "150", "30", "$100.00", "$200.00"],
            ["2026-04", "$1000.00", "20", "30", "$33.33", "$66.67"]
        ])
        XCTAssertEqual(page.days.map(\.day), EarningsPage.dayNames)
        XCTAssertEqual(page.days.map(\.deliveries), [0, 30, 0, 0, 0, 30, 0])
        XCTAssertEqual(page.days[1].share, 1, accuracy: 1e-9)
        XCTAssertEqual(page.notes, [
            "Best pay per delivery: 2026-03 at $100.00. Lowest: 2026-04 at $33.33. "
                + "The gap is what a better offer mix is worth.",
            "Mon is your busiest day with 30 deliveries, and Sun is your quietest with 0.",
            "Statements show total pay only. They don't split base pay, tips and peak pay, "
                + "and they have no miles. Logging offers with the shortcut is what shows which zones and offer types pay."
        ])
        // Only a month with 30+ deliveries is ranked in the best-pay note.
        let thin = EarningsPage(statements: Fixture.book, rows: [Fixture.archive("2026-03-02")])
        XCTAssertFalse(thin.notes[0].hasPrefix("Best pay per delivery"))
    }
    func testAnImpossibleDateCountsAsADeliveryButNotAsADay() {
        let rows = [Fixture.archive("2026-03-02"), Fixture.archive("2026-03-32", minutes: "60")]
        let page = EarningsPage(statements: Fixture.book, rows: rows)
        // `slice(0, 7)` still matches the statement month...
        XCTAssertEqual(page.months[0].deliveries, "2")
        XCTAssertEqual(page.months[0].perActiveHour, "$2000.00")
        // ...but `new Date(...)` is NaN, so no weekday is counted.
        XCTAssertEqual(page.days.map(\.deliveries).reduce(0, +), 1)
    }
    /// B1 as the web app has it: the statement total is the month's paid figure,
    /// and accepted shortcut pay is not a delivery and is not subtracted.
    func testShortcutPayIsNotADeliveryOrASubtraction() {
        let rows = [Fixture.archive("2026-03-02", minutes: "10"),
                    Fixture.archive("2026-03-03", minutes: "20"),
                    LogRow(date: "2026-03-03", time: "18:20", payout: "250.00", miles: "5.0",
                           items: "2", choice: "Accepted")]
        let page = EarningsPage(statements: Fixture.book, rows: rows)
        XCTAssertEqual(page.months[0].paid, "$3000.00")
        XCTAssertEqual(page.months[0].deliveries, "2")
        XCTAssertEqual(page.months[0].perDelivery, "$1500.00")
        XCTAssertEqual(page.tiles[0].value, "$4000")
    }
}
