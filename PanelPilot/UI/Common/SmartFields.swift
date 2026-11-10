import SwiftUI

// === 把接口报文变成「有效信息」的渲染层 ===
//
// 与 `DataViews` 的区别：这里不再把 JSON 原样铺开，而是先按
// `PanelFields` 翻译成「中文标签 + 格式化取值」，再按前缀分组
// （软件信息 / 运行环境 / 部署与路径 / 安全与凭证 / 规模 …）。
//
// 每一行都带动作：
//   · 链接 → 点右侧箭头直接打开（浏览器 / 系统）
//   · 路径 → 点右侧图标复制（长按任意行也能复制值）
//   · 布尔 → 直接显示「是 / 否」并用语义色
//   · 字节 / 秒数 / 时间戳 / 比率 → 换算成人类可读的写法
//
// 字段多的时候按组折叠，避免又变成一屏接一屏的无尽列表。

// MARK: - 数据模型

struct SmartField: Identifiable {
    let id: String
    /// 原始路径，如 `deployment.dbBytes`
    let path: String
    let label: String
    let icon: String
    let kind: PanelFieldKind
    /// 已格式化的显示值
    let value: String
    /// 复制用的原始值；敏感字段为 nil
    let copyText: String?
    /// 标签是否已翻译成中文（没翻译的用等宽字，提示这是技术键名）
    let translated: Bool
    /// 数组 / 嵌套对象：可以点进去看展开后的内容
    var children: JSONValue? = nil
}

struct SmartFieldGroup: Identifiable {
    let id: String
    let title: String
    var fields: [SmartField]
}

// MARK: - 构建

enum PanelFieldBuilder {

    static func groups(from json: JSONValue) -> [SmartFieldGroup] {
        var collected: [SmartField] = []
        collect(json, prefix: "", depth: 0, into: &collected)
        guard !collected.isEmpty else { return [] }

        var buckets: [String: [SmartField]] = [:]
        for field in collected {
            let key = PanelFields.groupKey(for: field.path)
            buckets[key, default: []].append(field)
        }

        let keys = buckets.keys.sorted { lhs, rhs in
            let left = PanelFields.groupRank(lhs)
            let right = PanelFields.groupRank(rhs)
            if left != right { return left < right }
            return lhs < rhs
        }

        return keys.map { key in
            let fields = (buckets[key] ?? []).sorted { lhs, rhs in
                let left = PanelFields.order(for: lhs.path)
                let right = PanelFields.order(for: rhs.path)
                if left != right { return left < right }
                return lhs.path < rhs.path
            }
            return SmartFieldGroup(id: key, title: PanelFields.groupTitle(for: key), fields: fields)
        }
    }

    private static func collect(
        _ node: JSONValue,
        prefix: String,
        depth: Int,
        into fields: inout [SmartField]
    ) {
        guard let dict = node.objectValue else {
            append(node, path: prefix.isEmpty ? "value" : prefix, into: &fields)
            return
        }
        // 顶层是数组时也走这里：`{0:…}` 之类不可靠，直接报条数
        for key in dict.keys.sorted() {
            guard let value = dict[key] else { continue }
            let path = prefix.isEmpty ? key : "\(prefix).\(key)"
            if value.objectValue != nil, depth < 2 {
                collect(value, prefix: path, depth: depth + 1, into: &fields)
            } else {
                append(value, path: path, into: &fields)
            }
        }
    }

    private static func append(_ value: JSONValue, path: String, into fields: inout [SmartField]) {
        let spec = PanelFields.spec(for: path)
        let kind = resolvedKind(value, path: path, spec: spec)
        let raw = PanelFields.rawText(value)
        var sensitive = PanelFields.isSensitive(path) && !raw.isEmpty
        // 计数、布尔这类「名字里带 key/token 但不是秘密」的字段别打码
        switch value {
        case .number, .bool:
            sensitive = false
        default:
            break
        }
        let display = sensitive ? PanelFields.mask(raw) : PanelFields.format(value, kind: kind)
        let label = spec?.label ?? PanelFields.label(for: path)
        let container: JSONValue? = {
            switch value {
            case .array, .object: return value
            default: return nil
            }
        }()
        fields.append(
            SmartField(
                id: path,
                path: path,
                label: label,
                icon: spec?.icon ?? defaultIcon(for: kind),
                kind: kind,
                value: display,
                copyText: sensitive ? nil : raw,
                translated: spec != nil || label.containsChinese,
                children: container
            )
        )
    }

    private static func resolvedKind(
        _ value: JSONValue,
        path: String,
        spec: PanelFieldSpec?
    ) -> PanelFieldKind {
        switch value {
        case .bool:
            return .flag
        case .array, .object, .null:
            return .text
        default:
            break
        }
        if let spec { return spec.kind }
        return inferredKind(path)
    }

    /// 没有字典条目时按键名猜类型
    private static func inferredKind(_ path: String) -> PanelFieldKind {
        let lower = path.lowercased()
        let leaf = lower.split(separator: ".").last.map(String.init) ?? lower
        if leaf.hasSuffix("at") || leaf.contains("date") || leaf.contains("time") && !leaf.hasSuffix("timeout") {
            return .timestamp
        }
        if leaf.contains("url") || leaf.contains("uri") || leaf.hasSuffix("link") { return .url }
        if leaf.contains("path") || leaf.contains("dir") || leaf.hasSuffix("file") { return .path }
        if leaf.contains("bytes") { return .bytes }
        if leaf.contains("seconds") || leaf.contains("duration") { return .duration }
        if leaf.contains("count") || leaf.hasSuffix("num") || leaf.hasSuffix("total") { return .count }
        if leaf.contains("version") { return .version }
        if leaf.contains("rate") || leaf.contains("percent") || leaf.contains("ratio") { return .ratio }
        if leaf.hasPrefix("is") || leaf.hasPrefix("has") || leaf.hasPrefix("can") { return .flag }
        if leaf.contains("host") || leaf.contains("ip") || leaf == "id" { return .code }
        return .text
    }

    private static func defaultIcon(for kind: PanelFieldKind) -> String {
        switch kind {
        case .bytes: return "internaldrive"
        case .path: return "folder"
        case .url: return "link"
        case .flag: return "checkmark.circle"
        case .count: return "number"
        case .duration: return "clock"
        case .ratio: return "percent"
        case .timestamp: return "calendar"
        case .version: return "shippingbox"
        case .tag: return "tag"
        case .code: return "chevron.left.forwardslash.chevron.right"
        case .text: return "text.alignleft"
        }
    }
}

// MARK: - 列表

struct SmartFieldList: View {

    let json: JSONValue
    /// 已经在别处（指标块）展示过的字段，这里跳过，避免重复
    var skipping: Set<String> = []
    /// 每组默认展示几条，超出折叠
    var collapsedLimit: Int = 7
    var onCopy: ((String) -> Void)? = nil

    @State private var expanded: Set<String> = []
    @State private var detail: JSONSheetItem?

    private var groups: [SmartFieldGroup] {
        PanelFieldBuilder.groups(from: json).compactMap { group in
            let fields = group.fields.filter { !skipping.contains($0.path) }
            guard !fields.isEmpty else { return nil }
            return SmartFieldGroup(id: group.id, title: group.title, fields: fields)
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            ForEach(groups) { group in
                groupView(group)
            }
        }
        .sheet(item: $detail) { item in
            JSONDetailSheet(
                title: item.title ?? "详细信息",
                json: item.value,
                onCopy: onCopy
            )
        }
    }

    @ViewBuilder
    private func groupView(_ group: SmartFieldGroup) -> some View {
        let isExpanded = expanded.contains(group.id)
        let shown = isExpanded ? group.fields : Array(group.fields.prefix(collapsedLimit))

        VStack(alignment: .leading, spacing: 2) {
            if !group.title.isEmpty {
                HStack(spacing: 8) {
                    Text(group.title)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(Aurora.muted)
                    Rectangle()
                        .fill(Aurora.hairline)
                        .frame(height: 1)
                }
                .padding(.bottom, 2)
            }

            VStack(spacing: 0) {
                ForEach(Array(shown.enumerated()), id: \.element.id) { index, field in
                    if index > 0 {
                        Rectangle()
                            .fill(Aurora.hairline)
                            .frame(height: 1)
                    }
                    SmartFieldRow(
                        field: field,
                        onCopy: onCopy,
                        onInspect: { node in
                            detail = JSONSheetItem(value: node, title: field.label)
                        }
                    )
                }

                if group.fields.count > shown.count {
                    Button {
                        withAnimation(.easeInOut(duration: 0.18)) {
                            _ = expanded.insert(group.id)
                        }
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "chevron.down")
                                .font(.system(size: 9, weight: .bold))
                            Text("展开其余 \(group.fields.count - shown.count) 项")
                                .font(.system(size: 11.5, weight: .semibold))
                        }
                        .foregroundStyle(Aurora.brand)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.vertical, 9)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }
}

// MARK: - 单行

struct SmartFieldRow: View {

    let field: SmartField
    var onCopy: ((String) -> Void)?
    /// 数组 / 嵌套对象：点进去看展开内容
    var onInspect: ((JSONValue) -> Void)?

    @Environment(\.openURL) private var openURL

    /// 路径、链接、长文本用「标签在上、值在下」，否则左右两栏
    private var stacked: Bool {
        switch field.kind {
        case .path, .url:
            return true
        default:
            return field.value.count > 24
        }
    }

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            if stacked {
                VStack(alignment: .leading, spacing: 4) {
                    label
                    value
                }
                Spacer(minLength: 4)
            } else {
                label
                    .frame(width: 100, alignment: .leading)
                value
                Spacer(minLength: 4)
            }
            accessory
        }
        .padding(.vertical, 9)
        .contentShape(Rectangle())
        .contextMenu {
            if let copyText = field.copyText, !copyText.isEmpty, let onCopy {
                Button {
                    onCopy(copyText)
                } label: {
                    Label("复制值", systemImage: "doc.on.doc")
                }
            }
            if field.kind == .url, let raw = field.copyText, let url = URL(string: raw) {
                Button {
                    openURL(url)
                } label: {
                    Label("打开链接", systemImage: "arrow.up.right")
                }
            }
            if !field.translated {
                Button {
                    if let onCopy { onCopy(field.path) }
                } label: {
                    Label("复制字段名", systemImage: "textformat")
                }
            }
        }
    }

    private var label: some View {
        HStack(spacing: 5) {
            Image(systemName: field.icon)
                .font(.system(size: 9.5, weight: .semibold))
                .foregroundStyle(Aurora.brand.opacity(0.7))
                .frame(width: 12, alignment: .center)
            Text(field.label)
                .font(
                    field.translated
                        ? .system(size: 11.5, weight: .medium)
                        : .system(size: 10.5, weight: .medium, design: .monospaced)
                )
                .foregroundStyle(Aurora.muted)
                .lineLimit(2)
        }
    }

    private var value: some View {
        Text(field.value)
            .font(valueFont)
            .foregroundStyle(valueColor)
            .lineLimit(stacked ? 4 : 3)
            .truncationMode(.middle)
            .multilineTextAlignment(.leading)
            .textSelection(.enabled)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var valueFont: Font {
        switch field.kind {
        case .path, .code, .url, .version:
            return AuroraFont.monoSmall
        default:
            return AuroraFont.bodySmall
        }
    }

    private var valueColor: Color {
        switch field.kind {
        case .flag:
            if field.value == "是" { return Aurora.success }
            if field.value == "否" { return Aurora.muted }
            return Aurora.ink
        case .url:
            return Aurora.brand
        case .tag:
            return Aurora.inkSoft
        default:
            return Aurora.ink
        }
    }

    @ViewBuilder
    private var accessory: some View {
        if field.kind == .url, let raw = field.copyText, let url = URL(string: raw) {
            MiniIconButton(icon: "arrow.up.right", tint: Aurora.brand) {
                openURL(url)
            }
        } else if field.kind == .path, let raw = field.copyText {
            MiniIconButton(icon: "doc.on.doc", tint: Aurora.inkSoft) {
                onCopy?(raw)
            }
        } else if let node = field.children, let onInspect {
            MiniIconButton(icon: "chevron.right", tint: Aurora.inkSoft) {
                onInspect(node)
            }
        }
    }
}

// MARK: - 小图标按钮

/// 26pt 的玻璃小圆钮：只放在信息行右侧做一个动作，不抢视线。
struct MiniIconButton: View {

    let icon: String
    var tint: Color = Aurora.inkSoft
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(tint)
                .frame(width: 26, height: 26)
                .background(GlassSurface(shape: Circle(), shadowRadius: 4, highlight: 0.22))
                .contentShape(Circle())
        }
        .buttonStyle(PressScaleStyle(scale: 0.9))
    }
}

// MARK: - 指标条

/// 关键几项先从字段里拎出来做成指标，剩下的再按组铺开。
struct SmartMetricStrip: View {

    struct Item: Identifiable {
        let id: String
        let label: String
        let value: String
        let icon: String
        var tint: Color = Aurora.brand
    }

    let items: [Item]

    private var columns: [GridItem] {
        [GridItem(.flexible(), spacing: 8), GridItem(.flexible(), spacing: 8)]
    }

    var body: some View {
        LazyVGrid(columns: columns, alignment: .leading, spacing: 8) {
            ForEach(items) { item in
                MetricTile(
                    icon: item.icon,
                    title: item.label,
                    value: item.value,
                    tint: item.tint
                )
            }
        }
    }
}

// MARK: - 取嵌套值

extension JSONValue {

    /// 顶层取不到时再看一层 `data` —— 面板一半接口是 `{ok, data:{…}}`。
    func lookup(_ key: String) -> JSONValue? {
        if let value = value(key) { return value }
        return value("data")?.value(key)
    }

    func lookupString(_ keys: [String]) -> String? {
        for key in keys {
            if let text = lookup(key)?.stringValue, !text.isEmpty { return text }
        }
        return nil
    }

    func lookupBool(_ keys: [String]) -> Bool? {
        for key in keys {
            if let flag = lookup(key)?.boolValue { return flag }
        }
        return nil
    }
}

extension String {

    /// 是否含中文：用来判断标签有没有被翻译过
    var containsChinese: Bool {
        unicodeScalars.contains { scalar in
            (0x4E00...0x9FFF).contains(scalar.value)
        }
    }
}
