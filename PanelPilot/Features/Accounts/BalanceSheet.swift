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
                Text(provider.label)
                    .font(.system(size: 12.5, weight: .semibold))
                    .foregroundStyle(Aurora.inkSoft)
                Spacer(minLength: 4)
                Text("\(provider.accounts.count) 个账号")
                    .font(.system(size: 11))
                    .foregroundStyle(Aurora.muted)
            }
            .padding(.horizontal, 14)
            .padding(.top, 12)
            .padding(.bottom, 6)

            ForEach(Array(provider.accounts.enumerated()), id: \.element.id) { index, account in
                if index > 0 {
                    Rectangle()
                        .fill(Aurora.hairline)
                        .frame(height: 1)
                        .padding(.leading, 58)
                }
                row(account)
            }
        }
        .padding(.bottom, 6)
        .background(
            RoundedRectangle(cornerRadius: AuroraMetrics.cardRadius, style: .continuous)
                .fill(Aurora.surface)
        )
    }

    private func row(_ account: AccountItem) -> some View {
        let balance = model.balanceByAccount[account.id]
        let busy = model.balanceBusyID == account.id

        return HStack(alignment: .top, spacing: 11) {
            ProviderIcon(provider: account.provider, fallback: account.name, size: 34)

            VStack(alignment: .leading, spacing: 3) {
                Text(account.name)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Aurora.ink)
                    .lineLimit(1)

                HStack(spacing: 5) {
                    Text(balance?.primary ?? "未查询")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(balance?.tint ?? Aurora.muted)
                        .monospacedDigit()
                    if let secondary = balance?.secondary, !secondary.isEmpty {
                        Text(secondary)
                            .font(.system(size: 11))
                            .foregroundStyle(Aurora.muted)
                            .lineLimit(1)
                    }
                }

                if let balance, !balance.metrics.isEmpty {
                    HStack(spacing: 6) {
                        ForEach(balance.metrics.prefix(3)) { metric in
                            HStack(spacing: 3) {
                                Text(metric.label)
                                    .foregroundStyle(Aurora.muted)
                                Text(metric.value)
                                    .foregroundStyle(Aurora.inkSoft)
                                    .monospacedDigit()
                            }
                            .font(.system(size: 10))
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Capsule().fill(Aurora.surfaceVariant))
                        }
                    }
                    .padding(.top, 1)
                }

                if let error = balance?.error, !error.isEmpty {
                    Text(error)
                        .font(.system(size: 10.5))
                        .foregroundStyle(Aurora.rose)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Text(balance.map { "查询于 \($0.atText)" } ?? "点右侧 ⟳ 实时查询")
                    .font(.system(size: 10))
                    .foregroundStyle(Aurora.muted)
            }

            Spacer(minLength: 4)

            Button {
                Task { await model.refreshBalance(id: account.id) }
            } label: {
                if busy {
                    ProgressView().controlSize(.mini)
                        .frame(width: 30, height: 30)
                } else {
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(Aurora.brand)
                        .frame(width: 30, height: 30)
                        .background(Circle().fill(Aurora.brand.opacity(0.10)))
                }
            }
            .buttonStyle(.plain)
            .disabled(model.balanceBusyID != nil)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 11)
    }
}
