import XCTest
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
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
    /// The Settings screen's order, verbatim: `signIn` returns, then
    /// `fetchSummary` runs in the same task with no extra step in between.
    func testSummaryFetchRunsImmediatelyAfterSignIn() async throws {
        StubURLProtocol.reset()
        let session = URLSession(configuration: StubURLProtocol.configuration())
        let account = SupabaseAccount(baseURL: URL(string: "https://stub.test")!,
                                      apiKey: "stub-key", urlSession: session)

        do {
            _ = try await account.fetchSummary()
            XCTFail("The initial fetch must not run before sign-in")
        } catch {
            XCTAssertEqual(error as? SupabaseAccountError, .notSignedIn)
        }
        XCTAssertTrue(StubURLProtocol.requests.isEmpty)

        try await account.signIn(email: "driver@example.test", password: "fixture")
        let summary = try await account.fetchSummary()

        XCTAssertEqual(summary.map(\.key), SupabaseStoreSummary.keys)
        XCTAssertEqual(summary.first?.exists, true)
        XCTAssertEqual(StubURLProtocol.requests.count, 2)
        XCTAssertEqual(StubURLProtocol.requests.first?.url?.path, "/auth/v1/token")
        XCTAssertEqual(StubURLProtocol.requests.last?.url?.path, "/rest/v1/hh_store")
        XCTAssertEqual(StubURLProtocol.requests.last?.httpMethod, "GET")
        XCTAssertEqual(StubURLProtocol.requests.last?.value(forHTTPHeaderField: "Authorization"),
                       "Bearer fresh-access")
    }

    func testErrorTextIsPlainAndNamesTheCause() {
        XCTAssertEqual(SupabaseAccountError.wrongPassword.errorDescription, "Wrong email or password.")
        XCTAssertEqual(SupabaseAccountError.noNetwork.errorDescription,
                       "No network connection. Check your connection and try again.")
        XCTAssertEqual(SupabaseAccountError.unexpectedResponse.errorDescription,
                       "The account service returned something this app does not understand.")
    }
}

/// Records request order and answers the two endpoints with fixture JSON, so a
/// test can prove what the account asks for and in which order. No network.
private final class StubURLProtocol: URLProtocol {
    private static let lock = NSLock()
    private static var recorded: [URLRequest] = []

    static var requests: [URLRequest] {
        lock.lock(); defer { lock.unlock() }
        return recorded
    }

    static func reset() {
        lock.lock(); recorded = []; lock.unlock()
    }

    static func configuration() -> URLSessionConfiguration {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [StubURLProtocol.self]
        return configuration
    }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        Self.lock.lock(); Self.recorded.append(request); Self.lock.unlock()

        let status: Int
        let body: String
        switch request.url?.path {
        case "/auth/v1/token":
            status = 200
            body = #"{"access_token":"fresh-access","refresh_token":"fresh-refresh","expires_in":3600,"user":{"id":"user-1"}}"#
        case "/rest/v1/hh_store":
            status = 200
            body = #"[{"k":"settings","updated_at":"2026-11-02T10:00:00Z","v":{"accept":89}}]"#
        default:
            status = 404
            body = ""
        }

        let response = HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil,
                                       headerFields: ["Content-Type": "application/json"])!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data(body.utf8))
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}
