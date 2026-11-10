import SwiftUI

// === 设计 token：iOS Native Minimal ===
//
// 这一版按 `ios-native-minimal` 技能重做视觉：
//   · 底层 #F2F2F7 浅灰，上面全部是**实白 20pt 圆角**容器，不投影、不描边、不用毛玻璃
//   · 只用两档圆角：外层 20 / 内层 14；胶囊 = 高度的一半
//   · 彩色稀缺：#007AFF 只给链接与选中态，用户气泡 #FCE8F0，其余黑白灰
//   · 底部是**离开屏幕底边 26pt 的白色浮岛**（见 `FloatingIsland`），不是贴底 TabBar
//
// `Aurora*` 这层名字保留下来，是为了不把上百个调用点全改一遍；
// 数值已经 1:1 对齐 `NativeUI`，两套 token 同源，页面里不要再写十六进制。

enum Aurora {

    // MARK: - 唯一强调色

    /// 链接、可点文字、选中态、主按钮
    static let brand = Color(hex: 0x007AFF)
    /// 按下态
    static let brandDeep = Color(hex: 0x0062CC)
    /// 成功圆点（只在状态点用）
    static let teal = Color(hex: 0x34C759)
    /// 删除类
    static let rose = Color(hex: 0xFF3B30)

    // MARK: - 中性

    /// 全屏底色
    static let canvas = Color(hex: 0xF2F2F7)
    static let surface = Color.white
    /// 主文字
    static let ink = Color.black
    /// 次要文字
    static let inkSoft = Color(hex: 0x666666)
    /// 细线
    static let line = Color(hex: 0xE9E9EE)
    /// 浅灰控件底（输入框、次按钮、胶囊槽）
    static let surfaceVariant = Color(hex: 0xE9E9EE)
    /// 更深一档的灰（按下态）
    static let outline = Color(hex: 0xDFDFE5)

    // MARK: - 容器（保留旧名，值统一收敛到灰阶）

    static let brandContainer = Color(hex: 0xE9E9EE)
    static let onBrandContainer = Color(hex: 0x007AFF)
    static let tealContainer = Color(hex: 0xE9E9EE)
    static let onTealContainer = Color(hex: 0x1C1C1E)
    static let roseContainer = Color(hex: 0xFFE5E3)
    static let onRoseContainer = Color(hex: 0xFF3B30)

    // MARK: - 语义

    static let success = Color(hex: 0x34C759)
    static let successContainer = Color(hex: 0xE9E9EE)
    static let warning = Color(hex: 0x666666)
    static let warningContainer = Color(hex: 0xE9E9EE)
    static let info = Color(hex: 0x007AFF)
    static let infoContainer = Color(hex: 0xE9E9EE)
    static let muted = Color(hex: 0x9A9AA0)
    static let hairline = Color(hex: 0xE9E9EE)
    static let danger = Color(hex: 0xFF3B30)

    // MARK: - 用户气泡

    static let userBubble = Color(hex: 0xFCE8F0)

    // MARK: - 渐变（这套风格不用渐变，保留 API 只为兼容；返回纯白）

    static let brandGradient = LinearGradient(
        colors: [Color.white, Color.white],
        startPoint: .leading,
        endPoint: .trailing
    )

    static let heroGradient = LinearGradient(
        colors: [Color.white, Color.white],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )

    // MARK: - 图表：单色蓝的透明度阶梯

    static let chartPalette: [Color] = [
        Color(hex: 0x007AFF),
        Color(hex: 0x007AFF).opacity(0.72),
        Color(hex: 0x007AFF).opacity(0.52),
        Color(hex: 0x007AFF).opacity(0.36),
        Color(hex: 0x007AFF).opacity(0.24),
        Color(hex: 0x007AFF).opacity(0.14)
    ]

    static func chartColor(_ index: Int) -> Color {
        chartPalette[index % chartPalette.count]
    }

    // MARK: - 阴影（全屏只允许浮岛那一层）

    static let cardShadow = Color.clear
    static let barShadow = Color.black.opacity(0.06)
}

// MARK: - 字阶（SF Pro，四档为主）

enum AuroraFont {

    /// 34 bold —— 主页面大标题
    static let headlineMedium = Font.system(size: 34, weight: .bold)
    static let headlineSmall = Font.system(size: 28, weight: .bold)
    /// 22 bold —— 卡片里的主数值旁边那种大号标题
    static let titleLarge = Font.system(size: 22, weight: .bold)
    /// 17 semibold —— 子页标题 / 卡片主标题
    static let titleMedium = Font.system(size: 17, weight: .semibold)
    /// 16 semibold
    static let titleSmall = Font.system(size: 16, weight: .semibold)
    static let bodyLarge = Font.system(size: 17, weight: .regular)
    /// 16 regular —— 正文
    static let bodyMedium = Font.system(size: 16, weight: .regular)
    /// 14 regular —— 次要
    static let bodySmall = Font.system(size: 14, weight: .regular)
    static let labelLarge = Font.system(size: 14, weight: .medium)
    static let labelMedium = Font.system(size: 12, weight: .medium)
    /// 13 semibold —— 分区小标题
    static let labelSmall = Font.system(size: 13, weight: .semibold)
    /// 16 medium —— 按钮
    static let controlLabel = Font.system(size: 16, weight: .medium)
    /// 数字（等宽）
    static let monoValue = Font.system(size: 22, weight: .semibold, design: .monospaced)
    static let monoSmall = Font.system(size: 13, weight: .regular, design: .monospaced)
}

// MARK: - 间距与尺寸

enum AuroraMetrics {
    /// 页面左右边距（浮岛同值）
    static let pagePadding: CGFloat = 16
    static let cardPadding: CGFloat = 16
    /// 卡片组之间
    static let cardSpacing: CGFloat = 16
    /// 内容底部留白：浮岛高度 + 24
    static let listBottomInset: CGFloat = 128
    static let barBottomInset: CGFloat = 68
    static let primaryButtonHeight: CGFloat = 50
    static let controlButtonHeight: CGFloat = 36
    static let controlButtonHPadding: CGFloat = 14
    static let controlButtonIconSize: CGFloat = 14
    static let controlButtonIconSpacing: CGFloat = 6
    static let smallButtonHeight: CGFloat = controlButtonHeight
    static let iconButtonSize: CGFloat = 40
    /// 内层控件圆角
    static let controlRadius: CGFloat = 14
    /// 外层卡片圆角
    static let cardRadius: CGFloat = 20
    /// 浮岛离屏幕底边（不含安全区）
    static let islandBottom: CGFloat = 26
}

// MARK: - 形状

enum AuroraShape {
    static let control = RoundedRectangle(cornerRadius: AuroraMetrics.controlRadius, style: .continuous)
    static let button = RoundedRectangle(cornerRadius: AuroraMetrics.controlRadius, style: .continuous)
    static let card = RoundedRectangle(cornerRadius: AuroraMetrics.cardRadius, style: .continuous)
    static let sheet = RoundedRectangle(cornerRadius: AuroraMetrics.cardRadius, style: .continuous)
    static let bar = RoundedRectangle(cornerRadius: AuroraMetrics.cardRadius, style: .continuous)
    static let badge = RoundedRectangle(cornerRadius: 12, style: .continuous)
}

// MARK: - 状态等级 → 颜色（只剩灰、蓝、红）

func statusColor(_ level: Int) -> Color {
    switch level {
    case 1, 2: return Aurora.success
    case 3: return Aurora.warning
    case 4: return Aurora.danger
    default: return Aurora.muted
    }
}

// MARK: - 按压反馈

struct PressScaleStyle: ButtonStyle {
    var scale: CGFloat = 0.97

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? scale : 1)
            .opacity(configuration.isPressed ? 0.9 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}
