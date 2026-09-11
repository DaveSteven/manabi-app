import Foundation
import Security

enum TokenVault {
    static func read(server: String) -> String? {
        var query = base(server)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    static func save(_ token: String, server: String) throws {
        let query = base(server)
        let attributes: [String: Any] = [kSecValueData as String: Data(token.utf8)]
        let status = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
        if status == errSecItemNotFound {
            var item = query
            item[kSecValueData as String] = Data(token.utf8)
            item[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
            let added = SecItemAdd(item as CFDictionary, nil)
            guard added == errSecSuccess else { throw VaultError(status: added) }
        } else if status != errSecSuccess {
            throw VaultError(status: status)
        }
    }

    static func remove(server: String) { SecItemDelete(base(server) as CFDictionary) }

    private static func base(_ server: String) -> [String: Any] {
        [kSecClass as String: kSecClassGenericPassword,
         kSecAttrService as String: "app.manabi.session",
         kSecAttrAccount as String: server]
    }

    struct VaultError: LocalizedError {
        let status: OSStatus
        var errorDescription: String? { "无法安全保存登录信息，请重试。" }
    }
}
