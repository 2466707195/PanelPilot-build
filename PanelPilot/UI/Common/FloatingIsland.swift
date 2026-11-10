import SwiftUI

// === 悬浮岛（底栏）===
//
// 容器：iOS 26+ 用系统 **Liquid Glass**（`.glassEffect(.regular, in: Capsule())`），
// 低版本用 `ultraThinMaterial` 兜底。玻璃分支不叠 fill / 描边 / 阴影 —— 叠了就没有折射。
//
// 选中项：一枚**会拉伸的毛玻璃透镜**（不是纯色胶囊）。它的几何按「起点格 → 手指/目标格」
// 算出来：
//   · 静止时 = 一格宽；
//   · 拖动时 = 从原格一路拉长到手指，松手再回弹成一格；
//   · 点击时 = 先撑开一点再落位（`tapStretch`），有那种「液滴被拉过去」的感觉。
// 透镜本身是 material + 半透白 + 极淡描边 + 轻投影，所以压在系统玻璃上还能分出层次。
//
// 交互：点某一格切页；**按住透镜左右拖**可连续选（`DragGesture` + `simultaneousGesture`，
// 不影响点击）。拖动只改高亮，松手才真正切页，避免连续拖时反复挂载页面。

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

    private let barHeight: CGFloat = 54
    private let lensHeight: CGFloat = 46

    /// 拖动中的连续位置（0 … tabs.count-1）；松手后置 nil，回到按选中项计算
    @State private var dragPosition: CGFloat?
    /// 点击切换时给透镜的额外宽度，落位后回 0（形成「撑开—收拢」）
    @State private var tapStretch: CGFloat = 0
    @State private var barWidth: CGFloat = 0

    private var count: CGFloat { CGFloat(tabs.count) }
    private var segment: CGFloat { barWidth > 0 ? barWidth / count : 0 }

    private var activeIndex: CGFloat {
        guard let index = tabs.firstIndex(of: selection) else { return 0 }
        return CGFloat(index)
    }

    private var position: CGFloat {
        min(max(dragPosition ?? activeIndex, 0), count - 1)
    }

    /// 拖动中高亮的那一格。只影响视觉，真正切页在松手时。
    private var highlightedIndex: Int {
        let raw = dragPosition ?? activeIndex
        return min(max(Int(raw.rounded()), 0), tabs.count - 1)
    }

    private var baseWidth: CGFloat { segment > 0 ? max(segment - 10, 24) : 0 }

    /// 透镜的位置与宽度：静止 = 一格；拖动 = 从原格拉长到手指；点击 = 撑一下再回弹。
    private var lens: (x: CGFloat, width: CGFloat) {
        guard segment > 0 else { return (0, 0) }
        let originCenter = activeIndex * segment + segment / 2
        let fingerCenter = position * segment + segment / 2
        let travel = abs(fingerCenter - originCenter)
        let width = min(baseWidth + travel * 0.9 + tapStretch, segment * 2.2)
        let center = dragPosition == nil ? fingerCenter : (originCenter + fingerCenter) / 2
        return (center - width / 2, width)
    }

    var body: some View {
        ZStack(alignment: .topLeading) {
            if segment > 0 {
                lensView
                    .frame(width: lens.width, height: lensHeight)
                    .offset(x: lens.x, y: (barHeight - lensHeight) / 2)
                    .allowsHitTesting(false)
            }

            HStack(spacing: 0) {
                ForEach(Array(tabs.enumerated()), id: \.element.id) { index, tab in
                    let active = index == highlightedIndex
                    Button {
                        select(tab)
                    } label: {
                        VStack(spacing: 5) {
                            Image(systemName: tab.icon)
                                .font(.system(size: 21, weight: active ? .medium : .light))
                                .frame(height: 23)
                            Text(tab.title)
                                .font(.system(size: active ? 10.5 : 10, weight: active ? .semibold : .medium))
                                .lineLimit(1)
                                .minimumScaleFactor(0.8)
                        }
                        .foregroundStyle(active ? Aurora.ink : Aurora.muted)
                        .frame(maxWidth: .infinity)
                        .frame(height: barHeight)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(IslandTabStyle())
                    .accessibilityLabel(tab.title)
                    .accessibilityAddTraits(active ? [.isSelected] : [])
                }
            }
            .frame(height: barHeight)
        }
        .frame(height: barHeight)
        .background(
            GeometryReader { geo in
                Color.clear
                    .onAppear { barWidth = geo.size.width }
                    .onChange(of: geo.size.width) { width in barWidth = width }
            }
        )
        .contentShape(Rectangle())
        .simultaneousGesture(dragGesture)
        .animation(.spring(response: 0.36, dampingFraction: 0.80), value: selection)
    }

    // MARK: 透镜

    private var lensView: some View {
        Capsule(style: .continuous)
            .fill(.ultraThinMaterial)
            .overlay(
                Capsule(style: .continuous)
                    .fill(Color.white.opacity(0.46))
            )
            .overlay(
                Capsule(style: .continuous)
                    .strokeBorder(Color.white.opacity(0.60), lineWidth: 0.8)
            )
            .shadow(color: Color.black.opacity(0.10), radius: 7, x: 0, y: 3)
    }

    // MARK: 切换

    private func select(_ tab: PanelTab) {
        guard tab != selection else { return }
        // 先撑开，再和位移一起回弹
        tapStretch = 28
        withAnimation(.spring(response: 0.38, dampingFraction: 0.78)) {
            selection = tab
            dragPosition = nil
            tapStretch = 0
        }
    }

    // MARK: 拖动

    private var dragGesture: some Gesture {
        DragGesture(minimumDistance: 6)
            .onChanged { value in
                guard segment > 0 else { return }
                let raw = (value.location.x - segment / 2) / segment
                dragPosition = min(max(raw, 0), count - 1)
            }
            .onEnded { _ in
                guard segment > 0 else { return }
                let target = Int((dragPosition ?? activeIndex).rounded())
                let clamped = min(max(target, 0), tabs.count - 1)
                withAnimation(.spring(response: 0.36, dampingFraction: 0.80)) {
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
