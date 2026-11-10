import SwiftUI

// === 悬浮岛（iOS Native Minimal 的签名元素）===
//
// 底栏装在**一块白色 20pt 圆角容器**里，左右各 16pt，离屏幕底边 26pt（不含安全区）。
// 不要改成贴底全宽 TabBar，也不要把输入框拆到另一个浮块。

struct FloatingIsland<Content: View>: View {

    var bottomGap: CGFloat = AuroraMetrics.islandBottom
    @ViewBuilder var content: () -> Content

    var body: some View {
        VStack(spacing: 0) { content() }
            .padding(10)
            .background(
                RoundedRectangle(cornerRadius: AuroraMetrics.cardRadius, style: .continuous)
                    .fill(Aurora.surface)
            )
            .shadow(color: Color.black.opacity(0.06), radius: 18, x: 0, y: 8)
            .padding(.horizontal, AuroraMetrics.pagePadding)
            .padding(.bottom, bottomGap)
            .contentShape(RoundedRectangle(cornerRadius: AuroraMetrics.cardRadius, style: .continuous))
    }
}

// MARK: - Tab 行

struct IslandTabBar: View {

    @Binding var selection: PanelTab

    private let tabs: [PanelTab] = [.overview, .routing, .agent, .accounts, .settings]

    var body: some View {
        HStack(spacing: 0) {
            ForEach(tabs) { tab in
                let active = selection == tab
                Button {
                    withAnimation(.spring(response: 0.32, dampingFraction: 0.86)) {
                        selection = tab
                    }
                } label: {
                    VStack(spacing: 4) {
                        Image(systemName: tab.icon)
                            .font(.system(size: 20, weight: active ? .regular : .light))
                            .foregroundStyle(active ? Aurora.ink : Aurora.muted)
                        Text(tab.title)
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(active ? Aurora.ink : Aurora.muted)
                    }
                    .frame(maxWidth: .infinity)
                    .frame(height: 50)
                    .contentShape(Rectangle())
                }
                .buttonStyle(IslandTabStyle())
                .accessibilityLabel(tab.title)
                .accessibilityAddTraits(active ? [.isSelected] : [])
            }
        }
        .animation(.spring(response: 0.32, dampingFraction: 0.86), value: selection)
    }
}

private struct IslandTabStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background {
                RoundedRectangle(cornerRadius: AuroraMetrics.controlRadius, style: .continuous)
                    .fill(Aurora.surfaceVariant)
                    .opacity(configuration.isPressed ? 1 : 0)
                    .padding(.horizontal, 8)
            }
    }
}
