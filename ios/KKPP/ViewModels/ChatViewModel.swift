import Foundation

@MainActor
final class ChatViewModel: ObservableObject {
    @Published var messages: [ChatMessage] = [
        ChatMessage(role: .assistant, content: "你好，我是 KKPP。按住下方麦克风，直接告诉我你的日程安排，我会像私人秘书一样帮你处理。")
    ]
    @Published var liveTranscript = ""
    @Published var isProcessing = false
    @Published var errorMessage: String?

    let speechManager: SpeechManager
    let calendarManager: CalendarManager
    let authManager: AuthManager

    private let backendService: BackendService
    private let timezone = "Asia/Shanghai"

    init(
        speechManager: SpeechManager,
        calendarManager: CalendarManager,
        authManager: AuthManager,
        backendService: BackendService
    ) {
        self.speechManager = speechManager
        self.calendarManager = calendarManager
        self.authManager = authManager
        self.backendService = backendService
    }

    func bootstrap() async {
        await speechManager.requestPermissions()
        _ = await calendarManager.requestAccess()
    }

    func beginRecording(cantonesePreferred: Bool = false) async {
        let locale = cantonesePreferred ? "zh-HK" : "zh-Hans"
        do {
            try await speechManager.startRecording(localeIdentifier: locale)
            liveTranscript = ""
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func stopRecordingAndSend() async {
        speechManager.stopRecording()
        liveTranscript = speechManager.transcript.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !liveTranscript.isEmpty else { return }
        await send(text: liveTranscript)
        liveTranscript = ""
        speechManager.transcript = ""
    }

    func send(text: String) async {
        guard authManager.isSignedIn else {
            errorMessage = "请先使用 Apple 账号登录。"
            return
        }

        let trimmedText = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedText.isEmpty else { return }

        messages.append(ChatMessage(role: .user, content: trimmedText))
        let assistantId = UUID()
        messages.append(ChatMessage(id: assistantId, role: .assistant, content: ""))
        isProcessing = true
        errorMessage = nil

        let request = await buildRequest(text: trimmedText)

        do {
            let streamResult = try await backendService.streamProcess(
                request: request,
                onAction: { _ in },
                onToken: { [weak self] token in
                    Task { @MainActor in
                        self?.appendAssistantToken(token, assistantId: assistantId)
                    }
                }
            )

            if let action = streamResult.structuredAction {
                try await execute(action: action)
            }

            finalizeAssistantMessage(id: assistantId, fallback: streamResult.reply)
        } catch {
            removeAssistantPlaceholder(id: assistantId)
            errorMessage = error.localizedDescription
            messages.append(ChatMessage(role: .assistant, content: "抱歉，刚才处理时出了点问题。你可以再说一次，我会重新帮你安排。"))
        }

        isProcessing = false
    }

    private func buildRequest(text: String) async -> ProcessRequest {
        let events: [CalendarEventSummary]

        if text.contains("今天") || text.contains("明天") || text.contains("未來") || text.contains("日程") || text.contains("行程") || text.contains("安排") {
            events = (try? await calendarManager.fetchUpcomingEvents(days: 7)) ?? []
        } else {
            events = []
        }

        return ProcessRequest(
            userId: authManager.userId,
            text: text,
            timezone: timezone,
            calendarContext: CalendarContext(events: events)
        )
    }

    private func execute(action: StructuredAction) async throws {
        switch action.type {
        case "add_calendar_event":
            try await calendarManager.addEvent(from: action)
        case "query_calendar_events":
            let _ = try await calendarManager.fetchEvents(
                anchorDateISO: action.payload.dateISO,
                rangeDays: action.payload.rangeDays ?? 1
            )
        default:
            break
        }
    }

    private func appendAssistantToken(_ token: String, assistantId: UUID) {
        guard let index = messages.firstIndex(where: { $0.id == assistantId }) else { return }
        messages[index].content += token
    }

    private func finalizeAssistantMessage(id: UUID, fallback: String) {
        guard let index = messages.firstIndex(where: { $0.id == id }) else { return }
        if messages[index].content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            messages[index].content = fallback
        }
    }

    private func removeAssistantPlaceholder(id: UUID) {
        messages.removeAll { $0.id == id }
    }
}
