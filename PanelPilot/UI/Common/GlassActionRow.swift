import SwiftUI

// === 一行等宽的玻璃按钮组 ===
//
// 用在哪：账号详情、网关 Key 详情这类「对当前这条记录做几件事」的操作条。
//
// 为什么不用现成的 `WrapLayout + MonoButton`：
//   · `WrapLayout` 会换行。四个按钮在 iPhone 上正好差一点点，于是「设为当前 / 签到」
//     占第一行、「刷新凭证 / 停用」掉到第二行 —— 视觉上像两组不同的操作，
//     实际上它们是同一组四个平行动作。
//   · `MonoButton` 的宽度由文字决定（`fixedSize`），所以「签到」（2 字）比
//     「刷新凭证」（4 字）窄一截，一排看过去参差不齐。
//   · 主按钮填了品牌蓝、其余是浅灰、危险是红字 —— 四种底色混在一条操作条上。
//
// 这里的做法：
//   · `HStack` + 每个按钮 `frame(maxWidth: .infinity)` → **等宽、等间距、永远一行**；
//   · 文字用 `lineLimit(1)` + `minimumScaleFactor` → 窄屏上缩字号而不是换行；
//   · `ViewThatFits` → 实在放不下时先丢掉图标，保住文字；
//   · 底色统一是**真透明玻璃**：`ultraThinMaterial` + 顶部白色高光 + 白色描边 +
//     一层极淡的墨色描边 + 轻投影。层级只靠文字颜色区分（墨 / 品牌 / 玫红），
//     这样一排四个按钮看起来是同一套材质，而不是四种不同的按钮。

/// 一行里的一个动作。
struct GlassActionSpec: Identifiable {

    let id = UUID()
    var title: String
    var icon: String
    /// 文字与图标的颜色。玻璃底不带色，颜色只在字上。
    var tint: Color = Aurora.ink
    var enabled: Bool = true
    var action: () -> Void
}

/// 等宽玻璃按钮组：一行、等间距、尺寸完全一致。
struct GlassActionRow: View {

    let items: [GlassActionSpec]

    var height: CGFloat = 42
    var spacing: CGFloat = 8

    var body: some View {
        HStack(spacing: spacing) {
            // 每个都 `maxWidth: .infinity`：HStack 会把可用宽度平均分，
            // 于是宽度只跟「有几个按钮」有关，跟文字多长无关。
            ForEach(items) { item in
                GlassActionButton(spec: item, height: height)
                    .frame(maxWidth: .infinity)
            }
        }
        .frame(maxWidth: .infinity)
    }
}

/// 单个玻璃按钮（不单独用；通过 `GlassActionRow` 排成一行）。
struct GlassActionButton: View {

    let spec: GlassActionSpec
    var height: CGFloat = 42

    var body: some View {
        Button {
            guard spec.enabled else { return }
            spec.action()
        } label: {
            // 先试「图标 + 文字」，宽度不够就退成「只有文字」。
            // 不这么做的话，窄屏上四字标题会把字号压到 0.6 以下、糊成一团。
            ViewThatFits(in: .horizontal) {
                label(showIcon: true)
                label(showIcon: false)
            }
            .frame(maxWidth: .infinity)
            .frame(height: height)
            .background(glass)
            .contentShape(Capsule(style: .continuous))
        }
        .buttonStyle(PressScaleStyle(scale: 0.96))
        .disabled(!spec.enabled)
        .opacity(spec.enabled ? 1 : 0.42)
        .accessibilityLabel(spec.title)
    }

    private func label(showIcon: Bool) -> some View {
        HStack(spacing: 5) {
            if showIcon {
                Image(systemName: spec.icon)
                    .font(.system(size: 12.5, weight: .semibold))
            }
            Text(spec.title)
                .font(.system(size: 13, weight: .semibold))
                .lineLimit(1)
                // 关键：允许一缩再缩，而不是换行 —— 换行就等于「不是一行」了
                .minimumScaleFactor(0.6)
                .allowsTightening(true)
        }
        .foregroundStyle(spec.tint)
        .padding(.horizontal, 6)
        // 这里**故意不写 maxWidth: .infinity**：
        // 写了等于告诉 ViewThatFits「我多宽都行」，于是它永远选第一个分支、
        // 图标永远不会被丢掉。宽度撑满交给外层那一层。
    }

    /// 真透明玻璃：材质模糊打底 + 顶部白色高光 + 双层描边 + 轻投影。
    private var glass: some View {
        Capsule(style: .continuous)
            .fill(.ultraThinMaterial)
            .overlay(
                // 高光是「上亮下暗」的线性渐变，不是整块半透明白 ——
                // 均匀加白会把背景糊成一块灰，看不出是玻璃。
                Capsule(style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [
                                Color.white.opacity(0.46),
                                Color.white.opacity(0.10),
                                Color.white.opacity(0.02)
                            ],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
            )
            .overlay(
                // 外圈白色描边（玻璃的边缘反光）
                Capsule(style: .continuous)
                    .strokeBorder(Color.white.opacity(0.62), lineWidth: 0.9)
            )
            .overlay(
                // 内圈极淡的墨色描边：纯白描边在浅色背景上会「消失」，
                // 补这一条才有轮廓
                Capsule(style: .continuous)
                    .strokeBorder(Aurora.ink.opacity(0.055), lineWidth: 0.5)
            )
            .shadow(color: Color.black.opacity(0.055), radius: 7, x: 0, y: 3)
    }
}
