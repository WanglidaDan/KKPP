import Foundation

struct CalendarEventSummary: Codable, Identifiable, Hashable {
    let id: String
    let title: String
    let startISO: String
    let endISO: String
    let location: String
}
