import SwiftUI

// === 悬浮岛（底栏）===
//
// iOS 26+ 直接用系统的 **Liquid Glass**：`.glassEffect(.regular, in: Capsule())`。
// 玻璃是系统材质，会真的折射滚动到它下面的内容、跟随「降低透明度 / 提高对比度」
// 等辅助功能、也会跟着系统大版本更新 —— 自己铺 `.ultraThinMaterial` 永远只是
// 一层发灰的磨砂片，所以新系统上不要再自绘玻璃。
//
// 低版本（iOS 16.4–25）走 Material 兜底，视觉尽量接近。
//
// 交互：
//   · 点某一格 → 切页（`IslandTabBar` 里的按钮）
//   · **按住胶囊左右拖** → 选中项跟着手指连续移动，松手吸附到最近一格
//     （`DragGesture(minimumDistance: 6)` + `simultaneousGesture`，不影响点击）
//
// 位置：`AuroraMetrics.islandBottom` 控制离屏幕底边（不含安全区）的距离。

struct FloatingIsland<Content: View>: View {

    var bottomGap: CGFloat = AuroraMetrics.islandBottom
    @ViewBuilder var content: () -> Content

    @ObservedObject private var look = AppearanceStore.shared

    var body: some View {
        content()
            .padding(.horizontal, 6)
            .padding(.vertical, 8)
            .modifier(IslandSurface(alpha: look.islandAlpha))
            .padding(.horizontal, AuroraMetrics.pagePadding)
            .padding(.bottom, bottomGap)
    }
}

// MARK: - 玻璃底

private struct IslandSurface: ViewModifier {

    var alpha: Double

    private var shape: Capsule { Capsule(style: .continuous) }

    func body(content: Content) -> some View {
        if #available(iOS 26.0, *) {
            // 原生 Liquid Glass。不要再叠 fill / 描边 / 阴影：那样会把折射盖掉。
            content
                .glassEffect(.regular, in: shape)
                .contentShape(shape)
        } else {
            content
                .background(
                    shape
                        .fill(.ultraThinMaterial)
                        .overlay(shape.fill(Aurora.surface.opacity(alpha * 0.7)))
                )
                .overlay(shape.strokeBorder(Aurora.ink.opacity(0.05), lineWidth: 0.5))
                .shadow(color: Color.black.opacity(0.10), radius: 22, x: 0, y: 12)
                .contentShape(shape)
        }
    }
}

// MARK: - Tab 行

struct IslandTabBar: View {

    @Binding var selection: PanelTab

    private let tabs: [PanelTab] = [.overview, .routing, .agent, .accounts, .settings]

    /// 拖动中的连续位置（0 … tabs.count-1）；松手后置 nil，回到按选中项计算
    @State private var dragPosition: CGFloat?
    @State private var barWidth: CGFloat = 0

    private var count: CGFloat { CGFloat(tabs.count) }
    private var segment: CGFloat { barWidth > 0 ? barWidth / count : 0 }

    private var activeIndex: CGFloat {
        guard let index = tabs.firstIndex(of: selection) else { return 0 }
        return CGFloat(index)
    }

    /// 胶囊当前落点：拖动时跟手指，平时跟选中项
    private var position: CGFloat {
        min(max(dragPosition ?? activeIndex, 0), count - 1)
    }

    var body: some View {
        ZStack(alignment: .leading) {
            // 选中胶囊：比玻璃再深一点，才看得出「选中了哪一格」
            if segment > 0 {
                Capsule(style: .continuous)
                    .fill(Aurora.ink.opacity(0.08))
                    .frame(width: max(segment - 6, 8), height: 54)
                    .offset(x: position * segment + 3)
                    .allowsHitTesting(false)
            }

            HStack(spacing: 0) {
                ForEach(tabs) { tab in
                    let active = selection == tab
                    Button {
                        withAnimation(.spring(response: 0.34, dampingFraction: 0.82)) {
                            selection = tab
                            dragPosition = nil
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
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(IslandTabStyle())
                    .accessibilityLabel(tab.title)
                    .accessibilityAddTraits(active ? [.isSelected] : [])
                }
            }
        }
        .background(
            GeometryReader { geo in
                Color.clear
                    .onAppear { barWidth = geo.size.width }
                    .onChange(of: geo.size.width) { width in barWidth = width }
            }
        )
        .contentShape(Rectangle())
        // 用 simultaneous：点击仍然交给上面的按钮，拖动才走这里
        .simultaneousGesture(dragGesture)
        .animation(.spring(response: 0.34, dampingFraction: 0.82), value: selection)
    }

    // MARK: 拖动

    private var dragGesture: some Gesture {
        DragGesture(minimumDistance: 6)
            .onChanged { value in
                guard segment > 0 else { return }
                let raw = (value.location.x - segment / 2) / segment
                let clamped = min(max(raw, 0), count - 1)
                dragPosition = clamped
                // 边走边点亮图标，但不动画（胶囊已经在跟手了，再动画会打架）
                let index = Int(clamped.rounded())
                if tabs.indices.contains(index), tabs[index] != selection {
                    selection = tabs[index]
                }
            }
            .onEnded { _ in
                guard segment > 0 else { return }
                let target = Int((dragPosition ?? activeIndex).rounded())
                let clamped = min(max(target, 0), tabs.count - 1)
                withAnimation(.spring(response: 0.34, dampingFraction: 0.82)) {
                    selection = tabs[clamped]
                    dragPosition = nil
                }
            }
    }
}

/// 按下时只把图标压小一点点，不做整块变灰（玻璃本身已经有按压反馈）。
private struct IslandTabStyle: ButtonStyle {

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.94 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}
