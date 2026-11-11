import SwiftUI

// === 目录驱动的通用渲染层 ===
//
// 一个区块 = 标题 + 动作行 + 内容。内容长什么样由 `PanelSectionStyle` 决定，
// 但**不认识任何业务字段名**：键值走 `PanelFields` 翻译 + 分组，列表靠候选键取标题。
// 这样服务器新增字段会自动多一行，字段改名最多显示「—」，不会白屏；
// 同时用户看到的是「数据库大小 2.1 MB」而不是「deployment.dbBytes 2236416」。

// MARK: - 数值美化

enum PanelFormat {

    /// 数字按整数/小数分开处理，大数加千分位；其余走 JSON 的默认文本。
    static func value(_ json: JSONValue) -> String {
        switch json {
        case .number(let raw):
            if raw.rounded() == raw, abs(raw) < 1e15 {
                let formatter = NumberFormatter()
                formatter.numberStyle = .decimal
                formatter.maximumFractionDigits = 0
                return formatter.string(from: NSNumber(value: raw)) ?? "\(Int(raw))"
            }
            if abs(raw) < 1 {
                return String(format: "%.4f", raw)
            }
            return String(format: "%.2f", raw)
        case .string(let text):
            return text.isEmpty ? "—" : text
        case .bool(let flag):
            return flag ? "是" : "否"
        case .null:
            return "—"
        case .array(let items):
            return "\(items.count) 项"
        case .object:
            return "对象"
        }
    }

    /// 列表行标题：按候选键依次取，全落空就用序号。
    static func title(_ row: JSONValue, keys: [String], fallback: String) -> String {
        for key in keys {
            if let text = row.str(key), !text.isEmpty { return text }
            if let number = row.int(key) { return "\(number)" }
        }
        if let id = row.firstString(["id", "uuid", "key"]) { return id }
        // 还没命中：从对象里挑第一个「像名字」的字符串。
        // 否则一屏全是「第 1 项 →」「第 2 项 →」，标题等于没写。
        if let dict = row.objectValue {
            let skip: Set<String> = [
                "enabled", "disabled", "status", "state", "ok", "success",
                "type", "kind", "id", "uuid", "key", "createdat", "updatedat"
            ]
            for pair in dict.sorted(by: { $0.key < $1.key }) {
                guard !skip.contains(pair.key.lowercased()) else { continue }
                if let text = pair.value.stringValue,
                   !text.isEmpty, text.count <= 60, text != "0" {
                    return text
                }
            }
        }
        return fallback
    }

    /// 列表行副标题：把最有信息量的两三个标量拼起来。
    ///
    /// 键名先过一遍字段字典，避免出现「provider openai · plan free」这种中英混排。
    static func subtitle(_ row: JSONValue, skipping keys: [String]) -> String? {
        guard let dict = row.objectValue else { return nil }
        var parts: [String] = []
        let preferred = [
            "email", "displayName", "provider", "plan", "type", "model",
            "priority", "group", "url", "host", "port", "expiresAt", "createdAt"
        ]
        for key in preferred where !keys.contains(key) {
            guard let value = dict[key] else { continue }
            switch value {
            case .string(let text) where !text.isEmpty:
                parts.append("\(PanelFields.label(for: key)) \(text)")
            case .number(let number):
                parts.append("\(PanelFields.label(for: key)) \(PanelFormat.value(.number(number)))")
            case .bool(let flag):
                parts.append("\(PanelFields.label(for: key)) \(flag ? "是" : "否")")
            default:
                continue
            }
            if parts.count >= 2 { break }
        }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    /// 状态胶囊：优先布尔 `enabled`，其次字符串 `status`。
    static func status(_ row: JSONValue, keys: [String]) -> (text: String, on: Bool)? {
        for key in keys {
            if let flag = row.bool(key) {
                return (flag ? "启用" : "停用", flag)
            }
            if let text = row.str(key), !text.isEmpty {
                let lower = text.lowercased()
                let off = ["disabled", "off", "error", "failed", "invalid", "expired", "stopped"]
                let on = ["ok", "active", "on", "ready", "running", "healthy", "success", "enabled"]
                if off.contains(where: { lower.contains($0) }) { return (text, false) }
                if on.contains(where: { lower.contains($0) }) { return (text, true) }
                return (text, true)
            }
        }
        return nil
    }

    static func timeText(_ row: JSONValue) -> String? {
        for key in ["time", "timestamp", "createdAt", "at", "date"] {
            guard let raw = row.value(key) else { continue }
            if case .number(let stamp) = raw {
                let seconds = stamp > 1e12 ? stamp / 1000 : stamp
                if seconds > 1e9 {
                    return Date(timeIntervalSince1970: seconds).formatted("HH:mm:ss")
                }
            }
            if case .string(let text) = raw, !text.isEmpty {
                return text.count > 19 ? String(text.suffix(8)) : text
            }
        }
        return nil
    }
}

// MARK: - 区块

/// `sheet(item:)` 要 `Identifiable`，JSON 本身没有 id，这里包一层。
struct JSONSheetItem: Identifiable {
    let id = UUID()
    let value: JSONValue
    var title: String? = nil
}

struct DataSection: View {

    @EnvironmentObject private var model: AppModel

    let page: PanelPage
    let section: PanelSectionSpec

    @State private var detail: JSONSheetItem?

    private var data: SectionData { model.data(page: page, section: section) }
    private var rows: [JSONValue] { model.rows(page: page, section: section) }
    private var scalars: [KeyValuePair] { model.scalars(page: page, section: section) }

    private var rowActions: [PanelActionSpec] {
        section.actions.filter { $0.usesRow }
    }
    private var globalActions: [PanelActionSpec] {
        section.actions.filter { !$0.usesRow }
    }

    var body: some View {
        SectionCard {
            header

            if section.collapsed && !model.isExpanded(page, section) {
                collapsedHint
            } else {
                content
            }
        }
        .sheet(item: $detail) { item in
            JSONDetailSheet(
                title: section.title,
                json: item.value,
                actions: rowActions,
                onAction: { action in
                    Task {
                        await model.perform(
                            action: action,
                            page: page,
                            section: section,
                            row: item.value
                        )
                    }
                },
                onCopy: { text in model.copy(text) }
            )
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                SectionTitle(title: section.title, trailing: trailingText)

                // 断网 / 后台时，明确标出这一块来自磁盘快照而不是刚拿回来的
                if data.json != nil, !model.state.isOnline {
                    StatusPill(text: "本地", color: Aurora.inkSoft)
                }

                if section.collapsed {
                    Image(systemName: model.isExpanded(page, section) ? "chevron.up" : "chevron.down")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(Aurora.muted)
                } else if data.loading {
                    ProgressView()
                        .controlSize(.mini)
                        .tint(Aurora.inkSoft)
                }
            }
            .contentShape(Rectangle())
            .onTapGesture {
                if section.collapsed { model.toggleExpanded(page, section) }
            }

            if !globalActions.isEmpty {
                ButtonWrap(actions: globalActions) { action in
                    Task { await model.perform(action: action, page: page, section: section) }
                }
            }
        }
    }

    private var trailingText: String? {
        if section.collapsed && !model.isExpanded(page, section) { return "点击展开" }
        if !rows.isEmpty { return "\(rows.count)" }
        guard let stamp = data.fetchedAt else { return data.loading ? "读取中" : nil }
        return stamp.formatted("HH:mm:ss")
    }

    private var collapsedHint: some View {
        Text(data.error == nil ? "已收起" : "已收起 · 上次读取失败")
            .font(AuroraFont.bodySmall)
            .foregroundStyle(Aurora.muted)
            .padding(.top, 6)
    }

    @ViewBuilder
    private var content: some View {
        if let error = data.error, data.json == nil {
            InlineErrorCard(
                title: "读取失败",
                message: error,
                hint: nil,
                actionTitle: "重试",
                action: { Task { await model.load(page: page, force: true, only: [section.id]) } }
            )
            .padding(.top, 8)
        } else if data.json == nil {
            Text(data.loading ? "读取中…" : "还没有数据")
                .font(AuroraFont.bodySmall)
                .foregroundStyle(Aurora.muted)
                .padding(.top, 6)
        } else {
            VStack(alignment: .leading, spacing: 8) {
                if let error = data.error {
                    Text("这次没读到：\(error)")
                        .font(AuroraFont.bodySmall)
                        .foregroundStyle(Aurora.muted)
                }
                body(for: section.style)
            }
            .padding(.top, 8)
        }
    }

    @ViewBuilder
    private func body(for style: PanelSectionStyle) -> some View {
        switch style {
        case .stats:
            if scalars.isEmpty {
                empty
            } else {
                StatGrid(pairs: scalars)
            }
        case .kv:
            if let json = data.json {
                SmartFieldList(json: json, onCopy: { text in model.copy(text) })
            } else {
                empty
            }
        case .rows:
            rowList
        case .feed:
            feedList
        case .auto:
            if rows.isEmpty {
                if let json = data.json {
                    SmartFieldList(json: json, onCopy: { text in model.copy(text) })
                } else {
                    empty
                }
            } else {
                VStack(alignment: .leading, spacing: 12) {
                    if let json = data.json, !scalars.isEmpty {
                        SmartFieldList(
                            json: json,
                            collapsedLimit: 4,
                            onCopy: { text in model.copy(text) }
                        )
                    }
                    rowList
                }
            }
        }
    }

    private var empty: some View {
        Text(section.emptyText)
            .font(AuroraFont.bodySmall)
            .foregroundStyle(Aurora.muted)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, 6)
    }

    @ViewBuilder
    private var rowList: some View {
        if rows.isEmpty {
            empty
        } else {
            VStack(spacing: 0) {
                ForEach(Array(rows.enumerated()), id: \.offset) { index, row in
                    if index > 0 {
                        Rectangle().fill(Aurora.hairline).frame(height: 1)
                    }
                    PanelListRow(
                        title: PanelFormat.title(
                            row,
                            keys: section.titleKeys,
                            fallback: "第 \(index + 1) 项"
                        ),
                        subtitle: PanelFormat.subtitle(row, skipping: section.titleKeys),
                        trailing: PanelFormat.status(row, keys: section.statusKeys)?.text,
                        icon: PanelFormat.status(row, keys: section.statusKeys)?.on == false
                            ? "circle.dashed" : "circle.fill",
                        onTap: { detail = JSONSheetItem(value: row) }
                    )
                }
            }
        }
    }

    @ViewBuilder
    private var feedList: some View {
        if rows.isEmpty {
            empty
        } else {
            VStack(spacing: 0) {
                ForEach(Array(rows.enumerated()), id: \.offset) { index, row in
                    if index > 0 {
                        Rectangle().fill(Aurora.hairline).frame(height: 1)
                    }
                    FeedRow(
                        title: PanelFormat.title(
                            row,
                            keys: section.titleKeys,
                            fallback: "记录 \(index + 1)"
                        ),
                        detail: PanelFormat.subtitle(row, skipping: section.titleKeys),
                        time: PanelFormat.timeText(row),
                        ok: PanelFormat.status(row, keys: ["status", "ok", "success"])?.on ?? true
                    )
                    .contentShape(Rectangle())
                    .onTapGesture { detail = JSONSheetItem(value: row) }
                }
            }
        }
    }
}

// MARK: - 行详情

struct RowDetailSheet: View {

    let title: String
    let json: JSONValue

    var body: some View {
        JSONDetailSheet(title: title, json: json)
    }
}

// MARK: - 页面骨架

/// 一级页面：标题 + 刷新 + 内容。
///
/// 标题**不带副标题**：移动端顶栏只保留主标题，说明性文字全部移除。
struct PanelPageShell<Content: View>: View {

    @EnvironmentObject private var model: AppModel

    let title: String
    var onLoad: (() -> Void)? = nil
    @ViewBuilder var content: () -> Content

    var body: some View {
        ZStack {
            AuroraBackdrop()

            VStack(spacing: 0) {
                AppTopBar(title: title) {
                    HStack(spacing: 6) {
                        ServerChip()
                        StatusPill(text: model.state.title, color: model.state.tint)
                        GlassIconButton(
                            systemIcon: "arrow.clockwise",
                            tint: Aurora.inkSoft,
                            diameter: 30,
                            iconSize: 12
                        ) {
                            Task { await model.refreshAll() }
                        }
                    }
                }

                ScrollView {
                    VStack(alignment: .leading, spacing: AuroraMetrics.cardSpacing) {
                        content()
                    }
                    .padding(.horizontal, AuroraMetrics.pagePadding)
                    .padding(.top, 4)
                    .padding(.bottom, AuroraMetrics.listBottomInset)
                    .frame(maxWidth: 640)
                    .frame(maxWidth: .infinity)
                }
                .scrollIndicators(.hidden)
                .refreshable { await model.refreshAll() }
            }
        }
        .onAppear { onLoad?() }
    }
}
