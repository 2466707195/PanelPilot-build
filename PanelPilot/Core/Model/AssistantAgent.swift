import SwiftUI

// === AI 助手：工具、步骤卡片、历史会话 ===
//
// 面板/网关走的是 OpenAI 的工具协议（`tools` + `tool_calls`），**工具由客户端执行**：
// 我们把这几个和面板能力一一对应的工具声明给模型，模型决定调哪个，
// 客户端去打对应的面板接口，再把结果作为 `role: tool` 塞回对话。
//
// 界面上每一次工具调用就是一张卡片（「获取账号列表 · 调用中… · 查看结果」），
// 和面板桌面端的观感一致。

// MARK: - 一次工具调用的展示状态

struct ChatToolStep: Identifiable, Equatable {

    enum Status: String {
        case running
        case done
        case failed
    }

    var id: String
    /// 原始工具名，例如 `list_accounts`
    var name: String
    /// 中文名，例如「获取账号列表」
    var label: String
    var icon: String
    var status: Status = .running
    /// 一句话结果，例如「131 个模型」
    var summary: String = ""
    /// 展开后看的原始结果（截断）
    var detail: String = ""

    var statusText: String {
        switch status {
        case .running: return "调用中…"
        case .done: return summary.isEmpty ? "已完成" : summary
        case .failed: return summary.isEmpty ? "失败" : summary
        }
    }

    var tint: Color {
        switch status {
        case .running: return Aurora.brand
        case .done: return Aurora.success
        case .failed: return Aurora.rose
        }
    }
}

// MARK: - 工具目录

enum AssistantToolCatalog {

    struct Spec {
        var name: String
        var label: String
        var icon: String
        var description: String
        var arguments: [String: Any]
    }

    static let specs: [Spec] = [
        Spec(
            name: "list_accounts",
            label: "获取账号列表",
            icon: "person.2",
            description: "读取网关里全部账号（提供商、启用状态、余额、到期时间、当前账号）。只读。",
            arguments: ["type": "object", "properties": [:], "required": []]
        ),
        Spec(
            name: "list_models",
            label: "获取模型列表",
            icon: "cpu",
            description: "读取网关当前可用的模型与映射数量。只读。",
            arguments: ["type": "object", "properties": [:], "required": []]
        ),
        Spec(
            name: "checkin_status",
            label: "查询签到状态",
            icon: "checkmark.seal",
            description: "读取今日签到进度、每个账号是否已签、以及定时签到条目。只读。",
            arguments: ["type": "object", "properties": [:], "required": []]
        ),
        Spec(
            name: "checkin_all",
            label: "全部账号签到",
            icon: "checkmark.seal.fill",
            description: "对所有可签到账号执行一次签到。这是写操作，只在用户明确要求签到/补签时调用。",
            arguments: ["type": "object", "properties": [:], "required": []]
        ),
        Spec(
            name: "usage_stats",
            label: "读取用量统计",
            icon: "chart.bar",
            description: "读取用量统计：请求数、成功率、Token、缓存命中与按天趋势。",
            arguments: [
                "type": "object",
                "properties": [
                    "range": [
                        "type": "string",
                        "enum": ["today", "yesterday", "7", "30"],
                        "description": "时间范围，默认 7"
                    ]
                ],
                "required": []
            ]
        ),
        Spec(
            name: "routing_status",
            label: "读取路由配置",
            icon: "arrow.triangle.branch",
            description: "读取路由策略、会话粘滞、参与提供商与账号。只读。",
            arguments: ["type": "object", "properties": [:], "required": []]
        ),
        Spec(
            name: "refresh_models",
            label: "刷新模型列表",
            icon: "arrow.clockwise",
            description: "让网关重新向上游拉取模型列表。写操作。",
            arguments: ["type": "object", "properties": [:], "required": []]
        ),
        Spec(
            name: "clear_sticky",
            label: "清空会话粘滞",
            icon: "pin.slash",
            description: "清空当前的会话粘滞绑定。写操作，用户明确要求时才调用。",
            arguments: ["type": "object", "properties": [:], "required": []]
        )
    ]

    static func spec(_ name: String) -> Spec? {
        specs.first { $0.name == name }
    }

    static func label(_ name: String) -> String {
        spec(name)?.label ?? name
    }

    static func icon(_ name: String) -> String {
        spec(name)?.icon ?? "wrench.and.screwdriver"
    }

    /// 发给模型的 `tools` 数组
    static var payload: [[String: Any]] {
        specs.map { spec in
            [
                "type": "function",
                "function": [
                    "name": spec.name,
                    "description": spec.description,
                    "parameters": spec.arguments
                ]
            ]
        }
    }
}

// MARK: - 历史会话

struct AssistantSession: Identifiable, Equatable {

    var id: String
    var title: String
    var updatedAt: Date?
    var messageCount: Int
    var preview: String

    var timeText: String {
        guard let updatedAt else { return "" }
        let calendar = Calendar.current
        if calendar.isDateInToday(updatedAt) { return updatedAt.formatted("HH:mm") }
        if calendar.isDateInYesterday(updatedAt) { return "昨天" }
        return updatedAt.formatted("MM-dd")
    }
}

enum AssistantSessionParser {

    static func list(_ json: JSONValue) -> [AssistantSession] {
        let node = json.obj("data") ?? json
        let rows = node.arr("sessions") ?? JSONRows.from(node)
        return rows.compactMap { raw in
            guard let id = raw.firstString(["id"]) else { return nil }
            let messages = raw.arr("messages") ?? []
            let title = raw.firstString(["title"]) ?? "未命名对话"
            let preview = messages.last?.firstString(["content", "text"]) ?? ""
            return AssistantSession(
                id: id,
                title: title.isEmpty ? "未命名对话" : title,
                updatedAt: date(raw.firstString(["updatedAt", "at", "createdAt"])),
                messageCount: messages.count,
                preview: String(preview.prefix(60))
            )
        }
        .sorted { ($0.updatedAt ?? .distantPast) > ($1.updatedAt ?? .distantPast) }
    }

    /// 打开一条会话：把面板的消息翻成气泡，工具调用翻成步骤卡片。
    static func transcript(_ json: JSONValue) -> (messages: [ChatMessage], toolMessages: [[String: Any]]) {
        let node = json.obj("data") ?? json
        let session = node.obj("session") ?? node
        let rows = session.arr("messages") ?? []

        var bubbles: [ChatMessage] = []
        var raw: [[String: Any]] = []

        for row in rows {
            let role = (row.firstString(["role"]) ?? "").lowercased()
            let text = row.firstString(["content", "text"]) ?? ""
            if role == "tool" {
                raw.append([
                    "role": "tool",
                    "tool_call_id": row.firstString(["toolCallId", "tool_call_id"]) ?? "",
                    "content": text
                ])
                continue
            }
            guard role == "assistant" || role == "user" else { continue }

            if role == "assistant" {
                var steps: [ChatToolStep] = []
                var calls: [[String: Any]] = []
                for item in row.arr("toolCalls") ?? [] {
                    let id = item.firstString(["id"]) ?? UUID().uuidString
                    let name = item.firstString(["name"]) ?? ""
                    let args = item.firstString(["arguments"]) ?? "{}"
                    steps.append(
                        ChatToolStep(
                            id: id,
                            name: name,
                            label: AssistantToolCatalog.label(name),
                            icon: AssistantToolCatalog.icon(name),
                            status: .done,
                            summary: "已完成",
                            detail: ""
                        )
                    )
                    calls.append([
                        "id": id,
                        "type": "function",
                        "function": ["name": name, "arguments": args]
                    ])
                }
                var message = ChatMessage(role: .assistant, text: text)
                message.steps = steps
                bubbles.append(message)
                var payload: [String: Any] = ["role": "assistant", "content": text]
                if !calls.isEmpty { payload["tool_calls"] = calls }
                raw.append(payload)
                continue
            }

            bubbles.append(ChatMessage(role: .user, text: text))
            raw.append(["role": "user", "content": text])
        }
        return (bubbles, raw)
    }

    static func date(_ raw: String?) -> Date? {
        guard let raw, !raw.isEmpty else { return nil }
        if let ms = Double(raw), ms > 1_000_000_000 {
            return Date(timeIntervalSince1970: ms > 1_700_000_000_000 ? ms / 1000 : ms)
        }
        return ISO8601DateFormatter().date(from: raw)
    }
}
