import EventKit
import Foundation
import UserNotifications

@MainActor
final class CalendarManager: ObservableObject {
    enum CalendarError: LocalizedError {
        case permissionDenied
        case invalidDate
        case saveFailed
        case eventNotFound

        var errorDescription: String? {
            switch self {
            case .permissionDenied:
                return "请先允许 KKPP 访问你的日历。"
            case .invalidDate:
                return "系统没能识别这条日程的时间，请再说一次。"
            case .saveFailed:
                return "日程创建失败，请稍后再试。"
            case .eventNotFound:
                return "这条日程没有找到，可能已经被删除。"
            }
        }
    }

    enum RecurrenceOption: String, CaseIterable, Identifiable {
        case none
        case daily
        case weekly
        case monthly

        var id: String { rawValue }

        var title: String {
            switch self {
            case .none: "不重复"
            case .daily: "每天"
            case .weekly: "每周"
            case .monthly: "每月"
            }
        }

        fileprivate var rule: EKRecurrenceRule? {
            switch self {
            case .none:
                nil
            case .daily:
                EKRecurrenceRule(recurrenceWith: .daily, interval: 1, end: nil)
            case .weekly:
                EKRecurrenceRule(recurrenceWith: .weekly, interval: 1, end: nil)
            case .monthly:
                EKRecurrenceRule(recurrenceWith: .monthly, interval: 1, end: nil)
            }
        }
    }

    @Published private(set) var authorizationStatus: EKAuthorizationStatus = .notDetermined

    private let eventStore = EKEventStore()
    private let notificationCenter = UNUserNotificationCenter.current()
    private let reminderMappingKey = "kkpp.event.reminder.mapping"
    private let isoFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        formatter.timeZone = TimeZone(identifier: "Asia/Shanghai")
        return formatter
    }()

    init() {
        authorizationStatus = EKEventStore.authorizationStatus(for: .event)
    }

    var hasReadAccess: Bool {
        authorizationStatus == .fullAccess
    }

    var hasWriteAccess: Bool {
        authorizationStatus == .fullAccess || authorizationStatus == .writeOnly
    }

    func requestAccess() async -> Bool {
        do {
            let granted = try await eventStore.requestFullAccessToEvents()
            authorizationStatus = EKEventStore.authorizationStatus(for: .event)
            return granted
        } catch {
            authorizationStatus = EKEventStore.authorizationStatus(for: .event)
            return false
        }
    }

    func addEvent(from action: StructuredAction) async throws {
        guard hasWriteAccess else {
            throw CalendarError.permissionDenied
        }

        guard action.type == "add_calendar_event",
              let title = action.payload.title,
              let startISO = action.payload.startISO,
              let durationHours = action.payload.durationHours else {
            throw CalendarError.invalidDate
        }

        let startDate = parseDate(startISO)
        guard let startDate else {
            throw CalendarError.invalidDate
        }

        let event = EKEvent(eventStore: eventStore)
        event.title = title
        event.startDate = startDate
        event.endDate = startDate.addingTimeInterval(durationHours * 3600)
        event.notes = action.payload.notes
        event.location = action.payload.location
        event.calendar = eventStore.defaultCalendarForNewEvents

        if let reminderMinutes = action.payload.reminderMinutesBefore {
            event.addAlarm(EKAlarm(relativeOffset: TimeInterval(-reminderMinutes * 60)))
        }

        do {
            try eventStore.save(event, span: .thisEvent)
            syncCompanionSystems(for: event)
        } catch {
            throw CalendarError.saveFailed
        }
    }

    func updateEventTime(eventID: String, startDate: Date, endDate: Date) throws {
        let event = try loadEvent(id: eventID)
        event.startDate = startDate
        event.endDate = endDate
        try save(event: event)
    }

    func updateEventLocation(eventID: String, location: String) throws {
        let event = try loadEvent(id: eventID)
        event.location = location.trimmingCharacters(in: .whitespacesAndNewlines)
        try save(event: event)
    }

    func updateRecurrence(eventID: String, option: RecurrenceOption) throws {
        let event = try loadEvent(id: eventID)
        if let rule = option.rule {
            event.recurrenceRules = [rule]
        } else {
            event.recurrenceRules = nil
        }
        try save(event: event)
    }

    func deleteEvent(eventID: String) throws {
        let event = try loadEvent(id: eventID)
        do {
            try eventStore.remove(event, span: .thisEvent)
            removeCompanionSystems(forEventID: eventID)
        } catch {
            throw CalendarError.saveFailed
        }
    }

    func fetchUpcomingEvents(days: Int = 7) async throws -> [CalendarEventSummary] {
        guard hasReadAccess else {
            throw CalendarError.permissionDenied
        }

        let calendar = Calendar(identifier: .gregorian)
        let startDate = calendar.startOfDay(for: Date())
        let endDate = calendar.date(byAdding: .day, value: days, to: startDate) ?? startDate
        let predicate = eventStore.predicateForEvents(withStart: startDate, end: endDate, calendars: nil)

        return eventStore.events(matching: predicate)
            .sorted { $0.startDate < $1.startDate }
            .map { event in
                CalendarEventSummary(
                    id: event.eventIdentifier ?? UUID().uuidString,
                    title: event.title,
                    startISO: isoFormatter.string(from: event.startDate),
                    endISO: isoFormatter.string(from: event.endDate),
                    location: event.location ?? ""
                )
            }
    }

    func fetchEvents(anchorDateISO: String?, rangeDays: Int) async throws -> [CalendarEventSummary] {
        guard hasReadAccess else {
            throw CalendarError.permissionDenied
        }

        let calendar = Calendar(identifier: .gregorian)
        let startDate = parseDate(anchorDateISO ?? "") ?? Date()
        let endDate = calendar.date(byAdding: .day, value: max(rangeDays, 1), to: startDate) ?? startDate
        let predicate = eventStore.predicateForEvents(withStart: startDate, end: endDate, calendars: nil)

        return eventStore.events(matching: predicate)
            .sorted { $0.startDate < $1.startDate }
            .map { event in
                CalendarEventSummary(
                    id: event.eventIdentifier ?? UUID().uuidString,
                    title: event.title,
                    startISO: isoFormatter.string(from: event.startDate),
                    endISO: isoFormatter.string(from: event.endDate),
                    location: event.location ?? ""
                )
            }
    }

    private func parseDate(_ isoString: String) -> Date? {
        if let date = isoFormatter.date(from: isoString) {
            return date
        }

        let fallback = ISO8601DateFormatter()
        fallback.formatOptions = [.withInternetDateTime]
        fallback.timeZone = TimeZone(identifier: "Asia/Shanghai")
        return fallback.date(from: isoString)
    }

    private func loadEvent(id: String) throws -> EKEvent {
        guard hasWriteAccess else {
            throw CalendarError.permissionDenied
        }
        guard let event = eventStore.event(withIdentifier: id) else {
            throw CalendarError.eventNotFound
        }
        return event
    }

    private func save(event: EKEvent) throws {
        do {
            try eventStore.save(event, span: .thisEvent)
            syncCompanionSystems(for: event)
        } catch {
            throw CalendarError.saveFailed
        }
    }

    private func syncCompanionSystems(for event: EKEvent) {
        Task {
            await scheduleNotification(for: event)
            try? syncReminder(for: event)
        }
    }

    private func removeCompanionSystems(forEventID eventID: String) {
        notificationCenter.removePendingNotificationRequests(withIdentifiers: [notificationIdentifier(for: eventID)])

        guard let reminderID = reminderMappings[eventID],
              let reminder = eventStore.calendarItem(withIdentifier: reminderID) as? EKReminder else {
            removeReminderMapping(for: eventID)
            return
        }

        do {
            try eventStore.remove(reminder, commit: true)
        } catch {
            // Ignore reminder cleanup errors to keep event deletion responsive.
        }
        removeReminderMapping(for: eventID)
    }

    private func scheduleNotification(for event: EKEvent) async {
        guard let eventID = event.eventIdentifier else { return }

        let content = UNMutableNotificationContent()
        content.title = event.title
        if let location = event.location, location.isEmpty == false {
            content.body = "地点：\(location)"
        } else {
            content.body = "你有一项新的安排即将开始。"
        }
        content.sound = .default

        let reminderOffset: TimeInterval
        if let relativeOffset = event.alarms?.first?.relativeOffset {
            reminderOffset = relativeOffset
        } else {
            reminderOffset = -900
        }

        let triggerDate = event.startDate.addingTimeInterval(reminderOffset)
        guard triggerDate > Date() else { return }

        let components = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: triggerDate)
        let request = UNNotificationRequest(
            identifier: notificationIdentifier(for: eventID),
            content: content,
            trigger: UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
        )

        notificationCenter.removePendingNotificationRequests(withIdentifiers: [notificationIdentifier(for: eventID)])
        try? await notificationCenter.add(request)
    }

    private func syncReminder(for event: EKEvent) throws {
        let status = EKEventStore.authorizationStatus(for: .reminder)
        guard status == .fullAccess || status == .writeOnly else { return }
        guard let eventID = event.eventIdentifier else { return }
        guard let reminderCalendar = eventStore.defaultCalendarForNewReminders() else { return }

        let reminder: EKReminder
        if let reminderID = reminderMappings[eventID],
           let existing = eventStore.calendarItem(withIdentifier: reminderID) as? EKReminder {
            reminder = existing
        } else {
            reminder = EKReminder(eventStore: eventStore)
            reminder.calendar = reminderCalendar
        }

        reminder.title = event.title
        reminder.notes = [event.location, event.notes].compactMap { $0 }.joined(separator: "\n")
        reminder.calendar = reminderCalendar
        reminder.dueDateComponents = Calendar.current.dateComponents(in: .current, from: event.startDate)

        if let relativeOffset = event.alarms?.first?.relativeOffset {
            reminder.alarms = [EKAlarm(relativeOffset: relativeOffset)]
        }

        try eventStore.save(reminder, commit: true)
        if let reminderID = reminder.calendarItemIdentifier as String? {
            setReminderMapping(reminderID, for: eventID)
        }
    }

    private func notificationIdentifier(for eventID: String) -> String {
        "kkpp.event.notification.\(eventID)"
    }

    private var reminderMappings: [String: String] {
        UserDefaults.standard.dictionary(forKey: reminderMappingKey) as? [String: String] ?? [:]
    }

    private func setReminderMapping(_ reminderID: String, for eventID: String) {
        var mappings = reminderMappings
        mappings[eventID] = reminderID
        UserDefaults.standard.set(mappings, forKey: reminderMappingKey)
    }

    private func removeReminderMapping(for eventID: String) {
        var mappings = reminderMappings
        mappings.removeValue(forKey: eventID)
        UserDefaults.standard.set(mappings, forKey: reminderMappingKey)
    }
}
