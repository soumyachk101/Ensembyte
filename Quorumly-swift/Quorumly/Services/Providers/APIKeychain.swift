import Foundation
import Security

/// One Keychain implementation for every native provider's API key. The accounts
/// live in one Keychain service (`AppInfo.name`), one item per provider.
enum APIKeychain {
    /// The stored key for an account, or `fallback` when nothing is stored.
    /// A capture run reads nothing, so recorded sessions keep working without
    /// touching the user's real credentials.
    static func key(for account: String, fallback: String) -> String {
        guard !CaptureRun.isEnabled else { return "" }
        if let keychain = read(account), !keychain.isEmpty { return keychain }
        return fallback
    }

    /// Stores the key, or removes it for an empty one.
    @discardableResult
    static func setKey(_ key: String, account: String) -> Bool {
        set(key, account: account)
    }

    /// Stores the value, or removes it for an empty one.
    @discardableResult
    static func set(_ key: String, account: String, service: String = AppInfo.name) -> Bool {
        let trimmed = key.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            delete(account, service: service)
            return true
        }
        let data = Data(trimmed.utf8)
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        let updated = SecItemUpdate(query as CFDictionary, [kSecValueData as String: data] as CFDictionary)
        if updated == errSecSuccess { return true }
        guard updated == errSecItemNotFound else { return false }
        let attributes = query.merging([
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlocked,
        ]) { _, new in new }
        return SecItemAdd(attributes as CFDictionary, nil) == errSecSuccess
    }

    static func read(_ account: String, service: String = AppInfo.name) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess,
              let data = item as? Data,
              let key = String(data: data, encoding: .utf8),
              !key.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
        return key.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static func delete(_ account: String, service: String = AppInfo.name) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        SecItemDelete(query as CFDictionary)
    }
}
