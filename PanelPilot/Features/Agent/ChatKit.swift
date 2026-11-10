import SwiftUI

// === 对话里的两个小组件 ===
//
// 1) `ToolStepCard`：一次工具调用的卡片（「获取模型列表 · 查看结果 · ✓ 131 个模型」）。
//    调用中显示进度、完成后显示结果摘要，点开能看原始返回。
// 2) `ChatHistorySheet`：历史会话列表，点一条就接着聊（会从面板读回整段对话）。

struct ToolStepCard: View {

    let step: ChatToolStep

    @State private var expanded = false

    private var hasDetail: Bool { !step.detail.isEmpty }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button {
                guard hasDetail else { return }
                withAnimation(.easeOut(duration: 0.18)) { expanded.toggle() }
            } label: {
                HStack(spacing: 10) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 9, style: .continuous)
                            .fill(step.tint.opacity(0.12))
                        Image(systemName: step.icon)
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(step.tint)
                    }
                    .frame(width: 30, height: 30)

                    VStack(alignment: .leading, spacing: 2) {
                        Text(step.label)
                            .font(.system(size: 13.5, weight: .semibold))
                            .foregroundStyle(Aurora.ink)
                            .lineLimit(1)
                        if hasDetail {
                            Text(expanded ? "收起结果" : "查看结果")
                                .font(.system(size: 11))
                                .foregroundStyle(Aurora.muted)
                        }
                    }

                    Spacer(minLength: 6)

                    HStack(spacing: 4) {
                        if step.status == .running {
                            ProgressView().controlSize(.mini)
                        } else {
                            Image(systemName: step.status == .done ? "checkmark" : "exclamationmark")
                                .font(.system(size: 10, weight: .bold))
                        }
                        Text(step.statusText)
                            .font(.system(size: 11.5, weight: .medium))
                            .lineLimit(1)
                    }
                    .foregroundStyle(step.tint)
                    .padding(.horizontal, 9)
                    .padding(.vertical, 4)
                    .background(Capsule().fill(step.tint.opacity(0.10)))

                    if hasDetail {
                        Image(systemName: expanded ? "chevron.up" : "chevron.down")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundStyle(Aurora.muted)
                    }
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 9)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if expanded, hasDetail {
                Divider().overlay(Aurora.hairline)
                ScrollView {
                    Text(step.detail)
                        .font(.system(size: 10.5, design: .monospaced))
                        .foregroundStyle(Aurora.inkSoft)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(10)
                }
                .frame(maxHeight: 180)
            }
        }
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Aurora.surface)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(step.tint.opacity(0.16), lineWidth: 0.8)
        )
        .frame(maxWidth: 480, alignment: .leading)
    }
}

// MARK: - 历史会话

struct ChatHistorySheet: View {

    @EnvironmentObject private var model: AppModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    if let error = model.sessionsError {
                        InlineErrorCard(
                            title: "历史会话读取失败",
                            message: error,
                            hint: "网关版本较旧时可能没有这个接口，不影响新对话。",
                            actionTitle: "重试",
                            action: { Task { await model.loadSessions(force: true) } }
                        )
                    }

                    if model.sessionsLoading && model.assistantSessions.isEmpty {
                        HStack(spacing: 8) {
                            ProgressView().controlSize(.small)
                            Text("正在读取历史会话…")
                                .font(.system(size: 13))
                                .foregroundStyle(Aurora.muted)
                        }
                        .padding(.top, 20)
                    }

                    if model.assistantSessions.isEmpty && !model.sessionsLoading {
                        StudioEmpty(
                            icon: "clock.arrow.circlepath",
                            title: "还没有历史会话",
                            detail: "每次对话结束会自动保存到网关，下次可以从这里接着聊。"
                        )
                    }

                    ForEach(model.assistantSessions) { session in
                        sessionRow(session)
                    }
                }
                .padding(16)
            }
            .scrollIndicators(.hidden)
            .background(AuroraBackdrop())
            .navigationTitle("历史会话")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("关闭") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button {
                        model.newChat()
                        dismiss()
                    } label: {
                        Image(systemName: "square.and.pencil")
                    }
                }
            }
        }
        .onAppear { Task { await model.loadSessions(force: true) } }
    }

    private func sessionRow(_ session: AssistantSession) -> some View {
        Button {
            Task {
                await model.openSession(session.id)
                dismiss()
            }
        } label: {
            HStack(alignment: .top, spacing: 11) {
                ZStack {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(Aurora.surfaceVariant)
                    Image(systemName: "bubble.left.and.text.bubble.right")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(Aurora.inkSoft)
                }
                .frame(width: 32, height: 32)

                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 6) {
                        Text(session.title)
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(Aurora.ink)
                            .lineLimit(1)
                        if model.loadedSessionID == session.id {
                            Text("当前")
                                .font(.system(size: 10, weight: .medium))
                                .foregroundStyle(Aurora.brand)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 1)
                                .background(Capsule().fill(Aurora.brand.opacity(0.10)))
                        }
                    }
                    Text(session.preview.isEmpty ? "（空会话）" : session.preview)
                        .font(.system(size: 11.5))
                        .foregroundStyle(Aurora.muted)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: 6)

                VStack(alignment: .trailing, spacing: 6) {
                    Text(session.timeText)
                        .font(.system(size: 11))
                        .foregroundStyle(Aurora.muted)
                        .monospacedDigit()
                    if session.messageCount > 0 {
                        Text("\(session.messageCount) 条")
                            .font(.system(size: 10.5))
                            .foregroundStyle(Aurora.muted)
                    }
                }
            }
            .padding(12)
            .background(
                RoundedRectangle(cornerRadius: AuroraMetrics.controlRadius, style: .continuous)
                    .fill(Aurora.surface)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .contextMenu {
            Button(role: .destructive) {
                Task { await model.deleteSession(session.id) }
            } label: {
                Label("删除", systemImage: "trash")
            }
        }
    }
}
