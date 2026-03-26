import SwiftUI

struct ScheduleRowView: View {
    let event: CalendarEventSummary

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(event.title)
                .font(.headline)

            Label(formattedTimeRange, systemImage: "calendar")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            if !event.location.isEmpty {
                Label(event.location, systemImage: "mappin.and.ellipse")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Color(.secondarySystemBackground))
        )
    }

    private var formattedTimeRange: String {
        let formatter = ISO8601DateFormatter()
        let inputStart = formatter.date(from: event.startISO) ?? Date()
        let inputEnd = formatter.date(from: event.endISO) ?? inputStart

        let output = DateFormatter()
        output.locale = Locale(identifier: "zh_CN")
        output.timeZone = TimeZone(identifier: "Asia/Shanghai")
        output.dateFormat = "M月d日 EEEE HH:mm"

        let endFormatter = DateFormatter()
        endFormatter.locale = Locale(identifier: "zh_CN")
        endFormatter.timeZone = TimeZone(identifier: "Asia/Shanghai")
        endFormatter.dateFormat = "HH:mm"

        return "\(output.string(from: inputStart)) - \(endFormatter.string(from: inputEnd))"
    }
}
