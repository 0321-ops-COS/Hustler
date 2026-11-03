import XCTest
@testable import HustlerCore

/// The Check screen's port of `#calc`: field parsing, rate precedence and the
/// verdict wording. `VerdictEngine`'s numbers are pinned by `VerdictParityTests`.
final class CheckModelTests: XCTestCase {

    private func model(_ payout: String, _ miles: String, items: String = "", minutes: String = "",
                       gas: String = "", rate: String = "89", rows: [LogRow] = []) -> CheckModel {
        var model = CheckModel(rows: rows)
        let texts: [CheckModel.Field: String] = [
            .payout: payout, .miles: miles, .items: items,
            .minutes: minutes, .gasToday: gas, .rate: rate
        ]
        for (field, text) in texts { model.setText(text, for: field) }
        return model
    }

    private func verdict(_ model: CheckModel) -> CheckModel.Verdict? {
        guard case let .verdict(verdict) = model.outcome() else { return nil }
        return verdict
    }

    private func stats(_ verdict: CheckModel.Verdict) -> [String: String] {
        Dictionary(uniqueKeysWithValues: verdict.stats.map { ($0.label, $0.value) })
    }

    private func row(rate: String = "", choice: String = "Accept") -> LogRow {
        LogRow(date: "2026-10-27", time: "12:00", payout: "8", miles: "3", items: "1",
               rate: rate, choice: choice)
    }

    func testTakeWhenBothBarsClear() throws {
        let verdict = try XCTUnwrap(verdict(model("12.50", "4.2", items: "3", minutes: "25")))
        XCTAssertTrue(verdict.result.takeIt)
        XCTAssertEqual(verdict.headline, "TAKE IT")
        XCTAssertEqual(stats(verdict), [
            "Net after car": "$10.62",
            "Net $/hr (need $16.40)": "$25.48",
            "Payout $/mile (need $1.35)": "$2.98",
            "Minutes": "25"
        ])
    }

    func testSkipWhenUnderAHourlyBar() throws {
        let verdict = try XCTUnwrap(verdict(model("4", "6", items: "2", minutes: "30")))
        XCTAssertFalse(verdict.result.takeIt)
        XCTAssertEqual(verdict.headline, "SKIP")
        XCTAssertEqual(stats(verdict)["Net after car"], "$1.31")
        XCTAssertEqual(stats(verdict)["Net $/hr (need $16.40)"], "$2.62")
    }

    /// Below `emergency`, a positive net takes the offer even under a bar.
    func testEmergencyRateTakesPositiveNet() throws {
        let verdict = try XCTUnwrap(verdict(model("5", "4", items: "1", minutes: "20", rate: "79")))
        XCTAssertTrue(verdict.result.takeIt)
        XCTAssertEqual(stats(verdict)["Net $/hr (need $10.00)"], "$9.62")
    }

    func testBlankMinutesUsesShortcutFormula() throws {
        let verdict = try XCTUnwrap(verdict(model("9", "3", items: "2")))
        XCTAssertEqual(verdict.result.minutes, 21.5, accuracy: 1e-9)
        XCTAssertEqual(verdict.minutesText, "22")
        XCTAssertEqual(stats(verdict)["Net after car"], "$7.65")
    }

    func testGarbageInputsParseAsZeroLikeNum() throws {
        let model = model("12.50", "4.2", items: "lots", minutes: "soon", gas: "n/a", rate: "high")
        let verdict = try XCTUnwrap(verdict(model))
        XCTAssertEqual(verdict.result.minutes, 20.5, accuracy: 1e-9)
        XCTAssertEqual(stats(verdict)["Net after car"], "$10.62")
        XCTAssertEqual(model.resolvedRate.source, .settings)
    }

    func testBlankOrGarbagePayoutAndMilesAskAgain() {
        for (payout, miles) in [("", "4"), ("abc", "4"), ("12", ""), ("12", "x"), ("0", "4")] {
            XCTAssertEqual(model(payout, miles, items: "1").outcome(), .needsPayoutAndMiles, "\(payout)/\(miles)")
        }
    }

    func testRatePrecedence() {
        let rows = [row(rate: "80"), row(rate: "91")]
        XCTAssertEqual(model("12", "4", rate: "87.5", rows: rows).resolvedRate,
                       CheckModel.ResolvedRate(rate: 87.5, source: .typed))
        XCTAssertEqual(model("12", "4", rate: "", rows: rows).resolvedRate,
                       CheckModel.ResolvedRate(rate: 91, source: .newestLogged))
        let choices = [row(choice: "Accept"), row(choice: "Declined")]
        XCTAssertEqual(model("12", "4", rate: "", rows: choices).resolvedRate,
                       CheckModel.ResolvedRate(rate: 50, source: .logImplied))
        XCTAssertEqual(model("12", "4", rate: "").resolvedRate,
                       CheckModel.ResolvedRate(rate: 89, source: .settings))
    }

    func testGasTodayOverridesTheSettingForThisCheckOnly() throws {
        let model = model("12.50", "4.2", items: "3", minutes: "25", gas: "6.50")
        XCTAssertEqual(stats(try XCTUnwrap(verdict(model)))["Net after car"], "$10.44")
        XCTAssertEqual(model.settings.gas, 5.75, "the stored price must not move")
    }

    func testLogRateHintAndUseIt() {
        var model = model("12", "4", rate: "", rows: [row(choice: "Accept"), row(choice: "Declined")])
        XCTAssertEqual(model.logRateHint, "Your log shows 50%.")
        XCTAssertNil(CheckModel().logRateHint)

        model.useLogRate()
        XCTAssertEqual(model.text(for: .rate), "50")
        XCTAssertEqual(model.resolvedRate.source, .typed)
    }
}
