import SwiftUI

/// 概览：真正的可视化仪表盘。
///
/// 设计原则（2.1.0 重做）：
///   · **固定版式**：头部状态 → 区间筛选 + KPI → 趋势柱状图 → 用量构成环形图
///     → 运行态矩阵 → 最近请求 → 快捷操作。七块，永远七块，不再按目录
///     把十几个只读区块无限往下堆。
///   · **一切联动后端**：`/api/stats/summary?range=` 是唯一统计口径，
///     切区间 → 请求换 range → KPI / 柱状图 / 环形图一起变。
///   · **可交互**：柱子可点选读数、扇区可点选看占比、区间可切、操作可执行。
///   · **能滑到底**：内容一次成型，底部留出 96pt 让最后一个按钮完整露出。
struct OverviewScreen: View {

    @EnvironmentObject private var model: AppModel
    @ObservedObject private var look = AppearanceStore.shared

    // 图表与筛选的本地状态
    @State private var metric: TrendMetric = .tokens
    @State private var trendSelection: Int?
    @State private var mixDimension: MixDimension = .models
    @State private var mixSelection: Int?
    @State private var showAllRequests = false
    @State private var confirmSticky = false

    // MARK: 构成维度

    enum MixDimension: String, CaseIterable, Identifiable {
        case models
        case providers
        case accounts

        var id: String { rawValue }

        var title: String {
            switch self {
            case .models: return "模型"
            case .providers: return "提供商"
            case .accounts: return "账号"
            }
        }
    }

    private var stats: PanelStatsSummary { model.stats ?? .empty }
    private var points: [PanelTrendPoint] { stats.trend }
    private var slices: [PanelStatSlice] {
        switch mixDimension {
        case .models: return stats.models
        case .providers: return stats.providers
        case .accounts: return stats.accounts
        }
    }
    private var sliceTotal: Int { slices.reduce(0) { $0 + $1.tokens } }

    var body: some View {
        ZStack {
            AuroraBackdrop()

            VStack(spacing: 0) {
                AppTopBar(title: "概览") {
                    HStack(spacing: 6) {
                        ServerChip()
                        StatusPill(text: model.state.title, color: model.state.tint)
                        refreshButton
                    }
                }

                ScrollView {
                    VStack(alignment: .leading, spacing: AuroraMetrics.cardSpacing) {
                        hero
                        if model.needsLogin { loginCard }
                        usageCard
                        trendCard
                        mixCard
                        runtimeCard
                        recentCard
                        actionsCard
                        footer
                    }
                    .padding(.horizontal, AuroraMetrics.pagePadding)
                    .padding(.top, 4)
                    // 底栏是系统 TabView，安全区之外再留一截，保证能真的滑到底
                    .padding(.bottom, AuroraMetrics.listBottomInset)
                    .frame(maxWidth: 640)
                    .frame(maxWidth: .infinity)
                    // 万一某个子视图算出来的宽度超了，也不要让它把整页撑宽
                    .clipped()
                }
                .scrollIndicators(.hidden)
                .refreshable { await model.refreshAll() }
            }
        }
        .task {
            if model.stats == nil { await model.loadDashboard() }
        }
        .confirmationDialog(
            "清除全部粘性会话？",
            isPresented: $confirmSticky,
            titleVisibility: .visible
        ) {
            Button("清除", role: .destructive) {
                Task {
                    await model.runCommand(
                        "清除粘性",
                        path: "/api/routing/sticky/clear"
                    )
                }
            }
            Button("取消", role: .cancel) {}
        } message: {
            Text("粘性会话会重新分配，正在进行的多轮对话可能换到别的账号。")
        }
    }

    // MARK: - 头部

    /// 右上角刷新：忙的时候图标自己转，并且**点不动**。
    /// 之前没有任何反馈，用户会连点几下，叠出好几轮全量请求 —— 越点越卡。
    private var refreshButton: some View {
        Button {
            Task { await model.refreshAll() }
        } label: {
            Image(systemName: "arrow.clockwise")
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(model.isRefreshing ? Aurora.brand : Aurora.inkSoft)
                .rotationEffect(.degrees(model.isRefreshing ? 360 : 0))
                .animation(
                    model.isRefreshing
                        ? .linear(duration: 0.9).repeatForever(autoreverses: false)
                        : .easeOut(duration: 0.2),
                    value: model.isRefreshing
                )
                .frame(width: 30, height: 30)
                .background(GlassSurface(shape: Circle(), shadowRadius: 8, highlight: 0.32))
                .contentShape(Circle())
        }
        .buttonStyle(PressScaleStyle(scale: 0.94))
        .disabled(model.isRefreshing)
    }

    private var hero: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 8) {
                HStack(spacing: 6) {
                    Circle()
                        .fill(heroDotColor)
                        .frame(width: 6, height: 6)
                    Text(model.state.title)
                        .font(.system(size: 13))
                        .foregroundStyle(Aurora.inkSoft)
                        .lineLimit(1)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(Capsule().fill(Aurora.surfaceVariant))

                // 推送在线 = 实时；否则说明还在轮询。
                if model.pushLive {
                    HStack(spacing: 5) {
                        Image(systemName: "bolt.fill")
                            .font(.system(size: 9, weight: .bold))
                        Text("实时")
                            .font(.system(size: 12, weight: .semibold))
                    }
                    .foregroundStyle(Aurora.brand)
                    .padding(.horizontal, 9)
                    .padding(.vertical, 4)
                    .background(Capsule().fill(Aurora.brand.opacity(0.1)))
                    .transition(.opacity)
                }

                Spacer(minLength: 4)

                Button {
                    Task { await model.refreshAll() }
                } label: {
                    HStack(spacing: 5) {
                        Image(systemName: "arrow.clockwise")
                            .font(.system(size: 11, weight: .bold))
                            .rotationEffect(.degrees(model.isRefreshing ? 360 : 0))
                            .animation(
                                model.isRefreshing
                                    ? .linear(duration: 0.9).repeatForever(autoreverses: false)
                                    : .easeOut(duration: 0.2),
                                value: model.isRefreshing
                            )
                        Text(model.isRefreshing ? "同步中" : "同步")
                            .font(.system(size: 12, weight: .semibold))
                    }
                    .foregroundStyle(Aurora.brand)
                    .padding(.horizontal, 12)
                    .frame(height: 30)
                    .background(Capsule().fill(Aurora.surfaceVariant))
                    .contentShape(Capsule())
                    .opacity(model.isRefreshing ? 0.6 : 1)
                }
                .buttonStyle(PressScaleStyle(scale: 0.95))
                .disabled(model.isRefreshing)
            }

            VStack(alignment: .leading, spacing: 4) {
                Text(model.activeProfile?.name ?? "未连接")
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundStyle(Aurora.ink)
                    .lineLimit(1)
                Text(model.activeProfile?.displayAddressWithScheme ?? "还没有配置面板地址")
                    .font(.system(size: 13, design: .monospaced))
                    .foregroundStyle(Aurora.inkSoft)
                    .lineLimit(1)

                // 失败时把「到底怎么失败的」直接摆出来：
                // 只写「连接失败」等于没说，用户没法把原因告诉别人。
                if case .failed(let reason) = model.state, !reason.isEmpty {
                    Text(reason)
                        .font(.system(size: 11))
                        .foregroundStyle(Aurora.rose)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.top, 2)
                }
            }

            HStack(spacing: 0) {
                heroStat("请求", model.displayNumber(stats.requests), rangeTitle)
                heroDivider
                heroStat("成功率", PanelNumber.percent(stats.successRate), "失败 \(PanelNumber.grouping(stats.failures))")
                heroDivider
                heroStat(
                    "延迟",
                    model.latency.map { "\($0)" } ?? "—",
                    "毫秒 · 网关"
                )
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: AuroraMetrics.cardRadius, style: .continuous)
                .fill(Aurora.surface.opacity(look.cardAlpha))
        )
    }

    private var heroDotColor: Color {
        switch model.state {
        case .online: return Color(hex: 0x6EF2A4)
        case .degraded: return Color(hex: 0xFFD166)
        case .connecting: return Color(hex: 0xD8D4FF)
        default: return Color(hex: 0xFF9A9A)
        }
    }

    private var heroDivider: some View {
        Rectangle()
            .fill(Aurora.hairline)
            .frame(width: 0.5, height: 28)
            .padding(.horizontal, 12)
    }

    private func heroStat(_ label: String, _ value: String, _ note: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(.system(size: 12))
                .foregroundStyle(Aurora.muted)
            Text(value)
                .font(.system(size: 20, weight: .semibold))
                .foregroundStyle(Aurora.ink)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
                .monospacedDigit()
            Text(note)
                .font(.system(size: 11))
                .foregroundStyle(Aurora.muted)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - 登录提示（只在面板真的拒绝凭证时出现）

    private var loginCard: some View {
        InlineErrorCard(
            title: "需要重新登录",
            message: model.lastError ?? "面板拒绝了当前账号密码",
            hint: model.authFixNote,
            actionTitle: "去连接设置",
            action: { NotificationCenter.default.post(name: .openConnectionSettings, object: nil) }
        )
    }

    // MARK: - KPI + 区间筛选

    private var usageCard: some View {
        SectionCard {
            SectionTitle(
                title: "用量",
                trailing: model.statsUpdatedAt?.formatted("HH:mm:ss") ?? (model.statsLoading ? "读取中" : nil)
            )

            metricSegmented(["today", "yesterday", "7", "30"], selection: rangeBinding) { rangeLabel($0) }
                .padding(.top, 10)

            LazyVGrid(
                columns: [GridItem(.flexible(), spacing: 8), GridItem(.flexible(), spacing: 8)],
                spacing: 8
            ) {
                KPITile(
                    icon: "arrow.left.arrow.right",
                    title: "请求数",
                    value: model.displayNumber(stats.requests),
                    detail: "区间内累计",
                    tint: Aurora.brand
                )
                KPITile(
                    icon: "checkmark.seal",
                    title: "成功率",
                    value: PanelNumber.percent(stats.successRate),
                    detail: "失败 \(PanelNumber.grouping(stats.failures)) 次",
                    tint: Aurora.teal
                )
                KPITile(
                    icon: "number.circle",
                    title: "Token",
                    value: model.displayNumber(stats.tokens),
                    detail: "输入 + 输出",
                    tint: Color(hex: 0x8B5CF6)
                )
                KPITile(
                    icon: "bolt.horizontal",
                    title: "缓存命中",
                    value: PanelNumber.percent(stats.cacheRate),
                    detail: "近 24 小时",
                    tint: Aurora.rose
                )
            }
            .padding(.top, 10)

            if !model.localInsights.isEmpty {
                // 两列网格，而不是横向滚动条：
                // 横向滚动的内容宽度是「数据驱动」的，30 天时模型名一长，
                // 整页的宽度就会被它撑开，看起来像整个面板被放大、还能左右拖。
                LazyVGrid(
                    columns: [
                        GridItem(.flexible(), spacing: 8),
                        GridItem(.flexible(), spacing: 8)
                    ],
                    spacing: 8
                ) {
                    ForEach(model.localInsights) { item in
                        insightChip(item)
                    }
                }
                .padding(.top, 10)
            }

            if let error = model.statsError, model.stats == nil {
                Text("统计数据读取失败：\(error)")
                    .font(AuroraFont.bodySmall)
                    .foregroundStyle(Aurora.rose)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 8)
            } else if model.stats == nil, model.statsLoading {
                Text("正在读取统计…")
                    .font(AuroraFont.bodySmall)
                    .foregroundStyle(Aurora.muted)
                    .padding(.top, 8)
            }
        }
    }

    /// 切区间是**纯本地动作**：只换一个字典键，不 await、不联网。
    private var rangeBinding: Binding<String> {
        Binding(
            get: { model.statsRange },
            set: { value in model.setStatsRange(value) }
        )
    }

    private func rangeLabel(_ value: String) -> String {
        switch value {
        case "today": return "今天"
        case "yesterday": return "昨天"
        case "7": return "近 7 天"
        case "30": return "近 30 天"
        default: return value
        }
    }

    private var rangeTitle: String { rangeLabel(model.statsRange) }

    // MARK: - 趋势柱状图

    /// 图表上方的指标切换：一条浅灰轨道 + 白色选中块，固定单行、等分。
    ///
    /// 原来用的是会换行的 `SegmentedPills`：选中块是白底，在白卡上等于隐形，
    /// 看起来就是两个裸文字；一旦换行（「Token」在上一行、「请求」掉到下一行），
    /// 第二行还会压到图表上去 —— 就是那张截图里「请求」浮在柱子上的样子。
    /// 换成有轨道的整行控件之后，选中态看得见，也不可能换行或压图。
    private func metricSegmented<Item: Hashable>(
        _ items: [Item],
        selection: Binding<Item>,
        title: @escaping (Item) -> String
    ) -> some View {
        HStack(spacing: 3) {
            ForEach(items, id: \.self) { item in
                let active = item == selection.wrappedValue
                Button {
                    withAnimation(.spring(response: 0.28, dampingFraction: 0.85)) {
                        selection.wrappedValue = item
                    }
                } label: {
                    Text(title(item))
                        .font(.system(size: 12.5, weight: .semibold))
                        .foregroundStyle(active ? Aurora.ink : Aurora.inkSoft)
                        .lineLimit(1)
                        .minimumScaleFactor(0.85)
                        .frame(maxWidth: .infinity)
                        .frame(height: 30)
                        .background(Capsule().fill(active ? Aurora.surface : Color.clear))
                        .contentShape(Capsule())
                }
                .buttonStyle(PressScaleStyle(scale: 0.96))
            }
        }
        .padding(3)
        .background(Capsule().fill(Aurora.surfaceVariant))
    }

    private var trendCard: some View {
        SectionCard {
            HStack(spacing: 8) {
                SectionTitle(title: "趋势", trailing: trendTrailing)
                Spacer(minLength: 0)
            }

            metricSegmented(TrendMetric.allCases, selection: $metric) { $0.title }
                .padding(.top, 10)

            if points.isEmpty || peakValue == 0 {
                emptyHint("这个区间还没有用量记录，换个区间或等有请求后再看")
            } else {
                AuroraBarChart(
                    points: points,
                    metric: metric,
                    selected: $trendSelection,
                    animated: model.chartAnimation
                )
                // 控件和图表之间留够空，别让「请求」看起来像贴在柱子上
                .padding(.top, 16)

                HStack(spacing: 12) {
                    legendDot(Aurora.brand, "峰值 \(model.displayNumber(peakValue))")
                    legendDot(Aurora.chartColor(3), "日均 \(model.displayNumber(averageValue))")
                    Spacer(minLength: 0)
                    if let selected = selectedPoint {
                        Text("\(selected.label) · \(metric.format(metric.value(of: selected)))")
                            .font(.system(size: 10.5, weight: .semibold))
                            .foregroundStyle(Aurora.brand)
                            .monospacedDigit()
                    }
                }
                .padding(.top, 10)
            }
        }
    }

    private var trendTrailing: String? {
        points.isEmpty ? nil : "\(points.count) 天"
    }

    private var peakValue: Int {
        points.map { metric.value(of: $0) }.max() ?? 0
    }

    private var averageValue: Int {
        guard !points.isEmpty else { return 0 }
        return points.map { metric.value(of: $0) }.reduce(0, +) / points.count
    }

    private var selectedPoint: PanelTrendPoint? {
        guard let trendSelection, points.indices.contains(trendSelection) else { return nil }
        return points[trendSelection]
    }

    private func legendDot(_ color: Color, _ text: String) -> some View {
        HStack(spacing: 4) {
            Circle().fill(color).frame(width: 6, height: 6)
            Text(text)
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(Aurora.inkSoft)
        }
    }

    // MARK: - 用量构成

    private var mixCard: some View {
        SectionCard {
            HStack(spacing: 8) {
                SectionTitle(title: "用量构成", trailing: sliceTotal > 0 ? PanelNumber.compact(sliceTotal) : nil)
                Spacer(minLength: 0)
            }

            metricSegmented(MixDimension.allCases, selection: $mixDimension) { $0.title }
                .padding(.top, 10)

            if slices.isEmpty || sliceTotal == 0 {
                emptyHint("这个区间还没有可拆分的 Token 用量")
            } else {
                HStack {
                    Spacer(minLength: 0)
                    AuroraDonutChart(
                        slices: slices,
                        total: sliceTotal,
                        selected: $mixSelection,
                        diameter: 148,
                        lineWidth: 20,
                        animated: model.chartAnimation
                    )
                    Spacer(minLength: 0)
                }
                // 环形图离上面的切换条太近会显得挤在一起，这里给足 18
                .padding(.top, 18)

                VStack(spacing: 2) {
                    ForEach(Array(slices.prefix(5).enumerated()), id: \.element.id) { index, slice in
                        DonutLegendRow(
                            slice: slice,
                            total: sliceTotal,
                            color: Aurora.chartColor(index),
                            active: mixSelection == index
                        ) {
                            withAnimation(.spring(response: 0.3, dampingFraction: 0.84)) {
                                mixSelection = mixSelection == index ? nil : index
                            }
                        }
                    }
                }
                .padding(.top, 6)

            }
        }
    }

    // MARK: - 运行态

    private var runtimeCard: some View {
        SectionCard {
            SectionTitle(title: "运行态", trailing: model.lastChecked?.formatted("HH:mm"))

            LazyVGrid(
                columns: [GridItem(.flexible(), spacing: 8), GridItem(.flexible(), spacing: 8)],
                spacing: 8
            ) {
                RuntimeCell(
                    label: "网关",
                    value: model.state.isOnline ? "正常" : model.state.title,
                    tint: model.state.isOnline ? Aurora.success : Aurora.warning,
                    dot: true
                )
                RuntimeCell(
                    label: "面板",
                    value: panelStateText,
                    tint: Aurora.brand
                )
                RuntimeCell(
                    label: "账号",
                    value: "\(model.accountCounts.enabled) / \(model.accountCounts.total)",
                    tint: Aurora.teal
                )
                RuntimeCell(
                    label: "路由队列",
                    value: "\(model.routingQueueCount) 条",
                    tint: Aurora.ink
                )
                RuntimeCell(
                    label: "今日签到",
                    value: checkinText,
                    tint: Aurora.warning
                )
                RuntimeCell(
                    label: "限流账号",
                    value: model.rateLimitedCount == 0 ? "无" : "\(model.rateLimitedCount)",
                    tint: model.rateLimitedCount == 0 ? Aurora.success : Aurora.rose,
                    dot: model.rateLimitedCount > 0
                )
            }
            .padding(.top, 9)
        }
    }

    private var panelStateText: String {
        guard let panel = model.dashboardPanel else { return "—" }
        let registered = panel.bool("registered")
            ?? panel.obj("data")?.bool("registered")
            ?? true
        if !registered { return "未注册" }
        if let version = panel.firstString(["version"])
            ?? panel.obj("data")?.firstString(["version"]) {
            return version.count > 10 ? String(version.prefix(10)) : version
        }
        return "已注册"
    }

    private var checkinText: String {
        let progress = model.checkinProgress
        guard progress.total > 0 else { return "—" }
        return "\(progress.done) / \(progress.total)"
    }

    // MARK: - 最近请求

    private var recentCard: some View {
        SectionCard {
            SectionTitle(
                title: "最近请求",
                trailing: model.dashboardRequests.isEmpty ? nil : "\(model.dashboardRequests.count)"
            )

            let rows = visibleRequests
            if rows.isEmpty {
                emptyHint("还没有请求记录")
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(rows.enumerated()), id: \.offset) { index, row in
                        if index > 0 {
                            Rectangle().fill(Aurora.hairline).frame(height: 1)
                        }
                        FeedRow(
                            title: requestTitle(row),
                            detail: requestDetail(row),
                            time: PanelNumber.clock(row.value("ts") ?? row.value("time") ?? row.value("createdAt")),
                            ok: requestOK(row)
                        )
                    }
                }
                .padding(.top, 4)

                if model.dashboardRequests.count > 5 {
                    MonoButton(
                        text: showAllRequests ? "收起" : "展开全部 \(model.dashboardRequests.count) 条",
                        icon: showAllRequests ? "chevron.up" : "chevron.down",
                        style: .outline
                    ) {
                        withAnimation(.spring(response: 0.32, dampingFraction: 0.86)) {
                            showAllRequests.toggle()
                        }
                    }
                    .padding(.top, 10)
                }
            }
        }
    }

    private var visibleRequests: [JSONValue] {
        let rows = model.dashboardRequests
        return showAllRequests ? Array(rows.prefix(12)) : Array(rows.prefix(5))
    }

    private func requestTitle(_ row: JSONValue) -> String {
        row.firstString(["upstreamModel", "model", "client", "apiKeyName"]) ?? "未知模型"
    }

    private func requestDetail(_ row: JSONValue) -> String? {
        var parts: [String] = []
        if let status = row.int("status") {
            parts.append("HTTP \(status)")
        } else if let status = row.str("status"), !status.isEmpty {
            parts.append(status)
        }
        if let duration = row.int("durationMs") {
            parts.append(PanelNumber.duration(duration))
        }
        if let tokens = row.int("totalTokens"), tokens > 0 {
            parts.append("\(PanelNumber.compact(tokens)) tok")
        }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    private func requestOK(_ row: JSONValue) -> Bool {
        if let status = row.int("status") { return (200..<400).contains(status) }
        if let failed = row.bool("error") { return !failed }
        return true
    }

    // MARK: - 快捷操作

    private var actionsCard: some View {
        SectionCard {
            SectionTitle(title: "本地操作")

            LazyVGrid(
                columns: [GridItem(.flexible(), spacing: 8), GridItem(.flexible(), spacing: 8)],
                spacing: 8
            ) {
                MonoButton(text: "本地自检", icon: "stethoscope", style: .tonal) {
                    Task { await model.runDiagnostics() }
                }
                MonoButton(text: "复制摘要", icon: "doc.on.doc", style: .tonal) {
                    model.copySummary()
                }
                MonoButton(text: "连接设置", icon: "antenna.radiowaves.left.and.right", style: .tonal) {
                    NotificationCenter.default.post(name: .openConnectionSettings, object: nil)
                }
                MonoButton(text: "刷新页面", icon: "arrow.clockwise", style: .tonal) {
                    Task { await model.refreshAll() }
                }
            }
            .padding(.top, 10)

            Rectangle()
                .fill(Aurora.hairline)
                .frame(height: 1)
                .padding(.vertical, 14)

            SectionTitle(title: "服务器操作")

            LazyVGrid(
                columns: [GridItem(.flexible(), spacing: 8), GridItem(.flexible(), spacing: 8)],
                spacing: 8
            ) {
                MonoButton(text: "同步面板", icon: "arrow.clockwise", style: .filled) {
                    Task { await model.refreshAll() }
                }
                MonoButton(
                    text: model.checkinBusy == "all" ? "签到中…" : "立即签到",
                    icon: "checkmark.seal",
                    style: .tonal
                ) {
                    Task { await model.checkinAll() }
                }
                MonoButton(text: "刷新模型", icon: "cpu", style: .tonal) {
                    Task { await model.runCommand("刷新模型", path: "/api/models/refresh") }
                }
                MonoButton(text: "清空粘性", icon: "pin.slash", style: .danger) {
                    confirmSticky = true
                }
            }
            .padding(.top, 10)
        }
    }

    // MARK: - 页脚

    private var footer: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                Circle()
                    .fill(model.statsFromSnapshot ? Aurora.warning : Aurora.success)
                    .frame(width: 5, height: 5)
                Text(sourceText)
                    .font(.system(size: 10.5))
                    .foregroundStyle(Aurora.muted)
                Spacer(minLength: 4)
                Text(model.authBadge.text)
                    .font(.system(size: 10.5))
                    .foregroundStyle(Aurora.muted)
            }
            HStack(spacing: 6) {
                Text("本次运行：网络 \(model.networkRequestCount) 次 · 本地计算 \(model.localComputeCount) 次 · 快照 \(model.vaultEntryCount) 份")
                    .font(.system(size: 9.5))
                    .foregroundStyle(Aurora.muted)
                    .monospacedDigit()
                Spacer(minLength: 0)
            }
        }
        .padding(.horizontal, 4)
        .padding(.top, 2)
    }

    private var sourceText: String {
        if model.statsFromSnapshot {
            let at = model.statsSnapshotAt?.formatted("MM-dd HH:mm")
                ?? model.statsUpdatedAt?.formatted("MM-dd HH:mm")
                ?? "—"
            return "本地快照 · \(at)（图表与筛选都在本机计算）"
        }
        let at = model.statsUpdatedAt?.formatted("HH:mm:ss") ?? "—"
        return "已同步 · \(at)"
    }

    private func insightChip(_ item: PanelLocalInsight) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(item.title)
                .font(.system(size: 9.5, weight: .medium))
                .foregroundStyle(Aurora.muted)
                .lineLimit(1)
            Text(item.value)
                .font(.system(size: 14, weight: .bold, design: .rounded))
                .foregroundStyle(insightColor(item.tone))
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .monospacedDigit()
            Text(item.note)
                .font(.system(size: 9))
                .foregroundStyle(Aurora.muted)
                .lineLimit(1)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: AuroraMetrics.controlRadius, style: .continuous)
                .fill(Aurora.surfaceVariant)
        )
    }

    private func insightColor(_ tone: PanelLocalInsight.Tone) -> Color {
        Aurora.ink
    }

    // MARK: - 小工具

    private func emptyHint(_ text: String) -> some View {
        Text(text)
            .font(AuroraFont.bodySmall)
            .foregroundStyle(Aurora.muted)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, 10)
    }
}

extension Notification.Name {
    /// 从任意页面跳到「设置 → 连接方式」。
    static let openConnectionSettings = Notification.Name("panel.openConnectionSettings")
    /// 从设置里跳到「路由」标签页。
    static let openRoutingTab = Notification.Name("panel.openRoutingTab")
}
