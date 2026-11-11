import SwiftUI

// === 网关 Key（可视化页）===
//
// 原来这一页走通用区块渲染：把 `/api/keys`、`/api/config`、`/api/cors` 三份 JSON
// 原样摊开，于是出现「Data / Success」这种英文分组标题、`APIKey`「Default 模型」
// `Sanitize Blacklist F…` 这种半截英文键名，以及一排「是」的裸布尔值 —— 看得懂才有鬼。
//
// 这里重做成三块：
//   1. 当前 Key：助手/客户端正在用的那一把，打码 + 一键复制；
//   2. Key 列表：一行一把，名称 + 打码 + 启用状态，点开看详情；右上角「＋」新建；
//   3. 网关配置 / 跨域与访问：键名翻成中文，布尔值变成「已启用 / 未启用」小胶囊，
//      长字符串打码并给复制按钮，`success` 这类没有任何信息量的字段直接不显示。

struct GatewayKeysScreen: View {

    @EnvironmentObject private var model: AppModel
    var onBack: () -> Void

    @State private var detail: GatewayKey?
    @State private var showCreate = false
    @State private var showAllKey = false
    @State private var copiedID: String?

    private var keys: [GatewayKey] { model.gatewayKeys }

    private var configJSON: JSONValue? {
        sectionJSON("config")
    }

    private var corsJSON: JSONValue? {
        sectionJSON("cors")
    }

    private func sectionJSON(_ id: String) -> JSONValue? {
        guard let spec = PanelPage.gatewayKeys.spec.sections.first(where: { $0.id == id }) else {
            return nil
        }
        return model.data(page: .gatewayKeys, section: spec).json
    }

    var body: some View {
        ZStack {
            AuroraBackdrop()

            VStack(spacing: 0) {
                AppTopBar(title: "网关 Key", onBack: onBack) {
                    HStack(spacing: 6) {
                        GlassIconButton(
                            systemIcon: "arrow.clockwise",
                            tint: Aurora.inkSoft,
                            diameter: 30,
                            iconSize: 12
                        ) {
                            Task { await reload(force: true) }
                        }
                        GlassIconButton(
                            systemIcon: "plus",
                            tint: Aurora.brand,
                            diameter: 30,
                            iconSize: 13
                        ) {
                            model.haptic(.medium)
                            showCreate = true
                        }
                    }
                }

                ScrollView {
                    VStack(alignment: .leading, spacing: AuroraMetrics.cardSpacing) {
                        currentKeyCard
                        keysCard
                        configCard(
                            title: "网关配置",
                            subtitle: "模型默认值、语言、敏感词过滤",
                            json: configJSON,
                            emptyText: "这台面板没有返回网关配置"
                        )
                        configCard(
                            title: "跨域与访问",
                            subtitle: "浏览器里跨域调用网关时的放行规则",
                            json: corsJSON,
                            emptyText: "这台面板没有返回跨域配置"
                        )
                    }
                    .padding(.horizontal, AuroraMetrics.pagePadding)
                    .padding(.top, 4)
                    .padding(.bottom, AuroraMetrics.listBottomInset)
                    .frame(maxWidth: 640)
                    .frame(maxWidth: .infinity)
                }
                .scrollIndicators(.hidden)
                .refreshable { await reload(force: true) }
            }
        }
        .task { await reload(force: false) }
        .sheet(item: $detail) { key in
            GatewayKeyDetailSheet(key: key)
        }
        .sheet(isPresented: $showCreate) {
            CreateGatewayKeySheet { name in
                await model.createGatewayKey(name: name)
            }
        }
    }

    // MARK: 加载

    private func reload(force: Bool) async {
        await model.loadGatewayKeys(force: force)
        await model.load(page: .gatewayKeys, force: force)
    }

    // MARK: 当前 Key

    private var currentKeyCard: some View {
        SectionCard {
            SectionTitle(title: "当前使用的 Key", trailing: model.assistantKey == nil ? nil : "助手和客户端都走它")

            if let key = model.assistantKey {
                VStack(alignment: .leading, spacing: 10) {
                    HStack(spacing: 8) {
                        Text(key.name)
                            .font(AuroraFont.titleSmall)
                            .foregroundStyle(Aurora.ink)
                            .lineLimit(1)
                        StudioTag(
                            text: key.enabled ? "已启用" : "已停用",
                            tint: key.enabled ? Aurora.success : Aurora.muted
                        )
                        Spacer(minLength: 0)
                    }

                    HStack(spacing: 8) {
                        Text(showAllKey ? key.value : mask(key.value))
                            .font(.system(size: 12, design: .monospaced))
                            .foregroundStyle(Aurora.inkSoft)
                            .lineLimit(1)
                            .truncationMode(.middle)

                        Spacer(minLength: 0)

                        Button {
                            model.copy(key.value, label: "Key 已复制")
                            flash(key.id)
                        } label: {
                            HStack(spacing: 4) {
                                Image(systemName: copiedID == key.id ? "checkmark" : "doc.on.doc")
                                    .font(.system(size: 10, weight: .bold))
                                Text(copiedID == key.id ? "已复制" : "复制")
                                    .font(.system(size: 11, weight: .semibold))
                            }
                            .foregroundStyle(Aurora.brand)
                            .padding(.horizontal, 10)
                            .frame(height: 26)
                            .background(Capsule().fill(Aurora.brand.opacity(0.10)))
                        }
                        .buttonStyle(PressScaleStyle(scale: 0.94))
                    }

                    HStack(spacing: 8) {
                        MiniAction(title: showAllKey ? "隐藏完整 Key" : "显示完整 Key", icon: showAllKey ? "eye.slash" : "eye") {
                            withAnimation(.easeOut(duration: 0.18)) { showAllKey.toggle() }
                        }
                        if keys.count > 1 {
                            Menu {
                                ForEach(keys) { item in
                                    Button {
                                        model.selectAssistantKey(item.id)
                                    } label: {
                                        Label(
                                            "\(item.name)\(item.id == model.assistantKeyID ? "（当前）" : "")",
                                            systemImage: item.id == model.assistantKeyID ? "checkmark" : "key"
                                        )
                                    }
                                }
                            } label: {
                                HStack(spacing: 4) {
                                    Image(systemName: "arrow.left.arrow.right")
                                        .font(.system(size: 10, weight: .bold))
                                    Text("切换")
                                        .font(.system(size: 11, weight: .semibold))
                                }
                                .foregroundStyle(Aurora.inkSoft)
                                .padding(.horizontal, 10)
                                .frame(height: 26)
                                .background(Capsule().fill(Aurora.surfaceVariant))
                            }
                        }
                        Spacer(minLength: 0)
                    }
                }
                .padding(.top, 10)
            } else {
                VStack(alignment: .leading, spacing: 8) {
                    Text("还没有可用的 Key")
                        .font(AuroraFont.bodyMedium)
                        .foregroundStyle(Aurora.ink)
                    Text("点右上角「＋」新建一把，客户端就能用 `x-api-key` 调这个网关了。")
                        .font(AuroraFont.bodySmall)
                        .foregroundStyle(Aurora.muted)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.top, 10)
            }
        }
    }

    // MARK: Key 列表

    private var keysCard: some View {
        SectionCard {
            SectionTitle(title: "Key 列表", trailing: keys.isEmpty ? nil : "\(keys.count) 把")

            if keys.isEmpty {
                StudioEmpty(
                    icon: "key",
                    title: "还没有创建过 Key",
                    detail: "右上角「＋」新建一把，名字随便起（例如「我的 Mac」）。"
                )
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(keys.enumerated()), id: \.element.id) { index, key in
                        if index > 0 {
                            Rectangle().fill(Aurora.hairline).frame(height: 1)
                        }
                        keyRow(key)
                    }
                }
                .padding(.top, 6)
            }
        }
    }

    private func keyRow(_ key: GatewayKey) -> some View {
        Button {
            detail = key
        } label: {
            HStack(spacing: 10) {
                Image(systemName: "key.fill")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(key.enabled ? Aurora.brand : Aurora.muted)
                    .frame(width: 26, height: 26)
                    .background(Circle().fill((key.enabled ? Aurora.brand : Aurora.muted).opacity(0.10)))

                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text(key.name)
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(Aurora.ink)
                            .lineLimit(1)
                        if key.id == model.assistantKeyID {
                            StudioTag(text: "使用中", tint: Aurora.brand)
                        }
                    }
                    Text(mask(key.value))
                        .font(.system(size: 10.5, design: .monospaced))
                        .foregroundStyle(Aurora.muted)
                        .lineLimit(1)
                }

                Spacer(minLength: 6)

                Circle()
                    .fill(key.enabled ? Aurora.success : Aurora.muted.opacity(0.5))
                    .frame(width: 6, height: 6)

                Image(systemName: "chevron.right")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(Aurora.muted)
            }
            .padding(.vertical, 11)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    // MARK: 配置卡

    private func configCard(
        title: String,
        subtitle: String,
        json: JSONValue?,
        emptyText: String
    ) -> some View {
        SectionCard {
            SectionTitle(title: title)

            Text(subtitle)
                .font(.system(size: 11))
                .foregroundStyle(Aurora.muted)
                .padding(.top, 2)

            if let rows = ConfigFields.rows(json), !rows.isEmpty {
                VStack(spacing: 0) {
                    ForEach(Array(rows.enumerated()), id: \.offset) { index, row in
                        if index > 0 {
                            Rectangle().fill(Aurora.hairline).frame(height: 1)
                        }
                        ConfigRowView(row: row)
                    }
                }
                .padding(.top, 8)
            } else {
                Text(emptyText)
                    .font(.system(size: 12))
                    .foregroundStyle(Aurora.muted)
                    .padding(.top, 10)
            }
        }
    }

    private func mask(_ value: String) -> String {
        let text = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard text.count > 12 else { return text }
        return "\(text.prefix(7))…\(text.suffix(4))"
    }

    private func flash(_ id: String) {
        copiedID = id
        Task {
            try? await Task.sleep(nanoseconds: 1_600_000_000)
            if copiedID == id { copiedID = nil }
        }
    }
}

// MARK: - 小胶囊动作

private struct MiniAction: View {

    let title: String
    let icon: String
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 4) {
                Image(systemName: icon).font(.system(size: 10, weight: .bold))
                Text(title).font(.system(size: 11, weight: .semibold))
            }
            .foregroundStyle(Aurora.inkSoft)
            .padding(.horizontal, 10)
            .frame(height: 26)
            .background(Capsule().fill(Aurora.surfaceVariant))
        }
        .buttonStyle(PressScaleStyle(scale: 0.94))
    }
}

// MARK: - 配置字段（把英文键名翻成人话）

/// 一行配置：`label` 已经是中文，`value` 已经是给人看的形状。
struct ConfigField: Equatable {
    var key: String
    var label: String
    var value: String
    var kind: Kind

    enum Kind: Equatable {
        case bool(Bool)
        case secret
        case plain
    }
}

enum ConfigFields {

    /// 这些键没有任何信息量，或者已经在页面上别处表达过了，直接不显示
    private static let hidden: Set<String> = [
        "success", "ok", "data", "version", "schema", "id"
    ]

    private static let labelMap: [String: String] = [
        "apikey": "API 密钥",
        "apiKey": "API 密钥",
        "key": "密钥",
        "defaultModel": "默认模型",
        "model": "默认模型",
        "locale": "语言",
        "language": "语言",
        "sanitizeBlacklist": "敏感词黑名单",
        "sanitizeBlacklistFromEnv": "敏感词来自环境变量",
        "enabled": "启用",
        "corsEnabled": "跨域启用",
        "allowOrigins": "允许来源",
        "allowedOrigins": "允许来源",
        "allowMethods": "允许方法",
        "allowHeaders": "允许请求头",
        "allowCredentials": "允许携带凭证",
        "maxAge": "缓存时间（秒）",
        "exposeHeaders": "暴露的响应头",
        "blacklist": "黑名单",
        "whitelist": "白名单",
        "logLevel": "日志级别",
        "timeout": "超时（秒）",
        "maxTokens": "最大 Token",
        "baseUrl": "上游地址",
        "proxy": "代理"
    ]

    /// 面板的实现里真正的配置多半包在 data 里
    private static let preferredOrder = [
        "defaultModel", "model", "locale", "language",
        "apikey", "apiKey", "key",
        "sanitizeBlacklist", "sanitizeBlacklistFromEnv",
        "corsEnabled", "allowOrigins", "allowedOrigins",
        "allowMethods", "allowHeaders", "allowCredentials",
        "exposeHeaders", "maxAge",
        "logLevel", "timeout", "maxTokens", "baseUrl", "proxy"
    ]

    /// 把 `{data:{...}, success:true}` 拆成一行行配置；认不出的键保留原名。
    static func rows(_ json: JSONValue?) -> [ConfigField]? {
        guard var object = json?.objectValue else { return nil }
        // 面板的实现里真正的配置多半包在 data 里
        if let data = object["data"]?.objectValue {
            object = data
        }

        // 先按「人关心的顺序」排，剩下的按字母排在后面，
        // 不要再让 sanitizeBlacklist 排到 Default 模型前面
        func rank(_ key: String) -> Int {
            preferredOrder.firstIndex(of: key) ?? preferredOrder.count
        }
        let orderedKeys = object.keys
            .filter { !hidden.contains($0) }
            .sorted { lhs, rhs in
                let l = rank(lhs), r = rank(rhs)
                return l == r ? lhs < rhs : l < r
            }

        let fields: [ConfigField] = orderedKeys.compactMap { key in
            guard let value = object[key] else { return nil }
            return field(key: key, value: value)
        }
        return fields
    }

    private static func field(key: String, value: JSONValue) -> ConfigField? {
        let label = labelMap[key] ?? key
        if let flag = value.boolValue {
            return ConfigField(key: key, label: label, value: flag ? "是" : "否", kind: .bool(flag))
        }
        if let text = value.stringValue {
            let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.isEmpty {
                return ConfigField(key: key, label: label, value: "—", kind: .plain)
            }
            // 看起来像密钥的值：打码，别把一串 sk- 摊在屏幕上
            let looksSecret = trimmed.hasPrefix("sk-") || trimmed.count > 40
            return ConfigField(
                key: key,
                label: label,
                value: looksSecret ? "\(trimmed.prefix(7))…\(trimmed.suffix(4))" : trimmed,
                kind: looksSecret ? .secret : .plain
            )
        }
        if let number = value.doubleValue {
            return ConfigField(
                key: key,
                label: label,
                value: number == number.rounded() ? String(Int(number)) : String(format: "%.2f", number),
                kind: .plain
            )
        }
        if let array = value.arrayValue {
            if array.isEmpty { return ConfigField(key: key, label: label, value: "无", kind: .plain) }
            let preview = array.prefix(3).compactMap { $0.stringValue ?? $0.doubleValue.map { String(Int($0)) } }
            let text = preview.isEmpty ? "\(array.count) 项" : preview.joined(separator: "、")
            return ConfigField(
                key: key,
                label: label,
                value: array.count > 3 ? "\(text) 等 \(array.count) 项" : text,
                kind: .plain
            )
        }
        if value.objectValue != nil {
            return ConfigField(key: key, label: label, value: "（\(value.objectValue?.count ?? 0) 项）", kind: .plain)
        }
        return nil
    }
}

private struct ConfigRowView: View {

    let row: ConfigField

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Text(row.label)
                .font(.system(size: 13))
                .foregroundStyle(Aurora.inkSoft)
                .frame(width: 104, alignment: .leading)

            Group {
                switch row.kind {
                case .bool(let flag):
                    Text(row.value)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(flag ? Aurora.success : Aurora.muted)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 2)
                        .background(Capsule().fill((flag ? Aurora.success : Aurora.muted).opacity(0.12)))
                case .secret:
                    Text(row.value)
                        .font(.system(size: 11.5, design: .monospaced))
                        .foregroundStyle(Aurora.ink)
                case .plain:
                    Text(row.value)
                        .font(.system(size: 13))
                        .foregroundStyle(Aurora.ink)
                }
            }
            .lineLimit(2)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.vertical, 8)
    }
}

// MARK: - Key 详情

struct GatewayKeyDetailSheet: View {

    @EnvironmentObject private var model: AppModel
    @Environment(\.dismiss) private var dismiss

    let key: GatewayKey

    @State private var showValue = false
    @State private var copied = false

    private var live: GatewayKey {
        model.gatewayKeys.first { $0.id == key.id } ?? key
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    SectionCard {
                        HStack(spacing: 8) {
                            Text(live.name)
                                .font(AuroraFont.titleSmall)
                                .foregroundStyle(Aurora.ink)
                                .lineLimit(1)
                            StudioTag(
                                text: live.enabled ? "已启用" : "已停用",
                                tint: live.enabled ? Aurora.success : Aurora.muted
                            )
                            Spacer(minLength: 0)
                            if live.id == model.assistantKeyID {
                                StudioTag(text: "使用中", tint: Aurora.brand)
                            }
                        }

                        Text(live.value.isEmpty ? "这个 Key 没有返回明文，面板只给了打码值"
                                                : (showValue ? live.value : mask(live.value)))
                            .font(.system(size: 12, design: .monospaced))
                            .foregroundStyle(Aurora.inkSoft)
                            .textSelection(.enabled)
                            .padding(.top, 10)

                        HStack(spacing: 8) {
                            MiniAction(title: showValue ? "隐藏" : "显示完整 Key", icon: showValue ? "eye.slash" : "eye") {
                                withAnimation(.easeOut(duration: 0.18)) { showValue.toggle() }
                            }
                            MiniAction(title: copied ? "已复制" : "复制 Key", icon: copied ? "checkmark" : "doc.on.doc") {
                                model.copy(live.value, label: "Key 已复制")
                                copied = true
                            }
                            if live.id != model.assistantKeyID {
                                MiniAction(title: "设为当前", icon: "checkmark.circle") {
                                    model.selectAssistantKey(live.id)
                                }
                            }
                            Spacer(minLength: 0)
                        }
                        .padding(.top, 10)
                    }

                    SectionCard {
                        SectionTitle(title: "信息")

                        VStack(spacing: 0) {
                            detailRow("名称", live.name)
                            divider
                            detailRow("标识", live.id, mono: true)
                            divider
                            detailRow("状态", live.enabled ? "已启用" : "已停用")
                            if let expires = live.expiresAt, !expires.isEmpty {
                                divider
                                detailRow("到期", expires)
                            }
                            if let note = live.note, !note.isEmpty {
                                divider
                                detailRow("备注", note)
                            }
                        }
                        .padding(.top, 6)
                    }
                }
                .padding(16)
            }
            .scrollIndicators(.hidden)
            .background(AuroraBackdrop())
            .navigationTitle("Key 详情")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("关闭") { dismiss() }
                }
            }
        }
    }

    private var divider: some View {
        Rectangle().fill(Aurora.hairline).frame(height: 1)
    }

    private func detailRow(_ label: String, _ value: String, mono: Bool = false) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Text(label)
                .font(.system(size: 13))
                .foregroundStyle(Aurora.inkSoft)
                .frame(width: 72, alignment: .leading)
            Text(value)
                .font(mono ? .system(size: 11.5, design: .monospaced) : .system(size: 13))
                .foregroundStyle(Aurora.ink)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.vertical, 8)
    }

    private func mask(_ value: String) -> String {
        let text = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard text.count > 12 else { return text }
        return "\(text.prefix(7))…\(text.suffix(4))"
    }
}

// MARK: - 新建 Key

struct CreateGatewayKeySheet: View {

    @Environment(\.dismiss) private var dismiss

    /// 返回 nil 表示成功，返回文案表示失败原因
    var submit: (String) async -> String?

    @State private var name = ""
    @State private var error: String?
    @State private var working = false
    @FocusState private var focused: Bool

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    SectionCard {
                        SectionTitle(title: "名称")

                        TextField("例如：我的 Mac / iPhone 快捷指令", text: $name)
                            .font(.system(size: 14))
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .focused($focused)
                            .padding(.horizontal, 12)
                            .frame(height: 42)
                            .background(
                                RoundedRectangle(cornerRadius: 12, style: .continuous)
                                    .fill(Aurora.surfaceVariant)
                            )
                            .padding(.top, 10)

                        Text("名称只用来区分用途，随时可以在面板里改。创建后把这把 Key 填进客户端的 `x-api-key`。")
                            .font(.system(size: 11))
                            .foregroundStyle(Aurora.muted)
                            .fixedSize(horizontal: false, vertical: true)
                            .padding(.top, 8)

                        if let error {
                            Text(error)
                                .font(.system(size: 11.5))
                                .foregroundStyle(Aurora.rose)
                                .fixedSize(horizontal: false, vertical: true)
                                .padding(.top, 8)
                        }

                        MonoButton(
                            text: working ? "创建中…" : "创建",
                            icon: "plus.circle.fill",
                            style: .filled,
                            enabled: !working && !name.trimmingCharacters(in: .whitespaces).isEmpty
                        ) {
                            Task { await run() }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.top, 14)
                    }
                }
                .padding(16)
            }
            .scrollIndicators(.hidden)
            .background(AuroraBackdrop())
            .navigationTitle("新建 Key")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
            }
            .onAppear { focused = true }
        }
    }

    private func run() async {
        working = true
        error = nil
        let failure = await submit(name)
        working = false
        if let failure {
            error = failure
        } else {
            dismiss()
        }
    }
}
