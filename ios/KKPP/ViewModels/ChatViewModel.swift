import Foundation

@MainActor
final class ChatViewModel: ObservableObject {
    enum ConnectionState: Equatable {
        case checking
        case connected
        case disconnected(String)
    }

    @Published var messages: [ChatMessage] = []
    @Published var liveTranscript = ""
    @Published var isProcessing = false
    @Published var errorMessage: String?
    @Published var connectionState: ConnectionState = .checking
    @Published var isRefiningVoiceInput = false
    @Published var analysisSteps: [String] = []
    @Published var streamRevision = 0

    let speechManager: SpeechManager
    let calendarManager: CalendarManager
    let authManager: AuthManager

    private let backendService: BackendService
    private let locationWeatherManager: LocationWeatherManager
    private let timezone = "Asia/Shanghai"
    private let deviceISOFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.timeZone = .current
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()
    private let localDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.timeZone = .current
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss ZZZZ"
        return formatter
    }()
    private var pendingActions: [StructuredAction] = []
    private var pendingActionMessageID: UUID?

    init(
        speechManager: SpeechManager,
        calendarManager: CalendarManager,
        authManager: AuthManager,
        backendService: BackendService,
        locationWeatherManager: LocationWeatherManager
    ) {
        self.speechManager = speechManager
        self.calendarManager = calendarManager
        self.authManager = authManager
        self.backendService = backendService
        self.locationWeatherManager = locationWeatherManager
    }

    var backendBaseURL: String {
        backendService.baseURLString
    }

    func bootstrap() async {
        // Keep launch light-weight so the first screen appears immediately on device.
        await MainActor.run {
            locationWeatherManager.refresh()
        }
        await refreshConnectionStatus()
    }

    func refreshConnectionStatus() async {
        connectionState = .checking

        do {
            let health = try await backendService.healthCheck()
            connectionState = health.ok ? .connected : .disconnected("后端服务未返回可用状态。")
        } catch {
            let extraHint = "请确认网络可用，并且后端地址 \(backendService.baseURLString) 能正常访问。"
            connectionState = .disconnected("\(error.localizedDescription)\n\(extraHint)")
        }
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
        let capture = speechManager.finishRecording()
        let fallbackTranscript = capture.transcript.trimmingCharacters(in: .whitespacesAndNewlines)
        liveTranscript = fallbackTranscript

        guard fallbackTranscript.isEmpty == false else {
            speechManager.resetTranscript()
            return
        }

        var finalTranscript = fallbackTranscript

        if let audioFileURL = capture.audioFileURL {
            isRefiningVoiceInput = true
            do {
                let transcription = try await backendService.transcribeAudio(
                    fileURL: audioFileURL,
                    fallbackText: fallbackTranscript,
                    localeIdentifier: capture.localeIdentifier
                )
                let refinedText = transcription.text.trimmingCharacters(in: .whitespacesAndNewlines)
                if refinedText.isEmpty == false {
                    finalTranscript = refinedText
                    liveTranscript = refinedText
                }
            } catch {
                // Fall back to the realtime transcript when the high-accuracy path is unavailable.
            }
            isRefiningVoiceInput = false
            speechManager.discardRecording(at: audioFileURL)
        }

        await send(text: finalTranscript)
        liveTranscript = ""
        speechManager.resetTranscript()
    }

    func send(text: String) async {
        if case .disconnected(let reason) = connectionState {
            await refreshConnectionStatus()
            if case .disconnected = connectionState {
                errorMessage = reason
                return
            }
        }

        let trimmedText = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedText.isEmpty else { return }

        messages.append(ChatMessage(role: .user, content: trimmedText))
        let assistantId = UUID()
        isProcessing = true
        errorMessage = nil
        analysisSteps = ["连接云端", "整理上下文"]
        streamRevision += 1

        let request = await buildRequest(text: trimmedText)

        do {
            do {
                let streamResult = try await backendService.streamProcess(
                    request: request,
                    onAction: { [weak self] action in
                        Task { @MainActor in
                            self?.handleActionUpdate(action)
                        }
                    },
                    onToken: { [weak self] token in
                        Task { @MainActor in
                            self?.appendAssistantToken(token, assistantId: assistantId)
                        }
                    },
                    onCollaboration: { [weak self] collaboration in
                        Task { @MainActor in
                            guard let self else { return }
                            self.analysisSteps = Self.makeAnalysisSteps(from: collaboration)
                            self.updateAssistantStatusLines(id: assistantId, lines: self.analysisSteps)
                            self.streamRevision += 1
                        }
                    },
                    onStage: { [weak self] stageMessage in
                        Task { @MainActor in
                            guard let self else { return }
                            self.analysisSteps = Self.mergeAnalysisSteps(self.analysisSteps, incoming: stageMessage)
                            self.updateAssistantStatusLines(id: assistantId, lines: self.analysisSteps)
                            self.streamRevision += 1
                        }
                    }
                )

                try await applyReplyResult(
                    reply: streamResult.reply,
                    structuredAction: streamResult.structuredAction,
                    structuredActions: streamResult.structuredActions,
                    collaboration: streamResult.collaboration,
                    assistantId: assistantId
                )
            } catch {
                analysisSteps = ["流式连接波动", "切换稳定模式", "继续完成这次请求"]
                streamRevision += 1
                let result = try await backendService.process(request: request)
                try await applyReplyResult(
                    reply: result.reply,
                    structuredAction: result.structuredAction,
                    structuredActions: result.structuredActions,
                    collaboration: result.collaboration,
                    assistantId: assistantId
                )
            }
        } catch {
            removeAssistantPlaceholder(id: assistantId)
            errorMessage = error.localizedDescription
            connectionState = .disconnected(error.localizedDescription)
            messages.append(ChatMessage(role: .assistant, content: "抱歉，刚才处理时出了点问题。你可以再说一次，我会重新帮你安排。"))
            analysisSteps = ["网络异常", "请重试"]
        }

        isProcessing = false
        streamRevision += 1
    }

    private func applyReplyResult(
        reply: String,
        structuredAction: StructuredAction?,
        structuredActions: [StructuredAction]?,
        collaboration: CollaborationPayload?,
        assistantId: UUID
    ) async throws {
        if let collaboration {
            analysisSteps = Self.makeAnalysisSteps(from: collaboration)
            updateAssistantStatusLines(id: assistantId, lines: analysisSteps)
        }

        finalizeAssistantMessage(id: assistantId, fallback: reply)

        let resolvedActions = structuredActions ?? structuredAction.map { [$0] } ?? []

        if !resolvedActions.isEmpty {
            presentOperationProposal(for: resolvedActions)
        } else if analysisSteps.isEmpty {
            analysisSteps = ["已完成分析", "结果已返回"]
        }
        connectionState = .connected
    }

    func selectOperationItem(messageID: UUID, itemID: UUID) {
        guard let index = messages.firstIndex(where: { $0.id == messageID }),
              var card = messages[index].operationCard else {
            return
        }

        card.selectedItemID = itemID
        messages[index].operationCard = card
        streamRevision += 1
    }

    func confirmOperation(messageID: UUID) {
        guard messageID == pendingActionMessageID,
              !pendingActions.isEmpty,
              let index = messages.firstIndex(where: { $0.id == messageID }),
              let card = messages[index].operationCard else {
            return
        }

        let selectedItem = card.items.first(where: { $0.id == card.selectedItemID }) ?? card.items.first
        let selectedText = selectedItem.map { "已选：\($0.title)" } ?? "已确认执行"
        messages.append(ChatMessage(role: .user, content: selectedText))

        Task {
            do {
                analysisSteps = ["执行中", "写入日历", "同步提醒事项"]
                updateAssistantStatusLines(id: messageID, lines: analysisSteps)
                for action in pendingActions {
                    try await execute(action: action)
                    await appendPreviewCardIfNeeded(for: action)
                }

                await MainActor.run {
                    let completedCard = makeCompletedCard(basedOn: card)
                    messages[index].operationCard = completedCard
                    messages[index].content = ""
                    messages[index].statusLines = []
                    messages.append(ChatMessage(role: .assistant, content: "好的，已经按你的确认执行完成。"))
                    analysisSteps = ["已完成执行", "结果已同步"]
                    pendingActions = []
                    pendingActionMessageID = nil
                    streamRevision += 1
                }
            } catch {
                await MainActor.run {
                    errorMessage = error.localizedDescription
                    messages.append(ChatMessage(role: .assistant, content: "执行时遇到了一点问题，我已经停下来，等你下一步指令。"))
                    analysisSteps = ["执行失败", "等待下一步指令"]
                    streamRevision += 1
                }
            }
        }
    }

    func cancelOperation(messageID: UUID) {
        guard messageID == pendingActionMessageID else { return }
        pendingActions = []
        pendingActionMessageID = nil

        if let index = messages.firstIndex(where: { $0.id == messageID }) {
            messages.remove(at: index)
        }
        messages.append(ChatMessage(role: .assistant, content: "这次执行我先取消了。你可以重新说一版，我再帮你整理。"))
        analysisSteps = ["已取消", "等待新的指令"]
        streamRevision += 1
    }

    func delete(preview: ChatMessage.SchedulePreview) {
        guard let eventID = preview.eventID else { return }

        do {
            try calendarManager.deleteEvent(eventID: eventID)
            removePreview(with: eventID)
            messages.append(ChatMessage(role: .assistant, content: "已经帮你删除这条日程。"))
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func updateLocation(preview: ChatMessage.SchedulePreview, location: String) {
        guard let eventID = preview.eventID else { return }
        let trimmed = location.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.isEmpty == false else { return }

        do {
            try calendarManager.updateEventLocation(eventID: eventID, location: trimmed)
            refreshPreview(
                eventID: eventID,
                title: preview.title,
                startDate: preview.startDate,
                endDate: preview.endDate,
                location: trimmed,
                reminderMinutes: extractReminderMinutes(from: preview.reminderText)
            )
            messages.append(ChatMessage(role: .assistant, content: "地点已经更新。"))
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func updateTime(preview: ChatMessage.SchedulePreview, startDate: Date, endDate: Date) {
        guard let eventID = preview.eventID else { return }

        do {
            try calendarManager.updateEventTime(eventID: eventID, startDate: startDate, endDate: endDate)
            refreshPreview(
                eventID: eventID,
                title: preview.title,
                startDate: startDate,
                endDate: endDate,
                location: preview.location.replacingOccurrences(of: "📌 ", with: ""),
                reminderMinutes: extractReminderMinutes(from: preview.reminderText)
            )
            messages.append(ChatMessage(role: .assistant, content: "时间已经改好了。"))
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func updateRecurrence(preview: ChatMessage.SchedulePreview, option: CalendarManager.RecurrenceOption) {
        guard let eventID = preview.eventID else { return }

        do {
            try calendarManager.updateRecurrence(eventID: eventID, option: option)
            let resultText = option == .none ? "已取消重复。" : "重复规则已改成\(option.title)。"
            messages.append(ChatMessage(role: .assistant, content: resultText))
        } catch {
            errorMessage = error.localizedDescription
        }
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
            calendarContext: CalendarContext(events: events),
            deviceContext: DeviceContext(
                currentDateISO: deviceISOFormatter.string(from: Date()),
                localDateLabel: localDateFormatter.string(from: Date()),
                city: locationWeatherManager.cityName == "未定位" ? nil : locationWeatherManager.cityName,
                district: locationWeatherManager.districtName.isEmpty ? nil : locationWeatherManager.districtName,
                weatherSummary: locationWeatherManager.weatherSummary == "天气待获取" ? nil : locationWeatherManager.weatherSummary,
                temperatureText: locationWeatherManager.temperatureText == "--" ? nil : locationWeatherManager.temperatureText,
                latitude: locationWeatherManager.latitude,
                longitude: locationWeatherManager.longitude
            )
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
        ensureAssistantMessageExists(id: assistantId)
        guard let index = messages.firstIndex(where: { $0.id == assistantId }) else { return }
        messages[index].content += token
        streamRevision += 1
    }

    private func finalizeAssistantMessage(id: UUID, fallback: String) {
        ensureAssistantMessageExists(id: id)
        guard let index = messages.firstIndex(where: { $0.id == id }) else { return }
        if messages[index].content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            messages[index].content = fallback
        }
        streamRevision += 1
    }

    private func removeAssistantPlaceholder(id: UUID) {
        messages.removeAll { $0.id == id }
        streamRevision += 1
    }

    private func updateAssistantStatusLines(id: UUID, lines: [String]) {
        guard let index = messages.firstIndex(where: { $0.id == id }) else { return }
        messages[index].statusLines = Array(lines.prefix(4))
    }

    private func ensureAssistantMessageExists(id: UUID) {
        guard messages.contains(where: { $0.id == id }) == false else { return }
        messages.append(ChatMessage(id: id, role: .assistant, content: ""))
    }

    private func appendPreviewCardIfNeeded(for action: StructuredAction) async {
        guard action.type == "add_calendar_event",
              let title = action.payload.title,
              let startISO = action.payload.startISO else {
            return
        }

        let startDate = ISO8601DateFormatter().date(from: startISO) ?? Date()
        let dateFormatter = DateFormatter()
        dateFormatter.locale = Locale(identifier: "zh_CN")
        dateFormatter.timeZone = TimeZone(identifier: "Asia/Shanghai")
        dateFormatter.dateFormat = "M月d日 HH:mm"

        let subtitle = "📅 \(dateFormatter.string(from: startDate))"
        let location = action.payload.location ?? "待补充地点"
        let reminderMinutes = action.payload.reminderMinutesBefore ?? 15
        let reminderText = "⏰ 提前\(reminderMinutes)分钟提醒"
        let endDate = startDate.addingTimeInterval((action.payload.durationHours ?? 1) * 3600)
        let eventID = await latestMatchingEventID(title: title, startDate: startDate)

        messages.append(
            ChatMessage(
                role: .system,
                content: "",
                schedulePreview: .init(
                    eventID: eventID,
                    title: title,
                    subtitle: subtitle,
                    location: "📌 \(location)",
                    reminderText: reminderText,
                    startDate: startDate,
                    endDate: endDate
                )
            )
        )
    }

    private func latestMatchingEventID(title: String, startDate: Date) async -> String? {
        let formatter = ISO8601DateFormatter()
        let events = (try? await calendarManager.fetchEvents(anchorDateISO: formatter.string(from: startDate), rangeDays: 1)) ?? []
        return events
            .filter { $0.title == title }
            .sorted { $0.startISO > $1.startISO }
            .first?.id
    }

    private func refreshPreview(
        eventID: String,
        title: String,
        startDate: Date,
        endDate: Date,
        location: String,
        reminderMinutes: Int
    ) {
        guard let index = messages.firstIndex(where: { $0.schedulePreview?.eventID == eventID }) else { return }

        let dateFormatter = DateFormatter()
        dateFormatter.locale = Locale(identifier: "zh_CN")
        dateFormatter.timeZone = TimeZone(identifier: "Asia/Shanghai")
        dateFormatter.dateFormat = "M月d日 HH:mm"

        messages[index] = ChatMessage(
            id: messages[index].id,
            role: .system,
            content: messages[index].content,
            createdAt: messages[index].createdAt,
            schedulePreview: .init(
                eventID: eventID,
                title: title,
                subtitle: "📅 \(dateFormatter.string(from: startDate))",
                location: "📌 \(location.isEmpty ? "待补充地点" : location)",
                reminderText: "⏰ 提前\(reminderMinutes)分钟提醒",
                startDate: startDate,
                endDate: endDate
            )
        )
    }

    private func removePreview(with eventID: String) {
        messages.removeAll { $0.schedulePreview?.eventID == eventID }
    }

    private func extractReminderMinutes(from text: String) -> Int {
        let digits = text.filter(\.isNumber)
        return Int(digits) ?? 15
    }

    private func handleActionUpdate(_ action: StructuredAction?) {
        guard let action else { return }
        switch action.type {
        case "add_calendar_event":
            analysisSteps = ["理解需求", "写入日历"]
        case "query_calendar_events":
            analysisSteps = ["理解需求", "查询日历"]
        default:
            break
        }
        streamRevision += 1
    }

    private func presentOperationProposal(for actions: [StructuredAction]) {
        let proposal = makeProposalCard(from: actions)
        let messageID = UUID()
        pendingActions = actions
        pendingActionMessageID = messageID
        messages.append(
            ChatMessage(
                id: messageID,
                role: .system,
                content: "",
                operationCard: proposal
            )
        )
        analysisSteps = ["拆解任务", "等待确认"]
        streamRevision += 1
    }

    private func makeProposalCard(from actions: [StructuredAction]) -> ChatMessage.OperationCard {
        let items = actions.map(makeOperationItem(from:))
        return ChatMessage.OperationCard(
            style: .proposal,
            headline: "需要补充信息",
            subtitle: "确认后我会继续执行这些任务。",
            items: items,
            needsConfirmation: true,
            confirmationTitle: "确认",
            selectedItemID: items.first?.id
        )
    }

    private func makeCompletedCard(basedOn card: ChatMessage.OperationCard) -> ChatMessage.OperationCard {
        ChatMessage.OperationCard(
            id: card.id,
            style: .completed,
            headline: "已完成 \(card.items.count)项操作",
            subtitle: "结果已经同步到系统日历。",
            items: card.items,
            needsConfirmation: false,
            confirmationTitle: "完成",
            selectedItemID: card.selectedItemID
        )
    }

    private func makeOperationItem(from action: StructuredAction) -> ChatMessage.OperationItem {
        let startDate = action.payload.startISO.flatMap { ISO8601DateFormatter().date(from: $0) } ?? Date()
        let timeFormatter = DateFormatter()
        timeFormatter.locale = Locale(identifier: "zh_CN")
        timeFormatter.timeZone = TimeZone(identifier: "Asia/Shanghai")
        timeFormatter.dateFormat = "HH:mm"

        let kind: ChatMessage.OperationKind
        switch action.type {
        case "add_calendar_event":
            kind = .execute
        case "query_calendar_events":
            kind = .query
        default:
            kind = .execute
        }

        let title = action.payload.title ?? action.payload.focus ?? "新的安排"
        let detail = action.payload.location ?? action.payload.notes ?? "点击后可查看详情"
        let timeText = timeFormatter.string(from: startDate)

        return ChatMessage.OperationItem(
            title: "\(timeText) \(title)",
            detail: detail,
            timeText: timeText,
            kind: kind
        )
    }

    private static func makeAnalysisSteps(from collaboration: CollaborationPayload?) -> [String] {
        guard let collaboration else { return [] }

        let intent = collaboration.intentAnalysis?.userGoal ?? collaboration.intentAnalysis?.reasoningSummary
        let planning = collaboration.planning?.planningSummary ?? collaboration.planning?.proposedActionType
        let decision = collaboration.decision?.internalSummary ?? collaboration.decision?.decision

        return compactAnalysisSteps([
            intent.map { _ in "理解需求" },
            planning.map { _ in "拆解日程" },
            decision.map { _ in "准备执行" }
        ].compactMap { $0 })
    }

    private static func mergeAnalysisSteps(_ existing: [String], incoming: String) -> [String] {
        compactAnalysisSteps(existing + [normalizeAnalysisStep(incoming)].compactMap { $0 })
    }

    private static func compactAnalysisSteps(_ steps: [String]) -> [String] {
        var result: [String] = []
        for step in steps {
            guard let normalized = normalizeAnalysisStep(step) else { continue }
            if result.last != normalized {
                result.append(normalized)
            }
        }
        return Array(result.suffix(3))
    }

    private static func normalizeAnalysisStep(_ raw: String) -> String? {
        let text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return nil }

        if text.contains("连接") { return "连接云端" }
        if text.contains("上下文") { return "整理上下文" }
        if text.contains("意图") || text.contains("理解") { return "理解需求" }
        if text.contains("规划") || text.contains("拆解") { return "拆解日程" }
        if text.contains("查询") { return "查询日历" }
        if text.contains("写入") || text.contains("创建") { return "写入日历" }
        if text.contains("同步") { return "同步提醒" }
        if text.contains("确认") { return "等待确认" }
        if text.contains("完成") { return "已完成" }
        if text.contains("执行") || text.contains("决策") { return "准备执行" }
        if text.contains("网络") { return "网络波动" }
        return String(text.prefix(12))
    }
}
