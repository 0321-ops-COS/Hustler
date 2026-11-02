import XCTest
@testable import HustlerCore

/// Hand-computed from `caAuto()`, `caMerge()`, `caEst()`, `caPace()` and `caProject()`
/// (`index.html:606-618`) with the defaults: an hour is `120/100 × 16.90 = 20.28`, a mile `0.37`.
final class CAPayGuaranteeTests: XCTestCase {
    private let rates = CAPayGuarantee.Rates()
    /// Week of Monday 2026-10-26: two accepted rows (30 pay, 90 minutes, 15
    /// miles), one declined row and one accepted row in the following week.
    private let weekRows = [
        LogRow(date: "2026-10-27", payout: "20.00", miles: "10", choice: "Accepted", minutes: "60"),
        LogRow(date: "2026-10-28", payout: "10.00", miles: "5", choice: "Accepted", minutes: "30"),
        LogRow(date: "2026-10-29", payout: "15.00", miles: "20", choice: "Declined", minutes: "60"),
        LogRow(date: "2026-11-02", payout: "99.00", miles: "9", choice: "Accepted", minutes: "60")
    ]
    private let weekKey = "2026-10-26"
    private var auto: CAPayGuarantee.AutoFigures { CAPayGuarantee.autoFigures(rows: weekRows, weekKey: weekKey) }

    func testAutoFiguresUseAcceptedRowsOfThatMondayWeekOnly() {
        XCTAssertEqual(PeriodGrouping.key(for: "2026-10-27", period: .week), weekKey)
        XCTAssertEqual(auto, CAPayGuarantee.AutoFigures(pay: 30, hours: 1.5, miles: 15, acceptedOffers: 2))
        XCTAssertEqual(CAPayGuarantee.autoFigures(rows: weekRows, weekKey: "2026-11-02"),
                       CAPayGuarantee.AutoFigures(pay: 99, hours: 1, miles: 9, acceptedOffers: 1))
    }

    func testNoEnteredValuesLeavesEveryFigureFromTheLog() {
        let merged = CAPayGuarantee.merged(auto, entry: nil)
        XCTAssertEqual(merged.pay, 30); XCTAssertEqual(merged.hours, 1.5)
        XCTAssertEqual(merged.miles, 15); XCTAssertEqual(merged.acceptedOffers, 2)
        XCTAssertTrue(merged.payFromLog && merged.hoursFromLog && merged.milesFromLog)
        // 20.28 × 1.5 + 0.37 × 15 = 30.42 + 5.55
        let estimate = CAPayGuarantee.estimate(merged, loggedMiles: 15, rates: rates)
        XCTAssertEqual(estimate.guarantee, 35.97, accuracy: 1e-9); XCTAssertEqual(estimate.miles, 15)
        XCTAssertEqual(estimate.milesSource, .fromLog)
        XCTAssertEqual(estimate.adjustment, 5.97, accuracy: 1e-9)
    }

    /// `m.pay>0?m.pay:a.pay`: any entry above zero wins, even below the log's;
    /// zero and missing entries never do.
    func testEnteredValuesWinAboveZeroButZeroNeverDoes() {
        let merged = CAPayGuarantee.merged(
            rows: weekRows, weekKey: weekKey,
            entries: [weekKey: CAPayGuarantee.Entry(pay: 20, hours: 2, miles: 30)]
        )
        XCTAssertEqual(merged.pay, 20, "above zero beats the log's 30")
        XCTAssertFalse(merged.payFromLog)
        XCTAssertEqual(merged.hours, 2); XCTAssertFalse(merged.hoursFromLog)
        XCTAssertEqual(merged.miles, 30); XCTAssertFalse(merged.milesFromLog)
        // 20.28 × 2 + 0.37 × 30 = 40.56 + 11.10
        let estimate = CAPayGuarantee.estimate(merged, loggedMiles: 15, rates: rates)
        XCTAssertEqual(estimate.guarantee, 51.66, accuracy: 1e-9)
        XCTAssertEqual(estimate.miles, 30); XCTAssertEqual(estimate.milesSource, .entered)
        XCTAssertEqual(estimate.adjustment, 31.66, accuracy: 1e-9)

        let higherPay = CAPayGuarantee.merged(
            rows: weekRows, weekKey: weekKey, entries: [weekKey: CAPayGuarantee.Entry(pay: 40)]
        )
        XCTAssertEqual(higherPay.pay, 40); XCTAssertFalse(higherPay.payFromLog)
        XCTAssertEqual(CAPayGuarantee.estimate(higherPay, loggedMiles: 15, rates: rates).adjustment, 0)

        let zeroed = CAPayGuarantee.merged(
            rows: weekRows, weekKey: weekKey,
            entries: [weekKey: CAPayGuarantee.Entry(pay: 0, hours: 0, miles: 0)]
        )
        XCTAssertEqual(zeroed, CAPayGuarantee.merged(auto, entry: nil))
        XCTAssertTrue(zeroed.payFromLog && zeroed.hoursFromLog && zeroed.milesFromLog)
    }
    func testZeroHoursStillOwesMiles() {
        let rows = [LogRow(date: "2026-10-27", payout: "2.00", miles: "", choice: "Accepted", minutes: "")]
        let merged = CAPayGuarantee.merged(rows: rows, weekKey: weekKey, entries: [:])
        XCTAssertEqual(merged.hours, 0); XCTAssertEqual(merged.miles, 0)
        // 20.28 × 0 + 0.37 × 12 = 4.44, minus 2.00 pay
        let estimate = CAPayGuarantee.estimate(merged, loggedMiles: 12, rates: rates)
        XCTAssertEqual(estimate.guarantee, 4.44, accuracy: 1e-9); XCTAssertEqual(estimate.miles, 12)
        XCTAssertEqual(estimate.adjustment, 2.44, accuracy: 1e-9)
    }

    /// `caEst()` takes the log's miles as a separate argument, used only when
    /// the merged miles are not above zero.
    func testMissingMilesFallBackToTheSuppliedLogMiles() {
        let rows = [LogRow(date: "2026-10-27", payout: "20.00", miles: "", choice: "Accepted", minutes: "60")]
        let merged = CAPayGuarantee.merged(
            rows: rows, weekKey: weekKey, entries: [weekKey: CAPayGuarantee.Entry(miles: 0)]
        )
        XCTAssertEqual(merged.miles, 0); XCTAssertTrue(merged.milesFromLog)
        // 20.28 × 1 + 0.37 × 12 = 20.28 + 4.44
        let estimate = CAPayGuarantee.estimate(merged, loggedMiles: 12, rates: rates)
        XCTAssertEqual(estimate.miles, 12); XCTAssertEqual(estimate.milesSource, .fromLog)
        XCTAssertEqual(estimate.guarantee, 24.72, accuracy: 1e-9)
        XCTAssertEqual(estimate.adjustment, 4.72, accuracy: 1e-9)
    }

    /// Binary-exact rates, so "never below zero" is checked at exactly 0.
    func testShortfallOfExactlyZero() {
        let exact = CAPayGuarantee.Rates(wage: 20, percent: 100, mile: 0.5)
        // 20 × 1.5 + 0.5 × 10 = 35 exactly
        let level = CAPayGuarantee.AutoFigures(pay: 35, hours: 1.5, miles: 10, acceptedOffers: 1)
        let estimate = CAPayGuarantee.estimate(CAPayGuarantee.merged(level, entry: nil), loggedMiles: 0, rates: exact)
        XCTAssertEqual(estimate.guarantee, 35); XCTAssertEqual(estimate.adjustment, 0)
        XCTAssertEqual(CAPayGuarantee.estimate(CAPayGuarantee.merged(level, entry: .init(pay: 40)),
                                               loggedMiles: 0, rates: exact).adjustment, 0)
        XCTAssertEqual(CAPayGuarantee.estimate(CAPayGuarantee.merged(level, entry: .init(pay: 30)),
                                               loggedMiles: 0, rates: exact).adjustment, 5)
    }
    func testPaceSumsTheLastFourWeeksWithAnActiveHour() {
        let rows = [
            LogRow(date: "2026-10-19", payout: "100", miles: "50", choice: "Accepted", minutes: "120"),
            LogRow(date: "2026-10-20", payout: "999", miles: "999", choice: "Declined", minutes: "600"),
            LogRow(date: "2026-10-26", payout: "40", miles: "10", choice: "Accepted", minutes: "60"),
            LogRow(date: "2026-11-02", payout: "90", miles: "90", choice: "Accepted", minutes: "300")
        ]
        let pace = CAPayGuarantee.pace(rows: rows, weekKey: weekKey)
        XCTAssertEqual(pace?.weeks, 2, "the following week is not counted yet")
        XCTAssertEqual(pace?.payPerHour ?? 0, 140.0 / 3.0, accuracy: 1e-9)
        XCTAssertEqual(pace?.milesPerHour ?? 0, 60.0 / 3.0, accuracy: 1e-9)
        XCTAssertEqual(pace?.averageHours ?? 0, 1.5, accuracy: 1e-9)
        let halfHour = [LogRow(date: "2026-10-27", payout: "10", miles: "5", choice: "Accepted", minutes: "30")]
        XCTAssertNil(CAPayGuarantee.pace(rows: halfHour, weekKey: weekKey))
        XCTAssertNil(CAPayGuarantee.pace(rows: [], weekKey: weekKey))
    }

    func testProjectionWithAndWithoutPace() {
        let merged = CAPayGuarantee.merged(auto, entry: nil)
        let pace = CAPayGuarantee.pace(rows: weekRows, weekKey: weekKey)
        XCTAssertEqual(pace?.payPerHour ?? 0, 20, accuracy: 1e-9)
        XCTAssertEqual(pace?.milesPerHour ?? 0, 10, accuracy: 1e-9)

        let withoutPace = CAPayGuarantee.project(merged, pace: nil, extraHours: 0, rates: rates)
        XCTAssertEqual(withoutPace.addedPay, 0); XCTAssertEqual(withoutPace.addedMiles, 0)
        XCTAssertEqual(withoutPace.hours, 1.5); XCTAssertEqual(withoutPace.miles, 15)
        XCTAssertEqual(withoutPace.pay, 30)
        XCTAssertEqual(withoutPace.guarantee, 35.97, accuracy: 1e-9)
        XCTAssertEqual(withoutPace.adjustment, 5.97, accuracy: 1e-9)
        XCTAssertEqual(withoutPace.total, 35.97, accuracy: 1e-9)
        XCTAssertEqual(withoutPace.soFarGuarantee, 35.97, accuracy: 1e-9)
        XCTAssertEqual(withoutPace.soFarAdjustment, 5.97, accuracy: 1e-9)

        // +2 h at 20 pay/h and 10 miles/h: 20.28 × 3.5 + 0.37 × 35 = 70.98 + 12.95
        let withPace = CAPayGuarantee.project(merged, pace: pace, extraHours: 2, rates: rates)
        XCTAssertEqual(withPace.addedPay, 40, accuracy: 1e-9)
        XCTAssertEqual(withPace.addedMiles, 20, accuracy: 1e-9)
        XCTAssertEqual(withPace.hours, 3.5, accuracy: 1e-9)
        XCTAssertEqual(withPace.miles, 35, accuracy: 1e-9)
        XCTAssertEqual(withPace.pay, 70, accuracy: 1e-9)
        XCTAssertEqual(withPace.guarantee, 83.93, accuracy: 1e-9)
        XCTAssertEqual(withPace.adjustment, 13.93, accuracy: 1e-9)
        XCTAssertEqual(withPace.total, 83.93, accuracy: 1e-9)
        XCTAssertEqual(withPace.soFarGuarantee, 35.97, accuracy: 1e-9)
        XCTAssertEqual(withPace.soFarAdjustment, 5.97, accuracy: 1e-9)

        // Preserved quirk: without a pace, extra hours raise the hour term only, as `renderCA()` hides.
        let noPace = CAPayGuarantee.project(merged, pace: nil, extraHours: 2, rates: rates)
        XCTAssertEqual(noPace.addedPay, 0); XCTAssertEqual(noPace.addedMiles, 0)
        XCTAssertEqual(noPace.hours, 3.5, accuracy: 1e-9)
        XCTAssertEqual(noPace.miles, 15, accuracy: 1e-9)
        XCTAssertEqual(noPace.pay, 30, accuracy: 1e-9)
        XCTAssertEqual(noPace.guarantee, 76.53, accuracy: 1e-9)
        XCTAssertEqual(noPace.adjustment, 46.53, accuracy: 1e-9)
    }
}
