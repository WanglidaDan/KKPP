import AuthenticationServices
import SwiftUI

struct AssistantView: View {
    @ObservedObject var viewModel: ChatViewModel

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [
                    Color(red: 0.95, green: 0.98, blue: 1.00),
                    Color(red: 0.89, green: 0.96, blue: 0.97)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()

            VStack(spacing: 16) {
                header
                PermissionBannerView(
                    microphoneAuthorized: viewModel.speechManager.microphoneAuthorized,
                    speechAuthorized: viewModel.speechManager.speechAuthorized,
                    calendarGranted: viewModel.calendarManager.hasReadAccess
                )

                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(spacing: 12) {
                            ForEach(viewModel.messages) { message in
                                MessageBubbleView(message: message)
                                    .id(message.id)
                            }

                            if !viewModel.speechManager.transcript.isEmpty {
                                MessageBubbleView(
                                    message: ChatMessage(role: .system, content: "正在识别：\(viewModel.speechManager.transcript)")
                                )
                            }

                            if viewModel.isProcessing {
                                HStack(spacing: 12) {
                                    ProgressView()
                                    Text("秘书正在整理安排…")
                                        .font(.subheadline)
                                        .foregroundStyle(.secondary)
                                }
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.top, 8)
                            }
                        }
                        .padding(.horizontal)
                        .padding(.bottom, 8)
                    }
                    .onChange(of: viewModel.messages.count) { _, _ in
                        if let lastId = viewModel.messages.last?.id {
                            withAnimation {
                                proxy.scrollTo(lastId, anchor: .bottom)
                            }
                        }
                    }
                }

                if let errorMessage = viewModel.errorMessage {
                    Text(errorMessage)
                        .font(.footnote)
                        .foregroundStyle(.red)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal)
                }

                VStack(spacing: 10) {
                    RecordingButton(
                        isRecording: viewModel.speechManager.isRecording,
                        actionStart: {
                            guard !viewModel.speechManager.isRecording else { return }
                            Task {
                                await viewModel.beginRecording()
                            }
                        },
                        actionEnd: {
                            guard viewModel.speechManager.isRecording else { return }
                            Task {
                                await viewModel.stopRecordingAndSend()
                            }
                        }
                    )

                    Text(viewModel.speechManager.isRecording ? "松手后立即发送" : "按住说话")
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(.secondary)
                }
                .padding(.bottom, 12)
            }
            .padding()
        }
        .task {
            await viewModel.bootstrap()
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                VStack(alignment: .leading, spacing: 6) {
                    Text("KKPP 私人秘書")
                        .font(.system(size: 28, weight: .bold, design: .rounded))
                    Text("语音驱动的多 Agent 日历助理")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                Spacer()
            }

            if viewModel.authManager.isSignedIn {
                HStack {
                    Label("已登录", systemImage: "person.crop.circle.badge.checkmark")
                        .font(.subheadline.weight(.semibold))
                    Text(viewModel.authManager.displayName)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            } else {
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
                .signInWithAppleButtonStyle(.black)
                .frame(height: 46)
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            }
        }
    }
}
