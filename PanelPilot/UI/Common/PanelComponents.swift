import SwiftUI

// === 面板通用组件（彩色 + 玻璃版）===
//
// 颜色全部来自 `Aurora` 的三色语义（靛蓝 / 青 / 玫瑰）+ 中性色。
// 按钮统一：**透明玻璃底**、高度 38pt、左右内边距 16pt、圆角 14pt、
// 宽度由文字决定；同一行里靠 `WrapLayout` 自动换行，视觉上齐平。

// MARK: - 标题

/// 区块标题。**不带任何辅助说明** —— 移动端只留标题本身。
struct SectionTitle: View {

    let title: String
    /// 兼容旧调用：传进来也不会渲染。
    var subtitle: String? = nil
    var trailing: String? = nil

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(title)
                .font(AuroraFont.labelSmall)
                .foregroundStyle(Aurora.inkSoft)
                .lineLimit(1)
            Spacer(minLength: 4)
            if let trailing, !trailing.isEmpty {
                Text(trailing)
                    .font(.system(size: 13))
                    .foregroundStyle(Aurora.muted)
                    .monospacedDigit()
            }
        }
    }
}

// MARK: - 指标块

struct MetricTile: View {

    let icon: String
    let title: String
    let value: String
    var detail: String? = nil
    var tint: Color = Aurora.brand

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 5) {
                Image(systemName: icon)
                    .font(.system(size: 12, weight: .light))
                    .foregroundStyle(Aurora.muted)
                Text(title)
                    .font(.system(size: 13))
                    .foregroundStyle(Aurora.inkSoft)
                    .lineLimit(1)
            }

            Text(value)
                .font(.system(size: 20, weight: .semibold))
                .foregroundStyle(Aurora.ink)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
                .monospacedDigit()

            if let detail, !detail.isEmpty {
                Text(detail)
                    .font(.system(size: 12))
                    .foregroundStyle(Aurora.muted)
                    .lineLimit(1)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 12)
        .padding(.vertical, 12)
        .background(
            RoundedRectangle(cornerRadius: AuroraMetrics.controlRadius, style: .continuous)
                .fill(Aurora.surfaceVariant)
        )
    }
}

// MARK: - 键值行

struct KeyValueRow: View {

    let label: String
    let value: String
    var mono: Bool = false

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Text(label)
                .font(AuroraFont.bodySmall)
                .foregroundStyle(Aurora.inkSoft)
                .frame(width: 96, alignment: .leading)

            Text(value)
                .font(mono ? AuroraFont.monoSmall : AuroraFont.bodySmall)
                .foregroundStyle(Aurora.ink)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.vertical, 7)
    }
}

/// 带分隔线的键值列表：把一串 `KeyValuePair` 直接铺开。
struct KeyValueList: View {

    let pairs: [KeyValuePair]

    var body: some View {
        VStack(spacing: 0) {
            ForEach(Array(pairs.enumerated()), id: \.element.id) { index, pair in
                if index > 0 {
                    Rectangle()
                        .fill(Aurora.hairline)
                        .frame(height: 1)
                }
                KeyValueRow(
                    label: pair.key,
                    value: pair.value,
                    mono: looksTechnical(pair.value)
                )
            }
        }
    }

    private func looksTechnical(_ value: String) -> Bool {
        if value.count > 24 { return false }
        let marks = ["http", "/", ":", "_", "sk-", "eyJ", "0x", "@"]
        return marks.contains { value.contains($0) }
    }
}

/// 指标矩阵：把扁平化的 JSON 铺成两列方块，字段再多也不会遗漏。
struct StatGrid: View {

    let pairs: [KeyValuePair]

    private var columns: [GridItem] {
        [GridItem(.flexible(), spacing: 8), GridItem(.flexible(), spacing: 8)]
    }

    var body: some View {
        LazyVGrid(columns: columns, alignment: .leading, spacing: 8) {
            ForEach(pairs) { pair in
                MetricTile(
                    icon: iconName(for: pair.key),
                    title: PanelFields.label(for: pair.key),
                    value: pair.value
                )
            }
        }
    }

    private func iconName(for key: String) -> String {
        let lower = key.lowercased()
        if lower.contains("token") { return "textformat.abc" }
        if lower.contains("request") || lower.contains("次数") { return "arrow.left.arrow.right" }
        if lower.contains("success") || lower.contains("成功率") { return "checkmark.circle" }
        if lower.contains("cost") || lower.contains("费用") || lower.contains("price") { return "yensign.circle" }
        if lower.contains("day") || lower.contains("天") { return "calendar" }
        if lower.contains("model") { return "cpu" }
        return "circle.dotted"
    }
}

// MARK: - 地址行

struct AddressRow: View {

    let label: String
    let value: String
    var onCopy: (String) -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            VStack(alignment: .leading, spacing: 4) {
                Text(label)
                    .font(AuroraFont.labelSmall)
                    .foregroundStyle(Aurora.muted)
                Text(value)
                    .font(AuroraFont.monoSmall)
                    .foregroundStyle(Aurora.ink)
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 6)
            MonoButton(text: "复制", icon: "doc.on.doc") { onCopy(value) }
        }
        .padding(.vertical, 8)
    }
}

// MARK: - 列表行

struct PanelListRow: View {

    let title: String
    var subtitle: String? = nil
    var trailing: String? = nil
    var icon: String = "circle"
    var tint: Color = Aurora.ink
    var onTap: (() -> Void)? = nil

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Aurora.muted)
                .frame(width: 18)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(AuroraFont.bodyMedium)
                    .foregroundStyle(Aurora.ink)
                    .lineLimit(2)
                if let subtitle, !subtitle.isEmpty {
                    Text(subtitle)
                        .font(AuroraFont.bodySmall)
                        .foregroundStyle(Aurora.muted)
                        .lineLimit(2)
                }
            }

            Spacer(minLength: 4)

            if let trailing, !trailing.isEmpty {
                Text(trailing)
                    .font(AuroraFont.labelSmall)
                    .foregroundStyle(Aurora.inkSoft)
                    .lineLimit(1)
            }

            if onTap != nil {
                Image(systemName: "chevron.right")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(Aurora.muted)
            }
        }
        .padding(.vertical, 9)
        .contentShape(Rectangle())
        .onTapGesture { onTap?() }
    }
}

/// 日志 / 记录行：等宽小字，正文不截断。
struct FeedRow: View {

    let title: String
    var detail: String? = nil
    var time: String? = nil
    var ok: Bool = true

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Circle()
                .fill(ok ? Aurora.success : Aurora.rose)
                .frame(width: 5, height: 5)
                .padding(.top, 6)

            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(AuroraFont.monoSmall)
                    .foregroundStyle(Aurora.ink)
                    .fixedSize(horizontal: false, vertical: true)
                if let detail, !detail.isEmpty {
                    Text(detail)
                        .font(.system(size: 11, weight: .regular, design: .monospaced))
                        .foregroundStyle(Aurora.inkSoft)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            Spacer(minLength: 4)

            if let time, !time.isEmpty {
                Text(time)
                    .font(AuroraFont.labelSmall)
                    .foregroundStyle(Aurora.muted)
                    .monospacedDigit()
            }
        }
        .padding(.vertical, 6)
    }
}

// MARK: - 错误卡

struct InlineErrorCard: View {

    let title: String
    let message: String
    var hint: String? = nil
    var actionTitle: String? = nil
    var action: (() -> Void)? = nil
    /// 语气：默认提醒（玫瑰），也可传成靛蓝的提示
    var tone: Color = Aurora.rose

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(spacing: 6) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 11, weight: .semibold))
                Text(title)
                    .font(AuroraFont.titleSmall)
            }
            .foregroundStyle(tone)

            Text(message)
                .font(AuroraFont.bodySmall)
                .foregroundStyle(Aurora.inkSoft)
                .fixedSize(horizontal: false, vertical: true)

            if let hint, !hint.isEmpty {
                Text(hint)
                    .font(AuroraFont.bodySmall)
                    .foregroundStyle(Aurora.muted)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if let actionTitle, let action {
                MonoButton(text: actionTitle, icon: "arrow.right", style: .filled, action: action)
                    .padding(.top, 2)
            }
        }
        .padding(13)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(tone.tint(0.06))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(tone.opacity(0.22), lineWidth: 1)
        )
    }
}

// MARK: - 明细列表

struct FlatDetailList: View {

    let pairs: [KeyValuePair]

    var body: some View {
        VStack(spacing: 0) {
            ForEach(Array(pairs.enumerated()), id: \.element.id) { index, pair in
                if index > 0 {
                    Rectangle()
                        .fill(Aurora.hairline)
                        .frame(height: 1)
                }
                HStack(alignment: .top, spacing: 10) {
                    Text(pair.key)
                        .font(.system(size: 11.5, weight: .medium, design: .monospaced))
                        .foregroundStyle(Aurora.inkSoft)
                        .frame(width: 108, alignment: .leading)
                    Text(pair.value)
                        .font(.system(size: 12, weight: .regular, design: .monospaced))
                        .foregroundStyle(Aurora.ink)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.vertical, 7)
            }
        }
    }
}

// MARK: - 命令块

struct CommandBlock: View {

    let text: String
    var onCopy: (String) -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Text(text)
                .font(.system(size: 11.5, weight: .regular, design: .monospaced))
                .foregroundStyle(Aurora.ink)
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)

            Button {
                onCopy(text)
            } label: {
                Image(systemName: "doc.on.doc")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Aurora.inkSoft)
                    .frame(width: 26, height: 26)
                    .background(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .fill(Aurora.surfaceVariant)
                    )
            }
            .buttonStyle(.plain)
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Aurora.surfaceVariant)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(Aurora.hairline, lineWidth: 1)
        )
    }
}

// MARK: - JSON 明细

struct JSONDetailSheet: View {

    let title: String
    var subtitle: String? = nil
    let json: JSONValue
    /// 针对这一行能做的动作（账号的设当前/刷新/签到等）
    var actions: [PanelActionSpec] = []
    var onAction: ((PanelActionSpec) -> Void)? = nil
    var onCopy: ((String) -> Void)? = nil

    @Environment(\.dismiss) private var dismiss
    @State private var raw = false

    private var pairs: [KeyValuePair] { json.flattened() }

    var body: some View {
        ZStack {
            AuroraBackdrop()

            VStack(spacing: 0) {
                HStack(spacing: 8) {
                    Text(title)
                        .font(AuroraFont.titleLarge)
                        .foregroundStyle(Aurora.ink)
                        .lineLimit(1)
                    Spacer(minLength: 4)
                    MonoButton(text: raw ? "字段" : "原始", icon: "curlybraces") {
                        raw.toggle()
                    }
                    GlassIconButton(systemIcon: "xmark", tint: Aurora.inkSoft, diameter: 30, iconSize: 12) {
                        dismiss()
                    }
                }
                .padding(.horizontal, 18)
                .padding(.top, 18)
                .padding(.bottom, 10)

                ScrollView {
                    VStack(alignment: .leading, spacing: 10) {
                        Group {
                            if raw {
                                Text(json.rawText)
                                    .font(.system(size: 11, weight: .regular, design: .monospaced))
                                    .foregroundStyle(Aurora.ink)
                                    .textSelection(.enabled)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            } else {
                                SmartFieldList(json: json, onCopy: onCopy)
                            }
                        }
                        .padding(14)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(
                            RoundedRectangle(cornerRadius: 16, style: .continuous)
                                .fill(Color.white)
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 16, style: .continuous)
                                .stroke(Aurora.line.opacity(0.6), lineWidth: 1)
                        )

                        if !actions.isEmpty, let onAction {
                            SectionCard {
                                SectionTitle(title: "操作")
                                WrapLayout(spacing: 8, lineSpacing: 8) {
                                    ForEach(actions) { action in
                                        MonoButton(
                                            text: action.title,
                                            icon: action.icon,
                                            style: action.confirm == nil ? .tonal : .outline
                                        ) {
                                            onAction(action)
                                        }
                                    }
                                }
                                .padding(.top, 8)
                            }
                        }

                        if let onCopy {
                            MonoButton(text: "复制全部字段", icon: "doc.on.doc", style: .outline) {
                                onCopy(json.rawText)
                            }
                        }
                    }
                    .padding(.horizontal, 14)
                    .padding(.bottom, 28)
                    .frame(maxWidth: 640)
                    .frame(maxWidth: .infinity)
                }
                .scrollIndicators(.hidden)
            }
        }
    }
}

// MARK: - 连接方式徽标

struct ModeBadge: View {

    let mode: ConnectionMode

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: mode.icon)
                .font(.system(size: 9, weight: .semibold))
            Text(mode.title)
                .font(AuroraFont.labelSmall)
        }
        .foregroundStyle(Aurora.inkSoft)
        .padding(.horizontal, 7)
        .padding(.vertical, 3)
        .background(Capsule().fill(Aurora.surfaceVariant))
    }
}

// MARK: - 呼吸点

struct PulseDot: View {

    var color: Color = Aurora.ink
    var size: CGFloat = 9
    var animated: Bool = true

    @State private var pulse = false

    var body: some View {
        ZStack {
            Circle()
                .fill(color.opacity(0.22))
                .frame(width: size * 2.1, height: size * 2.1)
                .scaleEffect(pulse ? 1 : 0.6)
                .opacity(pulse ? 0 : 1)

            Circle()
                .fill(color)
                .frame(width: size, height: size)
        }
        .onAppear {
            guard animated else { return }
            withAnimation(.easeOut(duration: 1.8).repeatForever(autoreverses: false)) {
                pulse = true
            }
        }
    }
}

// MARK: - 统一按钮

/// 全站唯一的按钮样式：**透明玻璃底**、宽度随文字、高 38、圆角 14。
///
/// 硬规则（用户指定）：
///   · 所有按钮都是透明玻璃 —— 不允许实心填充、不允许纯文字无底
///   · 层级只靠**文字颜色 + 玻璃染色深浅**区分，不靠色块
///   · 宽度由文字决定、纵向钉死 38pt，一行三四个按钮也能对齐
struct MonoButton: View {

    enum Style {
        /// 主操作：蓝底白字
        case filled
        /// 次操作：浅灰底黑字
        case tonal
        /// 弱操作：白底 + 0.5pt 细线
        case outline
        /// 纯文字：蓝色
        case plain
        /// 危险：红字
        case danger
    }

    let text: String
    var icon: String? = nil
    var style: Style = .tonal
    var enabled: Bool = true
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                if let icon {
                    Image(systemName: icon)
                        .font(.system(size: 13, weight: .regular))
                }
                Text(text)
                    .font(.system(size: 15, weight: .medium))
                    .lineLimit(1)
                    .fixedSize()
            }
            .foregroundStyle(foreground)
            .padding(.horizontal, AuroraMetrics.controlButtonHPadding)
            .frame(height: AuroraMetrics.controlButtonHeight)
            .background(background)
            .contentShape(AuroraShape.control)
        }
        .buttonStyle(PressScaleStyle())
        .disabled(!enabled)
        .opacity(enabled ? 1 : 0.38)
    }

    private var foreground: Color {
        switch style {
        case .filled: return .white
        case .tonal, .outline: return Aurora.ink
        case .plain: return Aurora.brand
        case .danger: return Aurora.danger
        }
    }

    @ViewBuilder
    private var background: some View {
        switch style {
        case .filled:
            AuroraShape.control.fill(Aurora.brand)
        case .tonal:
            AuroraShape.control.fill(Aurora.surfaceVariant)
        case .outline:
            AuroraShape.control
                .fill(Aurora.surface)
                .overlay(AuroraShape.control.stroke(Aurora.line, lineWidth: 0.5))
        case .plain, .danger:
            AuroraShape.control.fill(Color.clear)
        }
    }
}

// MARK: - 自动换行的按钮组

/// 一行放不下就换行，保证每个按钮宽度由自己的文字决定。
struct WrapLayout: Layout {

    var spacing: CGFloat = 8
    var lineSpacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let maxWidth = proposal.width ?? .infinity
        var rowWidth: CGFloat = 0
        var rowHeight: CGFloat = 0
        var totalHeight: CGFloat = 0
        var widestRow: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if rowWidth > 0, rowWidth + spacing + size.width > maxWidth {
                widestRow = max(widestRow, rowWidth)
                totalHeight += rowHeight + lineSpacing
                rowWidth = size.width
                rowHeight = size.height
            } else {
                rowWidth += (rowWidth > 0 ? spacing : 0) + size.width
                rowHeight = max(rowHeight, size.height)
            }
        }
        widestRow = max(widestRow, rowWidth)
        totalHeight += rowHeight
        return CGSize(width: min(widestRow, maxWidth), height: totalHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX
        var y = bounds.minY
        var rowHeight: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x > bounds.minX, x + size.width > bounds.maxX {
                x = bounds.minX
                y += rowHeight + lineSpacing
                rowHeight = 0
            }
            subview.place(at: CGPoint(x: x, y: y), anchor: .topLeading, proposal: ProposedViewSize(size))
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
    }
}

/// 一组动作按钮，自动换行。
struct ButtonWrap: View {

    let actions: [PanelActionSpec]
    var onTap: (PanelActionSpec) -> Void

    var body: some View {
        WrapLayout(spacing: 8, lineSpacing: 8) {
            ForEach(actions) { action in
                MonoButton(text: action.title, icon: action.icon, style: .outline) {
                    onTap(action)
                }
            }
        }
    }
}

// MARK: - 单选胶囊组

/// 一排玻璃胶囊：选中的那颗染一层淡淡的靛蓝，文字转靛蓝；
/// 未选中的保持无色玻璃 + 次级文字。整组都还是透明的。
struct SegmentedPills<T: Hashable>: View {

    let items: [T]
    let title: (T) -> String
    @Binding var selection: T
    /// 每个胶囊可带一枚图标（例如「今天 / 近 7 天」配日历）
    var icon: ((T) -> String)? = nil

    var body: some View {
        WrapLayout(spacing: 7, lineSpacing: 7) {
            ForEach(items, id: \.self) { item in
                let active = item == selection
                Button {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                        selection = item
                    }
                } label: {
                    HStack(spacing: 5) {
                        if let icon {
                            Image(systemName: icon(item))
                                .font(.system(size: 10.5, weight: .semibold))
                        }
                        Text(title(item))
                            .font(AuroraFont.controlLabel)
                            .lineLimit(1)
                    }
                    .foregroundStyle(active ? Aurora.ink : Aurora.inkSoft)
                    .padding(.horizontal, 14)
                    .frame(height: 32)
                    .background(
                        Capsule().fill(active ? Aurora.surface : Aurora.surfaceVariant)
                    )
                    .contentShape(Capsule())
                }
                .buttonStyle(PressScaleStyle(scale: 0.95))
            }
        }
    }
}

// MARK: - 原始 JSON 文本

extension JSONValue {

    /// 格式化后的原始 JSON，用于「原始」视图。
    var rawText: String {
        let any = toAny()
        if JSONSerialization.isValidJSONObject(any),
           let data = try? JSONSerialization.data(withJSONObject: any, options: [.prettyPrinted, .sortedKeys]),
           let text = String(data: data, encoding: .utf8) {
            return text
        }
        return displayText
    }

    private func toAny() -> Any {
        switch self {
        case .null:
            return NSNull()
        case .bool(let value):
            return value
        case .number(let value):
            return value
        case .string(let value):
            return value
        case .array(let items):
            return items.map { $0.toAny() }
        case .object(let dict):
            var result: [String: Any] = [:]
            for (key, value) in dict { result[key] = value.toAny() }
            return result
        }
    }
}
