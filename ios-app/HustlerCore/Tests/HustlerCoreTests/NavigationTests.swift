import XCTest
@testable import HustlerCore

final class NavigationTests: XCTestCase {

    func testDefaultPinsGiveTheFiveWebTabsInOrder() {
        let expected: [AppScreen] = [.scoreboard, .check, .whatIf, .data, .settings]
        XCTAssertEqual(NavigationPlan.make(pins: PagePins()).screens, expected)
        XCTAssertEqual(expected.map(\.title), ["Scoreboard", "Check", "What-if", "Data", "Settings"])
    }

    func testDataPinOffRemovesTheDataTab() {
        let expected: [AppScreen] = [.scoreboard, .check, .whatIf, .settings]
        XCTAssertEqual(NavigationPlan.make(pins: PagePins(data: false)).screens, expected)
        XCTAssertTrue(AppPage.all.contains(.data), "Settings still lists Data when its pin is off")
    }

    func testPinnedPagesFollowSettingsAndKeepPGSOrder() {
        let allOn: [AppScreen] = [.scoreboard, .check, .whatIf, .data, .settings, .log, .earn, .hist, .sync]
        XCTAssertEqual(
            NavigationPlan.make(pins: PagePins(log: true, data: true, earn: true, hist: true, sync: true)).screens,
            allOn
        )

        let logOff: [AppScreen] = [.scoreboard, .check, .whatIf, .settings]
        XCTAssertEqual(NavigationPlan.make(pins: PagePins(log: false, data: false)).screens, logOff)
        XCTAssertTrue(AppPage.all.contains(.log), "a pin off hides the page but Settings still lists it")

        let mixed: [AppScreen] = [.scoreboard, .check, .whatIf, .data, .settings, .log, .hist]
        XCTAssertEqual(
            NavigationPlan.make(pins: PagePins(log: true, data: true, earn: false, hist: true, sync: false)).screens,
            mixed
        )
    }

    func testOnePinOnlyAddsItsOwnPage() {
        let plan = NavigationPlan.make(pins: PagePins(earn: true))
        let pinned: [AppScreen] = [.earn]
        XCTAssertEqual(plan.screens.filter { $0.page != nil && $0 != .data }, pinned)
    }

    func testScreensMatchTheWebPGSMetadata() {
        let pages: [AppScreen] = [.log, .data, .earn, .hist, .sync]
        XCTAssertEqual(AppPage.all.map(\.screen), pages)
        XCTAssertEqual(AppScreen.log.title, "Master file")
        XCTAssertEqual(AppScreen.log.subtitle, "View, edit and save the master log")
        XCTAssertEqual(AppScreen.earn.title, "Earnings")
        XCTAssertEqual(AppScreen.earn.subtitle, "Read your monthly statements")
        XCTAssertEqual(AppScreen.hist.title, "History")
        XCTAssertEqual(AppScreen.hist.subtitle, "Load your DoorDash data archive")
        XCTAssertEqual(AppScreen.sync.title, "Handoff")
        XCTAssertEqual(AppScreen.sync.subtitle, "Export or import for another AI")
        XCTAssertEqual(AppScreen.data.subtitle, "Drop offers, statements and archive files")
        XCTAssertNil(AppScreen.settings.subtitle)

        for screen in AppScreen.allCases {
            XCTAssertFalse(screen.title.isEmpty)
        }
    }

    func testTabsAreNeverEmpty() {
        let onlyHome: [AppScreen] = [.scoreboard]
        XCTAssertEqual(NavigationPlan(screens: []).screens, onlyHome)
        XCTAssertFalse(NavigationPlan.make(pins: PagePins(data: false)).screens.isEmpty)
    }
}
