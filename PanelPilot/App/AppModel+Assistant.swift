import Foundation

// === 助手：历史会话 + 回写 ===
//
// 接口（与面板桌面端一致）：
//   GET    /api/assistant/sessions              列表
//   GET    /api/assistant/sessions/{id}         读一条（含 messages）
//   POST   /api/assistant/sessions              保存/新建 {id,title,messages,model}
//   DELETE /api/assistant/sessions/{id}
//
// 一条消息的结构沿用面板的：user/assistant 用 `content`，工具调用放在
// `toolCalls: [{id,name,arguments}]`（我们只回写文字，工具结果不回写，
// 因为历史里的工具结果对续聊没有价值，反而会把上下文撑爆）。

extension AppModel {

    func loadSessions(force: Bool = false) async {
        guard activeProfile?.isValid == true else { return }
        if sessionsLoading { return }
        if !force, !assistantSessions.isEmpty { return }

        sessionsLoading = true
        sessionsError = nil
        do {
            let response = try await authenticatedRequest("GET", "/api/assistant/sessions", timeout: 30)
            assistantSessions = AssistantSessionParser.list(response.json)
            noteLocalCompute()
        } catch {
            let apiError = error as? PanelAPIError
            sessionsError = apiError?.errorDescription ?? error.localizedDescription
        }
        sessionsLoading = false
    }

    /// 打开历史会话：把面板的消息翻成气泡（含工具步骤卡片），可以接着聊。
    func openSession(_ id: String) async {
        guard activeProfile?.isValid == true else { return }
        do {
            let response = try await authenticatedRequest(
                "GET", "/api/assistant/sessions/\(id)", timeout: 30
            )
            let transcript = AssistantSessionParser.transcript(response.json)
            chat = transcript.messages
            activeSessionID = id
            loadedSessionID = id
            if let index = assistantSessions.firstIndex(where: { $0.id == id }),
               !assistantSessions[index].title.isEmpty {
                // 标题沿用列表里的，发送时回写不会覆盖
            }
            noteLocalCompute()
            haptic()
        } catch {
            let apiError = error as? PanelAPIError
            toast = Toast(
                text: "打开会话失败：\(apiError?.errorDescription ?? error.localizedDescription)",
                kind: .error
            )
        }
    }

    func deleteSession(_ id: String) async {
        do {
            _ = try await authenticatedRequest("DELETE", "/api/assistant/sessions/\(id)", timeout: 20)
            assistantSessions.removeAll { $0.id == id }
            if activeSessionID == id { newChat() }
            toast = Toast(text: "已删除这条会话", kind: .success)
        } catch {
            let apiError = error as? PanelAPIError
            toast = Toast(
                text: "删除失败：\(apiError?.errorDescription ?? error.localizedDescription)",
                kind: .error
            )
        }
    }

    /// 一轮回答结束后回写。失败只记一条提示，不打断对话。
    func saveSession() async {
        guard let id = activeSessionID, !chat.isEmpty else { return }
        let messages: [[String: Any]] = chat.compactMap { message in
            guard !message.text.isEmpty else { return nil }
            return ["role": message.role.rawValue, "content": message.text]
        }
        guard !messages.isEmpty else { return }

        let title = chat.first(where: { $0.role == .user })?.text
            .replacingOccurrences(of: "\n", with: " ")
            .trimmingCharacters(in: .whitespaces) ?? "新对话"
        let shortTitle = String(title.prefix(28))

        var body: [String: Any] = [
            "id": id,
            "title": shortTitle,
            "messages": messages
        ]
        if !assistantModel.trimmingCharacters(in: .whitespaces).isEmpty {
            body["model"] = assistantModel.trimmingCharacters(in: .whitespaces)
        }

        do {
            _ = try await authenticatedRequest("POST", "/api/assistant/sessions", body: body, timeout: 40)
            // 本地列表同步一条，回到历史列表就能看到
            if let index = assistantSessions.firstIndex(where: { $0.id == id }) {
                assistantSessions[index].title = shortTitle
                assistantSessions[index].updatedAt = Date()
                assistantSessions[index].messageCount = messages.count
                assistantSessions[index].preview = String((chat.last?.text ?? "").prefix(60))
            } else {
                assistantSessions.insert(
                    AssistantSession(
                        id: id,
                        title: shortTitle,
                        updatedAt: Date(),
                        messageCount: messages.count,
                        preview: String((chat.last?.text ?? "").prefix(60))
                    ),
                    at: 0
                )
            }
        } catch {
            // 回写失败不打断对话，只在界面上留一句，方便排查
            sessionsError = "这条会话没能存到网关（下次打开历史可能看不到）"
        }
    }
}
