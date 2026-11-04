import XCTest
@testable import HustlerCore

/// Fixture JSON only. Nothing here touches the network or a real account.
final class SupabaseAccountTests: XCTestCase {
    private let authFixture = #"""
    {"access_token":"fixture-access","refresh_token":"fixture-refresh",
     "user":{"id":"00000000-0000-0000-0000-000000000000"}}
    """#

    func testAuthResponseKeepsTokensAndUserID() throws {
        let session = try SupabaseSession.from(data: Data(authFixture.utf8))
        XCTAssertEqual(session.accessToken, "fixture-access")
        XCTAssertEqual(session.refreshToken, "fixture-refresh")
        XCTAssertEqual(session.userID, "00000000-0000-0000-0000-000000000000")
    }
    func testAuthResponseRejectsUnexpectedShape() {
        for fixture in [#"{"access_token":"only"}"#, "not json", "[]"] {
            XCTAssertThrowsError(try SupabaseSession.from(data: Data(fixture.utf8))) { error in
                XCTAssertEqual(error as? SupabaseAccountError, .unexpectedResponse)
            }
        }
    }
    func testSummaryCoversEveryKeyAndCountsItems() throws {
        let fixture = #"""
        [{"k":"settings","updated_at":"2026-11-02T10:00:00Z",
          "v":{"accept":89,"gas":5.75,"version":1}},
         {"k":"archive","updated_at":"2026-11-01T09:30:00Z","v":{"v":1,"r":[[1,2],[3,4]]}},
         {"k":"statements","updated_at":null,"v":{"v":1}},
         {"k":"ca","updated_at":"2026-11-02T11:00:00Z","v":{"v":1,"w":{}}}]
        """#
        let rows = try SupabaseStoreSummary.parse(Data(fixture.utf8))
        XCTAssertEqual(rows.map(\.key), ["settings", "log", "archive", "statements", "ca"])
        XCTAssertEqual(rows.map(\.exists), [true, false, true, true, true])
        XCTAssertEqual(rows[0].updatedAt, "2026-11-02T10:00:00Z")
        XCTAssertEqual(rows.map(\.itemCount), [3, 0, 2, 1, 2])
        XCTAssertNil(rows[3].updatedAt)
        XCTAssertEqual(rows[1].line, "missing")
        XCTAssertEqual(rows[0].line, "updated 2026-11-02T10:00:00Z · 3 items")
        XCTAssertEqual(SupabaseStoreSummary.itemCount([1, 2, 3]), 3)
        XCTAssertEqual(SupabaseStoreSummary.itemCount(["a": 1, "b": 2]), 2)
    }
    func testSummaryRejectsUnexpectedShape() {
        for fixture in [#"{"k":"settings"}"#, #"[{"v":{}}]"#, "not json"] {
            XCTAssertThrowsError(try SupabaseStoreSummary.parse(Data(fixture.utf8))) { error in
                XCTAssertEqual(error as? SupabaseAccountError, .unexpectedResponse)
            }
        }
    }
    func testErrorTextIsPlainAndNamesTheCause() {
        XCTAssertEqual(SupabaseAccountError.wrongPassword.errorDescription, "Wrong email or password.")
        XCTAssertEqual(SupabaseAccountError.noNetwork.errorDescription,
                       "No network connection. Check your connection and try again.")
        XCTAssertEqual(SupabaseAccountError.unexpectedResponse.errorDescription,
                       "The account service returned something this app does not understand.")
    }
}
