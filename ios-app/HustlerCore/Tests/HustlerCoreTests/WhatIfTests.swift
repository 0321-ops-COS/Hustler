import XCTest
@testable import HustlerCore

/// Every expectation here came from running the `#runWf` handler in `index.html`
/// inside a stubbed DOM (the way `tools/parity/oracle.mjs` observes the web
/// app), so a failure is a port divergence, not a hand-written guess.
final class WhatIfTests: XCTestCase {

    private let log = MasterLog.header + "\n" + [
        "| 2026-10-27 14:46 | 26.50 | 9.1 | 6 | 2.91 |  |  | TAKE IT | 80.00 | Accept | 15.25 |  |  |",
        "| 2026-10-27 15:10 | 4.25 | 6.2 | 2 | 0.69 |  |  | SKIP | 89.00 | Declined | 0 |  |  |",
        "| 2026-10-27 16:05 | 12.00 | 4.0 | 3 | 3.00 |  |  | TAKE IT | 87.00 | Accept | 12 | Temecula | 25 |",
        "| 2026-10-27 09:15 | 9.00 | 3.0 | 2 | 3.00 |  |  | TAKE IT |  | Accepted | 10 |  | 21.5 |",
        "| 2026-10-27 08:00 | 6.30 | 4.2 | 1 | 1.50 |  |  | SKIP | 90.00 | Declined | 0 |  | 15 |",
        "| 2026-10-27 07:30 | 5.00 | 4.0 | 1 | 1.25 |  |  | SKIP | 89.00 | Declined | 0 | Temecula | 12 |"
    ].joined(separator: "\n")

    private var rows: [LogRow] { MasterLog.orderedForAnalysis(MasterLogParser.parse(log)) }
    private var settings: AppSettings { AppSettings(zoneGas: ["Temecula": 6.5]) }

    /// The form values the changed scenario used.
    private var changedSettings: AppSettings {
        var change = settings
        change.accept = 80
        change.gas = 5
        change.mpg = 20
        change.wear = 0.10
        change.rampLow = 70
        change.floorMile = 0.5
        change.floorHour = 8
        change.baseMile = 1.2
        change.baseHour = 16
        change.emergency = 90
        return change
    }

    func testUnchangedReplayMatchesTheStoredVerdicts() {
        let replay = WhatIf.replay(rows: rows, settings: settings, change: settings)
        XCTAssertEqual(replay.decisions.count, 6)
        for decision in replay.decisions {
            XCTAssertEqual(decision.current.takeIt, decision.row.verdictIsYes, decision.row.dateWithTime)
            XCTAssertEqual(decision.changed, decision.current, decision.row.dateWithTime)
        }
        XCTAssertEqual(replay.flippedCount, 0)
        XCTAssertEqual(replay.summaryLine, "0 verdicts flipped, +$0 net")
        XCTAssertEqual(replay.acceptanceLine,
                       "Acceptance rate used: 89% now, 89% in your change. Assumes you follow each verdict.")
        XCTAssertEqual(replay.tableRows.map(\.label), ["Offers you'd take", "Net total", "Net $/hr"])
        XCTAssertEqual(replay.tableRows.map(\.currentText), ["3", "$40", "$26.36"])
        XCTAssertEqual(replay.current.hours, 91.3 / 60, accuracy: 1e-9)
    }

    func testChangedReplayMatchesTheWebOutput() {
        let replay = WhatIf.replay(rows: rows, settings: settings, change: changedSettings)
        XCTAssertEqual(replay.tableRows.map(\.currentText), ["3", "$40", "$26.36"])
        XCTAssertEqual(replay.tableRows.map(\.changedText), ["6", "$52", "$21.02"])
        XCTAssertEqual(replay.flippedCount, 3)
        XCTAssertEqual(replay.summaryLine, "3 verdicts flipped, +$12 net")
        XCTAssertEqual(replay.netDifference, 11.668428571428564, accuracy: 1e-9)
        // Ordered by date and time, as the web app's `rows` are.
        XCTAssertEqual(replay.flipped.map(\.offer), ["2026-10-27 Temecula", "2026-10-27 ", "2026-10-27 "])
        XCTAssertEqual(replay.flipped.map(\.payout), ["$4.83", "$6.30", "$4.25"])
        XCTAssertEqual(replay.flipped.map(\.miles), ["4", "4.2", "6.2"])
        XCTAssertEqual(replay.flipped.map(\.currentText), ["Pass", "Pass", "Pass"])
        XCTAssertEqual(replay.flipped.map(\.changedText), ["Take", "Take", "Take"])
    }

    func testBlankMinutesAreFilledTheWayTheWebDoes() {
        XCTAssertEqual(rows.first { $0.time == "14:46" }!.minutes, "44.8", "parse() derives 10 + 9.1*2.5 + 6*2")
        // A row handed in with no minutes cell at all falls back inside verdict().
        let bare = LogRow(date: "2026-10-27", payout: "9.00", miles: "3.0", items: "2",
                          verdict: "TAKE IT", rate: "89", minutes: "")
        let replay = WhatIf.replay(rows: [bare], settings: settings, change: settings)
        XCTAssertEqual(replay.decisions[0].current.minutes, 21.5, accuracy: 1e-9)
        XCTAssertEqual(Money.format(replay.decisions[0].current.netPerHour), "$21.36")
        XCTAssertEqual(replay.current.hours, 21.5 / 60, accuracy: 1e-9)
    }

    func testBlankAcceptanceBoxAndEmptyLogMatchTheWeb() {
        var zeroed = settings
        WhatIf.Field.accept.set(Money.parse(""), in: &zeroed)
        XCTAssertEqual(zeroed.accept, 0, "draft() reads a blank box as 0")
        let replay = WhatIf.replay(rows: rows, settings: settings, change: zeroed)
        XCTAssertEqual(replay.acceptanceLine,
                       "Acceptance rate used: 89% now, 0% in your change. Assumes you follow each verdict.")
        XCTAssertEqual(replay.tableRows.map(\.changedText), ["3", "$40", "$26.36"])
        XCTAssertEqual(replay.flippedCount, 0)

        XCTAssertFalse(WhatIf.replay(rows: [], settings: settings, change: zeroed).hasRows)
        XCTAssertEqual(WhatIf.emptyLogMessage, "Load a log first.")
    }

    func testFieldsAreTheNumbersAReplayReads() {
        XCTAssertEqual(WhatIf.Field.all.map(\.id), [
            "accept", "mpg", "wear", "gas", "rampTop", "rampLow", "floorMile", "floorHour",
            "baseMile", "baseHour", "bigItems", "bigMile", "bigHour", "emergency"
        ])
        XCTAssertEqual(WhatIf.Field.accept.text(in: settings), "89")
        XCTAssertEqual(WhatIf.Field.gas.text(in: settings), "5.75")

        var next = settings
        WhatIf.Field.baseHour.set(Money.parse("$20"), in: &next)
        XCTAssertEqual(WhatIf.Field.baseHour.text(in: next), "20")
        let replay = WhatIf.replay(rows: rows, settings: settings, change: next)
        XCTAssertLessThanOrEqual(replay.changed.taken, replay.current.taken)
        XCTAssertTrue(replay.decisions.allSatisfy { !$0.changed.takeIt || $0.current.takeIt })
    }
}
