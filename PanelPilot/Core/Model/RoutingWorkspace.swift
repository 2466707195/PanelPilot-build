import Foundation

// === 路由工作区（`GET /api/routing/workspace`）===
//
// 桌面端「路由」页是一张可视化配置卡：路由策略 / 会话粘滞 / 参与方式三个下拉，
// 加一份参与名单。数据来自 `/api/routing/workspace`（不传 model 就是全局默认），
// 保存走 `PUT /api/routing/profile`，body 基本就是把读到的 profile 改几项再送回。
//
// 这里不按固定 schema 解码：字段缺了就退化成默认值，界面上最多少一个选项，
// 不会因为面板换版本整页白屏。

// MARK: - 选项

enum RoutingStrategy: String, CaseIterable, Identifiable {
    case inherit = "__inherit"
    case order
    case rotate
    case provider

    var id: String { rawValue }

    var title: String {
        switch self {
        case .inherit: return "继承全局"
        case .order: return "顺序优先"
        case .rotate: return "负载均衡"
        case .provider: return "家内轮询"
        }
    }

    var note: String {
        switch self {
        case .inherit: return "沿用全局路由策略"
        case .order: return "按账号顺序依次尝试，失败才换下一个"
        case .rotate: return "按用量轮转，分散到多个账号"
        case .provider: return "同一个提供商内轮询，跨提供商按顺序"
        }
    }

    static func title(_ raw: String?) -> String {
        RoutingStrategy(rawValue: raw ?? "")?.title ?? "顺序优先"
    }
}

enum RoutingSticky: String, CaseIterable, Identifiable {
    case inherit = "__inherit"
    case auto
    case session
    case turn
    case off

    var id: String { rawValue }

    var title: String {
        switch self {
        case .inherit: return "继承全局"
        case .auto: return "自动"
        case .session: return "会话内"
        case .turn: return "每轮"
        case .off: return "关闭"
        }
    }

    var note: String {
        switch self {
        case .inherit: return "沿用全局粘滞设置"
        case .auto: return "有会话标识时保持同一账号"
        case .session: return "整个会话固定在同一账号"
        case .turn: return "每轮都重新选账号"
        case .off: return "不做会话粘滞"
        }
    }

    static func title(_ raw: String?) -> String {
        RoutingSticky(rawValue: raw ?? "")?.title ?? "自动"
    }
}

enum RoutingScope: String, CaseIterable, Identifiable {
    case all
    case selected

    var id: String { rawValue }

    var title: String {
        switch self {
        case .all: return "全部自动参与"
        case .selected: return "仅加入的参与"
        }
    }

    var note: String {
        switch self {
        case .all: return "新增提供商自动参与；移出本路由的不会自动加回。"
        case .selected: return "只有加入的提供商参与，新增提供商需要手动加入。"
        }
    }
}

// MARK: - 参与者

struct RoutingProviderRef: Identifiable, Equatable {
    var id: String
    var label: String
    var available: Bool
}

struct RoutingAccountRef: Identifiable, Equatable {
    var id: String
    var name: String
    var provider: String
    var enabled: Bool
}

// MARK: - 工作区

struct RoutingWorkspace: Equatable {

    var model: String
    /// 当前模型是否有独立配置（false = 继承全局）
    var customized: Bool
    var strategy: String?
    var sticky: String?
    var providerScope: String
    var providers: [String]
    var disabledProviders: [String]
    var excludedAccounts: [String]
    var revision: Int?
    var accounts: [RoutingAccountRef]
    var providerRefs: [RoutingProviderRef]
    var models: [String]
    /// 全局保护开关（`settings`）
    var protection: [String: Bool]
    var raw: JSONValue

    static let empty = RoutingWorkspace(
        model: "",
        customized: false,
        strategy: nil,
        sticky: nil,
        providerScope: "all",
        providers: [],
        disabledProviders: [],
        excludedAccounts: [],
        revision: nil,
        accounts: [],
        providerRefs: [],
        models: [],
        protection: [:],
        raw: .null
    )

    // MARK: 解析

    static func parse(_ json: JSONValue, requestedModel: String) -> RoutingWorkspace {
        var root = json
        if let data = json.obj("data"), data.obj("profile") != nil { root = data }

        let profile = root.obj("profile") ?? root
        var ws = RoutingWorkspace.empty
        ws.raw = root
        ws.model = profile.firstString(["model", "route", "id"]) ?? requestedModel
        ws.customized = profile.bool("customized") ?? root.bool("customized") ?? false
        ws.strategy = profile.firstString(["strategy"])
        ws.sticky = profile.firstString(["sticky"])
        ws.providerScope = profile.firstString(["providerScope"]) ?? "all"
        ws.providers = profile.arr("providers")?.compactMap { item in
            item.stringValue ?? item.firstString(["id", "provider"])
        } ?? []
        ws.disabledProviders = profile.arr("disabledProviders")?.compactMap { $0.stringValue } ?? []
        ws.excludedAccounts = profile.arr("excludedAccounts")?.compactMap { $0.stringValue } ?? []
        ws.revision = profile.int("revision") ?? root.int("revision")

        ws.accounts = (root.arr("accounts") ?? []).compactMap { item in
            guard let id = item.firstString(["id", "accountId"]) else { return nil }
            return RoutingAccountRef(
                id: id,
                name: item.firstString(["name", "label", "email", "id"]) ?? id,
                provider: item.firstString(["provider", "providerId", "platform"]) ?? "",
                enabled: item.bool("enabled") ?? true
            )
        }

        ws.providerRefs = (root.arr("providers") ?? []).compactMap { item in
            guard let id = item.firstString(["id", "provider", "key"]) else { return nil }
            return RoutingProviderRef(
                id: id,
                label: item.firstString(["label", "name", "title", "id"]) ?? id,
                available: item.bool("available") ?? true
            )
        }

        // models 可能是字符串数组，也可能是 [{model:…}]
        ws.models = (root.arr("models") ?? []).compactMap { item in
            item.stringValue ?? item.firstString(["model", "id", "name"])
        }

        if let settings = root.obj("settings") {
            var protection: [String: Bool] = [:]
            for key in [
                "routingFailoverBackoff", "routingSink", "routingBreakerEnabled",
                "routingFailover", "routingRateLimitSink"
            ] {
                if let value = settings.bool(key) { protection[key] = value }
            }
            ws.protection = protection
        }

        return ws
    }

    // MARK: 派生

    var hasProtection: Bool { protection.values.contains(true) }

    var protectionText: String {
        var parts: [String] = []
        if protection["routingFailoverBackoff"] == true { parts.append("失败退避") }
        if protection["routingSink"] == true { parts.append("限流垫底") }
        if protection["routingBreakerEnabled"] == true { parts.append("熔断保护") }
        return parts.isEmpty ? "关闭" : parts.joined(separator: " · ")
    }

    /// 某个提供商下参与本路由的账号
    func accounts(of provider: String) -> [RoutingAccountRef] {
        accounts.filter { $0.provider == provider }
    }

    var providerLabel: [String: String] {
        var map: [String: String] = [:]
        for item in providerRefs { map[item.id] = item.label }
        return map
    }
}

// MARK: - 草稿

/// 用户还没保存的改动。与服务器返回分开存，才能做「已保存 / 未保存」与撤销。
struct RoutingDraft: Equatable {
    var strategy: RoutingStrategy
    var sticky: RoutingSticky
    var scope: RoutingScope
    var disabledProviders: Set<String>

    init(workspace: RoutingWorkspace) {
        strategy = RoutingStrategy(rawValue: workspace.strategy ?? RoutingStrategy.inherit.rawValue)
            ?? RoutingStrategy(rawValue: workspace.strategy ?? "")
            ?? .inherit
        sticky = RoutingSticky(rawValue: workspace.sticky ?? RoutingSticky.inherit.rawValue)
            ?? RoutingSticky(rawValue: workspace.sticky ?? "")
            ?? .inherit
        scope = RoutingScope(rawValue: workspace.providerScope) ?? .all
        // 没参与名单时用「禁用列表」表示；空集合 = 全部参与
        disabledProviders = Set(workspace.disabledProviders)
    }

    func isDirty(against workspace: RoutingWorkspace) -> Bool {
        let savedStrategy = workspace.strategy ?? RoutingStrategy.inherit.rawValue
        let savedSticky = workspace.sticky ?? RoutingSticky.inherit.rawValue
        let savedScope = workspace.providerScope
        return strategy.rawValue != savedStrategy
            || sticky.rawValue != savedSticky
            || scope.rawValue != savedScope
            || disabledProviders != Set(workspace.disabledProviders)
    }

    /// 保存时的 body：把读到的 profile 原样带上再覆盖改动项。
    func payload(workspace: RoutingWorkspace) -> [String: Any] {
        var body: [String: Any] = [:]
        if !workspace.model.isEmpty { body["model"] = workspace.model }
        if let revision = workspace.revision { body["revision"] = revision }

        // 继承全局 = 不下发该字段（桌面端也是把 undefined 当作继承）
        if strategy != .inherit { body["strategy"] = strategy.rawValue }
        if sticky != .inherit { body["sticky"] = sticky.rawValue }
        body["providerScope"] = scope.rawValue
        body["disabledProviders"] = Array(disabledProviders).sorted()
        return body
    }
}
