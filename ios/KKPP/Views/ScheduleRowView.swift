import SwiftUI

struct ScheduleRowView: View {
    let event: CalendarEventSummary

    var body: some View {
        HStack(alignment: .top, spacing: 16) {
            VStack(alignment: .leading, spacing: 2) {
                Text(startTime)
                    .font(.system(size: 22, weight: .bold, design: .rounded))
                Text(endTime)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .frame(width: 62, alignment: .leading)

            VStack(spacing: 0) {
                Circle()
                    .fill(Color.blue)
                    .frame(width: 10, height: 10)

                Rectangle()
                    .fill(Color.blue.opacity(0.18))
                    .frame(width: 2)
                    .frame(maxHeight: .infinity)
            }

            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(event.title)
                            .font(.headline)
                        Text(relativeDateText)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Text(durationText)
                        .font(.caption.weight(.semibold))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(Capsule().fill(Color.blue.opacity(0.10)))
                        .foregroundStyle(.blue)
                }

                if !event.location.isEmpty {
                    Label(event.location, systemImage: "mappin.and.ellipse")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(Color(uiColor: .secondarySystemGroupedBackground))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .strokeBorder(Color.black.opacity(0.05), lineWidth: 1)
        )
    }

    private var startDate: Date {
        ISO8601DateFormatter().date(from: event.startISO) ?? Date()
    }

    private var endDate: Date {
        ISO8601DateFormatter().date(from: event.endISO) ?? startDate
    }

    private var startTime: String {
        timeFormatter.string(from: startDate)
    }

    private var endTime: String {
        timeFormatter.string(from: endDate)
    }

    private var durationText: String {
        let minutes = max(Int(endDate.timeIntervalSince(startDate) / 60), 0)
        if minutes >= 60 {
            let hours = minutes / 60
            let remaining = minutes % 60
            return remaining == 0 ? "\(hours)小时" : "\(hours)小时\(remaining)分"
        }
        return "\(minutes)分钟"
    }

    private var relativeDateText: String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.timeZone = TimeZone(identifier: "Asia/Shanghai")
        formatter.dateFormat = "M月d日 EEEE"
        return formatter.string(from: startDate)
    }

    private var timeFormatter: DateFormatter {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.timeZone = TimeZone(identifier: "Asia/Shanghai")
        formatter.dateFormat = "HH:mm"
        return formatter
    }
}
