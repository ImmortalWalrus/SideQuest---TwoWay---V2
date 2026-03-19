import SwiftUI

struct JourneyDetailView: View {
    let journeyId: String
    let appState: AppState
    @Environment(\.dismiss) private var dismiss
    @State private var selectedTab: Int = 0
    @State private var showSettings: Bool = false
    @State private var selectedQuestItem: JourneyQuestItem?
    @State private var showStoryPlay: Bool = false

    private var journey: Journey? {
        appState.journeys.first(where: { $0.id == journeyId })
    }

    var body: some View {
        NavigationStack {
            if let journey {
                VStack(spacing: 0) {
                    journeyHeader(journey)
                    tabSelector
                    tabContent(journey)
                }
                .background(Color(.systemGroupedBackground))
                .navigationTitle(journey.name)
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Done") { dismiss() }
                    }
                    ToolbarItem(placement: .topBarTrailing) {
                        Button { showSettings = true } label: {
                            Image(systemName: "gearshape")
                        }
                    }
                }
                .sheet(isPresented: $showSettings) {
                    JourneySettingsView(journeyId: journeyId, appState: appState)
                }
                .sheet(item: $selectedQuestItem) { item in
                    if let quest = appState.allQuests.first(where: { $0.id == item.questId }) {
                        QuestDetailView(quest: quest, appState: appState)
                    }
                }
            } else {
                ContentUnavailableView("Quest Not Found", systemImage: "map")
            }
        }
    }

    private func journeyHeader(_ journey: Journey) -> some View {
        VStack(spacing: 12) {
            HStack(spacing: 16) {
                journeyRing(journey)
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 6) {
                        Image(systemName: journey.mode.icon)
                            .font(.caption)
                        Text(journey.mode.rawValue)
                            .font(.caption.weight(.medium))
                        Text("·")
                            .foregroundStyle(.tertiary)
                        Text("Day \(journey.currentDay)/\(journey.totalDays)")
                            .font(.caption.weight(.medium))
                    }
                    .foregroundStyle(.secondary)
                    Text("\(journey.daysRemaining) days remaining")
                        .font(.subheadline.weight(.semibold))
                    HStack(spacing: 10) {
                        Label("\(journey.streakDays)", systemImage: "flame.fill")
                            .font(.caption.weight(.bold))
                            .foregroundStyle(.orange)
                        Label("\(journey.questItems.count) side quests", systemImage: "scroll.fill")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        if journey.verificationMode == .nonVerified {
                            HStack(spacing: 3) {
                                Image(systemName: "hand.thumbsup.fill")
                                Text("Non-Verified")
                            }
                            .font(.caption.weight(.medium))
                            .foregroundStyle(.orange)
                        }
                    }
                }
                Spacer()
            }
        }
        .padding(16)
        .background(Color(.secondarySystemGroupedBackground))
    }

    private func journeyRing(_ journey: Journey) -> some View {
        ZStack {
            Circle()
                .stroke(.quaternary, lineWidth: 5)
            Circle()
                .trim(from: 0, to: journey.overallCompletionPercent)
                .stroke(Color.blue, style: StrokeStyle(lineWidth: 5, lineCap: .round))
                .rotationEffect(.degrees(-90))
            VStack(spacing: 0) {
                Text("\(Int(journey.overallCompletionPercent * 100))")
                    .font(.system(size: 18, weight: .bold).monospacedDigit())
                Text("%")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.secondary)
            }
        }
        .frame(width: 56, height: 56)
    }

    private var tabSelector: some View {
        HStack(spacing: 0) {
            ForEach(Array(["Today", "Week", "Campaign", "Progress", "Friends"].enumerated()), id: \.offset) { idx, title in
                let showFriends = journey?.mode == .withFriends
                if idx < 4 || showFriends {
                    Button {
                        withAnimation(.snappy) { selectedTab = idx }
                    } label: {
                        Text(title)
                            .font(.subheadline.weight(selectedTab == idx ? .bold : .medium))
                            .foregroundStyle(selectedTab == idx ? .primary : .secondary)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 10)
                            .overlay(alignment: .bottom) {
                                if selectedTab == idx {
                                    Capsule()
                                        .fill(.blue)
                                        .frame(height: 3)
                                        .padding(.horizontal, 12)
                                }
                            }
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .background(Color(.secondarySystemGroupedBackground))
    }

    @ViewBuilder
    private func tabContent(_ journey: Journey) -> some View {
        switch selectedTab {
        case 0: todayTab(journey)
        case 1: weekTab(journey)
        case 2: storyTab(journey)
        case 3: progressTab(journey)
        case 4: friendsTab(journey)
        default: EmptyView()
        }
    }

    private func storyTab(_ journey: Journey) -> some View {
        let storyProgress = appState.storyEngine.progressForJourney(journeyId)
        let hasStory = storyProgress != nil
        return ScrollView {
            VStack(spacing: 16) {
                if hasStory, let progress = storyProgress {
                    storyProgressCard(progress)
                } else {
                    storySetupCard
                }
            }
            .padding(16)
        }
        .sheet(isPresented: $showStoryPlay) {
            if let progress = appState.storyEngine.progressForJourney(journeyId) {
                StoryPlayView(appState: appState, templateId: progress.templateId, journeyId: journeyId)
            }
        }
    }

    private func storyProgressCard(_ progress: StoryProgress) -> some View {
        let template = appState.storyEngine.template(for: progress.templateId)
        return VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 12) {
                ZStack {
                    Circle()
                        .fill(.indigo.opacity(0.12))
                        .frame(width: 44, height: 44)
                    Image(systemName: template?.iconName ?? "book.pages.fill")
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(.indigo)
                }
                VStack(alignment: .leading, spacing: 3) {
                    Text(template?.title ?? "Story")
                        .font(.subheadline.weight(.bold))
                    if progress.isComplete {
                        HStack(spacing: 4) {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundStyle(.green)
                            Text("Complete — \(progress.endingReached ?? "Finished")")
                                .foregroundStyle(.green)
                        }
                        .font(.caption.weight(.medium))
                    } else {
                        Text("\(progress.decisionsMade) decisions made · \(progress.inventory.count) items")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer()
            }

            HStack(spacing: 8) {
                if progress.isEnabled || progress.isComplete {
                    Toggle(isOn: Binding(
                        get: { progress.isEnabled },
                        set: { _ in
                            appState.storyEngine.toggleStoryEnabled(progressKey: journeyId)
                            appState.saveStoryData()
                        }
                    )) {
                        Text("Story Events")
                            .font(.caption.weight(.medium))
                    }
                    .toggleStyle(.switch)
                    .tint(.indigo)
                    .disabled(progress.isComplete)
                }
            }

            Button {
                showStoryPlay = true
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: progress.isComplete ? "arrow.counterclockwise" : "play.fill")
                    Text(progress.isComplete ? "Replay Story" : "Continue Story")
                }
                .font(.subheadline.weight(.bold))
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
                .background(Color.indigo.gradient, in: Capsule())
            }
            .buttonStyle(.plain)

            if !progress.inventory.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text("ITEMS FOUND")
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(.secondary)
                        .tracking(0.5)
                    ForEach(progress.inventory.prefix(5)) { item in
                        InventoryItemRow(item: item)
                    }
                    if progress.inventory.count > 5 {
                        Text("+\(progress.inventory.count - 5) more")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .padding(16)
        .background(Color(.secondarySystemGroupedBackground), in: .rect(cornerRadius: 16))
    }

    private var storySetupCard: some View {
        VStack(spacing: 16) {
            Image(systemName: "book.pages.fill")
                .font(.system(size: 40))
                .foregroundStyle(.indigo.opacity(0.5))

            VStack(spacing: 6) {
                Text("Campaign")
                    .font(.title3.weight(.semibold))
                Text("Add an RPG storyline to this quest. Make decisions, find items, and unlock endings as you complete challenges.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }

            ForEach(SampleStoryData.allTemplates) { template in
                Button {
                    appState.startStoryForJourney(journeyId, templateId: template.id)
                } label: {
                    HStack(spacing: 12) {
                        Image(systemName: template.iconName)
                            .font(.title3)
                            .foregroundStyle(.indigo)
                            .frame(width: 36)
                        VStack(alignment: .leading, spacing: 3) {
                            Text(template.title)
                                .font(.subheadline.weight(.semibold))
                            Text(template.themeDescription)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(2)
                        }
                        Spacer()
                        VStack(spacing: 2) {
                            Text("\(template.decisionCount)")
                                .font(.caption.weight(.bold).monospacedDigit())
                            Text("choices")
                                .font(.system(size: 9))
                                .foregroundStyle(.secondary)
                        }
                    }
                    .padding(12)
                    .background(Color.indigo.opacity(0.06), in: .rect(cornerRadius: 12))
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .strokeBorder(Color.indigo.opacity(0.15), lineWidth: 1)
                    )
                }
                .buttonStyle(.plain)
            }
        }
        .padding(16)
        .background(Color(.secondarySystemGroupedBackground), in: .rect(cornerRadius: 16))
    }

    private func todayTab(_ journey: Journey) -> some View {
        let scheduled = journey.scheduledQuestsForDate(Date())
            .sorted { a, b in
                if a.isAnytime != b.isAnytime { return !a.isAnytime }
                return (a.scheduledHour ?? 99) < (b.scheduledHour ?? 99)
            }

        return ScrollView {
            if journey.verificationMode == .nonVerified {
                HStack(spacing: 8) {
                    Image(systemName: "info.circle.fill")
                        .foregroundStyle(.orange)
                    Text("Non-verified mode — reduced XP & coins, no diamonds")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.secondary)
                }
                .padding(10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(.orange.opacity(0.08), in: .rect(cornerRadius: 10))
                .padding(.horizontal, 16)
                .padding(.top, 8)
            }

            if scheduled.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "checkmark.circle")
                        .font(.system(size: 40))
                        .foregroundStyle(.green.opacity(0.5))
                    Text("No tasks scheduled for today")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 60)
            } else {
                LazyVStack(spacing: 8) {
                    ForEach(scheduled) { item in
                        let quest = appState.allQuests.first(where: { $0.id == item.questId })
                        let status = journey.questStatusForDate(item.id, date: Date())
                        JourneyTodayQuestRow(
                            item: item,
                            quest: quest,
                            status: status,
                            verificationMode: journey.verificationMode,
                            onTap: { selectedQuestItem = item },
                            onComplete: {
                                if journey.verificationMode == .nonVerified, let quest {
                                    appState.completeJourneyQuestNonVerified(
                                        journeyId: journeyId,
                                        questItemId: item.id,
                                        quest: quest
                                    )
                                } else {
                                    let newStatus: JourneyQuestStatus = quest?.type == .verified ? .completed : .verified
                                    appState.updateJourneyQuestStatus(
                                        journeyId: journeyId,
                                        questItemId: item.id,
                                        date: Date(),
                                        status: newStatus
                                    )
                                }
                            }
                        )
                    }
                }
                .padding(16)
            }
        }
    }

    private func weekTab(_ journey: Journey) -> some View {
        let cal = Calendar.current
        let today = cal.startOfDay(for: Date())
        let weekStart = cal.date(from: cal.dateComponents([.yearForWeekOfYear, .weekOfYear], from: today)) ?? today
        let dates: [Date] = (0..<7).map { cal.date(byAdding: .day, value: $0, to: weekStart) ?? today }

        return ScrollView {
            LazyVStack(spacing: 8) {
                ForEach(Array(dates.enumerated()), id: \.offset) { _, date in
                    WeekDayRow(journey: journey, date: date, quests: appState.allQuests)
                }
            }
            .padding(16)
        }
    }

    private func progressTab(_ journey: Journey) -> some View {
        ScrollView {
            VStack(spacing: 16) {
                HStack(spacing: 16) {
                    progressStat(
                        value: "\(Int(journey.overallCompletionPercent * 100))%",
                        label: "Completion",
                        icon: "chart.pie.fill",
                        color: .blue
                    )
                    progressStat(
                        value: "\(journey.streakDays)",
                        label: "Streak",
                        icon: "flame.fill",
                        color: .orange
                    )
                    progressStat(
                        value: "\(journey.dayProgress.filter { $0.completionPercent >= 1.0 }.count)",
                        label: "Perfect Days",
                        icon: "star.fill",
                        color: .yellow
                    )
                }

                VStack(alignment: .leading, spacing: 8) {
                    Text("COMPLETED SIDE QUESTS")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)

                    let completed = journey.dayProgress.flatMap { dp in
                        dp.questStatuses.filter { $0.value == .completed || $0.value == .verified }
                            .map { (questItemId: $0.key, date: dp.date) }
                    }

                    if completed.isEmpty {
                        Text("No side quests completed yet")
                            .font(.subheadline)
                            .foregroundStyle(.tertiary)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 20)
                    } else {
                        ForEach(completed.prefix(20), id: \.questItemId) { entry in
                            let item = journey.questItems.first(where: { $0.id == entry.questItemId })
                            let quest = item.flatMap { i in appState.allQuests.first(where: { $0.id == i.questId }) }
                            HStack(spacing: 10) {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundStyle(.green)
                                    .font(.caption)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(quest?.title ?? "Unknown")
                                        .font(.subheadline)
                                    Text(entry.date.formatted(date: .abbreviated, time: .omitted))
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                Spacer()
                            }
                            .padding(.vertical, 4)
                        }
                    }
                }
                .padding(14)
                .background(Color(.secondarySystemGroupedBackground), in: .rect(cornerRadius: 14))
            }
            .padding(16)
        }
    }

    private func progressStat(value: String, label: String, icon: String, color: Color) -> some View {
        VStack(spacing: 6) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundStyle(color)
            Text(value)
                .font(.title3.weight(.bold).monospacedDigit())
            Text(label)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 14)
        .background(Color(.secondarySystemGroupedBackground), in: .rect(cornerRadius: 14))
    }

    @ViewBuilder
    private func friendsTab(_ journey: Journey) -> some View {
        ScrollView {
            LazyVStack(spacing: 8) {
                if journey.friendProgress.isEmpty {
                    VStack(spacing: 8) {
                        Image(systemName: "person.2")
                            .font(.system(size: 36))
                            .foregroundStyle(.tertiary)
                        Text("No friends in this quest")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 40)
                } else {
                    ForEach(journey.friendProgress) { fp in
                        HStack(spacing: 12) {
                            Image(systemName: fp.avatarName)
                                .font(.title3)
                                .frame(width: 40, height: 40)
                                .background(Color(.tertiarySystemGroupedBackground), in: Circle())
                            VStack(alignment: .leading, spacing: 4) {
                                Text(fp.username)
                                    .font(.subheadline.weight(.semibold))
                                HStack(spacing: 6) {
                                    Text("Today: \(fp.todayCompleted)/\(fp.todayTotal)")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                    Text("·")
                                        .foregroundStyle(.tertiary)
                                    Text("\(Int(fp.overallPercent * 100))% overall")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                            Spacer()
                            Button {
                                appState.nudgeFriend(journeyId: journeyId, friendId: fp.friendId)
                            } label: {
                                Text("Nudge")
                                    .font(.caption.weight(.semibold))
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 5)
                                    .background(.blue, in: Capsule())
                                    .foregroundStyle(.white)
                            }
                            .buttonStyle(.plain)
                        }
                        .padding(12)
                        .background(Color(.secondarySystemGroupedBackground), in: .rect(cornerRadius: 12))
                    }
                }
            }
            .padding(16)
        }
    }
}

struct WeekDayRow: View {
    let journey: Journey
    let date: Date
    let quests: [Quest]

    private var scheduled: [JourneyQuestItem] {
        journey.scheduledQuestsForDate(date)
    }

    private var dayProgress: JourneyDayProgress? {
        let cal = Calendar.current
        return journey.dayProgress.first(where: { cal.isDate($0.date, inSameDayAs: date) })
    }

    private var isToday: Bool {
        Calendar.current.isDateInToday(date)
    }

    private var completionPct: Double {
        dayProgress?.completionPercent ?? 0
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            headerRow
            if !scheduled.isEmpty {
                ProgressView(value: completionPct)
                    .tint(completionPct >= 1.0 ? Color.green : Color.blue)
            }
            ForEach(scheduled) { item in
                questRow(item)
            }
        }
        .padding(12)
        .background(
            isToday ? Color.blue.opacity(0.05) : Color(.secondarySystemGroupedBackground),
            in: .rect(cornerRadius: 12)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .strokeBorder(isToday ? Color.blue.opacity(0.2) : .clear, lineWidth: 1)
        )
    }

    private var headerRow: some View {
        HStack {
            Text(date.formatted(.dateTime.weekday(.wide)))
                .font(.subheadline.weight(isToday ? .bold : .medium))
            if isToday {
                Text("TODAY")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(.blue, in: Capsule())
            }
            Spacer()
            let completed = dayProgress?.completedCount ?? 0
            Text("\(completed)/\(scheduled.count)")
                .font(.caption.weight(.bold).monospacedDigit())
                .foregroundStyle(completionPct >= 1.0 ? Color.green : Color.secondary)
        }
    }

    private func questRow(_ item: JourneyQuestItem) -> some View {
        let quest = quests.first(where: { $0.id == item.questId })
        let itemStatus = journey.questStatusForDate(item.id, date: date)
        let isDone = itemStatus == .verified || itemStatus == .completed
        return HStack(spacing: 8) {
            Image(systemName: isDone ? "checkmark.circle.fill" : "circle")
                .font(.caption)
                .foregroundStyle(isDone ? Color.green : Color.secondary.opacity(0.5))
            Text(quest?.title ?? "Unknown")
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
            Spacer()
            Text(item.timeDescription)
                .font(.caption2)
                .foregroundStyle(.secondary.opacity(0.6))
        }
    }
}

struct JourneyTodayQuestRow: View {
    let item: JourneyQuestItem
    let quest: Quest?
    let status: JourneyQuestStatus
    var verificationMode: JourneyVerificationMode = .verified
    let onTap: () -> Void
    let onComplete: () -> Void

    private var statusColor: Color {
        switch status {
        case .notStarted: .secondary
        case .active: .orange
        case .completed: .green
        case .verified: .blue
        case .skipped: .gray
        }
    }

    private var statusIcon: String {
        switch status {
        case .notStarted: "circle"
        case .active: "circle.inset.filled"
        case .completed: "checkmark.circle.fill"
        case .verified: "checkmark.seal.fill"
        case .skipped: "minus.circle"
        }
    }

    var body: some View {
        HStack(spacing: 12) {
            if let quest {
                RoundedRectangle(cornerRadius: 3)
                    .fill(PathColorHelper.color(for: quest.path).gradient)
                    .frame(width: 4)
            }

            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 8) {
                    Text(item.timeDescription)
                        .font(.caption.weight(.bold).monospacedDigit())
                        .foregroundStyle(item.isAnytime ? .secondary : .primary)

                    if let quest {
                        if quest.type == .verified {
                            Image(systemName: "checkmark.seal.fill")
                                .font(.system(size: 10))
                                .foregroundStyle(.blue)
                        } else {
                            Text("i")
                                .font(.system(size: 9, weight: .bold))
                                .foregroundStyle(.indigo)
                                .padding(.horizontal, 4)
                                .padding(.vertical, 1)
                                .background(.indigo.opacity(0.12), in: .rect(cornerRadius: 3))
                        }
                    }
                    Spacer()
                    Image(systemName: statusIcon)
                        .foregroundStyle(statusColor)
                        .font(.body)
                }

                Button(action: onTap) {
                    Text(quest?.title ?? "Unknown Side Quest")
                        .font(.subheadline.weight(.semibold))
                        .lineLimit(1)
                }
                .buttonStyle(.plain)

                if status == .notStarted || status == .active {
                    if verificationMode == .nonVerified && quest?.type == .verified {
                        VStack(alignment: .leading, spacing: 4) {
                            Button(action: onComplete) {
                                HStack(spacing: 4) {
                                    Image(systemName: "hand.thumbsup.fill")
                                        .font(.caption2.weight(.bold))
                                    Text("Mark Done")
                                        .font(.caption.weight(.semibold))
                                }
                                .padding(.horizontal, 10)
                                .padding(.vertical, 5)
                                .background(Color.orange, in: Capsule())
                                .foregroundStyle(.white)
                            }
                            .buttonStyle(.plain)
                            Text("No evidence needed · reduced rewards")
                                .font(.system(size: 9))
                                .foregroundStyle(.orange.opacity(0.8))
                        }
                    } else {
                        Button(action: onComplete) {
                            HStack(spacing: 4) {
                                Image(systemName: "checkmark")
                                    .font(.caption2.weight(.bold))
                                Text(quest?.type == .verified ? "Submit Evidence" : "Mark Complete")
                                    .font(.caption.weight(.semibold))
                            }
                            .padding(.horizontal, 10)
                            .padding(.vertical, 5)
                            .background(Color.green, in: Capsule())
                            .foregroundStyle(.white)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
        .padding(12)
        .background(Color(.secondarySystemGroupedBackground), in: .rect(cornerRadius: 12))
    }
}

struct JourneySettingsView: View {
    let journeyId: String
    let appState: AppState
    @Environment(\.dismiss) private var dismiss
    @State private var journeyName: String = ""
    @State private var showEndConfirm: Bool = false
    @State private var showPublish: Bool = false
    @State private var publishTitle: String = ""
    @State private var publishDescription: String = ""
    @State private var publishDifficulty: QuestDifficulty = .medium

    private var journey: Journey? {
        appState.journeys.first(where: { $0.id == journeyId })
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Name") {
                    TextField("Quest Name", text: $journeyName)
                        .onAppear { journeyName = journey?.name ?? "" }
                    Button("Save") {
                        appState.renameJourney(journeyId: journeyId, newName: journeyName)
                    }
                    .disabled(journeyName.trimmingCharacters(in: .whitespaces).isEmpty)
                }

                Section("Calendar") {
                    Toggle("Calendar Sync", isOn: Binding(
                        get: { journey?.calendarSyncEnabled ?? false },
                        set: { appState.toggleJourneyCalendarSync(journeyId: journeyId, enabled: $0) }
                    ))
                }

                if journey?.mode == .withFriends {
                    Section("Friends") {
                        ForEach(journey?.friendProgress ?? []) { fp in
                            HStack {
                                Image(systemName: fp.avatarName)
                                Text(fp.username)
                                Spacer()
                                Text("\(Int(fp.overallPercent * 100))%")
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }

                Section("Publish") {
                    if journey?.visibility == .publicTemplate {
                        Label("Published", systemImage: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                    } else {
                        Button("Publish as Template") {
                            publishTitle = journey?.name ?? ""
                            showPublish = true
                        }
                    }
                }

                Section {
                    Button("End Quest Early", role: .destructive) {
                        showEndConfirm = true
                    }
                    .confirmationDialog("End Quest?", isPresented: $showEndConfirm, titleVisibility: .visible) {
                        Button("End Quest", role: .destructive) {
                            appState.endJourneyEarly(journeyId: journeyId)
                            dismiss()
                        }
                        Button("Cancel", role: .cancel) {}
                    } message: {
                        Text("This will cancel the quest. Your progress so far will be saved.")
                    }
                }
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .sheet(isPresented: $showPublish) {
                NavigationStack {
                    Form {
                        TextField("Title", text: $publishTitle)
                        TextField("Description", text: $publishDescription, axis: .vertical)
                            .lineLimit(3...6)
                        Picker("Difficulty", selection: $publishDifficulty) {
                            ForEach(QuestDifficulty.allCases, id: \.self) { d in
                                Text(d.rawValue).tag(d)
                            }
                        }
                    }
                    .navigationTitle("Publish Template")
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) {
                            Button("Cancel") { showPublish = false }
                        }
                        ToolbarItem(placement: .confirmationAction) {
                            Button("Publish") {
                                appState.publishJourneyAsTemplate(
                                    journeyId: journeyId,
                                    title: publishTitle,
                                    description: publishDescription,
                                    difficulty: publishDifficulty
                                )
                                showPublish = false
                            }
                            .disabled(publishTitle.isEmpty)
                        }
                    }
                }
            }
        }
    }
}
