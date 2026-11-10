import SwiftUI

// === Aurora UI 设计 token（彩色版）===
//
// 与 `aurora-ui` 技能的 Theme.kt / AuroraTheme.swift 一一对应，数值完全一致。
//
// 界面语言：
//   · 背景近白微冷（#F8F7FC），上面浮三团极淡的极光色晕
//   · 卡片是**不透明纯白**，靠描边与微阴影和背景分开（背景可以淡，内容必须实）
//   · 三色语义：靛蓝 brand = 主操作/选中，青 teal = 正常/成功，玫瑰 rose = 提醒/危险
//   · 按钮一律**透明玻璃**（见 `MonoButton`），颜色只出现在文字与图标上
//
// 不要再把这里改回单色：2.0.0 试过全站黑白，用户明确要求恢复彩色。

enum Aurora {

    // MARK: - 品牌三色

    /// 主色：主操作、选中态、强调文字、进度条
    static let brand = Color(hex: 0x4F46E5)
    /// 主色深：渐变起点、按下态
    static let brandDeep = Color(hex: 0x3730C0)
    /// 青：正常/成功的辅助色、次强调
    static let teal = Color(hex: 0x0F9D9D)
    /// 玫瑰：提醒、警示、删除类操作
    static let rose = Color(hex: 0xD6336C)

    // MARK: - 中性

    static let canvas = Color(hex: 0xF8F7FC)
    static let surface = Color.white
    static let ink = Color(hex: 0x17171F)
    static let inkSoft = Color(hex: 0x5C5C70)
    static let line = Color(hex: 0xE7E5F0)
    static let surfaceVariant = Color(hex: 0xEFEDF7)
    static let outline = Color(hex: 0xC6C3D6)

    // MARK: - 容器（Material 3 container 语义）

    static let brandContainer = Color(hex: 0xE5E2FF)
    static let onBrandContainer = Color(hex: 0x1B1464)
    static let tealContainer = Color(hex: 0xCAF2F1)
    static let onTealContainer = Color(hex: 0x003737)
    static let roseContainer = Color(hex: 0xFFD9E3)
    static let onRoseContainer = Color(hex: 0x3E0021)

    // MARK: - 语义

    static let success = Color(hex: 0x11875A)
    static let successContainer = Color(hex: 0xD8F5E8)
    static let warning = Color(hex: 0xB26A00)
    static let warningContainer = Color(hex: 0xFFEDCB)
    static let info = Color(hex: 0x2563EB)
    static let infoContainer = Color(hex: 0xDDE8FF)
    static let muted = Color(hex: 0x8A8AA0)
    static let hairline = Color(hex: 0xEFEDF6)
    static let danger = Color(hex: 0xC62828)

    // MARK: - 渐变（主 CTA / 概览头图）

    static let brandGradient = LinearGradient(
        colors: [Color(hex: 0x5B54F0), Color(hex: 0x8B5CF6)],
        startPoint: .leading,
        endPoint: .trailing
    )

    /// 概览头部：深一点、带方向的靛蓝渐变
    static let heroGradient = LinearGradient(
        colors: [Color(hex: 0x5B54F0), Color(hex: 0x4338CA)],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )

    // MARK: - 图表调色板

    /// 环形图/柱状图按顺序取色：靛蓝 → 青 → 玫瑰 → 紫 → 琥珀 → 蓝
    static let chartPalette: [Color] = [
        Color(hex: 0x4F46E5),
        Color(hex: 0x0F9D9D),
        Color(hex: 0xD6336C),
        Color(hex: 0x8B5CF6),
        Color(hex: 0xE8A33D),
        Color(hex: 0x2563EB)
    ]

    static func chartColor(_ index: Int) -> Color {
        chartPalette[index % chartPalette.count]
    }

    // MARK: - 阴影

    static let cardShadow = Color.black.opacity(0.05)
    static let barShadow = Color(red: 0.06, green: 0.06, blue: 0.16).opacity(0.10)
}

// MARK: - 字阶

/// 中文优先：层级靠字重拉开，不靠字号堆叠；中文标题带负字距，视觉更紧实。
enum AuroraFont {

    static let headlineMedium = Font.system(size: 28, weight: .bold)
    static let headlineSmall = Font.system(size: 24, weight: .bold)
    static let titleLarge = Font.system(size: 19, weight: .bold)
    static let titleMedium = Font.system(size: 16, weight: .semibold)
    static let titleSmall = Font.system(size: 14, weight: .semibold)
    static let bodyLarge = Font.system(size: 15, weight: .regular)
    static let bodyMedium = Font.system(size: 14, weight: .regular)
    static let bodySmall = Font.system(size: 12.5, weight: .regular)
    static let labelLarge = Font.system(size: 14, weight: .semibold)
    static let labelMedium = Font.system(size: 12, weight: .semibold)
    static let labelSmall = Font.system(size: 11, weight: .medium)
    /// 控件内文案：13pt 半粗，与 38pt 高的玻璃按钮配平
    static let controlLabel = Font.system(size: 13, weight: .semibold)
    /// 数值（等宽，避免轮询刷新时数字左右抖动）
    static let monoValue = Font.system(size: 22, weight: .bold, design: .monospaced)
    static let monoSmall = Font.system(size: 12, weight: .regular, design: .monospaced)
}

// MARK: - 间距与尺寸（8pt 网格）

enum AuroraMetrics {
    static let pagePadding: CGFloat = 14
    static let cardPadding: CGFloat = 16
    static let cardSpacing: CGFloat = 10
    static let listBottomInset: CGFloat = 40
    static let barBottomInset: CGFloat = 68
    static let primaryButtonHeight: CGFloat = 50
    /// 统一控件高度：文字自适应横向宽度，纵向统一到 38pt，视觉齐平
    static let controlButtonHeight: CGFloat = 38
    static let controlButtonHPadding: CGFloat = 16
    static let controlButtonIconSize: CGFloat = 14
    static let controlButtonIconSpacing: CGFloat = 7
    static let smallButtonHeight: CGFloat = controlButtonHeight
    static let iconButtonSize: CGFloat = 40
    /// 控件圆角：比卡片小一档，形成「大容器/小控件」的层次
    static let controlRadius: CGFloat = 14
}

// MARK: - 形状

enum AuroraShape {
    static let control = RoundedRectangle(cornerRadius: AuroraMetrics.controlRadius, style: .continuous)
    static let button = RoundedRectangle(cornerRadius: 16, style: .continuous)
    static let card = RoundedRectangle(cornerRadius: 20, style: .continuous)
    static let sheet = RoundedRectangle(cornerRadius: 24, style: .continuous)
    static let bar = RoundedRectangle(cornerRadius: 26, style: .continuous)
    static let badge = RoundedRectangle(cornerRadius: 12, style: .continuous)
}

// MARK: - 状态等级 → 颜色

func statusColor(_ level: Int) -> Color {
    switch level {
    case 1: return Aurora.info
    case 2: return Aurora.success
    case 3: return Aurora.warning
    case 4: return Aurora.danger
    default: return Aurora.muted
    }
}

// MARK: - 按压反馈

struct PressScaleStyle: ButtonStyle {
    var scale: CGFloat = 0.982

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? scale : 1)
            .animation(.spring(response: 0.28, dampingFraction: 0.72), value: configuration.isPressed)
    }
}
