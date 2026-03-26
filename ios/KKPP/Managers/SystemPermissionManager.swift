import EventKit
import Foundation
import UserNotifications

@MainActor
final class SystemPermissionManager: ObservableObject {
    @Published private(set) var notificationStatus: UNAuthorizationStatus = .notDetermined
    @Published private(set) var reminderStatus: EKAuthorizationStatus = .notDetermined

    private let eventStore = EKEventStore()

    init() {
        refreshStatuses()
    }

    func refreshStatuses() {
        reminderStatus = EKEventStore.authorizationStatus(for: .reminder)

        Task {
            let settings = await UNUserNotificationCenter.current().notificationSettings()
            await MainActor.run {
                self.notificationStatus = settings.authorizationStatus
            }
        }
    }

    @discardableResult
    func requestNotifications() async -> Bool {
        do {
            let granted = try await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .badge, .sound])
            let settings = await UNUserNotificationCenter.current().notificationSettings()
            notificationStatus = settings.authorizationStatus
            return granted
        } catch {
            let settings = await UNUserNotificationCenter.current().notificationSettings()
            notificationStatus = settings.authorizationStatus
            return false
        }
    }

    @discardableResult
    func requestReminders() async -> Bool {
        do {
            let granted = try await eventStore.requestFullAccessToReminders()
            reminderStatus = EKEventStore.authorizationStatus(for: .reminder)
            return granted
        } catch {
            reminderStatus = EKEventStore.authorizationStatus(for: .reminder)
            return false
        }
    }
}
