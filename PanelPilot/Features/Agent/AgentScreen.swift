import SwiftUI
import PhotosUI
import UniformTypeIdentifiers
import UIKit

/// Agent：服务器端的「AI 助手」与「Agent 配置」两件事，合成一个 Tab。
///
/// 助手页是**整屏对话**：消息区撑满，输入框钉在底部（`safeAreaInset`，键盘弹出自动上移）；
/// Agent 配置页才是可滚动的卡片列表。
struct AgentScreen: View {

    @EnvironmentObject private var model: AppModel

    enum Mode: String, CaseIterable { case assistant, config }

    @State private var mode: Mode = .assistant
    @State private var showHistory = false

    var body: some View {
        ZStack {
            AuroraBackdrop()

            VStack(spacing: 0) {
                AppTopBar(title: "Agent") {
                    HStack(spacing: 6) {
                        StatusPill(text: model.state.title, color: model.state.tint)
                        GlassIconButton(
                            systemIcon: "arrow.clockwise",
                            tint: Aurora.inkSoft,
                            diameter: 30,
                            iconSize: 12
                        ) {
                            Task { await model.refreshAll() }
                        }
                    }
                }

                modeBar
                    .padding(.horizontal, AuroraMetrics.pagePadding)
                    .padding(.bottom, 6)

                switch mode {
                case .assistant:
                    AssistantPane()
                case .config:
                    ScrollView {
                        VStack(alignment: .leading, spacing: AuroraMetrics.cardSpacing) {
                            AgentConfigPane()
                        }
                        .padding(.horizontal, AuroraMetrics.pagePadding)
                        .padding(.top, 4)
                        .padding(.bottom, AuroraMetrics.listBottomInset)
                        .frame(maxWidth: 640)
                        .frame(maxWidth: .infinity)
                    }
                    .scrollIndicators(.hidden)
                }
            }
        }
        .onAppear {
            Task {
                await model.load(page: .agentAssistant)
                await model.loadAgents()
                await model.loadAssistantModels()
                await model.loadGatewayKeys()
                await model.loadSessions()
            }
        }
    }

    private var modeBar: some View {
        HStack(spacing: 6) {
            ForEach(Mode.allCases, id: \.self) { item in
                MonoButton(
                    text: item == .assistant ? "AI 助手" : "Agent 配置",
                    style: mode == item ? .filled : .tonal
                ) {
                    model.haptic()
                    mode = item
                }
            }
            Spacer(minLength: 0)
            if mode == .assistant {
                MonoButton(text: "历史", icon: "clock.arrow.circlepath", style: .tonal) {
                    showHistory = true
                    Task { await model.loadSessions(force: true) }
                }
                if !model.chat.isEmpty {
                    MonoButton(text: "新对话", icon: "plus", style: .outline) {
                        model.newChat()
                    }
                }
            }
        }
        .sheet(isPresented: $showHistory) {
            ChatHistorySheet()
        }
    }
}

// MARK: - 助手（只有对话框）

private struct AssistantPane: View {

    @EnvironmentObject private var model: AppModel
    /// 输入框的底跟随「设置 → 显示 → 外观」那根滑杆
    @ObservedObject private var look = AppearanceStore.shared

    @State private var input: String = ""
    /// 输入框焦点：发完消息立刻收起键盘
    @FocusState private var inputFocused: Bool
    @State private var photoItem: PhotosPickerItem?
    @State private var showPhotoPicker = false
    @State private var showFiles = false

    private var trimmed: String {
        input.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var hasKey: Bool { !model.assistantKeyValue.isEmpty }

    private var canSend: Bool {
        (!trimmed.isEmpty || !model.attachments.isEmpty) && !model.isReplying && hasKey
    }

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 10) {
                    if model.chat.isEmpty {
                        StudioEmpty(
                            icon: "bubble.left.and.text.bubble.right",
                            title: "问点什么",
                            detail: nil
                        )
                        .padding(.top, 40)
                    } else {
                        ForEach(model.chat) { message in
                            bubble(message).id(message.id)
                        }
                    }
                    Color.clear.frame(height: 4).id("bottom")
                }
                .padding(.horizontal, AuroraMetrics.pagePadding)
                .padding(.top, 10)
                .frame(maxWidth: 640)
                .frame(maxWidth: .infinity)
            }
            .scrollIndicators(.hidden)
            // 一滑就收键盘；点空白处也收
            .scrollDismissesKeyboard(.immediately)
            .onTapGesture { inputFocused = false }
            .onChange(of: model.chat.count) { _ in
                withAnimation(.easeOut(duration: 0.2)) { proxy.scrollTo("bottom", anchor: .bottom) }
            }
            .safeAreaInset(edge: .bottom) {
                composer
                    .padding(.horizontal, AuroraMetrics.pagePadding)
                    .padding(.bottom, 8)
                    .frame(maxWidth: 640)
                    .frame(maxWidth: .infinity)
            }
        }
    }

    private func bubble(_ message: ChatMessage) -> some View {
        VStack(alignment: message.role == .user ? .trailing : .leading, spacing: 8) {
            if !message.steps.isEmpty {
                ForEach(message.steps) { step in
                    ToolStepCard(step: step)
                }
            }

            if !message.text.isEmpty || message.steps.isEmpty {
                Text(message.text.isEmpty ? "…" : message.text)
                    .font(AuroraFont.bodyMedium)
                    .foregroundStyle(Aurora.ink)
                    .textSelection(.enabled)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 9)
                    .background(
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .fill(message.role == .user ? Aurora.userBubble : Aurora.surface)
                    )
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: message.role == .user ? .trailing : .leading)
    }

    // MARK: 输入框

    private var composer: some View {
        VStack(alignment: .leading, spacing: 8) {
            if !model.attachments.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        ForEach(model.attachments) { item in
                            attachmentChip(item)
                        }
                    }
                }
            }

            TextField("发消息或做任务…", text: $input, axis: .vertical)
                .focused($inputFocused)
                .submitLabel(.send)
                .font(AuroraFont.bodyMedium)
                .foregroundStyle(Aurora.ink)
                .lineLimit(1...5)
                .padding(.horizontal, 14)
                .padding(.vertical, 12)
                .background(
                    RoundedRectangle(cornerRadius: AuroraMetrics.controlRadius, style: .continuous)
                        .fill(Aurora.surfaceVariant)
                )
                .onSubmit(send)

            HStack(spacing: 6) {
                Menu {
                    Button {
                        showPhotoPicker = true
                    } label: { Label("相册图片", systemImage: "photo") }
                    Button {
                        showFiles = true
                    } label: { Label("JSON / 文本文件", systemImage: "doc.text") }
                    if !model.attachments.isEmpty {
                        Divider()
                        Button(role: .destructive) {
                            model.clearAttachments()
                        } label: { Label("清空附件", systemImage: "xmark.circle") }
                    }
                } label: {
                    Image(systemName: "plus")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(Aurora.ink)
                        .frame(width: 32, height: 32)
                        .background(Circle().fill(Aurora.surfaceVariant))
                }

                // 工具开关：关掉就是纯文本对话（任何网关都能回）。
                // 打开后模型可以调面板接口，气泡里会出现「调用中…」卡片。
                Button {
                    model.assistantToolsEnabled.toggle()
                    model.haptic()
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "wrench.and.screwdriver")
                            .font(.system(size: 10, weight: .bold))
                        Text("工具")
                            .font(.system(size: 11.5, weight: .semibold))
                    }
                    .foregroundStyle(model.assistantToolsEnabled ? Aurora.brand : Aurora.inkSoft)
                    .padding(.horizontal, 8)
                    .frame(height: 28)
                    .background(
                        Capsule().fill(
                            model.assistantToolsEnabled
                                ? Aurora.brand.opacity(0.12)
                                : Aurora.surfaceVariant
                        )
                    )
                }
                .buttonStyle(.plain)

                Menu {
                    ForEach(AssistantAccess.allCases) { access in
                        Button {
                            model.assistantAccess = access
                            model.haptic()
                        } label: {
                            if model.assistantAccess == access {
                                Label(access.title, systemImage: "checkmark")
                            } else {
                                Text(access.title)
                            }
                        }
                    }
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: model.assistantAccess.icon)
                            .font(.system(size: 10, weight: .bold))
                        Text(model.assistantAccess.title)
                            .font(.system(size: 11.5, weight: .semibold))
                    }
                    .foregroundStyle(Aurora.warning)
                    .padding(.horizontal, 8)
                    .frame(height: 28)
                    .glassPill()
                }

                // 网关 Key：没有它面板会回「所选 API Key 已失效」
                Menu {
                    if model.gatewayKeys.isEmpty {
                        Button {
                            Task { await model.loadGatewayKeys(force: true) }
                        } label: { Label("重新读取 Key", systemImage: "arrow.clockwise") }
                    } else {
                        ForEach(model.gatewayKeys) { key in
                            Button {
                                model.assistantKeyID = key.id
                                model.haptic()
                            } label: {
                                if key.id == model.assistantKeyID {
                                    Label("\(key.name)\(key.enabled ? "" : "（停用）")", systemImage: "checkmark")
                                } else {
                                    Text("\(key.name)\(key.enabled ? "" : "（停用）")")
                                }
                            }
                        }
                        Divider()
                        Button {
                            Task { await model.loadGatewayKeys(force: true) }
                        } label: { Label("刷新 Key 列表", systemImage: "arrow.clockwise") }
                    }
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "key.horizontal")
                            .font(.system(size: 10, weight: .bold))
                        Text(hasKey ? (model.assistantKey?.name ?? "Key") : "选 Key")
                            .font(.system(size: 11.5, weight: .semibold))
                            .lineLimit(1)
                            .frame(maxWidth: 74, alignment: .leading)
                    }
                    .foregroundStyle(hasKey ? Aurora.teal : Aurora.rose)
                    .padding(.horizontal, 8)
                    .frame(height: 28)
                    .glassPill()
                }

                Spacer(minLength: 2)

                Menu {
                    Button {
                        model.assistantModel = ""
                    } label: {
                        if model.assistantModel.isEmpty {
                            Label("跟随模型", systemImage: "checkmark")
                        } else {
                            Text("跟随模型")
                        }
                    }
                    if !model.assistantModels.isEmpty {
                        Divider()
                        ForEach(model.assistantModels, id: \.self) { name in
                            Button {
                                model.assistantModel = name
                            } label: {
                                if model.assistantModel == name {
                                    Label(name, systemImage: "checkmark")
                                } else {
                                    Text(name)
                                }
                            }
                        }
                    }
                } label: {
                    HStack(spacing: 4) {
                        Circle()
                            .fill(model.assistantModel.isEmpty ? Aurora.success : Aurora.brand)
                            .frame(width: 6, height: 6)
                        Text(model.assistantModel.isEmpty ? "跟随模型" : model.assistantModel)
                            .font(.system(size: 11.5, weight: .semibold))
                            .foregroundStyle(Aurora.inkSoft)
                            .lineLimit(1)
                            .frame(maxWidth: 96, alignment: .trailing)
                        Image(systemName: "chevron.down")
                            .font(.system(size: 8, weight: .bold))
                            .foregroundStyle(Aurora.muted)
                    }
                    .padding(.horizontal, 8)
                    .frame(height: 28)
                    .glassPill()
                }

                Button {
                    if model.isReplying { model.stopChat() } else { send() }
                } label: {
                    Image(systemName: model.isReplying ? "stop.fill" : "arrow.up")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(canSend || model.isReplying ? Color.white : Aurora.muted)
                        .frame(width: 32, height: 32)
                        .background(
                            Circle().fill(
                                model.isReplying
                                    ? Aurora.danger
                                    : (canSend ? Aurora.brand : Aurora.surfaceVariant)
                            )
                        )

                }
                .buttonStyle(.plain)
                .disabled(!canSend && !model.isReplying)
            }
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: AuroraMetrics.cardRadius, style: .continuous)
                .fill(Aurora.surface.opacity(look.islandAlpha))
        )
        .shadow(color: Color.black.opacity(0.08), radius: 18, x: 0, y: 8)
        .photosPicker(isPresented: $showPhotoPicker, selection: $photoItem, matching: .images, photoLibrary: .shared())
        .onChange(of: photoItem) { item in
            guard let item else { return }
            Task { await loadPhoto(item) }
        }
        .fileImporter(
            isPresented: $showFiles,
            allowedContentTypes: [.json, .plainText, .commaSeparatedText, .text, .data],
            allowsMultipleSelection: true
        ) { result in
            if case .success(let urls) = result {
                for url in urls { loadFile(url) }
            }
        }
    }

    private func attachmentChip(_ item: ChatAttachment) -> some View {
        HStack(spacing: 5) {
            Image(systemName: item.isImage ? "photo" : "doc.text")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(Aurora.brand)
            VStack(alignment: .leading, spacing: 0) {
                Text(item.name)
                    .font(.system(size: 10.5, weight: .medium))
                    .foregroundStyle(Aurora.ink)
                    .lineLimit(1)
                    .frame(maxWidth: 110, alignment: .leading)
                Text(item.sizeText)
                    .font(.system(size: 9))
                    .foregroundStyle(Aurora.muted)
            }
            Button {
                model.removeAttachment(item.id)
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 8, weight: .bold))
                    .foregroundStyle(Aurora.muted)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Aurora.surfaceVariant)
        )
    }

    private func send() {
        guard canSend else {
            if !hasKey { model.toast = Toast(text: "先选一把网关 Key", kind: .warning) }
            return
        }
        model.sendChat(trimmed)
        input = ""
        inputFocused = false
        model.haptic()
    }

    private func loadPhoto(_ item: PhotosPickerItem) async {
        defer { photoItem = nil }
        guard let data = try? await item.loadTransferable(type: Data.self) else {
            model.toast = Toast(text: "这张图片读不出来", kind: .warning)
            return
        }
        guard let attachment = Self.imageAttachment(data: data, name: "图片 \(model.attachments.count + 1)") else {
            model.toast = Toast(text: "只支持 JPG / PNG / HEIC 图片", kind: .warning)
            return
        }
        model.addAttachment(attachment)
    }

    private func loadFile(_ url: URL) {
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }

        guard let data = try? Data(contentsOf: url) else {
            model.toast = Toast(text: "读不到 \(url.lastPathComponent)", kind: .error)
            return
        }
        if let attachment = Self.imageAttachment(data: data, name: url.lastPathComponent) {
            model.addAttachment(attachment)
            return
        }
        guard data.count <= 512 * 1024 else {
            model.toast = Toast(text: "文件超过 512 KB", kind: .warning)
            return
        }
        let text = String(data: data, encoding: .utf8)
            ?? String(data: data, encoding: .isoLatin1)
            ?? ""
        guard !text.isEmpty else {
            model.toast = Toast(text: "这个文件不是文本，没法内联", kind: .warning)
            return
        }
        model.addAttachment(ChatAttachment(name: url.lastPathComponent, kind: .file(text: text)))
    }

    /// 压到最长边 1280、JPEG 0.72：一张 4MB 的截图大约落到 200KB 以内。
    static func imageAttachment(data: Data, name: String) -> ChatAttachment? {
        guard let image = UIImage(data: data) else { return nil }
        let maxSide: CGFloat = 1280
        let longest = max(image.size.width, image.size.height)
        let scale = longest > maxSide ? maxSide / longest : 1
        let size = CGSize(width: image.size.width * scale, height: image.size.height * scale)
        let renderer = UIGraphicsImageRenderer(size: size)
        let resized = renderer.image { _ in
            image.draw(in: CGRect(origin: .zero, size: size))
        }
        guard let jpeg = resized.jpegData(compressionQuality: 0.72) else { return nil }
        return ChatAttachment(name: name, kind: .image(jpeg, mime: "image/jpeg"))
    }
}

// MARK: - 玻璃胶囊（输入框里的小控件）

extension View {
    func glassPill() -> some View {
        background(Capsule().fill(Aurora.surfaceVariant))
    }
}
