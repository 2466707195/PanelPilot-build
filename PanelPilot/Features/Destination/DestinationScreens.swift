import SwiftUI

// === 目录页 ===
//
// 路由 / 账号 / 及其余二级页都是「同一种页面」：顶栏 + 目录声明的全部区块。
// 少数页面（路由、账号）在区块前面加一条派生摘要，只是把已拉到的数据换个算法，
// 不额外请求，也不替代任何区块。

/// 纯目录页：按 `page.spec` 逐块渲染。
struct GenericPage: View {

    @EnvironmentObject private var model: AppModel

    let page: PanelPage

    var body: some View {
        PanelPageShell(
            title: page.title,
            onLoad: { Task { await model.load(page: page) } }
        ) {
            ForEach(page.spec.sections) { section in
                DataSection(page: page, section: section)
            }
        }
    }
}

/// 二级页：带返回按钮的目录页（从设置里进）。
struct GenericSubPage: View {

    @EnvironmentObject private var model: AppModel

    let page: PanelPage
    var onBack: () -> Void

    var body: some View {
        ZStack {
            AuroraBackdrop()

            VStack(spacing: 0) {
                AppTopBar(title: page.title, onBack: onBack) {
                    GlassIconButton(
                        systemIcon: "arrow.clockwise",
                        tint: Aurora.inkSoft,
                        diameter: 30,
                        iconSize: 12
                    ) {
                        Task { await model.refresh(page: page) }
                    }
                }

                ScrollView {
                    VStack(alignment: .leading, spacing: AuroraMetrics.cardSpacing) {
                        ForEach(page.spec.sections) { section in
                            DataSection(page: page, section: section)
                        }
                    }
                    .padding(.horizontal, AuroraMetrics.pagePadding)
                    .padding(.top, 4)
                    .padding(.bottom, AuroraMetrics.listBottomInset)
                    .frame(maxWidth: 640)
                    .frame(maxWidth: .infinity)
                }
                .scrollIndicators(.hidden)
                .refreshable { await model.refresh(page: page) }
            }
        }
        .onAppear { Task { await model.load(page: page) } }
    }
}
