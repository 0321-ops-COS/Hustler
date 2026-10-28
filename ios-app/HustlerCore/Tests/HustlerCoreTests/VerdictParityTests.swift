import XCTest
@testable import HustlerCore

/// Every expectation here was produced by running `verdict()` from
/// `index.html` inside the parity oracle, so a failure means the port diverged
/// from the web app rather than from a hand-written guess.
final class VerdictParityTests: XCTestCase {

    private struct VerdictCase {
        let id: String
        let payout: Double
        let miles: Double
        let items: Double
        let minutes: Double
        let zone: String
        let rate: Double
        let zoneGas: [String: Double]
        let takeIt: Bool
        let minutesOut: Double
        let net: String
        let hourly: String
        let perMile: String
        let requiredMile: String
        let requiredHour: String
    }

    private let cases: [VerdictCase] = [
        VerdictCase(id: "base_rate89", payout: 12.50, miles: 4.2, items: 3, minutes: 25, zone: "", rate: 89, zoneGas: [:], takeIt: true, minutesOut: 25, net: "$10.62", hourly: "$25.48", perMile: "$2.98", requiredMile: "$1.35", requiredHour: "$16.40"),
        VerdictCase(id: "rate90_base_bars", payout: 12.50, miles: 4.2, items: 3, minutes: 25, zone: "", rate: 90, zoneGas: [:], takeIt: true, minutesOut: 25, net: "$10.62", hourly: "$25.48", perMile: "$2.98", requiredMile: "$1.50", requiredHour: "$18.00"),
        VerdictCase(id: "rate85_floor_bars", payout: 12.50, miles: 4.2, items: 3, minutes: 25, zone: "", rate: 85, zoneGas: [:], takeIt: true, minutesOut: 25, net: "$10.62", hourly: "$25.48", perMile: "$2.98", requiredMile: "$0.75", requiredHour: "$10.00"),
        VerdictCase(id: "rate87_5_mid_ramp", payout: 12.50, miles: 4.2, items: 3, minutes: 25, zone: "", rate: 87.5, zoneGas: [:], takeIt: true, minutesOut: 25, net: "$10.62", hourly: "$25.48", perMile: "$2.98", requiredMile: "$1.13", requiredHour: "$14.00"),
        VerdictCase(id: "rate95_clamped", payout: 12.50, miles: 4.2, items: 3, minutes: 25, zone: "", rate: 95, zoneGas: [:], takeIt: true, minutesOut: 25, net: "$10.62", hourly: "$25.48", perMile: "$2.98", requiredMile: "$1.50", requiredHour: "$18.00"),
        VerdictCase(id: "rate80_clamped", payout: 12.50, miles: 4.2, items: 3, minutes: 25, zone: "", rate: 80, zoneGas: [:], takeIt: true, minutesOut: 25, net: "$10.62", hourly: "$25.48", perMile: "$2.98", requiredMile: "$0.75", requiredHour: "$10.00"),
        VerdictCase(id: "emergency_79_positive", payout: 2.00, miles: 8.0, items: 1, minutes: 20, zone: "", rate: 79, zoneGas: [:], takeIt: false, minutesOut: 20, net: "$-1.59", hourly: "$-4.77", perMile: "$0.25", requiredMile: "$0.75", requiredHour: "$10.00"),
        VerdictCase(id: "emergency_79_negative", payout: 1.00, miles: 9.0, items: 1, minutes: 20, zone: "", rate: 79, zoneGas: [:], takeIt: false, minutesOut: 20, net: "$-3.04", hourly: "$-9.11", perMile: "$0.11", requiredMile: "$0.75", requiredHour: "$10.00"),
        VerdictCase(id: "big_order_items4", payout: 12.50, miles: 4.2, items: 4, minutes: 25, zone: "", rate: 87, zoneGas: [:], takeIt: true, minutesOut: 25, net: "$10.62", hourly: "$25.48", perMile: "$2.98", requiredMile: "$1.25", requiredHour: "$14.00"),
        VerdictCase(id: "base_order_items3", payout: 12.50, miles: 4.2, items: 3, minutes: 25, zone: "", rate: 87, zoneGas: [:], takeIt: true, minutesOut: 25, net: "$10.62", hourly: "$25.48", perMile: "$2.98", requiredMile: "$1.05", requiredHour: "$13.20"),
        VerdictCase(id: "zero_miles", payout: 6.00, miles: 0, items: 1, minutes: 12, zone: "", rate: 89, zoneGas: [:], takeIt: true, minutesOut: 12, net: "$6.00", hourly: "$30.00", perMile: "$6.00", requiredMile: "$1.35", requiredHour: "$16.40"),
        VerdictCase(id: "blank_minutes", payout: 9.00, miles: 3.0, items: 2, minutes: 0, zone: "", rate: 89, zoneGas: [:], takeIt: true, minutesOut: 21.5, net: "$7.65", hourly: "$21.36", perMile: "$3.00", requiredMile: "$1.35", requiredHour: "$16.40"),
        VerdictCase(id: "negative_minutes", payout: 9.00, miles: 3.0, items: 2, minutes: -5, zone: "", rate: 89, zoneGas: [:], takeIt: true, minutesOut: 21.5, net: "$7.65", hourly: "$21.36", perMile: "$3.00", requiredMile: "$1.35", requiredHour: "$16.40"),
        VerdictCase(id: "zone_gas", payout: 12.50, miles: 4.2, items: 3, minutes: 25, zone: "Temecula", rate: 89, zoneGas: ["Temecula": 6.5], takeIt: true, minutesOut: 25, net: "$10.44", hourly: "$25.05", perMile: "$2.98", requiredMile: "$1.35", requiredHour: "$16.40"),
        VerdictCase(id: "exact_base_bar", payout: 6.30, miles: 4.2, items: 1, minutes: 15, zone: "", rate: 90, zoneGas: [:], takeIt: false, minutesOut: 15, net: "$4.42", hourly: "$17.66", perMile: "$1.50", requiredMile: "$1.50", requiredHour: "$18.00"),
        VerdictCase(id: "rate_zero", payout: 12.50, miles: 4.2, items: 3, minutes: 25, zone: "", rate: 0, zoneGas: [:], takeIt: true, minutesOut: 25, net: "$10.62", hourly: "$25.48", perMile: "$2.98", requiredMile: "$0.75", requiredHour: "$10.00")
    ]

    func testVerdictMatchesWebApp() {
        for testCase in cases {
            let settings = VerdictSettings(zoneGas: testCase.zoneGas)
            let offer = VerdictOffer(
                payout: testCase.payout,
                miles: testCase.miles,
                items: testCase.items,
                minutes: testCase.minutes,
                zone: testCase.zone
            )
            let result = VerdictEngine.evaluate(offer, settings: settings, rate: testCase.rate)

            XCTAssertEqual(result.takeIt, testCase.takeIt, testCase.id)
            XCTAssertEqual(result.minutes, testCase.minutesOut, accuracy: 1e-9, testCase.id)
            XCTAssertEqual(Money.format(result.net), testCase.net, testCase.id)
            XCTAssertEqual(Money.format(result.netPerHour), testCase.hourly, testCase.id)
            XCTAssertEqual(Money.format(result.payoutPerMile), testCase.perMile, testCase.id)
            XCTAssertEqual(Money.format(result.requiredMile), testCase.requiredMile, testCase.id)
            XCTAssertEqual(Money.format(result.requiredHour), testCase.requiredHour, testCase.id)
        }
    }

    func testRampMatchesWebApp() {
        let settings = VerdictSettings()
        XCTAssertEqual(VerdictEngine.ramp(settings, rate: 90), 0, accuracy: 1e-12)
        XCTAssertEqual(VerdictEngine.ramp(settings, rate: 89), 0.2, accuracy: 1e-12)
        XCTAssertEqual(VerdictEngine.ramp(settings, rate: 87.5), 0.5, accuracy: 1e-12)
        XCTAssertEqual(VerdictEngine.ramp(settings, rate: 85), 1, accuracy: 1e-12)
        XCTAssertEqual(VerdictEngine.ramp(settings, rate: 80), 1, accuracy: 1e-12)
        XCTAssertEqual(VerdictEngine.ramp(settings, rate: 95), 0, accuracy: 1e-12)
        XCTAssertEqual(VerdictEngine.ramp(settings, rate: 0), 1, accuracy: 1e-12)
    }

    /// A zero-width ramp is `0/0` in the web app, i.e. NaN, which fails closed.
    func testZeroWidthRampFailsClosed() {
        let settings = VerdictSettings(rampTop: 90, rampLow: 90)
        XCTAssertTrue(VerdictEngine.ramp(settings, rate: 88).isNaN)
        let result = VerdictEngine.evaluate(
            VerdictOffer(payout: 20, miles: 4, items: 1, minutes: 20),
            settings: settings,
            rate: 88
        )
        XCTAssertFalse(result.takeIt)
    }

    func testDefaultMinutesIsUnrounded() {
        XCTAssertEqual(VerdictEngine.defaultMinutes(miles: 3.0, items: 2), 21.5, accuracy: 1e-12)
    }
}
