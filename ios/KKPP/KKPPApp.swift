import AppIntents
import SwiftUI

@main
struct KKPPApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
}

struct OpenTodayScheduleIntent: AppIntent {
    static var title: LocalizedStringResource = "查看今天安排"
    static var description = IntentDescription("打开 KKPP 并查看今天的安排。")
    static var openAppWhenRun = true

    func perform() async throws -> some IntentResult & ProvidesDialog {
        .result(dialog: "已为你打开 KKPP，查看今天安排。")
    }
}

struct CreateScheduleWithVoiceIntent: AppIntent {
    static var title: LocalizedStringResource = "语音新建安排"
    static var description = IntentDescription("打开 KKPP，直接开始语音录入新的安排。")
    static var openAppWhenRun = true

    func perform() async throws -> some IntentResult & ProvidesDialog {
        .result(dialog: "已打开 KKPP，你可以直接按住麦克风说出安排。")
    }
}

struct KKPPShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: OpenTodayScheduleIntent(),
            phrases: [
                "用 \(.applicationName) 看今天安排",
                "在 \(.applicationName) 里查看今天日程"
            ],
            shortTitle: "今天安排",
            systemImageName: "calendar"
        )

        AppShortcut(
            intent: CreateScheduleWithVoiceIntent(),
            phrases: [
                "用 \(.applicationName) 新建安排",
                "在 \(.applicationName) 里语音添加日程"
            ],
            shortTitle: "语音安排",
            systemImageName: "mic"
        )
    }
}
