import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// The signed-in session. The password is never part of this type.
public struct SupabaseSession: Codable, Equatable, Sendable {
    public let accessToken: String, refreshToken: String?, userID: String
    /// When the access token stops working. `nil` for a session an older build
    /// stored without one; that session is refreshed on first use.
    public let expiresAt: Date?

    /// A token this close to expiring is treated as expired, so an account
    /// call does not race the clock.
    public static let refreshLeeway: TimeInterval = 60

    public init(accessToken: String, refreshToken: String?, userID: String, expiresAt: Date? = nil) {
        self.accessToken = accessToken
        self.refreshToken = refreshToken
        self.userID = userID
        self.expiresAt = expiresAt
    }

    private enum CodingKeys: String, CodingKey { case accessToken, refreshToken, userID, expiresAt }

    /// A Keychain entry written before `expiresAt` existed still loads.
    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        accessToken = try values.decode(String.self, forKey: .accessToken)
        refreshToken = try values.decodeIfPresent(String.self, forKey: .refreshToken)
        userID = try values.decode(String.self, forKey: .userID)
        expiresAt = try values.decodeIfPresent(Date.self, forKey: .expiresAt)
    }

    /// `/auth/v1/token?grant_type=password` or `grant_type=refresh_token`:
    /// `access_token`, `refresh_token`, `user.id`, and `expires_at`/`expires_in`.
    public static func from(data: Data, now: Date = Date()) throws -> SupabaseSession {
        struct Payload: Decodable {
            struct User: Decodable { let id: String }
            let access_token: String, refresh_token: String?, user: User
            let expires_at: Double?, expires_in: Double?
        }
        guard let p = try? JSONDecoder().decode(Payload.self, from: data) else {
            throw SupabaseAccountError.unexpectedResponse
        }
        let expiresAt: Date?
        if let seconds = p.expires_at {
            expiresAt = Date(timeIntervalSince1970: seconds)
        } else if let seconds = p.expires_in {
            expiresAt = now.addingTimeInterval(seconds)
        } else {
            expiresAt = nil
        }
        return SupabaseSession(accessToken: p.access_token, refreshToken: p.refresh_token,
                               userID: p.user.id, expiresAt: expiresAt)
    }

    /// True when the access token is expired, about to expire, or of unknown age.
    public func needsRefresh(now: Date, leeway: TimeInterval = SupabaseSession.refreshLeeway) -> Bool {
        guard let expiresAt else { return true }
        return expiresAt.timeIntervalSince(now) <= leeway
    }
}

/// Keychain in the app; in-memory when the account is given no storage.
public protocol SessionStorage: AnyObject {
    func load() -> SupabaseSession?
    @discardableResult func save(_ session: SupabaseSession) -> Bool
    func clear()
}

public enum SupabaseAccountError: LocalizedError, Equatable {
    case wrongPassword, noNetwork, unexpectedResponse, notSignedIn, keychain
    public var errorDescription: String? {
        switch self {
        case .wrongPassword: return "Wrong email or password."
        case .noNetwork: return "No network connection. Check your connection and try again."
        case .unexpectedResponse: return "The account service returned something this app does not understand."
        case .notSignedIn: return "Sign in to see what is stored in your account."
        case .keychain: return "Could not keep the sign-in on this device."
        }
    }
}

/// What a refresh attempt did to the stored session.
public enum SessionRefreshOutcome: Equatable, Sendable {
    /// Nothing is stored: the gate shows.
    case noSession
    /// The access token is still good; no request was sent.
    case current
    /// The server issued a new session and it replaced the stored one.
    case refreshed
    /// The server refused the refresh token: the session was cleared and the
    /// gate shows.
    case rejected
    /// No usable answer (offline, timeout, server error): the session is kept,
    /// so a stored sign-in still opens the app without a network.
    case kept
}

/// The launch gate: the sign-in screen, or the app.
public enum SessionGate: Equatable, Sendable {
    case signIn, app

    /// Keychain only, never the network: a stored session opens the app straight
    /// away, so local data is never blocked by a refresh.
    public static func atLaunch(session: SupabaseSession?) -> SessionGate {
        session == nil ? .signIn : .app
    }

    /// After a refresh: only an explicit rejection, or an empty Keychain, sends
    /// the phone back to the gate. A phone that is offline stays signed in.
    public static func after(_ outcome: SessionRefreshOutcome) -> SessionGate {
        switch outcome {
        case .noSession, .rejected: return .signIn
        case .current, .refreshed, .kept: return .app
        }
    }
}

/// One `hh_store` key: present or missing, last change, item count (array length
/// or top-level key count of `v`).
public struct StoreKeySummary: Equatable, Sendable, Identifiable {
    public let key: String, exists: Bool, updatedAt: String?, itemCount: Int
    public var id: String { key }
    public var line: String {
        guard exists else { return "missing" }
        let updated = updatedAt.map { "updated \($0)" } ?? "no timestamp"
        return "\(updated) · \(itemCount) item\(itemCount == 1 ? "" : "s")"
    }
}

/// Parses `GET /rest/v1/hh_store?select=k,updated_at,v`, including keys the
/// response does not contain. The rows come from `SupabaseStoreRows`, so the
/// response is read once for both the summary and the pull.
public enum SupabaseStoreSummary {
    public static let keys = ["settings", "log", "archive", "statements", "ca"]
    public static func parse(_ data: Data) throws -> [StoreKeySummary] {
        summarize(try SupabaseStoreRows.parse(data))
    }
    public static func summarize(_ rows: [AccountStoreRow]) -> [StoreKeySummary] {
        var found: [String: StoreKeySummary] = [:]
        for row in rows {
            let value = try? JSONSerialization.jsonObject(with: row.value, options: [.fragmentsAllowed])
            found[row.key] = StoreKeySummary(key: row.key, exists: true,
                                             updatedAt: row.updatedAt,
                                             itemCount: itemCount(value))
        }
        return keys.map { found[$0] ?? StoreKeySummary(key: $0, exists: false, updatedAt: nil, itemCount: 0) }
    }
    static func itemCount(_ value: Any?) -> Int {
        if let array = value as? [Any] { return array.count }
        if let object = value as? [String: Any] { return object.count }
        return 0
    }
}

/// The web app's account, read-only: sign in and list `hh_store`.
public final class SupabaseAccount {
    public static let baseURL = URL(string: "https://xpcglmabtsceyzfrdiky.supabase.co")!
    public static let apiKey = "sb_publishable_-_9Q2cS-64BaU5-uQJDVlQ_c1k_IpeO"
    private let baseURL: URL, apiKey: String, urlSession: URLSession
    private let storage: SessionStorage?
    private var memory: SupabaseSession?

    public init(baseURL: URL = SupabaseAccount.baseURL, apiKey: String = SupabaseAccount.apiKey,
                urlSession: URLSession = .shared, storage: SessionStorage? = nil) {
        self.baseURL = baseURL; self.apiKey = apiKey
        self.urlSession = urlSession; self.storage = storage
    }
    /// The session this device holds. `memory` only holds a session the Keychain
    /// could not, so the newest token wins.
    public var storedSession: SupabaseSession? { memory ?? storage?.load() }

    /// One refresh at a time: Supabase rotates the refresh token, so a second
    /// request carrying the old one would be rejected and sign the phone out.
    private var refreshTask: Task<SessionRefreshOutcome, Never>?

    @discardableResult
    public func signIn(email: String, password: String) async throws -> SupabaseSession {
        var request = makeRequest(path: "auth/v1/token",
                                  query: [URLQueryItem(name: "grant_type", value: "password")])
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(Credentials(email: email, password: password))
        let (data, status) = try await send(request)
        if status == 400 || status == 401 { throw SupabaseAccountError.wrongPassword }
        guard (200..<300).contains(status) else { throw SupabaseAccountError.unexpectedResponse }
        let session = try SupabaseSession.from(data: data)
        if let storage {
            guard storage.save(session) else { throw SupabaseAccountError.keychain }
        } else {
            memory = session
        }
        return session
    }
    /// Clears the sign-in on this device only. Nothing the app stored (log,
    /// archive, settings) is touched.
    public func signOut() { storage?.clear(); memory = nil }

    /// Replaces the stored session when the access token is expired or about to
    /// expire, and sends nothing while it is still good.
    ///
    /// A server rejection means the refresh token is no longer usable, so the
    /// session is cleared and the gate shows. A network failure or a server
    /// error keeps the session: a stored sign-in opens the app offline.
    @discardableResult
    public func refreshSessionIfNeeded(now: Date = Date()) async -> SessionRefreshOutcome {
        guard let session = storedSession else { return .noSession }
        guard session.needsRefresh(now: now) else { return .current }
        if let inFlight = refreshTask { return await inFlight.value }
        let task = Task { await self.performRefresh(session) }
        refreshTask = task
        let outcome = await task.value
        refreshTask = nil
        return outcome
    }

    private func performRefresh(_ session: SupabaseSession) async -> SessionRefreshOutcome {
        guard let refreshToken = session.refreshToken else {
            // Nothing to send and nothing to keep: the phone must sign in again.
            clearSession()
            return .rejected
        }
        var request = makeRequest(path: "auth/v1/token",
                                  query: [URLQueryItem(name: "grant_type", value: "refresh_token")])
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try? JSONEncoder().encode(RefreshToken(refresh_token: refreshToken))
        do {
            let (data, status) = try await send(request)
            if Self.isRejection(status) {
                clearSession()
                return .rejected
            }
            guard (200..<300).contains(status),
                  let refreshed = try? SupabaseSession.from(data: data) else {
                // 5xx, 429 or a body this app does not understand: not the
                // phone's fault, so the session stays.
                return .kept
            }
            adopt(refreshed)
            return .refreshed
        } catch {
            // Offline, timed out, no route: keep the session and open the app.
            return .kept
        }
    }

    /// Only these mean "this device may not use this account any more".
    private static func isRejection(_ status: Int) -> Bool {
        status == 400 || status == 401 || status == 403
    }

    private func adopt(_ session: SupabaseSession) {
        if let storage, storage.save(session) { return }
        memory = session
    }
    private func clearSession() { storage?.clear(); memory = nil }

    private struct RefreshToken: Encodable { let refresh_token: String }

    /// Every account call refreshes first; a rejected refresh throws
    /// `.notSignedIn` so the caller returns to the gate.
    public func fetchSummary() async throws -> [StoreKeySummary] {
        SupabaseStoreSummary.summarize(try await fetchRows())
    }

    /// The account's rows, values included, for the pull preview and import.
    /// Same refresh rule as every account call, and read-only: the phone never
    /// writes to Supabase.
    public func fetchRows() async throws -> [AccountStoreRow] {
        let gate = SessionGate.after(await refreshSessionIfNeeded())
        guard gate == .app, let session = storedSession else { throw SupabaseAccountError.notSignedIn }
        var request = makeRequest(path: "rest/v1/hh_store",
                                  query: [URLQueryItem(name: "select", value: "k,updated_at,v")])
        request.setValue("Bearer \(session.accessToken)", forHTTPHeaderField: "Authorization")
        let (data, status) = try await send(request)
        if status == 401 { throw SupabaseAccountError.notSignedIn }
        guard (200..<300).contains(status) else { throw SupabaseAccountError.unexpectedResponse }
        return try SupabaseStoreRows.parse(data)
    }
    private func makeRequest(path: String, query: [URLQueryItem]) -> URLRequest {
        var components = URLComponents(url: baseURL.appendingPathComponent(path),
                                       resolvingAgainstBaseURL: false)!
        components.queryItems = query
        var request = URLRequest(url: components.url!)
        request.setValue(apiKey, forHTTPHeaderField: "apikey")
        return request
    }
    /// No request, token or password is ever logged.
    private func send(_ request: URLRequest) async throws -> (Data, Int) {
        do {
            let (data, response) = try await urlSession.data(for: request)
            return (data, (response as? HTTPURLResponse)?.statusCode ?? 0)
        } catch { throw SupabaseAccountError.noNetwork }
    }
    private struct Credentials: Encodable { let email: String, password: String }
}
