import SwiftUI
import UniformTypeIdentifiers
import UIKit

// === 添加账号 ===
//
// 最外层先选「怎么加」：网页登录 / 手机号 / 导入文件 / 自定义提供商；
// 前两种再选提供商（就是面板那一整份目录，已添加的排在前面），
// 然后进各自的表单。所有请求都走面板真实接口：
//   · 网页登录：GET /api/session/login/methods → POST /start → GET /wait
//   · 手机号：POST /api/session/login/sms/send → /sms/verify
//   · 导入：POST /api/accounts/import
//   · 自定义提供商：POST /api/custom-providers → POST /api/accounts

struct AddAccountScreen: View {

    @EnvironmentObject private var model: AppModel
    @Environment(\.dismiss) private var dismiss

    enum Mode: String, CaseIterable, Identifiable {
        case web, sms, file, custom

        var id: String { rawValue }

        var title: String {
            switch self {
            case .web: return "网页登录"
            case .sms: return "手机号"
            case .file: return "导入文件"
            case .custom: return "自定义提供商"
            }
        }

        var icon: String {
            switch self {
            case .web: return "globe"
            case .sms: return "iphone.gen3"
            case .file: return "doc.badge.plus"
            case .custom: return "square.grid.2x2"
            }
        }
    }

    @State private var mode: Mode = .web
    @State private var selected: ProviderSpec?
    @State private var showFilePicker = false

    // 手机号
    @State private var phone = ""
    @State private var code = ""
    @State private var codeSent = false

    // 导入
    @State private var importText = ""

    // 自定义提供商
    @State private var customName = ""
    @State private var customBase = ""
    @State private var customKey = ""
    @State private var customProtocol = "chat_completions"

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    modeBar
                    content
                    if let error = model.loginError {
                        InlineErrorCard(title: "没成功", message: error)
                    }
                    if let message = model.loginMessage {
                        Text(message)
                            .font(.system(size: 11.5))
                            .foregroundStyle(Aurora.teal)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .padding(.horizontal, 14)
                .padding(.top, 8)
                .padding(.bottom, 28)
            }
            .scrollIndicators(.hidden)
            .background(AuroraBackdrop())
            .navigationTitle(navTitle)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("关闭") {
                        Task { await model.cancelWebLogin() }
                        dismiss()
                    }
                }
                if selected != nil {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button("换提供商") { selected = nil }
                    }
                }
            }
            .onChange(of: mode) { _ in
                selected = nil
                model.loginError = nil
                model.loginMessage = nil
            }
            .fileImporter(
                isPresented: $showFilePicker,
                allowedContentTypes: [.json, .plainText, .data],
                allowsMultipleSelection: false
            ) { result in
                if case .success(let urls) = result, let url = urls.first {
                    loadFile(url)
                }
            }
        }
    }

    private var navTitle: String {
        if let selected { return selected.name }
        return "添加账号"
    }

    // MARK: 方式

    private var modeBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(Mode.allCases) { item in
                    MonoButton(
                        text: item.title,
                        icon: item.icon,
                        style: mode == item ? .filled : .tonal
                    ) {
                        mode = item
                        model.haptic()
                    }
                }
            }
            .padding(.vertical, 2)
        }
    }

    @ViewBuilder
    private var content: some View {
        switch mode {
        case .web:
            if let provider = selected {
                webLoginFlow(provider)
            } else {
                providerList
            }
        case .sms:
            if let provider = selected {
                smsFlow(provider)
            } else {
                providerList
            }
        case .file:
            importFlow
        case .custom:
            customFlow
        }
    }

    // MARK: 提供商列表

    private var providerList: some View {
        let existing = model.providers.map(\.id)
        let items = ProviderCatalog.ordered(existing: existing)
        return VStack(alignment: .leading, spacing: 10) {
            // 参照桌面端：两列网格，一格一个提供商，图标是各家官方图
            LazyVGrid(
                columns: [
                    GridItem(.flexible(), spacing: 10),
                    GridItem(.flexible(), spacing: 10)
                ],
                spacing: 10
            ) {
                ForEach(items) { spec in
                    providerTile(spec)
                }
            }

            Button {
                mode = .custom
                model.haptic()
            } label: {
                HStack(spacing: 11) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 11, style: .continuous)
                            .fill(Aurora.surfaceVariant)
                        Image(systemName: "plus")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(Aurora.inkSoft)
                    }
                    .frame(width: 34, height: 34)

                    VStack(alignment: .leading, spacing: 2) {
                        Text("自定义提供商")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(Aurora.ink)
                        Text("自己填 Base URL 与协议")
                            .font(.system(size: 10.5))
                            .foregroundStyle(Aurora.muted)
                    }
                    Spacer(minLength: 4)
                    Image(systemName: "chevron.right")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(Aurora.muted)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 12)
                .background(
                    RoundedRectangle(cornerRadius: AuroraMetrics.controlRadius, style: .continuous)
                        .fill(Aurora.surface.opacity(0.7))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: AuroraMetrics.controlRadius, style: .continuous)
                        .strokeBorder(Aurora.ink.opacity(0.05), lineWidth: 0.5)
                )
            }
            .buttonStyle(.plain)
            .padding(.top, 2)
        }
    }

    private func providerTile(_ spec: ProviderSpec) -> some View {
        let count = model.providers.first { $0.id == spec.id }?.accounts.count ?? 0
        return Button {
            selected = spec
            model.loginError = nil
            model.loginMessage = nil
            if mode == .web { Task { await model.loadLoginMethods(provider: spec.id) } }
            model.haptic()
        } label: {
            HStack(spacing: 9) {
                ProviderIcon(provider: spec.id, fallback: spec.glyph, size: 32)

                VStack(alignment: .leading, spacing: 2) {
                    Text(spec.name)
                        .font(.system(size: 12.5, weight: .semibold))
                        .foregroundStyle(Aurora.ink)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                    Text(count > 0 ? "\(count) 个账号" : "还没有账号")
                        .font(.system(size: 10))
                        .foregroundStyle(count > 0 ? Aurora.brand : Aurora.muted)
                        .lineLimit(1)
                }

                Spacer(minLength: 0)
            }
            .padding(.horizontal, 9)
            .frame(height: 58)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: AuroraMetrics.controlRadius, style: .continuous)
                    .fill(Aurora.surface.opacity(0.7))
            )
            .overlay(
                RoundedRectangle(cornerRadius: AuroraMetrics.controlRadius, style: .continuous)
                    .strokeBorder(Aurora.ink.opacity(0.05), lineWidth: 0.5)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    // MARK: 网页登录

    private func webLoginFlow(_ provider: ProviderSpec) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            if model.loginMethods.isEmpty {
                Text(model.loginError == nil ? "正在读取登录方式…" : "没有可用的登录方式")
                    .font(AuroraFont.bodySmall)
                    .foregroundStyle(Aurora.muted)
                    .padding(.vertical, 8)
            } else {
                ForEach(model.loginMethods) { method in
                    Button {
                        Task {
                            let ok = await model.startWebLogin(provider: provider.id, method: method)
                            if ok { _ = await model.waitForLogin(provider: provider.id) }
                        }
                    } label: {
                        HStack(spacing: 10) {
                            Image(systemName: method.icon)
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundStyle(Aurora.brand)
                                .frame(width: 22)
                            Text(method.label)
                                .font(.system(size: 13.5, weight: .semibold))
                                .foregroundStyle(Aurora.ink)
                            Spacer(minLength: 4)
                            if model.loginBusy {
                                ProgressView().controlSize(.mini).tint(Aurora.inkSoft)
                            } else {
                                Image(systemName: "arrow.up.right")
                                    .font(.system(size: 10, weight: .bold))
                                    .foregroundStyle(Aurora.muted)
                            }
                        }
                        .padding(.horizontal, 12)
                        .frame(height: 46)
                        .glassRow()
                    }
                    .buttonStyle(.plain)
                    .disabled(model.loginBusy)
                }

                if let url = model.loginURL, !url.isEmpty {
                    MonoButton(text: "重新打开授权页", icon: "safari", style: .outline) {
                        if let target = URL(string: url) { UIApplication.shared.open(target) }
                    }
                    .padding(.top, 4)
                }
            }
        }
    }

    // MARK: 手机号

    /// 手机号登录只支持 AutoClaw（网关的登录地区只有 autoclaw / autoclaw-intl）
    private func smsSupported(_ provider: ProviderSpec) -> Bool {
        provider.id == "autoclaw" || provider.id == "autoclaw-intl"
    }

    @ViewBuilder
    private func smsFlow(_ provider: ProviderSpec) -> some View {
        if !smsSupported(provider) {
            SectionCard {
                SectionTitle(title: "这个提供商不支持手机号登录")
                Text("手机号验证码只对 AutoClaw 开放。\(provider.name) 请在电脑的桌面面板登录一次，或用「导入文件」把现成配置带过来。")
                    .font(.system(size: 13))
                    .foregroundStyle(Aurora.muted)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 6)
                WrapLayout(spacing: 8, lineSpacing: 8) {
                    MonoButton(text: "改用网页登录", icon: "globe", style: .filled) {
                        mode = .web
                        selected = provider
                        Task { await model.loadLoginMethods(provider: provider.id) }
                    }
                    MonoButton(text: "改用导入文件", icon: "doc.badge.plus", style: .tonal) {
                        mode = .file
                        selected = provider
                    }
                }
                .padding(.top, 10)
            }
        } else {
            smsForm(provider)
        }
    }

    private func smsForm(_ provider: ProviderSpec) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            field("手机号", text: $phone, placeholder: "11 位手机号", keyboard: .phonePad)

            HStack(spacing: 8) {
                field("验证码", text: $code, placeholder: "短信验证码", keyboard: .numberPad)
                MonoButton(
                    text: codeSent ? "重新发送" : "发送验证码",
                    icon: "paperplane",
                    style: .tonal,
                    enabled: !model.loginBusy
                ) {
                    Task {
                        codeSent = await model.sendSmsCode(phone: phone, provider: provider.id)
                    }
                }
                .padding(.top, 16)
            }

            MonoButton(
                text: "登录并添加",
                icon: "checkmark",
                style: .filled,
                enabled: !model.loginBusy && !code.isEmpty
            ) {
                Task {
                    let ok = await model.verifySmsCode(phone: phone, code: code, provider: provider.id)
                    if ok { dismiss() }
                }
            }
            .padding(.top, 4)
        }
    }

    // MARK: 导入文件

    private var importFlow: some View {
        VStack(alignment: .leading, spacing: 10) {
            Button {
                showFilePicker = true
            } label: {
                HStack(spacing: 10) {
                    Image(systemName: "doc.badge.plus")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(Aurora.brand)
                    Text("选择 JSON 文件")
                        .font(.system(size: 13.5, weight: .semibold))
                        .foregroundStyle(Aurora.ink)
                    Spacer(minLength: 4)
                    Image(systemName: "chevron.right")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(Aurora.muted)
                }
                .padding(.horizontal, 12)
                .frame(height: 46)
                .glassRow()
            }
            .buttonStyle(.plain)

            TextEditor(text: $importText)
                .font(.system(size: 11.5, design: .monospaced))
                .scrollContentBackground(.hidden)
                .frame(height: 180)
                .padding(8)
                .background(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(Color.white.opacity(0.6))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .stroke(Aurora.line, lineWidth: 1)
                )

            MonoButton(
                text: "导入",
                icon: "square.and.arrow.down",
                style: .filled,
                enabled: !model.loginBusy && !importText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ) {
                Task {
                    let ok = await model.importAccounts(jsonText: importText)
                    if ok { dismiss() }
                }
            }
        }
    }

    private func loadFile(_ url: URL) {
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        if let data = try? Data(contentsOf: url),
           let text = String(data: data, encoding: .utf8) {
            importText = text
        } else {
            model.loginError = "读不到这个文件"
        }
    }

    // MARK: 自定义提供商

    private var customFlow: some View {
        VStack(alignment: .leading, spacing: 10) {
            field("名称", text: $customName, placeholder: "例如：我的中转", keyboard: .default)
            field("Base URL", text: $customBase, placeholder: "https://example.com/v1", keyboard: .URL)
            field("API Key", text: $customKey, placeholder: "sk-…", keyboard: .default)

            StudioSelect(
                title: "协议",
                value: customProtocol,
                options: [
                    .init(id: "chat_completions", title: "OpenAI 兼容（chat/completions）", note: nil),
                    .init(id: "anthropic", title: "Anthropic（v1/messages）", note: nil)
                ]
            ) { customProtocol = $0 }

            MonoButton(
                text: "创建并添加",
                icon: "plus",
                style: .filled,
                enabled: !model.loginBusy && !customName.isEmpty && !customBase.isEmpty
            ) {
                Task {
                    let ok = await model.createCustomProvider(
                        name: customName,
                        baseURL: customBase,
                        apiKey: customKey,
                        protocolName: customProtocol
                    )
                    if ok { dismiss() }
                }
            }
            .padding(.top, 4)
        }
    }

    // MARK: 输入框

    private func field(
        _ title: String,
        text: Binding<String>,
        placeholder: String,
        keyboard: UIKeyboardType = .default
    ) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(title)
                .font(.system(size: 11))
                .foregroundStyle(Aurora.muted)
            TextField(placeholder, text: text)
                .font(.system(size: 13))
                .foregroundStyle(Aurora.ink)
                .keyboardType(keyboard)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .padding(.horizontal, 11)
                .frame(height: 42)
                .background(
                    RoundedRectangle(cornerRadius: 11, style: .continuous)
                        .fill(Color.white.opacity(0.62))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 11, style: .continuous)
                        .stroke(Aurora.line, lineWidth: 1)
                )
        }
    }
}

// MARK: - 玻璃行

extension View {
    /// 添加账号里的每一行：透明玻璃 + 细描边，和全局按钮一个体系。
    func glassRow() -> some View {
        background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color.white.opacity(0.55))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(Aurora.line, lineWidth: 1)
        )
    }
}
