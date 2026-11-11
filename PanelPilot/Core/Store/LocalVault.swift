import Foundation

// === 本地快照仓库 ===
//
// 目标：**界面永远不等网络**。
//
// 每次成功取到一份 JSON，就同时写进这个仓库（Application Support/PanelPilot/vault-<uuid>.json）。
// 冷启动 / 切页面 / 点按钮读的都是这里的副本，只有用户明确点「同步」或后台定时同步时
// 才会去访问面板的 JSON 接口。
//
// 这么做有三个好处：
//   · 飞机上、面板挂了、反向代理抽风，界面依然能完整渲染最后一次拿到的数据；
//   · 图表、统计、筛选全部基于本地数据计算，切区间不会发请求；
//   · 出问题时能明确区分「数据是旧的」和「请求失败了」。

// MARK: - JSONValue 与 Foundation 互转

extension JSONValue {

    /// 转成 JSONSerialization 能吃的对象（落盘用）。
    var foundationObject: Any {
        switch self {
        case .null:
            return NSNull()
        case .bool(let value):
            return value
        case .number(let value):
            if value == value.rounded(), abs(value) < 1e15 {
                return Int64(value)
            }
            return value
        case .string(let value):
            return value
        case .array(let items):
            return items.map { $0.foundationObject }
        case .object(let dict):
            var result: [String: Any] = [:]
            for (key, value) in dict { result[key] = value.foundationObject }
            return result
        }
    }

    /// 落盘用的字节。
    func jsonData() -> Data? {
        try? JSONSerialization.data(withJSONObject: foundationObject, options: [])
    }

    /// 从磁盘读回来的字节还原成树。
    static func fromJSONData(_ data: Data) -> JSONValue? {
        try? JSONDecoder().decode(JSONValue.self, from: data)
    }
}

// MARK: - 仓库

/// 磁盘快照。按「连接（profile）」分文件，换面板不会串数据。
final class LocalVault {

    static let shared = LocalVault()

    struct Entry: Codable {
        var savedAt: Date
        var payload: Data
    }

    struct VaultFile: Codable {
        var profile: String
        var entries: [String: Entry]
    }

    private var files: [String: VaultFile] = [:]
    private let lock = NSLock()

    /// 落盘全部改到这条后台串行队列上。
    ///
    /// 原来的写法是「每存一个 key 就把整份快照 JSON 重新编码一次 + 原子写一次」，
    /// 而 `AppModel` 是 `@MainActor` —— 于是编码和写盘全压在主线程。
    /// 一次「刷新」要存十几份（4 个统计区间 + 5 份仪表盘 + 各页区块 + Agent），
    /// 每份都是整文件重编码，主线程被卡几百毫秒到一两秒，
    /// 表现就是**点右上角刷新，画面直接僵住**。
    /// 现在：内存改完立刻返回，0.35 秒内的多次改动合并成一次后台写。
    private let ioQueue = DispatchQueue(label: "com.agent2api.panelpilot.vault", qos: .utility)
    private var pendingFlush: [String: DispatchWorkItem] = [:]

    /// 目录只在 init 时解析一次：原来每次写盘都 `fileExists` + 可能 `createDirectory`，
    /// 这些也是同步 I/O。
    private let rootDirectory: URL?

    private init() {
        let manager = FileManager.default
        if let base = manager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first {
            let url = base.appendingPathComponent("PanelPilot", isDirectory: true)
            if !manager.fileExists(atPath: url.path) {
                try? manager.createDirectory(at: url, withIntermediateDirectories: true)
            }
            rootDirectory = url
        } else {
            rootDirectory = nil
        }
    }

    private func fileURL(for profile: UUID) -> URL? {
        rootDirectory?.appendingPathComponent("vault-\(profile.uuidString).json")
    }

    // MARK: 读写

    /// 读一个连接的全部快照（进程内只读一次盘）。
    func load(profile: UUID) {
        let key = profile.uuidString
        lock.lock()
        defer { lock.unlock() }
        guard files[key] == nil else { return }
        guard let url = fileURL(for: profile), let data = try? Data(contentsOf: url) else {
            files[key] = VaultFile(profile: key, entries: [:])
            return
        }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        files[key] = (try? decoder.decode(VaultFile.self, from: data))
            ?? VaultFile(profile: key, entries: [:])
    }

    func entry(profile: UUID, key: String) -> Entry? {
        lock.lock()
        defer { lock.unlock() }
        return files[profile.uuidString]?.entries[key]
    }

    func store(profile: UUID, key: String, json: JSONValue, at date: Date = Date()) {
        guard let payload = json.jsonData() else { return }
        lock.lock()
        var file = files[profile.uuidString] ?? VaultFile(profile: profile.uuidString, entries: [:])
        file.entries[key] = Entry(savedAt: date, payload: payload)
        files[profile.uuidString] = file
        lock.unlock()
        // 只标脏，不在这里编码、不在这里写盘：调用方在主线程上。
        scheduleFlush(profile: profile)
    }

    /// 合并 0.35 秒内的连续写入，然后到后台队列上编码 + 原子写。
    private func scheduleFlush(profile: UUID) {
        let key = profile.uuidString
        lock.lock()
        pendingFlush[key]?.cancel()
        let work = DispatchWorkItem { [weak self] in
            self?.writeToDisk(profile: profile)
        }
        pendingFlush[key] = work
        lock.unlock()
        ioQueue.asyncAfter(deadline: .now() + 0.35, execute: work)
    }

    /// 编码 + 原子写。只在 `ioQueue` 上跑（`flushNow` 会同步等它）。
    private func writeToDisk(profile: UUID) {
        let key = profile.uuidString
        lock.lock()
        guard let file = files[key] else {
            lock.unlock()
            return
        }
        pendingFlush[key] = nil
        lock.unlock()

        guard let url = fileURL(for: profile) else { return }
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        guard let data = try? encoder.encode(file) else { return }
        try? data.write(to: url, options: .atomic)
    }

    /// 立刻把还没落盘的改动写完（进后台 / 被系统回收前调用）。
    func flushNow() {
        lock.lock()
        let keys = Array(files.keys)
        lock.unlock()
        guard !keys.isEmpty else { return }
        ioQueue.sync {
            for key in keys {
                guard let uuid = UUID(uuidString: key) else { continue }
                self.writeToDisk(profile: uuid)
            }
        }
    }

    func remove(profile: UUID) {
        lock.lock()
        files.removeValue(forKey: profile.uuidString)
        pendingFlush[profile.uuidString]?.cancel()
        pendingFlush.removeValue(forKey: profile.uuidString)
        lock.unlock()
        if let url = fileURL(for: profile) { try? FileManager.default.removeItem(at: url) }
    }

    /// 仓库概况：条目数 + 最新一份的时间（本地自检用，不发请求）。
    func summary(profile: UUID) -> (count: Int, newest: Date?) {
        lock.lock()
        defer { lock.unlock() }
        let entries = files[profile.uuidString]?.entries ?? [:]
        return (entries.count, entries.values.map(\.savedAt).max())
    }

    /// 磁盘上这个连接是否已有快照（判断「能不能离线渲染」）。
    func hasSnapshot(profile: UUID) -> Bool {
        summary(profile: profile).count > 0
    }
}

// MARK: - 快照键

enum VaultKey {

    static func section(page: String, id: String) -> String {
        "\(page)/\(id)"
    }

    /// 仪表盘：每个统计区间单独存一份，切区间时直接命中本地。
    static func stats(range: String) -> String {
        "dashboard/stats-\(range)"
    }

    /// 仪表盘周边：accounts / panel / queue / checkin / requests
    static func dashboard(_ name: String) -> String {
        "dashboard/\(name)"
    }

    static let agents = "dashboard/agents"
}
