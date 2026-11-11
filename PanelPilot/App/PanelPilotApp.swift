import SwiftUI
import Foundation

@main
struct PanelPilotApp: App {

    @StateObject private var model = AppModel()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(model)
                .preferredColorScheme(.light)
        }
    }
}

/// 五栏结构：概览 / 路由 / Agent / 账号 / 设置。
///
/// 底栏交给系统原生 `TabView`：iOS 26 自动获得 Liquid Glass，
/// 选中态固定为近黑（`Aurora.ink`），未选中交给系统灰 —— 不自绘、不设背景。
struct RootView: View {

    @EnvironmentObject private var model: AppModel
    @Environment(\.scenePhase) private var scenePhase

    @State private var tab: PanelTab = .overview
    @State private var appliedStart = false

    var body: some View {
        TabView(selection: $tab) {
            OverviewScreen()
                .tabItem { Label("概览", systemImage: "square.grid.2x2") }
                .tag(PanelTab.overview)

            RoutingScreen()
                .tabItem { Label("路由", systemImage: "arrow.triangle.branch") }
                .tag(PanelTab.routing)

            AgentScreen()
                .tabItem { Label("Agent", systemImage: "sparkles") }
                .tag(PanelTab.agent)

            AccountsScreen()
                .tabItem { Label("账号", systemImage: "person.2") }
                .tag(PanelTab.accounts)

            SettingsScreen()
                .tabItem { Label("设置", systemImage: "slider.horizontal.3") }
                .tag(PanelTab.settings)
        }
        // 底栏交给系统：iOS 26+ 自动是 Liquid Glass + 系统的选中指示（会自己放大/滑动），
        // 选中态固定近黑，未选中交给系统灰。不要自绘、不要给底栏设背景。
        .tint(Aurora.ink)
        .onReceive(NotificationCenter.default.publisher(for: .openConnectionSettings)) { _ in
            tab = .settings
        }
        .onReceive(NotificationCenter.default.publisher(for: .openRoutingTab)) { _ in
            model.haptic()
            tab = .routing
        }
        .onChange(of: tab) { _ in model.haptic() }
        .onChange(of: scenePhase) { phase in
            if phase == .active {
                model.handleBecameActive()
            } else if phase == .background {
                // 落盘已经改成后台合并写（0.35 秒一次），进后台前把最后一批写完，
                // 免得刚同步完就切走、结果快照没留下。
                LocalVault.shared.flushNow()
            }
        }
        .onAppear {
            guard !appliedStart else { return }
            appliedStart = true
            if let start = PanelTab(rawValue: model.startTab) { tab = start }
        }
    }
}

// MARK: - 全局提示

/// 顶部提示条：单色下用图标与字重区分语气，不靠颜色。
struct ToastOverlay: View {

    @EnvironmentObject private var model: AppModel

    var body: some View {
        VStack {
            if let toast = model.toast {
                HStack(spacing: 7) {
                    Image(systemName: icon(for: toast.kind))
                        .font(.system(size: 12, weight: .bold))
                    Text(toast.text)
                        .font(AuroraFont.labelMedium)
                        .lineLimit(3)
                        .multilineTextAlignment(.leading)
                }
                .foregroundStyle(Aurora.ink)
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(Color.white)
                        .shadow(color: Aurora.cardShadow, radius: 10, y: 4)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .stroke(Aurora.line, lineWidth: 1)
                )
                .padding(.horizontal, 28)
                .padding(.top, 6)
                .transition(.move(edge: .top).combined(with: .opacity))
                .task(id: toast.id) {
                    try? await Task.sleep(nanoseconds: 2_600_000_000)
                    withAnimation(.easeOut(duration: 0.2)) { model.toast = nil }
                }
            }
            Spacer()
        }
        .animation(.spring(response: 0.3, dampingFraction: 0.85), value: model.toast?.id)
    }

    private func icon(for kind: Toast.Kind) -> String {
        switch kind {
        case .info: return "info.circle.fill"
        case .success: return "checkmark.circle.fill"
        case .warning: return "exclamationmark.triangle.fill"
        case .error: return "xmark.octagon.fill"
        }
    }
}
