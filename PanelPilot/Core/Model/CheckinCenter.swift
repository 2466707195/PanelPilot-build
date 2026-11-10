import SwiftUI

// === 签到中心的数据模型 ===
//
// 全部来自 `GET /api/checkin-center`（面板自己的签到页用的就是它），字段名逐个对齐
// `m/mobile.js` 的渲染逻辑：
//   daily.todayDone / daily.todayEligible / daily.providers[].accounts[]
//   auto.enabled / auto.running / auto.providerOptions[] / auto.schedules[]
// 单账号状态：`checkedInToday` 优先，其次 `dailyCheckin.status`
// （confirming / inactive / ineligible / captcha / failed），都没有就是「待签」。

// MARK: - 单账号状态

enum CheckinState: String {
    case done
    case confirming
    case captcha
    case inactive
    case ineligible
    case failed
    case unavailable
    case pending

    var label: String {
        switch self {
        case .done: return "已签"
        case .confirming: return "待确认"
        case .captcha: return "需人工"
        case .inactive: return "暂无活动"
        case .ineligible: return "不适用"
        case .failed: return "失败"
        case .unavailable: return "凭证失效"
        case .pending: return "未签"
        }
    }

    var color: Color {
        switch self {
        case .done: return Aurora.success
        case .confirming, .captcha: return Aurora.warning
        case .failed, .unavailable: return Aurora.rose
        case .pending: return Aurora.brand
        case .inactive, .ineligible: return Aurora.muted
        }
    }

    var signed: Bool { self == .done }
}

// MARK: - 账号

struct CheckinAccount: Identifiable, Equatable {

    var id: String
    var name: String
    var provider: String
    var available: Bool
    var checkedInToday: Bool
    var checkinAt: String?
    var streakDays: Int
    var status: CheckinState
    var message: String?
    var completed: Int?
    var total: Int?

    /// 一行的说明：最近签到时间 / 连登天数 / 面板给的提示
    var detail: String {
        var parts: [String] = []
        if let checkinAt, !checkinAt.isEmpty { parts.append("最近 \(checkinAt)") }
        if streakDays > 0 { parts.append("连登 \(streakDays) 天") }
        if let completed, let total, total > 0 { parts.append("已领 \(completed)/\(total)") }
        if parts.isEmpty, let message, !message.isEmpty { parts.append(message) }
        return parts.joined(separator: " · ")
    }

    var actionTitle: String {
        switch status {
        case .done: return "重签"
        case .inactive, .ineligible: return "重新查询"
        case .unavailable: return "凭证失效"
        default: return "签到"
        }
    }

    var canCheckin: Bool { available && status != .unavailable }
}

// MARK: - 提供商分组

struct CheckinProviderGroup: Identifiable, Equatable {
    var id: String
    var label: String
    var detail: String?
    var accounts: [CheckinAccount]

    var doneCount: Int { accounts.filter { $0.status.signed }.count }
}

// MARK: - 定时签到

struct CheckinSchedule: Identifiable, Equatable {

    var id: String
    var label: String
    var displayLabel: String
    var time: String
    var timeEnd: String?
    var enabled: Bool
    var providers: [String]
    /// 「每天 00:01–00:30 · 已执行 3/5 个账号」
    var providerRows: [String]
    var retryTime: String?
    var retryGapMinutes: Int
    var retryLimit: Int
    var retryCount: Int
    var nextRunAt: String?
    var lastRunAt: String?
    var lastSummary: String?

    var windowText: String {
        if let timeEnd, !timeEnd.isEmpty, timeEnd != time { return "\(time)–\(timeEnd)" }
        return time
    }

    var retryText: String {
        let head = retryTime.map { "补签到点 \($0)" } ?? "补签到点未设置"
        return "\(head) · 每 \(retryGapMinutes) 分钟重试 · 最多 \(retryLimit) 次"
    }
}

// MARK: - 签到记录

struct CheckinRecord: Identifiable, Equatable {

    var id: String
    var accountName: String
    var provider: String
    var providerLabel: String
    var at: String
    var outcome: String
    var source: String
    var message: String
    var failed: Bool

    var outcomeLabel: String {
        switch outcome.lowercased() {
        case "success", "succeeded", "done", "claimed": return "成功"
        case "already", "already_done", "duplicate": return "今日已领"
        case "pending", "waiting": return "未领取"
        case "captcha": return "需人工验证"
        case "skipped", "inactive", "ineligible": return "不适用"
        case "failed", "error": return "失败"
        default: return outcome.isEmpty ? "—" : outcome
        }
    }

    var outcomeColor: Color {
        switch outcome.lowercased() {
        case "success", "succeeded", "done", "claimed": return Aurora.success
        case "pending", "waiting": return Aurora.brand
        case "captcha": return Aurora.warning
        case "failed", "error": return Aurora.rose
        default: return Aurora.muted
        }
    }

    var sourceLabel: String {
        switch source.lowercased() {
        case "manual": return "手动签到"
        case "schedule": return "定时签到"
        case "makeup": return "定时补签"
        case "": return "—"
        default: return source
        }
    }
}

// MARK: - 提供商选项

struct CheckinProviderOption: Identifiable, Equatable {
    var id: String
    var label: String
}

// MARK: - 整个中心

struct CheckinCenter: Equatable {

    var todayDone: Int = 0
    var todayEligible: Int = 0
    var autoEnabled: Bool = false
    var autoRunning: Bool = false
    var groups: [CheckinProviderGroup] = []
    var schedules: [CheckinSchedule] = []
    var providerOptions: [CheckinProviderOption] = []
    var outOfScope: [String] = []
    var updatedAt: Date?

    static let empty = CheckinCenter()

    /// 还没签的账号数
    var pendingCount: Int {
        groups.reduce(0) { $0 + $1.accounts.filter { $0.available && !$0.status.signed }.count }
    }

    var allAccounts: [CheckinAccount] { groups.flatMap(\.accounts) }

    func account(id: String) -> CheckinAccount? {
        allAccounts.first { $0.id == id }
    }

    var progress: Double {
        guard todayEligible > 0 else { return 0 }
        return min(Double(todayDone) / Double(todayEligible), 1)
    }
}

// MARK: - 解析

enum CheckinParser {

    static func parse(_ json: JSONValue) -> CheckinCenter {
        var center = CheckinCenter()
        let node = json.obj("data") ?? json

        let daily = node.obj("daily") ?? node
        center.todayDone = daily.int("todayDone") ?? 0
        center.todayEligible = daily.int("todayEligible") ?? 0

        // 账号按提供商分组
        var groups: [CheckinProviderGroup] = []
        for provider in daily.arr("providers") ?? [] {
            let id = provider.firstString(["id", "provider"]) ?? ""
            let label = provider.firstString(["label", "name"]) ?? (id.isEmpty ? "账号" : id)
            let accounts = (provider.arr("accounts") ?? []).compactMap { raw -> CheckinAccount? in
                guard let id = raw.firstString(["id", "accountId"]) else { return nil }
                let dailyCheckin = raw.obj("dailyCheckin")
                let available = raw.bool("available") ?? true
                let checked = raw.bool("checkedInToday") ?? false
                let status = state(available: available, checked: checked, daily: dailyCheckin)
                return CheckinAccount(
                    id: id,
                    name: raw.firstString(["name", "label", "id"]) ?? id,
                    provider: raw.firstString(["provider"]) ?? provider.firstString(["id"]) ?? "",
                    available: available,
                    checkedInToday: checked,
                    checkinAt: raw.firstString(["checkinAt", "lastCheckinAt", "checkedAt"]),
                    streakDays: raw.int("streakDays") ?? 0,
                    status: status,
                    message: dailyCheckin?.firstString(["message"]),
                    completed: dailyCheckin?.int("completedCount"),
                    total: dailyCheckin?.int("totalCount")
                )
            }
            guard !accounts.isEmpty else { continue }
            groups.append(
                CheckinProviderGroup(
                    id: id.isEmpty ? label : id,
                    label: label,
                    detail: provider.firstString(["description"]),
                    accounts: accounts
                )
            )
        }
        center.groups = groups

        let auto = node.obj("auto")
        center.autoEnabled = auto?.bool("enabled") ?? false
        center.autoRunning = auto?.bool("running") ?? false

        center.providerOptions = (auto?.arr("providerOptions") ?? []).compactMap { item in
            guard let id = item.firstString(["id"]) else { return nil }
            return CheckinProviderOption(id: id, label: item.firstString(["label", "name"]) ?? id)
        }

        center.schedules = (auto?.arr("schedules") ?? []).compactMap { raw in
            guard let id = raw.firstString(["id"]) else { return nil }
            let rows = (raw.arr("providerRows") ?? []).map { row -> String in
                let label = row.firstString(["label"]) ?? ""
                let time = row.firstString(["time"]) ?? ""
                let end = row.firstString(["timeEnd"]) ?? ""
                let attempted = row.int("attemptedCount") ?? 0
                let total = row.int("accountCount") ?? 0
                let window = end.isEmpty || end == time ? time : "\(time)–\(end)"
                return "\(label) \(window) · 已执行 \(attempted)/\(total)"
            }
            let last = raw.obj("lastResult")
            return CheckinSchedule(
                id: id,
                label: raw.firstString(["label"]) ?? "",
                displayLabel: raw.firstString(["displayLabel"]) ?? raw.firstString(["label"]) ?? raw.firstString(["time"]) ?? "定时条目",
                time: raw.firstString(["time"]) ?? "00:01",
                timeEnd: raw.firstString(["timeEnd"]),
                enabled: raw.bool("enabled") ?? false,
                providers: (raw.arr("providers") ?? []).compactMap { $0.stringValue },
                providerRows: rows,
                retryTime: raw.firstString(["retryTime"]),
                retryGapMinutes: raw.int("retryGapMinutes") ?? 10,
                retryLimit: raw.int("retryLimit") ?? 3,
                retryCount: raw.int("retryCount") ?? 0,
                nextRunAt: raw.firstString(["nextRunAt"]),
                lastRunAt: last?.firstString(["at"]),
                lastSummary: last.map { summaryText($0) }
            )
        }

        center.outOfScope = (daily.arr("outOfScope") ?? []).compactMap { row in
            guard let label = row.firstString(["label"]) else { return nil }
            let count = row.int("count") ?? 0
            let reason = row.firstString(["reason"]) ?? ""
            return "\(label) ×\(count) · \(reason)"
        }
        center.updatedAt = Date()
        return center
    }

    static func state(available: Bool, checked: Bool, daily: JSONValue?) -> CheckinState {
        if !available { return .unavailable }
        if checked { return .done }
        switch (daily?.firstString(["status"]) ?? "").lowercased() {
        case "confirming": return .confirming
        case "inactive": return .inactive
        case "ineligible": return .ineligible
        case "captcha": return .captcha
        case "failed": return .failed
        default: return .pending
        }
    }

    /// 「签到完成：3/5 成功，保活 1，失败 1」
    static func summaryText(_ result: JSONValue) -> String {
        let total = result.int("total") ?? (result.arr("results")?.count ?? 0)
        let ok = result.int("succeeded") ?? 0
        let active = result.int("active") ?? 0
        let failed = result.int("failedCount") ?? (result.arr("failed")?.count ?? 0)
        var text = "成功 \(ok)/\(total)"
        if active > 0 { text += " · 保活 \(active)" }
        if failed > 0 { text += " · 失败 \(failed)" }
        return text
    }

    static func records(_ json: JSONValue, providerLabels: [String: String]) -> (items: [CheckinRecord], total: Int) {
        let node = json.obj("data") ?? json
        let total = node.int("total") ?? 0
        let rows = node.arr("records") ?? JSONRows.from(node)
        let items = rows.enumerated().compactMap { index, raw -> CheckinRecord? in
            guard raw.objectValue != nil else { return nil }
            let provider = raw.firstString(["provider"]) ?? ""
            return CheckinRecord(
                id: raw.firstString(["id"]) ?? "\(index)-\(raw.firstString(["ts"]) ?? "")",
                accountName: raw.firstString(["accountName", "accountId", "name"]) ?? "—",
                provider: provider,
                providerLabel: raw.firstString(["providerLabel"]) ?? providerLabels[provider] ?? provider,
                at: timeText(raw.firstString(["ts", "at", "time"]) ?? ""),
                outcome: raw.firstString(["outcome", "status"]) ?? "",
                source: raw.firstString(["source", "kind"]) ?? "",
                message: raw.firstString(["message", "error", "reason"]) ?? "",
                failed: raw.firstString(["error"]) != nil
            )
        }
        return (items, total)
    }

    /// 记录里的 `ts` 可能是毫秒数，也可能是 ISO 串
    static func timeText(_ raw: String) -> String {
        if raw.isEmpty { return "—" }
        if let ms = Double(raw), ms > 1_000_000_000 {
            let date = Date(timeIntervalSince1970: ms > 1_700_000_000_000 ? ms / 1000 : ms)
            return date.formatted("MM-dd HH:mm")
        }
        if let date = ISO8601DateFormatter().date(from: raw) {
            return date.formatted("MM-dd HH:mm")
        }
        return raw
    }
}
