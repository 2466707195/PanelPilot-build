import Foundation

// === 面板变化推送（SSE 订阅端）===
//
// 面板本身不会推数据，服务器上有一个小服务（scripts/push.py）盯着面板 SQLite 的
// `data_version`，一变就往下推一条 `change`。这里负责把那条流接住：
//   · 断线自动重连：1s → 2s → 4s … 封顶 30s；
//   · 401 交给上层换一次令牌，换不到就退化成轮询（不会把界面卡死）；
//   · 收到 change 只回调「该刷新了」，拉哪几个接口由 AppModel 决定。
//
// 为什么用 URLSession.bytes(for:) 而不是 WebSocket：
// 服务端是普通 HTTP SSE，跟着 nginx 的 443 走同一套鉴权，不需要额外开端口。

final class PushChannel {

    enum State: Equatable {
        case idle
        case connecting
        case live
        case unauthorized
        case failed(String)
    }

    private enum Outcome {
        case unauthorized
        case closed
        case failed
    }

    private let url: URL
    private let token: String
    private let onState: (State) -> Void
    /// `usage`：用量/账号/签到变了；`config`：路由、模型规则、助手会话这类配置变了
    private let onChange: (_ usage: Bool, _ config: Bool) -> Void

    private var task: Task<Void, Never>?
    private(set) var state: State = .idle

    /// 地址就是面板根地址，SSE 挂在 `/push/events`。
    init?(
        base: String,
        token: String,
        onState: @escaping (State) -> Void,
        onChange: @escaping (_ usage: Bool, _ config: Bool) -> Void
    ) {
        var trimmed = base.trimmingCharacters(in: .whitespacesAndNewlines)
        while trimmed.hasSuffix("/") { trimmed.removeLast() }
        guard !trimmed.isEmpty,
              !token.trimmingCharacters(in: .whitespaces).isEmpty,
              let url = URL(string: trimmed + "/push/events") else { return nil }

        self.url = url
        self.token = token
        self.onState = onState
        self.onChange = onChange
    }

    /// 每次（重）连都新建一个 session：SSE 是长连接，复用被上层取消过的 session
    /// 会拿到「已失效」的错误，重连就永远失败。
    private func makeSession() -> URLSession {
        let config = URLSessionConfiguration.default
        // 默认 60s 的请求超时会把流掐断，然后不停重连。
        config.timeoutIntervalForRequest = 3600
        config.timeoutIntervalForResource = 86_400
        config.waitsForConnectivity = false
        config.requestCachePolicy = .reloadIgnoringLocalCacheData
        return URLSession(configuration: config)
    }

    func start() {
        stop()
        task = Task { [weak self] in
            var delay: UInt64 = 1
            while !Task.isCancelled {
                guard let self else { return }
                let outcome = await self.openOnce()
                if Task.isCancelled { return }

                if case .unauthorized = outcome {
                    self.update(.unauthorized)
                    return  // 交给 AppModel 换令牌；换不到就老老实实轮询
                }
                self.update(.failed("推送已断开，\(delay) 秒后重连"))
                try? await Task.sleep(nanoseconds: delay * 1_000_000_000)
                delay = min(delay * 2, 30)
            }
        }
    }

    func stop() {
        task?.cancel()
        task = nil
        update(.idle)
    }

    // MARK: 一次连接

    private func openOnce() async -> Outcome {
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("text/event-stream", forHTTPHeaderField: "Accept")
        request.setValue(token, forHTTPHeaderField: "x-panel-token")
        request.setValue("Bearer " + token, forHTTPHeaderField: "Authorization")
        update(.connecting)

        let session = makeSession()
        defer { session.invalidateAndCancel() }

        do {
            let (bytes, response) = try await session.bytes(for: request)
            guard let http = response as? HTTPURLResponse else { return .failed }
            if http.statusCode == 401 || http.statusCode == 403 { return .unauthorized }
            guard http.statusCode == 200 else { return .failed }

            var event = ""
            var data = ""
            for try await line in bytes.lines {
                if Task.isCancelled { return .closed }

                if line.hasPrefix(":") { continue }                    // 心跳，不处理
                if line.hasPrefix("event:") {
                    event = line.dropFirst("event:".count)
                        .trimmingCharacters(in: .whitespaces)
                    continue
                }
                if line.hasPrefix("data:") {
                    data = String(line.dropFirst("data:".count))
                        .trimmingCharacters(in: .whitespaces)
                    continue
                }
                if !line.isEmpty { continue }

                // 空行 = 一个事件结束
                if event == "ready" {
                    update(.live)
                } else if event == "change" {
                    update(.live)
                    // 服务端会说明「哪一类变了」。老版本的服务端不带 data，
                    // 这种情况按「用量变了」处理，宁可多刷一次也别漏。
                    let flags = Self.parse(data)
                    onChange(flags.usage, flags.config)
                }
                event = ""
                data = ""
            }
            return .closed
        } catch {
            if Task.isCancelled { return .closed }
            return .failed
        }
    }

    /// `{"seq":12,"ts":...,"usage":true,"config":false}`
    private static func parse(_ text: String) -> (usage: Bool, config: Bool) {
        guard !text.isEmpty, let bytes = text.data(using: .utf8) else {
            return (true, false)
        }
        guard let raw = try? JSONSerialization.jsonObject(with: bytes),
              let object = raw as? [String: Any] else {
            return (true, false)
        }
        let usage = object["usage"] as? Bool ?? true
        let config = object["config"] as? Bool ?? false
        // 两个都没标（比如服务端只发了 seq）时，按用量变化处理
        if !usage && !config { return (true, false) }
        return (usage, config)
    }

    private func update(_ next: State) {
        guard next != state else { return }
        state = next
        onState(next)
    }
}
