import Foundation

// === 账号页的数据模型 ===
//
// 面板的 `/api/accounts` 回的是平铺的账号数组，每个账号自带 `provider`。
// 移动端要的是「已添加的提供商 → 已添加的账号」两层，所以这里做一次本地分组：
// 提供商不写死、账号数量也不设上限，完全跟着服务器返回走。

// MARK: - 账号

struct AccountItem: Identifiable, Equatable {

    var id: String
    var name: String
    var provider: String
    var providerLabel: String
    var enabled: Bool
    var isCurrent: Bool
    var status: String?
    var proxy: String?
    var balance: String?
    var expiresAt: String?
    var modelCount: Int
    var raw: JSONValue

    var statusText: String {
        if let status, !status.isEmpty { return status }
        return enabled ? "已启用" : "已停用"
    }

    var healthy: Bool {
        if !enabled { return false }
        let lower = (status ?? "").lowercased()
        return !["error", "fail", "invalid", "expired", "limit", "禁用", "限流"].contains { lower.contains($0) }
    }

    /// 详情页要展示的「状态 / 代理 / 余额 / 有效期」四行。
    var detailRows: [(String, String)] {
        var rows: [(String, String)] = []
        rows.append(("状态", statusText))
        if let proxy, !proxy.isEmpty { rows.append(("代理方式", proxy)) }
        if let balance, !balance.isEmpty { rows.append(("余额", balance)) }
        if let expiresAt, !expiresAt.isEmpty { rows.append(("有效期", expiresAt)) }
        if modelCount > 0 { rows.append(("可用模型", "\(modelCount) 个")) }
        if isCurrent { rows.append(("当前账号", "是")) }
        return rows
    }
}

// MARK: - 提供商分组

struct AccountProvider: Identifiable, Equatable {
    var id: String
    var label: String
    var accounts: [AccountItem]

    var enabledCount: Int { accounts.filter(\.enabled).count }
    var hasCurrent: Bool { accounts.contains(where: \.isCurrent) }

    var summary: String {
        "\(accounts.count) 个账号 · \(enabledCount) 启用"
    }
}

// MARK: - 解析

enum AccountsParser {

    /// 从 `/api/accounts` 的任意包装里取出账号数组。
    static func rows(_ json: JSONValue) -> [JSONValue] {
        JSONRows.from(json)
    }

    static func items(_ json: JSONValue) -> [AccountItem] {
        rows(json).compactMap { item in
            guard item.objectValue != nil else { return nil }
            let id = item.firstString(["id", "accountId", "uid", "key"]) ?? UUID().uuidString
            let provider = item.firstString(["provider", "providerId", "platform", "platformId", "vendor"]) ?? "other"
            let name = item.firstString(["name", "label", "nickname", "email", "displayName", "phone", "id"]) ?? id

            let status = item.firstString(["status", "state", "health"])
            var enabled = item.bool("enabled")
                ?? item.bool("active")
                ?? item.bool("isEnabled")
            if enabled == nil {
                let lower = (status ?? "").lowercased()
                enabled = !["disabled", "off", "invalid", "expired", "禁用"].contains { lower.contains($0) }
            }

            let isCurrent = item.bool("current") ?? item.bool("isCurrent") ?? item.bool("active") ?? false

            let proxy = item.firstString(["proxy", "proxyLabel", "proxyName", "proxyUrl", "egressProxy"])
            let balance = balanceText(item)
            let expires = item.firstString(["expiresAt", "expireAt", "expiredAt", "validUntil", "expiry"])

            return AccountItem(
                id: id,
                name: name,
                provider: provider,
                providerLabel: item.firstString(["providerLabel", "providerName"]) ?? provider,
                enabled: enabled ?? true,
                isCurrent: isCurrent,
                status: status,
                proxy: proxy,
                balance: balance,
                expiresAt: expires.map { shortDate($0) },
                modelCount: (item.arr("models") ?? item.arr("modelList"))?.count ?? 0,
                raw: item
            )
        }
    }

    /// 余额：优先 `balance`，其次 `credits/quota/remain`，数字按两位小数。
    private static func balanceText(_ item: JSONValue) -> String? {
        for key in ["balance", "credits", "quota", "remaining", "remain", "amount"] {
            guard let value = item.value(key) else { continue }
            if let number = value.doubleValue {
                return String(format: "%.2f", number)
            }
            if let text = value.stringValue, !text.isEmpty { return text }
        }
        if let usage = item.obj("usage") {
            for key in ["balance", "credits", "remaining"] {
                if let number = usage.value(key)?.doubleValue { return String(format: "%.2f", number) }
                if let text = usage.str(key), !text.isEmpty { return text }
            }
        }
        return nil
    }

    /// 时间戳 / ISO 串 → `MM-dd HH:mm`
    private static func shortDate(_ raw: String) -> String {
        if let stamp = Double(raw) {
            let seconds = stamp > 1e12 ? stamp / 1000 : stamp
            if seconds > 1_000_000_000 {
                return Date(timeIntervalSince1970: seconds).formatted("MM-dd HH:mm")
            }
        }
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = formatter.date(from: raw) { return date.formatted("MM-dd HH:mm") }
        formatter.formatOptions = [.withInternetDateTime]
        if let date = formatter.date(from: raw) { return date.formatted("MM-dd HH:mm") }
        return raw.count > 16 ? String(raw.prefix(16)) : raw
    }

    /// 按提供商分组，保持服务器返回的先后顺序。
    static func group(_ items: [AccountItem]) -> [AccountProvider] {
        var order: [String] = []
        var bucket: [String: [AccountItem]] = [:]
        for item in items {
            if bucket[item.provider] == nil { order.append(item.provider) }
            bucket[item.provider, default: []].append(item)
        }
        return order.map { key in
            let accounts = bucket[key] ?? []
            return AccountProvider(
                id: key,
                label: accounts.first?.providerLabel ?? key,
                accounts: accounts
            )
        }
    }
}


// MARK: - 网关 Key（助手聊天要用它）

/// `GET /api/model-access/keys` 的一条。
struct GatewayKey: Identifiable, Equatable {
    var id: String
    var name: String
    /// 真的密钥值（面板对已登录管理员返回原文），聊天时放进 `x-api-key`
    var value: String
    var enabled: Bool
    var expiresAt: String?
    var note: String?
}

enum GatewayKeysParser {

    static func items(_ json: JSONValue) -> [GatewayKey] {
        let rows = JSONRows.from(json)
        return rows.compactMap { item in
            guard item.objectValue != nil else { return nil }
            let id = item.firstString(["id", "keyId", "name"]) ?? UUID().uuidString
            let value = item.firstString(["key", "value", "token", "apiKey"]) ?? ""
            guard !value.isEmpty else { return nil }
            let name = item.firstString(["name", "label", "remark", "id"]) ?? "Key"
            let enabled = item.bool("enabled") ?? item.bool("active") ?? true
            let expires = item.firstString(["expiresAt", "expiredAt", "validUntil"])
            return GatewayKey(
                id: id,
                name: name,
                value: value,
                enabled: enabled,
                expiresAt: expires,
                note: item.firstString(["note", "description"])
            )
        }
    }
}

// MARK: - 登录方式

/// `GET /api/session/login/methods?provider=` 的一条。
struct LoginMethod: Identifiable, Equatable {
    var index: Int
    var kind: String        // oauth / password / sms / token / qr …
    var label: String
    var hint: String?

    var id: Int { index }

    var icon: String {
        switch kind.lowercased() {
        case "oauth", "browser", "web": return "globe"
        case "sms", "phone": return "iphone.gen3"
        case "password": return "key"
        case "qr", "qrcode": return "qrcode"
        case "token", "apikey", "api_key": return "curlybraces"
        default: return "arrow.right.circle"
        }
    }
}

enum LoginMethodsParser {

    static func items(_ json: JSONValue) -> [LoginMethod] {
        var node = json
        if let data = json.obj("data") { node = data }
        let raw = node.arr("methods") ?? node.arrayValue ?? []
        return raw.enumerated().compactMap { offset, item in
            guard item.objectValue != nil else { return nil }
            let index = item.int("methodIndex") ?? item.int("index") ?? offset
            let kind = item.firstString(["kind", "type", "method"]) ?? "oauth"
            let label = item.firstString(["label", "name", "title"]) ?? kind
            return LoginMethod(
                index: index,
                kind: kind,
                label: label,
                hint: item.firstString(["hint", "description", "note"])
            )
        }
    }
}
