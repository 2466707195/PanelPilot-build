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
    @State private var presetID: String = AgentPresetCatalog.all.first?.id ?? "generic"
    @State private var showShare = false
    @State private var shareItems: [Any] = []
    @State private var showKey = false
    @State private var copied = false

    private var preset: AgentPreset {
        AgentPresetCatalog.all.first { $0.id == presetID } ?? AgentPresetCatalog.all[0]
    }

    private var configText: String {
        model.agentConfigText(preset: preset, baseURL: baseURL, apiKey: apiKey, model: modelName)
    }

    var body: some View {
        onboardingCard
        presetCard
        previewCard
        tipsCard
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
                        apiKey = model.activeAPIKey
                        model.haptic()
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
            }
            .padding(.top, 10)

            if model.assistantModels.isEmpty {
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
                    value: modelName.isEmpty ? (model.assistantModels.first ?? "") : modelName,
                    options: model.assistantModels.map { .init(id: $0, title: $0, note: nil) }
                ) { value in
                    modelName = value
                    model.haptic()
                }
                .padding(.top, 10)
            }

            HStack(spacing: 8) {
                MonoButton(text: "一键填入", icon: "wand.and.stars", style: .filled) {
                    if baseURL.isEmpty { baseURL = model.defaultBaseURL }
                    if apiKey.isEmpty { apiKey = model.activeAPIKey }
                    if modelName.isEmpty { modelName = model.assistantModels.first ?? "" }
                    model.haptic(.medium)
                    model.toast = Toast(text: "已填入 baseURL / 密钥 / 模型", kind: .success)
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
                MonoButton(text: "刷新模型", icon: "arrow.clockwise", style: .outline) {
                    Task { await model.loadAssistantModels() }
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
