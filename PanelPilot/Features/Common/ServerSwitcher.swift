import SwiftUI

// === 服务器切换 ===
//
// 连接配置本来就支持多条（`PanelProfile`，每条有自己的地址、认证方式、钥匙串与本地快照），
// 这里只补一个显眼的入口：顶栏那枚「● 服务器名 ⌄」。
// 切过去之后所有页面都按新连接重新取数（`activate` 内部会重铺快照 + 重新连）。
//
// 新增/编辑仍然在「设置 → 连接方式」里，避免两处表单不一致。

struct ServerChip: View {

    @EnvironmentObject private var model: AppModel

    @State private var show = false

    private var dotColor: Color {
        switch model.state {
        case .online: return Aurora.success
        case .connecting: return Aurora.warning
        case .degraded: return Aurora.warning
        case .failed: return Aurora.rose
        default: return Aurora.muted
        }
    }

    var body: some View {
        Button {
            model.haptic()
            show = true
        } label: {
            HStack(spacing: 5) {
                Circle()
                    .fill(dotColor)
                    .frame(width: 6, height: 6)
                Text(model.activeProfile?.name ?? "未连接")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(Aurora.ink)
                    .lineLimit(1)
                    .frame(maxWidth: 92, alignment: .leading)
                Image(systemName: "chevron.down")
                    .font(.system(size: 8, weight: .bold))
                    .foregroundStyle(Aurora.muted)
            }
            .padding(.horizontal, 9)
            .frame(height: 28)
            .background(Capsule().fill(Aurora.surfaceVariant))
        }
        .buttonStyle(.plain)
        .sheet(isPresented: $show) {
            ServerSwitcherSheet()
        }
    }
}

struct ServerSwitcherSheet: View {

    @EnvironmentObject private var model: AppModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 10) {
                    if model.profiles.isEmpty {
                        StudioEmpty(
                            icon: "server.rack",
                            title: "还没有服务器",
                            detail: "去「设置 → 连接方式」新建一个，填地址和登录方式。"
                        )
                    }

                    ForEach(model.profiles) { profile in
                        row(profile)
                    }

                    Button {
                        dismiss()
                        NotificationCenter.default.post(name: .openConnectionSettings, object: nil)
                    } label: {
                        HStack(spacing: 10) {
                            Image(systemName: "plus")
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundStyle(Aurora.brand)
                                .frame(width: 30, height: 30)
                                .background(Circle().fill(Aurora.brand.opacity(0.10)))
                            VStack(alignment: .leading, spacing: 2) {
                                Text("添加或管理服务器")
                                    .font(.system(size: 14, weight: .semibold))
                                    .foregroundStyle(Aurora.ink)
                                Text("在「连接方式」里新建、编辑、测连通")
                                    .font(.system(size: 11))
                                    .foregroundStyle(Aurora.muted)
                            }
                            Spacer(minLength: 4)
                            Image(systemName: "chevron.right")
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundStyle(Aurora.muted)
                        }
                        .padding(12)
                        .background(
                            RoundedRectangle(cornerRadius: AuroraMetrics.controlRadius, style: .continuous)
                                .fill(Aurora.surface)
                        )
                    }
                    .buttonStyle(.plain)
                    .padding(.top, 4)
                }
                .padding(16)
            }
            .scrollIndicators(.hidden)
            .background(AuroraBackdrop())
            .navigationTitle("切换服务器")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("关闭") { dismiss() }
                }
            }
        }
    }

    private func row(_ profile: PanelProfile) -> some View {
        let active = profile.id == model.activeID
        return Button {
            guard !active else { dismiss(); return }
            model.activate(profile.id)
            model.haptic(.medium)
            dismiss()
        } label: {
            HStack(spacing: 10) {
                ZStack {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(active ? Aurora.brand.opacity(0.12) : Aurora.surfaceVariant)
                    Image(systemName: "server.rack")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(active ? Aurora.brand : Aurora.inkSoft)
                }
                .frame(width: 32, height: 32)

                VStack(alignment: .leading, spacing: 2) {
                    Text(profile.name.isEmpty ? profile.trimmedHost : profile.name)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(Aurora.ink)
                        .lineLimit(1)
                    Text(profile.displayAddress)
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(Aurora.muted)
                        .lineLimit(1)
                }

                Spacer(minLength: 4)

                if active {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 17))
                        .foregroundStyle(Aurora.brand)
                }
            }
            .padding(12)
            .background(
                RoundedRectangle(cornerRadius: AuroraMetrics.controlRadius, style: .continuous)
                    .fill(Aurora.surface)
            )
            .overlay(
                RoundedRectangle(cornerRadius: AuroraMetrics.controlRadius, style: .continuous)
                    .strokeBorder(active ? Aurora.brand.opacity(0.30) : Color.clear, lineWidth: 1)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}
