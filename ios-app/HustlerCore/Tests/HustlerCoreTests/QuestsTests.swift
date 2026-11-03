import XCTest
@testable import HustlerCore

/// Expected values come from running the web app's own `weekAggs()`,
/// `questState()` and `renderQuests()` in Node against this exact log; the
/// arithmetic is hand-checked in the comments.
final class QuestsTests: XCTestCase {

    /// Wednesday 2026-11-04, noon local, so the current week is Monday 11-02.
    private var clock: HomeClock {
        var c = DateComponents(); c.year = 2026; c.month = 11; c.day = 4; c.hour = 12
        return .fixed(Calendar(identifier: .gregorian).date(from: c)!)
    }

    private func accepted(
        _ date: String, net: Double, miles: Double, minutes: Double, _ verdict: String = "TAKE IT"
    ) -> LogRow {
        LogRow(date: date, payout: "\(net)", miles: "\(miles)", net: "\(net)", verdict: verdict, choice: "Accept", minutes: "\(minutes)")
    }

    private func declined(_ date: String, _ verdict: String) -> LogRow {
        LogRow(date: date, payout: "5", miles: "2", net: "0", verdict: verdict, choice: "Declined", minutes: "10")
    }

    /// Six Monday-keyed weeks. `2026-09-28` is the fifth prior week, so
    /// `slice(-4)` must leave its $500 week out of every baseline.
    private var log: [LogRow] {
        Array(repeating: accepted("2026-09-28", net: 100, miles: 2, minutes: 12), count: 5)
        + Array(repeating: accepted("2026-10-05", net: 20, miles: 10, minutes: 120), count: 5)
        + [accepted("2026-10-12", net: 10, miles: 5, minutes: 60)]
        + [accepted("2026-10-19", net: 100, miles: 40, minutes: 300), accepted("2026-10-19", net: 100, miles: 30, minutes: 300), accepted("2026-10-19", net: 100, miles: 30, minutes: 300)]
        + [accepted("2026-10-26", net: 45, miles: 10, minutes: 150), accepted("2026-10-26", net: 45, miles: 10, minutes: 150)]
        + [accepted("2026-11-02", net: 60, miles: 20, minutes: 180), accepted("2026-11-02", net: 50, miles: 10, minutes: 120), accepted("2026-11-02", net: 40, miles: 5, minutes: 60, "SKIP"), declined("2026-11-02", "SKIP")]
        + Array(repeating: declined("2026-11-02", "TAKE IT"), count: 4) + [declined("2026-11-02", "SKIP")]
    }

    func testWeekAggsMatchesTheWebPerWeekCounters() throws {
        let weeks = Quests.weekAggs(log)
        XCTAssertEqual(weeks.count, 6)
        XCTAssertEqual(try XCTUnwrap(weeks["2026-11-02"]), Quests.WeekAggregate(accepted: 3, net: 150, miles: 35, minutes: 360, archive: 0, logged: 9, followed: 4, yes: 6, yesAccepted: 2))
        XCTAssertEqual(try XCTUnwrap(weeks["2026-09-28"]), Quests.WeekAggregate(accepted: 5, net: 500, miles: 10, minutes: 60, archive: 0, logged: 5, followed: 5, yes: 5, yesAccepted: 5))
    }

    /// An archive row is an accepted delivery but not a logged offer, and a
    /// blank Net cell falls back to payout minus car cost.
    func testArchiveWeekCountsAsAcceptedButNotLogged() throws {
        let archive = LogRow(
            date: "2026-11-02", payout: "10", miles: "5", net: "",
            verdict: "", choice: "Accepted", minutes: "20", source: "archive"
        )
        let week = try XCTUnwrap(Quests.weekAggs([archive])["2026-11-02"])
        XCTAssertEqual(week.accepted, 1)
        XCTAssertEqual(week.archive, 1)
        XCTAssertEqual(week.logged, 0)
        XCTAssertEqual(week.net, 7.757142857142857, accuracy: 1e-12) // 10 - 5 × (5.75 / 17.5 + 0.12)
    }

    func testQuestStateUsesOnlyTheLastFourExistingWeeks() throws {
        let state = Quests.questState(Quests.weekAggs(log), week: "2026-11-02")

        // Only 2026-10-05 has five accepted rows among the last four weeks; the
        // excluded 2026-09-28 week would have made this $500.
        let net = try XCTUnwrap(state[.net])
        XCTAssertEqual(net.baseline, 100)
        XCTAssertEqual(net.target, 105)
        XCTAssertEqual(net.value, 150)

        let npm = try XCTUnwrap(state[.npm]) // (100+300+90) / (50+100+20), then ×1.02
        XCTAssertEqual(try XCTUnwrap(npm.baseline), 490.0 / 170.0, accuracy: 1e-12)
        XCTAssertEqual(try XCTUnwrap(npm.target), 2.94, accuracy: 1e-12)
        XCTAssertEqual(try XCTUnwrap(npm.value), 150.0 / 35.0, accuracy: 1e-12)

        let nph = try XCTUnwrap(state[.nph]) // 490 / (10+15+5) hours, then ×1.02
        XCTAssertEqual(try XCTUnwrap(nph.baseline), 490.0 / 30.0, accuracy: 1e-12)
        XCTAssertEqual(try XCTUnwrap(nph.target), 16.66, accuracy: 1e-12)
        XCTAssertEqual(nph.value, 25)

        let fol = try XCTUnwrap(state[.fol])
        XCTAssertEqual([fol.baseline, fol.target], [85, 85])
        XCTAssertEqual(try XCTUnwrap(fol.value), 100 * 4.0 / 9.0, accuracy: 1e-12)
        let pick = try XCTUnwrap(state[.pick])
        XCTAssertEqual([pick.baseline, pick.target], [90, 90])
        XCTAssertEqual(try XCTUnwrap(pick.value), 100 * 2.0 / 6.0, accuracy: 1e-12)
    }

    func testCardMatchesTheWebWordingAndStates() throws {
        let card = Quests.card(rows: log, clock: clock)
        XCTAssertEqual(card.title, "This week's quests")
        XCTAssertEqual(card.summary, "Targets are set from your own last 4 weeks, so they rise as you improve and refresh every Monday. Streak: 1 followed in a row. Best: 18.")
        XCTAssertEqual(card.rows.map(\.name), ["Net earnings", "Net $ per mile", "Net $ per active hour", "Followed the verdict", "Took the offers it said yes to"])
        XCTAssertEqual(card.rows.map(\.kind), [.estimate, .estimate, .estimate, .measured, .measured])
        XCTAssertEqual(card.rows.map(\.valueText), ["$150 / $105", "$4.29 / $2.94", "$25.00 / $16.66", "44% / 85%", "33% / 90%"])
        XCTAssertEqual(card.rows[0].state, .tracked(done: true))
        XCTAssertEqual(card.rows[3].state, .tracked(done: false))
        XCTAssertNil(card.rows[0].hint)
        XCTAssertEqual(try XCTUnwrap(card.rows[3].progress), 44.44444444444444 / 85, accuracy: 1e-12)
        XCTAssertEqual(try XCTUnwrap(card.rows[4].progress), 100.0 / 3 / 90, accuracy: 1e-12)
        XCTAssertEqual([card.lifetimeLabel, card.lifetimeText], ["Lifetime net (estimate)", "$1150 / $2500"])
        XCTAssertEqual(card.lifetimeProgress, 0.46, accuracy: 1e-12)
        XCTAssertEqual(card.footer, "Lifetime: 4 weekly quests cleared over 3 weeks. Lifetime totals never reset. Measured = counted straight from your log. Estimate = uses your car-cost settings and offer or archive time and miles, so tips and final pay can differ.")
    }

    func testFirstWeekBuildsABaselineAndEmptyLogShowsNothing() throws {
        let first = Quests.card(rows: [
            accepted("2026-11-02", net: 60, miles: 20, minutes: 180),
            accepted("2026-11-02", net: 50, miles: 10, minutes: 120),
            accepted("2026-11-02", net: 40, miles: 5, minutes: 60)
        ], clock: clock)
        XCTAssertEqual(first.rows[0].state, .buildingBaseline)
        XCTAssertEqual(first.rows[0].valueText, "$150")
        XCTAssertEqual(first.rows[0].hint, "Building your baseline: needs a finished prior week.")
        XCTAssertEqual(first.rows[3].state, .notEnoughData, "three offers are under the eight needed")

        let empty = Quests.card(rows: [], clock: clock)
        XCTAssertEqual(empty.summary, "Targets are set from your own last 4 weeks, so they rise as you improve and refresh every Monday. Streak: 0 followed in a row. Best: 0.")
        XCTAssertEqual(empty.rows.map(\.valueText), Array(repeating: "--", count: 5))
        XCTAssertEqual(empty.rows.first?.hint, "Not enough logged this week yet.")
        XCTAssertEqual(empty.lifetimeText, "$0 / $100")
        XCTAssertEqual(empty.lifetimeProgress, 0)
        XCTAssertTrue(empty.footer.hasPrefix("Lifetime: 0 weekly quests cleared over 0 weeks."))
    }

    func testNiceRoundsUpToTheNextOneTwoAndAHalfOrFive() {
        XCTAssertEqual([0, 99, 100, 250, 499, 1150, 5e11].map(Quests.nice), [100, 100, 250, 500, 500, 2500, 1e12])
    }
}
