import XCTest
@testable import HustlerCore

/// Every value here was captured by running the web app's `analyze()` on the
/// same fixture inside the parity oracle and parsing the tables it rendered
/// (`tools/parity/expectations.json`, section `analytics`). Sequence order is
/// part of the expectation.
final class AnalyticsTests: XCTestCase {

    private struct ZoneCase {
        let zone: String
        let orders: Int
        let netPerHour: String
        let netPerMile: String
    }

    private struct HourCase {
        let hour: Int
        let label: String
        let orders: Int
        let netPerHour: String
    }

    private struct MonthCase {
        let month: String
        let orders: Int
        let gross: String
        let miles: String
        let net: String
        let mileage: String
    }

    private struct TaxCase {
        let gross: String
        let miles: String
        let deduction: String
        let taxable: String
    }

    private let settings = VerdictSettings()
    /// The web app's `DEF.taxRate`, the flat mileage deduction rate.
    private let taxRate: Double = 0.70

    private var rows: [LogRow] {
        MasterLog.orderedForAnalysis(MasterLogParser.parse(Fixtures.analytics))
    }

    private let zoneCases: [ZoneCase] = [
        ZoneCase(zone: "Menifee", orders: 1, netPerHour: "$30.64", netPerMile: "$1.92"),
        ZoneCase(zone: "Murrieta", orders: 1, netPerHour: "$29.89", netPerMile: "$2.46"),
        ZoneCase(zone: "Temecula", orders: 2, netPerHour: "$13.55", netPerMile: "$1.24")
    ]

    private let hourCases: [HourCase] = [
        HourCase(hour: 0, label: "12am", orders: 1, netPerHour: "$15.98"),
        HourCase(hour: 9, label: "9am", orders: 1, netPerHour: "$27.18"),
        HourCase(hour: 12, label: "12pm", orders: 2, netPerHour: "$22.98"),
        HourCase(hour: 14, label: "2pm", orders: 1, netPerHour: "$29.89"),
        HourCase(hour: 18, label: "6pm", orders: 1, netPerHour: "$9.51")
    ]

    private let monthCases: [MonthCase] = [
        MonthCase(month: "2026-11", orders: 2, gross: "$17.00", miles: "8", net: "$14.32", mileage: "$5.60"),
        MonthCase(month: "2026-10", orders: 4, gross: "$56.50", miles: "20", net: "$46.24", mileage: "$14.07"),
        MonthCase(month: "2026-09", orders: 1, gross: "$10.00", miles: "4", net: "$7.66", mileage: "$2.80")
    ]

    private let taxCase = TaxCase(gross: "$83.50", miles: "32.1", deduction: "$22.47", taxable: "$61.03")

    func testZoneBreakdownMatchesWebApp() {
        let totals = Analytics.zones(rows, settings: settings)
        XCTAssertEqual(totals.count, zoneCases.count, "zone row count")
        for (index, expected) in zoneCases.enumerated() where index < totals.count {
            let actual = totals[index]
            let label = "zone[\(index)]"
            XCTAssertEqual(actual.zone, expected.zone, label)
            XCTAssertEqual(actual.orders, expected.orders, label)
            XCTAssertEqual(actual.netPerHour.map { Money.format($0) } ?? "--", expected.netPerHour, label)
            XCTAssertEqual(actual.netPerMile.map { Money.format($0) } ?? "--", expected.netPerMile, label)
        }
    }

    func testHourBreakdownMatchesWebApp() {
        let totals = Analytics.hours(rows, settings: settings)
        XCTAssertEqual(totals.count, hourCases.count, "hour row count")
        for (index, expected) in hourCases.enumerated() where index < totals.count {
            let actual = totals[index]
            let label = "hour[\(index)]"
            XCTAssertEqual(actual.hour, expected.hour, label)
            XCTAssertEqual(actual.label, expected.label, label)
            XCTAssertEqual(actual.orders, expected.orders, label)
            XCTAssertEqual(actual.netPerHour.map { Money.format($0) } ?? "--", expected.netPerHour, label)
        }
    }

    func testMonthBreakdownMatchesWebApp() {
        let totals = Analytics.months(rows, settings: settings, taxRate: taxRate)
        XCTAssertEqual(totals.count, monthCases.count, "month row count")
        for (index, expected) in monthCases.enumerated() where index < totals.count {
            let actual = totals[index]
            let label = "month[\(index)]"
            XCTAssertEqual(actual.month, expected.month, label)
            XCTAssertEqual(actual.orders, expected.orders, label)
            XCTAssertEqual(Money.format(actual.gross), expected.gross, label)
            XCTAssertEqual(JsNumber.toFixed(actual.miles, places: 0), expected.miles, label)
            XCTAssertEqual(Money.format(actual.net), expected.net, label)
            XCTAssertEqual(Money.format(actual.mileageDeduction), expected.mileage, label)
        }
    }

    func testTaxEstimateMatchesWebApp() {
        let estimate = Analytics.taxEstimate(rows, settings: settings, taxRate: taxRate)
        XCTAssertEqual(Money.format(estimate.gross), taxCase.gross)
        XCTAssertEqual(JsNumber.toFixed(estimate.miles, places: 1), taxCase.miles)
        XCTAssertEqual(Money.format(estimate.mileageDeduction), taxCase.deduction)
        XCTAssertEqual(Money.format(estimate.taxable), taxCase.taxable)
    }

    /// Rows without a zone fall out of the zone table, and the declined offer is
    /// not money, so it appears in none of the four panels.
    func testExcludedRows() {
        XCTAssertFalse(Analytics.zones(rows, settings: settings).contains { $0.zone.isEmpty })
        let zoneOrders = Analytics.zones(rows, settings: settings).reduce(0) { $0 + $1.orders }
        XCTAssertEqual(zoneOrders, 4, "only the four accepted, zoned rows")
        let hourOrders = Analytics.hours(rows, settings: settings).reduce(0) { $0 + $1.orders }
        XCTAssertEqual(hourOrders, 6, "the declined row and the timeless row are excluded")
        let monthOrders = Analytics.months(rows, settings: settings, taxRate: taxRate).reduce(0) { $0 + $1.orders }
        XCTAssertEqual(monthOrders, 7, "every accepted row has a date")
    }

    /// Months are newest first; hours are ascending; zones are ordered by net per
    /// active hour, descending.
    func testOrdering() {
        let months = Analytics.months(rows, settings: settings, taxRate: taxRate).map { $0.month }
        XCTAssertEqual(months, months.sorted(by: >))

        let hours = Analytics.hours(rows, settings: settings).map { $0.hour }
        XCTAssertEqual(hours, hours.sorted())

        let rates = Analytics.zones(rows, settings: settings).map { $0.net / max(1, $0.minutes) }
        XCTAssertEqual(rates, rates.sorted(by: >))
    }

    /// The tax panel is a flat mileage deduction: doubling the rate doubles the
    /// deduction and lowers taxable income by the same amount. No brackets, no
    /// credits, no other expenses — that is the existing model, documented rather
    /// than extended.
    func testTaxEstimateIsLinearInTheRate() {
        let base = Analytics.taxEstimate(rows, settings: settings, taxRate: 0.70)
        let doubled = Analytics.taxEstimate(rows, settings: settings, taxRate: 1.40)
        XCTAssertEqual(doubled.mileageDeduction, base.mileageDeduction * 2, accuracy: 1e-9)
        XCTAssertEqual(doubled.taxable, base.gross - base.mileageDeduction * 2, accuracy: 1e-9)
        XCTAssertEqual(base.taxable, base.gross - base.mileageDeduction, accuracy: 1e-9)
    }

    /// A zero-mile log deducts nothing and leaves gross as taxable income.
    func testTaxEstimateWithNoMiles() {
        let only = MasterLogParser.parse(Fixtures.headerLiteral + "\n"
            + "| 2026-10-27 14:46 | 12.00 | 0 | 1 | 0.00 | 12.00 | 30.00 | TAKE IT | 89 | Accept | 0 |  | 24 |")
        let estimate = Analytics.taxEstimate(only, settings: settings, taxRate: 0.70)
        XCTAssertEqual(estimate.mileageDeduction, 0, accuracy: 1e-12)
        XCTAssertEqual(estimate.taxable, estimate.gross, accuracy: 1e-12)
    }

    /// Hour labels use a 12-hour clock with no leading zero, and both midnight and
    /// noon read as 12.
    func testHourLabels() {
        XCTAssertEqual(HourTotals(hour: 0, orders: 0, net: 0, minutes: 0).label, "12am")
        XCTAssertEqual(HourTotals(hour: 1, orders: 0, net: 0, minutes: 0).label, "1am")
        XCTAssertEqual(HourTotals(hour: 12, orders: 0, net: 0, minutes: 0).label, "12pm")
        XCTAssertEqual(HourTotals(hour: 13, orders: 0, net: 0, minutes: 0).label, "1pm")
        XCTAssertEqual(HourTotals(hour: 23, orders: 0, net: 0, minutes: 0).label, "11pm")
    }
}
