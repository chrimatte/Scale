import Foundation
import Security

enum KeychainStore {
    private static var query: [String: Any] {
        [kSecClass as String: kSecClassGenericPassword,
         kSecAttrService as String: "local.chrimatte.scale.iphone",
         kSecAttrAccount as String: "intervals-api-key"]
    }
    static func read() throws -> String {
        var q = query
        q[kSecReturnData as String] = true
        q[kSecMatchLimit as String] = kSecMatchLimitOne
        var item: CFTypeRef?
        let status = SecItemCopyMatching(q as CFDictionary, &item)
        if status == errSecItemNotFound { return "" }
        guard status == errSecSuccess, let data = item as? Data, let key = String(data: data, encoding: .utf8) else {
            throw ScaleFailure(message: "Could not access the API key. Unlock your iPhone and try again.")
        }
        return key
    }
    static func save(_ key: String) throws {
        let attrs: [String: Any] = [kSecValueData as String: Data(key.utf8),
                                   kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly]
        var status = SecItemUpdate(query as CFDictionary, attrs as CFDictionary)
        if status == errSecItemNotFound {
            status = SecItemAdd(query.merging(attrs) { _, new in new } as CFDictionary, nil)
        }
        guard status == errSecSuccess else { throw ScaleFailure(message: "Could not save the API key securely.") }
    }
}
