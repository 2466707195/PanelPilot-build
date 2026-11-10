import SwiftUI

// === 外观：容器「透明 ↔ 色调」===
//
// 对应「设置 → 显示 → 外观」里的那根滑杆（参照 iOS 的外观/玻璃强度控件）：
//   · 最左（透明）：卡片、浮岛、输入框都变淡，底层 #F2F2F7 透上来；
//   · 最右（色调）：容器实白，内容与控件的对比度最高。
//
// 只作用在**容器底色**上，文字、图标、分隔线不动 —— 所以把它拉到最左也不会
// 牺牲可读性，页面里不需要为「透明」再写一套配色。
//
// 为什么用单例：`SectionCard` 这类基础组件在几十处被调用，没有 AppModel 可用；
// 用 `@ObservedObject` 订阅同一个 store，改滑杆时所有容器一起重绘。

final class AppearanceStore: ObservableObject {

    static let shared = AppearanceStore()

    private let key = "panel.appearance.tint"

    /// 0 = 透明，1 = 色调（实白）。默认略偏实，保证首次打开就清楚。
    @Published var tint: Double {
        didSet { UserDefaults.standard.set(level, forKey: key) }
    }

    /// 夹到 0…1，所有换算都读它（不在 didSet 里回写，避免观察者递归）
    var level: Double { min(max(tint, 0), 1) }

    private init() {
        let stored = UserDefaults.standard.object(forKey: key) as? Double
        tint = min(max(stored ?? 0.72, 0), 1)
    }

    /// 卡片、输入框、列表行
    var cardAlpha: Double { 0.55 + 0.45 * level }

    /// 浮岛（底栏）：始终比卡片实一点，图标才不会糊在灰底上
    var islandAlpha: Double { 0.72 + 0.28 * level }

    /// 内层浅灰控件底（输入框、胶囊槽、指标块）
    var variantAlpha: Double { 0.50 + 0.50 * level }

    /// 一句话描述当前档位，设置里显示在滑杆下面
    var levelText: String {
        switch level {
        case ..<0.25: return "更通透"
        case ..<0.6: return "均衡"
        case ..<0.9: return "偏实"
        default: return "最实"
        }
    }
}
