import SwiftUI

struct CreateJourneyView: View {
    let appState: AppState
    @Environment(\.dismiss) private var dismiss
    @State private var step: Int = 0
    @State private var journeyName: String = ""
    @State private var durationType: JourneyDurationType = .sevenDays
    @State private var startDate: Date = Date()
    @State private var endDate: Date = Calendar.current.date(byAdding: .day, value: 6, to: Date()) ?? Date()
    @State private var mode: JourneyMode = .solo
    @State private var visibility: JourneyVisibility = .privateJourney
    @State private var questItems: [JourneyQuestItem] = []
    @State private var calendarSync: Bool = false
    @State private var calendarAlert: CalendarAlertOption = .fifteenMin
    @State private var invitedFriendIds: [String] = []
    @State private var verificationMode: JourneyVerificationMode = .verified
    @State private var showQuestPicker: Bool = false
    @State private var editingItemId: String?
    @State private var showCreateCustom: Bool = false

    private let steps = ["Basics", "Quests", "Calendar", "Review"]

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                stepIndicator
                TabView(selection: $step) {
                    basicsStep.tag(0)
                    questsStep.tag(1)
                    calendarStep.tag(2)
                    reviewStep.tag(3)
                }
                .tabViewStyle(.page(indexDisplayMode: .never))
                .animation(.snappy, value: step)
                bottomButtons
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("Create Quest")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
            .sheet(isPresented: $showQuestPicker) {
                JourneyQuestPickerSheet(
                    allQuests: appState.allQuests,
                    existingQuestIds: Set(questItems.map(\.questId)),
                    onAdd: { quest in
                        addQuestItem(quest)
                    },
                    customQuests: appState.customQuests,
                    onCreateCustomQuest: { showCreateCustom = true }
                )
            }
            .sheet(isPresented: $showCreateCustom) {
                CreateCustomQuestView(appState: appState)
            }
        }
    }

    private var stepIndicator: some View {
        HStack(spacing: 4) {
            ForEach(0..<steps.count, id: \.self) { i in
                VStack(spacing: 4) {
                    Capsule()
                        .fill(i <= step ? Color.blue : Color(.tertiarySystemFill))
                        .frame(height: 3)
                    Text(steps[i])
                        .font(.system(size: 10, weight: i == step ? .bold : .medium))
                        .foregroundStyle(i == step ? .primary : .tertiary)
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 8)
        .padding(.bottom, 4)
    }

    private var basicsStep: some View {
        ScrollView {
            VStack(spacing: 20) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Quest Name")
                        .font(.subheadline.weight(.semibold))
                    TextField("e.g. Morning Warrior Week", text: $journeyName)
                        .textFieldStyle(.roundedBorder)
                }

                VStack(alignment: .leading, spacing: 8) {
                    Text("Duration")
                        .font(.subheadline.weight(.semibold))
                    Picker("Duration", selection: $durationType) {
                        ForEach(JourneyDurationType.allCases, id: \.self) { type in
                            Text(type.rawValue).tag(type)
                        }
                    }
                    .pickerStyle(.segmented)

                    if durationType == .custom {
                        DatePicker("Start", selection: $startDate, displayedComponents: .date)
                        DatePicker("End", selection: $endDate, in: startDate..., displayedComponents: .date)
                    }
                }

                VStack(alignment: .leading, spacing: 8) {
                    Text("Mode")
                        .font(.subheadline.weight(.semibold))
                    HStack(spacing: 12) {
                        ForEach(JourneyMode.allCases, id: \.self) { m in
                            Button {
                                mode = m
                            } label: {
                                HStack(spacing: 6) {
                                    Image(systemName: m.icon)
                                    Text(m.rawValue)
                                }
                                .font(.subheadline.weight(.medium))
                                .padding(.horizontal, 16)
                                .padding(.vertical, 10)
                                .frame(maxWidth: .infinity)
                                .background(mode == m ? Color.blue : Color(.tertiarySystemGroupedBackground), in: .rect(cornerRadius: 10))
                                .foregroundStyle(mode == m ? .white : .primary)
                            }
                            .buttonStyle(.plain)
                        }
                    }

                    if mode == .withFriends {
                        friendSelector
                    }
                }

                VStack(alignment: .leading, spacing: 10) {
                    Text("Verification Mode")
                        .font(.subheadline.weight(.semibold))
                    HStack(spacing: 12) {
                        ForEach(JourneyVerificationMode.allCases, id: \.self) { vm in
                            Button {
                                verificationMode = vm
                            } label: {
                                HStack(spacing: 6) {
                                    Image(systemName: vm.icon)
                                    Text(vm.rawValue)
                                }
                                .font(.subheadline.weight(.medium))
                                .padding(.horizontal, 16)
                                .padding(.vertical, 10)
                                .frame(maxWidth: .infinity)
                                .background(verificationMode == vm ? (vm == .verified ? Color.blue : Color.orange) : Color(.tertiarySystemGroupedBackground), in: .rect(cornerRadius: 10))
                                .foregroundStyle(verificationMode == vm ? .white : .primary)
                            }
                            .buttonStyle(.plain)
                        }
                    }

                    if verificationMode == .nonVerified {
                        HStack(alignment: .top, spacing: 8) {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .foregroundStyle(.orange)
                                .font(.caption)
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Reduced Rewards")
                                    .font(.caption.weight(.bold))
                                    .foregroundStyle(.orange)
                                Text("Verified side quests won't require evidence, but XP and coins are capped at open play levels. No diamonds will be awarded.")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .padding(10)
                        .background(.orange.opacity(0.08), in: .rect(cornerRadius: 10))
                    }
                }

                VStack(alignment: .leading, spacing: 8) {
                    Text("Visibility")
                        .font(.subheadline.weight(.semibold))
                    HStack(spacing: 12) {
                        ForEach(JourneyVisibility.allCases, id: \.self) { v in
                            Button {
                                visibility = v
                            } label: {
                                HStack(spacing: 6) {
                                    Image(systemName: v.icon)
                                    Text(v.rawValue)
                                }
                                .font(.subheadline.weight(.medium))
                                .padding(.horizontal, 16)
                                .padding(.vertical, 10)
                                .frame(maxWidth: .infinity)
                                .background(visibility == v ? Color.blue : Color(.tertiarySystemGroupedBackground), in: .rect(cornerRadius: 10))
                                .foregroundStyle(visibility == v ? .white : .primary)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
            .padding(16)
        }
    }

    private var friendSelector: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Invite Friends")
                .font(.caption.weight(.medium))
                .foregroundStyle(.secondary)
            ForEach(appState.acceptedFriends) { friend in
                Button {
                    if invitedFriendIds.contains(friend.id) {
                        invitedFriendIds.removeAll { $0 == friend.id }
                    } else {
                        invitedFriendIds.append(friend.id)
                    }
                } label: {
                    HStack(spacing: 10) {
                        Image(systemName: friend.avatarName)
                            .font(.title3)
                            .frame(width: 36, height: 36)
                            .background(Color(.tertiarySystemGroupedBackground), in: Circle())
                        Text(friend.username)
                            .font(.subheadline)
                        Spacer()
                        Image(systemName: invitedFriendIds.contains(friend.id) ? "checkmark.circle.fill" : "circle")
                            .foregroundStyle(invitedFriendIds.contains(friend.id) ? Color.blue : Color.secondary)
                    }
                    .padding(.vertical, 4)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(12)
        .background(Color(.tertiarySystemGroupedBackground), in: .rect(cornerRadius: 12))
    }

    private var questsStep: some View {
        ScrollView {
            VStack(spacing: 12) {
                Button { showQuestPicker = true } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "plus.circle.fill")
                        Text("Add Side Quest")
                            .font(.subheadline.weight(.semibold))
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(Color(.tertiarySystemGroupedBackground), in: .rect(cornerRadius: 12))
                }
                .buttonStyle(.plain)

                if questItems.isEmpty {
                    VStack(spacing: 8) {
                        Image(systemName: "scroll.fill")
                            .font(.largeTitle)
                            .foregroundStyle(.tertiary)
                        Text("No side quests added yet")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                        Text("Add side quests from the library to schedule them in your quest.")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                            .multilineTextAlignment(.center)
                    }
                    .padding(.vertical, 40)
                } else {
                    ForEach(questItems) { item in
                        JourneyQuestItemEditor(
                            item: binding(for: item),
                            quest: appState.allQuests.first(where: { $0.id == item.questId }),
                            onRemove: { questItems.removeAll { $0.id == item.id } }
                        )
                    }
                }
            }
            .padding(16)
        }
    }

    private func binding(for item: JourneyQuestItem) -> Binding<JourneyQuestItem> {
        guard let idx = questItems.firstIndex(where: { $0.id == item.id }) else {
            return .constant(item)
        }
        return $questItems[idx]
    }

    private var calendarStep: some View {
        ScrollView {
            VStack(spacing: 20) {
                VStack(alignment: .leading, spacing: 12) {
                    Toggle(isOn: $calendarSync) {
                        HStack(spacing: 10) {
                            Image(systemName: "calendar.badge.plus")
                                .font(.title3)
                                .foregroundStyle(.blue)
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Add to Calendar")
                                    .font(.subheadline.weight(.semibold))
                                Text("Create events for scheduled quests")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                    .tint(.blue)
                }
                .padding(14)
                .background(Color(.secondarySystemGroupedBackground), in: .rect(cornerRadius: 14))

                if calendarSync {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Alert")
                            .font(.subheadline.weight(.semibold))
                        Picker("Alert", selection: $calendarAlert) {
                            ForEach(CalendarAlertOption.allCases, id: \.self) { option in
                                Text(option.rawValue).tag(option)
                            }
                        }
                        .pickerStyle(.segmented)

                        HStack(spacing: 8) {
                            Image(systemName: "info.circle.fill")
                                .foregroundStyle(.blue)
                            Text("Only quests with a specific time will create calendar events. \"Anytime\" tasks won't.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        .padding(10)
                        .background(Color(.tertiarySystemGroupedBackground), in: .rect(cornerRadius: 10))
                    }
                    .padding(14)
                    .background(Color(.secondarySystemGroupedBackground), in: .rect(cornerRadius: 14))
                }

                HStack(spacing: 8) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                    Text("Calendar events are reminders only. Completion is tracked in-app.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding(10)
                .background(.orange.opacity(0.08), in: .rect(cornerRadius: 10))
            }
            .padding(16)
        }
    }

    private var reviewStep: some View {
        ScrollView {
            VStack(spacing: 16) {
                VStack(alignment: .leading, spacing: 12) {
                    Text("SUMMARY")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)

                    reviewRow(icon: "textformat", label: "Name", value: journeyName.isEmpty ? "Untitled" : journeyName)
                    reviewRow(icon: "calendar", label: "Duration", value: durationDescription)
                    reviewRow(icon: "person.fill", label: "Mode", value: mode.rawValue)
                    reviewRow(icon: "scroll.fill", label: "Quests", value: "\(questItems.count)")
                    reviewRow(icon: verificationMode.icon, label: "Verification", value: verificationMode.rawValue)
                    reviewRow(icon: "calendar.badge.plus", label: "Calendar Sync", value: calendarSync ? "On (\(calendarAlert.rawValue))" : "Off")
                    if mode == .withFriends {
                        reviewRow(icon: "person.2.fill", label: "Friends", value: "\(invitedFriendIds.count) invited")
                    }

                    let dailyEstimate = estimatedDailyTasks
                    reviewRow(icon: "clock.fill", label: "Est. Daily Tasks", value: "\(dailyEstimate)")
                }
                .padding(14)
                .background(Color(.secondarySystemGroupedBackground), in: .rect(cornerRadius: 14))

                if !questItems.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("SIDE QUEST SCHEDULE")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)

                        ForEach(questItems) { item in
                            let quest = appState.allQuests.first(where: { $0.id == item.questId })
                            HStack(spacing: 10) {
                                if let q = quest {
                                    Image(systemName: q.path.iconName)
                                        .font(.caption)
                                        .foregroundStyle(PathColorHelper.color(for: q.path))
                                }
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(quest?.title ?? "Unknown")
                                        .font(.subheadline.weight(.medium))
                                    Text("\(item.frequency.rawValue) · \(item.timeDescription)")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                Spacer()
                            }
                            .padding(.vertical, 4)
                        }
                    }
                    .padding(14)
                    .background(Color(.secondarySystemGroupedBackground), in: .rect(cornerRadius: 14))
                }
            }
            .padding(16)
        }
    }

    private func reviewRow(icon: String, label: String, value: String) -> some View {
        HStack {
            Label(label, systemImage: icon)
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Spacer()
            Text(value)
                .font(.subheadline.weight(.medium))
        }
    }

    private var durationDescription: String {
        switch durationType {
        case .oneDay: return "1 Day"
        case .sevenDays: return "7 Days"
        case .custom:
            let cal = Calendar.current
            let days = (cal.dateComponents([.day], from: startDate, to: endDate).day ?? 0) + 1
            return "\(days) Days"
        }
    }

    private var estimatedDailyTasks: Int {
        questItems.filter { $0.frequency == .daily }.count +
        questItems.filter { $0.frequency == .specificDays }.count / 2 +
        (questItems.contains(where: { $0.frequency == .oneTime }) ? 1 : 0)
    }

    private var computedEndDate: Date {
        let cal = Calendar.current
        switch durationType {
        case .oneDay: return startDate
        case .sevenDays: return cal.date(byAdding: .day, value: 6, to: startDate) ?? startDate
        case .custom: return endDate
        }
    }

    private var canCreate: Bool {
        !journeyName.trimmingCharacters(in: .whitespaces).isEmpty && !questItems.isEmpty
    }

    private var bottomButtons: some View {
        HStack(spacing: 12) {
            if step > 0 {
                Button {
                    withAnimation { step -= 1 }
                } label: {
                    Text("Back")
                        .font(.subheadline.weight(.semibold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .background(Color(.tertiarySystemGroupedBackground), in: .rect(cornerRadius: 12))
                }
                .buttonStyle(.plain)
            }

            if step < 3 {
                Button {
                    withAnimation { step += 1 }
                } label: {
                    Text("Next")
                        .font(.subheadline.weight(.semibold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .background(.blue, in: .rect(cornerRadius: 12))
                        .foregroundStyle(.white)
                }
                .buttonStyle(.plain)
            } else {
                Button {
                    createJourney()
                } label: {
                    Text("Create Quest")
                        .font(.subheadline.weight(.semibold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .background(canCreate ? .blue : Color(.tertiarySystemFill), in: .rect(cornerRadius: 12))
                        .foregroundStyle(canCreate ? .white : .secondary)
                }
                .buttonStyle(.plain)
                .disabled(!canCreate)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(.ultraThinMaterial)
    }

    private func addQuestItem(_ quest: Quest) {
        let item = JourneyQuestItem(
            id: UUID().uuidString,
            questId: quest.id,
            frequency: .daily,
            specificDays: [],
            scheduledHour: 8,
            scheduledMinute: 0,
            isAnytime: false,
            questMode: .solo
        )
        questItems.append(item)
    }

    private func createJourney() {
        let _ = appState.createJourney(
            name: journeyName,
            durationType: durationType,
            startDate: startDate,
            endDate: computedEndDate,
            mode: mode,
            visibility: visibility,
            questItems: questItems,
            calendarSync: calendarSync,
            calendarAlert: calendarAlert,
            invitedFriendIds: invitedFriendIds,
            verificationMode: verificationMode
        )
        dismiss()
    }
}

struct JourneyQuestItemEditor: View {
    @Binding var item: JourneyQuestItem
    let quest: Quest?
    let onRemove: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                if let q = quest {
                    Image(systemName: q.path.iconName)
                        .font(.caption)
                        .foregroundStyle(PathColorHelper.color(for: q.path))
                    Text(q.title)
                        .font(.subheadline.weight(.semibold))
                        .lineLimit(1)
                } else {
                    Text("Unknown Side Quest")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button(role: .destructive) { onRemove() } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.title3)
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }

            HStack(spacing: 8) {
                Text("Frequency")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.secondary)
                Picker("Frequency", selection: $item.frequency) {
                    ForEach(JourneyQuestFrequency.allCases, id: \.self) { f in
                        Text(f.rawValue).tag(f)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
            }

            if item.frequency == .specificDays {
                HStack(spacing: 4) {
                    ForEach(Weekday.allCases) { day in
                        Button {
                            if item.specificDays.contains(day) {
                                item.specificDays.removeAll { $0 == day }
                            } else {
                                item.specificDays.append(day)
                            }
                        } label: {
                            Text(day.rawValue)
                                .font(.system(size: 11, weight: .semibold))
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 6)
                                .background(
                                    item.specificDays.contains(day) ? Color.blue : Color(.tertiarySystemFill),
                                    in: .rect(cornerRadius: 6)
                                )
                                .foregroundStyle(item.specificDays.contains(day) ? .white : .primary)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }

            HStack(spacing: 12) {
                Toggle(isOn: $item.isAnytime) {
                    Text("Anytime")
                        .font(.caption.weight(.medium))
                }
                .toggleStyle(.switch)
                .tint(.blue)

                if !item.isAnytime {
                    Spacer()
                    HStack(spacing: 2) {
                        Picker("Hour", selection: Binding(
                            get: { let h = item.scheduledHour ?? 8; return h % 12 == 0 ? 12 : h % 12 },
                            set: { newH in
                                let isPM = (item.scheduledHour ?? 8) >= 12
                                let h12 = newH == 12 ? 0 : newH
                                item.scheduledHour = isPM ? h12 + 12 : h12
                            }
                        )) {
                            ForEach(1...12, id: \.self) { h in
                                Text("\(h)").tag(h)
                            }
                        }
                        .labelsHidden()

                        Text(":")
                            .fontWeight(.medium)

                        Picker("Minute", selection: Binding(
                            get: { item.scheduledMinute ?? 0 },
                            set: { item.scheduledMinute = $0 }
                        )) {
                            ForEach([0, 15, 30, 45], id: \.self) { m in
                                Text(String(format: "%02d", m)).tag(m)
                            }
                        }
                        .labelsHidden()

                        Picker("Period", selection: Binding(
                            get: { (item.scheduledHour ?? 8) >= 12 ? 1 : 0 },
                            set: { newPeriod in
                                let h = item.scheduledHour ?? 8
                                let h12 = h % 12
                                item.scheduledHour = newPeriod == 1 ? h12 + 12 : h12
                            }
                        )) {
                            Text("AM").tag(0)
                            Text("PM").tag(1)
                        }
                        .labelsHidden()
                    }
                }
            }
        }
        .padding(12)
        .background(Color(.secondarySystemGroupedBackground), in: .rect(cornerRadius: 12))
    }
}

struct JourneyQuestPickerSheet: View {
    let allQuests: [Quest]
    let existingQuestIds: Set<String>
    let onAdd: (Quest) -> Void
    var customQuests: [CustomQuest] = []
    var onCreateCustomQuest: (() -> Void)? = nil
    @Environment(\.dismiss) private var dismiss
    @State private var searchText: String = ""
    @State private var selectedPath: QuestPath?
    @State private var selectedTab: JourneyPickerTab = .library

    private var filteredQuests: [Quest] {
        var quests = allQuests
        if let path = selectedPath {
            quests = quests.filter { $0.path == path }
        }
        if !searchText.isEmpty {
            quests = quests.filter { $0.title.localizedStandardContains(searchText) }
        }
        return quests
    }

    private var filteredCustomQuests: [CustomQuest] {
        var quests = customQuests
        if let path = selectedPath {
            quests = quests.filter { $0.path == path }
        }
        if !searchText.isEmpty {
            quests = quests.filter { $0.title.localizedStandardContains(searchText) }
        }
        return quests
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                Picker("Tab", selection: $selectedTab) {
                    ForEach(JourneyPickerTab.allCases) { tab in
                        Text(tab.rawValue).tag(tab)
                    }
                }
                .pickerStyle(.segmented)
                .padding(.horizontal, 16)
                .padding(.vertical, 8)

                ScrollView(.horizontal) {
                    HStack(spacing: 8) {
                        filterChip("All", selected: selectedPath == nil) { selectedPath = nil }
                        ForEach(QuestPath.allCases) { path in
                            filterChip(path.rawValue, selected: selectedPath == path) { selectedPath = path }
                        }
                    }
                }
                .contentMargins(.horizontal, 16)
                .scrollIndicators(.hidden)
                .padding(.bottom, 8)

                if selectedTab == .myQuests {
                    myQuestsContent
                } else {
                    if let action = onCreateCustomQuest {
                        Button {
                            action()
                            dismiss()
                        } label: {
                            HStack(spacing: 10) {
                                Image(systemName: "plus.circle.fill")
                                    .font(.title3)
                                Text("Create Custom Side Quest")
                                    .font(.subheadline.weight(.semibold))
                                Spacer()
                                Image(systemName: "chevron.right")
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(.white.opacity(0.7))
                            }
                            .foregroundStyle(.white)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 14)
                            .background(.blue, in: RoundedRectangle(cornerRadius: 12))
                        }
                        .buttonStyle(.plain)
                        .padding(.horizontal, 16)
                    }
                    libraryContent
                }
            }
            .navigationTitle("Add Side Quest")
            .navigationBarTitleDisplayMode(.inline)
            .searchable(text: $searchText, prompt: "Search side quests...")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }

    private var libraryContent: some View {
        List(filteredQuests) { quest in
            let alreadyAdded = existingQuestIds.contains(quest.id)
            Button {
                if !alreadyAdded {
                    onAdd(quest)
                    dismiss()
                }
            } label: {
                HStack(spacing: 12) {
                    Image(systemName: quest.path.iconName)
                        .font(.caption)
                        .foregroundStyle(PathColorHelper.color(for: quest.path))
                        .frame(width: 28, height: 28)
                        .background(PathColorHelper.color(for: quest.path).opacity(0.12), in: Circle())
                    VStack(alignment: .leading, spacing: 2) {
                        Text(quest.title)
                            .font(.subheadline.weight(.medium))
                        HStack(spacing: 6) {
                            Text(quest.type.rawValue)
                            Text("·")
                            Text(quest.difficulty.rawValue)
                        }
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    }
                    Spacer()
                    if alreadyAdded {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                    } else {
                        Image(systemName: "plus.circle")
                            .foregroundStyle(.blue)
                    }
                }
            }
            .buttonStyle(.plain)
            .disabled(alreadyAdded)
        }
    }

    private var myQuestsContent: some View {
        List {
            if let action = onCreateCustomQuest {
                Button {
                    action()
                    dismiss()
                } label: {
                    HStack(spacing: 10) {
                        Image(systemName: "plus.circle.fill")
                            .font(.title3)
                            .foregroundStyle(.indigo)
                        Text("Create Custom Side Quest")
                            .font(.subheadline.weight(.semibold))
                        Spacer()
                    }
                }
                .buttonStyle(.plain)
            }

            if filteredCustomQuests.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "sparkle.magnifyingglass")
                        .font(.largeTitle)
                        .foregroundStyle(.tertiary)
                    Text("No custom side quests")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    Text("Create personal side quests to add them here.")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 30)
                .listRowBackground(Color.clear)
            } else {
                ForEach(filteredCustomQuests) { custom in
                    let quest = custom.toQuest()
                    let alreadyAdded = existingQuestIds.contains(quest.id)
                    Button {
                        if !alreadyAdded {
                            onAdd(quest)
                            dismiss()
                        }
                    } label: {
                        HStack(spacing: 12) {
                            Image(systemName: custom.path.iconName)
                                .font(.caption)
                                .foregroundStyle(PathColorHelper.color(for: custom.path))
                                .frame(width: 28, height: 28)
                                .background(PathColorHelper.color(for: custom.path).opacity(0.12), in: Circle())
                            VStack(alignment: .leading, spacing: 2) {
                                HStack(spacing: 6) {
                                    Text(custom.title)
                                        .font(.subheadline.weight(.medium))
                                    HStack(spacing: 2) {
                                        Image(systemName: "person.fill")
                                            .font(.system(size: 7))
                                        Text("Custom")
                                            .font(.system(size: 9, weight: .bold))
                                    }
                                    .foregroundStyle(.indigo)
                                    .padding(.horizontal, 5)
                                    .padding(.vertical, 2)
                                    .background(.indigo.opacity(0.12), in: Capsule())
                                }
                                HStack(spacing: 6) {
                                    Text("Open")
                                    Text("·")
                                    Text(custom.difficulty.rawValue)
                                }
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            }
                            Spacer()
                            if alreadyAdded {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundStyle(.green)
                            } else {
                                Image(systemName: "plus.circle")
                                    .foregroundStyle(.indigo)
                            }
                        }
                    }
                    .buttonStyle(.plain)
                    .disabled(alreadyAdded)
                }
            }
        }
    }

    private func filterChip(_ label: String, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(label)
                .font(.caption.weight(.medium))
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(selected ? Color.blue : Color(.tertiarySystemGroupedBackground), in: Capsule())
                .foregroundStyle(selected ? .white : .primary)
        }
        .buttonStyle(.plain)
    }
}

nonisolated enum JourneyPickerTab: String, CaseIterable, Identifiable, Sendable {
    case library = "Library"
    case myQuests = "My Side Quests"
    var id: String { rawValue }
}
