import Foundation

struct StructuredAction: Codable {
    let type: String
    let payload: Payload

    struct Payload: Codable {
        let title: String?
        let startISO: String?
        let durationHours: Double?
        let notes: String?
        let location: String?
        let reminderMinutesBefore: Int?
        let dateISO: String?
        let rangeDays: Int?
        let focus: String?
    }
}
