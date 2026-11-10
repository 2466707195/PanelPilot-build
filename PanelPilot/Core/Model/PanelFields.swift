import Foundation

// === 字段翻译层 ===
//
// 面板接口返回的是 `deployment.dbBytes = 2236416` 这种给机器看的键值对。
// 直接铺在手机上就是「把 JSON 丢给用户」：键名看不懂、字节数没单位、
// 时间戳是 1.7e9、布尔值是 true/false，一屏几十行全是噪音。
//
// 这一层负责三件事：
//   1. **认识**常见字段 → 中文标签 + 语义图标 + 取值类型；
//   2. **不认识的字段**也能把 camelCase / snake_case 拆词后按词表翻译，
//      至少不会再把 `deployment.configDir` 原样怼到脸上；
//   3. **格式化取值**：字节 → 2.1 MB，秒 → 3 天 4 小时，时间戳 → 08-02 14:20，
//      比率 → 87.4%，枚举 → 中文，令牌类字段打码。
//
// 这样同一份 JSON，在 iOS 上呈现的是「有效信息」，而不是原始报文。

// MARK: - 取值类型

enum PanelFieldKind {
    case text
    /// 版本号：等宽，不加千分位
    case version
    /// 字节数：自动换算 KB / MB / GB
    case bytes
    /// 文件或目录路径：长、可复制、等宽
    case path
    /// 链接：可点开
    case url
    /// 布尔：是 / 否，带语义色
    case flag
    /// 计数：整数 + 千分位
    case count
    /// 秒数：换算成「x 天 x 小时」
    case duration
    /// 比率：0.874 → 87.4%
    case ratio
    /// 时间戳：秒 / 毫秒都认
    case timestamp
    /// 技术字符串：等宽显示
    case code
    /// 枚举：查表翻成中文
    case tag
}

// MARK: - 字段规格

struct PanelFieldSpec {
    var label: String
    var icon: String = "circle.dotted"
    var kind: PanelFieldKind = .text
    /// 指定分组（默认按路径首段分组）
    var group: String? = nil
    /// 组内排序权重，越小越靠前
    var order: Int = 600
}

// MARK: - 字典与格式化

enum PanelFields {

    // MARK: 常见字段字典

    /// 键名一律小写（`.lowercased()`），先查完整路径，再查最后一段。
    private static let table: [String: PanelFieldSpec] = [
        // --- app.*：网关自身的身份信息 ---
        "app.version": .init(label: "软件版本", icon: "shippingbox", kind: .version, order: 10),
        "app.channel": .init(label: "更新通道", icon: "arrow.triangle.branch", kind: .tag, order: 20),
        "app.build": .init(label: "构建号", icon: "hammer", kind: .version, order: 30),
        "app.revision": .init(label: "修订号", icon: "number", kind: .version, order: 40),
        "app.name": .init(label: "软件名称", icon: "app.badge", kind: .text, order: 50),
        "app.schemaversion": .init(label: "数据结构版本", icon: "square.stack.3d.up", kind: .version, order: 70),
        "app.dbschemaversion": .init(label: "数据库结构版本", icon: "cylinder.split.1x2", kind: .version, order: 80),
        "app.license": .init(label: "开源许可证", icon: "doc.text", kind: .code, order: 90),
        "app.licenseurl": .init(label: "许可证地址", icon: "link", kind: .url, order: 91),
        "app.sourceurl": .init(label: "源码仓库", icon: "chevron.left.forwardslash.chevron.right", kind: .url, order: 92),
        "app.copyright": .init(label: "版权声明", icon: "c.circle", kind: .text, order: 95),

        // --- runtime.*：进程与系统 ---
        "runtime.deployment": .init(label: "运行形态", icon: "shippingbox", kind: .tag, order: 10),
        "runtime.os": .init(label: "操作系统", icon: "desktopcomputer", kind: .tag, order: 20),
        "runtime.osversion": .init(label: "系统版本", icon: "desktopcomputer", kind: .text, order: 25),
        "runtime.arch": .init(label: "处理器架构", icon: "cpu", kind: .tag, order: 30),
        "runtime.uptimeseconds": .init(label: "已运行", icon: "clock", kind: .duration, order: 40),
        "runtime.uptime": .init(label: "已运行", icon: "clock", kind: .duration, order: 40),
        "runtime.startedat": .init(label: "启动时间", icon: "power", kind: .timestamp, order: 45),
        "runtime.goversion": .init(label: "Go 版本", icon: "chevron.left.forwardslash.chevron.right", kind: .code, order: 50),
        "runtime.nodeversion": .init(label: "Node 版本", icon: "chevron.left.forwardslash.chevron.right", kind: .code, order: 50),
        "runtime.pid": .init(label: "进程号", icon: "number", kind: .code, order: 60),
        "runtime.user": .init(label: "运行用户", icon: "person", kind: .text, order: 70),
        "runtime.memorybytes": .init(label: "内存占用", icon: "memorychip", kind: .bytes, order: 80),

        // --- deployment.*：装在哪、数据放哪 ---
        "deployment.host": .init(label: "监听地址", icon: "network", kind: .code, order: 10),
        "deployment.port": .init(label: "端口", icon: "number", kind: .code, order: 20),
        "deployment.configdir": .init(label: "数据目录", icon: "folder", kind: .path, order: 30),
        "deployment.datadir": .init(label: "数据目录", icon: "folder", kind: .path, order: 30),
        "deployment.workdir": .init(label: "工作目录", icon: "folder", kind: .path, order: 35),
        "deployment.dbfile": .init(label: "数据库文件", icon: "cylinder", kind: .path, order: 40),
        "deployment.dbbytes": .init(label: "数据库大小", icon: "internaldrive", kind: .bytes, order: 50),
        "deployment.dbavailable": .init(label: "数据库可用", icon: "checkmark.seal", kind: .flag, order: 60),
        "deployment.logfile": .init(label: "日志文件", icon: "doc.plaintext", kind: .path, order: 70),
        "deployment.exepath": .init(label: "可执行文件", icon: "terminal", kind: .path, order: 80),
        "deployment.installerkind": .init(label: "安装方式", icon: "shippingbox", kind: .tag, order: 90),
        "deployment.localpanel": .init(label: "内置面板", icon: "rectangle.on.rectangle", kind: .flag, order: 100),
        "deployment.servicename": .init(label: "服务名", icon: "gearshape.2", kind: .code, order: 110),
        "deployment.version": .init(label: "部署版本", icon: "shippingbox", kind: .version, order: 5),

        // --- security.* ---
        "security.apikeycount": .init(label: "网关 Key 数量", icon: "key", kind: .count, order: 10),
        "security.apikeys": .init(label: "网关 Key 数量", icon: "key", kind: .count, order: 10),
        "security.adminuser": .init(label: "管理员账号", icon: "person.badge.key", kind: .text, order: 20),
        "security.username": .init(label: "当前账号", icon: "person.crop.circle", kind: .text, order: 20),
        "security.authmode": .init(label: "认证方式", icon: "lock.shield", kind: .tag, order: 30),
        "security.tls": .init(label: "启用 HTTPS", icon: "lock", kind: .flag, order: 40),
        "security.localonly": .init(label: "仅本机访问", icon: "network.slash", kind: .flag, order: 50),
        "security.requireauth": .init(label: "强制登录", icon: "lock", kind: .flag, order: 60),
        "security.corsorigins": .init(label: "跨域来源", icon: "globe", kind: .code, order: 70),
        "security.sessioncount": .init(label: "在线会话", icon: "person.2", kind: .count, order: 80),

        // --- stats.*：规模 ---
        "stats.accounts": .init(label: "账号总数", icon: "person.2", kind: .count, order: 10),
        "stats.enabledaccounts": .init(label: "启用账号", icon: "person.badge.shield.checkmark", kind: .count, order: 20),
        "stats.models": .init(label: "模型数量", icon: "cpu", kind: .count, order: 30),
        "stats.providers": .init(label: "提供商", icon: "building.2", kind: .count, order: 40),
        "stats.requests": .init(label: "请求总数", icon: "arrow.left.arrow.right", kind: .count, order: 50),
        "stats.keys": .init(label: "Key 数量", icon: "key", kind: .count, order: 60),
        "stats.sessions": .init(label: "会话数", icon: "bubble.left.and.bubble.right", kind: .count, order: 70),

        // --- 更新 ---
        "update.currentversion": .init(label: "当前版本", icon: "shippingbox", kind: .version, order: 10),
        "update.latestversion": .init(label: "最新版本", icon: "arrow.down.circle", kind: .version, order: 20),
        "update.hasupdate": .init(label: "有新版本", icon: "sparkles", kind: .flag, order: 30),
        "update.forceupdate": .init(label: "强制更新", icon: "exclamationmark.triangle", kind: .flag, order: 40),
        "update.channel": .init(label: "更新通道", icon: "arrow.triangle.branch", kind: .tag, order: 50),
        "update.checkedat": .init(label: "检查时间", icon: "clock", kind: .timestamp, order: 60),
        "update.publishedat": .init(label: "发布时间", icon: "calendar", kind: .timestamp, order: 70),
        "update.pageurl": .init(label: "发布页", icon: "link", kind: .url, order: 80),
        "update.downloadurl": .init(label: "下载地址", icon: "arrow.down.circle", kind: .url, order: 90),
        "update.notes": .init(label: "更新说明", icon: "doc.plaintext", kind: .text, order: 100),
        "update.latest": .init(label: "最新版本", icon: "arrow.down.circle", kind: .version, order: 20),

        // --- 会话 ---
        "session.user": .init(label: "登录账号", icon: "person.crop.circle", kind: .text, order: 10),
        "session.username": .init(label: "登录账号", icon: "person.crop.circle", kind: .text, order: 10),
        "session.role": .init(label: "角色", icon: "person.badge.shield.checkmark", kind: .tag, order: 20),
        "session.mode": .init(label: "登录方式", icon: "lock.open", kind: .tag, order: 30),
        "session.ip": .init(label: "来源地址", icon: "network", kind: .code, order: 40),
        "session.useragent": .init(label: "客户端", icon: "laptopcomputer", kind: .code, order: 50),
        "session.expiresat": .init(label: "过期时间", icon: "hourglass", kind: .timestamp, order: 60),
        "session.expiresin": .init(label: "剩余有效期", icon: "hourglass", kind: .duration, order: 70),
        "session.createdat": .init(label: "登录时间", icon: "clock", kind: .timestamp, order: 80),

        // --- 通用叶子字段（不带前缀也能认）---
        "version": .init(label: "版本", icon: "shippingbox", kind: .version, order: 5),
        "currentversion": .init(label: "当前版本", icon: "shippingbox", kind: .version, order: 10),
        "latestversion": .init(label: "最新版本", icon: "arrow.down.circle", kind: .version, order: 20),
        "hasupdate": .init(label: "有新版本", icon: "sparkles", kind: .flag, order: 30),
        "channel": .init(label: "通道", icon: "arrow.triangle.branch", kind: .tag, order: 40),
        "registered": .init(label: "已注册", icon: "checkmark.seal", kind: .flag, order: 10),
        "setuprequired": .init(label: "需要初始化", icon: "wand.and.stars", kind: .flag, order: 20),
        "enabled": .init(label: "已启用", icon: "power", kind: .flag, order: 30),
        "available": .init(label: "可用", icon: "checkmark.circle", kind: .flag, order: 35),
        "ok": .init(label: "成功", icon: "checkmark.circle", kind: .flag, order: 40),
        "status": .init(label: "状态", icon: "dot.radiowaves.left.and.right", kind: .tag, order: 50),
        "state": .init(label: "状态", icon: "dot.radiowaves.left.and.right", kind: .tag, order: 50),
        "mode": .init(label: "模式", icon: "slider.horizontal.3", kind: .tag, order: 55),
        "kind": .init(label: "类型", icon: "square.grid.2x2", kind: .tag, order: 56),
        "type": .init(label: "类型", icon: "square.grid.2x2", kind: .tag, order: 56),
        "name": .init(label: "名称", icon: "tag", kind: .text, order: 60),
        "id": .init(label: "标识", icon: "number", kind: .code, order: 70),
        "host": .init(label: "主机", icon: "network", kind: .code, order: 75),
        "port": .init(label: "端口", icon: "number", kind: .code, order: 76),
        "url": .init(label: "地址", icon: "link", kind: .url, order: 77),
        "endpoint": .init(label: "接入地址", icon: "link", kind: .url, order: 78),
        "baseurl": .init(label: "基础地址", icon: "link", kind: .url, order: 78),
        "webhook": .init(label: "回调地址", icon: "link", kind: .url, order: 79),
        "path": .init(label: "路径", icon: "folder", kind: .path, order: 80),
        "file": .init(label: "文件", icon: "doc", kind: .path, order: 81),
        "filepath": .init(label: "文件", icon: "doc", kind: .path, order: 81),
        "dir": .init(label: "目录", icon: "folder", kind: .path, order: 82),
        "count": .init(label: "数量", icon: "number", kind: .count, order: 83),
        "total": .init(label: "总计", icon: "sum", kind: .count, order: 84),
        "used": .init(label: "已用", icon: "chart.pie", kind: .count, order: 85),
        "limit": .init(label: "上限", icon: "gauge", kind: .count, order: 86),
        "rate": .init(label: "比率", icon: "percent", kind: .ratio, order: 87),
        "percent": .init(label: "百分比", icon: "percent", kind: .ratio, order: 87),
        "size": .init(label: "大小", icon: "internaldrive", kind: .bytes, order: 88),
        "bytes": .init(label: "大小", icon: "internaldrive", kind: .bytes, order: 88),
        "uptime": .init(label: "已运行", icon: "clock", kind: .duration, order: 89),
        "expiresat": .init(label: "过期时间", icon: "hourglass", kind: .timestamp, order: 90),
        "expiresin": .init(label: "剩余有效期", icon: "hourglass", kind: .duration, order: 91),
        "createdat": .init(label: "创建时间", icon: "calendar", kind: .timestamp, order: 92),
        "updatedat": .init(label: "更新时间", icon: "calendar", kind: .timestamp, order: 93),
        "lastusedat": .init(label: "最近使用", icon: "clock.arrow.circlepath", kind: .timestamp, order: 94),
        "checkedat": .init(label: "检查时间", icon: "clock", kind: .timestamp, order: 95),
        "email": .init(label: "邮箱", icon: "envelope", kind: .text, order: 96),
        "role": .init(label: "角色", icon: "person.badge.shield.checkmark", kind: .tag, order: 97),
        "provider": .init(label: "提供商", icon: "building.2", kind: .text, order: 98),
        "model": .init(label: "模型", icon: "cpu", kind: .code, order: 99),
        "tokens": .init(label: "Token", icon: "textformat.abc", kind: .count, order: 100),
        "cost": .init(label: "费用", icon: "yensign.circle", kind: .text, order: 101),
        "latency": .init(label: "延迟", icon: "timer", kind: .code, order: 102),
        "error": .init(label: "错误", icon: "exclamationmark.triangle", kind: .text, order: 103),
        "message": .init(label: "说明", icon: "text.bubble", kind: .text, order: 104),
        "notes": .init(label: "说明", icon: "doc.text", kind: .text, order: 105),
        "ip": .init(label: "来源地址", icon: "network", kind: .code, order: 106),
        "region": .init(label: "地区", icon: "globe", kind: .text, order: 107),
        "timezone": .init(label: "时区", icon: "clock", kind: .code, order: 108)
    ]

    /// 分组标题：路径首段 → 中文
    private static let groupTitles: [String: String] = [
        "app": "软件信息",
        "runtime": "运行环境",
        "deployment": "部署与路径",
        "security": "安全与凭证",
        "stats": "规模",
        "update": "版本更新",
        "session": "当前会话",
        "panel": "面板",
        "db": "数据库",
        "database": "数据库",
        "network": "网络",
        "proxy": "代理",
        "proxies": "代理",
        "limits": "限制",
        "quota": "额度",
        "config": "配置",
        "cache": "缓存",
        "build": "构建",
        "license": "许可",
        "system": "系统"
    ]

    /// 分组排序
    private static let groupOrder: [String] = [
        "app", "runtime", "deployment", "position", "location",
        "security", "stats", "session", "update", "panel",
        "db", "database", "network", "proxy", "proxies",
        "limits", "quota", "cache", "config", "build", "license", "system"
    ]

    // MARK: 枚举翻译

    private static let tagTexts: [String: String] = [
        "both": "正式 + beta",
        "stable": "仅正式版",
        "beta": "仅 beta 版",
        "canary": "内测版",
        "server": "服务端",
        "desktop": "桌面端",
        "cli": "命令行",
        "docker": "容器",
        "container": "容器",
        "portable": "免安装",
        "installer": "安装包",
        "systemd": "systemd 服务",
        "linux": "Linux",
        "darwin": "macOS",
        "windows": "Windows",
        "running": "运行中",
        "stopped": "已停止",
        "stopping": "停止中",
        "starting": "启动中",
        "error": "异常",
        "failed": "失败",
        "ok": "正常",
        "healthy": "健康",
        "degraded": "降级",
        "unknown": "未知",
        "enabled": "已启用",
        "disabled": "已停用",
        "active": "使用中",
        "inactive": "未启用",
        "password": "账号密码",
        "token": "令牌",
        "apikey": "API Key",
        "api_key": "API Key",
        "none": "无",
        "auto": "自动",
        "manual": "手动",
        "true": "是",
        "false": "否",
        "ready": "就绪",
        "pending": "等待中",
        "expired": "已过期",
        "valid": "有效",
        "local": "本机",
        "public": "公网",
        "lan": "局域网",
        "tailscale": "Tailscale"
    ]

    // MARK: 查表

    static func spec(for path: String) -> PanelFieldSpec? {
        let lower = path.lowercased()
        if let hit = table[lower] { return hit }
        guard let leaf = lower.split(separator: ".").last.map(String.init) else { return nil }
        return table[leaf]
    }

    /// 组内排序权重
    static func order(for path: String) -> Int {
        spec(for: path)?.order ?? 600
    }

    /// 分组键：路径首段（没有前缀就是空组，即「基础信息」）
    static func groupKey(for path: String) -> String {
        path.split(separator: ".").first.map { String($0) } ?? ""
    }

    static func groupTitle(for key: String) -> String {
        if key.isEmpty { return "" }
        if let title = groupTitles[key.lowercased()] { return title }
        return humanize(key)
    }

    static func groupRank(_ key: String) -> Int {
        if key.isEmpty { return 0 }
        if let index = groupOrder.firstIndex(of: key.lowercased()) { return index + 1 }
        return 500
    }

    // MARK: 标签

    static func label(for path: String) -> String {
        if let spec = spec(for: path) { return spec.label }
        let leaf = path.split(separator: ".").last.map(String.init) ?? path
        return humanize(leaf)
    }

    /// camelCase / snake_case → 可读文本；词表里有的词翻成中文。
    static func humanize(_ key: String) -> String {
        let parts = tokens(key)
        guard !parts.isEmpty else { return key }

        var translated: [String] = []
        var translatedCount = 0
        for part in parts {
            let lower = part.lowercased()
            if let word = words[lower] {
                translated.append(word)
                translatedCount += 1
            } else {
                translated.append(part.count <= 3 ? part.uppercased() : part.capitalized)
            }
        }

        // 全部词都认识 → 直接拼中文；否则保留空格，读起来仍是英文短语
        let allKnown = translatedCount == parts.count
        return allKnown ? translated.joined() : translated.joined(separator: " ")
    }

    private static let words: [String: String] = [
        "app": "应用", "version": "版本", "channel": "通道", "build": "构建",
        "license": "许可证", "url": "地址", "uri": "地址", "link": "链接",
        "source": "源码", "copyright": "版权", "schema": "结构", "db": "数据库",
        "runtime": "运行时", "deployment": "部署", "os": "系统", "arch": "架构",
        "uptime": "运行时长", "seconds": "秒", "started": "启动", "at": "时间",
        "pid": "进程号", "user": "用户", "memory": "内存", "bytes": "字节",
        "host": "主机", "port": "端口", "config": "配置", "dir": "目录",
        "directory": "目录", "data": "数据", "file": "文件", "log": "日志",
        "exe": "程序", "path": "路径", "installer": "安装器", "local": "本地",
        "panel": "面板", "service": "服务", "name": "名称", "security": "安全",
        "api": "API", "key": "Key", "keys": "Key", "count": "数量",
        "admin": "管理员", "username": "用户名", "auth": "认证", "mode": "方式",
        "tls": "HTTPS", "only": "仅", "require": "要求", "cors": "跨域",
        "origins": "来源", "session": "会话", "stats": "统计", "accounts": "账号",
        "account": "账号", "enabled": "启用", "models": "模型", "model": "模型",
        "providers": "提供商", "provider": "提供商", "requests": "请求",
        "request": "请求", "update": "更新", "current": "当前", "latest": "最新",
        "has": "有", "force": "强制", "checked": "检查", "published": "发布",
        "page": "页面", "notes": "说明", "download": "下载", "role": "角色",
        "expires": "过期", "in": "于", "created": "创建", "updated": "更新",
        "last": "最近", "used": "使用", "email": "邮箱", "ip": "IP",
        "region": "地区", "timezone": "时区", "status": "状态", "state": "状态",
        "kind": "类型", "type": "类型", "size": "大小", "total": "总计",
        "limit": "上限", "rate": "比率", "percent": "百分比", "tokens": "Token",
        "cost": "费用", "latency": "延迟", "error": "错误", "message": "说明",
        "id": "标识", "value": "值", "items": "条目", "list": "列表",
        "group": "分组", "priority": "优先级", "proxy": "代理", "pool": "池",
        "quota": "额度", "cache": "缓存", "hit": "命中", "ratio": "比率",
        "node": "节点", "address": "地址", "traffic": "流量"
    ]

    /// 拆词：`dbFile` → ["db", "File"]，`sourceURL` → ["source", "URL"]
    private static func tokens(_ key: String) -> [String] {
        var result: [String] = []
        var current = ""
        let chars = Array(key)
        for (index, ch) in chars.enumerated() {
            if ch == "_" || ch == "-" || ch == "." || ch == " " || ch == "/" {
                if !current.isEmpty { result.append(current); current = "" }
                continue
            }
            if ch.isUppercase {
                let prevLower = index > 0 && chars[index - 1].isLowercase
                let nextLower = index + 1 < chars.count && chars[index + 1].isLowercase
                if prevLower || (nextLower && !current.isEmpty) {
                    if !current.isEmpty { result.append(current); current = "" }
                }
                current.append(ch)
            } else {
                current.append(ch)
            }
        }
        if !current.isEmpty { result.append(current) }
        return result
    }

    // MARK: 取值格式化

    static func format(_ value: JSONValue, kind: PanelFieldKind) -> String {
        switch value {
        case .null:
            return "—"
        case .bool(let flag):
            return flag ? "是" : "否"
        case .array(let items):
            return items.isEmpty ? "无" : "\(items.count) 项"
        case .object(let dict):
            return dict.isEmpty ? "无" : "\(dict.count) 个字段"
        case .string(let text):
            guard !text.isEmpty else { return "—" }
            let clipped = text.count > 200 ? String(text.prefix(200)) + "…" : text
            switch kind {
            case .tag:
                return tagText(clipped)
            case .timestamp:
                return dateText(clipped) ?? clipped
            default:
                return clipped
            }
        case .number(let raw):
            switch kind {
            case .bytes:
                return byteText(raw)
            case .duration:
                return durationText(raw)
            case .ratio:
                return ratioText(raw)
            case .timestamp:
                return dateText(epoch: raw)
            case .count:
                return integerText(raw)
            case .version:
                return plainInteger(raw)
            default:
                return integerText(raw)
            }
        }
    }

    /// 原始值（复制用）
    static func rawText(_ value: JSONValue) -> String {
        switch value {
        case .null:
            return ""
        case .bool(let flag):
            return flag ? "true" : "false"
        case .number(let raw):
            if raw == raw.rounded(), abs(raw) < 1e15 { return String(Int64(raw)) }
            return String(format: "%g", raw)
        case .string(let text):
            return text
        case .array, .object:
            return value.rawText
        }
    }

    static func byteText(_ value: Double) -> String {
        guard value > 0 else { return "0 B" }
        guard value >= 1024 else { return "\(Int(value)) B" }
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        formatter.allowedUnits = value >= 1024 * 1024 * 1024 ? [.useGB] : (value >= 1024 * 1024 ? [.useMB] : [.useKB])
        formatter.includesUnit = true
        formatter.isAdaptive = true
        return formatter.string(fromByteCount: Int64(value))
    }

    static func durationText(_ seconds: Double) -> String {
        let total = Int(seconds.rounded())
        guard total > 0 else { return "刚启动" }
        let days = total / 86_400
        let hours = (total % 86_400) / 3_600
        let minutes = (total % 3_600) / 60
        let secs = total % 60
        if days > 0 { return hours > 0 ? "\(days) 天 \(hours) 小时" : "\(days) 天" }
        if hours > 0 { return minutes > 0 ? "\(hours) 小时 \(minutes) 分" : "\(hours) 小时" }
        if minutes > 0 { return secs > 0 ? "\(minutes) 分 \(secs) 秒" : "\(minutes) 分" }
        return "\(secs) 秒"
    }

    static func ratioText(_ value: Double) -> String {
        let percent = value <= 1 ? value * 100 : value
        let rounded = (percent * 10).rounded() / 10
        if rounded == rounded.rounded() { return "\(Int(rounded))%" }
        return String(format: "%.1f%%", rounded)
    }

    /// 版本号、端口、进程号这类不该有千分位的整数
    static func plainInteger(_ value: Double) -> String {
        if value == value.rounded(), abs(value) < 1e15 { return String(Int64(value)) }
        return String(format: "%g", value)
    }

    static func integerText(_ value: Double) -> String {
        if value == value.rounded(), abs(value) < 1e15 {
            let formatter = NumberFormatter()
            formatter.numberStyle = .decimal
            formatter.maximumFractionDigits = 0
            return formatter.string(from: NSNumber(value: value)) ?? "\(Int64(value))"
        }
        if abs(value) < 1 { return String(format: "%.4f", value) }
        return String(format: "%.2f", value)
    }

    static func dateText(epoch: Double) -> String {
        let seconds = epoch > 1e12 ? epoch / 1000 : epoch
        guard seconds > 1e9 else { return integerText(epoch) }
        return Date(timeIntervalSince1970: seconds).formatted("MM-dd HH:mm")
    }

    /// ISO8601 / 常见日期字符串 → MM-dd HH:mm
    static func dateText(_ text: String) -> String? {
        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = iso.date(from: text) { return date.formatted("MM-dd HH:mm") }
        iso.formatOptions = [.withInternetDateTime]
        if let date = iso.date(from: text) { return date.formatted("MM-dd HH:mm") }
        return nil
    }

    static func tagText(_ text: String) -> String {
        let lower = text.lowercased()
        if let value = tagTexts[lower] { return value }
        // 形如 "beta-only" / "正式版" 的直接原样
        return text
    }

    // MARK: 敏感字段

    private static let sensitiveWords = [
        "token", "secret", "password", "passwd", "apikey", "api_key",
        "authorization", "cookie", "credential", "privatekey"
    ]

    static func isSensitive(_ path: String) -> Bool {
        let lower = path.lowercased()
        let leaf = lower.split(separator: ".").last.map(String.init) ?? lower
        // 计数字段不是秘密
        if leaf.hasSuffix("count") || leaf.hasPrefix("has") { return false }
        return sensitiveWords.contains { leaf.contains($0) }
    }

    static func mask(_ text: String) -> String {
        guard text.count > 14 else { return "••••••" }
        return text.prefix(4) + "••••••" + text.suffix(4)
    }
}
