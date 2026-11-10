import SwiftUI
import UIKit

// === 提供商图标 ===
//
// 图标来自面板自己的资源目录 `/ui/assets/providers/*.png`（服务端 60 个文件里
// 挑了 47 个打进包，长边统一压到 160px）。**全部随包发布，运行时不联网**，
// 与「图表与图标都在本地渲染」那条约束一致。
//
// id 与面板一致，国际版/国内版共用同一张图（`qoder-intl` → `qoder`），
// 认不出来时退回首字母方块（浅蓝底 + 蓝字，和系统「通信录」那种占位一致）。

enum ProviderAssets {

    /// 别名：面板里的 provider id → 包内资源名
    static let alias: [String: String] = [
        "autoclaw-intl": "autoclaw",
        "qoder-intl": "qoder",
        "cline-free": "cline",
        "accio-cn": "accio",
        "zcode-intl": "zcode",
        "monkeycode-intl": "monkeycode",
        "modelscope-intl": "modelscope",
        "doubao": "doubaowork",
        "doubao-work": "doubaowork",
        "glm": "glm-cn",
        "zhipu": "chatglm",
        "kimi": "kimi-work",
        "alicode-cn": "alicode",
        "alims": "alims-intl",
        "alitp": "alitp-intl",
        "ollama": "ollama-local",
        "openai-compatible": "openai",
        "custom": ""
    ]

    // 查过一次就记住，避免每帧都问一次 bundle
    private static var cache: [String: String] = [:]

    static func assetName(for provider: String) -> String? {
        let key = provider
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        guard !key.isEmpty else { return nil }
        if let cached = cache[key] { return cached.isEmpty ? nil : cached }

        var candidates: [String] = [key]
        if let mapped = alias[key], !mapped.isEmpty { candidates.append(mapped) }
        for suffix in ["-intl", "-cn", "-free", "-pool", "-pool-free"] where key.hasSuffix(suffix) {
            candidates.append(String(key.dropLast(suffix.count)))
        }
        // 面板偶尔返回 `workbuddy-cn` 这种带地区后缀的 id
        if let dash = key.firstIndex(of: "-") {
            candidates.append(String(key[key.startIndex..<dash]))
        }

        for name in candidates where UIImage(named: name) != nil {
            cache[key] = name
            return name
        }
        cache[key] = ""
        return nil
    }
}

/// 一个提供商 / 一个账号的图标。有官方图就用官方图，没有就退回首字母。
struct ProviderIcon: View {

    /// provider id，例如 `workbuddy`、`qoder-intl`
    var provider: String
    /// 兜底用的字（账号名或中文名），留空则用 provider 首字母
    var fallback: String = ""
    var size: CGFloat = 34

    private var radius: CGFloat { size * 0.28 }

    var body: some View {
        Group {
            if let asset = ProviderAssets.assetName(for: provider) {
                Image(asset)
                    .resizable()
                    .interpolation(.high)
                    .scaledToFill()
            } else {
                ZStack {
                    Color(hex: 0xE8F0FE)
                    Text(letter)
                        .font(.system(size: size * 0.44, weight: .semibold))
                        .foregroundStyle(Aurora.brand)
                }
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: radius, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: radius, style: .continuous)
                .strokeBorder(Aurora.ink.opacity(0.06), lineWidth: 0.5)
        )
        .accessibilityHidden(true)
    }

    private var letter: String {
        let base = fallback.trimmingCharacters(in: .whitespaces)
        let source = base.isEmpty ? provider : base
        return String(source.prefix(1)).uppercased()
    }
}
