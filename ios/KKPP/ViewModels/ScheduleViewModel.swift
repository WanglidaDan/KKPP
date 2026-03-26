import Foundation

@MainActor
final class ScheduleViewModel: ObservableObject {
    @Published var events: [CalendarEventSummary] = []
    @Published var errorMessage: String?
    @Published var isLoading = false

    private let calendarManager: CalendarManager

    init(calendarManager: CalendarManager) {
        self.calendarManager = calendarManager
    }

    func refresh() async {
        isLoading = true
        errorMessage = nil

        do {
            events = try await calendarManager.fetchUpcomingEvents(days: 7)
        } catch {
            errorMessage = error.localizedDescription
        }

        isLoading = false
    }
}
