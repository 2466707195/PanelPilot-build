import Foundation

// === 概览仪表盘的数据模型 ===
//
// 服务端 `GET /api/stats/summary?range=` 的真实形状（取自面板前端 m/mobile.js）：
//
// ```
// {
//   overview: { requests, successful, tokens, activeDays, streak, topModel:{model} },
//   dailyTrend: [ { date, tokens, requests, models:[…], clients:[…], apiKeys:[…] } ],
//   models:   [ { id, model, label, requests, success, failures, successRate,
//                 totalTokens, promptTokens, completionTokens, cacheReadTokens } ],
//   providers:[ { id, label, requests, totalTokens } ],
//   accounts: [ { id, label, requests, totalTokens } ],
//   cacheRates: { last24h: { inputTokens, rate }, last1h: …, last7d: … }
// }
// ```
//
// 和别处一样**不按固定 schema 解码**：字段缺了就退化成 0 / nil，
// 图表画空态，不会因为面板换个版本整页白屏。

// MARK: - 趋势点

struct PanelTrendPoint: Identifiable, Equatable {
    var id: String
    /// x 轴文案，例如 `08-12`
    var label: String
    var tokens: Int
    var requests: Int
}

// MARK: - 构成切片

struct PanelStatSlice: Identifiable, Equatable {
    var id: String
    var label: String
    var tokens: Int
    var requests: Int
    var successRate: Double?

    /// 在总量里的占比（0…1）
    func share(of total: Int) -> Double {
        guard total > 0 else { return 0 }
        return Double(tokens) / Double(total)
    }
}

// MARK: - 汇总

struct PanelStatsSummary: Equatable {

    var range: String
    var requests: Int
    var successful: Int
    var tokens: Int
    /// 0…1
    var cacheRate: Double?
    var activeDays: Int
    var streak: Int
    var topModel: String?
    var trend: [PanelTrendPoint]
    var models: [PanelStatSlice]
    var providers: [PanelStatSlice]
    var accounts: [PanelStatSlice]

    var failures: Int { max(requests - successful, 0) }

    /// 0…1；没有请求时为 nil（显示「—」而不是 0%）
    var successRate: Double? {
        requests > 0 ? Double(successful) / Double(requests) : nil
    }

    var hasData: Bool { requests > 0 || tokens > 0 }

    static let empty = PanelStatsSummary(
        range: "7", requests: 0, successful: 0, tokens: 0, cacheRate: nil,
        activeDays: 0, streak: 0, topModel: nil,
        trend: [], models: [], providers: [], accounts: []
    )

    // MARK: 解析

    static func parse(_ json: JSONValue, range: String) -> PanelStatsSummary {
        // 有些版本会包一层 `{ok:true, data:{…}}`
        var root = json
        if let inner = json.obj("data"), inner.obj("overview") != nil || inner.arr("dailyTrend") != nil {
            root = inner
        }

        let overview = root.obj("overview") ?? .null
        let requests = overview.int("requests")
            ?? overview.int("totalRequests")
            ?? root.int("requests")
            ?? 0
        let successful = overview.int("successful")
            ?? overview.int("success")
            ?? overview.int("successCount")
            ?? 0
        let tokens = overview.int("tokens")
            ?? overview.int("totalTokens")
            ?? 0

        var summary = PanelStatsSummary.empty
        summary.range = range
        summary.requests = requests
        summary.successful = successful
        summary.tokens = tokens
        summary.cacheRate = cacheRate(in: root)
        summary.activeDays = overview.int("activeDays") ?? 0
        summary.streak = overview.int("streak") ?? 0
        summary.topModel = overview.obj("topModel")?.firstString(["model", "label", "id"])
            ?? overview.firstString(["topModel"])
        summary.trend = trend(in: root)
        summary.models = slices(in: root.arr("models"))
        summary.providers = slices(in: root.arr("providers"))
        summary.accounts = slices(in: root.arr("accounts"))
        return summary
    }

    /// `cacheRates.last24h.rate`，拿不到就退回 1h / 10m / 7d。
    private static func cacheRate(in root: JSONValue) -> Double? {
        guard let block = root.obj("cacheRates") else {
            // 少数版本把命中率直接放在根上
            return root.doubleValueIfPresent("cacheHitRate") ?? root.doubleValueIfPresent("cacheRate")
        }
        for key in ["last24h", "last1h", "last10m", "last7d"] {
            guard let entry = block.obj(key) else { continue }
            if let rate = entry.doubleValueIfPresent("rate") { return normalize(rate) }
        }
        return nil
    }

    private static func trend(in root: JSONValue) -> [PanelTrendPoint] {
        guard let items = root.arr("dailyTrend") else { return [] }
        return items.compactMap { item -> PanelTrendPoint? in
            let raw = item.firstString(["date", "hour", "day"])
            let tokens = item.int("tokens") ?? item.int("totalTokens") ?? 0
            let requests = item.int("requests") ?? 0
            guard raw != nil || tokens > 0 || requests > 0 else { return nil }
            let key = raw ?? UUID().uuidString
            return PanelTrendPoint(
                id: key,
                label: shortDate(key),
                tokens: tokens,
                requests: requests
            )
        }
    }

    private static func slices(in items: [JSONValue]?) -> [PanelStatSlice] {
        guard let items else { return [] }
        return items.compactMap { item -> PanelStatSlice? in
            let id = item.firstString(["id", "model", "label", "name", "filterValue"]) ?? "unknown"
            let label = item.firstString(["label", "name", "model", "id"]) ?? id
            let tokens = item.int("totalTokens") ?? item.int("tokens") ?? 0
            let requests = item.int("requests") ?? 0
            guard tokens > 0 || requests > 0 else { return nil }
            return PanelStatSlice(
                id: id,
                label: label,
                tokens: tokens,
                requests: requests,
                successRate: item.doubleValueIfPresent("successRate").map(normalize)
            )
        }
        .sorted { $0.tokens > $1.tokens }
    }

    /// 服务端给的是 0…1 的小数；万一给了 0…100 也能兜住。
    private static func normalize(_ value: Double) -> Double {
        value > 1.5 ? value / 100 : value
    }

    private static func shortDate(_ raw: String) -> String {
        // `2026-08-12` / `2026-08-12T10:00:00Z` → `08-12`
        if raw.count >= 10, raw.dropFirst(4).first == "-" {
            let start = raw.index(raw.startIndex, offsetBy: 5)
            let end = raw.index(raw.startIndex, offsetBy: 10)
            return String(raw[start..<end])
        }
        return raw
    }
}

// MARK: - 取数小工具

extension JSONValue {
    /// `doubleValue` 的可空版本：字段不存在时返回 nil，而不是 0。
    func doubleValueIfPresent(_ key: String) -> Double? {
        value(key)?.doubleValue
    }
}

// MARK: - 数字格式

enum PanelNumber {

    /// 紧凑计数：1234 → 1.2k，12345 → 1.2万，1.2e8 → 1.2亿
    static func compact(_ value: Int) -> String {
        let abs = Swift.abs(value)
        if abs >= 100_000_000 {
            return String(format: "%.1f亿", Double(value) / 100_000_000)
        }
        if abs >= 10_000 {
            return String(format: "%.1f万", Double(value) / 10_000)
        }
        if abs >= 1_000 {
            return String(format: "%.1fk", Double(value) / 1_000)
        }
        return grouping(value)
    }

    /// 千分位（不带小数）
    static func grouping(_ value: Int) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.maximumFractionDigits = 0
        return formatter.string(from: NSNumber(value: value)) ?? "\(value)"
    }

    /// 0…1 → `98.6%`
    static func percent(_ value: Double?, digits: Int = 1) -> String {
        guard let value, value.isFinite else { return "—" }
        return String(format: "%.\(digits)f%%", max(0, min(1, value)) * 100)
    }

    /// 时长：980ms / 1.2s
    static func duration(_ ms: Int) -> String {
        guard ms > 0 else { return "—" }
        if ms < 1000 { return "\(ms)ms" }
        return String(format: "%.1fs", Double(ms) / 1000)
    }

    /// 时间戳/字符串 → `HH:mm`
    static func clock(_ raw: JSONValue?) -> String? {
        guard let raw else { return nil }
        switch raw {
        case .number(let stamp):
            let seconds = stamp > 1e12 ? stamp / 1000 : stamp
            guard seconds > 1_000_000_000 else { return nil }
            return Date(timeIntervalSince1970: seconds).formatted("HH:mm")
        case .string(let text):
            guard !text.isEmpty else { return nil }
            let formatter = ISO8601DateFormatter()
            formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            if let date = formatter.date(from: text) { return date.formatted("HH:mm") }
            formatter.formatOptions = [.withInternetDateTime]
            if let date = formatter.date(from: text) { return date.formatted("HH:mm") }
            return text.count > 16 ? String(text.suffix(8).prefix(5)) : text
        default:
            return nil
        }
    }
}
