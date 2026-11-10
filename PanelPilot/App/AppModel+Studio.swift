import Foundation
import UIKit

// === AppModel 的业务扩展 ===
//
// 路由 / 账号 / 助手 / 偏好这四块放在这里，`AppModel.swift` 只保留状态与连接骨架。
// 所有网络出口仍然是 `authenticatedRequest`，所以计量、401 续期、错误文案都一致。

// MARK: - 路由

extension AppModel {

    var routingDirty: Bool { routingDraft.isDirty(against: routing) }

    /// 读工作区：不传 model 就是全局默认。
    func loadRouting(model: String? = nil, silent: Bool = false) async {
        if let model { routingModel = model }
        guard !routingLoading else { return }
        routingLoading = true
        if !silent { routingError = nil }

        var path = "/api/routing/workspace"
        if !routingModel.isEmpty {
            let encoded = routingModel.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? routingModel
            path += "?model=\(encoded)"
        }

        do {
            let response = try await authenticatedRequest("GET", path, timeout: 20)
            let workspace = RoutingWorkspace.parse(response.json, requestedModel: routingModel)
            routing = workspace
            routingDraft = RoutingDraft(workspace: workspace)
            if !workspace.models.isEmpty { routingModels = workspace.models }
            routingUpdatedAt = Date()
            routingError = nil
            noteLocalCompute()
        } catch {
            let apiError = error as? PanelAPIError
            routingError = apiError?.errorDescription ?? error.localizedDescription
        }
        routingLoading = false
    }

    /// 切换正在配置的模型（空字符串 = 全局默认）。
    func selectRoutingModel(_ model: String) async {
        guard routingModel != model else { return }
        routingModel = model
        routing = .empty
        routingDraft = RoutingDraft(workspace: .empty)
        await loadRouting()
    }

    func updateRoutingDraft(_ mutate: (inout RoutingDraft) -> Void) {
        var draft = routingDraft
        mutate(&draft)
        routingDraft = draft
        noteLocalCompute()
    }

    func discardRouting() {
        routingDraft = RoutingDraft(workspace: routing)
    }

    /// 保存：把读到的 profile 原样带回，只覆盖改动项。
    func saveRouting() async {
        guard !routingSaving else { return }
        routingSaving = true
        routingError = nil
        do {
            let body = routingDraft.payload(workspace: routing)
            _ = try await authenticatedRequest("PUT", "/api/routing/profile", body: body, timeout: 25)
            toast = Toast(text: "路由已保存", kind: .success)
            haptic(.medium)
            await loadRouting()
        } catch {
            let apiError = error as? PanelAPIError
            let message = apiError?.errorDescription ?? error.localizedDescription
            routingError = message
            toast = Toast(text: "保存失败：\(message)", kind: .error)
        }
        routingSaving = false
    }

    /// 把一个提供商移出 / 加入本路由（只改草稿，保存才生效）。
    func toggleRoutingProvider(_ id: String, included: Bool) {
        updateRoutingDraft { draft in
            if included {
                draft.disabledProviders.remove(id)
            } else {
                draft.disabledProviders.insert(id)
            }
        }
    }

    /// 账号启停：`POST /api/accounts/batch {action, ids}`，立即生效。
    func setAccountEnabled(_ account: AccountItem, enabled: Bool) async {
        await setAccountEnabled(id: account.id, name: account.name, enabled: enabled)
    }

    /// 路由页的账号行用的是 `RoutingAccountRef`，逻辑同上。
    func setAccountEnabled(_ account: RoutingAccountRef, enabled: Bool) async {
        await setAccountEnabled(id: account.id, name: account.name, enabled: enabled)
    }

    func setAccountEnabled(id: String, name: String, enabled: Bool) async {
        do {
            _ = try await authenticatedRequest(
                "POST", "/api/accounts/batch",
                body: ["action": enabled ? "enable" : "disable", "ids": [id]],
                timeout: 25
            )
            toast = Toast(text: enabled ? "已启用「\(name)」" : "已停用「\(name)」", kind: .success)
            haptic()
            await loadAccounts()
        } catch {
            let apiError = error as? PanelAPIError
            toast = Toast(
                text: "切换失败：\(apiError?.errorDescription ?? error.localizedDescription)",
                kind: .error
            )
        }
    }
}

// MARK: - 账号

extension AppModel {

    /// 读账号并本地按提供商分组。
    func loadAccounts(force: Bool = false) async {
        guard activeProfile?.isValid == true else { return }
        if accountsLoading { return }
        accountsLoading = true
        accountsError = nil
        do {
            let response = try await authenticatedRequest("GET", "/api/accounts", timeout: 20)
            let items = AccountsParser.items(response.json)
            providers = AccountsParser.group(items)
            currentAccountID = items.first(where: { $0.isCurrent })?.id ?? currentAccountID
            accountsUpdatedAt = Date()
            noteLocalCompute(items.count)
        } catch {
            let apiError = error as? PanelAPIError
            accountsError = apiError?.errorDescription ?? error.localizedDescription
        }
        accountsLoading = false
    }

    var allAccounts: [AccountItem] { providers.flatMap(\.accounts) }

    func account(with id: String) -> AccountItem? {
        allAccounts.first { $0.id == id }
    }

    /// 添加账号：面板侧若没有开放新增接口，会把服务端原话显示出来，而不是假装成功。
    func addAccount(provider: String, name: String, apiKey: String) async -> Bool {
        let provider = provider.trimmingCharacters(in: .whitespaces)
        let name = name.trimmingCharacters(in: .whitespaces)
        guard !provider.isEmpty else {
            toast = Toast(text: "先选一个提供商", kind: .warning)
            return false
        }
        var body: [String: Any] = ["provider": provider]
        if !name.isEmpty { body["name"] = name }
        if !apiKey.isEmpty { body["apiKey"] = apiKey }

        do {
            _ = try await authenticatedRequest("POST", "/api/accounts", body: body, timeout: 30)
            toast = Toast(text: "已添加账号", kind: .success)
            haptic(.medium)
            await loadAccounts(force: true)
            return true
        } catch {
            let apiError = error as? PanelAPIError
            toast = Toast(
                text: "添加失败：\(apiError?.errorDescription ?? error.localizedDescription)",
                kind: .error
            )
            return false
        }
    }

    /// 查询余额：`GET /api/accounts/usage`
    func queryBalances() async {
        guard activeProfile?.isValid == true else { return }
        balancesLoading = true
        do {
            let response = try await authenticatedRequest("GET", "/api/accounts/usage", timeout: 40)
            balances = response.json
            noteLocalCompute()
            toast = Toast(text: "余额已更新", kind: .success)
            await loadAccounts()
        } catch {
            let apiError = error as? PanelAPIError
            toast = Toast(
                text: "查询余额失败：\(apiError?.errorDescription ?? error.localizedDescription)",
                kind: .error
            )
        }
        balancesLoading = false
    }

    /// 全部账号签到：`POST /api/accounts/checkin`
    func checkinAllAccounts() async {
        do {
            _ = try await authenticatedRequest("POST", "/api/accounts/checkin", body: [String: Any](), timeout: 60)
            toast = Toast(text: "已提交签到", kind: .success)
            haptic(.medium)
            await loadAccounts()
        } catch {
            let apiError = error as? PanelAPIError
            toast = Toast(
                text: "签到失败：\(apiError?.errorDescription ?? error.localizedDescription)",
                kind: .error
            )
        }
    }

    func setCurrentAccount(_ id: String) async {
        do {
            _ = try await authenticatedRequest("POST", "/api/accounts/current", body: ["id": id], timeout: 30)
            toast = Toast(text: "已切换当前账号", kind: .success)
            haptic(.medium)
            await loadAccounts()
        } catch {
            let apiError = error as? PanelAPIError
            toast = Toast(
                text: "切换失败：\(apiError?.errorDescription ?? error.localizedDescription)",
                kind: .error
            )
        }
    }

    /// 单个账号签到：`POST /api/accounts/checkin {id}`
    func checkinAccount(_ id: String) async {
        do {
            _ = try await authenticatedRequest("POST", "/api/accounts/checkin", body: ["id": id], timeout: 60)
            toast = Toast(text: "已提交签到", kind: .success)
            haptic(.medium)
            await loadAccounts()
        } catch {
            let apiError = error as? PanelAPIError
            toast = Toast(
                text: "签到失败：\(apiError?.errorDescription ?? error.localizedDescription)",
                kind: .error
            )
        }
    }

    func refreshAccountToken(_ id: String) async {
        do {
            _ = try await authenticatedRequest("POST", "/api/accounts/refresh", body: ["id": id], timeout: 60)
            toast = Toast(text: "凭证已刷新", kind: .success)
            await loadAccounts()
        } catch {
            let apiError = error as? PanelAPIError
            toast = Toast(
                text: "刷新失败：\(apiError?.errorDescription ?? error.localizedDescription)",
                kind: .error
            )
        }
    }
}

// MARK: - 助手

extension AppModel {

    /// 可用模型清单（给输入框的模型选择器用）。
    func loadAssistantModels() async {
        guard assistantModels.isEmpty, activeProfile?.isValid == true else { return }
        do {
            let response = try await authenticatedRequest("GET", "/api/models/manage", timeout: 25)
            let node = response.json.obj("data") ?? response.json
            let items = node.arr("models") ?? []
            let names: [String] = items.compactMap { item in
                let kind = (item.firstString(["kind", "type"]) ?? "").lowercased()
                if kind == "image" { return nil }
                if item.bool("enabled") == false { return nil }
                return item.firstString(["model", "id", "name", "alias"])
            }
            assistantModels = Array(Set(names)).sorted()
        } catch {
            // 模型列表拿不到不影响聊天：不传 model 就是「跟随模型」
            assistantModels = []
        }
    }

    func addAttachment(_ item: ChatAttachment) {
        guard attachments.count < 8 else {
            toast = Toast(text: "一次最多带 8 个附件", kind: .warning)
            return
        }
        attachments.append(item)
        noteLocalCompute()
    }

    func removeAttachment(_ id: UUID) {
        attachments.removeAll { $0.id == id }
    }

    func clearAttachments() {
        attachments = []
    }
}

// MARK: - 接入配置生成（Agent 配置页）

/// 一种客户端的接入配置模板。生成的是**本地 JSON 文件**，导出后自己放到对应目录。
struct AgentPreset: Identifiable, Equatable {

    var id: String
    var name: String
    var fileName: String
    var target: String
    var note: String

    func object(baseURL: String, apiKey: String, model: String) -> [String: Any] {
        switch id {
        case "claude":
            var env: [String: Any] = [
                "ANTHROPIC_BASE_URL": baseURL,
                "ANTHROPIC_AUTH_TOKEN": apiKey
            ]
            if !model.isEmpty { env["ANTHROPIC_MODEL"] = model }
            return ["env": env]
        case "codex":
            var provider: [String: Any] = [
                "name": "Agent2API",
                "base_url": baseURL.hasSuffix("/v1") ? baseURL : baseURL + "/v1",
                "env_key": "AGENT2API_API_KEY"
            ]
            provider["wire_api"] = "responses"
            var root: [String: Any] = [
                "model_provider": "agent2api",
                "model_providers": ["agent2api": provider]
            ]
            if !model.isEmpty { root["model"] = model }
            return root
        case "opencode":
            return [
                "provider": [
                    "agent2api": [
                        "npm": "@ai-sdk/openai-compatible",
                        "options": [
                            "baseURL": baseURL.hasSuffix("/v1") ? baseURL : baseURL + "/v1",
                            "apiKey": apiKey
                        ],
                        "models": model.isEmpty ? [:] : [model: ["name": model]]
                    ]
                ]
            ]
        default:
            var root: [String: Any] = [
                "base_url": baseURL,
                "api_key": apiKey
            ]
            if !model.isEmpty {
                root["model"] = model
                root["models"] = [model]
            }
            root["provider"] = "openai-compatible"
            return root
        }
    }
}

enum AgentPresetCatalog {

    static let all: [AgentPreset] = [
        AgentPreset(
            id: "claude", name: "Claude Code", fileName: "claude-settings.json",
            target: "~/.claude/settings.json",
            note: "把 env 里的三项合并进现有 settings.json"
        ),
        AgentPreset(
            id: "codex", name: "Codex CLI", fileName: "codex-config.json",
            target: "~/.codex/config.json",
            note: "Codex 用 model_providers；TOML 版本可照着字段填"
        ),
        AgentPreset(
            id: "opencode", name: "OpenCode", fileName: "opencode.json",
            target: "~/.config/opencode/opencode.json",
            note: "openai-compatible 提供商，写入 options"
        ),
        AgentPreset(
            id: "generic", name: "通用（OpenAI 兼容）", fileName: "agent2api.json",
            target: "任意支持自定义 baseURL 的客户端",
            note: "base_url + api_key + model 三件套"
        )
    ]
}

extension AppModel {

    /// 接入用的默认 baseURL：面板地址 + `/v1`（已经是 /v1 就不重复加）。
    var defaultBaseURL: String {
        guard let profile = activeProfile else { return "" }
        let root = profile.rootString
        return root.hasSuffix("/v1") ? root : root + "/v1"
    }

    /// 生成配置文本（纯本地，不发请求）。
    func agentConfigText(
        preset: AgentPreset,
        baseURL: String,
        apiKey: String,
        model: String
    ) -> String {
        let object = preset.object(
            baseURL: baseURL.trimmingCharacters(in: .whitespacesAndNewlines),
            apiKey: apiKey.trimmingCharacters(in: .whitespacesAndNewlines),
            model: model.trimmingCharacters(in: .whitespacesAndNewlines)
        )
        guard JSONSerialization.isValidJSONObject(object),
              let data = try? JSONSerialization.data(
                withJSONObject: object,
                options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
              ),
              let text = String(data: data, encoding: .utf8) else {
            return "{}"
        }
        return text
    }

    /// 写到临时目录，供分享 / 导出。
    func writeAgentConfigFile(
        preset: AgentPreset,
        text: String
    ) -> URL? {
        let directory = FileManager.default.temporaryDirectory
        let url = directory.appendingPathComponent(preset.fileName)
        do {
            try text.data(using: .utf8)?.write(to: url, options: .atomic)
            return url
        } catch {
            toast = Toast(text: "写文件失败：\(error.localizedDescription)", kind: .error)
            return nil
        }
    }
}


// MARK: - 设置

extension AppModel {

    /// 数字显示：紧凑（1.2万）还是完整（12,345）。
    func displayNumber(_ value: Int) -> String {
        compactNumbers ? PanelNumber.compact(value) : PanelNumber.grouping(value)
    }

    /// 修改管理员密码：`POST /api/panel/change-password`
    func changePassword(current: String, next: String) async -> Bool {
        let current = current.trimmingCharacters(in: .whitespacesAndNewlines)
        let next = next.trimmingCharacters(in: .whitespacesAndNewlines)
        guard next.count >= 6 else {
            toast = Toast(text: "新密码至少 6 位", kind: .warning)
            return false
        }
        do {
            _ = try await authenticatedRequest(
                "POST", "/api/panel/change-password",
                body: ["oldPassword": current, "newPassword": next],
                timeout: 30
            )
            toast = Toast(text: "密码已更新，请记牢", kind: .success)
            haptic(.medium)
            // 改完密码旧令牌可能失效，清掉本地密码让下次重新登录
            if let id = activeID {
                KeychainStore.set(next, for: KeychainStore.panelPasswordKey(for: id))
                KeychainStore.delete(KeychainStore.panelTokenKey(for: id))
                KeychainStore.delete(KeychainStore.panelRefreshKey(for: id))
            }
            return true
        } catch {
            let apiError = error as? PanelAPIError
            toast = Toast(
                text: "修改失败：\(apiError?.errorDescription ?? error.localizedDescription)",
                kind: .error
            )
            return false
        }
    }

    /// 只清本机凭证（不动面板）。
    func signOutLocal() {
        guard let id = activeID else { return }
        KeychainStore.delete(KeychainStore.panelTokenKey(for: id))
        KeychainStore.delete(KeychainStore.panelRefreshKey(for: id))
        UserDefaults.standard.removeObject(forKey: "panel.tokenExpiry.\(id.uuidString)")
        toast = Toast(text: "本机凭证已清除，下次同步会重新登录", kind: .success)
        haptic(.medium)
    }
}

// MARK: - 网关 Key（助手聊天用）

extension AppModel {

    var assistantKey: GatewayKey? {
        gatewayKeys.first { $0.id == assistantKeyID && $0.enabled }
            ?? gatewayKeys.first { $0.enabled }
            ?? gatewayKeys.first
    }

    var assistantKeyValue: String { assistantKey?.value ?? "" }

    /// 优先 `/api/model-access/keys`（助手/模型测试用的那套），回落到 `/api/keys`。
    func loadGatewayKeys(force: Bool = false) async {
        if !force, !gatewayKeys.isEmpty { return }
        do {
            let response = try await authenticatedRequest("GET", "/api/model-access/keys", timeout: 20)
            var items = GatewayKeysParser.items(response.json)
            if items.isEmpty {
                let fallback = try await authenticatedRequest("GET", "/api/keys", timeout: 20)
                items = GatewayKeysParser.items(fallback.json)
            }
            gatewayKeys = items
            if assistantKeyID.isEmpty
                || !items.contains(where: { $0.id == assistantKeyID && $0.enabled }) {
                assistantKeyID = items.first(where: \.enabled)?.id ?? items.first?.id ?? ""
            }
            noteLocalCompute()
        } catch {
            // 静默失败：聊天时会明确提示「先选一把 Key」
        }
    }
}

// MARK: - 添加账号：网页登录 / 手机号 / 导入 / 自定义提供商

extension AppModel {

    private func payload(_ json: JSONValue) -> JSONValue {
        json.obj("data") ?? json
    }

    // MARK: 网页登录

    func loadLoginMethods(provider: String) async {
        loginMethods = []
        loginError = nil
        do {
            let encoded = provider.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? provider
            let response = try await authenticatedRequest(
                "GET", "/api/session/login/methods?provider=\(encoded)", timeout: 25
            )
            loginMethods = LoginMethodsParser.items(response.json)
            if loginMethods.isEmpty {
                loginError = "这个提供商没有返回可用的登录方式"
            }
        } catch {
            let apiError = error as? PanelAPIError
            loginError = apiError?.errorDescription ?? error.localizedDescription
        }
    }

    /// 发起网页 / OAuth 登录：面板给一个 state（有的还给授权地址）。
    func startWebLogin(provider: String, method: LoginMethod) async -> Bool {
        loginBusy = true
        loginError = nil
        loginMessage = nil
        defer { loginBusy = false }

        do {
            let response = try await authenticatedRequest(
                "POST", "/api/session/login/start",
                body: ["provider": provider, "methodIndex": method.index],
                timeout: 40
            )
            let node = payload(response.json)
            loginState = node.firstString(["state", "id", "loginId"]) ?? ""
            loginURL = node.firstString(["url", "authUrl", "loginUrl", "authorizeUrl"])

            if let url = loginURL, let target = URL(string: url) {
                await UIApplication.shared.open(target)
                loginMessage = "已打开授权页，完成后回到这里等结果"
            } else {
                loginMessage = "已向面板发起登录，正在等待结果"
            }
            return !loginState.isEmpty
        } catch {
            let apiError = error as? PanelAPIError
            loginError = apiError?.errorDescription ?? error.localizedDescription
            return false
        }
    }

    /// 轮询登录结果：`GET /api/session/login/wait?state=`
    func waitForLogin(provider: String) async -> Bool {
        guard !loginState.isEmpty else { return false }
        let encoded = loginState.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? loginState
        loginBusy = true
        loginError = nil
        defer { loginBusy = false }

        for _ in 0..<40 {
            if Task.isCancelled { return false }
            do {
                let response = try await authenticatedRequest(
                    "GET", "/api/session/login/wait?state=\(encoded)", timeout: 60
                )
                let node = payload(response.json)
                let status = (node.firstString(["status", "state"]) ?? "").lowercased()
                if let error = node.firstString(["error", "message"]), !error.isEmpty,
                   ["failed", "error", "canceled", "cancelled"].contains(status) {
                    loginError = error
                    return false
                }
                if ["done", "success", "succeeded", "ok", "completed"].contains(status) || node.bool("accountId") != nil {
                    loginMessage = "登录成功，正在刷新账号"
                    haptic(.medium)
                    await loadAccounts(force: true)
                    return true
                }
                if ["pending", "waiting", "running", "started", ""].contains(status) {
                    try? await Task.sleep(nanoseconds: 3_000_000_000)
                    continue
                }
                // 状态未知：交给下一轮，最多等两分钟
                try? await Task.sleep(nanoseconds: 3_000_000_000)
            } catch {
                let apiError = error as? PanelAPIError
                loginError = apiError?.errorDescription ?? error.localizedDescription
                return false
            }
        }
        loginError = "等待超时，如果浏览器里已经登录成功，直接刷新账号列表"
        return false
    }

    func cancelWebLogin() async {
        guard !loginState.isEmpty else { return }
        _ = try? await authenticatedRequest(
            "POST", "/api/session/login/cancel", body: ["state": loginState], timeout: 20
        )
        loginState = ""
        loginURL = nil
        loginMessage = nil
    }

    // MARK: 手机号

    func sendSmsCode(phone: String, provider: String) async -> Bool {
        let phone = phone.trimmingCharacters(in: .whitespacesAndNewlines)
        guard phone.count >= 6 else {
            loginError = "手机号不完整"
            return false
        }
        loginBusy = true
        loginError = nil
        loginMessage = nil
        defer { loginBusy = false }

        let path: String
        switch provider {
        case "loomy": path = "/api/session/login/loomy/sms/send"
        case "tabbit": path = "/api/session/login/tabbit/sms/send"
        default: path = "/api/session/login/sms/send"
        }

        do {
            var body: [String: Any] = ["phone": phone]
            if !provider.isEmpty { body["provider"] = provider }
            let response = try await authenticatedRequest("POST", path, body: body, timeout: 40)
            let node = payload(response.json)
            smsDeviceID = node.firstString(["deviceId", "msgid", "uuid", "id"]) ?? ""
            loginMessage = "验证码已发送"
            return true
        } catch {
            let apiError = error as? PanelAPIError
            loginError = apiError?.errorDescription ?? error.localizedDescription
            return false
        }
    }

    func verifySmsCode(phone: String, code: String, provider: String) async -> Bool {
        loginBusy = true
        loginError = nil
        defer { loginBusy = false }

        let path: String
        switch provider {
        case "loomy": path = "/api/session/login/loomy/sms/verify"
        case "tabbit": path = "/api/session/login/tabbit/sms/verify"
        default: path = "/api/session/login/sms/verify"
        }

        do {
            var body: [String: Any] = [
                "phone": phone.trimmingCharacters(in: .whitespacesAndNewlines),
                "code": code.trimmingCharacters(in: .whitespacesAndNewlines)
            ]
            if !provider.isEmpty { body["provider"] = provider }
            if !smsDeviceID.isEmpty {
                body["deviceId"] = smsDeviceID
                body["msgid"] = smsDeviceID
                body["uuid"] = smsDeviceID
            }
            _ = try await authenticatedRequest("POST", path, body: body, timeout: 60)
            loginMessage = "登录成功，正在刷新账号"
            haptic(.medium)
            await loadAccounts(force: true)
            return true
        } catch {
            let apiError = error as? PanelAPIError
            loginError = apiError?.errorDescription ?? error.localizedDescription
            return false
        }
    }

    // MARK: 导入文件

    /// `POST /api/accounts/import`：把 JSON 原样交给面板，它自己认结构。
    func importAccounts(jsonText: String) async -> Bool {
        guard let data = jsonText.data(using: .utf8),
              let value = try? JSONDecoder().decode(JSONValue.self, from: data) else {
            loginError = "这个文件不是合法 JSON"
            return false
        }
        loginBusy = true
        loginError = nil
        defer { loginBusy = false }

        do {
            let body: Any = value.objectValue != nil ? value.foundationObject : ["accounts": value.foundationObject]
            _ = try await authenticatedRequest("POST", "/api/accounts/import", body: body, timeout: 60)
            loginMessage = "导入已提交，正在刷新账号"
            haptic(.medium)
            await loadAccounts(force: true)
            return true
        } catch {
            let apiError = error as? PanelAPIError
            loginError = apiError?.errorDescription ?? error.localizedDescription
            return false
        }
    }

    // MARK: 自定义提供商

    /// 先建提供商，再建账号：`POST /api/custom-providers` → `POST /api/accounts`。
    func createCustomProvider(
        name: String,
        baseURL: String,
        apiKey: String,
        protocolName: String
    ) async -> Bool {
        let name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let baseURL = baseURL.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty, !baseURL.isEmpty else {
            loginError = "名称和 Base URL 都要填"
            return false
        }
        loginBusy = true
        loginError = nil
        defer { loginBusy = false }

        do {
            let created = try await authenticatedRequest(
                "POST", "/api/custom-providers",
                body: ["name": name, "baseUrl": baseURL, "baseURL": baseURL, "protocol": protocolName],
                timeout: 40
            )
            let node = payload(created.json)
            let providerID = node.firstString(["id", "provider", "providerId"])
                ?? node.obj("provider")?.firstString(["id"])
                ?? ""

            if !providerID.isEmpty {
                var account: [String: Any] = ["provider": providerID, "name": name]
                if !apiKey.isEmpty { account["apiKey"] = apiKey }
                _ = try? await authenticatedRequest("POST", "/api/accounts", body: account, timeout: 40)
            }
            loginMessage = "提供商已创建"
            haptic(.medium)
            await loadAccounts(force: true)
            return true
        } catch {
            let apiError = error as? PanelAPIError
            loginError = apiError?.errorDescription ?? error.localizedDescription
            return false
        }
    }
}
