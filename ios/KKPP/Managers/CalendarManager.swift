import EventKit
import Foundation

@MainActor
final class CalendarManager: ObservableObject {
    enum CalendarError: LocalizedError {
        case permissionDenied
        case invalidDate
        case saveFailed

        var errorDescription: String? {
            switch self {
            case .permissionDenied:
                return "请先允许 KKPP 访问你的日历。"
            case .invalidDate:
                return "系统没能识别这条日程的时间，请再说一次。"
            case .saveFailed:
                return "日程创建失败，请稍后再试。"
            }
        }
    }

    @Published private(set) var authorizationStatus: EKAuthorizationStatus = .notDetermined

    private let eventStore = EKEventStore()
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
        guard hasReadAccess else {
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
        } catch {
            throw CalendarError.saveFailed
        }
    }

    func fetchUpcomingEvents(days: Int = 7) async throws -> [CalendarEventSummary] {
        guard hasReadAccess else {
            throw CalendarError.permissionDenied
        }

        let calendar = Calendar(identifier: .gregorian)
        let startDate = Date()
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
}
