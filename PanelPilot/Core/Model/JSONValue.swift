import Foundation

// === 面板 API 的动态 JSON 容器 ===
//
// Agent2API 的接口字段会随版本变化（而且不同插件、不同账号类型返回的字段并不一致）。
// 如果按固定 Codable 结构解析，面板升级一次 App 就白屏。
// 所以：**所有响应先落成 JSONValue 树，页面上再按需取字段**。
// 取不到的字段显示「—」，而不是崩掉。

enum JSONValue: Decodable, Equatable {

    case null
    case bool(Bool)
    case number(Double)
    case string(String)
    case array([JSONValue])
    case object([String: JSONValue])

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() {
            self = .null
        } else if let value = try? container.decode(Bool.self) {
            self = .bool(value)
        } else if let value = try? container.decode(Double.self) {
            self = .number(value)
        } else if let value = try? container.decode(String.self) {
            self = .string(value)
        } else if let value = try? container.decode([JSONValue].self) {
            self = .array(value)
        } else if let value = try? container.decode([String: JSONValue].self) {
            self = .object(value)
        } else {
            self = .null
        }
    }

    static func decode(_ data: Data) throws -> JSONValue {
        try JSONDecoder().decode(JSONValue.self, from: data)
    }
}

// MARK: - 取值

extension JSONValue {

    var objectValue: [String: JSONValue]? {
        if case .object(let value) = self { return value }
        return nil
    }

    var arrayValue: [JSONValue]? {
        if case .array(let value) = self { return value }
        return nil
    }

    /// 字符串形式。数字/布尔会被转成文本，方便直接展示。
    var stringValue: String? {
        switch self {
        case .string(let value):
            return value
        case .number(let value):
            if value == value.rounded(), abs(value) < 1e15 {
                return String(Int64(value))
            }
            return String(format: "%g", value)
        case .bool(let value):
            return value ? "true" : "false"
        default:
            return nil
        }
    }

    var intValue: Int? {
        switch self {
        case .number(let value):
            return Int(value)
        case .string(let value):
            return Int(value)
        case .bool(let value):
            return value ? 1 : 0
        default:
            return nil
        }
    }

    var doubleValue: Double? {
        switch self {
        case .number(let value):
            return value
        case .string(let value):
            return Double(value)
        default:
            return nil
        }
    }

    /// 宽松布尔：兼容 true / "true" / 1 / "ok"。
    var boolValue: Bool? {
        switch self {
        case .bool(let value):
            return value
        case .number(let value):
            return value != 0
        case .string(let value):
            let lower = value.lowercased()
            if ["true", "yes", "ok", "1", "enabled", "on"].contains(lower) { return true }
            if ["false", "no", "0", "disabled", "off", ""].contains(lower) { return false }
            return nil
        default:
            return nil
        }
    }

    func value(_ key: String) -> JSONValue? {
        objectValue?[key]
    }

    func str(_ key: String) -> String? {
        value(key)?.stringValue
    }

    func int(_ key: String) -> Int? {
        value(key)?.intValue
    }

    func bool(_ key: String) -> Bool? {
        value(key)?.boolValue
    }

    func obj(_ key: String) -> JSONValue? {
        guard case .object = value(key) else { return nil }
        return value(key)
    }

    func arr(_ key: String) -> [JSONValue]? {
        value(key)?.arrayValue
    }

    /// 多候选键，按顺序取第一个非空值。面板不同版本字段名不统一时用这个。
    func firstString(_ keys: [String]) -> String? {
        for key in keys {
            if let value = str(key), !value.isEmpty, value != "null" { return value }
        }
        return nil
    }

    func firstInt(_ keys: [String]) -> Int? {
        for key in keys {
            if let value = int(key) { return value }
        }
        return nil
    }

    var displayText: String {
        switch self {
        case .null:
            return "—"
        case .bool(let value):
            return value ? "是" : "否"
        case .number(let value):
            return stringValue ?? "—"
        case .string(let value):
            return value.isEmpty ? "—" : value
        case .array(let items):
            return "\(items.count) 项"
        case .object(let dict):
            return "\(dict.count) 个字段"
        }
    }
}

// MARK: - 扁平化（兜底展示）

struct KeyValuePair: Identifiable, Equatable {
    let id = UUID()
    var key: String
    var value: String
}

extension JSONValue {

    /// 把任意嵌套结构压平成「键 → 值」，用于未知字段的兜底展示。
    ///
    /// 数组不展开下标，只报条数（否则日志里一条请求就能撑爆一屏）；
    /// 嵌在数组里的对象会展开到第一层，方便看列表项的字段名。
    func flattened(prefix: String = "", depth: Int = 0) -> [KeyValuePair] {
        guard depth < 3 else { return [] }

        switch self {
        case .object(let dict):
            var pairs: [KeyValuePair] = []
            for key in dict.keys.sorted() {
                guard let value = dict[key] else { continue }
                let path = prefix.isEmpty ? key : "\(prefix).\(key)"
                switch value {
                case .object:
                    pairs.append(contentsOf: value.flattened(prefix: path, depth: depth + 1))
                case .array(let items):
                    pairs.append(KeyValuePair(key: path, value: "\(items.count) 项"))
                    if let first = items.first, case .object = first {
                        pairs.append(contentsOf: first.flattened(prefix: "\(path)[0]", depth: depth + 1))
                    }
                default:
                    pairs.append(KeyValuePair(key: path, value: value.displayText))
                }
            }
            return pairs
        case .array(let items):
            return [KeyValuePair(key: prefix.isEmpty ? "items" : prefix, value: "\(items.count) 项")]
        default:
            return [KeyValuePair(key: prefix.isEmpty ? "value" : prefix, value: displayText)]
        }
    }
}
