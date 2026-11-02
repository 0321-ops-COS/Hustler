import XCTest
@testable import HustlerCore

/// Hand-checked against `analyze()` in `index.html`: the ladder and XP width at
/// line 413, and the hero text at line 389.
final class LevelProgressTests: XCTestCase {

    /// (deliveries, name, floor, ceiling, percent, deliveriesToNext)
    private let cases: [(Int, String, Int, Int, Double, Int)] = [
        (0, "Rookie", 0, 25, 0, 25),
        (24, "Rookie", 0, 25, 96, 1),
        (25, "Grinder", 25, 100, 0, 75),
        (99, "Grinder", 25, 100, 98.66666666666667, 1),
        (100, "Operator", 100, 300, 0, 200),
        (299, "Operator", 100, 300, 99.5, 1),
        (300, "Hustler", 300, 800, 0, 500),
        (799, "Hustler", 300, 800, 99.8, 1),
        (800, "Legend", 800, 1050, 0, 250),
        (1049, "Legend", 800, 1050, 99.6, 1),
        (1050, "Legend II", 1050, 1300, 0, 250),
        (1300, "Legend III", 1300, 1550, 0, 250),
        (10550, "Legend 40", 10550, 10800, 0, 250),
        (11000, "Legend 41", 10800, 11050, 80, 50)
    ]

    func testEveryLadderBoundaryMatchesTheWebApp() {
        for (deliveries, name, floor, ceiling, percent, toNext) in cases {
            let level = LevelProgress.compute(deliveries: deliveries)
            XCTAssertEqual(level.name, name, "\(deliveries)")
            XCTAssertEqual(level.floor, floor, "\(deliveries)")
            XCTAssertEqual(level.ceiling, ceiling, "\(deliveries)")
            XCTAssertEqual(level.toNext, toNext, "\(deliveries)")
            XCTAssertEqual(level.percent, percent, accuracy: 1e-9, "\(deliveries)")
        }
    }

    func testHeaderTextMatchesTheWebApp() {
        XCTAssertEqual(LevelProgress.compute(deliveries: 0).headerText, "Rookie · 0 deliveries")
        XCTAssertEqual(LevelProgress.compute(deliveries: 25).headerText, "Grinder · 25 deliveries")
        XCTAssertEqual(LevelProgress.compute(deliveries: 25).nextText, "75 deliveries to the next level")
    }

    /// `nd = acc.length`: accepted offers, archive rows included, declines not.
    func testDeliveriesCountAcceptedRowsOnly() {
        let rows = [LogRow(choice: "Accepted"), LogRow(choice: "Accept"),
                    LogRow(choice: "Declined"), LogRow(date: "2026-10-25", choice: "Accepted", source: "archive")]
        XCTAssertEqual(LevelProgress.compute(rows: rows).deliveries, 3)
    }
}

final class FollowedHeroTests: XCTestCase {
    private func logged(_ verdict: String, _ choice: String) -> LogRow {
        LogRow(verdict: verdict, choice: choice)
    }

    /// `total` logged offers of which `followed` match; the rest are TAKE IT declined.
    private func logged(_ followed: Int, of total: Int) -> [LogRow] {
        (0..<total).map { logged("TAKE IT", $0 < followed ? "Accepted" : "Declined") }
    }

    func testNoRowsKeepsThePlaceholder() {
        let hero = FollowedHero.compute([])
        XCTAssertEqual(hero.ringText, "--")
        XCTAssertEqual(hero.percent, 0)
        XCTAssertEqual(hero.arcFraction, 0)
        XCTAssertEqual(hero.message, "Load your log to see how often your choices matched the shortcut's verdict.")
    }

    func testArchiveRowsHaveNoVerdicts() {
        let hero = FollowedHero.compute([LogRow(choice: "Accepted", source: "archive"),
                                         LogRow(choice: "Accepted", source: "archive")])
        XCTAssertEqual(hero.ringText, "--")
        XCTAssertEqual(hero.loggedOffers, 0)
        XCTAssertEqual(hero.message, "Archive rows have no verdicts. Log offers with the shortcut to see this.")
    }

    func testSomeRows() {
        let hero = FollowedHero.compute([logged("TAKE IT", "Accepted"), logged("TAKE IT", "Declined"),
                                         logged("SKIP", "Declined"),
                                         LogRow(choice: "Accepted", source: "archive")])
        XCTAssertEqual(hero.followed, 2)
        XCTAssertEqual(hero.loggedOffers, 3)
        XCTAssertEqual(hero.percent, 67)
        XCTAssertEqual(hero.arcFraction, 0.67, accuracy: 1e-9)
        XCTAssertEqual(hero.message, "2 of 3 logged offers matched the verdict. Room to tighten up.")
    }

    func testAllFollowed() {
        let hero = FollowedHero.compute([logged("TAKE IT", "Accepted"), logged("SKIP", "Declined")])
        XCTAssertEqual(hero.ringText, "100%")
        XCTAssertEqual(hero.arcFraction, 1)
        XCTAssertEqual(hero.message, "2 of 2 logged offers matched the verdict. Locked in.")
    }

    /// 85% is the "Locked in." boundary; 84% is not.
    func testLockedInThreshold() {
        XCTAssertEqual(FollowedHero.compute(logged(17, of: 20)).percent, 85)
        XCTAssertEqual(FollowedHero.compute(logged(17, of: 20)).message,
                       "17 of 20 logged offers matched the verdict. Locked in.")
        XCTAssertEqual(FollowedHero.compute(logged(21, of: 25)).percent, 84)
        XCTAssertEqual(FollowedHero.compute(logged(21, of: 25)).message,
                       "21 of 25 logged offers matched the verdict. Room to tighten up.")
    }
}
