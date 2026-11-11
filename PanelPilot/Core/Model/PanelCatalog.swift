import Foundation

// === 页面目录 ===
//
// 这一份文件是「服务器端有哪些页、每页有哪些块、每块打哪个接口」的唯一口径。
// 界面不认识具体业务字段，只按这里的声明去取数据、按声明的样式渲染，
// 所以服务器加字段/换结构时页面不会白屏，最多是多出一行原始值。
//
// 端点全部来自服务器端二进制的路由表与前端 bundle，不是猜的。

// MARK: - 一级 Tab

enum PanelTab: String, CaseIterable, Identifiable {
    case overview
    case routing
    case agent
    case accounts
    case settings

    var id: String { rawValue }

    var title: String {
        switch self {
        case .overview: return "概览"
        case .routing: return "路由"
        case .agent: return "Agent"
        case .accounts: return "账号"
        case .settings: return "设置"
        }
    }

    var icon: String {
        switch self {
        case .overview: return "square.grid.2x2"
        case .routing: return "arrow.triangle.branch"
        case .agent: return "sparkles"
        case .accounts: return "person.2"
        case .settings: return "slider.horizontal.3"
        }
    }
}

// MARK: - 二级页面

enum PanelPage: String, CaseIterable, Identifiable {
    // 一级
    case overview
    case routing
    case agentAssistant
    case agentConfig
    case accounts
    // 设置下的二级
    case checkin
    case models
    case tools
    case proxies
    case gatewayKeys
    case tasks
    case connection

    var id: String { rawValue }

    var title: String {
        switch self {
        case .overview: return "概览"
        case .routing: return "路由"
        case .agentAssistant: return "AI 助手"
        case .agentConfig: return "Agent 配置"
        case .accounts: return "账号"
        case .checkin: return "签到"
        case .models: return "模型管理"
        case .tools: return "工具服务"
        case .proxies: return "网络代理"
        case .gatewayKeys: return "网关 Key"
        case .tasks: return "定时任务"
        case .connection: return "连接方式"
        }
    }

    var icon: String {
        switch self {
        case .overview: return "square.grid.2x2"
        case .routing: return "arrow.triangle.branch"
        case .agentAssistant: return "bubble.left.and.text.bubble.right"
        case .agentConfig: return "person.text.rectangle"
        case .accounts: return "person.2"
        case .checkin: return "checkmark.seal"
        case .models: return "cpu"
        case .tools: return "wrench.and.screwdriver"
        case .proxies: return "network"
        case .gatewayKeys: return "key"
        case .tasks: return "clock.arrow.circlepath"
        case .connection: return "antenna.radiowaves.left.and.right"
        }
    }

    var spec: PanelPageSpec { PanelCatalog.spec(for: self) }
}

// MARK: - 区块与动作

enum PanelSectionStyle {
    /// 自动：根是数组就按列表渲染，是对象就上半部分出指标、下半部分出列表
    case auto
    /// 纯指标：把 JSON 拍平成「标签 + 数值」的方块矩阵
    case stats
    /// 键值表：一行一条，适合配置类响应
    case kv
    /// 列表：一行一条，可点开看全部字段
    case rows
    /// 日志：等宽小字、左对齐、按条分隔
    case feed
}

struct PanelActionSpec: Identifiable {
    var id: String
    var title: String
    var method: String = "POST"
    /// 可含 `{id}`，从选中行取值替换
    var path: String
    /// 需要从某一行取 id 才能发
    var usesRow: Bool = false
    var idKeys: [String] = ["id", "accountId", "keyId", "name", "taskId"]
    /// 额外随 body 提交的固定字段
    var extra: [String: String] = [:]
    /// 二次确认文案（危险操作才填）
    var confirm: String? = nil
    var icon: String = "bolt"
}

struct PanelSectionSpec: Identifiable {
    var id: String
    var title: String
    var path: String
    var query: [String: String] = [:]
    var style: PanelSectionStyle = .auto
    /// 列表行的标题候选字段（依次尝试，全落空就显示 id）
    var titleKeys: [String] = ["name", "nickname", "title", "model", "id"]
    /// 列表行的状态候选字段（命中就渲染成右侧胶囊）
    var statusKeys: [String] = ["status", "state", "enabled", "ok"]
    var emptyText: String = "暂无数据"
    var actions: [PanelActionSpec] = []
    /// 折叠展示：默认收起，点开才请求（日志、原始记录这类大块）
    var collapsed: Bool = false
    /// 可选区块：面板版本不同，接口可能根本不存在（404）。
    /// 这类区块 404 时**直接不显示**，不要甩一张红色「读取失败 + 重试」给用户 ——
    /// 他点一百次重试也变不出一个不存在的接口。
    var optional: Bool = false

    /// 完整请求路径（把 query 拼上）
    var fullPath: String {
        guard !query.isEmpty else { return path }
        let items = query
            .sorted { $0.key < $1.key }
            .map { key, value in
                let escaped = value.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? value
                return "\(key)=\(escaped)"
            }
        let joiner = path.contains("?") ? "&" : "?"
        return path + joiner + items.joined(separator: "&")
    }
}

struct PanelPageSpec {
    var title: String
    var sections: [PanelSectionSpec]
}

// MARK: - 目录本体

enum PanelCatalog {

    static func spec(for page: PanelPage) -> PanelPageSpec {
        switch page {
        case .overview: return overview
        case .routing: return routing
        case .agentAssistant: return agentAssistant
        case .agentConfig: return agentConfig
        case .accounts: return accounts
        case .checkin: return checkin
        case .models: return models
        case .tools: return tools
        case .proxies: return proxies
        case .gatewayKeys: return gatewayKeys
        case .tasks: return tasks
        case .connection: return connection
        }
    }

    // MARK: 概览

    static let overview = PanelPageSpec(
        title: "概览",
        sections: [
            PanelSectionSpec(
                id: "health", title: "网关状态", path: "/health",
                style: .kv, emptyText: "没有返回状态"
            ),
            PanelSectionSpec(
                id: "panel", title: "面板", path: "/api/panel/status",
                style: .kv, emptyText: "面板没有返回注册信息"
            ),
            PanelSectionSpec(
                id: "system", title: "系统信息", path: "/api/system-info",
                style: .kv, emptyText: "没有返回系统信息"
            ),
            PanelSectionSpec(
                id: "today", title: "今日用量", path: "/api/stats/summary",
                query: ["range": "today"], style: .stats, emptyText: "今天还没有请求"
            ),
            PanelSectionSpec(
                id: "week", title: "近 7 天", path: "/api/stats/summary",
                query: ["range": "7"], style: .stats, emptyText: "没有用量记录"
            ),
            PanelSectionSpec(
                id: "accounts", title: "账号", path: "/api/accounts",
                style: .rows,
                titleKeys: ["name", "nickname", "email", "displayName", "id"],
                statusKeys: ["enabled", "status", "state"],
                emptyText: "面板上没有账号"
            ),
            PanelSectionSpec(
                id: "models", title: "模型", path: "/api/models/manage",
                style: .rows, titleKeys: ["name", "model", "id"],
                statusKeys: ["enabled", "status"],
                emptyText: "没有可用模型"
            ),
            PanelSectionSpec(
                id: "keys", title: "网关 Key", path: "/api/keys",
                style: .rows, titleKeys: ["name", "label", "id"],
                statusKeys: ["enabled", "status"],
                emptyText: "还没有网关 Key"
            ),
            PanelSectionSpec(
                id: "routing", title: "路由策略", path: "/api/routing",
                style: .kv, emptyText: "没有路由配置"
            ),
            PanelSectionSpec(
                id: "queue", title: "路由队列", path: "/api/routing/queue",
                style: .rows, titleKeys: ["model", "name", "id"],
                statusKeys: ["strategy", "state"],
                emptyText: "队列为空"
            ),
            PanelSectionSpec(
                id: "proxies", title: "网络代理", path: "/api/proxies",
                style: .rows, titleKeys: ["name", "label", "id"],
                statusKeys: ["enabled", "status"],
                emptyText: "没有代理"
            ),
            PanelSectionSpec(
                id: "tools", title: "工具服务", path: "/api/tools/servers",
                style: .rows, titleKeys: ["name", "id"],
                statusKeys: ["status", "enabled"],
                emptyText: "没有工具服务"
            ),
            PanelSectionSpec(
                id: "checkin", title: "签到", path: "/api/checkin/status",
                style: .kv, emptyText: "没有签到状态"
            ),
            PanelSectionSpec(
                id: "tasks", title: "定时任务", path: "/api/scheduled-tasks",
                style: .rows, titleKeys: ["name", "title", "id"],
                statusKeys: ["enabled", "status"],
                emptyText: "没有定时任务"
            ),
            PanelSectionSpec(
                id: "requests", title: "最近请求", path: "/api/stats/requests",
                query: ["limit": "20"], style: .feed,
                titleKeys: ["model", "id"], emptyText: "还没有请求记录"
            ),
            PanelSectionSpec(
                id: "logs", title: "运行日志", path: "/api/logs",
                query: ["limit": "20"], style: .feed,
                titleKeys: ["level", "event", "id"], emptyText: "还没有日志"
            ),
            PanelSectionSpec(
                id: "logStats", title: "日志统计", path: "/api/logs/stats",
                style: .kv, emptyText: "没有日志统计"
            )
        ]
    )

    // MARK: 路由

    static let routing = PanelPageSpec(
        title: "路由",
        sections: [
            PanelSectionSpec(
                id: "strategy", title: "转发策略", path: "/api/routing",
                style: .kv, emptyText: "没有返回策略"
            ),
            PanelSectionSpec(
                id: "profile", title: "当前画像", path: "/api/routing/profile",
                style: .kv, emptyText: "没有画像"
            ),
            PanelSectionSpec(
                id: "groups", title: "路由分组", path: "/api/routing/groups",
                style: .rows, titleKeys: ["name", "id"],
                statusKeys: ["enabled", "strategy"],
                emptyText: "没有分组",
                actions: [
                    PanelActionSpec(
                        id: "preview", title: "预览", path: "/api/routing/preview", icon: "eye"
                    )
                ]
            ),
            PanelSectionSpec(
                id: "queue", title: "候选队列", path: "/api/routing/queue",
                style: .rows, titleKeys: ["model", "name", "id"],
                statusKeys: ["strategy", "state"], emptyText: "队列为空"
            ),
            PanelSectionSpec(
                id: "sticky", title: "粘性会话", path: "/api/routing/sticky",
                style: .rows, titleKeys: ["model", "key", "id"],
                statusKeys: ["state"], emptyText: "没有粘性会话",
                actions: [
                    PanelActionSpec(
                        id: "clearSticky", title: "全部清除",
                        path: "/api/routing/sticky/clear",
                        confirm: "清除后所有粘性会话会重新分配，确定？",
                        icon: "xmark.circle"
                    )
                ]
            ),
            PanelSectionSpec(
                id: "flow", title: "流转配置", path: "/api/routing/flow",
                style: .kv, emptyText: "没有流转配置"
            ),
            PanelSectionSpec(
                id: "workspace", title: "工作区", path: "/api/routing/workspace",
                style: .kv, emptyText: "没有工作区配置"
            ),
            PanelSectionSpec(
                id: "replays", title: "重放记录", path: "/api/routing/replays",
                style: .feed, titleKeys: ["model", "id"], emptyText: "没有重放记录"
            ),
            PanelSectionSpec(
                id: "trace", title: "路由追踪", path: "/api/routing/trace",
                style: .feed, titleKeys: ["model", "id"], emptyText: "没有追踪记录"
            )
        ]
    )

    // MARK: Agent · 助手

    static let agentAssistant = PanelPageSpec(
        title: "AI 助手",
        sections: [
            PanelSectionSpec(
                id: "config", title: "助手配置", path: "/api/assistant/config",
                style: .kv, emptyText: "没有助手配置"
            ),
            PanelSectionSpec(
                id: "sessions", title: "会话记录", path: "/api/assistant/sessions",
                style: .rows, titleKeys: ["title", "id"],
                statusKeys: ["model"], emptyText: "还没有会话"
            )
        ]
    )

    // MARK: Agent · 配置

    /// 只保留真实存在的接口。
    ///
    /// 2.2.0 之前这里写了 `/api/agents/profiles`、`/api/agents/apply`、
    /// `/api/agent_resources` 三个面板根本没有的路径，必然 404，
    /// 整页就表现成「读取失败」。真实可用的是：
    ///   · `GET  /api/agents`                        客户端列表（`{clients:[…]}`）
    ///   · `POST /api/agents/preview`                `{clientId, operation:"restore"}`
    ///   · `POST /api/agents/restore`                `{clientId, operation:"restore", token}`
    ///   · `GET  /api/agents/{clientId}/resources`   提示词 / Skill / MCP
    static let agentConfig = PanelPageSpec(
        title: "Agent 配置",
        sections: [
            PanelSectionSpec(
                id: "agents", title: "Agent", path: "/api/agents",
                style: .rows, titleKeys: ["name", "id"],
                statusKeys: ["detectionState", "viaGateway"],
                emptyText: "没有检测到可接管的客户端"
            )
        ]
    )

    // MARK: 账号

    static let accounts = PanelPageSpec(
        title: "账号",
        sections: [
            PanelSectionSpec(
                id: "list", title: "账号列表", path: "/api/accounts",
                style: .rows,
                titleKeys: ["name", "nickname", "email", "displayName", "id"],
                statusKeys: ["enabled", "status", "state"],
                emptyText: "面板上没有账号",
                actions: [
                    PanelActionSpec(
                        id: "current", title: "设为当前",
                        path: "/api/accounts/current",
                        usesRow: true, icon: "arrow.right.circle"
                    ),
                    PanelActionSpec(
                        id: "refresh", title: "刷新凭证",
                        path: "/api/accounts/refresh",
                        usesRow: true, icon: "arrow.clockwise"
                    ),
                    PanelActionSpec(
                        id: "checkin", title: "签到",
                        path: "/api/accounts/checkin",
                        usesRow: true, icon: "checkmark.seal"
                    )
                ]
            ),
            PanelSectionSpec(
                id: "current", title: "当前账号", path: "/api/accounts/current",
                style: .kv, emptyText: "没有当前账号"
            ),
            PanelSectionSpec(
                id: "usage", title: "账号用量", path: "/api/accounts/usage",
                style: .auto, emptyText: "没有用量数据"
            ),
            PanelSectionSpec(
                id: "snapshot", title: "用量快照", path: "/api/accounts/usage/snapshot",
                style: .auto, emptyText: "没有快照"
            ),
            PanelSectionSpec(
                id: "connections", title: "账号连接", path: "/api/accounts/connections",
                style: .rows, titleKeys: ["name", "id"],
                statusKeys: ["status", "enabled"], emptyText: "没有连接"
            ),
            PanelSectionSpec(
                id: "sorting", title: "排序规则", path: "/api/accounts/sorting",
                style: .kv, emptyText: "没有排序配置"
            )
        ]
    )

    // MARK: 签到

    static let checkin = PanelPageSpec(
        title: "签到",
        sections: [
            PanelSectionSpec(
                id: "status", title: "签到状态", path: "/api/checkin/status",
                style: .kv, emptyText: "没有签到状态"
            ),
            PanelSectionSpec(
                id: "auto", title: "自动签到", path: "/api/auto-checkin",
                style: .kv, emptyText: "没有自动签到配置",
                actions: [
                    PanelActionSpec(
                        id: "runAuto", title: "立即执行",
                        path: "/api/auto-checkin/run", icon: "play.fill"
                    )
                ]
            ),
            PanelSectionSpec(
                id: "schedules", title: "签到计划", path: "/api/checkin-schedules",
                style: .rows, titleKeys: ["name", "title", "id"],
                statusKeys: ["enabled", "status"], emptyText: "没有签到计划",
                actions: [
                    PanelActionSpec(
                        id: "runSchedule", title: "执行",
                        path: "/api/checkin-schedules/{id}/run",
                        usesRow: true, icon: "play.fill"
                    )
                ]
            ),
            PanelSectionSpec(
                id: "records", title: "签到记录", path: "/api/checkin-records",
                style: .feed, titleKeys: ["account", "name", "id"],
                emptyText: "还没有签到记录"
            ),
            PanelSectionSpec(
                id: "center", title: "签到中心", path: "/api/checkin-center",
                style: .auto, emptyText: "没有签到中心数据"
            ),
            PanelSectionSpec(
                id: "activity", title: "签到活动", path: "/api/checkin-activity",
                style: .auto, emptyText: "没有活动"
            ),
            PanelSectionSpec(
                id: "keepalive", title: "保活", path: "/api/checkin-keepalive",
                style: .kv, emptyText: "没有保活配置"
            )
        ]
    )

    // MARK: 模型管理

    static let models = PanelPageSpec(
        title: "模型管理",
        sections: [
            PanelSectionSpec(
                id: "manage", title: "模型清单", path: "/api/models/manage",
                style: .rows, titleKeys: ["name", "model", "id"],
                statusKeys: ["enabled", "status"], emptyText: "没有模型",
                actions: [
                    PanelActionSpec(
                        id: "refreshModels", title: "刷新模型",
                        path: "/api/models/refresh", icon: "arrow.clockwise"
                    )
                ]
            ),
            PanelSectionSpec(
                id: "mappings", title: "模型映射", path: "/api/models/mappings",
                style: .rows, titleKeys: ["from", "alias", "name"],
                statusKeys: ["to", "target"], emptyText: "没有映射",
                actions: [
                    PanelActionSpec(
                        id: "removeMapping", title: "删除映射",
                        path: "/api/models/mappings/remove",
                        usesRow: true,
                        confirm: "删除这条模型映射？",
                        icon: "trash"
                    )
                ],
                optional: true
            ),
            PanelSectionSpec(
                id: "metadata", title: "模型元数据", path: "/api/models/metadata",
                style: .rows, titleKeys: ["name", "model", "id"],
                statusKeys: ["status"], emptyText: "没有元数据",
                actions: [
                    PanelActionSpec(
                        id: "refreshMeta", title: "刷新元数据",
                        path: "/api/models/metadata/refresh", icon: "arrow.clockwise"
                    )
                ]
            ),
            PanelSectionSpec(
                id: "capabilities", title: "能力标记", path: "/api/models/capabilities",
                style: .auto, emptyText: "没有能力数据", optional: true
            ),
            PanelSectionSpec(
                id: "custom", title: "自定义模型", path: "/api/models/custom",
                style: .rows, titleKeys: ["name", "model", "id"],
                statusKeys: ["enabled"], emptyText: "没有自定义模型",
                actions: [
                    PanelActionSpec(
                        id: "removeCustom", title: "删除",
                        path: "/api/models/custom/remove",
                        usesRow: true,
                        confirm: "删除这个自定义模型？",
                        icon: "trash"
                    )
                ],
                optional: true
            ),
            PanelSectionSpec(
                id: "compact", title: "紧凑路由", path: "/api/models/compact-routes",
                style: .rows, titleKeys: ["name", "model", "id"],
                statusKeys: ["status"], emptyText: "没有紧凑路由"
            ),
            PanelSectionSpec(
                id: "accessModels", title: "模型可见性", path: "/api/model-access/models",
                style: .rows, titleKeys: ["name", "model", "id"],
                statusKeys: ["enabled"], emptyText: "没有可见性配置"
            ),
            PanelSectionSpec(
                id: "accessKeys", title: "模型授权 Key", path: "/api/model-access/keys",
                style: .rows, titleKeys: ["name", "id"],
                statusKeys: ["enabled"], emptyText: "没有授权"
            )
        ]
    )

    // MARK: 工具服务

    static let tools = PanelPageSpec(
        title: "工具服务",
        sections: [
            PanelSectionSpec(
                id: "servers", title: "服务列表", path: "/api/tools/servers",
                style: .rows, titleKeys: ["name", "id"],
                statusKeys: ["status", "enabled"], emptyText: "没有工具服务"
            ),
            PanelSectionSpec(
                id: "providers", title: "工具提供方", path: "/api/tools/providers",
                style: .rows, titleKeys: ["display_name", "name", "id"],
                statusKeys: ["status", "enabled"], emptyText: "没有提供方"
            ),
            PanelSectionSpec(
                id: "selection", title: "提供方选择", path: "/api/tools/provider-selection",
                style: .auto, emptyText: "没有选择配置"
            ),
            PanelSectionSpec(
                id: "apiKeys", title: "工具 Key", path: "/api/tools/api-keys",
                style: .rows, titleKeys: ["name", "provider", "id"],
                statusKeys: ["status"], emptyText: "没有工具 Key"
            ),
            PanelSectionSpec(
                id: "vision", title: "视觉配置", path: "/api/tools/vision/config",
                style: .kv, emptyText: "没有视觉配置",
                actions: [
                    PanelActionSpec(
                        id: "visionTest", title: "测试",
                        path: "/api/tools/vision/config/test", icon: "bolt"
                    )
                ]
            ),
            PanelSectionSpec(
                id: "install", title: "安装信息", path: "/api/tools/install-info",
                style: .kv, emptyText: "没有安装信息"
            ),
            PanelSectionSpec(
                id: "targets", title: "安装目标", path: "/api/tools/install-targets",
                style: .rows, titleKeys: ["name", "id"],
                statusKeys: ["status"], emptyText: "没有安装目标"
            )
        ]
    )

    // MARK: 网络代理

    static let proxies = PanelPageSpec(
        title: "网络代理",
        sections: [
            PanelSectionSpec(
                id: "list", title: "代理列表", path: "/api/proxies",
                style: .rows, titleKeys: ["name", "label", "id"],
                statusKeys: ["enabled", "status"], emptyText: "没有代理",
                actions: [
                    PanelActionSpec(
                        id: "testProxy", title: "测试",
                        path: "/api/proxies/test", usesRow: true, icon: "bolt"
                    )
                ]
            ),
            PanelSectionSpec(
                id: "settings", title: "代理设置", path: "/api/proxies/settings",
                style: .kv, emptyText: "没有代理设置"
            ),
            PanelSectionSpec(
                id: "pool", title: "代理池", path: "/api/proxies/pool",
                style: .rows, titleKeys: ["name", "label", "id"],
                statusKeys: ["enabled", "status"], emptyText: "没有代理池",
                actions: [
                    PanelActionSpec(
                        id: "poolUpdate", title: "更新",
                        path: "/api/proxies/pool/update", icon: "arrow.clockwise"
                    ),
                    PanelActionSpec(
                        id: "poolTest", title: "测速",
                        path: "/api/proxies/pool/test", icon: "bolt"
                    ),
                    PanelActionSpec(
                        id: "poolSync", title: "同步 Clash",
                        path: "/api/proxies/pool/sync-clash", icon: "arrow.triangle.2.circlepath"
                    )
                ]
            )
        ]
    )

    // MARK: 网关 Key

    static let gatewayKeys = PanelPageSpec(
        title: "网关 Key",
        sections: [
            PanelSectionSpec(
                id: "keys", title: "Key 列表", path: "/api/keys",
                style: .rows, titleKeys: ["name", "label", "id"],
                statusKeys: ["enabled", "status"], emptyText: "还没有网关 Key"
            ),
            PanelSectionSpec(
                id: "config", title: "网关配置", path: "/api/config",
                style: .kv, emptyText: "没有网关配置"
            ),
            PanelSectionSpec(
                id: "cors", title: "跨域与访问", path: "/api/cors",
                style: .kv, emptyText: "没有跨域配置"
            )
        ]
    )

    // MARK: 定时任务

    static let tasks = PanelPageSpec(
        title: "定时任务",
        sections: [
            PanelSectionSpec(
                id: "list", title: "任务列表", path: "/api/scheduled-tasks",
                style: .rows, titleKeys: ["name", "title", "id"],
                statusKeys: ["enabled", "status"], emptyText: "没有定时任务",
                actions: [
                    PanelActionSpec(
                        id: "runTask", title: "执行",
                        path: "/api/scheduled-tasks/run",
                        usesRow: true, icon: "play.fill"
                    )
                ]
            ),
            PanelSectionSpec(
                id: "travel", title: "行程任务", path: "/api/travel-schedule",
                style: .rows, titleKeys: ["name", "title", "id"],
                statusKeys: ["enabled", "status"], emptyText: "没有行程任务",
                actions: [
                    PanelActionSpec(
                        id: "runTravel", title: "执行",
                        path: "/api/travel-schedule/run", icon: "play.fill"
                    )
                ]
            ),
            PanelSectionSpec(
                id: "queue", title: "任务队列", path: "/api/queue",
                style: .auto, emptyText: "队列为空"
            )
        ]
    )

    // MARK: 连接方式

    static let connection = PanelPageSpec(
        title: "连接方式",
        sections: [
            PanelSectionSpec(
                id: "status", title: "面板状态", path: "/api/panel/status",
                style: .kv, emptyText: "没有面板状态"
            ),
            PanelSectionSpec(
                id: "system", title: "服务端", path: "/api/system-info",
                style: .kv, emptyText: "没有系统信息"
            ),
            PanelSectionSpec(
                id: "session", title: "会话", path: "/api/session",
                style: .kv, emptyText: "没有会话信息"
            ),
            PanelSectionSpec(
                id: "update", title: "版本与更新", path: "/api/update/status",
                style: .kv, emptyText: "没有更新信息"
            )
        ]
    )
}
