import SwiftUI
import Foundation

// === 设置 ===
//
// 一级只放入口，全部走二级页：
//   通用 / 显示 / 网关 / 安全 / 连接方式 / 服务器 / 关于
// 每一项都是能落地的东西：要么改本机行为（自动刷新、启动页、触感、图表动画、
// 数字格式），要么真调面板接口（改密码、隐藏用户名、路由、签到、模型…）。
//
// 「服务器」这一项保留原来的六个面板页入口（签到 / 模型 / 工具 / 代理 /
// 网关 Key / 定时任务），换的是组织方式，不是砍功能。

struct SettingsScreen: View {

    @EnvironmentObject private var model: AppModel

    enum Pane: String, CaseIterable, Identifiable {
        case general, display, gateway, security, connection, server, about

        var id: String { rawValue }

        var title: String {
            switch self {
            case .general: return "通用"
            case .display: return "显示"
            case .gateway: return "网关"
            case .security: return "安全"
            case .connection: return "连接方式"
            case .server: return "服务器"
            case .about: return "关于"
            }
        }

        var icon: String {
            switch self {
            case .general: return "gearshape"
            case .display: return "paintbrush"
            case .gateway: return "server.rack"
            case .security: return "lock.shield"
            case .connection: return "antenna.radiowaves.left.and.right"
            case .server: return "externaldrive.connected.to.line.below"
            case .about: return "info.circle"
            }
        }

        var detail: String {
            switch self {
            case .general: return "刷新 · 启动页 · 本地引擎"
            case .display: return "图表动画 · 数字格式"
            case .gateway: return "版本 · 监听 · 全局路由"
            case .security: return "密码 · 凭证 · 用户名"
            case .connection: return "地址 · 登录 · 诊断"
            case .server: return "签到 · 模型 · 工具 · 代理 · Key · 定时"
            case .about: return "版本 · 数据来源"
            }
        }
    }

    @State private var opened: Pane?

    var body: some View {
        Group {
            if let opened {
                if opened == .connection {
                    ConnectionScreen(onBack: { self.opened = nil })
                } else {
                    SettingsDetailPane(pane: opened, onBack: { self.opened = nil })
                }
            } else {
                root
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .openConnectionSettings)) { _ in
            opened = .connection
        }
    }

    private var root: some View {
        PanelPageShell(title: "设置", onLoad: nil) {
            entriesCard
            aboutCard
        }
    }

    // MARK: 一级入口

    private var entriesCard: some View {
        SectionCard {
            SectionTitle(title: "设置")

            VStack(spacing: 0) {
                ForEach(Array(Pane.allCases.enumerated()), id: \.element.id) { index, pane in
                    if index > 0 {
                        Rectangle().fill(Aurora.hairline).frame(height: 1)
                    }
                    Button {
                        model.haptic()
                        opened = pane
                    } label: {
                        HStack(spacing: 12) {
                            Image(systemName: pane.icon)
                                .font(.system(size: 15, weight: .regular))
                                .foregroundStyle(Aurora.inkSoft)
                                .frame(width: 26)
                            Text(pane.title)
                                .font(AuroraFont.bodyMedium)
                                .foregroundStyle(Aurora.ink)
                            Spacer(minLength: 4)
                            Image(systemName: "chevron.right")
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(Aurora.muted)
                        }
                        .padding(.vertical, 17)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.top, 2)
        }
    }

    private var aboutCard: some View {
        HStack(spacing: 6) {
            Text("面板控制台 \(appVersion)")
                .font(.system(size: 10.5))
                .foregroundStyle(Aurora.muted)
            Spacer(minLength: 4)
            Text("本地渲染 · 无网页容器")
                .font(.system(size: 10.5))
                .foregroundStyle(Aurora.muted)
        }
        .padding(.horizontal, 4)
    }

    private var appVersion: String {
        let short = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1"
        return "\(short) (\(build))"
    }
}

// MARK: - 二级页骨架

private struct SettingsDetailPane: View {

    @EnvironmentObject private var model: AppModel

    let pane: SettingsScreen.Pane
    var onBack: () -> Void

    @State private var openedPage: PanelPage?

    var body: some View {
        Group {
            if let openedPage {
                if openedPage == .checkin {
                    // 签到是重点模块，用专门的可视化页面，不再走通用区块渲染
                    CheckinScreen(onBack: { self.openedPage = nil })
                } else if openedPage == .gatewayKeys {
                    // 网关 Key 也单独做：通用渲染会把 /api/config 摊成
                    // 「Data / Success」+ 英文键名，根本读不懂
                    GatewayKeysScreen(onBack: { self.openedPage = nil })
                } else {
                    GenericSubPage(page: openedPage, onBack: { self.openedPage = nil })
                }
            } else {
                ZStack {
                    AuroraBackdrop()

                    VStack(spacing: 0) {
                        AppTopBar(title: pane.title, onBack: onBack)

                        ScrollView {
                            VStack(alignment: .leading, spacing: AuroraMetrics.cardSpacing) {
                                switch pane {
                                case .general: GeneralSettings()
                                case .display: DisplaySettings()
                                case .gateway: GatewaySettings(onOpenRouting: jumpToRouting)
                                case .security: SecuritySettings()
                                case .server: ServerPages(onOpen: { openedPage = $0 })
                                case .about: AboutSettings()
                                case .connection: EmptyView()
                                }
                            }
                            .padding(.horizontal, AuroraMetrics.pagePadding)
                            .padding(.top, 4)
                            .padding(.bottom, AuroraMetrics.listBottomInset)
                            .frame(maxWidth: 640)
                            .frame(maxWidth: .infinity)
                        }
                        .scrollIndicators(.hidden)
                    }
                }
            }
        }
    }

    private func jumpToRouting() {
        NotificationCenter.default.post(name: .openRoutingTab, object: nil)
    }
}

// MARK: - 通用

private struct GeneralSettings: View {

    @EnvironmentObject private var model: AppModel

    var body: some View {
        SectionCard {
            SectionTitle(title: "刷新")

            StudioToggleRow(title: "自动刷新", isOn: $model.autoRefresh)

            Rectangle().fill(Aurora.hairline).frame(height: 1).padding(.vertical, 8)

            StudioSelect(
                title: "启动页",
                value: model.startTab,
                options: [
                    .init(id: "overview", title: "概览", note: nil),
                    .init(id: "routing", title: "路由", note: nil),
                    .init(id: "agent", title: "Agent", note: nil),
                    .init(id: "accounts", title: "账号", note: nil),
                    .init(id: "settings", title: "设置", note: nil)
                ]
            ) { value in
                model.startTab = value
                model.haptic()
            }
        }

        SectionCard {
            SectionTitle(title: "手感")

            StudioToggleRow(title: "触感反馈", isOn: $model.hapticsEnabled)
        }

        LocalEngineCard()
    }
}

// MARK: - 显示

private struct DisplaySettings: View {

    @EnvironmentObject private var model: AppModel

    var body: some View {
        SectionCard {
            SectionTitle(title: "图表")

            StudioToggleRow(title: "图表动画", isOn: $model.chartAnimation)
        }

        SectionCard {
            SectionTitle(title: "数字")

            StudioToggleRow(title: "紧凑写法", isOn: $model.compactNumbers)

            HStack(spacing: 8) {
                Text("示例")
                    .font(.system(size: 11))
                    .foregroundStyle(Aurora.muted)
                Spacer(minLength: 4)
                Text(model.displayNumber(12345))
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                    .foregroundStyle(Aurora.ink)
                    .monospacedDigit()
                Text("·")
                    .foregroundStyle(Aurora.muted)
                Text(model.displayNumber(2_400_000))
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                    .foregroundStyle(Aurora.ink)
                    .monospacedDigit()
            }
            .padding(.top, 8)
        }

        SectionCard {
            SectionTitle(title: "外观")

            AppearanceSlider()
        }

        SectionCard {
            SectionTitle(title: "界面")

            KeyValueRow(label: "主题", value: "浅色")
            KeyValueRow(label: "底栏", value: "悬浮岛 · 胶囊")
            KeyValueRow(label: "卡片圆角", value: "20 pt")
        }
    }
}

// MARK: - 外观滑杆（透明 ↔ 色调）

/// 参照系统「外观 / 玻璃强度」那种一根滑杆的写法：
/// 左端是叠放的描边方块（更通透），右端是实心方块（更有色调），
/// 拖动时全站卡片、浮岛、输入框一起变。
private struct AppearanceSlider: View {

    @ObservedObject private var look = AppearanceStore.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                Image(systemName: "square.on.square")
                    .font(.system(size: 17, weight: .regular))
                    .foregroundStyle(Aurora.inkSoft)

                Slider(value: $look.tint, in: 0...1)
                    .tint(Aurora.brand)

                Image(systemName: "square.fill.on.square.fill")
                    .font(.system(size: 17, weight: .regular))
                    .foregroundStyle(Aurora.ink)
            }
            .padding(.top, 6)

            HStack(alignment: .top, spacing: 10) {
                Text("「透明」更通透，「色调」可增加不透明度，提升内容和控制项的对比度。")
                    .font(.system(size: 12))
                    .foregroundStyle(Aurora.muted)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 4)
                Text(look.levelText)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(Aurora.inkSoft)
                    .monospacedDigit()
            }

            // 即时预览：一张套在卡片里的假卡片，拖动滑杆时看这里最直观
            HStack(spacing: 10) {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(Aurora.brand.opacity(0.12))
                    .frame(width: 34, height: 34)
                    .overlay(
                        Image(systemName: "rectangle.on.rectangle")
                            .font(.system(size: 15, weight: .regular))
                            .foregroundStyle(Aurora.brand)
                    )
                VStack(alignment: .leading, spacing: 2) {
                    Text("卡片预览")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(Aurora.ink)
                    Text("拖动滑杆看这一块的底")
                        .font(.system(size: 11.5))
                        .foregroundStyle(Aurora.muted)
                }
                Spacer(minLength: 0)
            }
            .padding(12)
            .background(
                RoundedRectangle(cornerRadius: AuroraMetrics.controlRadius, style: .continuous)
                    .fill(Aurora.surface.opacity(look.cardAlpha))
            )
            .overlay(
                RoundedRectangle(cornerRadius: AuroraMetrics.controlRadius, style: .continuous)
                    .strokeBorder(Aurora.ink.opacity(0.05), lineWidth: 0.5)
            )
        }
    }
}

// MARK: - 网关

private struct GatewaySettings: View {

    @EnvironmentObject private var model: AppModel

    var onOpenRouting: () -> Void

    private var system: JSONValue? { model.systemInfoJSON }

    private var globalStrategy: String? {
        model.routing.raw.obj("globalSettings")?.firstString(["routingStrategy"])
    }

    private var globalSticky: String? {
        model.routing.raw.obj("globalSettings")?.firstString(["routingSticky"])
    }

    var body: some View {
        SectionCard {
            SectionTitle(title: "服务端", trailing: model.serverVersionText)

            VStack(spacing: 0) {
                KeyValueRow(label: "版本", value: model.serverVersionText ?? "—", mono: true)
                KeyValueRow(
                    label: "监听地址",
                    value: system?.obj("deployment")?.firstString(["host", "address"]) ?? "—",
                    mono: true
                )
                KeyValueRow(label: "运行形态", value: system?.obj("app")?.firstString(["channel"]) ?? "—")
                KeyValueRow(label: "账号数", value: "\(model.allAccounts.count)")
            }
            .padding(.top, 4)

            HStack(spacing: 8) {
                MonoButton(text: "刷新", icon: "arrow.clockwise", style: .filled) {
                    Task {
                        await model.load(page: .connection, force: true)
                        await model.loadRouting()
                    }
                }
                MonoButton(text: "去路由", icon: "arrow.triangle.branch", style: .outline) {
                    onOpenRouting()
                }
            }
            .padding(.top, 10)
        }

        SectionCard {
            SectionTitle(title: "全局路由")

            VStack(spacing: 0) {
                KeyValueRow(label: "路由策略", value: RoutingStrategy.title(globalStrategy))
                KeyValueRow(label: "会话粘滞", value: RoutingSticky.title(globalSticky))
                KeyValueRow(label: "保护", value: model.routing.protectionText)
                KeyValueRow(label: "已保存版本", value: model.routing.revision.map(String.init) ?? "—", mono: true)
            }
            .padding(.top, 4)

        }

        SectionCard {
            SectionTitle(title: "系统信息")

            if let system {
                SmartFieldList(json: system, collapsedLimit: 6, onCopy: { text in model.copy(text) })
            } else {
                Text("还没有读取到系统信息，点上面的「刷新」。")
                    .font(AuroraFont.bodySmall)
                    .foregroundStyle(Aurora.muted)
            }
        }
    }
}

// MARK: - 安全

private struct SecuritySettings: View {

    @EnvironmentObject private var model: AppModel

    @State private var current = ""
    @State private var next = ""
    @State private var confirm = ""
    @State private var working = false

    private var tokenExpiry: Date? {
        guard let id = model.activeID else { return nil }
        let stamp = UserDefaults.standard.double(forKey: "panel.tokenExpiry.\(id.uuidString)")
        return stamp > 0 ? Date(timeIntervalSince1970: stamp) : nil
    }

    var body: some View {
        SectionCard {
            SectionTitle(title: "本机会话")

            VStack(spacing: 0) {
                KeyValueRow(
                    label: "令牌",
                    value: model.activeToken.isEmpty ? "无" : "\(model.activeToken.count) 字符",
                    mono: true
                )
                KeyValueRow(label: "过期时间", value: tokenExpiry?.formatted("MM-dd HH:mm") ?? "—", mono: true)
                KeyValueRow(label: "密钥", value: model.activeAPIKey.isEmpty ? "无" : "已保存在钥匙串")
            }
            .padding(.top, 4)

            HStack(spacing: 8) {
                MonoButton(text: "清除本机凭证", icon: "key.slash", style: .danger) {
                    model.signOutLocal()
                }
                Spacer(minLength: 0)
            }
            .padding(.top, 10)
        }

        SectionCard {
            SectionTitle(title: "路径隐私")

            StudioToggleRow(
                title: "隐藏用户名",
                isOn: Binding(
                    get: { model.hideUsername },
                    set: { value in Task { await model.setHideUsername(value) } }
                )
            )
        }

        SectionCard {
            SectionTitle(title: "修改管理员密码")

            secureField("当前密码", text: $current)
                .padding(.top, 10)
            secureField("新密码（至少 6 位）", text: $next)
                .padding(.top, 8)
            secureField("再输一次", text: $confirm)
                .padding(.top, 8)

            HStack(spacing: 8) {
                MonoButton(
                    text: working ? "提交中" : "更新密码",
                    icon: "lock.rotation",
                    style: .filled,
                    enabled: !working && next.count >= 6 && next == confirm
                ) {
                    working = true
                    Task {
                        let ok = await model.changePassword(current: current, next: next)
                        if ok {
                            current = ""
                            next = ""
                            confirm = ""
                        }
                        working = false
                    }
                }
                Spacer(minLength: 0)
                if !next.isEmpty, next != confirm {
                    Text("两次输入不一致")
                        .font(.system(size: 10.5))
                        .foregroundStyle(Aurora.rose)
                }
            }
            .padding(.top, 10)
        }
    }

    private func secureField(_ title: String, text: Binding<String>) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(title)
                .font(.system(size: 11))
                .foregroundStyle(Aurora.muted)
            SecureField("••••••", text: text)
                .font(AuroraFont.bodyMedium)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .padding(.horizontal, 11)
                .frame(height: 38)
                .background(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(Aurora.surfaceVariant.opacity(0.7))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .stroke(Aurora.line, lineWidth: 1)
                )
        }
    }
}

// MARK: - 服务器子页

private struct ServerPages: View {

    var onOpen: (PanelPage) -> Void

    private let pages: [(PanelPage, String, String, String)] = [
        (.checkin, "签到", "自动签到 · 计划 · 记录", "checkmark.seal"),
        (.models, "模型管理", "清单 · 映射 · 元数据", "cpu"),
        (.tools, "工具服务", "服务 · 提供方 · 密钥", "wrench.and.screwdriver"),
        (.proxies, "网络代理", "代理 · 代理池 · 设置", "network"),
        (.gatewayKeys, "网关 Key", "Key · 网关配置", "key"),
        (.tasks, "定时任务", "任务 · 行程 · 队列", "clock.arrow.circlepath")
    ]

    var body: some View {
        SectionCard {
            SectionTitle(title: "服务器页面")

            VStack(spacing: 0) {
                ForEach(Array(pages.enumerated()), id: \.offset) { index, item in
                    if index > 0 {
                        Rectangle().fill(Aurora.hairline).frame(height: 1)
                    }
                    PanelListRow(
                        title: item.1,
                        subtitle: item.2,
                        icon: item.3,
                        onTap: { onOpen(item.0) }
                    )
                }
            }
            .padding(.top, 4)

        }
    }
}

// MARK: - 关于

private struct AboutSettings: View {

    @EnvironmentObject private var model: AppModel

    private var version: String {
        let short = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1"
        return "\(short) (\(build))"
    }

    var body: some View {
        SectionCard {
            SectionTitle(title: "面板控制台")

            VStack(spacing: 0) {
                KeyValueRow(label: "版本", value: version, mono: true)
                KeyValueRow(label: "面板地址", value: model.activeProfile?.rootString ?? "—", mono: true)
                KeyValueRow(label: "数据来源", value: model.statsFromSnapshot ? "本地快照" : "面板实时")
                KeyValueRow(label: "渲染", value: "SwiftUI 原生，无网页容器")
            }
            .padding(.top, 4)
        }

        SectionCard {
            SectionTitle(title: "本次运行")
            VStack(spacing: 0) {
                KeyValueRow(label: "网络请求", value: "\(model.networkRequestCount) 次", mono: true)
                KeyValueRow(label: "本地计算", value: "\(model.localComputeCount) 次", mono: true)
                KeyValueRow(label: "快照", value: "\(model.vaultEntryCount) 份", mono: true)
            }
            .padding(.top, 4)
        }

        SectionCard {
            SectionTitle(title: "致谢")
        }
    }
}

// MARK: - 本地引擎卡（通用页复用）

struct LocalEngineCard: View {

    @EnvironmentObject private var model: AppModel

    var body: some View {
        SectionCard {
            SectionTitle(
                title: "本地引擎",
                trailing: model.vaultEntryCount > 0 ? "\(model.vaultEntryCount) 份快照" : "无快照"
            )

            VStack(spacing: 0) {
                KeyValueRow(label: "快照时间", value: model.vaultNewest?.formatted("MM-dd HH:mm") ?? "—", mono: true)
                KeyValueRow(label: "网络请求", value: "\(model.networkRequestCount) 次", mono: true)
                KeyValueRow(label: "本地计算", value: "\(model.localComputeCount) 次", mono: true)
            }
            .padding(.top, 4)

            WrapLayout(spacing: 8, lineSpacing: 8) {
                MonoButton(text: "本地自检", icon: "stethoscope", style: .filled) {
                    Task { await model.runDiagnostics() }
                }
                MonoButton(text: "清空快照", icon: "trash", style: .danger) {
                    model.clearVault()
                }
            }
            .padding(.top, 10)

            if !model.diagSteps.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(Array(model.diagSteps.enumerated()), id: \.offset) { _, step in
                        HStack(alignment: .top, spacing: 6) {
                            Circle()
                                .fill(step.ok ? Aurora.success : Aurora.rose)
                                .frame(width: 5, height: 5)
                                .padding(.top, 5)
                            VStack(alignment: .leading, spacing: 1) {
                                Text(step.title)
                                    .font(.system(size: 11.5, weight: .semibold))
                                    .foregroundStyle(Aurora.ink)
                                Text(step.detail)
                                    .font(.system(size: 10.5))
                                    .foregroundStyle(Aurora.muted)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                    }
                }
                .padding(.top, 10)
            }
        }
    }
}
