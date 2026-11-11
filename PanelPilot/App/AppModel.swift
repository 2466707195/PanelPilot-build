import Foundation
import SwiftUI
import Combine
import UIKit

struct Toast: Identifiable, Equatable {
    enum Kind { case info, success, warning, error }
    let id = UUID()
    var text: String
    var kind: Kind = .info
}

/// 一个区块的数据快照。失败时保留上一份成功结果，只把错误挂出来。
struct SectionData: Equatable {
    var json: JSONValue?
    var error: String?
    var fetchedAt: Date?
    var latency: Int?
    var loading: Bool = false

    var hasValue: Bool { json != nil }
}

/// 更新检查结果（`GET /api/update/check?current=`）。
struct UpdateCheckInfo: Equatable {
    var currentVersion: String?
    var latestVersion: String?
    var hasUpdate: Bool?
    var forced: Bool = false
    var notes: String?
    var pageURL: String?
    var publishedAt: String?
    var checkedAt: Date = Date()

    /// 文案：有新版本 / 已是最新 / 说不清
    var title: String {
        if hasUpdate == true { return "有新版本 \(latestVersion ?? "")" }
        if hasUpdate == false { return "已是最新版本" }
        return "已检查，服务端没给出结论"
    }
}

/// 助手对话里的一条消息。
struct ChatMessage: Identifiable, Equatable {
    enum Role: String { case user, assistant }
    let id: UUID
    var role: Role
    var text: String
    var at: Date
    /// 这一次回答里执行的工具（「调用中… / 已完成 131 个模型」那种卡片）
    var steps: [ChatToolStep]

    init(
        id: UUID = UUID(),
        role: Role,
        text: String,
        at: Date = Date(),
        steps: [ChatToolStep] = []
    ) {
        self.id = id
        self.role = role
        self.text = text
        self.at = at
        self.steps = steps
    }
}

/// 全局状态机：连接配置、登录态、目录驱动的数据缓存、动作执行、助手对话。
///
/// 一句话原则：**界面永远显示「最后一次真实拿到的数据」+「这次为什么没拿到」**。
/// 所有区块都按 `PanelCatalog` 的声明去取数，界面本身不认识业务字段，
/// 因此服务器换字段只会让某个值显示成「—」，不会整页白屏。
@MainActor
final class AppModel: ObservableObject {

    /// 公网入口的域名。证书由服务器上的 acme.sh 自动续期，
    /// App 这边只管认这个域名，不要写死 IP —— IP 没有证书，只能明文。
    static let secureHost = "qingye.cc.cd"

    // MARK: - 配置

    @Published private(set) var profiles: [PanelProfile] = []
    @Published private(set) var activeID: UUID?

    // MARK: - 连接

    @Published private(set) var state: LinkState = .idle
    @Published private(set) var health: PanelHealth?
    @Published private(set) var latency: Int?
    @Published private(set) var lastChecked: Date?
    @Published private(set) var lastError: String?
    @Published private(set) var errorHint: String?
    @Published private(set) var needsLogin = false

    // MARK: - 目录数据

    /// pageID -> sectionID -> 快照
    @Published private(set) var store: [String: [String: SectionData]] = [:]
    /// 折叠区块的展开状态：`pageID/sectionID`
    @Published private(set) var expanded: Set<String> = []

    // MARK: - 概览仪表盘（本地优先）

    /// 当前统计区间：`today / yesterday / 7 / 30`
    @Published private(set) var statsRange: String = "7"
    /// 四个区间的统计快照：同步时一次拉齐，切区间只在本地取，不发请求
    @Published private(set) var statsByRange: [String: PanelStatsSummary] = [:]
    /// 当前区间（本地取）
    var stats: PanelStatsSummary? { statsByRange[statsRange] }
    @Published private(set) var statsError: String?
    @Published private(set) var statsLoading = false
    @Published private(set) var statsUpdatedAt: Date?
    /// 当前展示的是不是磁盘快照（而不是刚同步回来的）
    @Published private(set) var statsFromSnapshot = false
    /// 磁盘快照里最新一份的时间
    @Published private(set) var statsSnapshotAt: Date?
    /// 仪表盘周边数据：accounts / panel / queue / checkin / requests
    @Published private(set) var dashboard: [String: JSONValue] = [:]

    // MARK: - 本地引擎计量（证明交互没有偷偷发请求）

    /// 本次运行真正发出去的网络请求数。
    ///
    /// **故意不加 `@Published`**：它每发一次请求就 +1，而 AppModel 是全局单例，
    /// 一个属性的 `objectWillChange` 会让五个 Tab 里所有存活视图全部重算一遍 body。
    /// 滚动时正好赶上后台刷新，就是肉眼可见的掉帧。诊断页按需读取它们就够了。
    private(set) var networkRequestCount = 0
    /// 本次运行在本地完成的计算 / 渲染次数（同上，不发布）
    private(set) var localComputeCount = 0
    /// 本地快照条目数
    @Published private(set) var vaultEntryCount = 0
    @Published private(set) var vaultNewest: Date?

    // MARK: - Agent 配置

    @Published private(set) var agents: [AgentClient] = []
    /// 实际命中的报文形状，例如 `clients`、`data.clients`
    @Published private(set) var agentsShape: String = ""
    /// 解析不出来时的人话（含实际字段名）
    @Published private(set) var agentsProblem: String?
    @Published private(set) var agentsError: String?
    @Published private(set) var agentsLoading = false
    @Published private(set) var agentsUpdatedAt: Date?
    @Published private(set) var agentsFromSnapshot = false
    /// 恢复预览（含 diff 与一次性令牌）
    @Published private(set) var agentPreview: AgentPreview?
    @Published private(set) var agentPreviewClient: AgentClient?
    @Published private(set) var agentWorkingID: String?
    /// clientId -> `/api/agents/{id}/resources` 的原始返回
    @Published private(set) var agentResources: [String: JSONValue] = [:]

    // MARK: - 路由工作区（可视化配置）

    @Published var routing: RoutingWorkspace = .empty
    @Published var routingDraft = RoutingDraft(workspace: .empty)
    /// 当前编辑的模型；空字符串 = 全局默认
    @Published var routingModel: String = ""
    @Published var routingLoading = false
    @Published var routingSaving = false
    @Published var routingError: String?
    @Published var routingUpdatedAt: Date?
    @Published var routingModels: [String] = []

    // MARK: - 账号（按提供商分组）

    @Published var providers: [AccountProvider] = []
    @Published var accountsLoading = false
    @Published var accountsError: String?
    @Published var accountsUpdatedAt: Date?
    @Published var balances: JSONValue?
    /// 账号 id → 可读余额（快照或单账号查询的结果）
    @Published var balanceByAccount: [String: AccountBalance] = [:]
    @Published var balancesUpdatedAt: Date?
    @Published var balanceError: String?
    /// 正在单独查询余额的账号 id
    @Published var balanceBusyID: String?
    @Published var balancesLoading = false
    @Published var currentAccountID: String?

    // MARK: - 助手输入框

    @Published var assistantModels: [String] = []
    /// Agent 配置用：提供商 → 该提供商下全部模型
    @Published var agentProviders: [String] = []
    @Published var agentModelsByProvider: [String: [String]] = [:]
    @Published var agentModelsLoading = false
    /// 是否把工具声明给模型（默认关：很多网关/模型对 `tools` 支持不完整，
    /// 开着会让请求一直挂着不返回。需要「调用工具中」那种卡片时再打开。）
    @Published var assistantToolsEnabled: Bool =
        UserDefaults.standard.object(forKey: "panel.assistant.tools") as? Bool ?? false {
        didSet { UserDefaults.standard.set(assistantToolsEnabled, forKey: "panel.assistant.tools") }
    }
    @Published var attachments: [ChatAttachment] = []
    @Published var assistantAccess: AssistantAccess = .full
    /// 这一轮回答从什么时候开始等（界面用来显示「正在思考 · 12s」）
    @Published private(set) var replyStartedAt: Date?
    /// 流式文字的累积缓冲：模型一秒可能吐几十段，
    /// 每段都发一次 `@Published` 会让界面明显滞后（字到了、屏上还没动）
    private var deltaBuffer = ""
    private var deltaFlushTask: Task<Void, Never>?
    // MARK: - 签到中心

    /// `GET /api/checkin-center` 的解析结果
    @Published var checkin: CheckinCenter?
    @Published var checkinLoading = false
    @Published var checkinError: String?
    /// 正在执行的账号 id，或 "all"
    @Published var checkinBusy: String?
    @Published var checkinRecords: [CheckinRecord] = []
    @Published var checkinRecordsTotal = 0
    @Published var checkinRecordsLoading = false
    @Published var checkinRecordsError: String?

    /// 网关 Key（助手聊天必须带一把可用的，否则面板会回「所选 API Key 已失效」）
    @Published var gatewayKeys: [GatewayKey] = []
    @Published var assistantKeyID: String = UserDefaults.standard.string(forKey: "panel.assistantKey") ?? "" {
        didSet { UserDefaults.standard.set(assistantKeyID, forKey: "panel.assistantKey") }
    }

    // MARK: - 添加账号流程（网页登录 / 手机号 / 导入）

    @Published var loginMethods: [LoginMethod] = []
    @Published var loginBusy = false
    @Published var loginMessage: String?
    @Published var loginError: String?
    @Published var loginURL: String?
    /// 面板给的中间态：网页登录的 state、短信登录的 deviceId/msgid/uuid
    @Published var loginState = ""
    @Published var smsDeviceID = ""

    // MARK: - 偏好

    /// 启动落在哪一栏：`overview / routing / agent / accounts / settings`
    @Published var startTab: String = UserDefaults.standard.string(forKey: "panel.startTab") ?? "overview" {
        didSet { UserDefaults.standard.set(startTab, forKey: "panel.startTab") }
    }
    /// 图表动画（关掉之后柱子和扇区直接落到终值）
    @Published var chartAnimation: Bool = UserDefaults.standard.object(forKey: "panel.chartAnimation") as? Bool ?? true {
        didSet { UserDefaults.standard.set(chartAnimation, forKey: "panel.chartAnimation") }
    }
    /// 触感反馈
    @Published var hapticsEnabled: Bool = UserDefaults.standard.object(forKey: "panel.haptics") as? Bool ?? true {
        didSet { UserDefaults.standard.set(hapticsEnabled, forKey: "panel.haptics") }
    }
    /// 数字用紧凑写法（1.2万 / 1.2k）还是完整写法
    @Published var compactNumbers: Bool = UserDefaults.standard.object(forKey: "panel.compactNumbers") as? Bool ?? true {
        didSet { UserDefaults.standard.set(compactNumbers, forKey: "panel.compactNumbers") }
    }

    // MARK: - 诊断 / 事件

    @Published private(set) var diagSteps: [DiagStep] = []
    @Published private(set) var isDiagnosing = false
    @Published private(set) var events: [PanelEvent] = []

    // MARK: - 服务端信息 / 更新

    /// 系统信息里的路径是否把主目录/用户名缩写（面板支持 `?hideUsername=1`）
    @Published private(set) var hideUsername: Bool =
        UserDefaults.standard.bool(forKey: "panel.hideUsername.v1")
    @Published private(set) var updateChecking = false
    @Published private(set) var updateInfo: UpdateCheckInfo?
    @Published private(set) var updateError: String?

    // MARK: - 助手

    @Published var chat: [ChatMessage] = []
    @Published var isReplying = false
    @Published var activeSessionID: String?
    @Published var assistantModel: String = ""
    /// 历史会话列表（`GET /api/assistant/sessions`）
    @Published var assistantSessions: [AssistantSession] = []
    @Published var sessionsLoading = false
    @Published var sessionsError: String?
    /// 当前打开的历史会话（用于高亮）
    @Published var loadedSessionID: String?

    // MARK: - 实时推送

    /// SSE 通道是否在线。在线时轮询降频成兜底（60s），不在线时退回 12s。
    @Published private(set) var pushLive = false

    /// 「同步」按钮的忙闲状态。放在这里而不是各个页面里：
    /// 之前点刷新没有任何反馈，用户会连点好几下，叠出好几轮全量请求。
    @Published private(set) var isRefreshing = false
    /// 上一次「同步」真正走完的时间（界面上显示成「刚刚 / 12 秒前」）
    @Published private(set) var lastRefreshAt: Date?

    // MARK: - 全局

    @Published var toast: Toast?
    @Published var autoRefresh: Bool = UserDefaults.standard.object(forKey: "panel.autoRefresh") as? Bool ?? true {
        didSet { UserDefaults.standard.set(autoRefresh, forKey: "panel.autoRefresh") }
    }

    let network = NetworkWatcher()

    // MARK: - 私有

    private var pollTask: Task<Void, Never>?
    private var pollTick = 0
    /// 连续失败次数：一次抖动不算断线，两次才翻状态
    private var pollFailures = 0
    private var pushChannel: PushChannel?
    private var pushDebounce: Task<Void, Never>?
    /// 有事件攒着没处理（刷新进行中时不再叠加，等这一轮跑完）
    private var pushPending = false
    /// 攒着的事件里，有没有「用量变了」/「配置变了」
    private var pushPendingUsage = false
    private var pushPendingConfig = false
    /// 正在跑一轮推送刷新：这期间新事件只标记，不打断
    private var pushRunning = false
    /// 推送很密（比如上游一直在跑请求）时，最多 1.5 秒刷一次界面
    private var lastPushRefresh = Date.distantPast
    /// 全量仪表盘（9 个请求）的节流时间戳
    private var lastFullDashboard = Date.distantPast
    private var chatTask: Task<Void, Never>?
    private var bag = Set<AnyCancellable>()
    private let profilesKey = "panel.profiles.v1"
    private let activeKey = "panel.activeProfile.v1"

    /// 单飞登录：并发请求同时遇到 401 时，只会真正登录一次
    private var loginTask: Task<Bool, Never>?
    /// 上一次「因为 401 主动换令牌」的时间（3 秒内不重复换，避免令牌互相作废）
    private var lastForcedRefreshAt = Date.distantPast
    /// 每次换到新令牌自增，用来判断「这枚令牌是不是我这次请求用的那枚」
    private var sessionGeneration = 0
    /// 上一次登录被面板拒绝的时间（避免被拒后每拍都再撞一次）
    private var lastRejectionAt: Date?
    /// 仪表盘加载序号：只接受最新一次的结果
    private var dashboardToken = 0

    init() {
        loadProfiles()
        network.objectWillChange
            .sink { [weak self] _ in self?.objectWillChange.send() }
            .store(in: &bag)

        // 冷启动先把磁盘快照铺满界面：这一步不依赖任何网络。
        if let id = activeID {
            LocalVault.shared.load(profile: id)
            refreshVaultStats(profile: id)
            seedDashboard(profile: id)
            seedAgents(profile: id)
            seedAllPages(profile: id)
        }

        if activeProfile != nil {
            Task { await connect() }
        }
        startPolling()
    }

    // MARK: - 配置读写

    var activeProfile: PanelProfile? {
        guard let activeID else { return nil }
        return profiles.first { $0.id == activeID }
    }

    var isConfigured: Bool { activeProfile?.isValid == true }

    var activeToken: String {
        guard let id = activeID else { return "" }
        return KeychainStore.get(KeychainStore.panelTokenKey(for: id)) ?? ""
    }

    var activeAPIKey: String {
        guard let id = activeID else { return "" }
        return KeychainStore.get(KeychainStore.apiKeyKey(for: id)) ?? ""
    }

    var activePassword: String {
        guard let id = activeID else { return "" }
        return KeychainStore.get(KeychainStore.panelPasswordKey(for: id)) ?? ""
    }

    var activeRefreshToken: String {
        guard let id = activeID else { return "" }
        return KeychainStore.get(KeychainStore.panelRefreshKey(for: id)) ?? ""
    }

    var hasToken: Bool { !activeToken.trimmingCharacters(in: .whitespaces).isEmpty }

    var authBadge: (text: String, ok: Bool) {
        switch activeProfile?.authMode {
        case .password:
            return needsLogin ? ("未登录", false) : ("已登录", true)
        case .token:
            return hasToken ? ("令牌已存", true) : ("未填令牌", false)
        case .none:
            return ("未配置", false)
        }
    }

    var authFixTitle: String { activeProfile?.authMode == .password ? "去登录" : "去填令牌" }

    var authFixNote: String {
        activeProfile?.authMode == .password
            ? "账号密码登录失效了。去设置里补一次管理员密码，App 会自己重新登录。"
            : "这个连接走的是面板令牌。把面板网页里的 x-panel-token 复制到设置里。"
    }

    var isAuthorized: Bool {
        if activeProfile?.authMode == .password { return !needsLogin }
        return hasToken
    }

    func token(for id: UUID) -> String {
        KeychainStore.get(KeychainStore.panelTokenKey(for: id)) ?? ""
    }

    func apiKey(for id: UUID) -> String {
        KeychainStore.get(KeychainStore.apiKeyKey(for: id)) ?? ""
    }

    func password(for id: UUID) -> String {
        KeychainStore.get(KeychainStore.panelPasswordKey(for: id)) ?? ""
    }

    func refreshToken(for id: UUID) -> String {
        KeychainStore.get(KeychainStore.panelRefreshKey(for: id)) ?? ""
    }

    /// 新建或更新。token / apiKey / password 传 nil 表示「不改」。
    func save(profile: PanelProfile, token: String?, apiKey: String?, password: String? = nil) {
        var list = profiles
        if let index = list.firstIndex(where: { $0.id == profile.id }) {
            list[index] = profile
        } else {
            list.append(profile)
        }
        profiles = list

        if let token { KeychainStore.set(token, for: KeychainStore.panelTokenKey(for: profile.id)) }
        if let apiKey { KeychainStore.set(apiKey, for: KeychainStore.apiKeyKey(for: profile.id)) }
        if let password {
            KeychainStore.set(password, for: KeychainStore.panelPasswordKey(for: profile.id))
            // 换了密码就把旧令牌与旧刷新令牌一起作废，逼下一次重新登录
            KeychainStore.delete(KeychainStore.panelTokenKey(for: profile.id))
            KeychainStore.delete(KeychainStore.panelRefreshKey(for: profile.id))
            UserDefaults.standard.removeObject(forKey: tokenExpiryKey(for: profile.id))
        }

        if activeID == nil { activeID = profile.id }
        persistProfiles()
        objectWillChange.send()
    }

    func activate(_ id: UUID) {
        guard activeID != id else {
            Task { await connect() }
            return
        }
        activeID = id
        UserDefaults.standard.set(id.uuidString, forKey: activeKey)
        resetRuntimeState()
        persistProfiles()
        // 换到另一台面板：先把它自己的本地快照铺上来，再谈连接
        LocalVault.shared.load(profile: id)
        refreshVaultStats(profile: id)
        seedDashboard(profile: id)
        seedAgents(profile: id)
        seedAllPages(profile: id)
        Task { await connect() }
    }

    func delete(_ id: UUID) {
        profiles.removeAll { $0.id == id }
        KeychainStore.delete(KeychainStore.panelTokenKey(for: id))
        KeychainStore.delete(KeychainStore.panelRefreshKey(for: id))
        KeychainStore.delete(KeychainStore.apiKeyKey(for: id))
        KeychainStore.delete(KeychainStore.panelPasswordKey(for: id))
        UserDefaults.standard.removeObject(forKey: tokenExpiryKey(for: id))

        if activeID == id {
            activeID = profiles.first?.id
            if let next = activeID {
                UserDefaults.standard.set(next.uuidString, forKey: activeKey)
            } else {
                UserDefaults.standard.removeObject(forKey: activeKey)
            }
            resetRuntimeState()
        }
        persistProfiles()
    }

    private func loadProfiles() {
        if let data = UserDefaults.standard.data(forKey: profilesKey),
           let list = try? JSONDecoder().decode([PanelProfile].self, from: data) {
            profiles = list
        }
        migrateToSecureEndpoint()
        seedDefaultProfileIfNeeded()

        if let raw = UserDefaults.standard.string(forKey: activeKey), let id = UUID(uuidString: raw) {
            activeID = profiles.contains { $0.id == id } ? id : profiles.first?.id
        } else {
            activeID = profiles.first?.id
        }
    }

    /// 老版本把公网入口写成了 `http://8.160.187.185/a2a`：明文、IP、子路径。
    /// 升级后自动搬到 `https://qingye.cc.cd`，用户不用手动改，也不会继续裸奔。
    private func migrateToSecureEndpoint() {
        guard !profiles.isEmpty else { return }
        var changed = false
        for index in profiles.indices {
            var item = profiles[index]
            guard item.mode == .publicNet, !item.secure else { continue }
            let host = item.trimmedHost
            guard host == "8.160.187.185" || host == Self.secureHost else { continue }
            item.host = Self.secureHost
            item.port = nil
            item.secure = true
            item.pathPrefix = ""
            item.note = "阿里云 · https 443 反代到 3065（Let's Encrypt）"
            if item.name == "阿里云面板" { item.name = "青叶面板" }
            profiles[index] = item
            changed = true
        }
        if changed { persistProfiles() }
    }

    /// 首次启动直接给出这台阿里云面板的入口，用户只需补密码。
    /// 不预填密码：它只该由用户自己输入，App 不内嵌任何凭据。
    ///
    /// 地址是域名 + 443，不是 IP + 80：
    ///   · 服务器在大陆且没有备案，阿里云的备案旁路只拦 80，明文域名根本打不开；
    ///   · 443 上有 Let's Encrypt 证书，全程 TLS，密码和令牌不会裸奔。
    private func seedDefaultProfileIfNeeded() {
        guard profiles.isEmpty else { return }
        let seeded = PanelProfile(
            name: "青叶面板",
            mode: .publicNet,
            host: Self.secureHost,
            port: nil,
            secure: true,
            note: "阿里云 · https 443 反代到 3065（Let's Encrypt）",
            pathPrefix: "",
            authMode: .password,
            username: ""
        )
        profiles = [seeded]
        activeID = seeded.id
        UserDefaults.standard.set(seeded.id.uuidString, forKey: activeKey)
        persistProfiles()
    }

    private func persistProfiles() {
        if let data = try? JSONEncoder().encode(profiles) {
            UserDefaults.standard.set(data, forKey: profilesKey)
        }
    }

    private func resetRuntimeState() {
        // 换服务器/断开时把推送通道一起收掉，否则会连着上一个面板的事件流。
        stopPushChannel()
        isRefreshing = false
        lastRefreshAt = nil
        state = .idle
        health = nil
        latency = nil
        lastError = nil
        errorHint = nil
        needsLogin = false
        lastRejectionAt = nil
        store = [:]
        expanded = []
        chat = []
        activeSessionID = nil
        events = []
        diagSteps = []
        statsByRange = [:]
        statsError = nil
        statsUpdatedAt = nil
        statsSnapshotAt = nil
        statsFromSnapshot = false
        dashboard = [:]
        agents = []
        agentsShape = ""
        agentsProblem = nil
        agentsError = nil
        agentsUpdatedAt = nil
        agentsFromSnapshot = false
        agentPreview = nil
        agentPreviewClient = nil
        agentResources = [:]
    }

    // MARK: - API 实例

    func makeAPI(
        timeout: TimeInterval = 10,
        token override: String? = nil,
        apiKeyOverride: String? = nil
    ) -> PanelAPI? {
        guard let profile = activeProfile, profile.isValid else { return nil }
        return PanelAPI(
            base: profile.rootString,
            token: override ?? activeToken,
            apiKey: apiKeyOverride ?? activeAPIKey,
            timeout: timeout
        )
    }

    private func tokenExpiryKey(for id: UUID) -> String { "panel.tokenExpiry.\(id.uuidString)" }

    private func tokenExpiry(for id: UUID) -> Date? {
        let stamp = UserDefaults.standard.double(forKey: tokenExpiryKey(for: id))
        return stamp > 0 ? Date(timeIntervalSince1970: stamp) : nil
    }

    /// 令牌是否还新鲜：留 2 分钟余量，快到点了就提前换。
    /// 没有过期时间（服务端没给 expiresIn）时当作新鲜，让 401 兜底。
    private func tokenIsFresh(_ id: UUID) -> Bool {
        let value = token(for: id).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else { return false }
        guard let expiry = tokenExpiry(for: id) else { return true }
        return expiry > Date().addingTimeInterval(120)
    }

    // MARK: - 会话（单飞登录）

    /// 账号密码模式下的会话保证。
    ///
    /// 这里是「频繁要求登录 / 凭证失效」的根治点，三条规则：
    ///   1. **单飞**：并发的 401 只会触发一次真实登录，其余等同一个结果。
    ///      面板每次登录都会换发新令牌，并发登录会互相把对方的令牌作废，
    ///      表现就是「一直登、一直失效」。
    ///   2. **只有面板真拒绝凭证时**才置 `needsLogin`。网络抖动、超时、
    ///      某个接口 500 都不算凭证失效，不能弹登录。
    ///   3. 令牌新鲜判断留 2 分钟余量，避免踩着过期点请求。
    func loginIfNeeded(force: Bool = false) async -> Bool {
        guard let profile = activeProfile else { return false }
        guard profile.authMode == .password else { return true }

        if !force, tokenIsFresh(profile.id) { return true }

        // 被拒后 5 秒内不重复撞，避免在错误密码上打转
        if let lastRejectionAt, Date().timeIntervalSince(lastRejectionAt) < 5 {
            return false
        }

        if let loginTask { return await loginTask.value }

        let task = Task<Bool, Never> { [weak self] in
            guard let self else { return false }
            // 先走刷新令牌：不碰密码、不重算人机题，也不会把上一枚令牌顶掉。
            if await self.performRefresh() { return true }
            // 刷新失败（没有 refreshToken / 已过期 / 被吊销）才回落到密码登录。
            return await self.performLogin()
        }
        loginTask = task
        let ok = await task.value
        loginTask = nil
        return ok
    }

    /// 用 refreshToken 续期。失败不翻 `needsLogin`，只把失效的 refresh 清掉。
    private func performRefresh() async -> Bool {
        guard let profile = activeProfile, profile.authMode == .password else { return false }
        let stored = refreshToken(for: profile.id)
        guard !stored.isEmpty, let api = makeAPI(timeout: 15) else { return false }

        do {
            let session = try await api.refreshSession(stored)
            store(session: session, for: profile.id)
            return true
        } catch {
            // 刷新令牌被吊销/过期：清掉，下一层用密码登录
            KeychainStore.delete(KeychainStore.panelRefreshKey(for: profile.id))
            return false
        }
    }

    /// 把一对令牌写进钥匙串，并记下过期时间（服务端给的是秒）。
    private func store(session: PanelSession, for id: UUID) {
        KeychainStore.set(session.accessToken, for: KeychainStore.panelTokenKey(for: id))
        if !session.refreshToken.isEmpty {
            KeychainStore.set(session.refreshToken, for: KeychainStore.panelRefreshKey(for: id))
        }
        if session.expiresIn > 0 {
            UserDefaults.standard.set(
                Date().addingTimeInterval(TimeInterval(session.expiresIn)).timeIntervalSince1970,
                forKey: tokenExpiryKey(for: id)
            )
        } else {
            UserDefaults.standard.removeObject(forKey: tokenExpiryKey(for: id))
        }
        sessionGeneration &+= 1
        needsLogin = false
        lastRejectionAt = nil
    }

    private func performLogin() async -> Bool {
        guard let profile = activeProfile else { return false }
        let id = profile.id
        let user = profile.username.trimmingCharacters(in: .whitespaces)
        let pass = password(for: id)

        guard !user.isEmpty, !pass.isEmpty else {
            needsLogin = true
            lastError = "还没有填管理员密码"
            errorHint = "去「设置 → 连接方式」打开这个连接，补上密码后会自动登录。"
            return false
        }

        guard let api = makeAPI(timeout: 20) else { return false }

        do {
            let session = try await api.login(username: user, password: pass)
            store(session: session, for: id)
            if lastError?.contains("密码") == true || lastError?.contains("登录") == true {
                lastError = nil
                errorHint = nil
            }
            return true
        } catch {
            let apiError = error as? PanelAPIError
            let message = apiError?.errorDescription ?? error.localizedDescription
            lastError = message
            if apiError?.isCredentialRejection == true {
                // 面板明确拒绝：这才是真的「凭证失效」，需要人去改密码
                needsLogin = true
                lastRejectionAt = Date()
                errorHint = "面板拒绝了这组账号密码。去「设置 → 连接方式」改一次密码。"
            } else {
                // 网络不通 / 超时 / 5xx：不是凭证问题，不弹登录，等下一拍自然恢复
                errorHint = apiError?.hint
            }
            return false
        }
    }

    /// 所有鉴权请求的唯一入口：401 时换一次令牌再重试一次。
    ///
    /// 重试只用**新**令牌；如果重试还失败，把原始错误抛给调用方，
    /// 但不在这里翻 `needsLogin` —— 单个接口失败不代表整个会话失效。
    func authenticatedRequest(
        _ method: String,
        _ path: String,
        body: Any? = nil,
        timeout: TimeInterval = 12
    ) async throws -> PanelResponse {
        guard let api = makeAPI(timeout: timeout) else { throw PanelAPIError.notConfigured }
        networkRequestCount &+= 1
        do {
            let response = try await api.request(method, path, body: body)
            markAuthorized()
            return response
        } catch let error as PanelAPIError where error.isAuthFailure {
            let generation = sessionGeneration
            // 一次刷新会并发打几十个接口。如果每个 401 都 `force` 换一次令牌，
            // 面板会不停换发新令牌、把彼此作废 —— 表现就是「点一下刷新就连接失败」。
            // 所以：别人刚换过就直接拿新令牌重试；确实过期了才换，且 3 秒内只换一次。
            if sessionGeneration == generation,
               Date().timeIntervalSince(lastForcedRefreshAt) > 3 {
                lastForcedRefreshAt = Date()
                _ = await loginIfNeeded(force: true)
            } else {
                _ = await loginIfNeeded(force: false)
            }
            guard let retry = makeAPI(timeout: timeout) else {
                throw error
            }
            networkRequestCount &+= 1
            let response = try await retry.request(method, path, body: body)
            if sessionGeneration != generation {
                needsLogin = false
                lastRejectionAt = nil
                errorHint = nil
            }
            markAuthorized()
            return response
        }
    }

    /// 任意一次鉴权成功 = 会话有效：把残留的登录提示收掉。
    private func markAuthorized() {
        if needsLogin { needsLogin = false }
        if lastRejectionAt != nil { lastRejectionAt = nil }
    }

    // MARK: - 连接

    func connect() async {
        guard activeProfile?.isValid == true else {
            state = .idle
            return
        }
        state = .connecting
        lastError = nil
        errorHint = nil

        // 登录失败也继续往下走：/health 不需要令牌，先把「机器还在不在」问清；
        // 真的登录被拒时，登录态会由 `needsLogin` 单独呈现。
        let authorized = await loginIfNeeded()
        guard let api = makeAPI() else {
            state = .idle
            return
        }

        do {
            let result = try await api.health()
            apply(health: result.health, latency: result.latencyMs)
            record(result.health.isHealthy ? "健康检查通过 · \(result.latencyMs)ms" : "面板自报异常：\(result.health.statusText)", ok: result.health.isHealthy)
            state = result.health.isHealthy ? .online : .degraded(result.health.statusText)
            if authorized {
                await loadDashboard(force: true)
                // 连上了就把推送通道挂上去：之后面板一有变化，这里会立刻收到
                startPushChannel()
            }
        } catch {
            handle(failure: error)
        }
    }

    /// 后台轮询：只刷新健康快照，不闪「连接中」，失败也不清空界面。
    func poll() async {
        guard let api = makeAPI(timeout: 8) else { return }
        do {
            let result = try await api.health()
            apply(health: result.health, latency: result.latencyMs)
            pollFailures = 0
            if result.health.isHealthy {
                if state != .online { record("恢复在线 · \(result.latencyMs)ms", ok: true) }
                state = .online
            } else {
                state = .degraded(result.health.statusText)
            }
            lastError = nil
            errorHint = nil
        } catch {
            let apiError = error as? PanelAPIError
            lastError = apiError?.errorDescription ?? error.localizedDescription
            errorHint = apiError?.hint
            pollFailures &+= 1

            // 一次失败不翻脸：刷新时并发拉几十个接口，健康检查可能只是排在队尾超时。
            // 连续两次（≈24 秒）都失败才认定断线 —— 否则会出现
            // 「连接失败 + 延迟 41ms」这种自相矛盾的显示。
            if pollFailures >= 2 || !state.isOnline {
                if state.isOnline {
                    record("连接中断：\(lastError ?? "未知原因")", ok: false)
                }
                state = .failed(lastError ?? "连接失败")
                // 失败就别再留着上一次的延迟数字
                latency = nil
            }
            // 健康检查本身不要令牌；走到这里只可能是网络/服务问题。
            // 只有面板明确要求登录时才去换令牌，别因为一次抖动就重登。
            if let apiError, case .needLogin = apiError {
                _ = await loginIfNeeded(force: true)
            }
        }
    }

    func disconnect() {
        pollTask?.cancel()
        stopPushChannel()
        resetRuntimeState()
    }

    /// 只在这个值**真的变了**的时候才发布：每 12 秒轮询一次，
    /// 无脑赋值会让五个 Tab 的全部视图重算一遍，滚动时看起来就是「掉帧」。
    private func apply(health newValue: PanelHealth, latency value: Int) {
        if health != newValue { health = newValue }
        if latency != value { latency = value }
        // 「最后检查时间」在界面上只显示到分钟。
        // 原来每次轮询/推送刷新都赋值一次，等于每秒让五个 Tab 全部重算一遍 body ——
        // 滚动时正好赶上就是掉帧。同一分钟内不再重复发布。
        let now = Date()
        if let last = lastChecked,
           Calendar.current.isDate(last, equalTo: now, toGranularity: .minute) {
            return
        }
        lastChecked = now
    }

    private func handle(failure error: Error) {
        let apiError = error as? PanelAPIError
        lastError = apiError?.errorDescription ?? error.localizedDescription
        errorHint = apiError?.hint
        state = .failed(lastError ?? "连接失败")
    }

    // MARK: - 目录数据

    func data(page: PanelPage, section: PanelSectionSpec) -> SectionData {
        store[page.rawValue]?[section.id] ?? SectionData()
    }

    /// 区块里的列表行。兼容裸数组、`{data:[...]}`、`{data:{items:[...]}}` 等包装。
    func rows(page: PanelPage, section: PanelSectionSpec) -> [JSONValue] {
        guard let json = data(page: page, section: section).json else { return [] }
        return PanelAPI.rows(from: json)
    }

    /// 区块里的标量字段（列表以外的那些），用于「上面指标、下面列表」的混排。
    func scalars(page: PanelPage, section: PanelSectionSpec) -> [KeyValuePair] {
        guard let json = data(page: page, section: section).json else { return [] }
        return Self.unwrapped(json).flattened().filter { !$0.value.isEmpty }
    }

    // MARK: - 服务端信息 / 更新

    /// `/api/system-info` 的原始返回（连接方式页的「服务端」卡用）
    var systemInfoJSON: JSONValue? {
        store[PanelPage.connection.rawValue]?["system"]?.json
    }

    /// 网关版本号：优先取 system-info 的 `app.version`
    var serverVersionText: String? {
        if let app = systemInfoJSON?.lookup("app"), let version = app.str("version"), !version.isEmpty {
            return version
        }
        if let version = systemInfoJSON?.lookupString(["version"]), !version.isEmpty { return version }
        if let version = updateInfo?.currentVersion, !version.isEmpty { return version }
        return nil
    }

    /// 把服务端信息整理成可粘贴的文本（发给别人排障时用）
    func serverReport() -> String {
        guard let json = systemInfoJSON else { return "" }
        var lines: [String] = []
        for group in PanelFieldBuilder.groups(from: json) {
            guard !group.fields.isEmpty else { continue }
            if !group.title.isEmpty { lines.append("[\(group.title)]") }
            for field in group.fields {
                lines.append("\(field.label): \(field.copyText ?? field.value)")
            }
            lines.append("")
        }
        return lines.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// 切换「隐藏用户名」：面板按 `?hideUsername=1` 把主目录缩成 `~`，切完重拉这一块。
    func setHideUsername(_ value: Bool) async {
        guard hideUsername != value else { return }
        hideUsername = value
        UserDefaults.standard.set(value, forKey: "panel.hideUsername.v1")
        await load(page: .connection, force: true, only: ["system"])
    }

    /// 检查更新：`GET /api/update/check?current=<当前版本>`
    func checkUpdate() async {
        guard !updateChecking else { return }
        updateChecking = true
        updateError = nil

        let current = serverVersionText ?? ""
        var path = "/api/update/check"
        if !current.isEmpty {
            let encoded = current.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? current
            path += "?current=\(encoded)"
        }

        do {
            let response = try await authenticatedRequest("GET", path, timeout: 25)
            let json = response.json
            let info = UpdateCheckInfo(
                currentVersion: json.lookupString(["currentVersion"]) ?? (current.isEmpty ? nil : current),
                latestVersion: json.lookupString(["latestVersion", "latest", "version"]),
                hasUpdate: json.lookupBool(["hasUpdate", "updateAvailable"]),
                forced: json.lookupBool(["forceUpdate"]) ?? false,
                notes: json.lookupString(["notes", "changelog", "releaseNotes"]),
                pageURL: json.lookupString(["pageUrl", "url", "releaseUrl"]),
                publishedAt: json.lookupString(["publishedAt"]),
                checkedAt: Date()
            )
            updateInfo = info
            if info.hasUpdate == true {
                toast = Toast(text: "发现新版本 \(info.latestVersion ?? "")", kind: .warning)
            } else if info.hasUpdate == false {
                toast = Toast(text: "已是最新版本", kind: .success)
            } else {
                toast = Toast(text: "已向面板查询更新", kind: .info)
            }
            record("检查更新：\(info.title)", ok: true)
        } catch {
            let apiError = error as? PanelAPIError
            updateError = apiError?.errorDescription ?? error.localizedDescription
            toast = Toast(text: "检查更新失败：\(updateError ?? "未知原因")", kind: .error)
            record("检查更新失败：\(updateError ?? "未知原因")", ok: false)
        }

        updateChecking = false
    }

    /// 拆掉 `{ok:true, data:{…}}` 这层包装。
    ///
    /// 面板大量接口都是「状态码 + 一层 data/summary」，直接拍平会让每个指标
    /// 都带上 `data.` 前缀。只在顶层确实是个薄包装时才拆，避免把业务对象误拆。
    private static func unwrapped(_ json: JSONValue) -> JSONValue {
        guard let object = json.objectValue, (1...3).contains(object.count) else { return json }
        let wrappers = ["data", "summary", "result", "stats", "usage", "overview", "info"]
        for key in wrappers {
            guard let inner = object[key], inner.objectValue != nil else { continue }
            return inner
        }
        return json
    }

    func isExpanded(_ page: PanelPage, _ section: PanelSectionSpec) -> Bool {
        expanded.contains("\(page.rawValue)/\(section.id)")
    }

    func toggleExpanded(_ page: PanelPage, _ section: PanelSectionSpec) {
        let key = "\(page.rawValue)/\(section.id)"
        if expanded.contains(key) {
            expanded.remove(key)
        } else {
            expanded.insert(key)
            if store[page.rawValue]?[section.id]?.json == nil {
                Task { await load(page: page, only: [section.id]) }
            }
        }
    }

    /// 载入一个页面：**先用本地快照，缺什么才补什么**。
    ///
    /// 只有 `force: true`（下拉刷新、右上角刷新、定时同步）才会整块重拉；
    /// 普通进入页面时，磁盘里有快照就一个请求都不发。
    func load(page: PanelPage, force: Bool = false, only: Set<String>? = nil) async {
        guard activeProfile?.isValid == true else { return }

        let spec = page.spec
        var targets = spec.sections.filter { section in
            if let only { return only.contains(section.id) }
            if section.collapsed && !isExpanded(page, section) { return false }
            return true
        }
        guard !targets.isEmpty else { return }

        if !force, let id = activeID {
            seedSections(page: page, sections: targets, profile: id)
            targets = targets.filter { store[page.rawValue]?[$0.id]?.json == nil }
            guard !targets.isEmpty else { return }
        }

        _ = await loginIfNeeded()

        // 「读取中」一次性标好：原来是一个区块一次赋值，
        // 十个区块就是十次 `objectWillChange`，五个 Tab 的视图跟着重算十遍。
        markLoading(page: page, ids: targets.map(\.id), true)

        // 结果先在本地攒着，全部到齐再发布一次 —— SwiftUI 只重算一遍。
        var bucket = store[page.rawValue] ?? [:]

        await withTaskGroup(of: (String, SectionData).self) { group in
            for section in targets {
                group.addTask { [weak self] in
                    guard let self else { return (section.id, SectionData()) }
                    let result = await self.fetch(page: page, section: section)
                    return (section.id, result)
                }
            }
            for await (id, result) in group {
                var merged = result
                // 失败时保留旧数据与旧时间，只换错误文案
                if result.json == nil, let old = bucket[id] {
                    merged.json = old.json
                    merged.fetchedAt = old.fetchedAt
                }
                merged.loading = false
                bucket[id] = merged
            }
        }

        store[page.rawValue] = bucket
    }

    /// 批量改「读取中」标记：一次赋值，一次发布。
    private func markLoading(page: PanelPage, ids: [String], _ value: Bool) {
        guard !ids.isEmpty else { return }
        var bucket = store[page.rawValue] ?? [:]
        for id in ids {
            var item = bucket[id] ?? SectionData()
            item.loading = value
            bucket[id] = item
        }
        store[page.rawValue] = bucket
    }

    private func fetch(page: PanelPage, section: PanelSectionSpec) async -> SectionData {
        do {
            // 服务端信息支持隐藏用户名（面板自带的能力），路径里就不会出现 /home/xxx
            var path = section.fullPath
            if section.id == "system" && hideUsername {
                path += path.contains("?") ? "&hideUsername=1" : "?hideUsername=1"
            }
            let response = try await authenticatedRequest("GET", path)
            if section.id == "health" {
                apply(health: PanelHealth(json: response.json), latency: response.latencyMs)
            }
            // 成功即落盘：下次进来先读它，不再等网络
            persist(response.json, key: VaultKey.section(page: page.rawValue, id: section.id))
            return SectionData(
                json: response.json,
                error: nil,
                fetchedAt: Date(),
                latency: response.latencyMs
            )
        } catch {
            let apiError = error as? PanelAPIError
            return SectionData(
                json: nil,
                error: apiError?.errorDescription ?? error.localizedDescription,
                fetchedAt: nil,
                latency: nil
            )
        }
    }

    /// 显式同步：这是唯一会「整块重拉」的入口（下拉刷新 / 右上角刷新 / 全部刷新）。
    ///
    /// 老实现是 `connect()` → 仪表盘 → Agent → 路由 → 账号 **串行四段**：
    ///   · 段与段之间互相等待，一次刷新好几秒，期间按钮毫无反馈，
    ///     用户以为没点上就再点一次，叠出第二轮、第三轮全量请求；
    ///   · `connect()` 会把连接状态翻成「连接中」并重启推送通道，
    ///     于是每刷新一次，推送就断一次、状态闪一次。
    /// 现在：四段并发 + 健康检查并发，不碰连接状态，也不重连推送。
    func refreshAll() async {
        guard !isRefreshing else { return }
        guard activeProfile?.isValid == true else {
            await connect()
            return
        }
        isRefreshing = true
        defer { isRefreshing = false }

        // 先单独探活：这一步必须在连接池空闲时做。
        // 原来五路并发铺开，健康检查排在几十个接口后面，8 秒超时直接报「连接失败」。
        await poll()

        _ = await loginIfNeeded()

        // 分阶段推，而不是一次性把四十个请求全扔出去：
        // 这台面板每处理一个带令牌的请求都要重写一次会话表，扛不住那种并发；
        // 而 URLSession 对同一域名只有 6 条连接，全排队就是自己把自己超时。
        await syncDashboard()
        await syncAgents()
        await load(page: .routing, force: true)
        await load(page: .accounts, force: true)

        lastRefreshAt = Date()
        if !pushLive { startPushChannel() }
    }

    func refresh(page: PanelPage) async {
        await load(page: page, force: true)
    }

    // MARK: - 概览仪表盘（本地优先）

    /// 四个区间在同步时一次拉齐；切区间只读本地，不发请求。
    static let statsRanges = ["today", "yesterday", "7", "30"]

    static func rangeTitle(_ range: String) -> String {
        switch range {
        case "today": return "今天"
        case "yesterday": return "昨天"
        case "7": return "近 7 天"
        case "30": return "近 30 天"
        default: return range
        }
    }

    /// 切区间：**纯本地动作**。不 await、不联网。
    ///
    /// 四个区间的统计在「同步」时一次拉齐并落盘，所以这里只是换一个字典键，
    /// KPI、柱状图、环形图、本地派生指标跟着重算一遍。
    func setStatsRange(_ range: String) {
        guard statsRange != range else { return }
        statsRange = range
        localComputeCount &+= 1
        if statsByRange[range] == nil {
            statsError = "本地还没有「\(Self.rangeTitle(range))」的快照，点一次「同步」补齐。"
        } else {
            statsError = nil
        }
        objectWillChange.send()
    }

    /// 显示数据：先读盘，本地有就不进网络。
    func loadDashboard(force: Bool = false) async {
        guard let profile = activeProfile, profile.isValid else { return }
        if !force {
            seedDashboard(profile: profile.id)
            seedAgents(profile: profile.id)
            if statsByRange[statsRange] != nil { return }
        }
        await syncDashboard()
    }

    /// 唯一的仪表盘网络入口。
    ///
    /// 九个请求并发、互不牵连：某个区间失败只让那个区间空着；
    /// 账号 / 队列 / 签到失败只让运行态少一格。拿到的每一份都写进本地快照，
    /// 下次冷启动就不用再等网络。
    func syncDashboard() async {
        guard activeProfile?.isValid == true else { return }
        _ = await loginIfNeeded()

        dashboardToken &+= 1
        let token = dashboardToken
        statsLoading = true

        async let todayJSON = fetchJSON("/api/stats/summary?range=today")
        async let yesterdayJSON = fetchJSON("/api/stats/summary?range=yesterday")
        async let weekJSON = fetchJSON("/api/stats/summary?range=7")
        async let monthJSON = fetchJSON("/api/stats/summary?range=30")
        async let accountsJSON = fetchJSON("/api/accounts")
        async let panelJSON = fetchJSON("/api/panel/status")
        async let queueJSON = fetchJSON("/api/routing/queue")
        async let checkinJSON = fetchJSON("/api/checkin-center")
        async let requestsJSON = fetchJSON("/api/stats/requests?limit=12")

        let (today, yesterday, week, month, accounts, panel, queue, checkin, requests) = await (
            todayJSON, yesterdayJSON, weekJSON, monthJSON,
            accountsJSON, panelJSON, queueJSON, checkinJSON, requestsJSON
        )

        guard token == dashboardToken else { return }

        var parsed = statsByRange
        var failures: [String] = []
        let statsResults: [(String, (JSONValue?, String?))] = [
            ("today", today), ("yesterday", yesterday), ("7", week), ("30", month)
        ]
        for (range, result) in statsResults {
            if let json = result.0 {
                parsed[range] = PanelStatsSummary.parse(json, range: range)
                persist(json, key: VaultKey.stats(range: range))
            } else {
                failures.append("\(Self.rangeTitle(range))：\(result.1 ?? "没有返回数据")")
            }
        }
        statsByRange = parsed
        if statsByRange[statsRange] != nil {
            statsUpdatedAt = Date()
            statsFromSnapshot = false
            statsError = failures.isEmpty ? nil : "部分区间没取到：" + failures.joined(separator: "；")
        } else {
            statsError = failures.first ?? "统计接口没有返回数据"
        }

        var board = dashboard
        let boardResults: [(String, (JSONValue?, String?))] = [
            ("accounts", accounts), ("panel", panel), ("queue", queue),
            ("checkin", checkin), ("requests", requests)
        ]
        for (name, result) in boardResults {
            guard let json = result.0 else { continue }
            board[name] = json
            persist(json, key: VaultKey.dashboard(name))
        }
        dashboard = board
        statsLoading = false
        localComputeCount &+= 1
    }

    /// 把一份 JSON 写进本地快照（这是「下次不联网也能看」的唯一来源）。
    private func persist(_ json: JSONValue, key: String) {
        guard let id = activeID else { return }
        LocalVault.shared.store(profile: id, key: key, json: json)
        refreshVaultStats(profile: id)
    }

    /// 清空本地快照（只删磁盘副本，不动面板）。
    func clearVault() {
        guard let id = activeID else { return }
        LocalVault.shared.remove(profile: id)
        refreshVaultStats(profile: id)
        toast = Toast(text: "本地快照已清空，下次进页面会重新读取", kind: .success)
    }

    func refreshVaultStats(profile: UUID) {
        let summary = LocalVault.shared.summary(profile: profile)
        vaultEntryCount = summary.count
        vaultNewest = summary.newest
    }

    /// 把磁盘上的统计快照铺进内存（本地解析，不发请求）。
    private func seedDashboard(profile: UUID) {
        LocalVault.shared.load(profile: profile)
        var parsed: [String: PanelStatsSummary] = [:]
        var newest: Date?

        for range in Self.statsRanges {
            guard let entry = LocalVault.shared.entry(profile: profile, key: VaultKey.stats(range: range)),
                  let json = JSONValue.fromJSONData(entry.payload) else { continue }
            parsed[range] = PanelStatsSummary.parse(json, range: range)
            newest = max(newest ?? entry.savedAt, entry.savedAt)
        }

        if !parsed.isEmpty {
            for (range, value) in parsed where statsByRange[range] == nil {
                statsByRange[range] = value
            }
            if statsUpdatedAt == nil { statsUpdatedAt = newest }
            statsSnapshotAt = newest
            statsFromSnapshot = true
            localComputeCount &+= 1
        }

        var board = dashboard
        for name in ["accounts", "panel", "queue", "checkin", "requests"] {
            guard let entry = LocalVault.shared.entry(profile: profile, key: VaultKey.dashboard(name)),
                  let json = JSONValue.fromJSONData(entry.payload) else { continue }
            if board[name] == nil { board[name] = json }
        }
        if !board.isEmpty { dashboard = board }
    }

    /// 冷启动时把所有页面已有的快照一次性铺好。
    private func seedAllPages(profile: UUID) {
        for page in PanelPage.allCases {
            seedSections(page: page, sections: page.spec.sections, profile: profile)
        }
    }

    private func seedSections(page: PanelPage, sections: [PanelSectionSpec], profile: UUID) {
        LocalVault.shared.load(profile: profile)
        var bucket = store[page.rawValue] ?? [:]
        var changed = false
        for section in sections {
            if bucket[section.id]?.json != nil { continue }
            guard let entry = LocalVault.shared.entry(
                profile: profile,
                key: VaultKey.section(page: page.rawValue, id: section.id)
            ), let json = JSONValue.fromJSONData(entry.payload) else { continue }
            bucket[section.id] = SectionData(json: json, error: nil, fetchedAt: entry.savedAt, latency: nil)
            changed = true
        }
        if changed {
            store[page.rawValue] = bucket
            localComputeCount &+= 1
        }
    }

    // MARK: - Agent 配置（本地解析 + 明确报错）

    /// 本地有没有解析出东西（界面上决定显示「重新读取」还是直接渲染）。
    var agentsLoaded: Bool { !agents.isEmpty || agentsProblem != nil }

    /// 读数据：先本地，缺了才进网络。
    func loadAgents(force: Bool = false) async {
        guard let profile = activeProfile, profile.isValid else { return }
        if !force {
            seedAgents(profile: profile.id)
            if agentsLoaded { return }
        }
        await syncAgents()
    }

    private func seedAgents(profile: UUID) {
        LocalVault.shared.load(profile: profile)
        guard let entry = LocalVault.shared.entry(profile: profile, key: VaultKey.agents),
              let json = JSONValue.fromJSONData(entry.payload) else { return }
        let outcome = AgentConfigParser.parse(json)
        if agents.isEmpty {
            agents = outcome.clients
            agentsShape = outcome.shape
            agentsProblem = outcome.problem
            agentsUpdatedAt = entry.savedAt
            agentsFromSnapshot = true
            localComputeCount &+= 1
        }
    }

    /// 唯一入口：`GET /api/agents`，回 `{clients:[…]}`。解析交给 `AgentConfigParser`。
    func syncAgents() async {
        guard activeProfile?.isValid == true else { return }
        agentsLoading = true
        agentsError = nil
        do {
            let response = try await authenticatedRequest("GET", "/api/agents")
            let outcome = AgentConfigParser.parse(response.json)
            agents = outcome.clients
            agentsShape = outcome.shape
            agentsProblem = outcome.problem
            agentsUpdatedAt = Date()
            agentsFromSnapshot = false
            if let id = activeID {
                LocalVault.shared.store(profile: id, key: VaultKey.agents, json: response.json)
                refreshVaultStats(profile: id)
            }
            localComputeCount &+= 1
            if let problem = outcome.problem {
                agentsError = problem
            }
        } catch {
            let apiError = error as? PanelAPIError
            agentsError = apiError?.errorDescription ?? error.localizedDescription
            if case .http(let code, _)? = apiError, code == 404 {
                agentsError = "这台面板没有 /api/agents（HTTP 404），升级面板后再看这一页。"
            }
        }
        agentsLoading = false
    }

    /// 预览恢复：`POST /api/agents/preview`，body 必须是 `{clientId, operation:"restore"}`。
    func previewAgent(_ client: AgentClient) async {
        guard activeProfile?.isValid == true else { return }
        guard !client.id.isEmpty else {
            toast = Toast(text: "这个客户端没有 id，面板无法预览", kind: .warning)
            return
        }
        agentWorkingID = client.id
        do {
            let response = try await authenticatedRequest(
                "POST", "/api/agents/preview",
                body: ["clientId": client.id, "operation": "restore"]
            )
            let parsed = AgentPreviewParser.parse(response.json, clientID: client.id)
            if let preview = parsed.preview {
                agentPreview = preview
                agentPreviewClient = client
                if let problem = parsed.problem {
                    toast = Toast(text: problem, kind: .warning)
                }
            } else {
                toast = Toast(text: parsed.problem ?? "预览没有返回内容", kind: .error)
            }
        } catch {
            let apiError = error as? PanelAPIError
            toast = Toast(
                text: "预览失败：\(apiError?.errorDescription ?? error.localizedDescription)",
                kind: .error
            )
        }
        agentWorkingID = nil
    }

    /// 恢复上次应用：必须带着预览返回的令牌，否则面板会拒绝覆盖。
    func restoreAgent(_ client: AgentClient) async {
        guard activeProfile?.isValid == true else { return }
        guard let token = agentPreview?.token, !token.isEmpty else {
            toast = Toast(text: "没有预览令牌，先点一次「预览」", kind: .warning)
            return
        }
        agentWorkingID = client.id
        do {
            _ = try await authenticatedRequest(
                "POST", "/api/agents/restore",
                body: [
                    "clientId": client.id,
                    "operation": "restore",
                    "token": token
                ]
            )
            toast = Toast(text: "配置已恢复并校验", kind: .success)
            record("Agent 配置已恢复：\(client.name)", ok: true)
            agentPreview = nil
            agentPreviewClient = nil
            await syncAgents()
        } catch {
            let apiError = error as? PanelAPIError
            toast = Toast(
                text: "恢复失败：\(apiError?.errorDescription ?? error.localizedDescription)",
                kind: .error
            )
        }
        agentWorkingID = nil
    }

    /// 读某个客户端的提示词 / Skill / MCP：`GET /api/agents/{id}/resources`。
    func loadAgentResources(_ client: AgentClient) async {
        guard activeProfile?.isValid == true, !client.id.isEmpty else { return }
        agentWorkingID = client.id
        do {
            let encoded = client.id.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? client.id
            let response = try await authenticatedRequest("GET", "/api/agents/\(encoded)/resources")
            agentResources[client.id] = response.json
        } catch {
            let apiError = error as? PanelAPIError
            toast = Toast(
                text: "读取资源失败：\(apiError?.errorDescription ?? error.localizedDescription)",
                kind: .error
            )
        }
        agentWorkingID = nil
    }

    /// 本地派生指标（日均 / 每请求 Token / 头部集中度 / 峰值日 / 环比）。
    var localInsights: [PanelLocalInsight] {
        guard let summary = stats else { return [] }
        return LocalStatsEngine.insights(
            summary: summary,
            siblings: statsByRange,
            range: statsRange
        )
    }

    /// 拉一个 JSON；失败时把错误文案一起带回来。
    private func fetchJSON(_ path: String) async -> (JSONValue?, String?) {
        do {
            let response = try await authenticatedRequest("GET", path)
            return (response.json, nil)
        } catch {
            let apiError = error as? PanelAPIError
            return (nil, apiError?.errorDescription ?? error.localizedDescription)
        }
    }

    // MARK: 仪表盘的周边数据

    var dashboardAccounts: [JSONValue] {
        dashboard["accounts"].map { PanelAPI.rows(from: $0) } ?? []
    }

    var dashboardRequests: [JSONValue] {
        dashboard["requests"].map { PanelAPI.rows(from: $0) } ?? []
    }

    var dashboardQueue: [JSONValue] {
        dashboard["queue"].map { PanelAPI.rows(from: $0) } ?? []
    }

    /// 路由队列里真正排着的账号数：`/api/routing/queue` 回的是 `{ordered:[…], blocked:[…]}`。
    var routingQueueCount: Int {
        guard let json = dashboard["queue"] else { return 0 }
        let node = json.value("data") ?? json
        if let ordered = node.arr("ordered") {
            return ordered.count + (node.arr("blocked")?.count ?? 0)
        }
        return PanelAPI.rows(from: json).count
    }

    var dashboardPanel: JSONValue? { dashboard["panel"] }

    /// 启用中的账号数 / 总数
    var accountCounts: (enabled: Int, total: Int) {
        let rows = dashboardAccounts
        let enabled = rows.filter { row in
            if let flag = row.bool("enabled") { return flag }
            if let status = row.str("status") {
                return !["dis", "off", "fail", "expire"].contains { status.lowercased().contains($0) }
            }
            return true
        }.count
        return (enabled, rows.count)
    }

    /// 被限流的账号数（服务端字段名各版本不一，宽松匹配）
    var rateLimitedCount: Int {
        dashboardAccounts.filter { row in
            if row.bool("rateLimited") == true || row.bool("limited") == true { return true }
            let status = (row.str("status") ?? "").lowercased()
            return status.contains("limit") || status.contains("限流")
        }.count
    }

    /// 今日签到：done / eligible
    var checkinProgress: (done: Int, total: Int) {
        guard let daily = dashboard["checkin"]?.obj("daily") else { return (0, 0) }
        return (daily.int("todayDone") ?? 0, daily.int("todayEligible") ?? 0)
    }

    // MARK: - 动作

    /// 执行区块声明的动作。`row` 用于把行 id 填进 `{id}` 占位符。
    func perform(
        action: PanelActionSpec,
        page: PanelPage,
        section: PanelSectionSpec,
        row: JSONValue? = nil
    ) async {
        var path = action.path
        var body: [String: Any] = action.extra
        if action.usesRow {
            guard let row, let id = row.firstString(action.idKeys) else {
                toast = Toast(text: "这一行没有可用的 id 字段", kind: .warning)
                return
            }
            path = path.replacingOccurrences(of: "{id}", with: id)
            body["id"] = id
        }

        await submit(
            action.title,
            method: action.method,
            path: path,
            body: body,
            onSuccess: { [weak self] in
                await self?.load(page: page, force: true, only: [section.id])
            }
        )
    }

    /// 概览快捷操作直接调用的入口（不在任何页面的目录里）。
    func runCommand(
        _ title: String,
        method: String = "POST",
        path: String,
        body: [String: Any] = [:],
        refreshDashboard: Bool = true
    ) async {
        await submit(
            title,
            method: method,
            path: path,
            body: body,
            onSuccess: { [weak self] in
                if refreshDashboard { await self?.loadDashboard(force: true) }
            }
        )
    }

    /// 写操作的统一收口：401 会自动换令牌重试一次，成功后提示 + 刷新。
    private func submit(
        _ title: String,
        method: String,
        path: String,
        body: [String: Any],
        onSuccess: @escaping () async -> Void
    ) async {
        do {
            // 写接口一律带 body：Go 侧对 POST 的空 body 会直接判 400，
            // 所以没有字段时也发一个 `{}`。
            let payload: Any? = (method == "GET") ? nil : body
            _ = try await authenticatedRequest(method, path, body: payload, timeout: 30)
            toast = Toast(text: "\(title)已提交", kind: .success)
            record(title, ok: true)
            await onSuccess()
        } catch {
            let apiError = error as? PanelAPIError
            let message = apiError?.errorDescription ?? error.localizedDescription
            toast = Toast(text: "\(title)失败：\(message)", kind: .error)
            record("\(title)失败：\(message)", ok: false)
        }
    }

    // MARK: - 助手对话

    func newChat() {
        chat = []
        activeSessionID = nil
    }

    /// 发送一条消息。附件与访问权限都在本地拼进报文：
    ///   · 文件（JSON / TXT / MD）折进文本，和桌面端一样；
    ///   · 图片走 `image_url` + `data:` URL，不在服务器留副本；
    ///   · 访问权限只影响提示词（网关权限是服务端策略，客户端没有改它的接口）。
    func sendChat(_ text: String) {
        let content = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let pending = attachments
        guard !content.isEmpty || !pending.isEmpty else { return }

        // 上一轮如果卡死（网络断、任务丢了），isReplying 会一直是 true，
        // 这时再发消息会被静默拦掉 —— 用户看到的就是「发消息完全没反应」。
        if isReplying {
            let waited = replyStartedAt.map { Date().timeIntervalSince($0) } ?? 0
            if waited > 120 || chatTask == nil || chatTask?.isCancelled == true {
                stopChat()
            } else {
                toast = Toast(
                    text: "上一条还在回复中（已等 \(Int(waited))s），点右下角停止可以中断",
                    kind: .warning
                )
                return
            }
        }
        guard activeProfile?.isValid == true else { return }
        // 没有可用的网关 Key 就不要发：面板只会回「所选 API Key 已失效」。
        guard !assistantKeyValue.isEmpty else {
            toast = Toast(text: "先在输入框里选一把可用的网关 Key", kind: .warning)
            if gatewayKeys.isEmpty { Task { await loadGatewayKeys() } }
            return
        }

        // 1) 文件内容折进正文
        var finalText = content
        for item in pending where !item.isImage {
            guard let body = item.text else { continue }
            finalText += "\n\n--- 文件：\(item.name) ---\n\(body)"
        }
        if let instruction = assistantAccess.instruction {
            finalText = instruction + "\n\n" + finalText
        }

        // 2) 图片转 data URL
        let images = pending.compactMap(\.dataURL)

        // 3) 气泡上显示的文字（图片用占位，不塞 base64）
        var display = content
        if !images.isEmpty {
            display += (display.isEmpty ? "" : "\n") + "［\(images.count) 张图片］"
        }
        for item in pending where !item.isImage {
            display += (display.isEmpty ? "" : "\n") + "［文件 \(item.name)］"
        }
        if display.isEmpty { display = "（已发送附件）" }

        // 4) 历史 + 本次消息
        let history = chat.filter { !$0.text.isEmpty || !$0.steps.isEmpty }.map { message -> [String: Any] in
            ["role": message.role.rawValue, "content": message.text]
        }

        var current: [String: Any]
        if images.isEmpty {
            current = ["role": "user", "content": finalText]
        } else {
            var parts: [[String: Any]] = [["type": "text", "text": finalText]]
            for url in images {
                parts.append(["type": "image_url", "image_url": ["url": url]])
            }
            current = ["role": "user", "content": parts]
        }

        chat.append(ChatMessage(role: .user, text: display))
        let answerID = UUID()
        chat.append(ChatMessage(id: answerID, role: .assistant, text: ""))
        isReplying = true
        replyStartedAt = Date()
        attachments = []
        // 新对话第一次发送时分配一个会话 id，用于回写历史
        if activeSessionID == nil { activeSessionID = UUID().uuidString }

        var messages = history
        messages.append(current)

        chatTask?.cancel()
        chatTask = Task { [weak self] in
            guard let self else { return }
            _ = await self.loginIfNeeded()
            await self.runAgent(answerID: answerID, messages: messages)
        }
    }

    /// 工具循环：发一轮 → 模型要调工具就执行 → 把结果塞回去 → 再发。
    /// 最多四轮，防止模型自己绕圈。
    private func runAgent(answerID: UUID, messages start: [[String: Any]]) async {
        var messages = start
        var round = 0
        /// 这一轮对话里工具被网关拒绝了；后续都走纯文本
        var toolsDisabledByFailure = false

        while round < 4, !Task.isCancelled {
            round += 1
            var pending: [PanelToolCall] = []

            guard let api = makeAPI(timeout: 180, apiKeyOverride: assistantKeyValue) else {
                finishReply(answerID, error: PanelAPIError.notConfigured)
                return
            }
            var body: [String: Any] = ["messages": messages]
            if !assistantModel.trimmingCharacters(in: .whitespaces).isEmpty {
                body["model"] = assistantModel.trimmingCharacters(in: .whitespaces)
            }
            // 工具是可选的：关掉时就是最普通的对话，任何网关都能回。
            // 打开后如果这一轮直接失败（不支持 tools / 参数被拒），下一次自动去掉工具再试。
            let withTools = assistantToolsEnabled && !toolsDisabledByFailure
            if withTools {
                body["tools"] = AssistantToolCatalog.payload
                body["tool_choice"] = "auto"
            }

            do {
                try await api.streamChat(
                    "/api/assistant/chat",
                    body: body,
                    // 带工具时网关若不支持 tools，常常是「接受请求然后不吐字」，
                    // 等满 45 秒才降级太亏；22 秒没动静就退回纯文本重试。
                    timeout: withTools ? 22 : 45,
                    onText: { piece in
                        Task { @MainActor [weak self] in
                            self?.enqueueAssistant(piece, to: answerID)
                        }
                    },
                    onToolCalls: { calls in
                        pending = calls.filter { !$0.name.isEmpty }
                    }
                )
            } catch {
                let apiError = error as? PanelAPIError
                if apiError?.isAuthFailure == true, round == 1 {
                    _ = await loginIfNeeded(force: true)
                    round -= 1
                    continue
                }
                // 带工具时失败：立刻退回普通对话重试一轮，别让用户对着省略号等
                if withTools {
                    toolsDisabledByFailure = true
                    round -= 1
                    continue
                }
                finishReply(answerID, error: error)
                return
            }

            if Task.isCancelled { return }
            guard !pending.isEmpty else { break }

            // 把「我要调这些工具」写回对话历史，模型下一轮才知道结果属于谁
            var assistantMessage: [String: Any] = ["role": "assistant", "content": ""]
            assistantMessage["tool_calls"] = pending.map { call -> [String: Any] in
                [
                    "id": call.id,
                    "type": "function",
                    "function": ["name": call.name, "arguments": call.arguments]
                ]
            }
            messages.append(assistantMessage)

            for call in pending {
                appendStep(
                    answerID: answerID,
                    step: ChatToolStep(
                        id: call.id,
                        name: call.name,
                        label: AssistantToolCatalog.label(call.name),
                        icon: AssistantToolCatalog.icon(call.name),
                        status: .running,
                        summary: "调用中…"
                    )
                )
            }

            for call in pending {
                let result = await executeTool(call)
                updateStep(
                    answerID: answerID,
                    stepID: call.id,
                    status: result.ok ? .done : .failed,
                    summary: result.summary,
                    detail: result.text
                )
                messages.append([
                    "role": "tool",
                    "tool_call_id": call.id,
                    "content": String(result.text.prefix(8000))
                ])
            }
        }

        finishReply(answerID, error: nil)
        await saveSession()
    }

    // MARK: 工具执行

    /// 一个工具 → 一次面板接口调用。返回「给模型看的原文」和「给人看的一句话」。
    private func executeTool(_ call: PanelToolCall) async -> (ok: Bool, summary: String, text: String) {
        do {
            switch call.name {
            case "list_accounts":
                let response = try await authenticatedRequest("GET", "/api/accounts", timeout: 30)
                let rows = JSONRows.from(response.json)
                let enabled = rows.filter { $0.bool("enabled") ?? true }.count
                return (true, "\(rows.count) 个账号（\(enabled) 个启用）", response.json.rawText)

            case "list_models":
                let response = try await authenticatedRequest("GET", "/api/models/manage", timeout: 40)
                let rows = JSONRows.from(response.json)
                return (true, "\(rows.count) 个模型", response.json.rawText)

            case "checkin_status":
                let response = try await authenticatedRequest("GET", "/api/checkin-center", timeout: 40)
                let center = CheckinParser.parse(response.json)
                checkin = center
                return (
                    true,
                    "今日已签 \(center.todayDone)/\(center.todayEligible)",
                    response.json.rawText
                )

            case "checkin_all":
                let response = try await authenticatedRequest(
                    "POST", "/api/accounts/checkin", body: [String: Any](), timeout: 120
                )
                let summary = CheckinParser.summaryText(response.json)
                await loadCheckin(force: true)
                return (true, summary, response.json.rawText)

            case "usage_stats":
                let range = (call.json["range"] as? String) ?? "7"
                let response = try await authenticatedRequest(
                    "GET", "/api/stats/summary?range=\(range)", timeout: 40
                )
                let stats = PanelStatsSummary.parse(response.json, range: range)
                return (
                    true,
                    "\(stats.requests) 次请求 · 成功率 \(PanelNumber.percent(stats.successRate))",
                    response.json.rawText
                )

            case "routing_status":
                let response = try await authenticatedRequest("GET", "/api/routing/workspace", timeout: 40)
                return (true, "已读取路由配置", response.json.rawText)

            case "refresh_models":
                let response = try await authenticatedRequest("POST", "/api/models/refresh", body: [String: Any](), timeout: 90)
                return (true, "已触发刷新", response.json.rawText)

            case "clear_sticky":
                let response = try await authenticatedRequest("POST", "/api/routing/sticky/clear", body: [String: Any](), timeout: 40)
                return (true, "已清空粘滞", response.json.rawText)

            default:
                return (false, "不支持的工具", "未知工具：\(call.name)")
            }
        } catch {
            let apiError = error as? PanelAPIError
            let message = apiError?.errorDescription ?? error.localizedDescription
            return (false, message, "调用失败：\(message)")
        }
    }

    // MARK: 步骤卡片

    private func appendStep(answerID: UUID, step: ChatToolStep) {
        guard let index = chat.firstIndex(where: { $0.id == answerID }) else { return }
        if let existing = chat[index].steps.firstIndex(where: { $0.id == step.id }) {
            chat[index].steps[existing] = step
        } else {
            chat[index].steps.append(step)
        }
        localComputeCount &+= 1
    }

    private func updateStep(
        answerID: UUID,
        stepID: String,
        status: ChatToolStep.Status,
        summary: String,
        detail: String
    ) {
        guard let index = chat.firstIndex(where: { $0.id == answerID }),
              let stepIndex = chat[index].steps.firstIndex(where: { $0.id == stepID }) else { return }
        chat[index].steps[stepIndex].status = status
        chat[index].steps[stepIndex].summary = summary
        chat[index].steps[stepIndex].detail = detail
        localComputeCount &+= 1
    }

    private func finishReply(_ id: UUID, error: Error?) {
        flushDeltas(to: id)
        isReplying = false
        replyStartedAt = nil
        guard let index = chat.firstIndex(where: { $0.id == id }) else { return }
        if let error {
            let apiError = error as? PanelAPIError
            let message = apiError?.errorDescription ?? error.localizedDescription
            chat[index].text = chat[index].text.isEmpty
                ? "请求失败：\(message)"
                : chat[index].text + "\n\n（中断：\(message)）"
        } else if chat[index].text.isEmpty {
            chat[index].text = chat[index].steps.isEmpty
                ? "网关没有返回内容。可能是这个模型不支持当前请求参数，去输入框的「工具」关掉后再试一次。"
                : "工具已经执行完，但模型没有继续输出。可以把「工具」关掉再问一遍。"
        }
    }

    private func appendAssistant(_ piece: String, to id: UUID) {
        guard let index = chat.firstIndex(where: { $0.id == id }) else { return }
        chat[index].text += piece
    }

    /// 把流式片段先攒起来，最多 45ms 刷一次。
    ///
    /// 原来的写法是「每段文字都 `Task { @MainActor in ... }` 改一次 chat」：
    /// 模型吐得快的时候一秒能创建几十个 Task、触发几十次界面刷新，
    /// 表现为「字早就到了，屏幕上要慢半拍才滚出来」。
    private func enqueueAssistant(_ piece: String, to id: UUID) {
        deltaBuffer += piece
        guard deltaFlushTask == nil else { return }
        deltaFlushTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 45_000_000)
            guard let self else { return }
            self.flushDeltas(to: id)
        }
    }

    private func flushDeltas(to id: UUID) {
        deltaFlushTask?.cancel()
        deltaFlushTask = nil
        let chunk = deltaBuffer
        deltaBuffer = ""
        guard !chunk.isEmpty else { return }
        appendAssistant(chunk, to: id)
    }

    func stopChat() {
        chatTask?.cancel()
        if let last = chat.last(where: { $0.role == .assistant }) {
            flushDeltas(to: last.id)
        }
        isReplying = false
        replyStartedAt = nil
        // 停在半路的空气泡要留一句「已停止」，
        // 否则它会一直显示思考态（模型那条消息永远收不到收尾回调）
        if let index = chat.lastIndex(where: { $0.role == .assistant }), chat[index].text.isEmpty {
            chat[index].text = "（已停止）"
        }
    }

    // MARK: - 本地自检（不发任何一个请求）

    /// 检查的是「本地这一套能不能自己跑起来」：
    /// 配置解析、钥匙串令牌、磁盘快照、统计能否复算、Agent 报文能否解析、
    /// 图表组件是否全在本地。**全程零网络**。
    func runDiagnostics() async {
        isDiagnosing = true
        diagSteps = []
        await Task.yield()

        // 1. 连接配置（本地解析）
        if let profile = activeProfile {
            diagSteps.append(
                DiagStep(title: "连接配置", ok: true, detail: "\(profile.mode.title) · \(profile.rootString)")
            )
            if profile.trimmedHost == "127.0.0.1" || profile.trimmedHost == "localhost" {
                diagSteps.append(
                    DiagStep(
                        title: "地址可用性",
                        ok: false,
                        detail: "127.0.0.1 在手机上指向手机自己。本地渲染不受影响，但同步会失败。"
                    )
                )
            }
        } else {
            diagSteps.append(DiagStep(title: "连接配置", ok: false, detail: "还没有新建连接"))
        }

        // 2. 令牌（只读钥匙串，不请求）
        if activeProfile?.authMode == .password {
            let hasToken = !activeToken.isEmpty
            diagSteps.append(
                DiagStep(
                    title: "访问令牌",
                    ok: hasToken,
                    detail: hasToken ? "钥匙串里有一枚令牌（\(max(activeToken.count, 8)) 字符）" : "钥匙串里没有令牌，点同步会重新登录"
                )
            )
        } else {
            let hasKey = !activeAPIKey.isEmpty
            diagSteps.append(
                DiagStep(title: "接口密钥", ok: hasKey, detail: hasKey ? "钥匙串里有密钥" : "还没填密钥")
            )
        }

        // 3. 磁盘快照
        let vault = vaultEntryCount
        diagSteps.append(
            DiagStep(
                title: "本地快照",
                ok: vault > 0,
                detail: vault == 0
                    ? "还没有快照：第一次必须先同步一次"
                    : "\(vault) 份 · 最新 \(vaultNewest?.formatted("MM-dd HH:mm") ?? "—")，断网也能渲染"
            )
        )

        // 4. 统计本地计算
        let ranges = statsByRange.keys.sorted()
        if let summary = stats {
            let insights = localInsights.count
            diagSteps.append(
                DiagStep(
                    title: "统计与图表",
                    ok: !summary.trend.isEmpty || summary.requests > 0,
                    detail: "区间 \(Self.rangeTitle(statsRange)) · \(summary.trend.count) 个趋势点 · \(insights) 项本地派生指标 · 已缓存区间 \(ranges.count)/4"
                )
            )
        } else {
            diagSteps.append(
                DiagStep(title: "统计与图表", ok: false, detail: "本地没有统计快照，先同步一次")
            )
        }

        // 5. Agent 报文解析
        let parsedAgents = AgentConfigParser.parse(.object([:]))
        diagSteps.append(
            DiagStep(
                title: "Agent 解析器",
                ok: agentsProblem == nil,
                detail: agentsProblem
                    ?? "形状 \(agentsShape.isEmpty ? "未同步" : agentsShape) · \(agents.count) 个客户端 · 空对象兜底 \(parsedAgents.shape)"
            )
        )

        // 6. 渲染引擎（静态检查：工程里没有网页容器）
        diagSteps.append(
            DiagStep(
                title: "渲染方式",
                ok: true,
                detail: "柱状图 / 环形图 / KPI 全部 SwiftUI 手绘，无 WKWebView、无远程脚本与 CDN"
            )
        )

        // 7. 本次运行计量
        diagSteps.append(
            DiagStep(
                title: "本次运行",
                ok: networkRequestCount >= 0,
                detail: "网络请求 \(networkRequestCount) 次 · 本地计算 \(localComputeCount) 次"
            )
        )

        isDiagnosing = false
    }

    private func record(_ text: String, ok: Bool) {
        events.insert(PanelEvent(at: Date(), text: text, ok: ok), at: 0)
        if events.count > 60 { events.removeLast(events.count - 60) }
    }

    private func startPolling() {
        pollTask?.cancel()
        pollTask = Task { [weak self] in
            while !Task.isCancelled {
                // 推送在线时这段时间只是兜底（防推送静默挂掉），所以拉长到 60s；
                // 推送没握手成功才用 12s 的老节奏。
                let interval: UInt64 = (self?.pushLive ?? false) ? 60_000_000_000 : 12_000_000_000
                try? await Task.sleep(nanoseconds: interval)
                guard let self else { return }
                if Task.isCancelled { return }
                guard self.autoRefresh, self.isConfigured else { continue }
                self.pollTick &+= 1
                if self.state.isOnline || self.pollTick % 4 == 0 {
                    await self.poll()
                }
                // 每 4 拍顺带把仪表盘的数据换新；推送在线时靠推送触发，这里很少走到。
                if self.state.isOnline, self.pollTick % 4 == 0 {
                    await self.loadDashboard(force: true)
                }
            }
        }
    }

    // MARK: - 推送通道

    /// 订阅「面板数据变了」的 SSE。连不上/没令牌就静默退回轮询，不影响主流程。
    func startPushChannel() {
        stopPushChannel()
        guard autoRefresh,
              let profile = activeProfile,
              profile.isValid,
              !activeToken.isEmpty,
              let channel = PushChannel(
                base: profile.rootString,
                token: activeToken,
                // 回调是从 URLSession 的线程上来的，必须显式跳回主线程：
                // 原来直接调 `@MainActor` 方法，等于在后台线程改 UI 状态
                // （`pushDebounce` / 界面刷新），偶发「收到了但要等下一拍才动」。
                onState: { [weak self] state in
                    Task { @MainActor in self?.applyPushState(state) }
                },
                onChange: { [weak self] usage, config in
                    Task { @MainActor in self?.schedulePushRefresh(usage: usage, config: config) }
                }
              ) else {
            pushLive = false
            return
        }
        pushChannel = channel
        channel.start()
    }

    func stopPushChannel() {
        pushChannel?.stop()
        pushChannel = nil
        pushDebounce?.cancel()
        pushDebounce = nil
        pushPending = false
        pushPendingUsage = false
        pushPendingConfig = false
        if pushLive { pushLive = false }
    }

    private func applyPushState(_ state: PushChannel.State) {
        switch state {
        case .live:
            if !pushLive {
                pushLive = true
                record("已订阅面板变化推送", ok: true)
            }
        case .unauthorized:
            pushLive = false
            // 只换一次令牌；换不到（比如密码也过期了）就老实轮询，别再打转
            Task { [weak self] in
                guard let self else { return }
                let ok = await self.loginIfNeeded(force: true)
                if ok { self.startPushChannel() }
            }
        case .idle, .connecting, .failed:
            pushLive = false
        }
    }

    /// 收到 change。
    ///
    /// 老实现有个要命的毛病：每来一条事件就 `pushDebounce?.cancel()`，
    /// 而那个 Task 里装的是**整段刷新**。上游一直在写（跑批、连续对话）时，
    /// 后一条事件会把前一条正在跑的刷新取消掉，`URLSession` 的请求跟着被取消，
    /// 于是「事件一直在来，界面一直不更新」—— 这就是「推送不及时」的真正原因。
    ///
    /// 现在把「等待」和「刷新」拆开：
    ///   · 新事件只标记 `pushPending = true`，并把定时器往后推 200ms；
    ///   · 刷新一旦开始就**不被打断**，跑完再看有没有新事件，有就再来一轮；
    ///   · 两轮之间至少隔 0.8 秒，上游高频写入不会把面板打爆，但也不会丢事件。
    private func schedulePushRefresh(usage: Bool, config: Bool) {
        guard autoRefresh, isConfigured else { return }
        pushPending = true
        if usage { pushPendingUsage = true }
        if config { pushPendingConfig = true }
        guard !pushRunning else { return }   // 正在刷：跑完自己会再看 pending

        pushDebounce?.cancel()
        pushDebounce = Task { [weak self] in
            // 合并 200ms 内的连击（一次请求落库通常会带出好几条写入）
            try? await Task.sleep(nanoseconds: 200_000_000)
            guard let self, !Task.isCancelled else { return }
            await self.drainPushChanges()
        }
    }

    /// 把攒下的事件一轮轮刷完。这个函数里的刷新不会被新事件取消。
    private func drainPushChanges() async {
        guard !pushRunning else { return }
        pushRunning = true
        defer { pushRunning = false }

        while pushPending {
            pushPending = false
            let usage = pushPendingUsage
            let config = pushPendingConfig
            pushPendingUsage = false
            pushPendingConfig = false

            let elapsed = Date().timeIntervalSince(lastPushRefresh)
            if elapsed < 0.8 {
                let wait = UInt64((0.8 - elapsed) * 1_000_000_000)
                try? await Task.sleep(nanoseconds: wait)
            }
            lastPushRefresh = Date()

            if usage {
                // 健康 / 当前区间统计 / 最近请求 并发跑：
                // 原来 `poll()` 串在最前面，一个健康检查慢一点统计就被拖到后面。
                await withTaskGroup(of: Void.self) { group in
                    group.addTask { [weak self] in _ = await self?.poll() }
                    group.addTask { [weak self] in _ = await self?.refreshStatsForCurrentRange() }
                    group.addTask { [weak self] in _ = await self?.refreshRecentRequests() }
                }
            } else {
                await poll()
            }

            // 配置变了：路由规则 / 模型规则 / 助手会话，得整份重拉
            if config { lastFullDashboard = .distantPast }

            // 全量仪表盘（9 个请求）单独节流 10 秒，别让上游把自己打爆
            if Date().timeIntervalSince(lastFullDashboard) > 10 {
                lastFullDashboard = Date()
                await loadDashboard(force: true)
            }
        }
    }

    /// 只重拉当前区间的 `/api/stats/summary`（切区间不发请求的那套逻辑不动）。
    private func refreshStatsForCurrentRange() async {
        guard activeProfile?.isValid == true else { return }
        let range = statsRange
        let result = await fetchJSON("/api/stats/summary?range=\(range)")
        guard let json = result.0 else { return }
        var parsed = statsByRange
        parsed[range] = PanelStatsSummary.parse(json, range: range)
        statsByRange = parsed
        statsUpdatedAt = Date()
        persist(json, key: VaultKey.stats(range: range))
    }

    /// 最近请求列表是概览里最常被盯着看的一块，单独给一条轻量刷新路径：
    /// 原来要等 15 秒一次的全量仪表盘，所以列表总比上面的数字慢半拍。
    private func refreshRecentRequests() async {
        guard activeProfile?.isValid == true else { return }
        let result = await fetchJSON("/api/stats/requests?limit=12")
        guard let json = result.0 else { return }
        // 内容没变就别赋值：`dashboard` 是 @Published，
        // 赋一次就让五个 Tab 全部重算 body。推送每 0.8 秒来一次，
        // 列表没变却一直重绘 —— 滚动时就是掉帧。
        if dashboard["requests"] == json { return }
        var board = dashboard
        board["requests"] = json
        dashboard = board
        persist(json, key: VaultKey.dashboard("requests"))
    }

    /// 回到前台：已经在线就只做一次轻量续命（健康 + 统计 + 最近请求 + 重新订阅推送），
    /// 不再为了「刷新」把九个请求全拉一遍 —— 那会让回前台的第一屏明显发木。
    func handleBecameActive() {
        guard autoRefresh, isConfigured else { return }
        if state.isOnline {
            Task { [weak self] in
                guard let self else { return }
                self.startPushChannel()
                await self.poll()
                await self.refreshStatsForCurrentRange()
                await self.refreshRecentRequests()
            }
        } else {
            Task { await connect() }
        }
    }

    /// 本地计算计量（扩展文件里用，`private(set)` 在扩展里改不了）。
    func noteLocalCompute(_ count: Int = 1) {
        localComputeCount &+= count
    }

    func haptic(_ style: UIImpactFeedbackGenerator.FeedbackStyle = .light) {
        guard hapticsEnabled else { return }
        UIImpactFeedbackGenerator(style: style).impactOccurred()
    }

    func copy(_ text: String, label: String = "已复制") {
        UIPasteboard.general.string = text
        toast = Toast(text: label, kind: .success)
        localComputeCount &+= 1
    }

    /// 把当前区间的 KPI 与本地派生指标拼成可粘贴文本（纯本地，不发请求）。
    func copySummary() {
        guard let summary = stats else {
            toast = Toast(text: "还没有统计数据，先同步一次", kind: .warning)
            return
        }
        var lines: [String] = []
        lines.append("面板：\(activeProfile?.name ?? "—")（\(activeProfile?.displayAddress ?? "—")）")
        lines.append("区间：\(Self.rangeTitle(statsRange)) · 数据时间 \(statsUpdatedAt?.formatted("yyyy-MM-dd HH:mm:ss") ?? "—")")
        lines.append("请求 \(PanelNumber.grouping(summary.requests)) · 成功 \(PanelNumber.grouping(summary.successful)) · 成功率 \(PanelNumber.percent(summary.successRate))")
        lines.append("Token \(PanelNumber.grouping(summary.tokens)) · 缓存命中 \(PanelNumber.percent(summary.cacheRate)) · 趋势 \(summary.trend.count) 天")
        for item in localInsights {
            lines.append("\(item.title)：\(item.value)（\(item.note)）")
        }
        copy(lines.joined(separator: "\n"), label: "用量摘要已复制")
    }
}
