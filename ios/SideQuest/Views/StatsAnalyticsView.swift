import SwiftUI

struct StatsAnalyticsView: View {
    let appState: AppState
    @State private var selectedPeriod: StatsPeriod = .week

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    periodPicker
                    xpChartSection
                    questBreakdownSection
                    pathDistributionSection
                    streakInsightSection
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 20)
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("Stats")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {}
                }
            }
        }
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
    }

    private var periodPicker: some View {
        Picker("Period", selection: $selectedPeriod) {
            ForEach(StatsPeriod.allCases) { period in
                Text(period.label).tag(period)
            }
        }
        .pickerStyle(.segmented)
    }

    private var xpChartSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("XP Earned")
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(.secondary)
                    Text("\(totalXPForPeriod.formatted())")
                        .font(.title.weight(.bold))
                        .foregroundStyle(.orange)
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 2) {
                    Text("Quests")
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(.secondary)
                    Text("\(totalQuestsForPeriod)")
                        .font(.title.weight(.bold))
                }
            }

            barChart
        }
        .padding(16)
        .background(Color(.secondarySystemGroupedBackground), in: .rect(cornerRadius: 16))
    }

    private var barChart: some View {
        let data = chartData
        let maxVal = max(data.map(\.value).max() ?? 1, 1)
        return VStack(spacing: 8) {
            HStack(alignment: .bottom, spacing: selectedPeriod == .month ? 2 : 4) {
                ForEach(data) { item in
                    VStack(spacing: 4) {
                        RoundedRectangle(cornerRadius: 3)
                            .fill(item.isToday ? Color.orange : Color.orange.opacity(0.3))
                            .frame(height: max(4, CGFloat(item.value) / CGFloat(maxVal) * 120))
                    }
                    .frame(maxWidth: .infinity)
                }
            }
            .frame(height: 120)

            HStack(spacing: 0) {
                ForEach(labelIndices(for: data), id: \.self) { idx in
                    if idx < data.count {
                        Text(data[idx].label)
                            .font(.system(size: 9))
                            .foregroundStyle(.tertiary)
                            .frame(maxWidth: .infinity)
                    }
                }
            }
        }
    }

    private var questBreakdownSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Quest Breakdown")
                .font(.headline)

            HStack(spacing: 12) {
                breakdownTile(
                    icon: "checkmark.seal.fill",
                    value: "\(verifiedForPeriod)",
                    label: "Verified",
                    color: .blue
                )
                breakdownTile(
                    icon: "brain.fill",
                    value: "\(brainForPeriod)",
                    label: "Brain Games",
                    color: .indigo
                )
                breakdownTile(
                    icon: "flame.fill",
                    value: "\(averageXPPerDay)",
                    label: "XP/Day",
                    color: .orange
                )
            }
        }
        .padding(16)
        .background(Color(.secondarySystemGroupedBackground), in: .rect(cornerRadius: 16))
    }

    private func breakdownTile(icon: String, value: String, label: String, color: Color) -> some View {
        VStack(spacing: 6) {
            Image(systemName: icon)
                .font(.title2)
                .foregroundStyle(color)
            Text(value)
                .font(.title3.weight(.bold).monospacedDigit())
            Text(label)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
        .background(color.opacity(0.08), in: .rect(cornerRadius: 12))
    }

    private var pathDistributionSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Path Distribution")
                .font(.headline)

            let dist = pathDistribution
            let total = max(dist.values.reduce(0, +), 1)

            ForEach(QuestPath.allCases) { path in
                let count = dist[path] ?? 0
                let pct = Double(count) / Double(total)
                HStack(spacing: 10) {
                    Image(systemName: path.iconName)
                        .font(.body)
                        .foregroundStyle(PathColorHelper.color(for: path))
                        .frame(width: 28)
                    Text(path.rawValue)
                        .font(.subheadline.weight(.medium))
                    Spacer()
                    Text("\(count)")
                        .font(.subheadline.weight(.bold).monospacedDigit())
                        .foregroundStyle(.secondary)
                }

                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule()
                            .fill(Color(.tertiarySystemGroupedBackground))
                        Capsule()
                            .fill(PathColorHelper.color(for: path).gradient)
                            .frame(width: max(4, geo.size.width * pct))
                    }
                }
                .frame(height: 6)
                .clipShape(Capsule())
            }
        }
        .padding(16)
        .background(Color(.secondarySystemGroupedBackground), in: .rect(cornerRadius: 16))
    }

    private var streakInsightSection: some View {
        HStack(spacing: 12) {
            VStack(spacing: 4) {
                Image(systemName: "flame.fill")
                    .font(.title)
                    .foregroundStyle(.orange)
                Text("\(appState.profile.currentStreak)")
                    .font(.title.weight(.bold).monospacedDigit())
                Text("Day Streak")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
            .background(Color.orange.opacity(0.08), in: .rect(cornerRadius: 14))

            VStack(spacing: 4) {
                Image(systemName: "calendar.badge.checkmark")
                    .font(.title)
                    .foregroundStyle(.green)
                Text("\(activeDaysInPeriod)")
                    .font(.title.weight(.bold).monospacedDigit())
                Text("Active Days")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
            .background(Color.green.opacity(0.08), in: .rect(cornerRadius: 14))

            VStack(spacing: 4) {
                Image(systemName: "trophy.fill")
                    .font(.title)
                    .foregroundStyle(.yellow)
                Text("\(appState.profile.earnedBadges.count)")
                    .font(.title.weight(.bold).monospacedDigit())
                Text("Badges")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
            .background(Color.yellow.opacity(0.08), in: .rect(cornerRadius: 14))
        }
    }

    private var periodDays: Int {
        switch selectedPeriod {
        case .week: 7
        case .month: 30
        case .allTime: 90
        }
    }

    private var eventsInPeriod: [RewardEvent] {
        let cutoff = Calendar.current.date(byAdding: .day, value: -periodDays, to: Date()) ?? Date()
        return selectedPeriod == .allTime
            ? appState.completedHistory
            : appState.completedHistory.filter { $0.createdAt >= cutoff }
    }

    private var totalXPForPeriod: Int {
        eventsInPeriod.reduce(0) { $0 + $1.xpEarned }
    }

    private var totalQuestsForPeriod: Int {
        eventsInPeriod.count
    }

    private var verifiedForPeriod: Int {
        eventsInPeriod.filter { !$0.questTitle.contains("Memory") && !$0.questTitle.contains("Math") && !$0.questTitle.contains("Word") && !$0.questTitle.contains("Chess") }.count
    }

    private var brainForPeriod: Int {
        eventsInPeriod.count - verifiedForPeriod
    }

    private var averageXPPerDay: Int {
        let days = max(activeDaysInPeriod, 1)
        return totalXPForPeriod / days
    }

    private var activeDaysInPeriod: Int {
        let cal = Calendar.current
        let cutoff = cal.date(byAdding: .day, value: -periodDays, to: Date()) ?? Date()
        let activeDates = Set(eventsInPeriod.map { cal.startOfDay(for: $0.createdAt) })
        if selectedPeriod == .allTime {
            return appState.dailyCompletions.count
        }
        return activeDates.filter { $0 >= cutoff }.count
    }

    private var pathDistribution: [QuestPath: Int] {
        var result: [QuestPath: Int] = [.warrior: 0, .explorer: 0, .mind: 0]
        for event in eventsInPeriod {
            if let quest = appState.allQuests.first(where: { $0.title == event.questTitle }) {
                result[quest.path, default: 0] += 1
            } else if event.questTitle.contains("Chess") || event.questTitle.contains("Memory") || event.questTitle.contains("Math") || event.questTitle.contains("Word") {
                result[.mind, default: 0] += 1
            }
        }
        return result
    }

    private struct ChartItem: Identifiable {
        let id: String
        let label: String
        let value: Int
        let isToday: Bool
    }

    private var chartData: [ChartItem] {
        let cal = Calendar.current
        let today = cal.startOfDay(for: Date())
        let days = periodDays
        let formatter = DateFormatter()

        return (0..<days).map { offset in
            let day = cal.date(byAdding: .day, value: -(days - 1 - offset), to: today)!
            let dayStart = cal.startOfDay(for: day)
            let xp = eventsInPeriod
                .filter { cal.isDate($0.createdAt, inSameDayAs: dayStart) }
                .reduce(0) { $0 + $1.xpEarned }

            formatter.dateFormat = selectedPeriod == .month ? "d" : "EEE"
            let label = formatter.string(from: day)
            let isToday = cal.isDateInToday(day)

            return ChartItem(id: "\(offset)", label: label, value: xp, isToday: isToday)
        }
    }

    private func labelIndices(for data: [ChartItem]) -> [Int] {
        switch selectedPeriod {
        case .week:
            return Array(0..<data.count)
        case .month:
            return stride(from: 0, to: data.count, by: 5).map { $0 }
        case .allTime:
            return stride(from: 0, to: data.count, by: 15).map { $0 }
        }
    }
}

enum StatsPeriod: String, CaseIterable, Identifiable {
    case week = "Week"
    case month = "Month"
    case allTime = "All Time"

    var id: String { rawValue }

    var label: String { rawValue }
}
