import SwiftUI

// === 账号余额（可视化）===
//
// 替代原来那张「原始字段」弹层：一行一个账号，左图标 + 名称，右侧直接给余额数值；
// 下面小字是「剩 1200 / 5000 积分」「11-10 18:58 更新」；
// 有额外指标（可用/冻结/今日已用）就排成小胶囊。
//
// 顶部「刷新全部」走快照接口（快、不打扰上游），每行的 ⟳ 走单账号实时查询（慢、准确）。

struct BalanceSheet: View {

    @EnvironmentObject private var model: AppModel
    @Environment(\.dismiss) private var dismiss

    private var accounts: [AccountItem] {
        model.providers.flatMap(\.accounts)
    }

    private var queried: Int {
        accounts.filter { model.balanceByAccount[$0.id] != nil }.count
    }

    private var failed: Int {
        accounts.filter { model.balanceByAccount[$0.id]?.hasError == true }.count
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    summary

                    if let error = model.balanceError {
                        InlineErrorCard(
                            title: "余额读取失败",
                            message: error,
                            hint: "余额由网关上的插件提供；有的提供商根本没有余额概念，会一直显示「未查询」。",
                            actionTitle: "重试",
                            action: { Task { await model.queryBalances() } }
                        )
                    }

                    if accounts.isEmpty {
                        StudioEmpty(
                            icon: "creditcard",
                            title: "还没有账号",
                            detail: "先在「账号 → 添加账号」里加一个，再回来看余额。"
                        )
                    }

                    ForEach(model.providers) { provider in
                        if !provider.accounts.isEmpty {
                            providerCard(provider)
                        }
                    }
                }
                .padding(16)
            }
            .scrollIndicators(.hidden)
            .background(AuroraBackdrop())
            .navigationTitle("账号余额")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("关闭") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button {
                        Task { await model.queryBalances() }
                    } label: {
                        Image(systemName: "arrow.clockwise")
                    }
                    .disabled(model.balancesLoading)
                }
            }
            .task {
                if model.balanceByAccount.isEmpty { await model.queryBalances() }
            }
        }
    }

    private var summary: some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 3) {
                Text("\(queried) / \(accounts.count) 个账号有余额数据")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Aurora.ink)
                Text(
                    model.balancesUpdatedAt.map { "更新于 \($0.formatted("HH:mm:ss"))" }
                        ?? "还没有查询过"
                )
                .font(.system(size: 11.5))
                .foregroundStyle(Aurora.muted)
            }
            Spacer(minLength: 6)
            if failed > 0 {
                Text("\(failed) 个失败")
                    .font(.system(size: 11.5, weight: .medium))
                    .foregroundStyle(Aurora.rose)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Capsule().fill(Aurora.rose.opacity(0.10)))
            }
            if model.balancesLoading {
                ProgressView().controlSize(.small)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: AuroraMetrics.controlRadius, style: .continuous)
                .fill(Aurora.surface)
        )
    }

    private func providerCard(_ provider: AccountProvider) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 8) {
                // 分组标题要比条目里的账号名更重，不然层级是倒挂的
                Text(provider.label)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Aurora.ink)
                Spacer(minLength: 4)
                Text("\(provider.accounts.count) 个账号")
                    .font(.system(size: 11))
                    .foregroundStyle(Aurora.muted)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(Capsule().fill(Aurora.surfaceVariant))
            }
            .padding(.horizontal, 14)
            .padding(.top, 13)
            .padding(.bottom, 8)

            ForEach(Array(provider.accounts.enumerated()), id: \.element.id) { index, account in
                if index > 0 {
                    Rectangle()
                        .fill(Aurora.hairline)
                        .frame(height: 1)
                        // 和文字左边缘对齐（14 内边距 + 34 头像 + 11 间距 = 59）
                        .padding(.leading, 59)
                }
                row(account)
            }
        }
        .padding(.bottom, 4)
        .background(
            RoundedRectangle(cornerRadius: AuroraMetrics.cardRadius, style: .continuous)
                .fill(Aurora.surface)
        )
    }

    /// 一行 = 左「谁」/ 右「多少钱」。
    ///
    /// 原来的排法是竖着堆：账号名一行、余额一行、三四个灰色胶囊挤成一行，
    /// 胶囊里名字和数字还要换行 —— 中文被逐字折断，三个胶囊宽高都不一致，
    /// 看上去就是一堆方块。现在：
    ///   · 余额变成**行尾的主数值**（右对齐、等宽数字），和账号名同一水平线；
    ///   · 额度明细改成**单列列表**（名称在左、数值在右），一行一项，不再折行；
    ///   · 「查询于」固定在最后一行，和时间、明细共用同一条左轴。
    private func row(_ account: AccountItem) -> some View {
        let balance = model.balanceByAccount[account.id]
        let busy = model.balanceBusyID == account.id
        let metrics = balance?.metrics ?? []

        return VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .center, spacing: 11) {
                ProviderIcon(provider: account.provider, fallback: account.name, size: 34)

                VStack(alignment: .leading, spacing: 2) {
                    Text(account.name)
                        .font(.system(size: 14.5, weight: .semibold))
                        .foregroundStyle(Aurora.ink)
                        .lineLimit(1)
                        .minimumScaleFactor(0.9)

                    Text(statusLine(account))
                        .font(.system(size: 10.5))
                        .foregroundStyle(Aurora.muted)
                        .lineLimit(1)
                }

                Spacer(minLength: 6)

                // 余额：整行最大的一个数，右对齐，跟账号名同一水平线
                VStack(alignment: .trailing, spacing: 1) {
                    HStack(spacing: 7) {
                        Text(balance?.primary ?? "未查询")
                            .font(.system(size: 17, weight: .semibold))
                            .foregroundStyle(balance?.tint ?? Aurora.muted)
                            .monospacedDigit()
                            .lineLimit(1)
                            .minimumScaleFactor(0.72)

                        refreshButton(account: account, busy: busy)
                    }

                    if let secondary = balance?.secondary, !secondary.isEmpty {
                        Text(secondary)
                            .font(.system(size: 9.5))
                            .foregroundStyle(Aurora.muted)
                            .lineLimit(1)
                    }
                }
            }

            // 额度明细：一行一项，名称可截断、数值右对齐，不再塞进胶囊里换行
            if !metrics.isEmpty {
                VStack(spacing: 5) {
                    ForEach(Array(metrics.prefix(3))) { metric in
                        HStack(spacing: 8) {
                            Text(metric.label)
                                .font(.system(size: 10.5))
                                .foregroundStyle(Aurora.muted)
                                // 券名很长（「CodeBuddy个人版国内运营裂变包」），
                                // 允许折成两行，别截成两条看起来一样的「CodeBuddy个人版…」
                                .lineLimit(2)
                                .fixedSize(horizontal: false, vertical: true)
                                .multilineTextAlignment(.leading)
                            Spacer(minLength: 6)
                            Text(metric.value)
                                .font(.system(size: 10.5, weight: .semibold))
                                .foregroundStyle(Aurora.inkSoft)
                                .monospacedDigit()
                                .lineLimit(1)
                        }
                    }
                }
                .padding(.top, 8)
                .padding(.leading, 45)
            }

            if let error = balance?.error, !error.isEmpty {
                Text(error)
                    .font(.system(size: 10.5))
                    .foregroundStyle(Aurora.rose)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 6)
                    .padding(.leading, 45)
            }

            HStack(spacing: 6) {
                Text(balance.map { "查询于 \($0.atText)" } ?? "点右侧 ⟳ 实时查询")
                    .font(.system(size: 9.5))
                    .foregroundStyle(Aurora.muted)
                Spacer(minLength: 4)
                if metrics.count > 3 {
                    Text("还有 \(metrics.count - 3) 项")
                        .font(.system(size: 9.5))
                        .foregroundStyle(Aurora.muted)
                }
            }
            .padding(.top, 7)
            .padding(.leading, 45)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
    }

    /// 账号名下面那行：只留「启用状态」和「到期」，余额已经单独摆在右边了
    private func statusLine(_ account: AccountItem) -> String {
        var parts: [String] = [account.enabled ? "已启用" : "已停用"]
        if let expires = account.expiresAt, !expires.isEmpty { parts.append("到期 \(expires)") }
        if let proxy = account.proxy, !proxy.isEmpty { parts.append(proxy) }
        return parts.joined(separator: " · ")
    }

    /// 刷新单个账号：收成 26pt 的灰底小圆，别再拿品牌蓝去抢余额的视线
    private func refreshButton(account: AccountItem, busy: Bool) -> some View {
        Button {
            Task { await model.refreshBalance(id: account.id) }
        } label: {
            Group {
                if busy {
                    ProgressView().controlSize(.mini)
                } else {
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 10.5, weight: .semibold))
                        .foregroundStyle(Aurora.inkSoft)
                }
            }
            .frame(width: 26, height: 26)
            .background(Circle().fill(Aurora.surfaceVariant))
            .contentShape(Circle())
        }
        .buttonStyle(PressScaleStyle(scale: 0.92))
        .disabled(model.balanceBusyID != nil)
    }
}
