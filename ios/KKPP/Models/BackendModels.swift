import Foundation

struct ProcessRequest: Codable {
    let userId: String
    let text: String
    let timezone: String
    let calendarContext: CalendarContext?
    let deviceContext: DeviceContext?
}

struct CalendarContext: Codable {
    let events: [CalendarEventSummary]
}

struct DeviceContext: Codable {
    let currentDateISO: String
    let localDateLabel: String?
    let city: String?
    let district: String?
    let weatherSummary: String?
    let temperatureText: String?
    let latitude: Double?
    let longitude: Double?
}

struct ProcessResponse: Codable {
    let reply: String
    let structuredAction: StructuredAction?
    let structuredActions: [StructuredAction]?
    let collaboration: CollaborationPayload?
}

struct CollaborationPayload: Codable {
    let intentAnalysis: CollaborationStage?
    let planning: CollaborationStage?
    let decision: CollaborationStage?
}

struct CollaborationStage: Codable {
    let userGoal: String?
    let intentType: String?
    let complexity: String?
    let reasoningSummary: String?
    let planningSummary: String?
    let internalSummary: String?
    let proposedActionType: String?
    let decision: String?
}

struct StreamingEvent: Decodable {
    let type: String
    let content: String?
    let reply: String?
    let structuredAction: StructuredAction?
    let structuredActions: [StructuredAction]?
    let message: String?
    let collaboration: CollaborationPayload?
    let stage: String?
}
