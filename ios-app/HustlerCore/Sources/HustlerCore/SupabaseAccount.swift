import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// The signed-in session. The password is never part of this type.
public struct SupabaseSession: Codable, Equatable, Sendable {
    public let accessToken: String, refreshToken: String?, userID: String

    /// `/auth/v1/token?grant_type=password`: `access_token`, `refresh_token`, `user.id`.
    public static func from(data: Data) throws -> SupabaseSession {
        struct Payload: Decodable {
            struct User: Decodable { let id: String }
            let access_token: String, refresh_token: String?, user: User
        }
        guard let p = try? JSONDecoder().decode(Payload.self, from: data) else {
            throw SupabaseAccountError.unexpectedResponse
        }
        return SupabaseSession(accessToken: p.access_token, refreshToken: p.refresh_token, userID: p.user.id)
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
/// response does not contain.
public enum SupabaseStoreSummary {
    public static let keys = ["settings", "log", "archive", "statements", "ca"]
    public static func parse(_ data: Data) throws -> [StoreKeySummary] {
        guard let rows = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] else {
            throw SupabaseAccountError.unexpectedResponse
        }
        var found: [String: StoreKeySummary] = [:]
        for row in rows {
            guard let key = row["k"] as? String else { throw SupabaseAccountError.unexpectedResponse }
            found[key] = StoreKeySummary(key: key, exists: true,
                                         updatedAt: row["updated_at"] as? String,
                                         itemCount: itemCount(row["v"]))
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
    public var storedSession: SupabaseSession? { storage?.load() ?? memory }

    /// Returns the new session (access token, optional refresh token, user ID) and stores it for later requests.
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
    /// Clears the persisted session from the keychain (or the in-memory fallback) so the next call sees no signed-in user.
    public func signOut() { storage?.clear(); memory = nil }

    public func fetchSummary() async throws -> [StoreKeySummary] {
        guard let session = storedSession else { throw SupabaseAccountError.notSignedIn }
        var request = makeRequest(path: "rest/v1/hh_store",
                                  query: [URLQueryItem(name: "select", value: "k,updated_at,v")])
        request.setValue("Bearer \(session.accessToken)", forHTTPHeaderField: "Authorization")
        let (data, status) = try await send(request)
        if status == 401 { throw SupabaseAccountError.notSignedIn }
        guard (200..<300).contains(status) else { throw SupabaseAccountError.unexpectedResponse }
        return try SupabaseStoreSummary.parse(data)
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
