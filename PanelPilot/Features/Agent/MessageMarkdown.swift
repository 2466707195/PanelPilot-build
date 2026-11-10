import SwiftUI
import UIKit

// === 助手消息的 Markdown 渲染 ===
//
// 面板返回的是标准 Markdown：```bash 代码块、## 标题、- 列表、`行内代码`、**强调**。
// 直接丢给 Text 会原样显示成「```bash」这种裸符号，读起来很糟，
// 所以这里做一个小而稳的解析器：**只认对话里真会出现的这几种块**，
// 不追求完整 CommonMark，也不引入第三方库。
//
// 块级：标题 / 段落 / 无序列表 / 有序列表 / 引用 / 代码块 / 表格 / 分隔线
// 行内：**粗体**、`行内代码`、[文字](链接) → 只留文字
//
// 代码块单独做成卡片：语言标签 + 复制按钮 + 横向滚动，长命令行不用折行折成一团。

// MARK: - 块模型

struct MessageBlock: Identifiable {

    enum Kind {
        case heading(level: Int, text: String)
        case paragraph(String)
        case bullets([String])
        case ordered([String])
        case quote(String)
        case code(language: String, code: String)
        case table([String])
        case divider
    }

    let id: Int
    let kind: Kind
}

// MARK: - 解析

enum MarkdownParser {

    static func parse(_ text: String) -> [MessageBlock] {
        var blocks: [MessageBlock] = []
        let lines = text.components(separatedBy: "\n")
        var index = 0

        func append(_ kind: MessageBlock.Kind) {
            blocks.append(MessageBlock(id: blocks.count, kind: kind))
        }

        func trimmed(_ line: String) -> String {
            line.trimmingCharacters(in: .whitespaces)
        }

        while index < lines.count {
            let raw = lines[index]
            let t = trimmed(raw)

            // 代码块
            if t.hasPrefix("```") {
                let language = String(t.dropFirst(3)).trimmingCharacters(in: .whitespaces)
                index += 1
                var body: [String] = []
                while index < lines.count {
                    let line = lines[index]
                    if trimmed(line).hasPrefix("```") {
                        index += 1
                        break
                    }
                    body.append(line)
                    index += 1
                }
                while let first = body.first, trimmed(first).isEmpty { body.removeFirst() }
                while let last = body.last, trimmed(last).isEmpty { body.removeLast() }
                append(.code(language: language, code: body.joined(separator: "\n")))
                continue
            }

            if t.isEmpty {
                index += 1
                continue
            }

            if t == "---" || t == "***" || t == "___" {
                append(.divider)
                index += 1
                continue
            }

            if let heading = headingOf(t) {
                append(.heading(level: heading.level, text: heading.text))
                index += 1
                continue
            }

            if isBullet(t) {
                var items: [String] = []
                while index < lines.count {
                    let line = lines[index]
                    let item = trimmed(line)
                    if isBullet(item) {
                        items.append(stripBullet(item))
                        index += 1
                    } else if !item.isEmpty, !items.isEmpty, line.hasPrefix("  ") || line.hasPrefix("\t") {
                        items[items.count - 1] += "\n" + item
                        index += 1
                    } else {
                        break
                    }
                }
                append(.bullets(items))
                continue
            }

            if isOrdered(t) {
                var items: [String] = []
                while index < lines.count {
                    let line = lines[index]
                    let item = trimmed(line)
                    if isOrdered(item) {
                        items.append(stripOrdered(item))
                        index += 1
                    } else if !item.isEmpty, !items.isEmpty, line.hasPrefix("  ") || line.hasPrefix("\t") {
                        items[items.count - 1] += "\n" + item
                        index += 1
                    } else {
                        break
                    }
                }
                append(.ordered(items))
                continue
            }

            if t.hasPrefix(">") {
                var quoted: [String] = []
                while index < lines.count {
                    let item = trimmed(lines[index])
                    guard item.hasPrefix(">") else { break }
                    quoted.append(String(item.dropFirst()).trimmingCharacters(in: .whitespaces))
                    index += 1
                }
                append(.quote(quoted.joined(separator: "\n")))
                continue
            }

            if t.hasPrefix("|") {
                var rows: [String] = []
                while index < lines.count {
                    let item = trimmed(lines[index])
                    guard item.hasPrefix("|") else { break }
                    rows.append(item)
                    index += 1
                }
                append(.table(rows))
                continue
            }

            // 普通段落：一路吃到空行或下一个块的起始
            var paragraph: [String] = []
            while index < lines.count {
                let item = trimmed(lines[index])
                if item.isEmpty || item.hasPrefix("```") || headingOf(item) != nil
                    || isBullet(item) || isOrdered(item) || item.hasPrefix(">")
                    || item.hasPrefix("|") || item == "---" {
                    break
                }
                paragraph.append(item)
                index += 1
            }
            append(.paragraph(paragraph.joined(separator: "\n")))
        }

        return blocks
    }

    // MARK: 行级判断

    private static func headingOf(_ line: String) -> (level: Int, text: String)? {
        var level = 0
        for character in line {
            if character == "#" { level += 1 } else { break }
        }
        guard level > 0, level <= 6 else { return nil }
        let rest = line.dropFirst(level)
        guard rest.first == " " else { return nil }
        return (level, rest.trimmingCharacters(in: .whitespaces))
    }

    private static func isBullet(_ line: String) -> Bool {
        guard let first = line.first, "-*+•".contains(first) else { return false }
        return line.dropFirst().first == " "
    }

    private static func stripBullet(_ line: String) -> String {
        String(line.dropFirst()).trimmingCharacters(in: .whitespaces)
    }

    private static func isOrdered(_ line: String) -> Bool {
        var digits = ""
        var rest = Substring(line)
        while let first = rest.first, first.isNumber {
            digits.append(first)
            rest = rest.dropFirst()
        }
        guard !digits.isEmpty, digits.count <= 3 else { return false }
        guard let marker = rest.first, marker == "." || marker == ")" else { return false }
        return rest.dropFirst().first == " "
    }

    private static func stripOrdered(_ line: String) -> String {
        var rest = Substring(line)
        while let first = rest.first, first.isNumber { rest = rest.dropFirst() }
        rest = rest.dropFirst()  // 丢掉 . 或 )
        return rest.trimmingCharacters(in: .whitespaces)
    }
}

// MARK: - 渲染

struct MessageMarkdown: View {

    let text: String

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            ForEach(MarkdownParser.parse(text)) { block in
                blockView(block.kind)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private func blockView(_ kind: MessageBlock.Kind) -> some View {
        switch kind {
        case let .heading(level, content):
            Text(inline(content, size: level <= 2 ? 18 : 16.5, weight: .semibold))
                .foregroundStyle(Aurora.ink)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 2)

        case let .paragraph(content):
            Text(inline(content))
                .foregroundStyle(Aurora.ink)
                .lineSpacing(3)
                .fixedSize(horizontal: false, vertical: true)

        case let .bullets(items):
            VStack(alignment: .leading, spacing: 6) {
                ForEach(Array(items.enumerated()), id: \.offset) { _, item in
                    HStack(alignment: .top, spacing: 7) {
                        Text("•")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(Aurora.muted)
                            .frame(width: 10, alignment: .leading)
                        Text(inline(item))
                            .foregroundStyle(Aurora.ink)
                            .lineSpacing(3)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }

        case let .ordered(items):
            VStack(alignment: .leading, spacing: 6) {
                ForEach(Array(items.enumerated()), id: \.offset) { offset, item in
                    HStack(alignment: .top, spacing: 7) {
                        Text("\(offset + 1).")
                            .font(.system(size: 14, weight: .semibold, design: .monospaced))
                            .foregroundStyle(Aurora.muted)
                            .frame(minWidth: 16, alignment: .leading)
                        Text(inline(item))
                            .foregroundStyle(Aurora.ink)
                            .lineSpacing(3)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }

        case let .quote(content):
            HStack(alignment: .top, spacing: 9) {
                Capsule()
                    .fill(Aurora.brand.opacity(0.35))
                    .frame(width: 2.5)
                Text(inline(content, color: Aurora.inkSoft))
                    .lineSpacing(3)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .fixedSize(horizontal: false, vertical: true)

        case let .code(language, code):
            CodeBlockCard(language: language, code: code)

        case let .table(rows):
            ScrollView(.horizontal, showsIndicators: false) {
                Text(tableText(rows))
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundStyle(Aurora.inkSoft)
                    .lineSpacing(3)
                    .textSelection(.enabled)
                    .fixedSize(horizontal: true, vertical: false)
            }

        case .divider:
            Rectangle()
                .fill(Aurora.hairline)
                .frame(height: 0.5)
                .padding(.vertical, 2)
        }
    }

    /// 表格不做真表格：保留竖线对齐原文，用等宽字体横向滚动，读起来已经够清楚。
    private func tableText(_ rows: [String]) -> String {
        rows.filter { row in
            // 丢掉 |---|:--:| 这种分隔行
            !row.replacingOccurrences(of: "|", with: "")
                .replacingOccurrences(of: "-", with: "")
                .replacingOccurrences(of: ":", with: "")
                .trimmingCharacters(in: .whitespaces)
                .isEmpty
        }.joined(separator: "\n")
    }

    // MARK: 行内样式

    /// 只处理 **粗体**、`代码`、[文字](链接)，够对话用；解析不出来就原样显示。
    private func inline(
        _ raw: String,
        size: CGFloat = 16,
        weight: Font.Weight = .regular,
        color: Color = Aurora.ink
    ) -> Text {
        var result = Text("")
        var buffer = ""
        var index = raw.startIndex

        func flush() {
            guard !buffer.isEmpty else { return }
            result = result + Text(buffer).font(.system(size: size, weight: weight)).foregroundColor(color)
            buffer = ""
        }

        while index < raw.endIndex {
            // **粗体**
            if raw[index...].hasPrefix("**"),
               let close = raw.range(of: "**", range: raw.index(index, offsetBy: 2)..<raw.endIndex) {
                flush()
                let content = String(raw[raw.index(index, offsetBy: 2)..<close.lowerBound])
                result = result + Text(content)
                    .font(.system(size: size, weight: .semibold))
                    .foregroundColor(color)
                index = close.upperBound
                continue
            }

            // `行内代码`
            if raw[index] == "`",
               let close = raw[raw.index(after: index)...].firstIndex(of: "`") {
                flush()
                let content = String(raw[raw.index(after: index)..<close])
                result = result + Text(content)
                    .font(.system(size: size - 1, weight: .medium, design: .monospaced))
                    .foregroundColor(Aurora.brand)
                index = raw.index(after: close)
                continue
            }

            // [文字](链接) → 只留文字
            if raw[index] == "[",
               let mid = raw[index...].firstIndex(of: "]"),
               let open = raw.index(mid, offsetBy: 1, limitedBy: raw.endIndex),
               open < raw.endIndex, raw[open] == "(",
               let close = raw[open...].firstIndex(of: ")") {
                flush()
                let label = String(raw[raw.index(after: index)..<mid])
                result = result + Text(label)
                    .font(.system(size: size, weight: weight))
                    .foregroundColor(Aurora.brand)
                index = raw.index(after: close)
                continue
            }

            buffer.append(raw[index])
            index = raw.index(after: index)
        }

        flush()
        return result
    }
}

// MARK: - 代码块卡片

struct CodeBlockCard: View {

    let language: String
    let code: String

    @State private var copied = false

    private var label: String {
        let trimmed = language.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return "CODE" }
        let aliases = ["sh": "shell", "zsh": "shell", "yml": "yaml", "js": "javascript", "ts": "typescript"]
        let value = aliases[trimmed.lowercased()] ?? trimmed
        return value.uppercased()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 8) {
                Text(label)
                    .font(.system(size: 10, weight: .semibold, design: .monospaced))
                    .foregroundStyle(Aurora.muted)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 3)
                    .background(Capsule().fill(Aurora.surface))

                Spacer(minLength: 0)

                Button {
                    UIPasteboard.general.string = code
                    copied = true
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.6) { copied = false }
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: copied ? "checkmark" : "doc.on.doc")
                            .font(.system(size: 10, weight: .semibold))
                        Text(copied ? "已复制" : "复制")
                            .font(.system(size: 11, weight: .semibold))
                    }
                    .foregroundStyle(copied ? Aurora.success : Aurora.brand)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 10)
            .padding(.top, 8)
            .padding(.bottom, 6)

            ScrollView(.horizontal, showsIndicators: false) {
                Text(code.isEmpty ? " " : code)
                    .font(.system(size: 12.5, design: .monospaced))
                    .foregroundStyle(Aurora.ink)
                    .lineSpacing(3.5)
                    .textSelection(.enabled)
                    .fixedSize(horizontal: true, vertical: false)
                    .padding(.horizontal, 11)
                    .padding(.bottom, 10)
                    .padding(.top, 2)
            }
        }
        .background(
            RoundedRectangle(cornerRadius: 13, style: .continuous)
                .fill(Aurora.surfaceVariant.opacity(0.72))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 13, style: .continuous)
                .strokeBorder(Aurora.hairline, lineWidth: 0.5)
        )
    }
}
