import Foundation

// === Agent 配置：本地解析层 ===
//
// 「Agent 配置」之前读不出来的真正原因不是网络，而是**报文形状对不上**：
//   · 面板 `GET /api/agents` 回的是 `{ clients: [...] }`，
//     通用列表提取器没把 `clients` 当成列表键，于是整块被当成「一行对象」，
//     标题取不到、状态取不到，界面就只剩一句「读取失败」；
//   · 目录里还写了 `/api/agents/profiles`、`/api/agents/apply`、`/api/agent_resources`
//     这三个根本不存在的路径，必然 404。
//
// 这一层把解析从「猜」改成「按形状枚举 + 明确报错」：
//   · 认 `{clients:[]}`、`{data:{clients:[]}}`、`{items:[]}`、裸数组、单个对象；
//   · 每个客户端逐字段宽松取值，缺字段只影响那一行，不影响整页；
//   · 认不出来时给出**实际收到的顶层键名**，而不是一句空泛的失败。
//
// 纯 Foundation，可以在 CI 里用 fixture 直接跑断言。

// MARK: - 能力

struct AgentCapabilities: Equatable {

    var prompt = false
    var skills = false
    var mcp = false

    var chips: [String] {
        var result: [String] = []
        if prompt { result.append("提示词") }
        if skills { result.append("Skill") }
        if mcp { result.append("MCP") }
        return result
    }

    var isSupported: Bool { prompt || skills || mcp }

    static func parse(_ json: JSONValue?) -> AgentCapabilities {
        guard let json else { return AgentCapabilities() }

        // 少数版本直接给字符串数组：["prompt","skills"]
        if let items = json.arrayValue {
            var caps = AgentCapabilities()
            for item in items {
                switch (item.stringValue ?? "").lowercased() {
                case "prompt", "prompts", "instructions": caps.prompt = true
                case "skill", "skills": caps.skills = true
                case "mcp", "mcps", "tools": caps.mcp = true
                default: continue
                }
            }
            return caps
        }

        guard let object = json.objectValue else { return AgentCapabilities() }
        func on(_ key: String) -> Bool {
            guard let value = object[key] else { return false }
            if let flag = value.boolValue { return flag }
            if value.objectValue != nil { return true }
            if let items = value.arrayValue { return !items.isEmpty }
            if let text = value.stringValue { return !text.isEmpty && text.lowercased() != "false" }
            return false
        }
        return AgentCapabilities(prompt: on("prompt"), skills: on("skills"), mcp: on("mcp"))
    }
}

// MARK: - 一个客户端

struct AgentClient: Identifiable, Equatable {

    var id: String
    var name: String
    /// `resolvedPath` / `configPath`，取到哪个算哪个
    var path: String?
    var viaGateway: Bool
    /// `missing` / `uninitialized` / `read_error` / `unsupported` / 其它
    var detectionState: String
    var readError: String?
    var canUndo: Bool
    var capabilities: AgentCapabilities
    var raw: JSONValue

    /// 检测状态的中文说法（面板前端自己也是这一套）
    var stateTitle: String {
        switch detectionState {
        case "missing": return "未检测到"
        case "uninitialized": return "尚未初始化"
        case "read_error": return "读取失败"
        case "unsupported": return "仅可读取"
        case "": return "客户端原生配置"
        default: return detectionState
        }
    }

    var stateOK: Bool {
        detectionState.isEmpty || detectionState == "unsupported"
    }

    var gatewayTitle: String { viaGateway ? "接入本网关" : "未接入本网关" }
}

// MARK: - 解析器

enum AgentConfigParser {

    struct Outcome: Equatable {
        var clients: [AgentClient]
        /// 实际命中的形状，例如 `clients`、`data.clients`、`array`、`single`
        var shape: String
        /// 解析不出来时的人话（含实际顶层键名），直接显示在界面上
        var problem: String?
        /// 给「本地解析」徽标用，例如 `clients · 3 个`
        var note: String {
            if let problem { return problem }
            if clients.isEmpty { return "\(shape) · 0 个" }
            return "\(shape) · \(clients.count) 个"
        }
    }

    private static let listKeys = ["clients", "agents", "items", "list", "results", "rows"]

    static func parse(_ json: JSONValue) -> Outcome {
        if let items = json.arrayValue {
            return Outcome(clients: items.map(client), shape: "array")
        }

        guard let object = json.objectValue else {
            return Outcome(
                clients: [],
                shape: "scalar",
                problem: "接口返回的不是对象或数组：\(json.displayText)"
            )
        }

        // 1) 顶层直接挂列表
        for key in listKeys {
            guard let value = object[key] else { continue }
            if let items = value.arrayValue {
                return Outcome(clients: items.map(client), shape: key)
            }
            if case .null = value {
                return Outcome(
                    clients: [],
                    shape: key,
                    problem: "`\(key)` 是 null，面板没有返回客户端列表"
                )
            }
        }

        // 2) 包一层 data
        if let data = object["data"] {
            if let items = data.arrayValue {
                return Outcome(clients: items.map(client), shape: "data[]")
            }
            if let inner = data.objectValue {
                for key in listKeys {
                    if let items = inner[key]?.arrayValue {
                        return Outcome(clients: items.map(client), shape: "data.\(key)")
                    }
                }
                // `{data:{}}`：确实没有数据，不算错
                if inner.isEmpty {
                    return Outcome(clients: [], shape: "data", problem: nil)
                }
            }
        }

        // 3) 单个客户端对象（有些版本按 id 查询）
        if object["id"] != nil || object["clientId"] != nil || object["detectionState"] != nil {
            return Outcome(clients: [client(json)], shape: "single")
        }

        // 4) 认不出来：把实际键名报出来，方便一眼看出接口换形状了
        let keys = object.keys.sorted().prefix(8).joined(separator: "、")
        return Outcome(
            clients: [],
            shape: "unknown",
            problem: "返回里没有 clients 列表（实际字段：\(keys.isEmpty ? "空对象" : keys)）"
        )
    }

    static func client(_ item: JSONValue) -> AgentClient {
        let id = item.firstString(["id", "clientId", "key", "slug"]) ?? ""
        let name = item.firstString(["name", "label", "title", "id", "clientId"]) ?? (id.isEmpty ? "未命名客户端" : id)
        let path = item.firstString(["resolvedPath", "configPath", "path", "file"])

        let applied = item.obj("applied")
        let canUndo = applied?.bool("canUndo") ?? item.bool("canUndo") ?? false

        let readError = item.firstString(["readError", "error", "readFailure"])
            ?? applied?.firstString(["readError", "error"])

        return AgentClient(
            id: id,
            name: name,
            path: path,
            viaGateway: item.bool("viaGateway") ?? false,
            detectionState: (item.firstString(["detectionState", "state", "status"]) ?? "").lowercased(),
            readError: readError,
            canUndo: canUndo,
            capabilities: AgentCapabilities.parse(item.value("resources")),
            raw: item
        )
    }
}

// MARK: - 恢复预览

/// `POST /api/agents/preview` 的结果：要改哪些文件、每个文件加了几行减了几行。
struct AgentPreview: Equatable {

    struct FileDiff: Equatable, Identifiable {
        var id: String { path }
        var path: String
        var added: Int
        var removed: Int
        var lines: [String]
    }

    var clientID: String
    var files: [FileDiff]
    var warnings: [String]
    /// 恢复时要原样带回的令牌（`POST /api/agents/restore` 的 body 里）
    var token: String?
    var previewedAt: Date = Date()

    var changedLines: Int { files.reduce(0) { $0 + $1.lines.count } }
    var hasChanges: Bool { changedLines > 0 }

    var summary: String {
        if files.isEmpty { return "没有需要改写的文件" }
        return "\(files.count) 个文件 · \(changedLines) 行差异"
    }
}

enum AgentPreviewParser {

    static func parse(_ json: JSONValue, clientID: String) -> (preview: AgentPreview?, problem: String?) {
        var root = json
        if let data = json.obj("data") { root = data }

        guard root.objectValue != nil || root.arrayValue != nil else {
            return (nil, "预览接口没有返回可解析的内容")
        }

        var files: [AgentPreview.FileDiff] = []
        if let items = root.arr("files") ?? root.arrayValue {
            for item in items {
                let path = item.firstString(["path", "file", "target"]) ?? "（未命名文件）"
                var added = 0
                var removed = 0
                var lines: [String] = []
                if let diff = item.arr("diff") {
                    for entry in diff {
                        let kind = (entry.firstString(["kind", "type"]) ?? "").lowercased()
                        let text = entry.str("text") ?? entry.stringValue ?? ""
                        switch kind {
                        case "added", "add", "+": added += 1; lines.append("+ \(text)")
                        case "removed", "delete", "del", "-", "−": removed += 1; lines.append("− \(text)")
                        default: continue
                        }
                    }
                }
                files.append(.init(path: path, added: added, removed: removed, lines: lines))
            }
        }

        var warnings: [String] = []
        if let items = root.arr("warnings") {
            warnings = items.compactMap { $0.stringValue }.filter { !$0.isEmpty }
        }

        let token = root.firstString(["token", "restoreToken"])
        return (AgentPreview(clientID: clientID, files: files, warnings: warnings, token: token), nil)
    }
}
