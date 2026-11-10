import SwiftUI

/// 连接方式：本地连接管理 + 诊断 + 接入指引 + 服务器端信息。
///
/// 「服务端」这一块不再是 `/api/system-info` 的原始键值堆：
/// 先拎出版本 / 运行形态 / 已运行 / 监听地址做成指标，再按
/// 「软件信息 / 运行环境 / 部署与路径 / 安全 / 规模」分组展示，
/// 路径可复制、链接可打开，并挂上「检查更新 / 复制信息 / 隐藏用户名」三个真动作。
struct ConnectionScreen: View {

    @EnvironmentObject private var model: AppModel
    @Environment(\.openURL) private var openURL

    var onBack: () -> Void

    @State private var editing: PanelProfile?
    @State private var creating = false
    @State private var showGuide = false
    @State private var rawSheet: JSONSheetItem?

    var body: some View {
        ZStack {
            AuroraBackdrop()

            VStack(spacing: 0) {
                AppTopBar(title: "连接方式", onBack: onBack) {
                    HStack(spacing: 6) {
                        StatusPill(text: model.state.title, color: model.state.tint)
                        GlassIconButton(
                            systemIcon: "plus",
                            tint: Aurora.inkSoft,
                            diameter: 30,
                            iconSize: 12
                        ) {
                            creating = true
                        }
                    }
                }

                ScrollView {
                    VStack(alignment: .leading, spacing: AuroraMetrics.cardSpacing) {
                        profilesCard
                        diagCard
                        guideCard
                        serverCard
                        otherSections
                        eventsCard
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
        .onAppear { Task { await model.load(page: .connection) } }
        .sheet(isPresented: $creating) {
            ProfileEditorView(profile: nil)
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
        }
        .sheet(item: $editing) { profile in
            ProfileEditorView(profile: profile)
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
        }
        .sheet(item: $rawSheet) { item in
            JSONDetailSheet(
                title: "服务端原始数据",
                json: item.value,
                onCopy: { text in model.copy(text) }
            )
            .presentationDetents([.large])
            .presentationDragIndicator(.visible)
        }
        .sheet(isPresented: $showGuide) {
            SetupGuideView(initialMode: model.activeProfile?.mode ?? .publicNet) { mode in
                showGuide = false
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.45) {
                    creating = true
                    _ = mode
                }
            }
            .presentationDetents([.large])
            .presentationDragIndicator(.visible)
        }
    }

    // MARK: 连接列表

    private var profilesCard: some View {
        SectionCard {
            SectionTitle(title: "连接", trailing: "\(model.profiles.count)")

            VStack(spacing: 0) {
                ForEach(Array(model.profiles.enumerated()), id: \.element.id) { index, profile in
                    if index > 0 {
                        Rectangle().fill(Aurora.hairline).frame(height: 1)
                    }
                    HStack(spacing: 10) {
                        Image(systemName: model.activeID == profile.id ? "largecircle.fill.circle" : "circle")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(model.activeID == profile.id ? Aurora.ink : Aurora.muted)

                        VStack(alignment: .leading, spacing: 3) {
                            Text(profile.name)
                                .font(AuroraFont.bodyMedium)
                                .foregroundStyle(Aurora.ink)
                                .lineLimit(1)
                            Text("\(profile.mode.title) · \(profile.displayAddress)")
                                .font(AuroraFont.bodySmall)
                                .foregroundStyle(Aurora.muted)
                                .lineLimit(2)
                        }

                        Spacer(minLength: 4)

                        MonoButton(text: model.activeID == profile.id ? "已启用" : "切换", style: .outline) {
                            model.activate(profile.id)
                        }
                        MonoButton(text: "编辑", icon: "pencil", style: .plain) {
                            editing = profile
                        }
                    }
                    .padding(.vertical, 9)
                    .contentShape(Rectangle())
                    .onTapGesture { model.activate(profile.id) }
                }
            }
            .padding(.top, 4)

            HStack(spacing: 8) {
                MonoButton(text: "新建连接", icon: "plus", style: .filled) { creating = true }
                MonoButton(text: "重连", icon: "arrow.clockwise") {
                    Task { await model.connect() }
                }
                Spacer(minLength: 0)
            }
            .padding(.top, 10)
        }
    }

    // MARK: 诊断

    private var diagCard: some View {
        SectionCard {
            SectionTitle(title: "诊断", trailing: model.isDiagnosing ? "进行中" : nil)

            if model.diagSteps.isEmpty {
                Text("点下面的按钮，按「配置 → 地址 → 可达 → 登录 → 鉴权」逐层检查。")
                    .font(AuroraFont.bodySmall)
                    .foregroundStyle(Aurora.muted)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 6)
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(model.diagSteps.enumerated()), id: \.element.id) { index, step in
                        if index > 0 {
                            Rectangle().fill(Aurora.hairline).frame(height: 1)
                        }
                        HStack(alignment: .top, spacing: 9) {
                            Image(systemName: step.ok ? "checkmark.circle.fill" : "xmark.circle")
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(step.ok ? Aurora.ink : Aurora.muted)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(step.title)
                                    .font(AuroraFont.bodyMedium)
                                    .foregroundStyle(Aurora.ink)
                                Text(step.detail)
                                    .font(AuroraFont.bodySmall)
                                    .foregroundStyle(Aurora.muted)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                            Spacer(minLength: 0)
                        }
                        .padding(.vertical, 8)
                    }
                }
                .padding(.top, 6)
            }

            HStack(spacing: 8) {
                MonoButton(
                    text: model.isDiagnosing ? "检查中" : "开始诊断",
                    icon: "stethoscope",
                    style: .filled,
                    enabled: !model.isDiagnosing
                ) {
                    Task { await model.runDiagnostics() }
                }
                Spacer(minLength: 0)
            }
            .padding(.top, 10)
        }
    }

    // MARK: 指引

    private var guideCard: some View {
        SectionCard {
            SectionTitle(title: "接入指引")

            Text("公网 / Tailscale / 局域网三条路径的具体命令与注意事项，按现在这台服务器的部署写的。")
                .font(AuroraFont.bodySmall)
                .foregroundStyle(Aurora.inkSoft)
                .fixedSize(horizontal: false, vertical: true)

            MonoButton(text: "打开指引", icon: "book", style: .tonal) {
                showGuide = true
            }
            .padding(.top, 8)
        }
    }

    // MARK: 服务器端

    private var serverSection: PanelSectionSpec? {
        PanelCatalog.connection.sections.first { $0.id == "system" }
    }

    private var serverData: SectionData {
        guard let serverSection else { return SectionData() }
        return model.data(page: .connection, section: serverSection)
    }

    /// 服务端：指标条 + 分组字段 + 更新结果 + 真动作
    private var serverCard: some View {
        SectionCard {
            SectionTitle(title: "服务端", trailing: versionTrailing)

            WrapLayout(spacing: 8, lineSpacing: 8) {
                MonoButton(
                    text: model.updateChecking ? "检查中" : "检查更新",
                    icon: "arrow.triangle.2.circlepath",
                    style: .filled,
                    enabled: !model.updateChecking
                ) {
                    Task { await model.checkUpdate() }
                }
                MonoButton(text: "复制信息", icon: "doc.on.doc", style: .tonal) {
                    let report = model.serverReport()
                    model.copy(report.isEmpty ? "还没有读到服务端信息" : report, label: "服务端信息已复制")
                }
                if let json = serverData.json {
                    MonoButton(text: "原始数据", icon: "curlybraces", style: .plain) {
                        rawSheet = JSONSheetItem(value: json)
                    }
                }
            }
            .padding(.top, 10)

            if let info = model.updateInfo {
                updateNotice(info)
                    .padding(.top, 10)
            } else if let error = model.updateError {
                errorNotice(error)
                    .padding(.top, 10)
            }

            if let json = serverData.json {
                let metrics = metricItems(for: json)
                if !metrics.isEmpty {
                    SmartMetricStrip(items: metrics)
                        .padding(.top, 12)
                }

                SmartFieldList(
                    json: json,
                    skipping: metricKeys(for: metrics),
                    onCopy: { text in model.copy(text) }
                )
                .padding(.top, 14)

                linkActions(for: json)
                    .padding(.top, 12)

                HStack(spacing: 8) {
                    MonoButton(
                        text: model.hideUsername ? "显示用户名" : "隐藏用户名",
                        icon: model.hideUsername ? "eye" : "eye.slash",
                        style: .outline
                    ) {
                        Task { await model.setHideUsername(!model.hideUsername) }
                    }
                    Spacer(minLength: 0)
                }
                .padding(.top, 10)
            } else if let error = serverData.error {
                InlineErrorCard(
                    title: "读取服务端信息失败",
                    message: error,
                    hint: nil,
                    actionTitle: "重试",
                    action: {
                        Task {
                            await model.load(page: .connection, force: true, only: ["system"])
                        }
                    }
                )
                .padding(.top, 10)
            } else {
                Text(serverData.loading ? "正在读取服务端信息…" : "还没有读到服务端信息")
                    .font(AuroraFont.bodySmall)
                    .foregroundStyle(Aurora.muted)
                    .padding(.top, 10)
            }
        }
    }

    private var versionTrailing: String? {
        guard let version = model.serverVersionText, !version.isEmpty else { return nil }
        return version.lowercased().hasPrefix("v") ? version : "v\(version)"
    }

    /// 关键几项先做成指标，避免它们淹没在字段列表里
    private func metricItems(for json: JSONValue) -> [SmartMetricStrip.Item] {
        var items: [SmartMetricStrip.Item] = []
        if let version = json.lookup("app")?.str("version"), !version.isEmpty {
            items.append(
                .init(
                    id: "version",
                    label: "软件版本",
                    value: version.lowercased().hasPrefix("v") ? version : "v\(version)",
                    icon: "shippingbox"
                )
            )
        }
        if let deployment = json.lookup("runtime")?.str("deployment"), !deployment.isEmpty {
            items.append(
                .init(
                    id: "deployment",
                    label: "运行形态",
                    value: PanelFields.tagText(deployment),
                    icon: "square.stack.3d.up"
                )
            )
        }
        if let seconds = json.lookup("runtime")?.value("uptimeSeconds")?.doubleValue {
            items.append(
                .init(
                    id: "uptime",
                    label: "已运行",
                    value: PanelFields.durationText(seconds),
                    icon: "clock",
                    tint: Aurora.teal
                )
            )
        }
        if let host = json.lookup("deployment")?.str("host") {
            let port = json.lookup("deployment")?.int("port")
            let address = port.map { "\(host):\($0)" } ?? host
            items.append(
                .init(
                    id: "endpoint",
                    label: "监听地址",
                    value: address,
                    icon: "network",
                    tint: Aurora.inkSoft
                )
            )
        }
        if items.count < 4, let accounts = json.lookup("stats")?.int("accounts") {
            let enabled = json.lookup("stats")?.int("enabledAccounts")
            let text = enabled.map { "\($0) / \(accounts)" } ?? "\(accounts)"
            items.append(
                .init(
                    id: "accounts",
                    label: "启用账号",
                    value: text,
                    icon: "person.2",
                    tint: Aurora.inkSoft
                )
            )
        }
        return items
    }

    /// 指标里已经展示过的字段，列表里不重复
    private func metricKeys(for items: [SmartMetricStrip.Item]) -> Set<String> {
        var keys: Set<String> = []
        for item in items {
            switch item.id {
            case "version": keys.insert("app.version")
            case "deployment": keys.insert("runtime.deployment")
            case "uptime": keys.insert("runtime.uptimeSeconds")
            case "endpoint":
                keys.insert("deployment.host")
                keys.insert("deployment.port")
            case "accounts":
                keys.insert("stats.accounts")
                keys.insert("stats.enabledAccounts")
            default: break
            }
        }
        return keys
    }

    /// 能直接点开的链接（源码、许可证、发布页）
    @ViewBuilder
    private func linkActions(for json: JSONValue) -> some View {
        let app = json.lookup("app")
        let source = app?.str("sourceUrl")
        let license = app?.str("licenseUrl")

        if source != nil || license != nil {
            WrapLayout(spacing: 8, lineSpacing: 8) {
                if let source, let url = URL(string: source) {
                    MonoButton(text: "源码仓库", icon: "chevron.left.forwardslash.chevron.right", style: .outline) {
                        openURL(url)
                    }
                }
                if let license, let url = URL(string: license) {
                    MonoButton(text: "开源许可证", icon: "doc.text", style: .outline) {
                        openURL(url)
                    }
                }
                if let page = model.updateInfo?.pageURL, let url = URL(string: page) {
                    MonoButton(text: "发布页", icon: "arrow.up.right", style: .outline) {
                        openURL(url)
                    }
                }
            }
        } else if let page = model.updateInfo?.pageURL, let url = URL(string: page) {
            MonoButton(text: "打开发布页", icon: "arrow.up.right", style: .outline) {
                openURL(url)
            }
        }
    }

    private func updateNotice(_ info: UpdateCheckInfo) -> some View {
        let hasNew = info.hasUpdate == true
        let tint = hasNew ? Aurora.brand : Aurora.success
        return HStack(alignment: .top, spacing: 9) {
            Image(systemName: hasNew ? "arrow.down.circle.fill" : "checkmark.seal.fill")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(tint)

            VStack(alignment: .leading, spacing: 4) {
                Text(info.title)
                    .font(AuroraFont.bodyMedium)
                    .foregroundStyle(Aurora.ink)
                    .fixedSize(horizontal: false, vertical: true)

                Text("当前 \(info.currentVersion ?? "—") · 检查于 \(info.checkedAt.formatted("HH:mm"))")
                    .font(AuroraFont.bodySmall)
                    .foregroundStyle(Aurora.muted)

                if let notes = info.notes, !notes.isEmpty {
                    Text(notes)
                        .font(AuroraFont.bodySmall)
                        .foregroundStyle(Aurora.inkSoft)
                        .lineLimit(5)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            Spacer(minLength: 4)

            if let raw = info.pageURL, let url = URL(string: raw) {
                MiniIconButton(icon: "arrow.up.right", tint: Aurora.brand) {
                    openURL(url)
                }
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(tint.opacity(0.07))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(tint.opacity(0.22), lineWidth: 1)
        )
    }

    private func errorNotice(_ message: String) -> some View {
        HStack(alignment: .top, spacing: 9) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Aurora.rose)
            VStack(alignment: .leading, spacing: 3) {
                Text("检查更新失败")
                    .font(AuroraFont.bodyMedium)
                    .foregroundStyle(Aurora.ink)
                Text(message)
                    .font(AuroraFont.bodySmall)
                    .foregroundStyle(Aurora.inkSoft)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Aurora.rose.opacity(0.06))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(Aurora.rose.opacity(0.2), lineWidth: 1)
        )
    }

    /// 其余服务端区块（面板状态 / 会话 / 版本与更新）仍走通用渲染
    private var otherSections: some View {
        VStack(spacing: AuroraMetrics.cardSpacing) {
            ForEach(PanelCatalog.connection.sections.filter { $0.id != "system" }) { section in
                DataSection(page: .connection, section: section)
            }
        }
    }

    // MARK: 事件

    private var eventsCard: some View {
        SectionCard {
            SectionTitle(title: "事件", trailing: model.events.isEmpty ? nil : "\(model.events.count)")

            if model.events.isEmpty {
                Text("还没有事件")
                    .font(AuroraFont.bodySmall)
                    .foregroundStyle(Aurora.muted)
                    .padding(.top, 6)
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(model.events.prefix(30).enumerated()), id: \.element.id) { index, event in
                        if index > 0 {
                            Rectangle().fill(Aurora.hairline).frame(height: 1)
                        }
                        FeedRow(title: event.text, time: event.timeText, ok: event.ok)
                    }
                }
                .padding(.top, 4)
            }
        }
    }
}
