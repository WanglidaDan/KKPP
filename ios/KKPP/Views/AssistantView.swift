import AuthenticationServices
import SwiftUI
import UIKit

struct AssistantView: View {
    @ObservedObject var viewModel: ChatViewModel
    @ObservedObject var permissionManager: SystemPermissionManager
    @ObservedObject var locationWeatherManager: LocationWeatherManager
    @ObservedObject var calendarManager: CalendarManager
    var onOpenSchedule: () -> Void = {}

    @State private var manualInput = ""
    @FocusState private var isTextFieldFocused: Bool
    @State private var showingQuickActions = false
    @State private var editingPreview: ChatMessage.SchedulePreview?
    @State private var locationDraft = ""
    @State private var showLocationSheet = false
    @State private var showTimeSheet = false
    @State private var timeDraftStart = Date()
    @State private var timeDraftEnd = Date().addingTimeInterval(3600)
    @State private var isHoldingVoice = false
    @State private var showingCamera = false
    @State private var repeatPreview: ChatMessage.SchedulePreview?
    @State private var deletePreview: ChatMessage.SchedulePreview?
    @State private var recordingStartedAt: Date?
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .bottom) {
                background

                VStack(spacing: 0) {
                    topBar
                        .padding(.horizontal, 18)
                        .padding(.top, max(geometry.safeAreaInsets.top, 8) + 8)
                        .padding(.bottom, 14)

                    ScrollViewReader { proxy in
                        VStack(spacing: 0) {
                            ScrollView(showsIndicators: false) {
                                LazyVStack(spacing: 16) {
                                    if shouldShowLandingCanvas {
                                        landingCanvas(
                                            minHeight: max(
                                                420,
                                                geometry.size.height
                                                    - max(geometry.safeAreaInsets.top, 8)
                                                    - 260
                                            )
                                        )
                                    } else {
                                        ForEach(viewModel.messages) { message in
                                            MessageBubbleView(
                                                message: message,
                                                onEditTime: handleEditTime,
                                                onEditRepeat: handleEditRepeat,
                                                onDelete: handleDelete,
                                                onAddLocation: handleAddLocation,
                                                onSelectOperation: viewModel.selectOperationItem,
                                                onConfirmOperation: viewModel.confirmOperation,
                                                onCancelOperation: viewModel.cancelOperation
                                            )
                                            .id(message.id)
                                        }

                                        if shouldShowInlineStatusCard {
                                            inlineStatusCard
                                                .transition(.move(edge: .bottom).combined(with: .opacity))
                                        }

                                        if let errorMessage = viewModel.errorMessage {
                                            inlineErrorCard(errorMessage)
                                        }
                                    }

                                    Color.clear
                                        .frame(height: 1)
                                        .id("bottom-anchor")
                                }
                                .padding(.horizontal, 20)
                                .padding(.top, 22)
                                .padding(.bottom, 150)
                            }
                            .scrollDismissesKeyboard(.interactively)
                            .onAppear {
                                scrollToBottom(proxy, animated: false)
                            }
                            .onChange(of: viewModel.messages) { _, _ in
                                scrollToBottom(proxy)
                            }
                            .onChange(of: viewModel.isProcessing) { _, _ in
                                scrollToBottom(proxy)
                            }
                            .onChange(of: viewModel.streamRevision) { _, _ in
                                scrollToBottom(proxy)
                            }
                            .onChange(of: viewModel.speechManager.transcript) { _, _ in
                                scrollToBottom(proxy)
                            }
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                        .background(conversationCanvasBackground)
                        .clipShape(RoundedRectangle(cornerRadius: 30, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: 30, style: .continuous)
                                .strokeBorder(Color.white.opacity(0.05), lineWidth: 0.8)
                        )
                        .padding(.horizontal, 12)
                        .padding(.bottom, 94)
                    }
                }

                bottomTalkBar(safeBottom: geometry.safeAreaInsets.bottom)

                if viewModel.speechManager.isRecording || viewModel.isRefiningVoiceInput {
                    recordingOverlay
                        .transition(.opacity.combined(with: .scale))
                }
            }
        }
        .sheet(isPresented: $showingCamera) {
            CameraPicker { _ in }
                .ignoresSafeArea()
        }
        .confirmationDialog("å¿«æ·æä½", isPresented: $showingQuickActions, titleVisibility: .visible) {
            Button("æ¥çä»å¤©å®æ") {
                Task { await viewModel.send(text: "ççæä»å¤©çå®æ") }
            }
            Button("æ°å»ºææå®æ") {
                manualInput = "å¸®ææ°å»ºä¸ä¸ªææå®æï¼"
                isTextFieldFocused = true
            }
            Button("æ»ç»æ¬å¨å®æ") {
                Task { await viewModel.send(text: "æ»ç»ä¸ä¸æè¿å¨çå®æ") }
            }
            Button("åæ¶", role: .cancel) {}
        }
        .confirmationDialog(
            "æ¹éå¤",
            isPresented: Binding(
                get: { repeatPreview != nil },
                set: { if !$0 { repeatPreview = nil } }
            ),
            titleVisibility: .visible
        ) {
            ForEach(CalendarManager.RecurrenceOption.allCases) { option in
                Button(option.title) {
                    if let preview = repeatPreview {
                        viewModel.updateRecurrence(preview: preview, option: option)
                    }
                    repeatPreview = nil
                }
            }
            Button("åæ¶", role: .cancel) {
                repeatPreview = nil
            }
        }
        .confirmationDialog(
            "å é¤è¿æ¡å®æï¼",
            isPresented: Binding(
                get: { deletePreview != nil },
                set: { if !$0 { deletePreview = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button("å é¤", role: .destructive) {
                if let preview = deletePreview {
                    viewModel.delete(preview: preview)
                }
                deletePreview = nil
            }
            Button("åæ¶", role: .cancel) {
                deletePreview = nil
            }
        }
        .sheet(isPresented: $showLocationSheet) {
            NavigationStack {
                VStack(spacing: 18) {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("ææå°ç¹")
                            .font(.headline)
                        TextField("ä¾å¦ï¼å¤æ»©æº 2 å·é¨", text: $locationDraft, axis: .vertical)
                            .textFieldStyle(.plain)
                            .padding(16)
                            .background(
                                RoundedRectangle(cornerRadius: 18, style: .continuous)
                                    .fill(Color(uiColor: .secondarySystemGroupedBackground))
                            )
                    }

                    Spacer()
                }
                .padding(20)
                .navigationTitle("å å°ç¹")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("åæ¶") {
                            showLocationSheet = false
                        }
                    }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("ä¿å­") {
                            if let preview = editingPreview {
                                viewModel.updateLocation(preview: preview, location: locationDraft)
                            }
                            showLocationSheet = false
                            editingPreview = nil
                        }
                    }
                }
            }
            .presentationDetents([.medium])
        }
        .sheet(isPresented: $showTimeSheet) {
            NavigationStack {
                VStack(alignment: .leading, spacing: 16) {
                    DatePicker("å¼å§", selection: $timeDraftStart, displayedComponents: [.date, .hourAndMinute])
                        .datePickerStyle(.graphical)

                    DatePicker("ç»æ", selection: $timeDraftEnd, displayedComponents: [.date, .hourAndMinute])
                        .datePickerStyle(.graphical)

                    Spacer()
                }
                .padding(20)
                .navigationTitle("æ¹æ¶é´")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("åæ¶") {
                            showTimeSheet = false
                        }
                    }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("ä¿å­") {
                            if let preview = editingPreview {
                                let end = max(timeDraftEnd, timeDraftStart.addingTimeInterval(1800))
                                viewModel.updateTime(preview: preview, startDate: timeDraftStart, endDate: end)
                            }
                            showTimeSheet = false
                            editingPreview = nil
                        }
                    }
                }
            }
            .presentationDetents([.large])
        }
        .task {
            permissionManager.refreshStatuses()
            await viewModel.speechManager.requestPermissions()
            locationWeatherManager.ensureAccessAndRefresh()
            await viewModel.bootstrap()
        }
        .onChange(of: scenePhase) { _, newPhase in
            guard newPhase == .active else { return }
            permissionManager.refreshStatuses()
            locationWeatherManager.ensureAccessAndRefresh()
            Task(priority: .background) {
                await viewModel.refreshConnectionStatus()
            }
        }
    }

    private var background: some View {
        ZStack {
            LinearGradient(
                colors: [
                    Color(red: 0.08, green: 0.09, blue: 0.12),
                    Color(red: 0.05, green: 0.06, blue: 0.09)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            LinearGradient(
                colors: [
                    Color(red: 0.22, green: 0.14, blue: 0.34).opacity(0.35),
                    Color.clear,
                    Color.black.opacity(0.25)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        }
        .ignoresSafeArea()
    }

    private var topBar: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 6) {
                Text("KKPP")
                    .font(.system(size: 30, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)

                Text("ç§äººæ¶é´å©æ")
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.46))
            }

            Spacer()

            HStack(spacing: 8) {
                Circle()
                    .fill(connectionColor)
                    .frame(width: 7, height: 7)

                Text(connectionLabel)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.white.opacity(0.78))
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(Color.white.opacity(0.06))
            .clipShape(Capsule(style: .continuous))
        }
    }

    private var conversationCanvasBackground: some View {
        RoundedRectangle(cornerRadius: 30, style: .continuous)
            .fill(
                LinearGradient(
                    colors: [
                        Color.white.opacity(0.05),
                        Color.white.opacity(0.025),
                        Color.black.opacity(0.18)
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
            )
    }


    private var signInCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("ç°å¨ä¸ç»å½ä¹è½ç´æ¥ç¨ãç»å½ Apple è´¦å·åï¼èº«ä»½ä¸å¤è®¾å¤ä½éªä¼æ´å®æ´ã")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.white.opacity(0.88))

            SignInWithAppleButton(.signIn) { request in
                request.requestedScopes = [.fullName]
            } onCompletion: { result in
                switch result {
                case .success(let authorization):
                    viewModel.authManager.handleAuthorization(authorization)
                case .failure(let error):
                    viewModel.errorMessage = error.localizedDescription
                }
            }
            .signInWithAppleButtonStyle(.white)
            .frame(height: 46)
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(Color.white.opacity(0.04))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .strokeBorder(Color.white.opacity(0.06), lineWidth: 1)
        )
    }

    private var compactPermissionsCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("è®¾å¤è½å")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.white.opacity(0.50))

                Spacer()

                Button("ä¸é®å¼å¯") {
                    Task { await requestAllCapabilities() }
                }
                .font(.caption.weight(.semibold))
                .foregroundStyle(.white.opacity(0.86))
            }

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    permissionButton("éº¦åé£", granted: viewModel.speechManager.microphoneAuthorized) {
                        Task {
                            await viewModel.speechManager.requestPermissions()
                            permissionManager.refreshStatuses()
                        }
                    }

                    permissionButton("è¯­é³", granted: viewModel.speechManager.speechAuthorized) {
                        Task {
                            await viewModel.speechManager.requestPermissions()
                            permissionManager.refreshStatuses()
                        }
                    }

                    permissionButton("æ¥å", granted: calendarManager.hasReadAccess || calendarManager.hasWriteAccess) {
                        Task {
                            _ = await calendarManager.requestAccess()
                            permissionManager.refreshStatuses()
                        }
                    }

                    permissionButton("å®ä½", granted: locationWeatherManager.hasLocationAccess) {
                        locationWeatherManager.requestWhenInUseAccess()
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
                            locationWeatherManager.refresh()
                        }
                    }
                }
            }
        }
        .padding(16)
        .background(Color.white.opacity(0.035))
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .strokeBorder(Color.white.opacity(0.05), lineWidth: 0.8)
        )
    }

    private func landingCanvas(minHeight: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: 24) {
            VStack(alignment: .leading, spacing: 12) {
                Text("ææ¶é´äº¤ç»ææ´ç")
                    .font(.system(size: 34, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)

                Text("ç´æ¥è¯´éæ±ï¼æä¼å¸®ä½ çè§£ãæè§£ï¼å¹¶æ´çææ¥ç¨ä¸å¾ç¡®è®¤å¨ä½ã")
                    .font(.subheadline)
                    .foregroundStyle(.white.opacity(0.62))
                    .fixedSize(horizontal: false, vertical: true)
            }

            HStack(spacing: 12) {
                landingMetric(
                    title: "è¿æ¥ç¶æ",
                    value: connectionLabel,
                    tint: connectionColor
                )

                landingMetric(
                    title: "å¤©æ°",
                    value: locationWeatherManager.weatherSummary,
                    tint: Color(hex: 0x60A5FA)
                )
            }

            compactPermissionsCard

            VStack(alignment: .leading, spacing: 12) {
                Text("è¯çè¿æ ·è¯´")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.white.opacity(0.48))

                VStack(spacing: 10) {
                    landingPromptRow("æå¤©ä¸åä¸ç¹åæå½±æ£ç¡®è®¤æææ¡£æ")
                    landingPromptRow("ä¸å¨ä¸ä¸åæéæå¸¦éå¤´å»å¤æ¯")
                    landingPromptRow("ççæä»å¤©è¿æåªäºå®æ")
                }
            }

            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, minHeight: minHeight, alignment: .topLeading)
    }

    private func landingMetric(title: String, value: String, tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.caption.weight(.medium))
                .foregroundStyle(.white.opacity(0.54))
            HStack(spacing: 8) {
                Circle()
                    .fill(tint)
                    .frame(width: 8, height: 8)
                Text(value)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.white.opacity(0.92))
                    .lineLimit(1)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(Color.white.opacity(0.04))
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    private func landingPromptRow(_ text: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Circle()
                .fill(Color.white.opacity(0.16))
                .frame(width: 8, height: 8)
                .padding(.top, 6)

            Text(text)
                .font(.footnote)
                .foregroundStyle(.white.opacity(0.76))

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color.white.opacity(0.035))
        )
    }

    private func permissionButton(_ title: String, granted: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: granted ? "checkmark.circle.fill" : "plus.circle")
                Text(title)
            }
            .font(.caption.weight(.semibold))
            .foregroundStyle(granted ? Color.green : Color.white.opacity(0.86))
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(
                Capsule(style: .continuous)
                    .fill(granted ? Color.green.opacity(0.14) : Color.white.opacity(0.07))
            )
        }
        .buttonStyle(.plain)
    }

    private var shouldShowTransparencyPanel: Bool {
        viewModel.isProcessing || !viewModel.messages.isEmpty
    }


    private var shouldShowInlineStatusCard: Bool {
        viewModel.isProcessing
    }

    private var shouldShowLandingCanvas: Bool {
        viewModel.messages.isEmpty && !viewModel.isProcessing && !viewModel.isRefiningVoiceInput
    }

    private var inlineStatusCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 8) {
                Text("å¤çä¸­â¦")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.white.opacity(0.58))
                Text(statusSummaryText)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.white.opacity(0.92))
                    .fixedSize(horizontal: false, vertical: true)
            }

            VStack(alignment: .leading, spacing: 6) {
                ForEach(displayAnalysisSteps, id: \.self) { step in
                    HStack(spacing: 8) {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(Color(hex: 0x10B981))
                        Text(step)
                            .font(.caption)
                            .foregroundStyle(.white.opacity(0.48))
                    }
                }
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(Color.white.opacity(0.045))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .strokeBorder(Color.white.opacity(0.04), lineWidth: 1)
        )
    }

    private var displayAnalysisSteps: [String] {
        Array(viewModel.analysisSteps.suffix(2))
    }

    private var statusSummaryText: String {
        if let last = displayAnalysisSteps.last {
            switch last {
            case "è¿æ¥äºç«¯":
                return "æ­£å¨è¿æ¥äºç«¯å©æã"
            case "æ´çä¸ä¸æ":
                return "æ­£å¨æ´çä½ çæ¶é´ãä¸ä¸æåè®¾å¤ä¿¡æ¯ã"
            case "çè§£éæ±":
                return "æ­£å¨çè§£è¿æ¬¡å®æççå®æå¾ã"
            case "æè§£æ¥ç¨":
                return "æ­£å¨æè§£è¿æ¬¡æ¥ç¨è¯·æ±ã"
            case "æ¥è¯¢æ¥å":
                return "æ­£å¨æ¥çä½ çæ¥åå®æã"
            case "åå¥æ¥å":
                return "æ­£å¨æç¡®è®¤åçç»æåå¥ç³»ç»æ¥åã"
            case "ç­å¾ç¡®è®¤":
                return "æå·²ç»æ´çå¥½æ¹æ¡ï¼ç­ä½ ç¡®è®¤ã"
            default:
                return "æ­£å¨ä¸ºä½ çææ´åéçå®æã"
            }
        }

        return "æ­£å¨ä¸ºä½ çææ´åéçå®æã"
    }

    private func statusRow(title: String, isDone: Bool) -> some View {
        HStack(spacing: 8) {
            Text(isDone ? "â" : "Q")
                .font(.caption.weight(.bold))
                .foregroundStyle(isDone ? Color(hex: 0x10B981) : Color.white.opacity(0.45))
            Text(title)
                .font(.caption)
                .foregroundStyle(Color.white.opacity(isDone ? 0.78 : 0.48))
            if !isDone {
                Text("...")
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.34))
            }
        }
    }

    private func inlineErrorCard(_ text: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
            Text(text)
                .font(.footnote)
                .foregroundStyle(.white.opacity(0.92))
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Color.orange.opacity(0.12))
        )
    }

    private func bottomTalkBar(safeBottom: CGFloat) -> some View {
        HStack(spacing: 12) {
            darkIconButton(
                systemImage: manualInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                    ? "mic.fill"
                    : "arrow.up"
            ) {
                if manualInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    if viewModel.speechManager.isRecording {
                        Task { await stopVoiceFlow() }
                    } else {
                        Task { await startVoiceFlow() }
                    }
                } else {
                    sendManualInput()
                }
            }

            textComposerField

            darkIconButton(systemImage: "calendar") {
                onOpenSchedule()
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(Color.black.opacity(0.42))
        .overlay(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .strokeBorder(Color.white.opacity(0.06), lineWidth: 0.8)
        )
        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        .shadow(color: .black.opacity(0.22), radius: 18, x: 0, y: 10)
        .padding(.horizontal, 14)
        .padding(.bottom, max(safeBottom, 10))
    }

    private var textComposerField: some View {
        HStack(spacing: 10) {
            TextField("è¯´ç¹ä»ä¹â¦", text: $manualInput, axis: .vertical)
                .textFieldStyle(.plain)
                .focused($isTextFieldFocused)
                .lineLimit(1 ... 3)
                .foregroundStyle(.white)
                .submitLabel(.send)
                .onSubmit { sendManualInput() }
        }
        .padding(.horizontal, 16)
        .frame(maxWidth: .infinity)
        .frame(height: 48)
        .background(Color.white.opacity(0.055))
        .clipShape(Capsule(style: .continuous))
    }

    private var voiceHoldButton: some View {
        HStack(spacing: 10) {
            Text(viewModel.speechManager.isRecording || isHoldingVoice ? "æ¾å¼åé" : "æä½è¯´è¯")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.white.opacity(0.92))
        }
        .frame(maxWidth: .infinity)
        .frame(height: 48)
        .background(Color.white.opacity(0.06))
        .clipShape(Capsule(style: .continuous))
        .contentShape(Capsule(style: .continuous))
        .gesture(
            DragGesture(minimumDistance: 0)
                .onChanged { _ in
                    beginVoiceHoldIfNeeded()
                }
                .onEnded { _ in
                    endVoiceHoldIfNeeded()
                }
        )
    }

    private func darkIconButton(systemImage: String, action: (() -> Void)? = nil) -> some View {
        Button {
            (action ?? { showingQuickActions = true })()
        } label: {
            Image(systemName: systemImage)
                .font(.system(size: 16, weight: .bold))
                .foregroundStyle(.white.opacity(0.92))
                .frame(width: 42, height: 42)
                .background(Color.white.opacity(0.07))
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    private var recordingOverlay: some View {
        ZStack {
            Rectangle()
                .fill(.ultraThinMaterial)
                .overlay(Color.black.opacity(0.68))
                .ignoresSafeArea()

            VStack(spacing: 18) {
                VStack(spacing: 12) {
                    Circle()
                        .fill(viewModel.isRefiningVoiceInput ? Color.blue.opacity(0.9) : Color.green.opacity(0.9))
                        .frame(width: 84, height: 84)
                        .overlay {
                            Image(systemName: viewModel.isRefiningVoiceInput ? "sparkles" : "mic.fill")
                                .font(.system(size: 30, weight: .bold))
                                .foregroundStyle(.white)
                        }

                    VoiceWaveformView(isActive: true)
                        .frame(height: 34)

                    TimelineView(.periodic(from: .now, by: 0.1)) { context in
                        Text(recordingDurationText(referenceDate: context.date))
                            .font(.system(size: 48, weight: .bold, design: .rounded))
                            .foregroundStyle(.white)
                    }

                    Text(viewModel.isRefiningVoiceInput ? "æ­£å¨æ´çææ´å¥½çè¡¨è¾¾" : "recording")
                        .font(.subheadline)
                        .foregroundStyle(.white.opacity(0.6))
                }
                .frame(maxWidth: 320)
                .padding(.vertical, 36)
                .padding(.horizontal, 38)
                .background(
                    RoundedRectangle(cornerRadius: 34, style: .continuous)
                        .fill(Color.white.opacity(0.12))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 34, style: .continuous)
                        .strokeBorder(Color.white.opacity(0.08), lineWidth: 1)
                )
                .shadow(color: .black.opacity(0.28), radius: 30, x: 0, y: 18)

                if !liveTranscriptText.isEmpty {
                    Text(liveTranscriptText)
                        .font(.footnote)
                        .foregroundStyle(.white.opacity(0.72))
                        .padding(.horizontal, 30)
                        .multilineTextAlignment(.center)
                }

                Button {
                    if viewModel.speechManager.isRecording {
                        Task { await stopVoiceFlow() }
                    }
                } label: {
                    Circle()
                        .fill(Color.red.opacity(0.95))
                        .frame(width: 54, height: 54)
                        .overlay {
                            Image(systemName: "xmark")
                                .font(.system(size: 18, weight: .bold))
                                .foregroundStyle(.white)
                        }
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func promptChip(_ title: String) -> some View {
        Button(title) {
            Task { await viewModel.send(text: promptText(for: title)) }
        }
        .font(.caption.weight(.semibold))
        .foregroundStyle(.white.opacity(0.82))
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(
            Capsule(style: .continuous)
                .fill(Color.white.opacity(0.06))
        )
        .buttonStyle(.plain)
    }

    private var liveTranscriptText: String {
        viewModel.isRefiningVoiceInput ? viewModel.liveTranscript : viewModel.speechManager.transcript
    }

    private func recordingDurationText(referenceDate: Date = Date()) -> String {
        let startedAt = recordingStartedAt ?? Date()
        let seconds = max(referenceDate.timeIntervalSince(startedAt), 0)
        return String(format: "%.1fs", seconds)
    }

    private var connectionLabel: String {
        switch viewModel.connectionState {
        case .checking:
            "è¿æ¥ä¸­"
        case .connected:
            "å¨çº¿"
        case .disconnected:
            "ç¦»çº¿"
        }
    }

    private var connectionColor: Color {
        switch viewModel.connectionState {
        case .checking:
            .orange
        case .connected:
            .green
        case .disconnected:
            .red
        }
    }

    private var isDisconnected: Bool {
        if case .disconnected = viewModel.connectionState {
            return true
        }
        return false
    }

    private func promptText(for title: String) -> String {
        switch title {
        case "ä»å¤©å®æ":
            "ççæä»å¤©çå®æ"
        case "æ°å»ºææ":
            "å¸®ææ°å»ºä¸ä¸ªææå®æ"
        case "æ»ç»æ¬å¨":
            "æ»ç»ä¸ä¸æè¿å¨çå®æ"
        default:
            title
        }
    }

    private func startVoiceFlow() async {
        guard !viewModel.speechManager.isRecording, !viewModel.isRefiningVoiceInput else { return }
        recordingStartedAt = Date()
        await viewModel.beginRecording()
    }

    private func stopVoiceFlow() async {
        guard viewModel.speechManager.isRecording else { return }
        await viewModel.stopRecordingAndSend()
        recordingStartedAt = nil
    }

    private func sendManualInput() {
        let text = manualInput.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, !viewModel.isProcessing else { return }
        manualInput = ""
        Task { await viewModel.send(text: text) }
    }

    private func scrollToBottom(_ proxy: ScrollViewProxy, animated: Bool = true) {
        let action = {
            proxy.scrollTo("bottom-anchor", anchor: .bottom)
        }

        if animated {
            withAnimation(.easeOut(duration: 0.25)) {
                action()
            }
        } else {
            action()
        }
    }

    private func triggerPressHaptic() {
        let generator = UIImpactFeedbackGenerator(style: .medium)
        generator.prepare()
        generator.impactOccurred(intensity: 0.95)
    }

    private func triggerReleaseHaptic() {
        let generator = UINotificationFeedbackGenerator()
        generator.prepare()
        generator.notificationOccurred(.success)
    }

    private func beginVoiceHoldIfNeeded() {
        guard manualInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        guard !isHoldingVoice, !viewModel.speechManager.isRecording, !viewModel.isRefiningVoiceInput else { return }
        isHoldingVoice = true
        triggerPressHaptic()
        Task { await startVoiceFlow() }
    }

    private func endVoiceHoldIfNeeded() {
        guard isHoldingVoice else { return }
        isHoldingVoice = false
        triggerReleaseHaptic()
        Task { await stopVoiceFlow() }
    }

    private func handleEditTime(_ preview: ChatMessage.SchedulePreview) {
        editingPreview = preview
        timeDraftStart = preview.startDate
        timeDraftEnd = preview.endDate
        showTimeSheet = true
    }

    private func handleAddLocation(_ preview: ChatMessage.SchedulePreview) {
        editingPreview = preview
        locationDraft = preview.location.replacingOccurrences(of: "ð ", with: "")
        showLocationSheet = true
    }

    private func handleEditRepeat(_ preview: ChatMessage.SchedulePreview) {
        repeatPreview = preview
    }

    private func handleDelete(_ preview: ChatMessage.SchedulePreview) {
        deletePreview = preview
    }

    private func requestAllCapabilities() async {
        await viewModel.speechManager.requestPermissions()
        _ = await calendarManager.requestAccess()
        _ = await permissionManager.requestNotifications()
        _ = await permissionManager.requestReminders()
        locationWeatherManager.requestWhenInUseAccess()
        permissionManager.refreshStatuses()
        locationWeatherManager.refresh()
    }
}

private struct VoiceWaveformView: View {
    let isActive: Bool

    private let barHeights: [CGFloat] = [10, 18, 12, 26, 16, 24, 14, 20, 12]

    var body: some View {
        HStack(alignment: .center, spacing: 5) {
            ForEach(Array(barHeights.enumerated()), id: \.offset) { index, baseHeight in
                VoiceWaveformBar(isActive: isActive, index: index, baseHeight: baseHeight)
            }
        }
        .frame(height: 24)
    }
}

private struct VoiceWaveformBar: View {
    let isActive: Bool
    let index: Int
    let baseHeight: CGFloat

    var body: some View {
        TimelineView(.animation(minimumInterval: 0.12)) { context in
            let time = context.date.timeIntervalSinceReferenceDate
            let phase = Double(index) * 0.17
            let offset = sin((time + phase) * 5.4)
            let animatedHeight = max(8, baseHeight + CGFloat(offset * 8))
            let currentHeight = isActive ? animatedHeight : 8

            RoundedRectangle(cornerRadius: 4, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: isActive
                            ? [Color(red: 0.10, green: 0.86, blue: 0.67), Color(red: 0.10, green: 0.66, blue: 0.99)]
                            : [Color.gray.opacity(0.35), Color.gray.opacity(0.20)],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .frame(width: 5, height: currentHeight)
        }
    }
}

private extension Color {
    init(hex: UInt, alpha: Double = 1) {
        self.init(
            .sRGB,
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255,
            opacity: alpha
        )
    }
}

import SwiftUI
import UIKit

struct CameraPicker: UIViewControllerRepresentable {
    var onImagePicked: (UIImage) -> Void
    @Environment(\.dismiss) private var dismiss

    func makeCoordinator() -> Coordinator {
        Coordinator(onImagePicked: onImagePicked, dismiss: dismiss)
    }

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.sourceType = UIImagePickerController.isSourceTypeAvailable(.camera) ? .camera : .photoLibrary
        picker.cameraCaptureMode = .photo
        picker.delegate = context.coordinator
        picker.allowsEditing = false
        return picker
    }

    func updateUIViewController(_ uiViewController: UIImagePickerController, context: Context) {}

    final class Coordinator: NSObject, UINavigationControllerDelegate, UIImagePickerControllerDelegate {
        private let onImagePicked: (UIImage) -> Void
        private let dismiss: DismissAction

        init(onImagePicked: @escaping (UIImage) -> Void, dismiss: DismissAction) {
            self.onImagePicked = onImagePicked
            self.dismiss = dismiss
        }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            dismiss()
        }

        func imagePickerController(
            _ picker: UIImagePickerController,
            didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]
        ) {
            if let image = info[.originalImage] as? UIImage {
                onImagePicked(image)
            }
            dismiss()
        }
    }
}