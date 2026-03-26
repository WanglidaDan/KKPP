import SwiftUI

@MainActor
final class AppContainer: ObservableObject {
    let authManager: AuthManager
    let speechManager: SpeechManager
    let calendarManager: CalendarManager
    let permissionManager: SystemPermissionManager
    let locationWeatherManager: LocationWeatherManager
    let chatViewModel: ChatViewModel
    let scheduleViewModel: ScheduleViewModel

    init() {
        let authManager = AuthManager()
        let speechManager = SpeechManager()
        let calendarManager = CalendarManager()
        let permissionManager = SystemPermissionManager()
        let locationWeatherManager = LocationWeatherManager()
        let backendService = BackendService(baseURLString: AppConfig.backendBaseURL)

        self.authManager = authManager
        self.speechManager = speechManager
        self.calendarManager = calendarManager
        self.permissionManager = permissionManager
        self.locationWeatherManager = locationWeatherManager
        self.chatViewModel = ChatViewModel(
            speechManager: speechManager,
            calendarManager: calendarManager,
            authManager: authManager,
            backendService: backendService,
            locationWeatherManager: locationWeatherManager
        )
        self.scheduleViewModel = ScheduleViewModel(calendarManager: calendarManager)
    }
}

@MainActor
final class ContentBootstrapper: ObservableObject {
    @Published private(set) var appContainer: AppContainer?

    func prepareIfNeeded() async {
        guard appContainer == nil else { return }
        await Task.yield()
        appContainer = AppContainer()
    }
}

struct ContentView: View {
    @StateObject private var bootstrapper = ContentBootstrapper()
    @State private var showingSchedule = false

    var body: some View {
        Group {
            if let appContainer = bootstrapper.appContainer {
                AssistantView(
                    viewModel: appContainer.chatViewModel,
                    permissionManager: appContainer.permissionManager,
                    locationWeatherManager: appContainer.locationWeatherManager,
                    calendarManager: appContainer.calendarManager,
                    onOpenSchedule: {
                        showingSchedule = true
                    }
                )
                .fullScreenCover(isPresented: $showingSchedule) {
                    ScheduleView(
                        viewModel: appContainer.scheduleViewModel,
                        locationWeatherManager: appContainer.locationWeatherManager
                    )
                }
            } else {
                launchPlaceholder
            }
        }
        .task {
            await bootstrapper.prepareIfNeeded()
        }
    }

    private var launchPlaceholder: some View {
        ZStack {
            LinearGradient(
                colors: [
                    Color(red: 0.97, green: 0.98, blue: 1.0),
                    Color(red: 0.93, green: 0.97, blue: 0.99)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()

            VStack(spacing: 16) {
                Image(systemName: "message.badge.waveform")
                    .font(.system(size: 34, weight: .semibold))
                    .foregroundStyle(.blue)
                Text("KKPP")
                    .font(.system(size: 28, weight: .bold, design: .rounded))
                Text("正在准备你的日程助手…")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                ProgressView()
                    .padding(.top, 4)
            }
            .padding(32)
        }
    }
}

