import SwiftUI

// === Agent 配置：一键接入 + 生成配置文件 ===
//
// 这一页不接管任何客户端目录，只做两件事：
//   1. 把「接入三件套」——baseURL、API Key、主力模型——填一次；
//   2. 按客户端模板生成 JSON 配置，复制或导出成文件，自己放到对应目录。
//
// 为什么不再做「预览 / 恢复 / 资源」：那些操作要写网关所在机器的文件，
// 面板只对已接管的客户端开放，绝大多数账号一打开就是满屏的「Permission denied」。
// 生成配置文件是本地动作，任何账号都能用，也不会写坏别人的目录。

struct AgentConfigPane: View {

    @EnvironmentObject private var model: AppModel

    @State private var baseURL: String = ""
    @State private var apiKey: String = ""
    @State private var modelName: String = ""
    /// 选中的提供商：配置里会写入它下面的**全部**模型
    @State private var provider: String = ""
    @State private var presetID: String = AgentPresetCatalog.all.first?.id ?? "generic"
    @State private var showShare = false
    @State private var shareItems: [Any] = []
    @State private var showKey = false
    @State private var copied = false
    /// 取密钥失败时给一句人话，不然按钮点下去毫无反馈
    @State private var keyHint: String?

    private var preset: AgentPreset {
        AgentPresetCatalog.all.first { $0.id == presetID } ?? AgentPresetCatalog.all[0]
    }

    /// 当前提供商下的全部模型（配置里全部写进去，客户端就能随时切换）
    private var providerModels: [String] {
        model.agentModels(for: provider)
    }

    private var configText: String {
        model.agentConfigText(
            preset: preset,
            baseURL: baseURL,
            apiKey: apiKey,
            model: modelName,
            models: providerModels
        )
    }

    var body: some View {
        providerCard
        onboardingCard
        presetCard
        previewCard
        tipsCard
            .task { await prepare() }
    }

    // MARK: 供应商与模型

    private var providerCard: some View {
        SectionCard {
            SectionTitle(
                title: "供应商",
                trailing: model.agentModelsLoading ? "读取中…" : "共 \(providerModels.count) 个模型"
            )

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(model.agentProviders, id: \.self) { item in
                        StudioChip(text: item, active: provider == item) {
                            provider = item
                            modelName = model.agentModels(for: item).first ?? ""
                            model.haptic()
                        }
                    }
                }
                .padding(.vertical, 2)
            }
            .padding(.top, 8)

            if providerModels.isEmpty {
                Text("还没读到这个提供商的模型，点右上角刷新；也可以直接在下面手填模型名。")
                    .font(.system(size: 11.5))
                    .foregroundStyle(Aurora.muted)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 8)
            } else {
                Text("生成配置时会把这 \(providerModels.count) 个模型一起写进去，客户端里可以直接切换。")
                    .font(.system(size: 11.5))
                    .foregroundStyle(Aurora.muted)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 8)

                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        ForEach(providerModels.prefix(12), id: \.self) { name in
                            Text(name)
                                .font(.system(size: 10, design: .monospaced))
                                .foregroundStyle(Aurora.inkSoft)
                                .padding(.horizontal, 7)
                                .padding(.vertical, 3)
                                .background(Capsule().fill(Aurora.surfaceVariant))
                        }
                        if providerModels.count > 12 {
                            Text("+\(providerModels.count - 12)")
                                .font(.system(size: 10, weight: .semibold))
                                .foregroundStyle(Aurora.muted)
                                .padding(.horizontal, 7)
                                .padding(.vertical, 3)
                        }
                    }
                }
                .padding(.top, 8)
            }

            HStack(spacing: 8) {
                MonoButton(text: "刷新模型", icon: "arrow.clockwise", style: .outline) {
                    Task { await model.loadAgentModelCatalog(force: true) }
                }
                Spacer(minLength: 0)
            }
            .padding(.top, 10)
        }
    }

    private func prepare() async {
        await model.loadAgentModelCatalog()
        // 先把面板的网关 Key 拉下来：这一页的「用本机密钥」全靠它，
        // 之前只读钥匙串里手填过的 key，没填过就永远是空，点了像没反应。
        await model.loadGatewayKeys()
        if apiKey.isEmpty, !model.assistantKeyValue.isEmpty {
            apiKey = model.assistantKeyValue
            keyHint = nil
        }
        if provider.isEmpty, let first = model.agentProviders.first {
            provider = first
        }
        if modelName.isEmpty {
            modelName = providerModels.first ?? model.assistantModels.first ?? ""
        }
        if baseURL.isEmpty { baseURL = model.defaultBaseURL }
    }

    /// 取一把能直接用的密钥：面板里启用的网关 Key 优先，其次才是用户以前手填进钥匙串的那把。
    private func applyLocalKey(explicit: Bool) async {
        if model.assistantKeyValue.isEmpty {
            await model.loadGatewayKeys(force: true)
        }
        let resolved = model.assistantKeyValue
        if !resolved.isEmpty {
            apiKey = resolved
            keyHint = nil
            model.haptic()
            if explicit {
                model.toast = Toast(text: "已填入面板的网关密钥", kind: .success)
            }
            return
        }
        let fallback = model.activeAPIKey
        if !fallback.isEmpty {
            apiKey = fallback
            keyHint = nil
            model.haptic()
            return
        }
        guard explicit else { return }
        keyHint = "面板还没有返回可用的 Key。先去「设置 → 网关 Key」新建一把，再回来点这里；或者直接点下面的「一键填入」。"
        model.toast = Toast(text: "没有可用的密钥", kind: .warning)
    }

    // MARK: 一键接入

    private var onboardingCard: some View {
        SectionCard {
            SectionTitle(title: "一键接入", trailing: model.activeProfile?.name)

            Text("填好三项，下面会自动生成对应客户端的 JSON 配置。全部在本机完成，不上传、不改服务器文件。")
                .font(AuroraFont.bodySmall)
                .foregroundStyle(Aurora.muted)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 6)

            field(
                title: "Base URL",
                text: $baseURL,
                placeholder: "https://your-panel/v1",
                mono: true
            ) {
                Button("填入默认") {
                    baseURL = model.defaultBaseURL
                    model.haptic()
                }
                .font(.system(size: 10.5, weight: .semibold))
                .foregroundStyle(Aurora.brand)
            }
            .padding(.top, 12)

            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 6) {
                    Text("API Key")
                        .font(.system(size: 11.5, weight: .medium))
                        .foregroundStyle(Aurora.muted)
                    Spacer(minLength: 0)
                    Button(showKey ? "隐藏" : "显示") {
                        showKey.toggle()
                    }
                    .font(.system(size: 10.5, weight: .semibold))
                    .foregroundStyle(Aurora.inkSoft)

                    Button("用本机密钥") {
                        Task { await applyLocalKey(explicit: true) }
                    }
                    .font(.system(size: 10.5, weight: .semibold))
                    .foregroundStyle(Aurora.brand)
                }

                Group {
                    if showKey {
                        TextField("sk-…", text: $apiKey)
                    } else {
                        SecureField("sk-…", text: $apiKey)
                    }
                }
                .font(.system(size: 12.5, design: .monospaced))
                .foregroundStyle(Aurora.ink)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .padding(.horizontal, 11)
                .frame(height: 40)
                .background(
                    RoundedRectangle(cornerRadius: 11, style: .continuous)
                        .fill(Aurora.surfaceVariant.opacity(0.7))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 11, style: .continuous)
                        .stroke(Aurora.line, lineWidth: 1)
                )

                if let keyHint {
                    Text(keyHint)
                        .font(.system(size: 11.5))
                        .foregroundStyle(Aurora.danger)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(.top, 10)

            if providerModels.isEmpty {
                field(
                    title: "主力模型",
                    text: $modelName,
                    placeholder: "例如 claude-sonnet-4",
                    mono: true
                ) { EmptyView() }
                .padding(.top, 10)
            } else {
                StudioSelect(
                    title: "主力模型",
                    value: modelName.isEmpty ? (providerModels.first ?? "") : modelName,
                    options: providerModels.map { .init(id: $0, title: $0, note: nil) }
                ) { value in
                    modelName = value
                    model.haptic()
                }
                .padding(.top, 10)
            }

            HStack(spacing: 8) {
                MonoButton(text: "一键填入", icon: "wand.and.stars", style: .filled) {
                    if baseURL.isEmpty { baseURL = model.defaultBaseURL }
                    if apiKey.isEmpty {
                        // 网关 Key 才是真正能过 /v1 鉴权的那把，手填的只作兜底
                        apiKey = model.assistantKeyValue.isEmpty ? model.activeAPIKey : model.assistantKeyValue
                    }
                    if provider.isEmpty { provider = model.agentProviders.first ?? "" }
                    if modelName.isEmpty { modelName = providerModels.first ?? model.assistantModels.first ?? "" }
                    model.haptic(.medium)
                    model.toast = Toast(
                        text: apiKey.isEmpty
                            ? "已填入地址与模型；密钥还没拿到，点右侧「用本机密钥」重试"
                            : "已填入 baseURL / 密钥 / 主模型（还会写入 \(providerModels.count) 个模型）",
                        kind: apiKey.isEmpty ? .warning : .success
                    )
                }
                MonoButton(text: "清空", icon: "eraser", style: .outline) {
                    baseURL = ""
                    apiKey = ""
                    modelName = ""
                }
            }
            .padding(.top, 12)
        }
    }

    // MARK: 客户端模板

    private var presetCard: some View {
        SectionCard {
            SectionTitle(title: "客户端", trailing: preset.target)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(AgentPresetCatalog.all) { item in
                        StudioChip(text: item.name, active: item.id == presetID) {
                            presetID = item.id
                            model.haptic()
                        }
                    }
                }
                .padding(.vertical, 2)
            }
            .padding(.top, 8)

            Text(preset.note)
                .font(.system(size: 10.5))
                .foregroundStyle(Aurora.muted)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 8)
        }
    }

    // MARK: 预览 + 导出

    private var previewCard: some View {
        SectionCard {
            SectionTitle(title: "配置预览", trailing: preset.fileName)

            ScrollView([.horizontal, .vertical], showsIndicators: false) {
                Text(configText)
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(Aurora.ink)
                    .textSelection(.enabled)
                    .padding(12)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(maxHeight: 260)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Aurora.surfaceVariant.opacity(0.5))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(Aurora.line, lineWidth: 1)
            )
            .padding(.top, 9)

            WrapLayout(spacing: 8, lineSpacing: 8) {
                MonoButton(
                    text: copied ? "已复制" : "复制",
                    icon: copied ? "checkmark" : "doc.on.doc",
                    style: .filled
                ) {
                    model.copy(configText, label: "配置已复制")
                    copied = true
                    model.haptic()
                    Task {
                        try? await Task.sleep(nanoseconds: 1_600_000_000)
                        copied = false
                    }
                }
                MonoButton(text: "导出文件", icon: "square.and.arrow.up") {
                    exportFile()
                }
                MonoButton(text: "刷新目录", icon: "arrow.clockwise", style: .outline) {
                    Task { await model.loadAgentModelCatalog(force: true) }
                }
            }
            .padding(.top, 12)
        }
        .sheet(isPresented: $showShare) {
            ShareSheet(items: shareItems)
        }
    }

    private var tipsCard: some View {
        SectionCard {
            SectionTitle(title: "说明")

            VStack(alignment: .leading, spacing: 8) {
                tip("1", "文件放哪：\(preset.target)")
                tip("2", "密钥只保留在本机与生成的文件里，不上传面板。")
                tip("3", "面板侧若改过端口或路径，Base URL 记得同步改。")
                tip("4", "想用别的客户端，选「通用（OpenAI 兼容）」，字段就三件套。")
            }
            .padding(.top, 6)
        }
    }

    private func tip(_ index: String, _ text: String) -> some View {
        HStack(alignment: .top, spacing: 7) {
            Text(index)
                .font(.system(size: 9.5, weight: .bold, design: .monospaced))
                .foregroundStyle(Aurora.brand)
                .frame(width: 16, height: 16)
                .background(Circle().fill(Aurora.brand.tint(0.12)))
            Text(text)
                .font(.system(size: 11.5))
                .foregroundStyle(Aurora.inkSoft)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: 工具

    private func exportFile() {
        guard let url = model.writeAgentConfigFile(preset: preset, text: configText) else { return }
        shareItems = [url]
        showShare = true
        model.haptic(.medium)
    }

    @ViewBuilder
    private func field<Trailing: View>(
        title: String,
        text: Binding<String>,
        placeholder: String,
        mono: Bool = false,
        @ViewBuilder trailing: () -> Trailing
    ) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Text(title)
                    .font(.system(size: 11.5, weight: .medium))
                    .foregroundStyle(Aurora.muted)
                Spacer(minLength: 0)
                trailing()
            }

            TextField(placeholder, text: text)
                .font(mono ? .system(size: 12.5, design: .monospaced) : AuroraFont.bodyMedium)
                .foregroundStyle(Aurora.ink)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .keyboardType(.URL)
                .padding(.horizontal, 11)
                .frame(height: 40)
                .background(
                    RoundedRectangle(cornerRadius: 11, style: .continuous)
                        .fill(Aurora.surfaceVariant.opacity(0.7))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 11, style: .continuous)
                        .stroke(Aurora.line, lineWidth: 1)
                )
        }
    }
}
