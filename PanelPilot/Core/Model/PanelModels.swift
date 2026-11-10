import Foundation
import SwiftUI

// === 面板控制台的数据模型 ===
//
// 注意：这里**没有**「启动进程」「重启服务」这类命令。
// 面板跑在 Windows 上，而且是监听 127.0.0.1 的本机进程；
// iOS 端拿不到那台机器的进程句柄，任何「远程启停」都得靠面板自己暴露接口。
// App 的定位是「连上去看状态、改配置、取密钥、看日志」，不是远程 shell。

// MARK: - 连接方式

/// 三种可达路径。它们的区别只在「手机怎么走到那台 Windows」，
/// 到了 HTTP 层完全一样：都是 `{scheme}://{host}:{port}` + 面板令牌。
enum ConnectionMode: String, Codable, CaseIterable, Identifiable {

    case publicNet = "public"
    case tailscale
    case lan

    var id: String { rawValue }

    var title: String {
        switch self {
        case .publicNet: return "公网"
        case .tailscale: return "Tailscale"
        case .lan: return "局域网"
        }
    }

    var icon: String {
        switch self {
        case .publicNet: return "globe"
        case .tailscale: return "lock.shield"
        case .lan: return "wifi"
        }
    }

    var tint: Color {
        switch self {
        case .publicNet: return Aurora.info
        case .tailscale: return Aurora.brand
        case .lan: return Aurora.teal
        }
    }

    /// 该方式默认的传输层。公网默认强制 HTTPS，另两种默认明文。
    var defaultSecure: Bool {
        self == .publicNet
    }

    /// 面板默认端口：Agent2API 的 HTTP 接口固定从 3065 起。
    var defaultPort: Int? {
        switch self {
        case .publicNet: return nil    // 公网走反代，通常 443/80，由用户自己填
        case .tailscale: return 3065
        case .lan: return 3065
        }
    }

    var placeholderHost: String {
        switch self {
        case .publicNet: return "panel.example.com"
        case .tailscale: return "100.101.102.103 或 my-pc.tailnet.ts.net"
        case .lan: return "192.168.1.20"
        }
    }

    /// 一句话说明「什么情况下用这个」。
    var summary: String {
        switch self {
        case .publicNet:
            return "手机在任何网络下都能连。需要自己搭反向代理 + HTTPS，暴露面最大，务必配强令牌。"
        case .tailscale:
            return "两端都装 Tailscale、登同一账号就能直连。推荐日常使用：不暴露公网，地址固定。"
        case .lan:
            return "手机和电脑在同一 Wi-Fi 下直连。最快，但面板必须监听 0.0.0.0，且电脑不能睡眠。"
        }
    }

    var addressExample: String {
        switch self {
        case .publicNet: return "https://panel.example.com"
        case .tailscale: return "http://100.101.102.103:3065"
        case .lan: return "http://192.168.1.20:3065"
        }
    }
}

// MARK: - 认证方式

/// 面板有两种门：
///   · **令牌**：桌面版直接读 `x-panel-token`，一个头就够；
///   · **账号密码**：装到服务器上的版本强制管理员登录，要先换一次 accessToken。
/// 换到的令牌同样走 `x-panel-token`，所以上层逻辑不需要区分。
enum PanelAuthMode: String, Codable, CaseIterable, Identifiable {

    case token
    case password

    var id: String { rawValue }

    var title: String {
        switch self {
        case .token: return "面板令牌"
        case .password: return "账号密码"
        }
    }

    var icon: String {
        switch self {
        case .token: return "key"
        case .password: return "person.badge.key"
        }
    }

    var summary: String {
        switch self {
        case .token:
            return "直接填 x-panel-token。本机桌面版面板用这个。"
        case .password:
            return "面板装了登录页时用这个：App 自己换令牌，续期也自动做。"
        }
    }
}

// MARK: - 连接配置

struct PanelProfile: Identifiable, Codable, Equatable {

    var id: UUID
    var name: String
    var mode: ConnectionMode
    var host: String
    /// nil 表示用连接方式的默认端口（公网 443/80，内网 3065）
    var port: Int?
    var secure: Bool
    var note: String
    var createdAt: Date
    /// 面板装在了子路径下（例如 nginx 的 `location /a2a/`），这里填 `a2a`
    var pathPrefix: String
    var authMode: PanelAuthMode
    /// 账号密码模式下的管理员用户名（密码进钥匙串，不落配置）
    var username: String

    init(
        id: UUID = UUID(),
        name: String = "",
        mode: ConnectionMode = .tailscale,
        host: String = "",
        port: Int? = nil,
        secure: Bool? = nil,
        note: String = "",
        createdAt: Date = Date(),
        pathPrefix: String = "",
        authMode: PanelAuthMode = .token,
        username: String = ""
    ) {
        self.id = id
        self.name = name
        self.mode = mode
        self.host = host
        self.port = port
        self.secure = secure ?? mode.defaultSecure
        self.note = note
        self.createdAt = createdAt
        self.pathPrefix = pathPrefix
        self.authMode = authMode
        self.username = username
    }

    // 手工解码：以后加字段时老配置不会整条读不出来
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = (try? c.decode(UUID.self, forKey: .id)) ?? UUID()
        name = (try? c.decode(String.self, forKey: .name)) ?? "面板"
        mode = (try? c.decode(ConnectionMode.self, forKey: .mode)) ?? .tailscale
        host = (try? c.decode(String.self, forKey: .host)) ?? ""
        port = try? c.decodeIfPresent(Int.self, forKey: .port)
        secure = (try? c.decode(Bool.self, forKey: .secure)) ?? mode.defaultSecure
        note = (try? c.decode(String.self, forKey: .note)) ?? ""
        createdAt = (try? c.decode(Date.self, forKey: .createdAt)) ?? Date()
        pathPrefix = (try? c.decode(String.self, forKey: .pathPrefix)) ?? ""
        authMode = (try? c.decode(PanelAuthMode.self, forKey: .authMode)) ?? .token
        username = (try? c.decode(String.self, forKey: .username)) ?? ""
    }

    var effectivePort: Int? { port ?? mode.defaultPort }

    var trimmedHost: String {
        var value = host.trimmingCharacters(in: .whitespacesAndNewlines)
        while value.hasSuffix("/") { value.removeLast() }
        return value
    }

    var isValid: Bool { !trimmedHost.isEmpty }

    /// 面板根地址，末尾不带斜杠。路径拼接统一在这里做。
    var baseString: String {
        let scheme = secure ? "https" : "http"
        var hostPart = trimmedHost
        // 用户可能直接粘贴了带协议的完整 URL
        if let range = hostPart.range(of: "://") {
            hostPart = String(hostPart[range.upperBound...])
        }
        if let port = effectivePort, !hostPart.contains(":") {
            hostPart += ":\(port)"
        }
        return "\(scheme)://\(hostPart)"
    }

    /// 规范化后的子路径：`a2a`、`/a2a`、`/a2a/` 都变成 `/a2a`；空则无子路径。
    var normalizedPathPrefix: String {
        var value = pathPrefix.trimmingCharacters(in: .whitespacesAndNewlines)
        while value.hasPrefix("/") { value.removeFirst() }
        while value.hasSuffix("/") { value.removeLast() }
        return value.isEmpty ? "" : "/" + value
    }

    /// 真正要请求的根（含子路径）。API 客户端一律拿这个当 base。
    var rootString: String { baseString + normalizedPathPrefix }

    /// 面板自己的 OpenAI 兼容入口（给 Agent/CLI 填 base_url 用）。
    var apiBaseString: String { rootString + "/v1" }

    var displayAddress: String {
        var text = trimmedHost
        if let port = effectivePort { text += ":\(port)" }
        return text + normalizedPathPrefix
    }

    /// 带协议头的地址。界面上用它，一眼能看出这一条是不是 TLS。
    var displayAddressWithScheme: String {
        (secure ? "https://" : "http://") + displayAddress
    }

    /// 从粘贴的文本里解析出 host / 端口 / 协议 / 子路径。
    /// 支持 `http://1.2.3.4:3065`、`1.2.3.4:3065`、`http://1.2.3.4/a2a`、`panel.example.com`。
    static func parse(_ text: String, into profile: inout PanelProfile) {
        let raw = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !raw.isEmpty else { return }

        var working = raw
        if working.hasPrefix("https://") {
            profile.secure = true
            working = String(working.dropFirst("https://".count))
        } else if working.hasPrefix("http://") {
            profile.secure = false
            working = String(working.dropFirst("http://".count))
        }
        while working.hasSuffix("/") { working.removeLast() }

        // 路径部分单独收进 pathPrefix —— 反向代理常把面板挂在子路径下
        if let slash = working.firstIndex(of: "/") {
            let path = String(working[working.startIndex..<slash])
            profile.pathPrefix = String(working[slash...]).trimmingCharacters(in: CharacterSet(charactersIn: "/"))
            working = path
        } else {
            profile.pathPrefix = ""
        }

        let parts = working.split(separator: ":")
        if parts.count == 2, let port = Int(parts[1]) {
            profile.host = String(parts[0])
            profile.port = port
        } else {
            profile.host = working
        }
    }
}

// MARK: - /health 快照

/// `/health` 是面板唯一不需要鉴权的运行时接口，
/// 字段就是面板自报的家底，App 的「在线」判定完全基于它。
struct PanelHealth: Equatable {

    var status: String = "unknown"
    var product: String = ""
    var modelCount: Int = 0
    var authRequired: Bool = true
    var authSource: String = ""
    var currentAccountId: String = ""
    var defaultModel: String = "auto"
    var transport: String = ""
    var upstreamBaseURL: String = ""
    var upstreamConfigured: Bool = false
    var unavailableReason: String?
    var login: PanelLogin?
    var raw: JSONValue = .object([:])

    init() {}

    init(json: JSONValue) {
        raw = json
        status = json.firstString(["status"]) ?? "unknown"
        product = json.firstString(["product"]) ?? ""
        modelCount = json.firstInt(["models"]) ?? 0
        authRequired = json.bool("authRequired") ?? true
        authSource = json.firstString(["authSource"]) ?? ""
        currentAccountId = json.firstString(["currentAccountId"]) ?? ""
        defaultModel = json.firstString(["defaultModel"]) ?? "auto"
        transport = json.firstString(["transport"]) ?? ""
        upstreamBaseURL = json.firstString(["upstreamBaseUrl", "upstreamBaseURL"]) ?? ""
        upstreamConfigured = json.bool("upstreamConfigured") ?? false
        unavailableReason = json.firstString(["unavailableReason"])
        if let loginJSON = json.obj("login") {
            login = PanelLogin(json: loginJSON)
        }
    }

    var isHealthy: Bool { status.lowercased() == "ok" }

    var statusText: String {
        if isHealthy { return "运行中" }
        if let reason = unavailableReason, !reason.isEmpty { return reason }
        return status.isEmpty ? "未知" : status
    }
}

struct PanelLogin: Equatable {
    var platform: String = ""
    var nickname: String = ""
    var edition: String = ""
    var endpoint: String = ""
    var accountUid: String = ""
    var accountType: String = ""
    var loggedIn: Bool = false
    var canRefresh: Bool = false
    var tokenExpiry: String?
    var authFile: String = ""

    init(json: JSONValue) {
        platform = json.firstString(["platform"]) ?? ""
        nickname = json.firstString(["nickname"]) ?? ""
        edition = json.firstString(["edition"]) ?? ""
        endpoint = json.firstString(["endpoint"]) ?? ""
        accountUid = json.firstString(["accountUid", "currentAccountId"]) ?? ""
        accountType = json.firstString(["accountType"]) ?? ""
        loggedIn = json.bool("loggedIn") ?? false
        canRefresh = json.bool("canRefresh") ?? false
        tokenExpiry = json.firstString(["tokenExpiresAt"])
        authFile = json.firstString(["authFile"]) ?? ""
    }

    /// 昵称优先，其次账号 UID 前 8 位。
    var displayName: String {
        if !nickname.isEmpty { return nickname }
        if !accountUid.isEmpty { return String(accountUid.prefix(8)) }
        return platform.isEmpty ? "未登录" : platform
    }
}

// MARK: - 连接状态

enum LinkState: Equatable {

    case idle
    case connecting
    case online
    /// 连上了，但面板自己报异常（例如上游账号过期）
    case degraded(String)
    case failed(String)

    var isOnline: Bool {
        switch self {
        case .online, .degraded: return true
        default: return false
        }
    }

    var title: String {
        switch self {
        case .idle: return "未连接"
        case .connecting: return "连接中"
        case .online: return "在线"
        case .degraded: return "在线 · 有告警"
        case .failed: return "连接失败"
        }
    }

    var tint: Color {
        switch self {
        case .idle: return Aurora.muted
        case .connecting: return Aurora.info
        case .online: return Aurora.success
        case .degraded: return Aurora.warning
        case .failed: return Aurora.danger
        }
    }

    var detail: String? {
        switch self {
        case .degraded(let reason), .failed(let reason): return reason
        default: return nil
        }
    }
}

// MARK: - 诊断

struct DiagStep: Identifiable, Equatable {
    let id = UUID()
    var title: String
    var ok: Bool
    var detail: String
}

// MARK: - 面板资源（可拉取的接口）

enum PanelResource: String, CaseIterable, Identifiable {

    case accounts
    case models
    case keys
    case logs
    case requests
    case stats
    case checkin

    var id: String { rawValue }

    /// 路径以部署版（带登录的 Web 版）为准，逐个对过前端 bundle：
    /// - 模型清单是 `GET /api/models/manage`；`/api/models/state` 只接受 POST，
    ///   用 GET 打过去会回 404「Not found: GET /api/models/state」。
    /// - 密钥是 `GET /api/keys`（管理外发密钥的那套，不是 model-access 的）。
    /// - 请求记录要带 `limit`，否则服务端按默认条数截断。
    var path: String {
        switch self {
        case .accounts: return "/api/accounts"
        case .models: return "/api/models/manage"
        case .keys: return "/api/keys"
        case .logs: return "/api/logs?limit=60"
        case .requests: return "/api/stats/requests?limit=50"
        case .stats: return "/api/stats/summary?range=7"
        case .checkin: return "/api/checkin-center"
        }
    }

    var title: String {
        switch self {
        case .accounts: return "账号"
        case .models: return "模型"
        case .keys: return "密钥"
        case .logs: return "日志"
        case .requests: return "请求"
        case .stats: return "统计"
        case .checkin: return "签到"
        }
    }

    var icon: String {
        switch self {
        case .accounts: return "person.crop.circle"
        case .models: return "cpu"
        case .keys: return "key"
        case .logs: return "text.alignleft"
        case .requests: return "arrow.left.arrow.right"
        case .stats: return "chart.bar"
        case .checkin: return "calendar"
        }
    }

    var emptyText: String {
        switch self {
        case .accounts: return "面板没返回账号。可能当前实例还没登录上游账号。"
        case .models: return "面板没返回模型清单。"
        case .keys: return "还没有生成过接口密钥。"
        case .logs: return "暂无日志。"
        case .requests: return "暂无请求记录。"
        case .stats: return "暂无统计数据。"
        case .checkin: return "面板没有签到数据。"
        }
    }

    /// 列表项标题候选字段（面板不同版本命名不一致，按顺序试）。
    var titleKeys: [String] {
        switch self {
        case .accounts: return ["nickname", "name", "email", "label", "accountUid", "id"]
        case .models: return ["id", "model", "name", "slug"]
        case .keys: return ["name", "label", "keyName", "id"]
        case .logs: return ["message", "msg", "path", "url", "event", "id"]
        case .requests: return ["model", "path", "endpoint", "url", "id"]
        case .stats: return ["name", "model", "key", "id"]
        case .checkin: return ["name", "nickname", "account", "id"]
        }
    }

    var subtitleKeys: [String] {
        switch self {
        case .accounts: return ["platform", "edition", "accountType", "status", "currentAccountId"]
        case .models: return ["owned_by", "provider", "type", "status"]
        case .keys: return ["prefix", "createdAt", "lastUsedAt", "status"]
        case .logs: return ["level", "time", "ts", "createdAt", "status"]
        case .requests: return ["provider", "status", "duration", "createdAt", "time"]
        case .stats: return ["count", "value", "total"]
        case .checkin: return ["date", "status", "reward", "time"]
        }
    }
}

// MARK: - 列表项取字段

extension PanelResource {

    /// 行标题：按候选字段取第一个非空值，取不到就退回 id / 序号。
    func title(of row: JSONValue) -> String {
        if let value = row.firstString(titleKeys), !value.isEmpty { return value }
        return "未命名"
    }

    /// 行副标题：把候选字段按顺序拼起来，全空则返回 nil（不显示空行）。
    func subtitle(of row: JSONValue) -> String? {
        let parts = subtitleKeys.compactMap { row.str($0) }.filter { !$0.isEmpty && $0 != "null" }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    /// 行右侧的短标记（时间、状态、数量），尽量短，避免把标题挤没。
    func trailing(of row: JSONValue) -> String? {
        let keys = ["time", "ts", "createdAt", "updatedAt", "date", "count", "total", "duration", "status"]
        for key in keys {
            if let value = row.str(key), !value.isEmpty, value != "null" {
                return String(value.suffix(19))
            }
        }
        return nil
    }
}

// MARK: - 拉取结果
struct PanelDataset {
    var resource: PanelResource
    var rows: [JSONValue]
    var root: JSONValue
    var fetchedAt: Date
    var latencyMs: Int
}

// MARK: - 时间线事件

struct PanelEvent: Identifiable, Equatable {
    let id = UUID()
    var at: Date
    var text: String
    var ok: Bool

    var timeText: String { at.formatted("HH:mm:ss") }
}
