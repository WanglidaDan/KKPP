import Foundation

struct ProcessRequest: Codable {
    let userId: String
    let text: String
    let timezone: String
    let calendarContext: CalendarContext?
}

struct CalendarContext: Codable {
    let events: [CalendarEventSummary]
}

struct ProcessResponse: Codable {
    let reply: String
    let structuredAction: StructuredAction?
}

struct StreamingEvent: Decodable {
    let type: String
    let content: String?
    let reply: String?
    let structuredAction: StructuredAction?
    let message: String?
}
