import SwiftUI

// === 悬浮岛（底栏）===
//
// 视觉语言取自 Aurora UI：**全胶囊**容器（圆角 = 高度的一半）、实白、一层极淡描边，
// 唯一一层柔和投影；选中项是一枚会滑动的浅墨胶囊 + 稍粗的字重。
//
// 与之前那版（20pt 圆角方盒 + 纯文字变色）的区别：
//   · 形状 20pt 圆角 → 全胶囊，行高 54、图标 21、标签 10.5；
//   · 选中态多了一枚 ink 6% 的滑动胶囊（`matchedGeometryEffect`），
//     切换时从上一格滑过去，而不是整条一起淡入淡出；
//   · 底色跟随「设置 → 显示 → 外观」的不透明度（透明 ↔ 色调）。
//
// 仍然只有这一个浮块：不要把输入框、工具条再做第二个浮块塞进来。

struct FloatingIsland<Content: View>: View {

    var bottomGap: CGFloat = AuroraMetrics.islandBottom
    @ViewBuilder var content: () -> Content

    @ObservedObject private var look = AppearanceStore.shared

    private var shape: Capsule { Capsule(style: .continuous) }

    var body: some View {
        content()
            .padding(.horizontal, 6)
            .padding(.vertical, 8)
            .background(
                shape
                    .fill(Aurora.surface.opacity(look.islandAlpha))
                    .overlay(
                        shape.strokeBorder(Aurora.ink.opacity(0.05), lineWidth: 0.5)
                    )
                    .shadow(color: Color.black.opacity(0.10), radius: 22, x: 0, y: 12)
            )
            .padding(.horizontal, AuroraMetrics.pagePadding)
            .padding(.bottom, bottomGap)
            .contentShape(shape)
    }
}

// MARK: - Tab 行

struct IslandTabBar: View {

    @Binding var selection: PanelTab

    @Namespace private var pill

    private let tabs: [PanelTab] = [.overview, .routing, .agent, .accounts, .settings]

    var body: some View {
        HStack(spacing: 2) {
            ForEach(tabs) { tab in
                let active = selection == tab
                Button {
                    withAnimation(.spring(response: 0.36, dampingFraction: 0.82)) {
                        selection = tab
                    }
                } label: {
                    VStack(spacing: 5) {
                        Image(systemName: tab.icon)
                            .font(.system(size: 21, weight: active ? .medium : .light))
                            .frame(height: 23)
                        Text(tab.title)
                            .font(.system(size: 10.5, weight: active ? .semibold : .medium))
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                    }
                    .foregroundStyle(active ? Aurora.ink : Aurora.muted)
                    .frame(maxWidth: .infinity)
                    .frame(height: 54)
                    .background {
                        if active {
                            Capsule(style: .continuous)
                                .fill(Aurora.ink.opacity(0.06))
                                .matchedGeometryEffect(id: "island.pill", in: pill)
                        }
                    }
                    .contentShape(Capsule(style: .continuous))
                }
                .buttonStyle(IslandTabStyle())
                .accessibilityLabel(tab.title)
                .accessibilityAddTraits(active ? [.isSelected] : [])
            }
        }
        .animation(.spring(response: 0.36, dampingFraction: 0.82), value: selection)
    }
}

/// 按下时只把图标压小一点点，不做整块变灰（胶囊本身已经很轻）。
private struct IslandTabStyle: ButtonStyle {

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.94 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}
