import SwiftUI

// === 签到 ===
//
// 四个分栏，全部是可视化操作、全部真打接口：
//   签到中心 · 今日进度 + 每个账号的签到状态（已签 / 未签）+ 单账号签到 + 全部签到
//   定时签到 · 总开关 + 每条定时（含各自的时间窗口、参与提供商、下次执行）
//   定时补签 · 每条定时的补签策略（补签到点 / 间隔 / 次数）+ 立即补签
//   签到记录 · 每次执行的结果（成功 / 已领 / 未领 / 需人工 / 失败）
//
// 数据来自 `GET /api/checkin-center`，写法见 `AppModel+Checkin`。

struct CheckinScreen: View {

    @EnvironmentObject private var model: AppModel

    var onBack: () -> Void

    enum Tab: String, CaseIterable, Identifiable {
        case center, schedule, makeup, records
        var id: String { rawValue }
        var title: String {
            switch self {
            case .center: return "签到中心"
            case .schedule: return "定时签到"
            case .makeup: return "定时补签"
            case .records: return "签到记录"
            }
        }
    }

    @State private var tab: Tab = .center
    @State private var editing: CheckinSchedule?
    @State private var creating = false
    @State private var deleting: CheckinSchedule?
    @State private var retryDraft: [String: RetryDraft] = [:]

    private var center: CheckinCenter? { model.checkin }

    var body: some View {
        ZStack {
            AuroraBackdrop()

            VStack(spacing: 0) {
                AppTopBar(title: "签到", onBack: onBack) {
                    Button {
                        Task {
                            await model.loadCheckin(force: true)
                            await model.loadCheckinRecords()
                        }
                    } label: {
                        Image(systemName: "arrow.clockwise")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(Aurora.inkSoft)
                            .frame(width: 32, height: 32)
                            .background(Circle().fill(Aurora.surfaceVariant))
                    }
                    .buttonStyle(.plain)
                }

                ScrollView {
                    VStack(alignment: .leading, spacing: AuroraMetrics.cardSpacing) {
                        if let error = model.checkinError, center == nil {
                            InlineErrorCard(
                                title: "签到状态读取失败",
                                message: error,
                                hint: "签到能力由网关上的插件提供；如果提示登录态问题，先在桌面面板登录一次。",
                                actionTitle: "重试",
                                action: { Task { await model.loadCheckin(force: true) } }
                            )
                        }

                        progressCard
                        tabBar

                        switch tab {
                        case .center: centerPane
                        case .schedule: schedulePane
                        case .makeup: makeupPane
                        case .records: recordsPane
                        }
                    }
                    .padding(.horizontal, AuroraMetrics.pagePadding)
                    .padding(.top, 4)
                    .padding(.bottom, AuroraMetrics.listBottomInset)
                    .frame(maxWidth: 640)
                    .frame(maxWidth: .infinity)
                }
                .scrollIndicators(.hidden)
                .refreshable {
                    await model.loadCheckin(force: true)
                    await model.loadCheckinRecords()
                }
            }
        }
        .task {
            await model.loadCheckin()
            if model.checkinRecords.isEmpty { await model.loadCheckinRecords() }
        }
        .sheet(item: $editing) { entry in
            ScheduleEditor(schedule: entry) { draft in
                Task {
                    await model.saveSchedule(
                        id: draft.id, label: draft.label, time: draft.time,
                        timeEnd: draft.timeEnd, enabled: draft.enabled,
                        providers: draft.providers, retryTime: draft.retryTime,
                        retryGapMinutes: draft.retryGapMinutes, retryLimit: draft.retryLimit
                    )
                }
            }
        }
        .sheet(isPresented: $creating) {
            ScheduleEditor(schedule: nil) { draft in
                Task {
                    await model.saveSchedule(
                        id: nil, label: draft.label, time: draft.time,
                        timeEnd: draft.timeEnd, enabled: true,
                        providers: draft.providers, retryTime: draft.retryTime,
                        retryGapMinutes: draft.retryGapMinutes, retryLimit: draft.retryLimit
                    )
                }
            }
        }
        .confirmationDialog(
            "删除「\(deleting?.displayLabel ?? "")」？",
            isPresented: Binding(
                get: { deleting != nil },
                set: { if !$0 { deleting = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button("删除", role: .destructive) {
                if let entry = deleting { Task { await model.deleteSchedule(entry.id) } }
                deleting = nil
            }
            Button("取消", role: .cancel) { deleting = nil }
        }
    }

    // MARK: 今日进度

    private var progressCard: some View {
        SectionCard {
            HStack(alignment: .center, spacing: 14) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("今日签到")
                        .font(.system(size: 13))
                        .foregroundStyle(Aurora.inkSoft)
                    HStack(alignment: .firstTextBaseline, spacing: 3) {
                        Text("\(center?.todayDone ?? 0)")
                            .font(.system(size: 28, weight: .semibold))
                            .foregroundStyle(Aurora.ink)
                            .monospacedDigit()
                        Text("/ \(center?.todayEligible ?? 0)")
                            .font(.system(size: 15))
                            .foregroundStyle(Aurora.muted)
                            .monospacedDigit()
                    }
                }

                Spacer(minLength: 8)

                MonoButton(
                    text: model.checkinBusy == "all" ? "签到中…" : "全部签到",
                    icon: "checkmark.seal",
                    style: .filled,
                    enabled: model.checkinBusy == nil && (center?.todayEligible ?? 0) > 0
                ) {
                    Task { await model.checkinAll() }
                }
            }

            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(Aurora.surfaceVariant)
                    Capsule()
                        .fill(Aurora.brand)
                        .frame(width: max(geo.size.width * (center?.progress ?? 0), 0))
                }
            }
            .frame(height: 6)
            .padding(.top, 12)

            HStack(spacing: 6) {
                Circle()
                    .fill((center?.autoRunning ?? false) ? Aurora.warning : (center?.autoEnabled ?? false) ? Aurora.success : Aurora.muted)
                    .frame(width: 5, height: 5)
                Text(autoText)
                    .font(.system(size: 11.5))
                    .foregroundStyle(Aurora.muted)
                Spacer(minLength: 4)
                if let updated = center?.updatedAt {
                    Text("更新 \(updated.formatted("HH:mm:ss"))")
                        .font(.system(size: 11))
                        .foregroundStyle(Aurora.muted)
                        .monospacedDigit()
                }
            }
            .padding(.top, 10)
        }
    }

    private var autoText: String {
        guard let center else { return "还没有读到签到状态" }
        if center.autoRunning { return "定时签到正在执行" }
        if center.autoEnabled {
            if let next = center.schedules.compactMap(\.nextRunAt).sorted().first {
                return "定时签到已开启 · 下次 \(CheckinParser.timeText(next))"
            }
            return "定时签到已开启"
        }
        return "定时签到已关闭"
    }

    // MARK: 分栏

    private var tabBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(Tab.allCases) { item in
                    StudioChip(text: item.title, active: tab == item) {
                        model.haptic()
                        tab = item
                    }
                }
            }
            .padding(.horizontal, 1)
            .padding(.vertical, 2)
        }
    }

    // MARK: 签到中心

    @ViewBuilder
    private var centerPane: some View {
        if model.checkinLoading && center == nil {
            SectionCard { loadingRow("正在读取签到状态…") }
        } else if let center, center.groups.isEmpty {
            SectionCard {
                StudioEmpty(
                    icon: "checkmark.seal",
                    title: "还没有可签到的账号",
                    detail: "账号与签到插件都保存在网关上；先添加账号或启用对应提供商插件。"
                )
            }
        } else {
            ForEach(center?.groups ?? []) { group in
                SectionCard {
                    SectionTitle(
                        title: group.label,
                        trailing: "\(group.doneCount)/\(group.accounts.count) 已签"
                    )

                    VStack(spacing: 0) {
                        ForEach(Array(group.accounts.enumerated()), id: \.element.id) { index, account in
                            if index > 0 {
                                Rectangle().fill(Aurora.hairline).frame(height: 1)
                            }
                            accountRow(account)
                        }
                    }
                    .padding(.top, 4)
                }
            }

            if let outOfScope = center?.outOfScope, !outOfScope.isEmpty {
                SectionCard {
                    SectionTitle(title: "不参与每日签到")
                    VStack(alignment: .leading, spacing: 6) {
                        ForEach(outOfScope, id: \.self) { line in
                            Text(line)
                                .font(.system(size: 12))
                                .foregroundStyle(Aurora.muted)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    .padding(.top, 6)
                }
            }
        }
    }

    private func accountRow(_ account: CheckinAccount) -> some View {
        let busy = model.checkinBusy == account.id || model.checkinBusy == "all"
        return HStack(spacing: 11) {
            ProviderIcon(provider: account.provider, fallback: account.name, size: 34)
                .opacity(account.available ? 1 : 0.45)

            VStack(alignment: .leading, spacing: 3) {
                Text(account.name)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Aurora.ink)
                    .lineLimit(1)
                Text(account.detail.isEmpty ? account.status.label : account.detail)
                    .font(.system(size: 11.5))
                    .foregroundStyle(Aurora.muted)
                    .lineLimit(1)
            }

            Spacer(minLength: 4)

            StatusPill(text: account.status.label, color: account.status.color)

            Button {
                Task { await model.checkinAccount(account.id) }
            } label: {
                Text(busy ? "…" : account.actionTitle)
                    .font(.system(size: 12.5, weight: .semibold))
                    .foregroundStyle(account.canCheckin ? Aurora.brand : Aurora.muted)
                    .padding(.horizontal, 10)
                    .frame(height: 28)
                    .background(Capsule().fill(Aurora.brand.opacity(account.canCheckin ? 0.10 : 0.04)))
            }
            .buttonStyle(.plain)
            .disabled(busy || !account.canCheckin || model.checkinBusy != nil)
        }
        .padding(.vertical, 10)
    }

    // MARK: 定时签到

    @ViewBuilder
    private var schedulePane: some View {
        SectionCard {
            StudioToggleRow(
                title: "定时签到总开关",
                isOn: Binding(
                    get: { center?.autoEnabled ?? false },
                    set: { value in Task { await model.setAutoCheckin(enabled: value) } }
                )
            )

            MonoButton(text: "添加条目", icon: "plus", style: .tonal) {
                creating = true
            }
            .padding(.top, 10)
        }

        if let schedules = center?.schedules, !schedules.isEmpty {
            ForEach(schedules) { entry in
                scheduleCard(entry)
            }
        } else {
            SectionCard {
                StudioEmpty(
                    icon: "clock",
                    title: "还没有定时条目",
                    detail: "添加一条之后，网关会在指定时间窗口内随机签到，手机不用一直开着。"
                )
            }
        }
    }

    private func scheduleCard(_ entry: CheckinSchedule) -> some View {
        SectionCard {
            HStack(spacing: 8) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(entry.displayLabel)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(Aurora.ink)
                        .lineLimit(1)
                    Text("每天 \(entry.windowText)")
                        .font(.system(size: 12))
                        .foregroundStyle(Aurora.muted)
                }
                Spacer(minLength: 4)
                Toggle("", isOn: Binding(
                    get: { entry.enabled },
                    set: { value in
                        Task {
                            await model.saveSchedule(
                                id: entry.id, label: entry.label, time: entry.time,
                                timeEnd: entry.timeEnd, enabled: value,
                                providers: entry.providers, retryTime: entry.retryTime ?? entry.time,
                                retryGapMinutes: entry.retryGapMinutes, retryLimit: entry.retryLimit
                            )
                        }
                    }
                ))
                .labelsHidden()
                .tint(Aurora.brand)
            }

            if !entry.providerRows.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(entry.providerRows, id: \.self) { row in
                        Text(row)
                            .font(.system(size: 11.5))
                            .foregroundStyle(Aurora.muted)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .padding(.top, 8)
            }

            HStack(spacing: 10) {
                Label(
                    entry.nextRunAt.map { "下次 \(CheckinParser.timeText($0))" } ?? "未安排下次执行",
                    systemImage: "clock"
                )
                .font(.system(size: 11.5))
                .foregroundStyle(Aurora.muted)
                Spacer(minLength: 4)
                if let summary = entry.lastSummary {
                    Text("上次 \(summary)")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(Aurora.inkSoft)
                        .lineLimit(1)
                }
            }
            .padding(.top, 8)

            WrapLayout(spacing: 8, lineSpacing: 8) {
                MonoButton(
                    text: model.checkinBusy == "run-\(entry.id)" ? "执行中…" : "立即执行",
                    icon: "play.fill",
                    style: .filled,
                    enabled: model.checkinBusy == nil
                ) {
                    Task { await model.runSchedule(entry.id) }
                }
                MonoButton(text: "编辑", icon: "slider.horizontal.3") {
                    editing = entry
                }
                MonoButton(text: "删除", icon: "trash", style: .danger) {
                    deleting = entry
                }
            }
            .padding(.top, 10)
        }
    }

    // MARK: 定时补签

    @ViewBuilder
    private var makeupPane: some View {
        SectionCard {
            SectionTitle(title: "补签策略")
            Text("主签到窗口内没签上的账号，会在补签到点之后按间隔重试，直到成功或用完次数。所有时间都是北京时间。")
                .font(.system(size: 12))
                .foregroundStyle(Aurora.muted)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 6)
        }

        if let schedules = center?.schedules, !schedules.isEmpty {
            ForEach(schedules) { entry in
                makeupCard(entry)
            }
        } else {
            SectionCard {
                StudioEmpty(
                    icon: "arrow.counterclockwise",
                    title: "先添加定时条目",
                    detail: "补签依附在定时条目上：没有条目就没有补签窗口。"
                )
            }
        }
    }

    private func makeupCard(_ entry: CheckinSchedule) -> some View {
        let key = entry.id
        let draft = retryDraft[key] ?? RetryDraft(entry: entry)
        return SectionCard {
            HStack(spacing: 8) {
                Text(entry.displayLabel)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Aurora.ink)
                Spacer(minLength: 4)
                Text(entry.windowText)
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundStyle(Aurora.muted)
            }

            VStack(spacing: 0) {
                HStack {
                    Text("补签到点")
                        .font(.system(size: 13.5))
                        .foregroundStyle(Aurora.inkSoft)
                    Spacer(minLength: 8)
                    DatePicker(
                        "",
                        selection: Binding(
                            get: { CheckinTime.date(draft.time) },
                            set: { retryDraft[key] = draft.with(time: CheckinTime.text($0)) }
                        ),
                        displayedComponents: .hourAndMinute
                    )
                    .labelsHidden()
                }
                .padding(.vertical, 6)

                Divider().overlay(Aurora.hairline)

                HStack {
                    Text("重试间隔")
                        .font(.system(size: 13.5))
                        .foregroundStyle(Aurora.inkSoft)
                    Spacer(minLength: 8)
                    Stepper(
                        "\(draft.gap) 分钟",
                        value: Binding(
                            get: { draft.gap },
                            set: { retryDraft[key] = draft.with(gap: $0) }
                        ),
                        in: 1...120,
                        step: 5
                    )
                    .font(.system(size: 13))
                }
                .padding(.vertical, 6)

                Divider().overlay(Aurora.hairline)

                HStack {
                    Text("最多重试")
                        .font(.system(size: 13.5))
                        .foregroundStyle(Aurora.inkSoft)
                    Spacer(minLength: 8)
                    Stepper(
                        "\(draft.limit) 次",
                        value: Binding(
                            get: { draft.limit },
                            set: { retryDraft[key] = draft.with(limit: $0) }
                        ),
                        in: 0...10
                    )
                    .font(.system(size: 13))
                }
                .padding(.vertical, 6)
            }
            .padding(.top, 6)

            WrapLayout(spacing: 8, lineSpacing: 8) {
                MonoButton(
                    text: model.checkinBusy == "schedule" ? "保存中…" : "保存补签设置",
                    icon: "checkmark",
                    style: .filled,
                    enabled: model.checkinBusy == nil
                ) {
                    let current = retryDraft[key] ?? RetryDraft(entry: entry)
                    Task {
                        _ = await model.saveSchedule(
                            id: entry.id, label: entry.label, time: entry.time,
                            timeEnd: entry.timeEnd, enabled: entry.enabled,
                            providers: entry.providers, retryTime: current.time,
                            retryGapMinutes: current.gap, retryLimit: current.limit
                        )
                        retryDraft[key] = nil
                    }
                }
                MonoButton(
                    text: model.checkinBusy == "run-\(entry.id)" ? "补签中…" : "立即补签",
                    icon: "arrow.counterclockwise",
                    enabled: model.checkinBusy == nil
                ) {
                    Task { await model.runSchedule(entry.id) }
                }
            }
            .padding(.top, 10)

            if entry.retryCount > 0 {
                Text("当前有 \(entry.retryCount) 个账号在等窗口重试")
                    .font(.system(size: 11.5))
                    .foregroundStyle(Aurora.warning)
                    .padding(.top, 8)
            }
        }
    }

    // MARK: 记录

    @ViewBuilder
    private var recordsPane: some View {
        SectionCard {
            HStack {
                SectionTitle(title: "签到记录", trailing: "共 \(model.checkinRecordsTotal) 条")
                Spacer(minLength: 0)
            }

            if model.checkinRecordsLoading && model.checkinRecords.isEmpty {
                loadingRow("正在读取记录…")
            } else if model.checkinRecords.isEmpty {
                StudioEmpty(
                    icon: "list.bullet.rectangle",
                    title: "这段时间还没有签到记录",
                    detail: nil
                )
                .padding(.top, 6)
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(model.checkinRecords.enumerated()), id: \.element.id) { index, record in
                        if index > 0 {
                            Rectangle().fill(Aurora.hairline).frame(height: 1)
                        }
                        recordRow(record)
                    }
                }
                .padding(.top, 4)

                if model.checkinRecords.count < model.checkinRecordsTotal {
                    MonoButton(text: "加载更多", icon: "arrow.down.circle") {
                        Task {
                            await model.loadCheckinRecords(offset: model.checkinRecords.count, append: true)
                        }
                    }
                    .padding(.top, 10)
                }
            }

            if let error = model.checkinRecordsError {
                Text(error)
                    .font(.system(size: 11.5))
                    .foregroundStyle(Aurora.rose)
                    .padding(.top, 8)
            }
        }
    }

    private func recordRow(_ record: CheckinRecord) -> some View {
        HStack(alignment: .top, spacing: 10) {
            ProviderIcon(provider: record.provider, fallback: record.providerLabel, size: 28)

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(record.accountName)
                        .font(.system(size: 13.5, weight: .semibold))
                        .foregroundStyle(Aurora.ink)
                        .lineLimit(1)
                    Text(record.outcomeLabel)
                        .font(.system(size: 10.5, weight: .medium))
                        .foregroundStyle(record.outcomeColor)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 2)
                        .background(Capsule().fill(record.outcomeColor.opacity(0.10)))
                }
                Text("\(record.at) · \(record.providerLabel) · \(record.sourceLabel)")
                    .font(.system(size: 11))
                    .foregroundStyle(Aurora.muted)
                    .lineLimit(1)
                if !record.message.isEmpty {
                    Text(record.message)
                        .font(.system(size: 11))
                        .foregroundStyle(record.failed ? Aurora.rose : Aurora.muted)
                        .lineLimit(3)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, 9)
    }

    private func loadingRow(_ text: String) -> some View {
        HStack(spacing: 8) {
            ProgressView().controlSize(.mini)
            Text(text)
                .font(.system(size: 12))
                .foregroundStyle(Aurora.muted)
        }
        .padding(.vertical, 8)
    }
}

// MARK: - 补签草稿

private struct RetryDraft: Equatable {
    var time: String
    var gap: Int
    var limit: Int

    init(entry: CheckinSchedule) {
        time = entry.retryTime ?? entry.time
        gap = entry.retryGapMinutes
        limit = entry.retryLimit
    }

    func with(time: String) -> RetryDraft {
        var copy = self
        copy.time = time
        return copy
    }

    func with(gap: Int) -> RetryDraft {
        var copy = self
        copy.gap = gap
        return copy
    }

    func with(limit: Int) -> RetryDraft {
        var copy = self
        copy.limit = limit
        return copy
    }
}

// MARK: - 时间小工具

enum CheckinTime {

    static func date(_ text: String) -> Date {
        let parts = text.split(separator: ":").compactMap { Int($0) }
        let calendar = Calendar.current
        var components = calendar.dateComponents([.year, .month, .day], from: Date())
        components.hour = parts.count > 0 ? parts[0] : 0
        components.minute = parts.count > 1 ? parts[1] : 0
        return calendar.date(from: components) ?? Date()
    }

    static func text(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"
        return formatter.string(from: date)
    }
}

// MARK: - 定时条目编辑器

private struct ScheduleDraft {
    var id: String?
    var label: String
    var time: String
    var timeEnd: String
    var enabled: Bool
    var providers: [String]
    var retryTime: String
    var retryGapMinutes: Int
    var retryLimit: Int
}

private struct ScheduleEditor: View {

    @EnvironmentObject private var model: AppModel
    @Environment(\.dismiss) private var dismiss

    let schedule: CheckinSchedule?
    var onSave: (ScheduleDraft) -> Void

    @State private var label = ""
    @State private var start = Date()
    @State private var end = Date()
    @State private var selected: Set<String> = []
    @State private var retryAt = Date()
    @State private var gap = 10
    @State private var limit = 3

    private var options: [CheckinProviderOption] {
        if let options = model.checkin?.providerOptions, !options.isEmpty { return options }
        return (model.checkin?.groups ?? []).map {
            CheckinProviderOption(id: $0.id, label: $0.label)
        }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    SectionCard {
                        SectionTitle(title: "基本信息")

                        TextField("名称（如 工作日上午）", text: $label)
                            .font(.system(size: 14))
                            .padding(.horizontal, 12)
                            .frame(height: 40)
                            .background(
                                RoundedRectangle(cornerRadius: 12, style: .continuous)
                                    .fill(Aurora.surfaceVariant)
                            )
                            .padding(.top, 8)

                        HStack {
                            Text("开始").font(.system(size: 13.5)).foregroundStyle(Aurora.inkSoft)
                            Spacer()
                            DatePicker("", selection: $start, displayedComponents: .hourAndMinute)
                                .labelsHidden()
                        }
                        .padding(.top, 8)

                        HStack {
                            Text("结束").font(.system(size: 13.5)).foregroundStyle(Aurora.inkSoft)
                            Spacer()
                            DatePicker("", selection: $end, displayedComponents: .hourAndMinute)
                                .labelsHidden()
                        }
                        .padding(.top, 6)
                    }

                    SectionCard {
                        SectionTitle(title: "参与提供商", trailing: "已选 \(selected.count)")

                        WrapLayout(spacing: 8, lineSpacing: 8) {
                            ForEach(options) { option in
                                StudioChip(
                                    text: option.label,
                                    active: selected.contains(option.id)
                                ) {
                                    if selected.contains(option.id) {
                                        selected.remove(option.id)
                                    } else {
                                        selected.insert(option.id)
                                    }
                                }
                            }
                        }
                        .padding(.top, 8)
                    }

                    SectionCard {
                        SectionTitle(title: "补签")

                        HStack {
                            Text("补签到点").font(.system(size: 13.5)).foregroundStyle(Aurora.inkSoft)
                            Spacer()
                            DatePicker("", selection: $retryAt, displayedComponents: .hourAndMinute)
                                .labelsHidden()
                        }
                        .padding(.top, 8)

                        HStack {
                            Text("重试间隔").font(.system(size: 13.5)).foregroundStyle(Aurora.inkSoft)
                            Spacer()
                            Stepper("\(gap) 分钟", value: $gap, in: 1...120, step: 5)
                                .font(.system(size: 13))
                        }
                        .padding(.top, 6)

                        HStack {
                            Text("最多重试").font(.system(size: 13.5)).foregroundStyle(Aurora.inkSoft)
                            Spacer()
                            Stepper("\(limit) 次", value: $limit, in: 0...10)
                                .font(.system(size: 13))
                        }
                        .padding(.top, 6)
                    }
                }
                .padding(16)
            }
            .scrollIndicators(.hidden)
            .background(AuroraBackdrop())
            .navigationTitle(schedule == nil ? "添加定时签到" : "编辑定时签到")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") {
                        onSave(
                            ScheduleDraft(
                                id: schedule?.id,
                                label: label.isEmpty ? CheckinTime.text(start) : label,
                                time: CheckinTime.text(start),
                                timeEnd: CheckinTime.text(end),
                                enabled: schedule?.enabled ?? true,
                                providers: selected.isEmpty ? options.map(\.id) : Array(selected),
                                retryTime: CheckinTime.text(retryAt),
                                retryGapMinutes: gap,
                                retryLimit: limit
                            )
                        )
                        dismiss()
                    }
                    .disabled(options.isEmpty)
                }
            }
        }
        .onAppear(perform: load)
    }

    private func load() {
        guard let schedule else {
            start = CheckinTime.date("00:01")
            end = CheckinTime.date("00:30")
            retryAt = CheckinTime.date("00:10")
            selected = Set(options.map(\.id))
            return
        }
        label = schedule.label
        start = CheckinTime.date(schedule.time)
        end = CheckinTime.date(schedule.timeEnd ?? schedule.time)
        retryAt = CheckinTime.date(schedule.retryTime ?? schedule.time)
        gap = schedule.retryGapMinutes
        limit = schedule.retryLimit
        selected = Set(schedule.providers)
    }
}
