import XCTest
@testable import HustlerCore

/// The text here is the web app's `brief()` and `#cpBrief` output, with the two
/// page-naming phrases changed to the native app.
final class AIBriefTests: XCTestCase {

    private let defaultSettingsJSON = """
    {"accept":89,"estPay":7,"estMph":20,"mpg":17.5,"wear":0.12,"gas":5.75,\
    "rampTop":90,"rampLow":85,"floorMile":0.75,"floorHour":10,"baseMile":1.5,\
    "baseHour":18,"bigItems":3,"bigMile":2,"bigHour":20,"emergency":80,\
    "taxRate":0.7,"target":85,"caWage":16.9,"caPct":120,"caMile":0.37}
    """

    /// `JSON.stringify(S)` order, no spaces, and JavaScript's number printing:
    /// 0.70 is `0.7` and 16.90 is `16.9`, not the two decimals `Money` would
    /// add. The web brief prints bare numbers, so the text has no `$`.
    func testSettingsUseTheWebNumberFormatting() {
        let settingsLine = AIBrief.brief(settings: AppSettings())
            .components(separatedBy: "\n").last
        XCTAssertEqual(settingsLine, "Settings: " + defaultSettingsJSON)
        XCTAssertFalse(settingsLine?.contains("$") ?? true)

        XCTAssertEqual(JsNumber.description(0.70), "0.7")
        XCTAssertEqual(JsNumber.description(16.90), "16.9")
        XCTAssertEqual(Money.format(16.90), "$16.90", "money styling is not what brief() emits")
        XCTAssertFalse(AIBrief.brief(settings: AppSettings()).contains(Money.format(16.90)))
    }

    func testNonDefaultSettingsKeepTheWebKeyOrder() {
        var settings = AppSettings(accept: 92, gas: 6.05)
        settings.zoneGas = ["Temecula": 6.5]
        settings.accSet = true

        let line = AIBrief.brief(settings: settings).components(separatedBy: "\n").last
        XCTAssertEqual(
            line,
            "Settings: {\"accept\":92,\"estPay\":7,\"estMph\":20,\"mpg\":17.5,\"wear\":0.12,"
                + "\"gas\":6.05,\"rampTop\":90,\"rampLow\":85,\"floorMile\":0.75,\"floorHour\":10,"
                + "\"baseMile\":1.5,\"baseHour\":18,\"bigItems\":3,\"bigMile\":2,\"bigHour\":20,"
                + "\"emergency\":80,\"taxRate\":0.7,\"target\":85,\"caWage\":16.9,\"caPct\":120,"
                + "\"caMile\":0.37,\"zoneGas\":{\"Temecula\":6.5},\"accSet\":1}"
        )
    }

    func testTheLogIsIncludedInTheSameOrder() {
        let log = Fixtures.headerLiteral + "\n"
            + Fixtures.shortcutLine("2026-10-26", payout: "8.00") + "\n"
            + Fixtures.shortcutLine("2026-10-27", payout: "26.50")
        let text = AIBrief.copyText(settings: AppSettings(), log: log)

        XCTAssertEqual(text, AIBrief.brief(settings: AppSettings()) + "\n\nLOG:\n" + log)
        let first = try? XCTUnwrap(text.range(of: "2026-10-26"))
        let second = try? XCTUnwrap(text.range(of: "2026-10-27"))
        XCTAssertNotNil(first)
        XCTAssertNotNil(second)
        if let first, let second { XCTAssertLessThan(first.lowerBound, second.lowerBound) }
    }

    func testEmptyLogKeepsTheHeadingAndNothingElse() {
        let text = AIBrief.copyText(settings: AppSettings(), log: "")
        XCTAssertEqual(text, AIBrief.brief(settings: AppSettings()) + "\n\nLOG:\n")
        XCTAssertTrue(text.hasSuffix("LOG:\n"))
    }

    /// The only wording changes from `brief()`.
    func testWordingNamesTheNativeApp() {
        let brief = AIBrief.brief(settings: AppSettings())
        XCTAssertTrue(brief.contains("this native iOS app analyzes the log"))
        XCTAssertTrue(brief.contains("Rule used by the app:"))
        XCTAssertFalse(brief.contains("web page"))
        XCTAssertFalse(brief.contains("used by the page"))
        XCTAssertTrue(brief.hasPrefix("HUSTLE HQ HANDOFF\nApp: DoorDash offer analyzer."))
    }
}
