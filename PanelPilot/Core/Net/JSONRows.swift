import Foundation

// === 列表行提取（纯 Foundation，可在 CI 里单测）===
//
// 面板的包装层至少有三种形态：`{data:[…]}`、`{success, data:{items:[…]}}`、直接返回数组。
// 这里统一探测，免得每个页面写一遍。
//
// 2.2.0 的「Agent 配置读取失败」就是这张候选键表漏了 `clients`：
// 面板回 `{clients:[…]}`，提取器认不出来，于是整块被当成「一个对象」当行渲染，
// 标题取不到、状态取不到，界面只剩一句「读取失败」。

enum JSONRows {

    static let candidates = [
        "items", "list", "accounts", "keys", "logs", "requests",
        "entries", "ordered", "queue", "records", "rows",
        "sessions", "models", "data", "results",
        // Agent / 工具 / 定时任务这类接口用复数集合名，漏了就会把整块当成一行
        "clients", "agents", "profiles", "servers", "providers",
        "pools", "tasks", "schedules", "resources", "messages"
    ]

    static func from(_ json: JSONValue) -> [JSONValue] {
        var node = json
        if let data = json.value("data") { node = data }

        if let items = node.arrayValue { return items }

        if let object = node.objectValue {
            for key in candidates {
                if let items = object[key]?.arrayValue, !items.isEmpty { return items }
            }
            // 单对象接口（比如 summary）：整块当成一行渲染
            return object.isEmpty ? [] : [node]
        }
        return []
    }
}
