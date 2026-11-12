import SwiftUI
import UIKit

// === 可视化控件（路由 / 账号 / 设置共用）===
//
// 参考桌面端那张「独立配置」卡：标签在上、值在下，右侧一个 chevron，
// 点开是原生的单选菜单。全部用系统 `Menu`，不自己造弹层。

// MARK: - 下拉

struct StudioSelect: View {

    struct Option: Identifiable, Equatable {
        var id: String
        var title: String
        var note: String?
    }

    let title: String
    let value: String
    var options: [Option]
    var enabled: Bool = true
    var onSelect: (String) -> Void

    private var current: Option? {
        options.first { $0.id == value }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.system(size: 11.5, weight: .medium))
                .foregroundStyle(Aurora.muted)

            Menu {
                ForEach(options) { option in
                    Button {
                        onSelect(option.id)
                    } label: {
                        if option.id == value {
                            Label(option.title, systemImage: "checkmark")
                        } else {
                            Text(option.title)
                        }
                    }
                }
            } label: {
                HStack(spacing: 6) {
                    Text(current?.title ?? "未设置")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(enabled ? Aurora.ink : Aurora.muted)
                        .lineLimit(1)
                    Spacer(minLength: 2)
                    Image(systemName: "chevron.down")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(Aurora.muted)
                }
                .padding(.horizontal, 11)
                .frame(height: 38)
                .background(
                    RoundedRectangle(cornerRadius: AuroraMetrics.controlRadius, style: .continuous)
                        .fill(Aurora.surfaceVariant)
                )
                .contentShape(Rectangle())
            }
            .disabled(!enabled)
        }
    }
}

// MARK: - 胶囊

struct StudioChip: View {

    let text: String
    var active: Bool = false
    var icon: String? = nil
    var onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 5) {
                if let icon {
                    Image(systemName: icon)
                        .font(.system(size: 10, weight: .semibold))
                }
                Text(text)
                    .font(.system(size: 12.5, weight: active ? .semibold : .regular))
                    .lineLimit(1)
            }
            // 选中态必须**看得见**：之前是「白底 + 近黑字」，而卡片本身也是白的 ——
            // 选中的 chip 等于隐形，用户会以为一个都没选（供应商列表尤其明显）。
            .foregroundStyle(active ? Color.white : Aurora.inkSoft)
            .padding(.horizontal, 14)
            .frame(height: 32)
            .background(
                Capsule().fill(active ? Aurora.brand : Aurora.surfaceVariant)
            )
        }
        .buttonStyle(.plain)
    }
}

// MARK: - 小标签

struct StudioTag: View {

    let text: String
    var tint: Color = Aurora.inkSoft

    var body: some View {
        Text(text)
            .font(.system(size: 10.5, weight: .medium))
            .foregroundStyle(tint)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(Capsule().fill(tint.opacity(0.12)))
    }
}

// MARK: - 开关行

struct StudioToggleRow: View {

    let title: String
    var detail: String? = nil
    let isOn: Binding<Bool>
    var tint: Color = Aurora.brand

    var body: some View {
        Toggle(isOn: isOn) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(AuroraFont.bodyMedium)
                    .foregroundStyle(Aurora.ink)
                if let detail {
                    Text(detail)
                        .font(.system(size: 10.5))
                        .foregroundStyle(Aurora.muted)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .tint(tint)
        .padding(.vertical, 4)
    }
}

// MARK: - 空状态

struct StudioEmpty: View {

    let icon: String
    let title: String
    var detail: String? = nil

    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 22, weight: .light))
                .foregroundStyle(Aurora.muted)
            Text(title)
                .font(AuroraFont.titleSmall)
                .foregroundStyle(Aurora.inkSoft)
            if let detail {
                Text(detail)
                    .font(AuroraFont.bodySmall)
                    .foregroundStyle(Aurora.muted)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 22)
    }
}

// MARK: - 系统分享 / 导出

/// 系统分享面板：导出文件、存到「文件」、发给别人都用它。
struct ShareSheet: UIViewControllerRepresentable {

    let items: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }

    func updateUIViewController(_ controller: UIActivityViewController, context: Context) {}
}
