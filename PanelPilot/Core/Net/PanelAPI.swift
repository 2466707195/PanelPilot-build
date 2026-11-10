import Foundation

// === 面板 HTTP 客户端 ===
//
// 只做三件事：拼 URL、带令牌、把错误翻译成人话。
// 所有响应保持 JSONValue（不按固定 schema 解码），理由见 JSONValue.swift 顶部。

struct PanelResponse {
    var json: JSONValue
    var statusCode: Int
    var latencyMs: Int
    var byteCount: Int
}

enum PanelAPIError: LocalizedError {

    case notConfigured
    /// 带上面板返回的原话：`请先登录管理面板` 和 `令牌无效` 要分开提示
    case unauthorized(String?)
    case needLogin(String)
    case http(Int, String)
    case transport(String, String)
    case decoding(String)

    var errorDescription: String? {
        switch self {
        case .notConfigured: return "还没有配置面板地址"
        case .unauthorized(let reason):
            let text = reason?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            return text.isEmpty ? "令牌无效或未填写" : text
        case .needLogin(let reason): return reason
        case .http(let code, let message): return "HTTP \(code) · \(message)"
        case .transport(let message, _): return message
        case .decoding(let message): return "响应不是合法 JSON：\(message)"
        }
    }

    /// 给用户的下一步动作，直接显示在错误卡片下面。
    var hint: String? {
        switch self {
        case .notConfigured:
            return "去「设置」新建一个连接，填上地址和登录方式。"
        case .unauthorized:
            return "去「设置 → 这个连接」检查令牌，或者把认证方式改成账号密码。"
        case .needLogin:
            return "在「设置」里把这个连接改成「账号密码」并填上管理员账号，App 会自己登录。"
        case .http(let code, _):
            if code == 404 { return "这个接口在当前面板版本里可能不存在，不影响其他页面。" }
            if code == 403 { return "面板拒绝了这次请求，检查令牌权限或反向代理的规则。" }
            if code >= 500 { return "面板内部报错，去看一眼它的服务端日志。" }
            return nil
        case .transport(_, let hint):
            return hint
        case .decoding:
            return "如果反向代理返回了 HTML 登录页，说明请求被拦在代理层，没到面板。"
        }
    }

    /// 是不是「令牌问题」：这类错误值得自动换一枚令牌再试一次。
    ///
    /// 注意 403 不算 —— 那通常是某个接口的权限，不是会话失效，
    /// 拿它去重登只会让用户以为凭证坏了。
    var isAuthFailure: Bool {
        switch self {
        case .unauthorized, .needLogin:
            return true
        default:
            return false
        }
    }

    /// 面板**明确拒绝**了账号密码。只有这种才允许把界面切成「需要登录」。
    var isCredentialRejection: Bool {
        switch self {
        case .http(let code, _):
            return code == 401 || code == 403
        case .unauthorized:
            return true
        default:
            return false
        }
    }

    /// 把 URLError 翻译成「哪一层断了」。
    static func from(_ error: Error) -> PanelAPIError {
        guard let urlError = error as? URLError else {
            return .transport(error.localizedDescription, "把地址、端口、令牌逐个核对一遍。")
        }
        switch urlError.code {
        case .cannotFindHost, .dnsLookupFailed:
            return .transport("域名解析失败", "地址拼错了，或者 Tailscale 的 MagicDNS 名字在这台手机上解析不了。")
        case .cannotConnectToHost:
            return .transport("端口没有响应", "面板可能没运行，或者只监听了 127.0.0.1 —— 这种情况下手机从任何网络都连不上，需要按「接入指引」把端口暴露出来。")
        case .timedOut:
            return .transport("连接超时", "电脑在睡眠、Tailscale 掉线，或者防火墙挡住了端口。")
        case .networkConnectionLost:
            return .transport("连接被中断", "网络切换（Wi-Fi ↔ 蜂窝）导致，重试一次即可。")
        case .notConnectedToInternet:
            return .transport("手机没有网络", "先确认手机本身能上网。")
        case .secureConnectionFailed, .serverCertificateUntrusted, .serverCertificateHasBadDate,
             .serverCertificateNotYetValid, .serverCertificateHasUnknownRoot:
            return .transport("HTTPS 证书不受信任", "自签证书需要换成受信任的；临时调试可以把连接方式改成 http。")
        case .appTransportSecurityRequiresSecureConnection:
            return .transport(
                "被 iOS 的 ATS 策略拦下",
                "安装包的 Info.plist 没有放开明文 HTTP（1.2.0 起已修）。若不是最新包，换最新包重装；或者给面板配上 HTTPS。"
            )
        case .cancelled:
            return .transport("请求已取消", "重新点一次刷新。")
        default:
            return .transport("网络请求失败（\(urlError.code.rawValue)）", urlError.localizedDescription)
        }
    }
}

struct PanelAPI {

    let base: String
    let token: String
    let apiKey: String
    let timeout: TimeInterval

    init(base: String, token: String = "", apiKey: String = "", timeout: TimeInterval = 10) {
        self.base = base
        self.token = token
        self.apiKey = apiKey
        self.timeout = timeout
    }

    private static let session: URLSession = {
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 12
        config.timeoutIntervalForResource = 20
        config.waitsForConnectivity = false
        config.requestCachePolicy = .reloadIgnoringLocalCacheData
        config.httpAdditionalHeaders = ["Accept": "application/json"]
        return URLSession(configuration: config)
    }()

    func url(for path: String) -> URL? {
        let trimmed = path.hasPrefix("/") ? path : "/" + path
        return URL(string: base + trimmed)
    }

    // MARK: 请求

    func get(_ path: String, authenticated: Bool = true) async throws -> PanelResponse {
        try await send(path: path, method: "GET", body: nil, authenticated: authenticated)
    }

    func post(
        _ path: String,
        body: [String: Any]? = nil,
        authenticated: Bool = true,
        extraHeaders: [String: String] = [:]
    ) async throws -> PanelResponse {
        var data: Data?
        if let body {
            data = try? JSONSerialization.data(withJSONObject: body, options: [])
        }
        return try await send(
            path: path,
            method: "POST",
            body: data,
            authenticated: authenticated,
            extraHeaders: extraHeaders
        )
    }

    /// 通用请求：路径自带的 query 原样保留，body 允许任意 JSON 结构。
    /// 页面目录里所有区块都走这一个入口，避免每种资源各写一个方法。
    func request(
        _ method: String,
        _ path: String,
        body: Any? = nil,
        authenticated: Bool = true
    ) async throws -> PanelResponse {
        var data: Data?
        if let body {
            data = try? JSONSerialization.data(withJSONObject: body, options: [])
        }
        return try await send(path: path, method: method, body: data, authenticated: authenticated)
    }

    /// 助手对话：服务端按 SSE 逐段吐字，这里边读边回调。
    ///
    /// 事件结构各版本不完全一致，所以不按固定字段解码：从每个事件的 JSON 里
    /// 递归找第一段文本增量（`delta.content` / `content` / `text` / `delta`），
    /// 找到什么就用什么，找不到就跳过 —— 宁可少显示一段，也不整轮报错。
    func streamChat(
        _ path: String,
        body: [String: Any],
        onText: @escaping (String) -> Void
    ) async throws {
        guard let url = url(for: path) else { throw PanelAPIError.notConfigured }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 120
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(token, forHTTPHeaderField: "x-panel-token")
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("panel-console-ios", forHTTPHeaderField: "x-agent2api-client")
        if !apiKey.isEmpty {
            request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        }
        request.httpBody = try? JSONSerialization.data(withJSONObject: body, options: [])

        let (bytes, response) = try await Self.session.bytes(for: request)
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            var raw = Data()
            for try await byte in bytes {
                raw.append(byte)
                if raw.count > 4096 { break }
            }
            let message = Self.errorMessage(from: raw) ?? "HTTP \(http.statusCode)"
            if http.statusCode == 401 || http.statusCode == 403 {
                throw PanelAPIError.unauthorized(message)
            }
            throw PanelAPIError.http(http.statusCode, message)
        }

        for try await line in bytes.lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard !trimmed.isEmpty else { continue }
            let payload = trimmed.hasPrefix("data:")
                ? String(trimmed.dropFirst(5)).trimmingCharacters(in: .whitespaces)
                : trimmed
            if payload == "[DONE]" { break }
            guard payload.hasPrefix("{") || payload.hasPrefix("[") else { continue }
            guard let data = payload.data(using: .utf8),
                  let json = try? JSONValue.decode(data) else { continue }
            if let piece = PanelAPI.deltaText(in: json), !piece.isEmpty {
                onText(piece)
            }
        }
    }

    /// 从任意结构的事件里挑出第一段文本增量。
    static func deltaText(in value: JSONValue) -> String? {
        // 首选标准形态：choices[0].delta.content
        if let choices = value.value("choices")?.arrayValue, let first = choices.first {
            if let delta = first.value("delta") {
                if let text = delta.str("content"), !text.isEmpty { return text }
                if let text = delta.firstString(["text", "reasoning_content"]), !text.isEmpty { return text }
            }
            if let text = first.value("message")?.str("content"), !text.isEmpty { return text }
        }
        // 面板自定义事件：{type:"text", delta:"..."} / {type:"content_block_delta", ...}
        if let delta = value.str("delta"), !delta.isEmpty { return delta }
        if let type = value.str("type"), ["text", "content", "delta", "message"].contains(type) {
            if let text = value.firstString(["text", "content", "value"]), !text.isEmpty { return text }
        }
        return nil
    }

    private func send(
        path: String,
        method: String,
        body: Data?,
        authenticated: Bool,
        extraHeaders: [String: String] = [:]
    ) async throws -> PanelResponse {

        guard !base.isEmpty, let url = url(for: path) else {
            throw PanelAPIError.notConfigured
        }

        var request = URLRequest(url: url)
        request.httpMethod = method
        request.timeoutInterval = timeout
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("panel-console-ios", forHTTPHeaderField: "x-agent2api-client")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if authenticated, !token.isEmpty {
            // 面板自己的前端是「两个头一起发」：
            //   headers['Authorization'] = 'Bearer ' + panelAccess
            //   headers['x-panel-token']  = panelAccess
            // 只发一个在部分分支上会被判成未登录（实测 401 panel_login_required）。
            request.setValue(token, forHTTPHeaderField: "x-panel-token")
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        if !apiKey.isEmpty {
            request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        }
        for (key, value) in extraHeaders {
            request.setValue(value, forHTTPHeaderField: key)
        }
        request.httpBody = body

        let started = Date()
        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await Self.session.data(for: request)
        } catch {
            throw PanelAPIError.from(error)
        }
        let latency = max(Int(Date().timeIntervalSince(started) * 1000), 1)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0

        if status == 401 {
            // 面板对「没登录」和「令牌过期」都回 401，靠原文区分：
            // 前者要重新登录，后者要重新换令牌 —— 上层据此决定要不要自动登一次。
            let message = Self.errorMessage(from: data)
            if let type = Self.errorType(from: data), type == "panel_login_required" {
                throw PanelAPIError.needLogin(message ?? "面板要求先登录")
            }
            throw PanelAPIError.unauthorized(message)
        }
        guard (200..<300).contains(status) else {
            throw PanelAPIError.http(status, Self.errorMessage(from: data) ?? "无响应内容")
        }

        let json: JSONValue
        if data.isEmpty {
            json = .null
        } else {
            do {
                json = try JSONValue.decode(data)
            } catch {
                throw PanelAPIError.decoding(error.localizedDescription)
            }
        }

        return PanelResponse(json: json, statusCode: status, latencyMs: latency, byteCount: data.count)
    }

    private static func errorMessage(from data: Data) -> String? {
        guard let json = try? JSONValue.decode(data) else {
            return String(data: data.prefix(200), encoding: .utf8)
        }
        if let message = json.value("error")?.firstString(["message"]) { return message }
        return json.firstString(["message", "detail", "error"])
    }

    /// 面板错误信封里的机器可读类型，`panel_login_required` 表示「该登录了」。
    private static func errorType(from data: Data) -> String? {
        guard let json = try? JSONValue.decode(data) else { return nil }
        return json.value("error")?.str("type")
    }

    // MARK: - 登录

    /// 账号密码换令牌。
    ///
    /// 两步：领题 → 解工作量证明 → 提交。面板的机器人校验是 altcha 题，
    /// 客户端自己算，不需要人工点选，所以这里对用户是「一闪而过」。
    ///
    /// 为什么强制 `x-panel-auth-mode: body`：
    ///   走 Cookie 会话要接管 HttpOnly 的 access/refresh 两枚 cookie，
    ///   而把令牌放进响应体后，后续请求用 `x-panel-token` 头就够了 ——
    ///   和桌面版完全同一条通道，上层不用为两种面板写两套逻辑。
    func login(username: String, password: String) async throws -> PanelSession {
        let name = username.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else {
            throw PanelAuthError.rejected("还没填管理员账号。")
        }

        // 1) 领题。校验被关掉时服务端回 400，那就直接提交。
        var captcha: String?
        do {
            let response = try await get("/api/panel/captcha", authenticated: false)
            let json = response.json
            let challenge = AltchaChallenge(
                algorithm: json.str("algorithm") ?? "SHA-256",
                challenge: json.str("challenge") ?? "",
                maxnumber: json.int("maxnumber") ?? 0,
                salt: json.str("salt") ?? "",
                signature: json.str("signature") ?? ""
            )
            if !challenge.challenge.isEmpty, !challenge.salt.isEmpty {
                // 十万次级别枚举在后台线程跑，别卡主线程
                let solved = await Task.detached(priority: .userInitiated) {
                    PanelAuth.solve(challenge)
                }.value
                guard let solved else {
                    throw PanelAuthError.challengeUnsolved(challenge.maxnumber)
                }
                captcha = solved
            }
        } catch let error as PanelAPIError {
            if case .http(let code, _) = error, code == 400 {
                captcha = nil   // 未启用机器人校验
            } else {
                throw error
            }
        }

        // 2) 提交。`auth-mode=body` 同时放 query 和请求头：有的中介会剥自定义头，
        //    query 剥不掉（这是面板前端自己的双通道做法，照它的来）。
        var body: [String: Any] = ["username": name, "password": password]
        if let captcha { body["captcha"] = captcha }

        let response = try await post(
            "/api/panel/login?auth-mode=body",
            body: body,
            authenticated: false,
            extraHeaders: ["x-panel-auth-mode": "body"]
        )
        let data = response.json.value("data") ?? response.json
        let access = data.str("accessToken") ?? ""
        guard !access.isEmpty else {
            throw PanelAuthError.rejected("登录成功但没拿到令牌，面板版本可能不支持令牌通道。")
        }
        return PanelSession(
            accessToken: access,
            refreshToken: data.str("refreshToken") ?? "",
            expiresIn: data.int("expiresIn") ?? 0
        )
    }

    // MARK: 便捷

    /// 用 refreshToken 换一对新的 access/refresh。
    ///
    /// 这是**续期的首选通道**：不用重走 altcha 人机校验、不用拿密码再登一次，
    /// 也就不会出现「每次续期都换发新令牌、把上一枚立刻作废」的抖动。
    /// 报文与面板前端一致：`POST /api/panel/refresh`，refresh 放请求头。
    func refreshSession(_ refresh: String) async throws -> PanelSession {
        let token = refresh.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !token.isEmpty else { throw PanelAPIError.unauthorized("没有可用的刷新令牌") }

        let response = try await post(
            "/api/panel/refresh",
            body: [:],
            authenticated: false,
            extraHeaders: [
                "x-panel-refresh": token,
                "x-panel-auth-mode": "body"
            ]
        )
        let data = response.json.value("data") ?? response.json
        let access = data.str("accessToken") ?? ""
        guard !access.isEmpty else {
            throw PanelAPIError.unauthorized("面板没有返回新的访问令牌")
        }
        return PanelSession(
            accessToken: access,
            refreshToken: data.str("refreshToken") ?? token,
            expiresIn: data.int("expiresIn") ?? 0
        )
    }

    /// 健康检查。这是唯一不需要令牌的接口，用来判定「这台机器上的面板还在不在」。
    func health() async throws -> (health: PanelHealth, latencyMs: Int) {
        let response = try await get("/health", authenticated: false)
        return (PanelHealth(json: response.json), response.latencyMs)
    }

    /// 面板是否已经完成初始化（首次运行时要先在电脑上注册）。
    func panelStatus() async throws -> (registered: Bool, json: JSONValue) {
        let response = try await get("/api/panel/status", authenticated: false)
        return (response.json.value("data")?.bool("registered") ?? false, response.json)
    }

    /// 把任意列表接口的结果压成行数组（实现见 `JSONRows`）。
    static func rows(from json: JSONValue) -> [JSONValue] {
        JSONRows.from(json)
    }
}
