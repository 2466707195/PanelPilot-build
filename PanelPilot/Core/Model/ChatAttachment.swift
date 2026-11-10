import Foundation

// === 助手输入框里的附件 ===
//
// 面板的 `/api/assistant/chat` 接受两种 user 消息形态：
//   · 纯文本：`{role:"user", content:"…"}`
//   · 多段：`{role:"user", content:[{type:"text",text:…},{type:"image_url",image_url:{url:…}}]}`
// 文件（JSON / TXT / MD）没有独立通道，桌面端也是把内容折进文本里，这里保持一致。
//
// 图片用 `data:` URL 直接内联：不依赖面板的上传接口，也不会在服务器留副本。

struct ChatAttachment: Identifiable, Equatable {

    enum Kind: Equatable {
        case image(Data, mime: String)
        case file(text: String)
    }

    var id = UUID()
    var name: String
    var kind: Kind

    var isImage: Bool {
        if case .image = kind { return true }
        return false
    }

    var byteCount: Int {
        switch kind {
        case .image(let data, _): return data.count
        case .file(let text): return text.utf8.count
        }
    }

    var sizeText: String {
        let bytes = byteCount
        if bytes >= 1024 * 1024 { return String(format: "%.1f MB", Double(bytes) / 1_048_576) }
        if bytes >= 1024 { return String(format: "%.0f KB", Double(bytes) / 1024) }
        return "\(bytes) B"
    }

    var badge: String { isImage ? "图片" : "文件" }

    var dataURL: String? {
        guard case .image(let data, let mime) = kind else { return nil }
        return "data:\(mime);base64,\(data.base64EncodedString())"
    }

    var text: String? {
        guard case .file(let text) = kind else { return nil }
        return text
    }
}

// MARK: - 访问权限（本地策略）

/// 输入框左下角的「访问权限」。
///
/// 说明：这一项**不改网关配置**，只影响这一次发送的提示词——
/// 面板的助手权限是服务器侧策略，客户端没有改它的接口，
/// 与其做一个假的开关，不如明确标成「本地策略」。
enum AssistantAccess: String, CaseIterable, Identifiable {

    case full
    case readonly
    case chatOnly

    var id: String { rawValue }

    var title: String {
        switch self {
        case .full: return "完全访问"
        case .readonly: return "只读"
        case .chatOnly: return "仅对话"
        }
    }

    var icon: String {
        switch self {
        case .full: return "bolt.fill"
        case .readonly: return "eye"
        case .chatOnly: return "bubble.left"
        }
    }

    /// 附在用户消息前面的一句约束。
    var instruction: String? {
        switch self {
        case .full: return nil
        case .readonly: return "【只读】只做查询与解释，不要修改任何配置、不要写文件、不要执行有副作用的操作。"
        case .chatOnly: return "【仅对话】只回答这个问题，不要调用任何工具。"
        }
    }
}
