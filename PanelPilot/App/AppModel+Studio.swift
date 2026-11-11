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

    /// 查询余额：`GET /api/accounts/usage/snapshot`
    ///
    /// `silent: true` 用于「进账号页顺手拉一次」：不弹 toast、不报错弹窗，
    /// 失败就让列表继续显示上一次的数字（余额不是主功能，不该打扰人）。
    func queryBalances(silent: Bool = false) async {
        guard activeProfile?.isValid == true else { return }
        balancesLoading = true
        balanceError = nil
        do {
            // 快照接口：一次拿全部账号最近一次的余额（不打上游、很快）
            let response = try await authenticatedRequest("GET", "/api/accounts/usage/snapshot", timeout: 40)
            balances = response.json
            let parsed = AccountBalanceParser.snapshot(response.json)
            if parsed.isEmpty {
                balanceError = "网关没有返回任何余额数据；可能是这个版本还没有余额查询插件。"
            }
            balanceByAccount.merge(parsed) { _, new in new }
            balancesUpdatedAt = Date()
            noteLocalCompute()
            if !silent {
                toast = Toast(text: "余额已更新（\(parsed.count) 个账号）", kind: parsed.isEmpty ? .warning : .success)
            }
        } catch {
            let apiError = error as? PanelAPIError
            balanceError = apiError?.errorDescription ?? error.localizedDescription
            if !silent {
                toast = Toast(text: "查询余额失败：\(balanceError ?? "")", kind: .error)
            }
        }
        balancesLoading = false
    }

    /// 进账号页时自动补一次余额。
    ///
    /// 列表里每个账号的副标题都要带余额，不能等用户点「查询余额」才出现；
    /// 但也没必要每次进页面都打一次接口 —— 5 分钟内的结果够新。
    func loadBalancesQuietly(force: Bool = false) async {
        guard activeProfile?.isValid == true else { return }
        if !force, !balanceByAccount.isEmpty, let at = balancesUpdatedAt,
           Date().timeIntervalSince(at) < 300 {
            return
        }
        await queryBalances(silent: true)
    }

    /// 单账号实时查询：`GET /api/accounts/usage?id=`（会真的打一次上游，慢一点）
    func refreshBalance(id: String) async {
        guard activeProfile?.isValid == true, !id.isEmpty else { return }
        balanceBusyID = id
        do {
            let encoded = id.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? id
            let response = try await authenticatedRequest(
                "GET", "/api/accounts/usage?id=\(encoded)", timeout: 60
            )
            let parsed = AccountBalanceParser.single(response.json, id: id)
            balanceByAccount[id] = parsed
            balancesUpdatedAt = Date()
            if parsed.hasError {
                toast = Toast(text: parsed.error ?? "上游返回了错误", kind: .warning)
            }
        } catch {
            let apiError = error as? PanelAPIError
            balanceByAccount[id] = AccountBalance(id: id, primary: "查询失败", error: apiError?.errorDescription ?? error.localizedDescription)
            toast = Toast(text: "查询失败：\(apiError?.errorDescription ?? error.localizedDescription)", kind: .error)
        }
        balanceBusyID = nil
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

/// 一种客户端的接入配置模板。
///
/// 每个模板都按**那个客户端真正吃的格式**生成，而不是把三件套随便包成 JSON：
///   · Claude Code 读 `~/.claude/settings.json` 的 `env`，它的 SDK 会自己拼上
///     `/v1/messages` —— base 写 `.../v1` 就变成 `/v1/v1/messages`，直接 404；
///   · Codex CLI 只认 `~/.codex/config.toml`（TOML），JSON 那份它根本读不了；
///   · OpenCode 读 `opencode.json`，要 `npm` + `options` + `models` 的固定形状；
///   · 剩下两个是通用件：`.env`（openai SDK / Chatbox / Cherry Studio 直接能用）
///     和一段 curl 自测脚本（地址、密钥、模型到底哪一步不对，跑一下就知道）。
struct AgentPreset: Identifiable, Equatable {

    var id: String
    var name: String
    var fileName: String
    var target: String
    var note: String

    // MARK: 地址归一

    /// 面板根地址：去掉末尾斜杠，以及可能被用户粘进来的 `/v1`。
    static func rootURL(_ base: String) -> String {
        var value = base.trimmingCharacters(in: .whitespacesAndNewlines)
        while value.hasSuffix("/") { value.removeLast() }
        if value.hasSuffix("/v1") { value = String(value.dropLast(3)) }
        while value.hasSuffix("/") { value.removeLast() }
        return value
    }

    /// OpenAI 兼容基址：不管用户填没填 `/v1`，这里都以 `/v1` 结尾。
    static func openAIBase(_ base: String) -> String {
        let root = rootURL(base)
        return root.isEmpty ? "" : root + "/v1"
    }

    // MARK: 生成

    func text(baseURL: String, apiKey: String, model: String, models: [String] = []) -> String {
        let root = Self.rootURL(baseURL)
        let openai = Self.openAIBase(baseURL)
        let key = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        let mainModel = model.trimmingCharacters(in: .whitespacesAndNewlines)
        let list = models.isEmpty ? (mainModel.isEmpty ? [] : [mainModel]) : models

        switch id {
        case "claude":
            var env: [String: Any] = [
                // 注意：这里**不能**带 /v1。Claude Code 自己会拼 /v1/messages。
                "ANTHROPIC_BASE_URL": root,
                "ANTHROPIC_AUTH_TOKEN": key
            ]
            if !mainModel.isEmpty {
                env["ANTHROPIC_MODEL"] = mainModel
                // 后台小任务也会发请求；指到同一个模型最稳（指到面板没有的 haiku 会直接报错）
                env["ANTHROPIC_SMALL_FAST_MODEL"] = mainModel
            }
            return Self.json(["env": env] as [String: Any])

        case "codex":
            var lines = [
                "# ~/.codex/config.toml —— Codex CLI 只认 TOML，JSON 它读不了",
                "# 用之前先让终端里有这个环境变量（也可以写进 ~/.zshrc）：",
                "#   export AGENT2API_API_KEY=\"\(key)\"",
                ""
            ]
            if !mainModel.isEmpty { lines.append("model = \"\(mainModel)\"") }
            lines.append("model_provider = \"agent2api\"")
            lines.append("")
            lines.append("[model_providers.agent2api]")
            lines.append("name = \"Agent2API\"")
            lines.append("base_url = \"\(openai)\"")
            lines.append("env_key = \"AGENT2API_API_KEY\"")
            lines.append("# 网关两种协议都支持：chat 兼容性最好，responses 功能更全")
            lines.append("wire_api = \"chat\"")
            if !list.isEmpty {
                lines.append("")
                lines.append("# 可用模型（/model 里能选到的 id）")
                for item in list.prefix(40) { lines.append("# - \(item)") }
            }
            return lines.joined(separator: "\n") + "\n"

        case "opencode":
            var modelDict: [String: Any] = [:]
            for item in (list.isEmpty ? ["auto"] : list) {
                modelDict[item] = ["name": item]
            }
            var options: [String: Any] = ["baseURL": openai]
            if !key.isEmpty { options["apiKey"] = key }
            var object: [String: Any] = [
                "$schema": "https://opencode.ai/config.json",
                "provider": [
                    "agent2api": [
                        "npm": "@ai-sdk/openai-compatible",
                        "name": "Agent2API",
                        "options": options,
                        "models": modelDict
                    ]
                ]
            ]
            if !mainModel.isEmpty { object["model"] = "agent2api/\(mainModel)" }
            return Self.json(object)

        case "curl":
            let script = """
            #!/usr/bin/env bash
            # 面板连通性自测：哪一步不对，跑一下就知道是哪一步
            set -uo pipefail

            BASE="\(openai)"
            KEY="\(key)"
            MODEL="\(mainModel.isEmpty ? "auto" : mainModel)"

            echo "① 模型列表（不需要 key；能返回 JSON 就说明地址和证书都对）"
            curl -sS --max-time 20 "$BASE/models" | head -c 300; echo

            echo "② 聊天补全（这一步才真正校验 key 和模型）"
            BODY=$(cat <<JSON
            {"model":"$MODEL","messages":[{"role":"user","content":"ping"}],"max_tokens":16}
            JSON
            )
            curl -sS --max-time 60 "$BASE/chat/completions" -H "Authorization: Bearer $KEY" -H "Content-Type: application/json" -d "$BODY"
            echo
            """
            return script + "\n"

        default:
            var lines = [
                "# 通用 OpenAI 兼容三件套：openai SDK / Chatbox / Cherry Studio / NextChat / LobeChat",
                "# 这些软件里就填这三个值；Base URL 别再自己加 /v1",
                "OPENAI_BASE_URL=\(openai)",
                "OPENAI_API_KEY=\(key)",
                "OPENAI_MODEL=\(mainModel.isEmpty ? "auto" : mainModel)",
                "",
                "# Claude Code 用另一组，注意 base 不带 /v1：",
                "# ANTHROPIC_BASE_URL=\(root)",
                "# ANTHROPIC_AUTH_TOKEN=\(key)"
            ]
            if !list.isEmpty {
                lines.append("")
                lines.append("# 可用模型：")
                for item in list.prefix(40) { lines.append("# - \(item)") }
            }
            return lines.joined(separator: "\n") + "\n"
        }
    }

    static func json(_ object: [String: Any]) -> String {
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
}

enum AgentPresetCatalog {

    static let all: [AgentPreset] = [
        AgentPreset(
            id: "claude", name: "Claude Code", fileName: "claude-settings.json",
            target: "~/.claude/settings.json",
            note: "合并进现有 settings.json 的 env；base 不能带 /v1"
        ),
        AgentPreset(
            id: "codex", name: "Codex CLI", fileName: "config.toml",
            target: "~/.codex/config.toml",
            note: "TOML 格式；密钥放环境变量 AGENT2API_API_KEY"
        ),
        AgentPreset(
            id: "opencode", name: "OpenCode", fileName: "opencode.json",
            target: "~/.config/opencode/opencode.json",
            note: "openai-compatible 提供商，写入 options"
        ),
        AgentPreset(
            id: "env", name: "通用（.env）", fileName: ".env",
            target: "任意 OpenAI 兼容软件 / SDK",
            note: "Base URL + API Key + 模型三件套"
        ),
        AgentPreset(
            id: "curl", name: "连通性自测", fileName: "check-agent2api.sh",
            target: "在电脑上 bash 跑一下",
            note: "两条命令区分：地址不对，还是 key / 模型不对"
        )
    ]
}

extension AppModel {

    /// 把 `/api/models/manage` 按提供商分组，供「Agent 配置」直接选。
    func loadAgentModelCatalog(force: Bool = false) async {
        guard activeProfile?.isValid == true else { return }
        if agentModelsLoading { return }
        if !force, !agentModelsByProvider.isEmpty { return }

        agentModelsLoading = true
        do {
            let response = try await authenticatedRequest("GET", "/api/models/manage", timeout: 40)
            var grouped: [String: [String]] = [:]
            for row in JSONRows.from(response.json) {
                guard let id = row.firstString(["id", "model", "name"]) else { continue }
                let provider = row.firstString(["provider", "providerId"]) ?? "全部"
                grouped[provider, default: []].append(id)
            }
            for key in grouped.keys {
                grouped[key] = Array(Set(grouped[key] ?? [])).sorted()
            }
            agentModelsByProvider = grouped
            agentProviders = grouped.keys.sorted()
            noteLocalCompute()
        } catch {
            // 拿不到就退回助手模型列表，不挡用户
            if agentModelsByProvider.isEmpty, !assistantModels.isEmpty {
                agentModelsByProvider = ["全部": assistantModels]
                agentProviders = ["全部"]
            }
        }
        agentModelsLoading = false
    }

    /// 当前选中的提供商下所有模型
    func agentModels(for provider: String) -> [String] {
        if provider.isEmpty { return assistantModels }
        return agentModelsByProvider[provider] ?? assistantModels
    }

    /// 接入用的默认 baseURL：面板地址 + `/v1`（已经是 /v1 就不重复加）。
    var defaultBaseURL: String {
        guard let profile = activeProfile else { return "" }
        let root = profile.rootString
        return root.hasSuffix("/v1") ? root : root + "/v1"
    }

    /// 生成配置文本（纯本地，不发请求）。
    /// 生成配置文本（纯本地，不发请求）。格式由模板自己决定：JSON / TOML / .env / shell。
    func agentConfigText(
        preset: AgentPreset,
        baseURL: String,
        apiKey: String,
        model: String,
        models: [String] = []
    ) -> String {
        preset.text(baseURL: baseURL, apiKey: apiKey, model: model, models: models)
    }

    /// 真的拿这份配置去打一次 `/chat/completions`，把网关的原话翻译成人话。
    /// 「导出的配置别的软件用不了」这种事，点一下就能知道卡在地址、密钥还是模型。
    func probeAgentEndpoint(
        baseURL: String,
        apiKey: String,
        model: String
    ) async -> (ok: Bool, text: String) {
        let base = AgentPreset.openAIBase(baseURL)
        guard let url = URL(string: base + "/chat/completions") else {
            return (false, "地址不合法：\(baseURL)")
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 60
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let key = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        if !key.isEmpty {
            request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
            request.setValue(key, forHTTPHeaderField: "x-api-key")
        }
        let payload: [String: Any] = [
            "model": model.isEmpty ? "auto" : model,
            "messages": [["role": "user", "content": "ping"]],
            "max_tokens": 16,
            "stream": false
        ]
        request.httpBody = try? JSONSerialization.data(withJSONObject: payload)

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            let code = (response as? HTTPURLResponse)?.statusCode ?? 0
            let raw = String(data: data, encoding: .utf8) ?? ""
            if (200..<300).contains(code) {
                let reply = Self.replyText(from: data)
                let short = reply.count > 40 ? String(reply.prefix(40)) + "…" : reply
                return (true, "连通 · HTTP \(code) · 模型回：\(short)")
            }
            return (false, "HTTP \(code) · \(Self.explainAgentCode(code, raw: raw))")
        } catch {
            return (false, "连不上：\(error.localizedDescription)")
        }
    }

    /// 从 `/chat/completions` 的返回里抠出第一段正文（流式的 delta 也认）。
    private static func replyText(from data: Data) -> String {
        guard let root = (try? JSONValue.decode(data))?.objectValue,
              let choices = root["choices"]?.arrayValue,
              let first = choices.first?.objectValue else {
            return "（空回复）"
        }
        if let content = first["message"]?.objectValue?["content"]?.stringValue, !content.isEmpty {
            return content
        }
        if let text = first["text"]?.stringValue, !text.isEmpty { return text }
        if let delta = first["delta"]?.objectValue?["content"]?.stringValue, !delta.isEmpty { return delta }
        return "（空回复）"
    }

    /// 把网关/客户端的报错翻成「下一步该改哪」。
    private static func explainAgentCode(_ code: Int, raw: String) -> String {
        let body = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        let brief = body.count > 160 ? String(body.prefix(160)) + "…" : body
        switch code {
        case 401, 403:
            return "密钥没带对或这把 Key 被停用了。去「设置 → 网关 Key」确认它已启用，再点「用本机密钥」。"
        case 404:
            return "地址层级不对。Base URL 应该是 https://域名/v1（Claude Code 用 https://域名，不带 /v1）。响应：\(brief)"
        case 429:
            return "被限流了，等一会儿再试；也可能是这把 Key 的额度用完了。"
        case 500...599:
            return "网关或上游账号出错：\(brief)"
        default:
            return brief.isEmpty ? "没有返回内容" : brief
        }
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

    /// 把网关的登录报错翻译成「用户下一步该干嘛」
    private func friendlyLoginError(_ text: String) -> String {
        if text.contains("尚未申报动态登录方式") {
            return "这个提供商没有网页登录入口。请在电脑的桌面面板里登录一次，或用「导入文件」把配置带过来。"
        }
        if text.contains("未知的登录地区") || text.contains("只支持 autoclaw") {
            return "手机号登录只支持 AutoClaw（国内/国际版）。其他提供商请用「网页登录」或「导入文件」。"
        }
        if text.contains("Not found") || text.contains("404") {
            return "这个网关版本还没有开通这条登录通道（HTTP 404），请升级网关后再试。"
        }
        if text.contains("没有可用登录态") {
            return "网关还没有可用的浏览器登录态：先在桌面面板登录一次，再回来重试。"
        }
        return text
    }

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
                loginError = "这个提供商没有返回可用的登录方式（可能需要在桌面面板登录）"
            }
        } catch {
            let apiError = error as? PanelAPIError
            loginError = friendlyLoginError(apiError?.errorDescription ?? error.localizedDescription)
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
            loginError = friendlyLoginError(apiError?.errorDescription ?? error.localizedDescription)
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
            loginError = friendlyLoginError(apiError?.errorDescription ?? error.localizedDescription)
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
