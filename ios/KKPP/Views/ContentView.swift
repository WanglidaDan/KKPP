import SwiftUI

struct ContentView: View {
    @StateObject private var authManager = AuthManager()
    @StateObject private var speechManager = SpeechManager()
    @StateObject private var calendarManager = CalendarManager()
    @StateObject private var chatViewModel: ChatViewModel
    @StateObject private var scheduleViewModel: ScheduleViewModel

    init() {
        let authManager = AuthManager()
        let speechManager = SpeechManager()
        let calendarManager = CalendarManager()
        let backendService = BackendService(baseURLString: AppConfig.backendBaseURL)

        _authManager = StateObject(wrappedValue: authManager)
        _speechManager = StateObject(wrappedValue: speechManager)
        _calendarManager = StateObject(wrappedValue: calendarManager)
        _chatViewModel = StateObject(
            wrappedValue: ChatViewModel(
                speechManager: speechManager,
                calendarManager: calendarManager,
                authManager: authManager,
                backendService: backendService
            )
        )
        _scheduleViewModel = StateObject(wrappedValue: ScheduleViewModel(calendarManager: calendarManager))
    }

    var body: some View {
        TabView {
            AssistantView(viewModel: chatViewModel)
                .tabItem {
                    Label("Assistant", systemImage: "message.badge.waveform")
                }

            ScheduleView(viewModel: scheduleViewModel)
                .tabItem {
                    Label("Schedule", systemImage: "calendar")
                }
        }
    }
}
