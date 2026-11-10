import SwiftUI

// === 路由：可视化配置 ===
//
// 对齐桌面端那张「独立配置」卡：上方是模型，中间三个下拉（路由策略 / 会话粘滞 /
// 参与方式），下方是全局保护摘要与「已保存 / 保存路由」，再往下是参与名单。
//
// 数据：`GET /api/routing/workspace[?model=]`；保存：`PUT /api/routing/profile`。
// 保存失败会把服务端原话显示出来，不会静默吞掉。

struct RoutingScreen: View {

    @EnvironmentObject private var model: AppModel

    @State private var expandedProviders: Set<String> = []
    @State private var showRaw = false

    var body: some View {
        PanelPageShell(
            title: "路由",
            onLoad: { Task { await model.loadRouting() } }
        ) {
            modelChips
            if let error = model.routingError, model.routing.raw == .null {
                InlineErrorCard(
                    title: "路由配置读取失败",
                    message: error,
                    hint: "面板需要 `/api/routing/workspace`（2.x 版本提供）。",
                    actionTitle: "重试",
                    action: { Task { await model.loadRouting() } }
                )
            } else if model.routingLoading && model.routing.raw == .null {
                loadingCard
            } else {
                configCard
                rosterCard
                runtimeCard
            }
            footer
        }
        .sheet(isPresented: $showRaw) {
            JSONDetailSheet(
                title: "路由原始数据",
                json: model.routing.raw,
                onCopy: { text in model.copy(text) }
            )
        }
    }

    // MARK: 模型选择

    private var modelChips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                StudioChip(
                    text: "全局默认",
                    active: model.routingModel.isEmpty,
                    icon: "globe"
                ) {
                    Task { await model.selectRoutingModel("") }
                }
                ForEach(model.routingModels, id: \.self) { name in
                    StudioChip(text: name, active: model.routingModel == name) {
                        Task { await model.selectRoutingModel(name) }
                    }
                }
                if model.routingLoading {
                    ProgressView()
                        .controlSize(.mini)
                        .tint(Aurora.inkSoft)
                        .padding(.horizontal, 4)
                }
            }
            .padding(.horizontal, 1)
            .padding(.vertical, 2)
        }
    }

    // MARK: 配置卡

    private var configCard: some View {
        SectionCard {
            HStack(alignment: .top, spacing: 10) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(eyebrow)
                        .font(.system(size: 10.5, weight: .semibold))
                        .foregroundStyle(Aurora.muted)
                    Text(model.routingModel.isEmpty ? "全局默认" : model.routingModel)
                        .font(.system(size: 18, weight: .bold))
                        .foregroundStyle(Aurora.ink)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                }

                Spacer(minLength: 4)

                Menu {
                    Button {
                        Task { await model.loadRouting() }
                    } label: { Label("重新读取", systemImage: "arrow.clockwise") }
                    Button {
                        showRaw = true
                    } label: { Label("查看原始数据", systemImage: "curlybraces") }
                } label: {
                    Image(systemName: "ellipsis")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(Aurora.inkSoft)
                        .frame(width: 30, height: 30)
                        .background(Circle().fill(Aurora.surfaceVariant.opacity(0.8)))
                }
            }

            HStack(alignment: .top, spacing: 10) {
                StudioSelect(
                    title: "路由策略",
                    value: model.routingDraft.strategy.rawValue,
                    options: strategyOptions
                ) { value in
                    model.updateRoutingDraft { draft in
                        draft.strategy = RoutingStrategy(rawValue: value) ?? .inherit
                    }
                }
                StudioSelect(
                    title: "会话粘滞",
                    value: model.routingDraft.sticky.rawValue,
                    options: stickyOptions
                ) { value in
                    model.updateRoutingDraft { draft in
                        draft.sticky = RoutingSticky(rawValue: value) ?? .inherit
                    }
                }
            }
            .padding(.top, 12)

            StudioSelect(
                title: "参与方式",
                value: model.routingDraft.scope.rawValue,
                options: scopeOptions
            ) { value in
                model.updateRoutingDraft { draft in
                    draft.scope = RoutingScope(rawValue: value) ?? .all
                }
            }
            .padding(.top, 10)

            Text(model.routingDraft.scope.note)
                .font(.system(size: 11))
                .foregroundStyle(Aurora.muted)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 8)

            Rectangle()
                .fill(Aurora.hairline)
                .frame(height: 1)
                .padding(.vertical, 11)

            HStack(spacing: 7) {
                Image(systemName: "shield")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(Aurora.inkSoft)
                Text("全局保护设置")
                    .font(AuroraFont.bodySmall)
                    .foregroundStyle(Aurora.inkSoft)
                Spacer(minLength: 4)
                StudioTag(text: model.routing.protectionText, tint: Aurora.brand)
            }

            HStack(spacing: 8) {
                HStack(spacing: 5) {
                    Circle()
                        .fill(model.routingDirty ? Aurora.warning : Aurora.success)
                        .frame(width: 5, height: 5)
                    Text(model.routingDirty ? "\(dirtyCount) 处未保存" : "已保存")
                        .font(.system(size: 11))
                        .foregroundStyle(Aurora.muted)
                }
                Spacer(minLength: 4)
                MonoButton(
                    text: "撤销修改",
                    style: .outline,
                    enabled: model.routingDirty && !model.routingSaving
                ) {
                    model.discardRouting()
                    model.haptic()
                }
                MonoButton(
                    text: model.routingSaving ? "保存中" : "保存路由",
                    icon: "checkmark",
                    style: .filled,
                    enabled: model.routingDirty && !model.routingSaving
                ) {
                    Task { await model.saveRouting() }
                }
            }
            .padding(.top, 12)
        }
    }

    private var eyebrow: String {
        if model.routingModel.isEmpty { return "默认规则" }
        return model.routing.customized ? "独立配置" : "继承全局"
    }

    private var dirtyCount: Int {
        var count = 0
        if model.routingDraft.strategy.rawValue != (model.routing.strategy ?? RoutingStrategy.inherit.rawValue) { count += 1 }
        if model.routingDraft.sticky.rawValue != (model.routing.sticky ?? RoutingSticky.inherit.rawValue) { count += 1 }
        if model.routingDraft.scope.rawValue != model.routing.providerScope { count += 1 }
        if model.routingDraft.disabledProviders != Set(model.routing.disabledProviders) { count += 1 }
        return max(count, 1)
    }

    private var strategyOptions: [StudioSelect.Option] {
        var items: [StudioSelect.Option] = []
        if !model.routingModel.isEmpty {
            items.append(
                .init(
                    id: RoutingStrategy.inherit.rawValue,
                    title: "继承全局：\(RoutingStrategy.title(globalStrategy))",
                    note: nil
                )
            )
        }
        for item in [RoutingStrategy.order, .rotate, .provider] {
            items.append(.init(id: item.rawValue, title: item.title, note: item.note))
        }
        return items
    }

    private var globalStrategy: String? {
        model.routing.raw.obj("globalSettings")?.firstString(["routingStrategy"])
    }

    private var stickyOptions: [StudioSelect.Option] {
        var items: [StudioSelect.Option] = []
        if !model.routingModel.isEmpty {
            let global = model.routing.raw.obj("globalSettings")?.firstString(["routingSticky"])
            items.append(
                .init(
                    id: RoutingSticky.inherit.rawValue,
                    title: "继承全局：\(RoutingSticky.title(global))",
                    note: nil
                )
            )
        }
        for item in [RoutingSticky.auto, .session, .turn, .off] {
            items.append(.init(id: item.rawValue, title: item.title, note: item.note))
        }
        return items
    }

    private var scopeOptions: [StudioSelect.Option] {
        [RoutingScope.all, .selected].map {
            .init(id: $0.rawValue, title: $0.title, note: $0.note)
        }
    }

    // MARK: 参与名单

    private var rosterCard: some View {
        SectionCard {
            SectionTitle(
                title: "参与名单",
                trailing: "\(includedProviderCount) / \(model.routing.providerRefs.count) 个提供商"
            )

            if model.routing.providerRefs.isEmpty {
                StudioEmpty(
                    icon: "square.stack.3d.up.slash",
                    title: "没有可参与的提供商",
                    detail: "先在账号页添加账号；有账号的提供商才会出现在这里。"
                )
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(model.routing.providerRefs.enumerated()), id: \.element.id) { index, provider in
                        if index > 0 {
                            Rectangle().fill(Aurora.hairline).frame(height: 1)
                        }
                        providerRow(provider)
                    }
                }
                .padding(.top, 6)
            }
        }
    }

    private func providerRow(_ provider: RoutingProviderRef) -> some View {
        let accounts = model.routing.accounts(of: provider.id)
        let included = !model.routingDraft.disabledProviders.contains(provider.id)
        let expanded = expandedProviders.contains(provider.id)

        return VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 8) {
                Button {
                    withAnimation(.easeInOut(duration: 0.18)) {
                        if expanded { expandedProviders.remove(provider.id) }
                        else { expandedProviders.insert(provider.id) }
                    }
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: expanded ? "chevron.down" : "chevron.right")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundStyle(Aurora.muted)
                            .frame(width: 12)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(provider.label)
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundStyle(Aurora.ink)
                            Text("\(accounts.count) 个账号 · \(accounts.filter(\.enabled).count) 启用")
                                .font(.system(size: 10.5))
                                .foregroundStyle(Aurora.muted)
                        }
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)

                Spacer(minLength: 4)

                if !provider.available {
                    StudioTag(text: "不可用", tint: Aurora.rose)
                }

                Toggle("", isOn: Binding(
                    get: { included },
                    set: { model.toggleRoutingProvider(provider.id, included: $0) }
                ))
                .labelsHidden()
                .tint(Aurora.brand)
                .scaleEffect(0.85)
            }
            .padding(.vertical, 9)

            if expanded {
                VStack(spacing: 6) {
                    if accounts.isEmpty {
                        Text("这个提供商还没有账号")
                            .font(.system(size: 11))
                            .foregroundStyle(Aurora.muted)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.leading, 18)
                    } else {
                        ForEach(accounts) { account in
                            HStack(spacing: 8) {
                                Circle()
                                    .fill(account.enabled ? Aurora.success : Aurora.muted)
                                    .frame(width: 5, height: 5)
                                Text(account.name)
                                    .font(.system(size: 12))
                                    .foregroundStyle(Aurora.inkSoft)
                                    .lineLimit(1)
                                Spacer(minLength: 4)
                                Toggle("", isOn: Binding(
                                    get: { account.enabled },
                                    set: { value in
                                        Task { await model.setAccountEnabled(account, enabled: value) }
                                    }
                                ))
                                .labelsHidden()
                                .tint(Aurora.brand)
                                .scaleEffect(0.75)
                            }
                            .padding(.leading, 18)
                            .padding(.vertical, 3)
                        }
                    }
                }
                .padding(.bottom, 8)
            }
        }
    }

    private var includedProviderCount: Int {
        model.routing.providerRefs.filter { !model.routingDraft.disabledProviders.contains($0.id) }.count
    }

    // MARK: 运行态

    private var runtimeCard: some View {
        SectionCard {
            SectionTitle(title: "运行态", trailing: model.routingUpdatedAt?.formatted("HH:mm:ss"))

            VStack(spacing: 0) {
                KeyValueRow(label: "配置文件", value: model.routingModel.isEmpty ? "全局默认" : model.routingModel, mono: true)
                KeyValueRow(label: "独立配置", value: model.routing.customized ? "是" : "否")
                KeyValueRow(label: "版本号", value: model.routing.revision.map(String.init) ?? "—", mono: true)
                KeyValueRow(label: "账号总数", value: "\(model.routing.accounts.count)")
            }
            .padding(.top, 4)
        }
    }

    private var loadingCard: some View {
        SectionCard {
            HStack(spacing: 8) {
                ProgressView().controlSize(.small).tint(Aurora.inkSoft)
                Text("正在读取路由工作区…")
                    .font(AuroraFont.bodySmall)
                    .foregroundStyle(Aurora.muted)
            }
        }
    }

    private var footer: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(model.routingDirty ? Aurora.warning : Aurora.success)
                .frame(width: 5, height: 5)
            Text(
                model.routingDirty
                    ? "改动只在本地，点「保存路由」才写到面板"
                    : "配置已与面板一致 · \(model.routingUpdatedAt?.formatted("HH:mm") ?? "—")"
            )
            .font(.system(size: 10.5))
            .foregroundStyle(Aurora.muted)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 4)
    }
}
