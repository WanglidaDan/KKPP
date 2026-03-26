import SwiftUI

struct ScheduleView: View {
    @ObservedObject var viewModel: ScheduleViewModel
    @ObservedObject var locationWeatherManager: LocationWeatherManager
    @Environment(\.dismiss) private var dismiss

    @State private var selectedDate = Date()
    @State private var showingMonthSheet = false

    private let calendar = Calendar(identifier: .gregorian)

    var body: some View {
        NavigationStack {
            ZStack(alignment: .bottom) {
                background

                if viewModel.isLoading {
                    ProgressView("正在整理时间线…")
                        .tint(.white)
                        .foregroundStyle(.white)
                } else if let errorMessage = viewModel.errorMessage {
                    errorState(errorMessage)
                } else {
                    ScrollView(showsIndicators: false) {
                        LazyVStack(spacing: 0, pinnedViews: []) {
                            topSummary
                                .padding(.horizontal, 22)
                                .padding(.top, 12)
                                .padding(.bottom, 18)

                            ForEach(timelineDays) { day in
                                TimepageDayRow(
                                    day: day,
                                    isSelected: calendar.isDate(day.date, inSameDayAs: selectedDate)
                                )
                                .contentShape(Rectangle())
                                .onTapGesture {
                                    withAnimation(.spring(response: 0.28, dampingFraction: 0.82)) {
                                        selectedDate = day.date
                                    }
                                }
                            }
                        }
                        .padding(.bottom, 120)
                    }
                }

                bottomDock
            }
            .navigationBarHidden(true)
        }
        .sheet(isPresented: $showingMonthSheet) {
            TimepageMonthSheet(
                selectedDate: $selectedDate,
                markedDates: timelineDays.filter { !$0.events.isEmpty }.map(\.date)
            )
            .presentationDetents([.fraction(0.62)])
            .presentationDragIndicator(.hidden)
        }
        .task {
            locationWeatherManager.refresh()
            await viewModel.refresh()
        }
    }

    private var background: some View {
        LinearGradient(
            colors: [
                Color(red: 0.16, green: 0.08, blue: 0.24),
                Color(red: 0.15, green: 0.07, blue: 0.23),
                Color(red: 0.10, green: 0.05, blue: 0.16)
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
        .overlay(
            Rectangle()
                .fill(Color.black.opacity(0.18))
                .ignoresSafeArea()
        )
        .ignoresSafeArea()
    }

    private var topSummary: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top) {
                Button {
                    dismiss()
                } label: {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 16, weight: .bold))
                        .foregroundStyle(.white.opacity(0.92))
                        .frame(width: 38, height: 38)
                        .background(Color.black.opacity(0.28))
                        .clipShape(Circle())
                }
                .buttonStyle(.plain)

                VStack(alignment: .leading, spacing: 4) {
                    Text(monthTitle)
                        .font(.system(size: 34, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)
                    Text("返回秘书")
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.5))
                }

                Spacer()
            }

            HStack(spacing: 12) {
                summaryPill(
                    title: dayTitleText,
                    value: "\(selectedDayEvents.count) 项安排"
                )
                summaryPill(
                    title: "天气",
                    value: locationWeatherManager.weatherSummary
                )
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func summaryPill(title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.white.opacity(0.52))
            Text(value)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.white)
                .lineLimit(1)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Color.white.opacity(0.07))
        )
    }

    private var bottomDock: some View {
        HStack(spacing: 18) {
            Button {
                showingMonthSheet = true
            } label: {
                Image(systemName: "circle.grid.3x3.fill")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.92))
                    .frame(width: 50, height: 50)
                    .background(Color.black.opacity(0.46))
                    .clipShape(Circle())
            }
            .buttonStyle(.plain)

            Button {
                withAnimation(.spring(response: 0.26, dampingFraction: 0.8)) {
                    selectedDate = Date()
                }
            } label: {
                Image(systemName: "chevron.up")
                    .font(.system(size: 18, weight: .bold))
                    .foregroundStyle(.white.opacity(0.92))
                    .frame(width: 52, height: 52)
                    .background(Color.black.opacity(0.52))
                    .clipShape(Circle())
            }
            .buttonStyle(.plain)

            HStack(spacing: 2) {
                Button {
                    Task { await viewModel.refresh() }
                } label: {
                    Image(systemName: "ellipsis")
                        .font(.system(size: 18, weight: .bold))
                        .foregroundStyle(.white)
                        .frame(width: 54, height: 50)
                }

                Divider()
                    .frame(height: 24)
                    .overlay(Color.white.opacity(0.08))

                Button {
                    // Placeholder for future quick-create entry in the calendar page.
                } label: {
                    Image(systemName: "plus")
                        .font(.system(size: 20, weight: .bold))
                        .foregroundStyle(.white)
                        .frame(width: 54, height: 50)
                }
            }
            .background(Color.black.opacity(0.50))
            .clipShape(Capsule(style: .continuous))
        }
        .padding(.bottom, 18)
    }

    private func errorState(_ text: String) -> some View {
        VStack(spacing: 14) {
            Image(systemName: "icloud.slash")
                .font(.system(size: 32))
                .foregroundStyle(.white)
            Text(text)
                .foregroundStyle(.white.opacity(0.86))
                .multilineTextAlignment(.center)
                .padding(.horizontal, 28)
            Button("重新加载") {
                Task { await viewModel.refresh() }
            }
            .buttonStyle(.borderedProminent)
        }
    }

    private var timelineDays: [TimelineDay] {
        let start = calendar.startOfDay(for: Date())

        return (0 ..< 7).compactMap { offset in
            guard let date = calendar.date(byAdding: .day, value: offset, to: start) else {
                return nil
            }

            let events = viewModel.eventsForDay(date)
            let forecast = locationWeatherManager.forecast(for: date)
            return TimelineDay(date: date, events: events, forecast: forecast)
        }
    }

    private var monthTitle: String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.dateFormat = "M月"
        return formatter.string(from: selectedDate)
    }

    private var dayTitleText: String {
        if calendar.isDateInToday(selectedDate) {
            return "今天"
        }
        if calendar.isDateInTomorrow(selectedDate) {
            return "明天"
        }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.dateFormat = "M月d日"
        return formatter.string(from: selectedDate)
    }

    private var selectedDayEvents: [CalendarEventSummary] {
        viewModel.eventsForDay(selectedDate)
    }
}

private struct TimelineDay: Identifiable {
    let id = UUID()
    let date: Date
    let events: [CalendarEventSummary]
    let forecast: LocationWeatherManager.DayForecast?
}

private struct TimepageDayRow: View {
    let day: TimelineDay
    let isSelected: Bool

    private let calendar = Calendar(identifier: .gregorian)

    var body: some View {
        HStack(alignment: .top, spacing: 16) {
            dateRail

            VStack(alignment: .leading, spacing: 12) {
                if day.events.isEmpty {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(Color.white.opacity(0.02))
                        .frame(height: 84)
                        .overlay(alignment: .trailing) {
                            weatherColumn
                                .padding(.trailing, 14)
                        }
                } else {
                    VStack(spacing: 10) {
                        ForEach(day.events) { event in
                            TimepageEventCard(event: event)
                        }
                    }
                    .overlay(alignment: .trailing) {
                        weatherColumn
                            .padding(.trailing, 10)
                    }
                }
            }
            .padding(.vertical, 16)
            .overlay(alignment: .topLeading) {
                Rectangle()
                    .fill(isSelected ? Color.white.opacity(0.16) : Color.white.opacity(0.05))
                    .frame(height: 1)
            }
        }
        .padding(.horizontal, 18)
        .background(isSelected ? Color.white.opacity(0.02) : .clear)
    }

    private var dateRail: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(weekdayText)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(isSelected ? .white : .white.opacity(0.65))
            Text(dayNumberText)
                .font(.system(size: 34, weight: .bold, design: .rounded))
                .foregroundStyle(isSelected ? .white : .white.opacity(0.92))
        }
        .frame(width: 58, alignment: .leading)
        .padding(.top, 14)
    }

    private var weatherColumn: some View {
        VStack(alignment: .trailing, spacing: 4) {
            Image(systemName: forecastSymbol)
                .font(.system(size: 20))
                .foregroundStyle(.white.opacity(0.78))
            Text(temperatureText)
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(.white.opacity(0.82))
        }
    }

    private var weekdayText: String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.dateFormat = "EEE"
        return formatter.string(from: day.date)
    }

    private var dayNumberText: String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.dateFormat = "d"
        return formatter.string(from: day.date)
    }

    private var temperatureText: String {
        guard let forecast = day.forecast else { return "--°" }
        return "\(Int(forecast.minTemperature.rounded()))°-\(Int(forecast.maxTemperature.rounded()))°"
    }

    private var forecastSymbol: String {
        guard let forecast = day.forecast else { return "cloud" }
        switch forecast.weatherCode {
        case 0: return "sun.max.fill"
        case 1, 2: return "cloud.sun.fill"
        case 3: return "cloud.fill"
        case 45, 48: return "cloud.fog.fill"
        case 51 ... 67, 80 ... 82: return "cloud.rain.fill"
        case 71 ... 77, 85, 86: return "cloud.snow.fill"
        case 95 ... 99: return "cloud.bolt.rain.fill"
        default: return "cloud.fill"
        }
    }
}

private struct TimepageEventCard: View {
    let event: CalendarEventSummary

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            RoundedRectangle(cornerRadius: 3, style: .continuous)
                .fill(Color(red: 0.20, green: 0.57, blue: 0.99))
                .frame(width: 5, height: 34)
                .overlay(alignment: .trailing) {
                    EmptyView()
                }

            Text(event.title)
                .font(.headline.weight(.semibold))
                .foregroundStyle(.white)

            Text("\(startTime) - \(endTime)")
                .font(.subheadline)
                .foregroundStyle(.white.opacity(0.74))

            if !event.location.isEmpty {
                Text(event.location)
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.56))
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color.white.opacity(0.05))
        )
    }

    private var startDate: Date {
        ISO8601DateFormatter().date(from: event.startISO) ?? Date()
    }

    private var endDate: Date {
        ISO8601DateFormatter().date(from: event.endISO) ?? startDate
    }

    private var startTime: String {
        Self.timeFormatter.string(from: startDate)
    }

    private var endTime: String {
        Self.timeFormatter.string(from: endDate)
    }

    private static let timeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.dateFormat = "HH:mm"
        return formatter
    }()
}

private struct TimepageMonthSheet: View {
    @Binding var selectedDate: Date
    let markedDates: [Date]

    private let calendar = Calendar(identifier: .gregorian)

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            VStack(alignment: .leading, spacing: 18) {
                Text(monthHeader)
                    .font(.system(size: 32, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                    .padding(.top, 24)

                LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 7), spacing: 16) {
                    ForEach(weekdayHeaders, id: \.self) { item in
                        Text(item)
                            .font(.caption)
                            .foregroundStyle(.white.opacity(0.56))
                    }

                    ForEach(monthDays, id: \.id) { day in
                        Button {
                            if let date = day.date {
                                selectedDate = date
                            }
                        } label: {
                            ZStack {
                                if let date = day.date, markedDates.contains(where: { calendar.isDate($0, inSameDayAs: date) }) {
                                    Circle()
                                        .stroke(Color.purple.opacity(0.92), lineWidth: 1.5)
                                }

                                if let date = day.date, calendar.isDate(date, inSameDayAs: selectedDate) {
                                    Circle()
                                        .fill(Color.purple.opacity(0.58))
                                }

                                Text(day.label)
                                    .font(.system(size: 16, weight: .semibold))
                                    .foregroundStyle(.white)
                            }
                            .frame(width: 34, height: 34)
                        }
                        .buttonStyle(.plain)
                        .disabled(day.date == nil)
                    }
                }

                Spacer()
            }
            .padding(.horizontal, 24)
        }
    }

    private var monthHeader: String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.dateFormat = "yyyy年 M月"
        return formatter.string(from: selectedDate)
    }

    private var weekdayHeaders: [String] {
        ["日", "一", "二", "三", "四", "五", "六"]
    }

    private var monthDays: [CalendarDayCell] {
        guard let interval = calendar.dateInterval(of: .month, for: selectedDate),
              let firstWeek = calendar.dateInterval(of: .weekOfMonth, for: interval.start),
              let lastWeek = calendar.dateInterval(of: .weekOfMonth, for: interval.end.addingTimeInterval(-1)) else {
            return []
        }

        var days: [CalendarDayCell] = []
        var current = firstWeek.start

        while current < lastWeek.end {
            let isCurrentMonth = calendar.isDate(current, equalTo: selectedDate, toGranularity: .month)
            let day = calendar.component(.day, from: current)
            days.append(CalendarDayCell(date: isCurrentMonth ? current : nil, label: "\(day)"))
            current = calendar.date(byAdding: .day, value: 1, to: current) ?? current.addingTimeInterval(86_400)
        }

        return days
    }
}

private struct CalendarDayCell: Identifiable {
    let id = UUID()
    let date: Date?
    let label: String
}
