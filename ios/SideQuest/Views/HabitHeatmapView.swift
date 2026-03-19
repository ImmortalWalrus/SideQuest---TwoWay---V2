import SwiftUI

struct HabitHeatmapView: View {
    let appState: AppState
    @State private var selectedDay: Date?

    private let columns = 7
    private let weeks = 13

    private var calendar: Calendar { Calendar.current }

    private var heatmapDays: [HeatmapDay] {
        let today = calendar.startOfDay(for: Date())
        let totalDays = weeks * columns
        return (0..<totalDays).reversed().map { offset in
            let date = calendar.date(byAdding: .day, value: -offset, to: today)!
            let dayStart = calendar.startOfDay(for: date)
            let count = appState.dailyCompletions[dayStart] ?? 0
            return HeatmapDay(date: dayStart, count: count)
        }
    }

    private var maxCount: Int {
        max(heatmapDays.map(\.count).max() ?? 1, 1)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Activity")
                    .font(.headline)
                Spacer()
                HStack(spacing: 4) {
                    Text("Less")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                    ForEach(0..<5) { level in
                        RoundedRectangle(cornerRadius: 2)
                            .fill(intensityColor(for: level, max: 4))
                            .frame(width: 10, height: 10)
                    }
                    Text("More")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            }

            dayLabelsRow

            let gridColumns = Array(repeating: GridItem(.flexible(), spacing: 3), count: weeks)
            LazyVGrid(columns: gridColumns, spacing: 3) {
                ForEach(heatmapDays) { day in
                    RoundedRectangle(cornerRadius: 2)
                        .fill(dayColor(day))
                        .frame(height: 14)
                        .overlay {
                            if selectedDay == day.date {
                                RoundedRectangle(cornerRadius: 2)
                                    .stroke(.primary, lineWidth: 1.5)
                            }
                        }
                        .onTapGesture {
                            withAnimation(.snappy(duration: 0.2)) {
                                selectedDay = selectedDay == day.date ? nil : day.date
                            }
                        }
                }
            }

            if let selected = selectedDay {
                selectedDayInfo(selected)
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }

            monthLabels
        }
        .padding(16)
        .background(Color(.secondarySystemGroupedBackground), in: .rect(cornerRadius: 16))
        .animation(.snappy(duration: 0.2), value: selectedDay)
    }

    private var dayLabelsRow: some View {
        HStack(spacing: 0) {
            Spacer()
            ForEach(["M", "W", "F"], id: \.self) { label in
                Text(label)
                    .font(.system(size: 9))
                    .foregroundStyle(.tertiary)
                    .frame(maxWidth: .infinity)
            }
            Spacer()
        }
    }

    private var monthLabels: some View {
        HStack(spacing: 0) {
            let today = calendar.startOfDay(for: Date())
            let months = (0..<4).compactMap { offset -> (String, Int)? in
                guard let date = calendar.date(byAdding: .month, value: -offset, to: today) else { return nil }
                let formatter = DateFormatter()
                formatter.dateFormat = "MMM"
                return (formatter.string(from: date), offset)
            }.reversed()

            ForEach(Array(months), id: \.1) { month in
                Text(month.0)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    private func selectedDayInfo(_ date: Date) -> some View {
        let count = appState.dailyCompletions[date] ?? 0
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        return HStack(spacing: 8) {
            Image(systemName: count > 0 ? "checkmark.circle.fill" : "circle")
                .foregroundStyle(count > 0 ? .green : .secondary)
            Text(formatter.string(from: date))
                .font(.subheadline.weight(.medium))
            Spacer()
            Text("\(count) quest\(count == 1 ? "" : "s")")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(count > 0 ? .green : .secondary)
        }
        .padding(10)
        .background(Color(.tertiarySystemGroupedBackground), in: .rect(cornerRadius: 10))
    }

    private func dayColor(_ day: HeatmapDay) -> Color {
        if day.count == 0 {
            return Color(.tertiarySystemGroupedBackground)
        }
        let intensity = min(Double(day.count) / Double(max(maxCount, 1)), 1.0)
        if intensity < 0.25 { return .green.opacity(0.25) }
        if intensity < 0.5 { return .green.opacity(0.45) }
        if intensity < 0.75 { return .green.opacity(0.65) }
        return .green.opacity(0.9)
    }

    private func intensityColor(for level: Int, max: Int) -> Color {
        if level == 0 { return Color(.tertiarySystemGroupedBackground) }
        let step = Double(level) / Double(max)
        if step < 0.25 { return .green.opacity(0.25) }
        if step < 0.5 { return .green.opacity(0.45) }
        if step < 0.75 { return .green.opacity(0.65) }
        return .green.opacity(0.9)
    }
}

struct HeatmapDay: Identifiable {
    let date: Date
    let count: Int
    var id: Date { date }
}
