import SwiftUI

// === 添加账号：提供商目录 ===
//
// id 与面板一致（取自桌面端 `accountFeatures` 表：workbuddy / raccoon / autoclaw /
// qoder / zcode / codearts / trae / loomy / kuku / officeace / antigravity /
// modelscope / atomcode / commandcode / monkeycode / orcaterm / qwenwork …）。
// 面板升级新增的提供商不在这个表里时，用「自定义提供商」填名字与 Base URL 也能加。
//
// 这里只负责「长什么样」，不负责接口：点击后由 AddAccountScreen 走各自的登录方式。

struct ProviderSpec: Identifiable, Equatable {

    var id: String
    var name: String
    /// 品牌色，用来画左侧的圆角图标底
    var tint: Color
    /// 图标里的字符（没有官方图标时用首字母/一个汉字）
    var glyph: String
    /// SF Symbol，优先于 glyph
    var symbol: String? = nil
    var note: String? = nil
}

enum ProviderCatalog {

    static let all: [ProviderSpec] = [
        .init(id: "workbuddy", name: "WorkBuddy", tint: Color(hex: 0x10B981), glyph: "W", symbol: "bolt.horizontal.circle.fill"),
        .init(id: "raccoon", name: "小浣熊", tint: Color(hex: 0x64748B), glyph: "浣"),
        .init(id: "catpaw", name: "CatPaw", tint: Color(hex: 0x22C55E), glyph: "C"),
        .init(id: "autoclaw", name: "AutoClaw 国内版", tint: Color(hex: 0x111827), glyph: "A"),
        .init(id: "autoclaw-intl", name: "AutoClaw 国际版", tint: Color(hex: 0x374151), glyph: "A"),
        .init(id: "qoder", name: "Qoder 中国版", tint: Color(hex: 0x0EA5A5), glyph: "Q"),
        .init(id: "qoder-intl", name: "Qoder 国际版", tint: Color(hex: 0x14B8A6), glyph: "Q"),
        .init(id: "cline-free", name: "Cline Free", tint: Color(hex: 0x6B7280), glyph: "Cl"),
        .init(id: "accio", name: "Accio", tint: Color(hex: 0x111827), glyph: "Ac"),
        .init(id: "accio-cn", name: "Accio 国内版", tint: Color(hex: 0x1F2937), glyph: "Ac"),
        .init(id: "zcode", name: "ZCode 国内版", tint: Color(hex: 0x111827), glyph: "Z"),
        .init(id: "zcode-intl", name: "ZCode 国际版", tint: Color(hex: 0x1F2937), glyph: "Z"),
        .init(id: "codearts", name: "CodeArts", tint: Color(hex: 0xE8572A), glyph: "C"),
        .init(id: "trae", name: "Trae", tint: Color(hex: 0x10B981), glyph: "T"),
        .init(id: "loomy", name: "Loomy", tint: Color(hex: 0xE11D48), glyph: "L"),
        .init(id: "kuku", name: "KukuAI", tint: Color(hex: 0xF97316), glyph: "K"),
        .init(id: "monkeycode", name: "MonkeyCode", tint: Color(hex: 0xD97706), glyph: "M"),
        .init(id: "monkeycode-intl", name: "MonkeyCode 国际版", tint: Color(hex: 0xF59E0B), glyph: "M"),
        .init(id: "commandcode", name: "Command Code", tint: Color(hex: 0x111827), glyph: "CC"),
        .init(id: "antigravity", name: "Antigravity", tint: Color(hex: 0x2563EB), glyph: "An"),
        .init(id: "officeace", name: "OfficeAce 果办", tint: Color(hex: 0xEF4444), glyph: "O"),
        .init(id: "orcaterm", name: "OrcaTerm", tint: Color(hex: 0x0EA5E9), glyph: "Or"),
        .init(id: "modelscope", name: "ModelScope 国内版", tint: Color(hex: 0x7C3AED), glyph: "MS"),
        .init(id: "modelscope-intl", name: "ModelScope 国际版", tint: Color(hex: 0x8B5CF6), glyph: "MS"),
        .init(id: "atomcode", name: "AtomCode", tint: Color(hex: 0x3B82F6), glyph: "At"),
        .init(id: "astudio", name: "AStudio", tint: Color(hex: 0x8B5CF6), glyph: "AS"),
        .init(id: "doubao", name: "豆包工作", tint: Color(hex: 0x3B82F6), glyph: "豆"),
        .init(id: "kiro", name: "Kiro", tint: Color(hex: 0xA855F7), glyph: "K"),
        .init(id: "qwenwork", name: "千问办公 国内版", tint: Color(hex: 0x615CED), glyph: "千"),
        .init(id: "chatglm", name: "智谱 GLM", tint: Color(hex: 0x2563EB), glyph: "GLM"),
        .init(id: "lobsterai", name: "LobsterAI", tint: Color(hex: 0xEF4444), glyph: "Lo")
    ]

    static func spec(_ id: String) -> ProviderSpec? {
        all.first { $0.id == id }
    }

    /// 已添加的提供商优先排在前面，其余按目录顺序。
    static func ordered(existing: [String]) -> [ProviderSpec] {
        let known = Set(all.map(\.id))
        let existingKnown = existing.filter { known.contains($0) }
        var result: [ProviderSpec] = []
        for id in existingKnown {
            if let spec = spec(id), !result.contains(where: { $0.id == id }) {
                result.append(spec)
            }
        }
        for item in all where !result.contains(where: { $0.id == item.id }) {
            result.append(item)
        }
        return result
    }
}
