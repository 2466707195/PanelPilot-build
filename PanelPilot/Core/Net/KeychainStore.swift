import Foundation
import Security

// === 令牌存储 ===
//
// 面板令牌（x-panel-token）等于那台 Windows 的管理权限：
// 拿到它就能改账号、导密钥、看日志。所以**不写 UserDefaults**，
// 一律进 Keychain（kSecAttrAccessibleAfterFirstUnlock，重装即失效）。
// 配置本身（地址、方式、备注）不敏感，留在 UserDefaults 里方便调试。

enum KeychainStore {

    private static let service = "com.agent2api.PanelPilot"

    static func set(_ value: String, for key: String) {
        guard !value.isEmpty else {
            delete(key)
            return
        }
        let data = Data(value.utf8)
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key
        ]
        let attributes: [String: Any] = [
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlock
        ]

        let status = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
        if status == errSecItemNotFound {
            var insert = query
            insert.merge(attributes) { current, _ in current }
            SecItemAdd(insert as CFDictionary, nil)
        }
    }

    static func get(_ key: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess,
              let data = item as? Data,
              let text = String(data: data, encoding: .utf8) else { return nil }
        return text
    }

    static func delete(_ key: String) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key
        ]
        SecItemDelete(query as CFDictionary)
    }

    static func panelTokenKey(for id: UUID) -> String { "\(id.uuidString).panel-token" }
    static func apiKeyKey(for id: UUID) -> String { "\(id.uuidString).api-key" }
    /// 管理员密码：只在「账号密码」模式下用，和令牌一样进钥匙串。
    static func panelPasswordKey(for id: UUID) -> String { "\(id.uuidString).panel-password" }
    /// 续期用的 refreshToken，换成新的 accessToken 后会一起更新。
    static func panelRefreshKey(for id: UUID) -> String { "\(id.uuidString).panel-refresh" }
}
