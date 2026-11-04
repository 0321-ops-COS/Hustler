import XCTest
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
@testable import HustlerCore

/// Answers account requests from a script: no network, no real account, and no
/// real token. Nothing here prints a token.
final class StubAccountProtocol: URLProtocol {
    struct Reply {
        var status: Int
        var body: Data
        var error: Error?

        init(status: Int, body: Data = Data(), error: Error? = nil) {
            self.status = status
            self.body = body
            self.error = error
        }
    }

    static var replies: [Reply] = []
    static var requests: [URLRequest] = []

    static func reset() {
        replies = []
        requests = []
    }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        Self.requests.append(request)
        guard !Self.replies.isEmpty else {
            client?.urlProtocol(self, didFailWithError: URLError(.unknown))
            return
        }
        let reply = Self.replies.removeFirst()
        if let error = reply.error {
            client?.urlProtocol(self, didFailWithError: error)
            return
        }
        let response = HTTPURLResponse(url: request.url!, statusCode: reply.status,
                                       httpVersion: "HTTP/1.1",
                                       headerFields: ["Content-Type": "application/json"])!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: reply.body)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}

/// The Keychain, replaced by a box the test can look inside.
private final class TestStorage: SessionStorage {
    var session: SupabaseSession?
    var saveCount = 0
    var clearCount = 0

    func load() -> SupabaseSession? { session }
    @discardableResult func save(_ session: SupabaseSession) -> Bool {
        self.session = session
        saveCount += 1
        return true
    }
    func clear() {
        session = nil
        clearCount += 1
    }
}

/// Refresh and gate decisions: expired token, refresh success, server-rejected
/// refresh, network failure. Every case is decided without a real phone.
final class SessionRefreshTests: XCTestCase {
    private var storage: TestStorage!
    private var urlSession: URLSession!

    private let userID = "11111111-1111-1111-1111-111111111111"

    override func setUp() {
        super.setUp()
        StubAccountProtocol.reset()
        storage = TestStorage()
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [StubAccountProtocol.self]
        urlSession = URLSession(configuration: configuration)
    }

    override func tearDown() {
        StubAccountProtocol.reset()
        urlSession = nil
        storage = nil
        super.tearDown()
    }

    private func account() -> SupabaseAccount {
        SupabaseAccount(baseURL: URL(string: "https://example.supabase.co")!,
                        apiKey: "test-publishable-key",
                        urlSession: urlSession,
                        storage: storage)
    }

    private func authBody(access: String, refresh: String?, expiresIn: Double?) -> Data {
        var json = #"{"access_token":"\#(access)","user":{"id":"\#(userID)"}"#
        if let refresh { json += #","refresh_token":"\#(refresh)""# }
        if let expiresIn { json += #","expires_in":\#(expiresIn)"# }
        json += "}"
        return Data(json.utf8)
    }

    private func session(access: String = "old-access",
                         refresh: String? = "old-refresh",
                         expiresIn seconds: TimeInterval? = -60) -> SupabaseSession {
        SupabaseSession(accessToken: access, refreshToken: refresh, userID: userID,
                        expiresAt: seconds.map { Date(timeIntervalSinceNow: $0) })
    }

    // MARK: - Expired token

    func testExpiredTokenIsRefreshedAndReplacesTheStoredSession() async throws {
        storage.session = session()
        StubAccountProtocol.replies = [
            .init(status: 200, body: authBody(access: "new-access", refresh: "new-refresh", expiresIn: 3600))
        ]

        let outcome = await account().refreshSessionIfNeeded()

        XCTAssertEqual(outcome, .refreshed)
        XCTAssertEqual(storage.session?.accessToken, "new-access")
        XCTAssertEqual(storage.session?.refreshToken, "new-refresh")
        XCTAssertEqual(storage.saveCount, 1)
        let request = try XCTUnwrap(StubAccountProtocol.requests.first)
        XCTAssertEqual(request.httpMethod, "POST")
        XCTAssertEqual(request.url?.path, "/auth/v1/token")
        XCTAssertEqual(request.url?.query, "grant_type=refresh_token")
        XCTAssertEqual(SessionGate.after(outcome), .app)
    }

    /// The rejected earlier job: a token inside the leeway counts as expired.
    func testTokenAboutToExpireIsRefreshed() async {
        storage.session = session(expiresIn: 30)
        StubAccountProtocol.replies = [
            .init(status: 200, body: authBody(access: "new-access", refresh: "new-refresh", expiresIn: 3600))
        ]

        let outcome = await account().refreshSessionIfNeeded()

        XCTAssertEqual(outcome, .refreshed)
        XCTAssertEqual(storage.session?.accessToken, "new-access")
    }

    func testTokenThatIsStillGoodIsNotRefreshed() async {
        storage.session = session(expiresIn: 1800)

        let outcome = await account().refreshSessionIfNeeded()

        XCTAssertEqual(outcome, .current)
        XCTAssertTrue(StubAccountProtocol.requests.isEmpty)
        XCTAssertEqual(storage.saveCount, 0)
        XCTAssertEqual(SessionGate.after(outcome), .app)
    }

    /// A session an older build stored has no expiry at all: refresh it once.
    func testSessionStoredWithoutAnExpiryIsRefreshed() async {
        storage.session = session(expiresIn: nil)
        StubAccountProtocol.replies = [
            .init(status: 200, body: authBody(access: "new-access", refresh: "new-refresh", expiresIn: 3600))
        ]

        let outcome = await account().refreshSessionIfNeeded()

        XCTAssertEqual(outcome, .refreshed)
        XCTAssertEqual(storage.session?.accessToken, "new-access")
        XCTAssertNotNil(storage.session?.expiresAt)
    }

    // MARK: - Refresh success feeds the account call

    func testAccountCallRefreshesFirstAndSendsTheNewToken() async throws {
        storage.session = session()
        StubAccountProtocol.replies = [
            .init(status: 200, body: authBody(access: "new-access", refresh: "new-refresh", expiresIn: 3600)),
            .init(status: 200, body: Data("[]".utf8))
        ]

        let rows = try await account().fetchSummary()

        XCTAssertEqual(StubAccountProtocol.requests.count, 2)
        XCTAssertEqual(StubAccountProtocol.requests[1].url?.path, "/rest/v1/hh_store")
        XCTAssertEqual(StubAccountProtocol.requests[1].value(forHTTPHeaderField: "Authorization"),
                       "Bearer new-access")
        XCTAssertEqual(rows.map(\.key), SupabaseStoreSummary.keys)
        XCTAssertTrue(rows.allSatisfy { !$0.exists })
    }

    // MARK: - Server-rejected refresh

    func testRejectedRefreshClearsTheSessionAndShowsTheGate() async {
        for status in [400, 401, 403] {
            StubAccountProtocol.reset()
            storage = TestStorage()
            storage.session = session()
            StubAccountProtocol.replies = [.init(status: status, body: Data(#"{"error":"invalid_grant"}"#.utf8))]

            let outcome = await account().refreshSessionIfNeeded()

            XCTAssertEqual(outcome, .rejected, "status \(status)")
            XCTAssertNil(storage.session, "status \(status) must clear the session")
            XCTAssertEqual(SessionGate.after(outcome), .signIn, "status \(status) must show the gate")
        }
    }

    func testRejectedRefreshMakesTheAccountCallSignInAgain() async {
        storage.session = session()
        StubAccountProtocol.replies = [.init(status: 401, body: Data())]

        do {
            _ = try await account().fetchSummary()
            XCTFail("a rejected refresh must not reach the account call")
        } catch {
            XCTAssertEqual(error as? SupabaseAccountError, .notSignedIn)
        }
        XCTAssertNil(storage.session)
    }

    func testSessionWithoutARefreshTokenSignsInAgainInsteadOfOpeningTheApp() async {
        storage.session = session(refresh: nil)

        let outcome = await account().refreshSessionIfNeeded()

        XCTAssertEqual(outcome, .rejected)
        XCTAssertNil(storage.session)
        XCTAssertTrue(StubAccountProtocol.requests.isEmpty)
    }

    // MARK: - Network failure and server errors keep the session

    func testOfflineRefreshKeepsTheSessionAndOpensTheApp() async {
        storage.session = session()
        StubAccountProtocol.replies = [.init(status: 0, error: URLError(.notConnectedToInternet))]

        let outcome = await account().refreshSessionIfNeeded()

        XCTAssertEqual(outcome, .kept)
        XCTAssertEqual(storage.session?.accessToken, "old-access")
        XCTAssertEqual(storage.session?.refreshToken, "old-refresh")
        XCTAssertEqual(storage.clearCount, 0)
        XCTAssertEqual(SessionGate.after(outcome), .app)
    }

    func testServerErrorDuringRefreshKeepsTheSession() async {
        storage.session = session()
        StubAccountProtocol.replies = [.init(status: 503, body: Data("upstream".utf8))]

        let outcome = await account().refreshSessionIfNeeded()

        XCTAssertEqual(outcome, .kept)
        XCTAssertEqual(storage.session?.accessToken, "old-access")
        XCTAssertEqual(SessionGate.after(outcome), .app)
    }

    func testUnreadableRefreshBodyKeepsTheSession() async {
        storage.session = session()
        StubAccountProtocol.replies = [.init(status: 200, body: Data("not json".utf8))]

        let outcome = await account().refreshSessionIfNeeded()

        XCTAssertEqual(outcome, .kept)
        XCTAssertEqual(storage.session?.accessToken, "old-access")
    }

    /// An offline account call still says why, and still does not sign out.
    func testOfflineAccountCallKeepsTheSession() async {
        storage.session = session(expiresIn: 1800)
        StubAccountProtocol.replies = [.init(status: 0, error: URLError(.notConnectedToInternet))]

        do {
            _ = try await account().fetchSummary()
            XCTFail("the account call should fail without a network")
        } catch {
            XCTAssertEqual(error as? SupabaseAccountError, .noNetwork)
        }
        XCTAssertNotNil(storage.session)
    }

    // MARK: - Gate decisions

    func testGateFollowsTheKeychainNotTheNetwork() {
        XCTAssertEqual(SessionGate.atLaunch(session: nil), .signIn)
        // A stored session opens the app with no request and no network.
        XCTAssertEqual(SessionGate.atLaunch(session: session(expiresIn: -60)), .app)
        XCTAssertEqual(SessionGate.atLaunch(session: session(expiresIn: nil)), .app)
    }

    func testGateAfterEachRefreshOutcome() {
        XCTAssertEqual(SessionGate.after(.noSession), .signIn)
        XCTAssertEqual(SessionGate.after(.rejected), .signIn)
        XCTAssertEqual(SessionGate.after(.current), .app)
        XCTAssertEqual(SessionGate.after(.refreshed), .app)
        XCTAssertEqual(SessionGate.after(.kept), .app)
    }

    func testNoStoredSessionSendsNoRequest() async {
        let outcome = await account().refreshSessionIfNeeded()

        XCTAssertEqual(outcome, .noSession)
        XCTAssertTrue(StubAccountProtocol.requests.isEmpty)
        XCTAssertEqual(SessionGate.after(outcome), .signIn)
    }

    // MARK: - Session shape

    func testExpiryComesFromExpiresAtOrExpiresIn() throws {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let absolute = try SupabaseSession.from(
            data: Data(#"{"access_token":"a","refresh_token":"r","expires_at":1800003600,"user":{"id":"u"}}"#.utf8),
            now: now)
        XCTAssertEqual(absolute.expiresAt, Date(timeIntervalSince1970: 1_800_003_600))
        XCTAssertFalse(absolute.needsRefresh(now: now))

        let relative = try SupabaseSession.from(
            data: Data(#"{"access_token":"a","refresh_token":"r","expires_in":3600,"user":{"id":"u"}}"#.utf8),
            now: now)
        XCTAssertEqual(relative.expiresAt, now.addingTimeInterval(3600))
        XCTAssertFalse(relative.needsRefresh(now: now))

        let unknown = try SupabaseSession.from(
            data: Data(#"{"access_token":"a","user":{"id":"u"}}"#.utf8))
        XCTAssertNil(unknown.expiresAt)
        XCTAssertTrue(unknown.needsRefresh(now: now))
    }

    /// A Keychain entry written before `expiresAt` existed still decodes.
    func testOlderStoredSessionStillDecodes() throws {
        let stored = Data(#"{"accessToken":"a","refreshToken":"r","userID":"u"}"#.utf8)
        let decoded = try JSONDecoder().decode(SupabaseSession.self, from: stored)

        XCTAssertEqual(decoded.accessToken, "a")
        XCTAssertNil(decoded.expiresAt)
        XCTAssertEqual(try JSONDecoder().decode(SupabaseSession.self,
                                                from: JSONEncoder().encode(decoded)),
                       decoded)
    }

    func testSignOutClearsOnlyTheSession() {
        storage.session = session()
        let account = self.account()

        account.signOut()

        XCTAssertNil(storage.session)
        XCTAssertNil(account.storedSession)
    }
}
