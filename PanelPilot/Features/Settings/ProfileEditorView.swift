import SwiftUI
import UIKit

/// 连接编辑器：地址、方式、端口、令牌。
///
/// 这里的「测试连接」走和主页一样的 `/health`：
/// 它不需要令牌，所以能单独把「网络通不通」和「令牌对不对」拆开验证。
struct ProfileEditorView: View {

    @EnvironmentObject private var model: AppModel
    @Environment(\.dismiss) private var dismiss

    private let original: PanelProfile?

    @State private var draft: PanelProfile
    @State private var token: String
    @State private var apiKey: String
    @State private var password: String
    @State private var portText: String
    @State private var note: String

    @State private var testing = false
    @State private var testMessage: String?
    @State private var testOK = false

    init(profile: PanelProfile?) {
        let seed = profile ?? PanelProfile()
        original = profile
        _draft = State(initialValue: seed)
        _token = State(initialValue: profile.flatMap { KeychainStore.get(KeychainStore.panelTokenKey(for: $0.id)) } ?? "")
        _apiKey = State(initialValue: profile.flatMap { KeychainStore.get(KeychainStore.apiKeyKey(for: $0.id)) } ?? "")
        _password = State(initialValue: profile.flatMap { KeychainStore.get(KeychainStore.panelPasswordKey(for: $0.id)) } ?? "")
        _portText = State(initialValue: seed.port.map(String.init) ?? "")
        _note = State(initialValue: seed.note)
    }

    private var isNew: Bool { original == nil }

    var body: some View {
        ZStack {
            AuroraBackdrop()

            VStack(spacing: 0) {
                header

                ScrollView {
                    VStack(alignment: .leading, spacing: AuroraMetrics.cardSpacing) {
                        nameCard
                        modeCard
                        addressCard
                        authCard
                        testCard
                    }
                    .padding(.horizontal, AuroraMetrics.pagePadding)
                    .padding(.bottom, 28)
                }
                .scrollIndicators(.hidden)
            }
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            footer
        }
    }

    // MARK: 头部

    private var header: some View {
        HStack(spacing: 8) {
            VStack(alignment: .leading, spacing: 2) {
                Text(isNew ? "新建连接" : "编辑连接")
                    .font(AuroraFont.titleLarge)
                    .foregroundStyle(Aurora.ink)
                Text("地址填到端口，令牌单独存进钥匙串")
                    .font(AuroraFont.bodySmall)
                    .foregroundStyle(Aurora.inkSoft)
            }
            Spacer(minLength: 4)
            GlassIconButton(systemIcon: "xmark", tint: Aurora.inkSoft, diameter: 30, iconSize: 12) {
                dismiss()
            }
        }
        .padding(.horizontal, 18)
        .padding(.top, 18)
        .padding(.bottom, 12)
    }

    // MARK: 名称

    private var nameCard: some View {
        SectionCard {
            SectionTitle(title: "名字", subtitle: "只是给你自己认的，随便起")
            AuroraTextField(placeholder: "家里的台式机", text: $draft.name, systemIcon: "tag")
                .padding(.top, 10)
        }
    }

    // MARK: 方式

    private var modeCard: some View {
        SectionCard {
            SectionTitle(title: "连接方式", subtitle: "决定手机走哪条路到那台电脑")

            VStack(spacing: 8) {
                ForEach(ConnectionMode.allCases) { mode in
                    modeRow(mode)
                }
            }
            .padding(.top, 10)
        }
    }

    private func modeRow(_ mode: ConnectionMode) -> some View {
        let selected = draft.mode == mode
        return Button {
            draft.mode = mode
            draft.secure = mode.defaultSecure
            if let def = mode.defaultPort, portText.isEmpty {
                portText = String(def)
            }
            if mode == .publicNet, draft.secure == false {
                draft.secure = true
            }
            testMessage = nil
        } label: {
            HStack(alignment: .top, spacing: 10) {
                ZStack {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(mode.tint.tint(0.13))
                        .frame(width: 34, height: 34)
                    Image(systemName: mode.icon)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(mode.tint)
                }

                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 6) {
                        Text(mode.title)
                            .font(AuroraFont.titleSmall)
                            .foregroundStyle(Aurora.ink)
                        Text(mode.addressExample)
                            .font(.system(size: 10.5, weight: .regular, design: .monospaced))
                            .foregroundStyle(Aurora.muted)
                            .lineLimit(1)
                    }
                    Text(mode.summary)
                        .font(AuroraFont.bodySmall)
                        .foregroundStyle(Aurora.inkSoft)
                        .fixedSize(horizontal: false, vertical: true)
                        .multilineTextAlignment(.leading)
                }

                Spacer(minLength: 0)

                Image(systemName: selected ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 17, weight: .regular))
                    .foregroundStyle(selected ? mode.tint : Aurora.outline)
            }
            .padding(11)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(selected ? mode.tint.tint(0.06) : Color.white)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(selected ? mode.tint.opacity(0.55) : Aurora.line.opacity(0.6), lineWidth: 1)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    // MARK: 地址

    private var addressCard: some View {
        SectionCard {
            SectionTitle(title: "地址与端口", subtitle: "可以整段粘贴 http://1.2.3.4:3065")

            VStack(spacing: 8) {
                AuroraTextField(
                    placeholder: draft.mode.placeholderHost,
                    text: $draft.host,
                    systemIcon: "network",
                    keyboardType: .URL
                )

                HStack(spacing: 8) {
                    AuroraTextField(
                        placeholder: "端口 \(draft.mode.defaultPort.map(String.init) ?? "443")",
                        text: $portText,
                        systemIcon: "number",
                        keyboardType: .numberPad
                    )
                    SmallTonalButton(text: "粘贴地址", systemIcon: "doc.on.clipboard") {
                        if let text = UIPasteboard.general.string, !text.isEmpty {
                            PanelProfile.parse(text, into: &draft)
                            portText = draft.port.map(String.init) ?? ""
                            testMessage = nil
                        }
                    }
                }

                AuroraTextField(
                    placeholder: "子路径（反向代理挂在 /a2a 下时填 a2a）",
                    text: $draft.pathPrefix,
                    systemIcon: "link"
                )
            }
            .padding(.top, 10)

            HStack(spacing: 8) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("使用 HTTPS")
                        .font(AuroraFont.titleSmall)
                        .foregroundStyle(Aurora.ink)
                    Text(draft.secure ? "连接会走 TLS，证书必须受信任" : "明文传输，只建议在内网 / Tailscale 里用")
                        .font(AuroraFont.bodySmall)
                        .foregroundStyle(Aurora.muted)
                }
                Spacer(minLength: 0)
                Toggle("", isOn: $draft.secure)
                    .labelsHidden()
                    .tint(Aurora.brand)
            }
            .padding(.top, 12)

            VStack(spacing: 0) {
                KeyValueRow(label: "将访问", value: previewAddress, mono: true)
                if let hint = modeHint {
                    Text(hint)
                        .font(AuroraFont.bodySmall)
                        .foregroundStyle(Aurora.warning)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.top, 4)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(.top, 10)
        }
    }

    private var parsedPort: Int? {
        let text = portText.trimmingCharacters(in: .whitespaces)
        return text.isEmpty ? nil : Int(text)
    }

    /// 纯计算，不能在这里写 `draft` —— 视图刷新期间改 @State 会触发运行时告警。
    private var previewAddress: String {
        var temp = draft
        temp.port = parsedPort
        return temp.rootString
    }

    private var modeHint: String? {
        let host = draft.trimmedHost.lowercased()
        if host == "127.0.0.1" || host == "localhost" {
            return "127.0.0.1 在手机上指手机自己，永远连不到电脑。改成电脑的内网 IP、Tailscale IP 或域名。"
        }
        if draft.mode == .lan, let ip = LocalNetwork.wifiIPv4(),
           !host.isEmpty, let panelIP = firstIPv4(host) {
            if !sameSubnet(ip, panelIP) {
                return "手机当前是 \(ip)，和 \(panelIP) 不在同一网段，局域网方式大概率连不上。"
            }
        }
        return nil
    }

    private func firstIPv4(_ text: String) -> String? {
        let parts = text.split(separator: ".")
        guard parts.count == 4, parts.allSatisfy({ Int($0) != nil }) else { return nil }
        return text
    }

    private func sameSubnet(_ a: String, _ b: String) -> Bool {
        let pa = a.split(separator: ".")
        let pb = b.split(separator: ".")
        guard pa.count == 4, pb.count == 4 else { return true }
        return pa[0] == pb[0] && pa[1] == pb[1] && pa[2] == pb[2]
    }

    // MARK: 鉴权

    private var authCard: some View {
        SectionCard {
            SectionTitle(
                title: "认证方式",
                subtitle: "面板装了登录页就选账号密码，App 会自己换令牌"
            )

            VStack(spacing: 8) {
                ForEach(PanelAuthMode.allCases) { mode in
                    authRow(mode)
                }
            }
            .padding(.top, 10)

            VStack(spacing: 8) {
                if draft.authMode == .password {
                    AuroraTextField(
                        placeholder: "管理员账号",
                        text: $draft.username,
                        systemIcon: "person"
                    )
                    AuroraTextField(
                        placeholder: "管理员密码",
                        text: $password,
                        systemIcon: "lock",
                        isSecure: true
                    )
                } else {
                    AuroraTextField(
                        placeholder: "面板令牌 x-panel-token",
                        text: $token,
                        systemIcon: "key",
                        isSecure: true
                    )
                }
                AuroraTextField(
                    placeholder: "接口密钥 x-api-key（可留空）",
                    text: $apiKey,
                    systemIcon: "key.horizontal",
                    isSecure: true
                )
                AuroraTextField(
                    placeholder: "备注：这台机器放在哪、谁在用",
                    text: $note,
                    systemIcon: "text.bubble"
                )
            }
            .padding(.top, 12)

            Text(authFootnote)
                .font(AuroraFont.bodySmall)
                .foregroundStyle(Aurora.muted)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 8)
        }
    }

    private func authRow(_ mode: PanelAuthMode) -> some View {
        let selected = draft.authMode == mode
        return Button {
            draft.authMode = mode
            testMessage = nil
        } label: {
            HStack(alignment: .top, spacing: 10) {
                ZStack {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(Aurora.brand.tint(0.13))
                        .frame(width: 34, height: 34)
                    Image(systemName: mode.icon)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(Aurora.brand)
                }

                VStack(alignment: .leading, spacing: 3) {
                    Text(mode.title)
                        .font(AuroraFont.titleSmall)
                        .foregroundStyle(Aurora.ink)
                    Text(mode.summary)
                        .font(AuroraFont.bodySmall)
                        .foregroundStyle(Aurora.inkSoft)
                        .fixedSize(horizontal: false, vertical: true)
                        .multilineTextAlignment(.leading)
                }

                Spacer(minLength: 0)

                Image(systemName: selected ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 17, weight: .regular))
                    .foregroundStyle(selected ? Aurora.brand : Aurora.outline)
            }
            .padding(11)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(selected ? Aurora.brand.tint(0.06) : Color.white)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(selected ? Aurora.brand.opacity(0.55) : Aurora.line.opacity(0.6), lineWidth: 1)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private var authFootnote: String {
        switch draft.authMode {
        case .password:
            return "面板登录前会下一道机器校验题（altcha 工作量证明），App 在本地算完直接提交，你不用点任何东西。密码和换到的令牌都只进系统钥匙串，不写配置文件。"
        case .token:
            return "令牌不是密码，是面板自己签发的一串字符串。面板网页里随便一个 /api 请求的请求头都能看到。"
        }
    }

    // MARK: 测试

    private var testCard: some View {
        SectionCard {
            SectionTitle(title: "先测一下", subtitle: "只打 /health，不需要令牌")

            HStack(spacing: 8) {
                SmallTonalButton(
                    text: testing ? "测试中…" : "测试连接",
                    systemIcon: "bolt.horizontal",
                    enabled: !testing
                ) {
                    Task { await runTest() }
                }
                Spacer(minLength: 0)
                if let testMessage {
                    Image(systemName: testOK ? "checkmark.circle.fill" : "xmark.octagon.fill")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(testOK ? Aurora.success : Aurora.danger)
                }
            }
            .padding(.top, 10)

            if let testMessage {
                Text(testMessage)
                    .font(AuroraFont.bodySmall)
                    .foregroundStyle(testOK ? Aurora.success : Aurora.danger)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 6)
            }
        }
    }

    private func runTest() async {
        applyDraftPort()
        guard draft.isValid else {
            testOK = false
            testMessage = "先填地址。"
            return
        }
        testing = true
        testMessage = nil
        defer { testing = false }

        var probe = draft
        probe.port = parsedPort
        let api = PanelAPI(base: probe.rootString, token: token, apiKey: apiKey, timeout: 12)

        var lines: [String] = []
        do {
            let result = try await api.health()
            lines.append("连通 \(result.latencyMs)ms")
            if result.health.isHealthy {
                if result.health.modelCount > 0 {
                    lines.append("\(result.health.modelCount) 个模型")
                }
            } else {
                lines.append("面板自报：\(result.health.statusText)")
            }
            testOK = result.health.isHealthy
        } catch {
            let apiError = error as? PanelAPIError
            testOK = false
            testMessage = [apiError?.errorDescription, apiError?.hint]
                .compactMap { $0 }
                .joined(separator: "。")
            return
        }

        // 地址通了再验证「这一层能不能进去」：这才是真正会卡住的地方
        if draft.authMode == .password {
            let loginAPI = PanelAPI(base: probe.rootString, token: "", timeout: 25)
            do {
                let session = try await loginAPI.login(username: draft.username, password: password)
                lines.append("登录成功（令牌 \(session.accessToken.prefix(8))…）")
                testOK = testOK && true
            } catch {
                testOK = false
                lines.append("登录失败：\(errorText(error))")
            }
        } else if !token.isEmpty {
            do {
                _ = try await api.get("/api/stats/summary?range=today")
                lines.append("令牌可用")
            } catch {
                testOK = false
                lines.append("令牌不可用：\(errorText(error))")
            }
        }
        testMessage = lines.joined(separator: " · ")
    }

    private func errorText(_ error: Error) -> String {
        (error as? PanelAPIError)?.errorDescription
            ?? (error as? LocalizedError)?.errorDescription
            ?? error.localizedDescription
    }

    // MARK: 底部

    private var footer: some View {
        VStack(spacing: 8) {
            if original != nil {
                DangerTonalButton(text: "删除这个连接", systemIcon: "trash") {
                    if let id = original?.id {
                        model.delete(id)
                        dismiss()
                    }
                }
            }
            PrimaryButton(text: isNew ? "保存并连接" : "保存", systemIcon: "checkmark") {
                save()
            }
        }
        .padding(.horizontal, AuroraMetrics.pagePadding)
        .padding(.top, 8)
        .padding(.bottom, 10)
        .background(GlassSurface(shape: AuroraShape.bar, highlight: 0.30))
        .padding(.horizontal, AuroraMetrics.pagePadding)
    }

    private func save() {
        applyDraftPort()
        draft.note = note

        var payload = draft
        if payload.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            payload.name = payload.trimmedHost.isEmpty ? "面板" : payload.trimmedHost
        }
        guard payload.isValid else {
            testOK = false
            testMessage = "地址不能为空。"
            return
        }

        model.save(profile: payload, token: token, apiKey: apiKey, password: password)
        model.activate(payload.id)
        model.toast = Toast(text: isNew ? "已保存并连接" : "已保存", kind: .success)
        dismiss()
    }

    private func applyDraftPort() {
        draft.port = parsedPort
    }
}
