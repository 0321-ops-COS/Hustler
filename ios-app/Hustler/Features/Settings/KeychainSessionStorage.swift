import Foundation
import Security
import HustlerCore

/// Keychain-only session storage. The password never reaches this type.
final class KeychainSessionStorage: SessionStorage {
    private let service = "com.hustler.hq.supabase", account = "session"
    private var base: [String: Any] {
        [kSecClass as String: kSecClassGenericPassword,
         kSecAttrService as String: service,
         kSecAttrAccount as String: account]
    }
    func load() -> SupabaseSession? {
        var query = base
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess,
              let data = item as? Data else { return nil }
        return try? JSONDecoder().decode(SupabaseSession.self, from: data)
    }
    @discardableResult
    func save(_ session: SupabaseSession) -> Bool {
        guard let data = try? JSONEncoder().encode(session) else { return false }
        clear()
        var query = base
        query[kSecValueData as String] = data
        query[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        return SecItemAdd(query as CFDictionary, nil) == errSecSuccess
    }
    func clear() { SecItemDelete(base as CFDictionary) }
}
