import SwiftUI

// === 账号余额（可视化）===
//
// 面板把「余额/额度」放在两处：
//   · `GET /api/accounts/usage/snapshot`  全量快照（含最近一次查询结果与时间）
//   · `GET /api/accounts/usage?id=`       单账号实时查询（会打上游）
// 快照结构在面板前端里演化过好几版（`usage.totalLeft` / `available` / `remaining` /
// `items[]` / `quotaSources[]` 都出现过），所以这里**不写死路径**：
// 递归找出所有「有 id 且带 usage/balance/at」的对象，再按可用字段拼出人话。
//
// 一条余额长这样：
//   primary   「1200 积分」/「¥12.50」/「不限」
//   secondary 「剩 1200 / 5000 积分」或「已用 80%」
//   metrics   额外指标（可用余额、今日已用…），最多 4 条

struct BalanceMetric: Identifiable, Equatable {
    var id: String
    var label: String
    var value: String
}

struct AccountBalance: Identifiable, Equatable {

    var id: String
    /// 主数值，直接可读
    var primary: String = "未查询"
    /// 补充说明（剩余/总量、百分比、冻结…）
    var secondary: String?
    var metrics: [BalanceMetric] = []
    var at: Date?
    var error: String?
    /// 面板给的原因码，例如 `usage_not_configured` / `refresh_token_expired`
    var code: String?

    var hasError: Bool { !(error ?? "").isEmpty }

    /// 网关明确说「这家没有余额查询」，不是失败，别当错误红字显示
    var notConfigured: Bool { code == "usage_not_configured" }

    var atText: String {
        guard let at else { return "还没有查询过" }
        return at.formatted("MM-dd HH:mm")
    }

    var tint: Color {
        if hasError { return Aurora.rose }
        if primary.contains("不限") { return Aurora.brand }
        if primary == "未查询" || notConfigured { return Aurora.muted }
        return Aurora.ink
    }
}

enum AccountBalanceParser {

    static func snapshot(_ json: JSONValue) -> [String: AccountBalance] {
        var found: [String: AccountBalance] = [:]
        walk(json, depth: 0) { node in
            guard let dict = node.objectValue else { return }
            let id = dict["id"]?.stringValue
                ?? dict["accountId"]?.stringValue
                ?? dict["account"]?.stringValue
            guard let id, !id.isEmpty else { return }
            guard dict["usage"] != nil || dict["balance"] != nil
                    || dict["at"] != nil || dict["code"] != nil else { return }
            if found[id] != nil { return }
            found[id] = parse(id: id, node: node)
        }
        return found
    }

    /// 单账号接口 `GET /api/accounts/usage?id=`
    ///
    /// 面板真实返回和快照同一个信封：
    ///   `{results: [{id, usage: {...}, error, code, at, lastUsage}, …]}`
    /// 老版本这里只认 `{usage:{…}}`，于是把整个信封当 usage 解析，
    /// 一个数值都找不到 → primary 停在默认的「未查询」。
    /// 表现就是：**点了刷新凭证 / 重进详情页，余额还是一直「未查询」**。
    static func single(_ json: JSONValue, id: String) -> AccountBalance {
        // ① 标准信封
        if let results = json.arr("results") ?? json.obj("data")?.arr("results") {
            let node = results.first { item in
                item.firstString(["id", "accountId", "account"]) == id
            } ?? (results.count == 1 ? results[0] : nil)
            if let node { return parseResultItem(id: id, node: node) }
        }
        // ② 老式 `{usage:{…}}`
        if let usage = json.obj("usage") {
            return parse(id: id, node: .object(["id": .string(id), "usage": usage]))
        }
        // ③ `{data:{…}}`
        if let data = json.obj("data") { return single(data, id: id) }
        // ④ 直接就是 usage
        return parse(id: id, node: json)
    }

    /// 解 `results[]` 里的一个账号。
    ///
    /// 这次查询失败但网关带了 `lastUsage` 时，显示上一次的数字并标注来源 ——
    /// 比直接甩一个「查询失败」有用得多（上游偶发 5xx 时尤其明显）。
    private static func parseResultItem(id: String, node: JSONValue) -> AccountBalance {
        let parsed = parse(id: id, node: node)
        guard parsed.primary == "未查询",
              let last = node.obj("lastUsage") ?? node.obj("last_usage") else { return parsed }
        var older = parse(id: id, node: .object(["id": .string(id), "usage": last]))
        guard older.primary != "未查询" else { return parsed }
        older.error = parsed.error
        older.code = parsed.code
        older.at = date(node.firstString(["lastSuccessAt"])) ?? parsed.at
        older.secondary = ["上次查询", older.secondary].compactMap { $0 }.joined(separator: " · ")
        return older
    }

    // MARK: 一条

    private static func parse(id: String, node: JSONValue) -> AccountBalance {
        var result = AccountBalance(id: id)
        result.code = node.firstString(["code"])
        result.at = date(node.firstString(["at", "updatedAt", "lastSuccessAt"]))

        let usage = node.obj("usage") ?? node
        // error 有的是字符串，有的是 `{message:…}`；usage 里也可能再带一份
        if let error = errorText(node) ?? errorText(usage) {
            result.error = error
        }

        if usage.bool("unlimited") == true {
            result.primary = "不限"
        }

        let unit = normalizedUnit(usage.firstString(["unit"]) ?? unitFromSources(usage))
        var remaining = number(usage, keys: ["totalLeft", "available", "remaining", "left", "balance"])
        let limit = number(usage, keys: ["limit", "total", "quota"])
        let percent = number(usage, keys: ["remainingPercent", "percent"])
        /// 总额是「赠送 + 券」拼出来的时，记一句拆分说明
        var breakdown: String?

        // 面板的余额快照里，每个账号是 `{id, usage:{...}, remaining: 1340, ...}`：
        // 有些提供商（autoclaw 这类）自己在 usage 里带 available/remaining，
        // 有些（workbuddy）只给 `bonusLeft` + `credits[]`，可用总额在**外层** remaining 上。
        if remaining == nil {
            remaining = number(node, keys: ["remaining", "totalLeft", "left", "balance"])
        }
        if remaining == nil {
            // workbuddy / CodeBuddy：赠送额度 + 各张券的剩余，加起来才是可用总额。
            // 顺手记一句拆分说明 —— 不然「1340」和下面三张券（500+80+80）对不上，
            // 用户会以为算错了。
            let bonus = number(usage, keys: ["bonusLeft", "bonus", "giftLeft"])
            let credits = usage.arr("credits") ?? []
            let creditSum = credits
                .compactMap { number($0, keys: ["remain", "remaining", "left"]) }
                .reduce(0, +)
            if let bonus {
                remaining = bonus + creditSum
                breakdown = "含赠送 \(format(bonus)) + 券 \(format(creditSum))"
            } else if !credits.isEmpty {
                remaining = creditSum
                breakdown = "券合计 \(format(creditSum))"
            }
        }

        if result.primary != "不限" {
            if let remaining {
                result.primary = "\(format(remaining))\(unit.isEmpty ? "" : " \(unit)")"
            } else if let percent {
                result.primary = "\(Int(percent.rounded()))%"
            } else if let view = usage.firstString(["view"]), !view.isEmpty, view.count <= 16 {
                result.primary = view
            }
        }

        if let remaining, let limit, limit > 0 {
            result.secondary = "剩 \(format(remaining)) / \(format(limit))\(unit.isEmpty ? "" : " \(unit)")"
        } else if let percent, result.primary != "\(Int(percent.rounded()))%" {
            result.secondary = "剩 \(Int(percent.rounded()))%"
        } else if let breakdown {
            result.secondary = breakdown
        }

        // 额外指标：items[] / quotaSources[]（后者在有的版本里是数组，有的是 {items:[]}）
        var metrics: [BalanceMetric] = []
        let items = usage.arr("items")
            ?? usage.arr("quotaSources")
            ?? usage.obj("quotaSources")?.arr("items")
            ?? []
        for item in items {
            guard metrics.count < 4 else { break }
            let name = item.firstString(["name", "label", "key"]) ?? ""
            guard !name.isEmpty else { continue }
            // 同一家可能给好几条同名额度（比如 trae 的「签到奖励」有 4 张券），
            // 只留一条，不然右栏会出现 4 行一样的字
            guard !metrics.contains(where: { $0.id == name }) else { continue }
            let value = number(item, keys: ["balance", "remaining", "left", "used", "value"])
            let itemUnit = normalizedUnit(item.firstString(["unit"]) ?? unit)
            guard let value else { continue }
            let text = "\(format(value))\(itemUnit.isEmpty ? "" : " \(itemUnit)")"
            if text == result.primary { continue }
            metrics.append(
                BalanceMetric(id: name, label: prettyName(name), value: text)
            )
        }
        result.metrics = metrics
        // 网关说「这家没配余额查询」：这不是失败，别用红字吓人
        if result.notConfigured {
            result.primary = "未配置"
            result.error = nil
        }
        return result
    }

    // MARK: 工具

    /// `error` 有的是字符串，有的是 `{message:…}` / `{detail:…}`
    private static func errorText(_ node: JSONValue) -> String? {
        guard let value = node.value("error") else { return nil }
        if let text = value.stringValue, !text.isEmpty, text != "null" { return text }
        if let message = value.firstString(["message", "detail", "error"]), !message.isEmpty {
            return message
        }
        return nil
    }

    private static func walk(_ value: JSONValue, depth: Int, visit: (JSONValue) -> Void) {
        guard depth < 6 else { return }
        visit(value)
        if let array = value.arrayValue {
            for item in array { walk(item, depth: depth + 1, visit: visit) }
        } else if let object = value.objectValue {
            for (_, child) in object { walk(child, depth: depth + 1, visit: visit) }
        }
    }

    private static func number(_ node: JSONValue, keys: [String]) -> Double? {
        for key in keys {
            guard let value = node.value(key) else { continue }
            if let number = value.doubleValue { return number }
            if let text = value.stringValue,
               let parsed = Double(text.trimmingCharacters(in: .whitespaces)) { return parsed }
        }
        return nil
    }

    private static func unitFromSources(_ usage: JSONValue) -> String? {
        guard let sources = usage.arr("quotaSources") else { return nil }
        for source in sources where source.firstString(["id"]) == "account" {
            if let unit = source.firstString(["unit"]) { return unit }
        }
        return nil
    }

    private static func normalizedUnit(_ raw: String?) -> String {
        guard let raw else { return "" }
        switch raw {
        case "积分", "quota", "credits", "points": return "积分"
        case "次", "times", "requests": return "次"
        case "usd", "USD": return "$"
        case "cny", "CNY", "rmb": return "¥"
        case "copilot_quota_units": return "额度"
        default: return raw
        }
    }

    private static func prettyName(_ raw: String) -> String {
        switch raw {
        case "available", "可用余额": return "可用余额"
        case "frozen", "冻结余额": return "冻结余额"
        case "used-today", "今日已用（次）", "今日已用": return "今日已用"
        case "total", "总额度": return "总额度"
        default: return raw
        }
    }

    static func format(_ value: Double) -> String {
        if value == value.rounded(), abs(value) < 1e12 {
            return String(Int(value))
        }
        return String(format: "%.2f", value)
    }

    private static func date(_ raw: String?) -> Date? {
        guard let raw, !raw.isEmpty else { return nil }
        if let ms = Double(raw), ms > 1_000_000_000 {
            return Date(timeIntervalSince1970: ms > 1_700_000_000_000 ? ms / 1000 : ms)
        }
        return ISO8601DateFormatter().date(from: raw)
    }
}
