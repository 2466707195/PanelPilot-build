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
                    .font(.system(size: 13, weight: .regular))
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
                    .font(.system(size: 11, weight: .light))
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
                .buttonStyle(PressScaleStyle())
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
