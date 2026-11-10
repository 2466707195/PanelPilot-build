import SwiftUI

// === 无色玻璃（Liquid-Glass 风格的低版本实现）===
//
// 为什么不用 iOS 26 的 `glassEffect`：
//   部署目标是 16.4，CI 的 Xcode 也未必带 iOS 26 SDK，用了会直接编译失败
//   （`cannot find 'glassEffect' in scope`，@available 守卫救不了符号缺失）。
//   `.ultraThinMaterial` 从 iOS 15 就有，视觉上同样是「透出背景的磨砂玻璃」。
//
// 硬规则：玻璃层**不带品牌色**。颜色只出现在文字和图标上，
// 底色一律是材质 + 极淡白色高光，这样叠在极光背景上才是透明的。

/// 无色玻璃底：材质模糊 + 顶部白色高光 + 1pt 渐变描边 + 极轻投影。
///
/// `tint` 是**染色玻璃**：只叠一层很淡的品牌色（默认 14%），
/// 用来表达「这是当前选中的那个」，玻璃本体依然是透明的。
struct GlassSurface<S: InsettableShape>: View {

    var shape: S
    var strokeWidth: CGFloat = 1
    var shadowRadius: CGFloat = 10
    /// 白色高光强度。列表上的小控件可以调低，避免糊成一片白。
    var highlight: Double = 0.30
    /// 染色（主按钮 / 选中胶囊）。nil 表示纯无色玻璃。
    var tint: Color? = nil
    /// 染色强度
    var tintStrength: Double = 0.14

    var body: some View {
        shape
            .fill(.ultraThinMaterial)
            .overlay(
                shape.fill(
                    LinearGradient(
                        colors: [
                            Color.white.opacity(highlight),
                            Color.white.opacity(highlight * 0.18)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
            )
            .overlay(
                Group {
                    if let tint {
                        shape.fill(tint.opacity(tintStrength))
                    }
                }
            )
            .overlay(
                shape.strokeBorder(
                    LinearGradient(
                        colors: tint == nil
                            ? [Color.white.opacity(0.86), Color.white.opacity(0.28)]
                            : [tint!.opacity(0.42), Color.white.opacity(0.34)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: strokeWidth
                )
            )
            .shadow(color: Color.black.opacity(0.06), radius: shadowRadius, x: 0, y: 3)
    }
}

/// 玻璃胶囊按钮的容器尺寸（选中/未选中都用同一套，避免跳变）。
struct GlassCapsuleLabel<Content: View>: View {

    var horizontalPadding: CGFloat = 12
    var verticalPadding: CGFloat = 8
    var highlight: Double = 0.30
    @ViewBuilder var content: () -> Content

    var body: some View {
        content()
            .padding(.horizontal, horizontalPadding)
            .padding(.vertical, verticalPadding)
            .background(GlassSurface(shape: Capsule(), shadowRadius: 8, highlight: highlight))
            .contentShape(Capsule())
    }
}
