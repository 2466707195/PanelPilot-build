import SwiftUI

// === 账号：提供商 → 账号 ===
//
// 版式参照「连接应用」那一屏：顶部标题 + 右上角三个点，下面是提供商胶囊，
// 再下面是「该提供商下已添加的账号」列表。提供商与账号数量都不写死，
// 完全跟着 `/api/accounts` 返回走；点进账号看状态、代理、余额、有效期。

struct AccountsScreen: View {

    @EnvironmentObject private var model: AppModel

    @State private var providerFilter: String = ""
    @State private var detail: AccountItem?
    @State private var showAddAccount = false
    @State private var showBalances = false

    private var visibleProviders: [AccountProvider] {
        guard !providerFilter.isEmpty else { return model.providers }
        return model.providers.filter { $0.id == providerFilter }
    }

    private var totalAccounts: Int { model.providers.reduce(0) { $0 + $1.accounts.count } }
    private var enabledAccounts: Int { model.providers.reduce(0) { $0 + $1.enabledCount } }

    var body: some View {
        ZStack {
            AuroraBackdrop()

            VStack(spacing: 0) {
                AppTopBar(title: "账号") {
                    HStack(spacing: 6) {
                        ServerChip()
                        accountMenu
                    }
                }

                ScrollView {
                    VStack(alignment: .leading, spacing: AuroraMetrics.cardSpacing) {
                        providerChips
                        overviewLine

                        if let error = model.accountsError, model.providers.isEmpty {
                            InlineErrorCard(
                                title: "账号读取失败",
                                message: error,
                                hint: "检查面板版本与管理员权限；离线时这里显示的是上一次的快照。",
                                actionTitle: "重试",
                                action: { Task { await model.loadAccounts(force: true) } }
                            )
                        }

                        ForEach(visibleProviders) { provider in
                            providerSection(provider)
                        }

                        if visibleProviders.isEmpty && model.accountsError == nil {
                            SectionCard {
                                StudioEmpty(
                                    icon: "person.crop.circle.badge.plus",
                                    title: model.accountsLoading ? "正在读取账号…" : "还没有添加账号",
                                    detail: "右上角三个点 →「添加账号」。添加之后这里会按提供商分组显示。"
                                )
                            }
                        }
                    }
                    .padding(.horizontal, AuroraMetrics.pagePadding)
                    .padding(.top, 4)
                    .padding(.bottom, 96)
                    .frame(maxWidth: 640)
                    .frame(maxWidth: .infinity)
                }
                .scrollIndicators(.hidden)
                .refreshable { await model.loadAccounts(force: true) }
            }
        }
        .task { await model.loadAccounts() }
        .sheet(item: $detail) { account in
            AccountDetailSheet(account: account)
        }
        .fullScreenCover(isPresented: $showAddAccount) {
            AddAccountScreen()
        }
        .sheet(isPresented: $showBalances) {
            BalanceSheet()
        }
    }

    /// 右上角三个点：刷新 / 添加账号 / 查询余额 / 全部签到 / 切换服务器
    private var accountMenu: some View {
        Menu {
            Button {
                Task { await model.loadAccounts(force: true) }
            } label: { Label("刷新", systemImage: "arrow.clockwise") }

            Button {
                showAddAccount = true
            } label: { Label("添加账号", systemImage: "plus") }

            Button {
                Task {
                    showBalances = true
                    await model.queryBalances()
                }
            } label: { Label("查询余额", systemImage: "creditcard") }

            Button {
                Task { await model.checkinAll() }
            } label: { Label("全部签到", systemImage: "checkmark.seal") }

            Divider()

            Button {
                NotificationCenter.default.post(name: .openConnectionSettings, object: nil)
            } label: { Label("切换服务器", systemImage: "server.rack") }
        } label: {
            Image(systemName: "ellipsis")
                .font(.system(size: 15, weight: .bold))
                .foregroundStyle(Aurora.inkSoft)
                .frame(width: 32, height: 32)
                .background(Circle().fill(Aurora.surfaceVariant.opacity(0.8)))
        }
    }

    // MARK: 提供商胶囊

    private var providerChips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                StudioChip(text: "全部", active: providerFilter.isEmpty, icon: "square.grid.2x2") {
                    providerFilter = ""
                }
                ForEach(model.providers) { provider in
                    let active = providerFilter == provider.id
                    Button {
                        providerFilter = active ? "" : provider.id
                        model.haptic()
                    } label: {
                        HStack(spacing: 6) {
                            ProviderIcon(provider: provider.id, fallback: provider.label, size: 18)
                            Text("\(provider.label) \(provider.accounts.count)")
                                .font(.system(size: 13, weight: active ? .semibold : .medium))
                                .foregroundStyle(active ? Aurora.ink : Aurora.inkSoft)
                                .lineLimit(1)
                        }
                        .padding(.horizontal, 10)
                        .frame(height: 32)
                        .background(
                            Capsule().fill(Aurora.surface.opacity(active ? 1 : 0.6))
                        )
                        .overlay(
                            Capsule().strokeBorder(
                                Aurora.ink.opacity(active ? 0.14 : 0.05),
                                lineWidth: 0.5
                            )
                        )
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 1)
            .padding(.vertical, 2)
        }
    }

    private var overviewLine: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(model.accountsError == nil ? Aurora.success : Aurora.rose)
                .frame(width: 5, height: 5)
            Text("\(model.providers.count) 个提供商 · \(totalAccounts) 个账号 · \(enabledAccounts) 个启用")
                .font(.system(size: 10.5))
                .foregroundStyle(Aurora.muted)
            Spacer(minLength: 4)
            Text(model.accountsUpdatedAt?.formatted("HH:mm") ?? "—")
                .font(.system(size: 10.5))
                .foregroundStyle(Aurora.muted)
                .monospacedDigit()
        }
        .padding(.horizontal, 4)
    }

    // MARK: 一个提供商

    private func providerSection(_ provider: AccountProvider) -> some View {
        SectionCard {
            HStack(spacing: 8) {
                SectionTitle(title: provider.label, trailing: provider.summary)
                Spacer(minLength: 0)
            }

            VStack(spacing: 0) {
                ForEach(Array(provider.accounts.enumerated()), id: \.element.id) { index, account in
                    if index > 0 {
                        Rectangle().fill(Aurora.hairline).frame(height: 1)
                    }
                    accountRow(account)
                }
            }
            .padding(.top, 4)
        }
    }

    private func accountRow(_ account: AccountItem) -> some View {
        Button {
            detail = account
        } label: {
            HStack(spacing: 11) {
                ProviderIcon(
                    provider: account.provider,
                    fallback: initial(account),
                    size: 38
                )
                .opacity(account.enabled ? 1 : 0.45)

                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 5) {
                        Text(account.name)
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(Aurora.ink)
                            .lineLimit(1)
                        if account.isCurrent {
                            StudioTag(text: "当前", tint: Aurora.brand)
                        }
                    }
                    Text(subtitle(account))
                        .font(.system(size: 11.5))
                        .foregroundStyle(Aurora.muted)
                        .lineLimit(1)
                }

                Spacer(minLength: 4)

                Circle()
                    .fill(account.healthy ? Aurora.success : Aurora.rose)
                    .frame(width: 6, height: 6)

                Image(systemName: "chevron.right")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(Aurora.muted)
            }
            .padding(.vertical, 12)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func initial(_ account: AccountItem) -> String {
        let label = account.providerLabel.isEmpty ? account.provider : account.providerLabel
        return String(label.prefix(1)).uppercased()
    }

    private func subtitle(_ account: AccountItem) -> String {
        var parts: [String] = [account.statusText]
        if let balance = account.balance { parts.append("余额 \(balance)") }
        if let expires = account.expiresAt { parts.append("到期 \(expires)") }
        if let proxy = account.proxy { parts.append(proxy) }
        return parts.joined(separator: " · ")
    }
}

// MARK: - 账号详情（说人话，不铺原始字段）

struct AccountDetailSheet: View {

    @EnvironmentObject private var model: AppModel
    @Environment(\.dismiss) private var dismiss

    let account: AccountItem

    private var live: AccountItem { model.account(with: account.id) ?? account }
    private var checkin: CheckinAccount? { model.checkin?.account(id: account.id) }

    /// 一句话总结：把最要紧的几件事按人话拼起来
    private var summary: String {
        var parts: [String] = []
        if !live.enabled {
            parts.append("这个账号已停用，不参与路由")
        } else if live.healthy {
            parts.append("账号可用，正在参与路由")
        } else {
            parts.append("账号状态异常（\(live.statusText)）")
        }
        if let proxyText { parts.append("走 \(proxyText)") }
        if let balance = live.balance, !balance.isEmpty { parts.append("余额 \(balance)") }
        if let expires = live.expiresAt, !expires.isEmpty { parts.append("\(expires) 到期") }
        if let checkin {
            parts.append(checkin.status.signed ? "今天已签到" : "今天还没签")
        }
        return parts.joined(separator: "，") + "。"
    }

    /// 代理方式的通俗说法
    private var proxyText: String? {
        guard let proxy = live.proxy?.trimmingCharacters(in: .whitespaces), !proxy.isEmpty else { return nil }
        let lower = proxy.lowercased()
        if lower.contains("direct") || proxy == "直连" { return "直连（不走代理）" }
        if lower.hasPrefix("http") { return "HTTP 代理 \(proxy)" }
        if lower.hasPrefix("socks") { return "SOCKS 代理 \(proxy)" }
        return proxy
    }

    private var rows: [(String, String)] {
        var rows: [(String, String)] = []
        rows.append(("状态", live.statusText))
        if let proxyText { rows.append(("代理方式", proxyText)) }
        if let balance = live.balance, !balance.isEmpty {
            rows.append(("余额", balance))
        } else if let parsed = model.balanceByAccount[live.id] {
            rows.append(("余额", parsed.primary + (parsed.secondary.map { "（\($0)）" } ?? "")))
        } else {
            rows.append(("余额", "未查询"))
        }
        if let expires = live.expiresAt, !expires.isEmpty {
            rows.append(("有效期", expires))
        } else {
            rows.append(("有效期", "长期有效 / 未提供"))
        }
        if let checkin {
            rows.append(("今日签到", checkin.status.label))
        }
        if live.modelCount > 0 {
            rows.append(("可用模型", "\(live.modelCount) 个"))
        }
        return rows
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    header
                    summaryCard
                    detailCard
                    actions
                }
                .padding(16)
            }
            .scrollIndicators(.hidden)
            .background(AuroraBackdrop())
            .navigationTitle("账号详情")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("关闭") { dismiss() }
                }
            }
            .task {
                if model.checkin == nil { await model.loadCheckin() }
            }
        }
    }

    private var header: some View {
        HStack(spacing: 12) {
            ProviderIcon(provider: live.provider, fallback: live.name, size: 48)
                .opacity(live.enabled ? 1 : 0.5)

            VStack(alignment: .leading, spacing: 3) {
                Text(live.name)
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(Aurora.ink)
                    .lineLimit(1)
                Text(live.providerLabel.isEmpty ? live.provider : live.providerLabel)
                    .font(.system(size: 12.5))
                    .foregroundStyle(Aurora.muted)
            }

            Spacer(minLength: 4)

            if live.isCurrent {
                Text("当前账号")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(Aurora.brand)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Capsule().fill(Aurora.brand.opacity(0.10)))
            }
        }
    }

    private var summaryCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Circle()
                    .fill(live.healthy ? Aurora.success : (live.enabled ? Aurora.warning : Aurora.muted))
                    .frame(width: 7, height: 7)
                Text(summary)
                    .font(.system(size: 13.5))
                    .foregroundStyle(Aurora.ink)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: AuroraMetrics.cardRadius, style: .continuous)
                .fill(Aurora.surface)
        )
    }

    private var detailCard: some View {
        VStack(spacing: 0) {
            ForEach(Array(rows.enumerated()), id: \.offset) { index, row in
                if index > 0 {
                    Rectangle().fill(Aurora.hairline).frame(height: 1)
                }
                HStack(spacing: 10) {
                    Text(row.0)
                        .font(.system(size: 13.5))
                        .foregroundStyle(Aurora.inkSoft)
                    Spacer(minLength: 8)
                    Text(row.1)
                        .font(.system(size: 13.5, weight: .medium))
                        .foregroundStyle(Aurora.ink)
                        .multilineTextAlignment(.trailing)
                }
                .padding(.vertical, 11)
            }
        }
        .padding(.horizontal, 14)
        .background(
            RoundedRectangle(cornerRadius: AuroraMetrics.cardRadius, style: .continuous)
                .fill(Aurora.surface)
        )
    }

    private var actions: some View {
        WrapLayout(spacing: 8, lineSpacing: 8) {
            if !live.isCurrent {
                MonoButton(text: "设为当前", icon: "arrow.right.circle", style: .filled) {
                    Task {
                        await model.setCurrentAccount(live.id)
                        dismiss()
                    }
                }
            }
            MonoButton(text: "签到", icon: "checkmark.seal", style: .tonal) {
                Task { await model.checkinAccount(live.id) }
            }
            MonoButton(text: "刷新凭证", icon: "arrow.clockwise", style: .tonal) {
                Task { await model.refreshAccountToken(live.id) }
            }
            MonoButton(
                text: live.enabled ? "停用" : "启用",
                icon: live.enabled ? "pause.circle" : "play.circle",
                style: live.enabled ? .danger : .tonal
            ) {
                Task {
                    await model.setAccountEnabled(live, enabled: !live.enabled)
                    dismiss()
                }
            }
        }
    }
}
