import SwiftUI

// MARK: - Supporting Types

nonisolated enum CampaignDuration: Int, CaseIterable, Sendable {
    case week = 7
    case twoWeeks = 14
    case threeWeeks = 21
    case month = 30

    var label: String {
        switch self {
        case .week: "1 Week"
        case .twoWeeks: "2 Weeks"
        case .threeWeeks: "3 Weeks"
        case .month: "1 Month"
        }
    }

    var subtitle: String {
        switch self {
        case .week: "Quick sprint"
        case .twoWeeks: "Steady momentum"
        case .threeWeeks: "Locked in"
        case .month: "The full run"
        }
    }

    var icon: String {
        switch self {
        case .week: "bolt.fill"
        case .twoWeeks: "repeat.circle.fill"
        case .threeWeeks: "target"
        case .month: "flame.fill"
        }
    }
}

nonisolated enum PreferredTrainTime: String, CaseIterable, Sendable {
    case morning = "Morning"
    case afternoon = "Afternoon"
    case evening = "Evening"
    case flexible = "Flexible"

    var icon: String {
        switch self {
        case .morning: "sunrise.fill"
        case .afternoon: "sun.max.fill"
        case .evening: "moon.stars.fill"
        case .flexible: "shuffle"
        }
    }

    var color: Color {
        switch self {
        case .morning: .orange
        case .afternoon: .yellow
        case .evening: .indigo
        case .flexible: .blue
        }
    }

    var defaultHour: Int {
        switch self {
        case .morning: 7
        case .afternoon: 13
        case .evening: 19
        case .flexible: 8
        }
    }
}

nonisolated enum IntensityLevel: String, CaseIterable, Sendable {
    case light = "Light"
    case moderate = "Moderate"
    case intense = "Intense"

    var subtitle: String {
        switch self {
        case .light: "1–2 side quests/day"
        case .moderate: "3–4 side quests/day"
        case .intense: "5+ side quests/day"
        }
    }

    var icon: String {
        switch self {
        case .light: "1.circle.fill"
        case .moderate: "3.circle.fill"
        case .intense: "5.circle.fill"
        }
    }

    var questCount: Int {
        switch self {
        case .light: 2
        case .moderate: 3
        case .intense: 5
        }
    }
}

nonisolated enum ExperienceLevel: String, CaseIterable, Sendable {
    case beginner = "New Hero"
    case intermediate = "Rising Force"
    case advanced = "Elite"

    var subtitle: String {
        switch self {
        case .beginner: "I'm just starting out"
        case .intermediate: "I've built some habits"
        case .advanced: "I push hard daily"
        }
    }

    var icon: String {
        switch self {
        case .beginner: "seedling"
        case .intermediate: "figure.walk"
        case .advanced: "bolt.circle.fill"
        }
    }

    var difficulty: QuestDifficulty {
        switch self {
        case .beginner: .easy
        case .intermediate: .medium
        case .advanced: .hard
        }
    }
}

// MARK: - Campaign Generator

struct GeneratedCampaignPlan {
    var name: String
    var questItems: [JourneyQuestItem]
    var durationType: JourneyDurationType
    var startDate: Date
    var endDate: Date
    var difficulty: QuestDifficulty
}

struct CampaignGenerator {
    static func skillsToPath(_ skills: [UserSkill]) -> [QuestPath] {
        var paths: Set<QuestPath> = []
        for skill in skills {
            switch skill {
            case .strength, .endurance, .resilience, .discipline:
                paths.insert(.warrior)
            case .mindfulness, .focus, .intelligence, .creativity:
                paths.insert(.mind)
            case .charisma, .leadership:
                paths.insert(.explorer)
                paths.insert(.mind)
            }
        }
        return paths.isEmpty ? QuestPath.allCases : Array(paths)
    }

    static func generate(
        skills: [UserSkill],
        duration: CampaignDuration,
        trainTime: PreferredTrainTime,
        intensity: IntensityLevel,
        experience: ExperienceLevel,
        availableDays: Set<Weekday>,
        allQuests: [Quest]
    ) -> GeneratedCampaignPlan {
        let paths = skillsToPath(skills)
        let targetDifficulty = experience.difficulty
        let questCount = intensity.questCount

        let difficulties: [QuestDifficulty] = {
            switch targetDifficulty {
            case .easy: return [.easy]
            case .medium: return [.easy, .medium]
            case .hard: return [.medium, .hard]
            case .expert: return [.hard, .expert]
            }
        }()

        var pool = allQuests.filter { q in
            paths.contains(q.path) && difficulties.contains(q.difficulty) && q.type != .event
        }

        if pool.isEmpty {
            pool = allQuests.filter { difficulties.contains($0.difficulty) && $0.type != .event }
        }

        let skillTagged = pool.filter { q in
            !q.skillTags.isEmpty && !Set(q.skillTags).isDisjoint(with: Set(skills))
        }

        var selected: [Quest] = []
        var usedPaths: [QuestPath: Int] = [:]

        for q in skillTagged.shuffled() {
            if selected.count >= questCount { break }
            let pathCount = usedPaths[q.path] ?? 0
            if pathCount < 2 {
                selected.append(q)
                usedPaths[q.path, default: 0] += 1
            }
        }

        if selected.count < questCount {
            for q in pool.shuffled() {
                if selected.count >= questCount { break }
                if !selected.contains(where: { $0.id == q.id }) {
                    selected.append(q)
                }
            }
        }

        let useSpecificDays = !availableDays.isEmpty && availableDays.count < 7
        let frequency: JourneyQuestFrequency = useSpecificDays ? .specificDays : .daily
        let isAnytime = trainTime == .flexible

        var questItems: [JourneyQuestItem] = []
        for (i, quest) in selected.enumerated() {
            let hourOffset = i % 2 == 0 ? 0 : 1
            let hour = isAnytime ? trainTime.defaultHour : trainTime.defaultHour + hourOffset
            let item = JourneyQuestItem(
                id: UUID().uuidString,
                questId: quest.id,
                frequency: frequency,
                specificDays: useSpecificDays ? Array(availableDays) : [],
                scheduledHour: isAnytime ? nil : hour,
                scheduledMinute: isAnytime ? nil : 0,
                isAnytime: isAnytime,
                questMode: .solo
            )
            questItems.append(item)
        }

        let cal = Calendar.current
        let startDate = Date()
        let endDate = cal.date(byAdding: .day, value: duration.rawValue - 1, to: startDate) ?? startDate

        let durationType: JourneyDurationType = duration == .week ? .sevenDays : .custom

        return GeneratedCampaignPlan(
            name: generateCampaignName(skills: skills, duration: duration),
            questItems: questItems,
            durationType: durationType,
            startDate: startDate,
            endDate: endDate,
            difficulty: targetDifficulty
        )
    }

    static func generateCampaignName(skills: [UserSkill], duration: CampaignDuration) -> String {
        let nameMap: [Set<UserSkill>: [String]] = [
            [.strength, .endurance]: ["Iron Body Protocol", "Forge & Grind", "Steel Initiative"],
            [.strength, .discipline]: ["No Days Off", "Ironclad Arc", "Daily Grind"],
            [.focus, .intelligence]: ["Deep Work Sprint", "Clarity Ops", "Signal Over Noise"],
            [.mindfulness, .discipline]: ["Steady Ground", "Stillness & Steel", "Centered Force"],
            [.charisma, .leadership]: ["Command Presence", "Social Ops", "Influence Forge"],
            [.resilience, .discipline]: ["Grit Protocol", "Storm Protocol", "Hard Reset"],
            [.creativity, .intelligence]: ["Creative Surge", "Idea Lab Sprint", "Build Mode"],
            [.mindfulness, .focus]: ["Flow State Protocol", "Locked In", "Quiet Mode"],
            [.endurance, .resilience]: ["Endure Everything", "Long Game", "Iron Will"],
            [.charisma, .mindfulness]: ["People Mode", "Social Recharge", "Easy Company"],
        ]

        let skillSet = Set(skills.prefix(2))
        for (key, names) in nameMap {
            if key == skillSet { return names.randomElement() ?? "My Quest" }
        }

        if let first = skills.first {
            let suffixes = ["Protocol", "Run", "Sprint", "Initiative", "Forge"]
            return "\(first.rawValue) \(suffixes.randomElement() ?? "Protocol")"
        }

        return "My Quest"
    }
}

// MARK: - Main View

struct SmartCampaignBuilderView: View {
    let appState: AppState
    @Environment(\.dismiss) private var dismiss

    @State private var step: Int = 0
    @State private var selectedSkills: Set<UserSkill> = []
    @State private var selectedDuration: CampaignDuration = .twoWeeks
    @State private var preferredTime: PreferredTrainTime = .morning
    @State private var intensity: IntensityLevel = .moderate
    @State private var experience: ExperienceLevel = .intermediate
    @State private var availableDays: Set<Weekday> = Set(Weekday.allCases)
    @State private var generatedPlan: GeneratedCampaignPlan?
    @State private var isGenerating: Bool = false
    @State private var generatingProgress: Double = 0
    @State private var showCustomize: Bool = false
    @State private var planName: String = ""
    @State private var editableQuestItems: [JourneyQuestItem] = []
    @State private var showQuestPicker: Bool = false
    @State private var showCreateCustom: Bool = false
    @State private var calendarConflicts: [String: String] = [:]

    private let totalSteps = 4

    var body: some View {
        NavigationStack {
            ZStack {
                Color(.systemGroupedBackground).ignoresSafeArea()

                if isGenerating {
                    generatingView
                } else if let plan = generatedPlan, !showCustomize {
                    resultView(plan: plan)
                } else if showCustomize {
                    customizeView
                } else {
                    wizardContent
                }
            }
            .navigationTitle(isGenerating ? "" : (generatedPlan != nil ? "" : "Smart Build"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    if !isGenerating {
                        Button("Cancel") { dismiss() }
                    }
                }
            }
            .sheet(isPresented: $showCustomize) {
                customizeSheetContent
            }

        }
    }

    // MARK: - Wizard

    private var wizardContent: some View {
        VStack(spacing: 0) {
            stepDots
            TabView(selection: $step) {
                skillStep.tag(0)
                durationStep.tag(1)
                scheduleStep.tag(2)
                intensityStep.tag(3)
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
            .animation(.snappy, value: step)
            wizardBottomBar
        }
    }

    private var stepDots: some View {
        HStack(spacing: 6) {
            ForEach(0..<totalSteps, id: \.self) { i in
                Capsule()
                    .fill(i <= step ? Color.blue : Color(.tertiarySystemFill))
                    .frame(width: i == step ? 20 : 6, height: 6)
                    .animation(.spring(response: 0.3), value: step)
            }
        }
        .padding(.top, 12)
        .padding(.bottom, 4)
    }

    // MARK: Step 1: Skills

    private var skillStep: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("What do you want to develop?")
                        .font(.title2.weight(.bold))
                    Text("Select all skills you want this quest to train.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .padding(.horizontal, 20)
                .padding(.top, 16)

                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                    ForEach(UserSkill.allCases) { skill in
                        skillTile(skill)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 20)
            }
        }
    }

    private func skillTile(_ skill: UserSkill) -> some View {
        let selected = selectedSkills.contains(skill)
        return Button {
            withAnimation(.spring(response: 0.25)) {
                if selected {
                    selectedSkills.remove(skill)
                } else {
                    selectedSkills.insert(skill)
                }
            }
        } label: {
            VStack(spacing: 10) {
                ZStack {
                    Circle()
                        .fill(selected ? skill.color : skill.color.opacity(0.1))
                        .frame(width: 48, height: 48)
                    Image(systemName: skill.icon)
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundStyle(selected ? .white : skill.color)
                }
                VStack(spacing: 3) {
                    Text(skill.rawValue)
                        .font(.subheadline.weight(.semibold))
                    Text(skill.description)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .lineLimit(2)
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .padding(.horizontal, 8)
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .fill(selected ? skill.color.opacity(0.1) : Color(.secondarySystemGroupedBackground))
                    .overlay(
                        RoundedRectangle(cornerRadius: 16)
                            .strokeBorder(selected ? skill.color : Color.clear, lineWidth: 2)
                    )
            )
            .scaleEffect(selected ? 1.02 : 1.0)
        }
        .buttonStyle(.plain)
    }

    // MARK: Step 2: Duration

    private var durationStep: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("How long is your quest?")
                        .font(.title2.weight(.bold))
                    Text("Pick a timeframe that works for you.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .padding(.horizontal, 20)
                .padding(.top, 16)

                VStack(spacing: 10) {
                    ForEach(CampaignDuration.allCases, id: \.self) { dur in
                        durationCard(dur)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 20)
            }
        }
    }

    private func durationCard(_ dur: CampaignDuration) -> some View {
        let selected = selectedDuration == dur
        return Button {
            withAnimation(.spring(response: 0.25)) { selectedDuration = dur }
        } label: {
            HStack(spacing: 14) {
                ZStack {
                    RoundedRectangle(cornerRadius: 10)
                        .fill(selected ? Color.blue : Color(.tertiarySystemGroupedBackground))
                        .frame(width: 44, height: 44)
                    Image(systemName: dur.icon)
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(selected ? .white : .secondary)
                }

                VStack(alignment: .leading, spacing: 3) {
                    Text(dur.label)
                        .font(.headline)
                    Text(dur.subtitle)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Image(systemName: selected ? "checkmark.circle.fill" : "circle")
                    .font(.title3)
                    .foregroundStyle(selected ? Color.blue : Color(.tertiaryLabel))
            }
            .padding(14)
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .fill(selected ? Color.blue.opacity(0.07) : Color(.secondarySystemGroupedBackground))
                    .overlay(
                        RoundedRectangle(cornerRadius: 16)
                            .strokeBorder(selected ? Color.blue.opacity(0.4) : Color.clear, lineWidth: 1.5)
                    )
            )
        }
        .buttonStyle(.plain)
    }

    // MARK: Step 3: Schedule

    private var scheduleStep: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Tell us about your schedule")
                        .font(.title2.weight(.bold))
                    Text("We'll work around your availability.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .padding(.horizontal, 20)
                .padding(.top, 16)

                VStack(alignment: .leading, spacing: 14) {
                    Text("PREFERRED TRAINING TIME")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 4)

                    HStack(spacing: 8) {
                        ForEach(PreferredTrainTime.allCases, id: \.self) { time in
                            trainTimeChip(time)
                        }
                    }
                }
                .padding(.horizontal, 16)

                VStack(alignment: .leading, spacing: 14) {
                    Text("AVAILABLE DAYS")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 4)

                    HStack(spacing: 6) {
                        ForEach(Weekday.allCases) { day in
                            Button {
                                withAnimation(.spring(response: 0.2)) {
                                    if availableDays.contains(day) {
                                        if availableDays.count > 1 {
                                            availableDays.remove(day)
                                        }
                                    } else {
                                        availableDays.insert(day)
                                    }
                                }
                            } label: {
                                let on = availableDays.contains(day)
                                Text(String(day.rawValue.prefix(1)))
                                    .font(.system(size: 13, weight: .bold))
                                    .frame(maxWidth: .infinity)
                                    .frame(height: 36)
                                    .background(on ? Color.blue : Color(.secondarySystemGroupedBackground), in: .rect(cornerRadius: 8))
                                    .foregroundStyle(on ? .white : .secondary)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                .padding(.horizontal, 16)

                VStack(alignment: .leading, spacing: 14) {
                    Text("YOUR EXPERIENCE LEVEL")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 4)

                    VStack(spacing: 8) {
                        ForEach(ExperienceLevel.allCases, id: \.self) { lvl in
                            experienceRow(lvl)
                        }
                    }
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 20)
            }
        }
    }

    private func trainTimeChip(_ time: PreferredTrainTime) -> some View {
        let selected = preferredTime == time
        return Button {
            withAnimation(.spring(response: 0.25)) { preferredTime = time }
        } label: {
            VStack(spacing: 5) {
                Image(systemName: time.icon)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(selected ? time.color : .secondary)
                Text(time.rawValue)
                    .font(.caption.weight(.semibold))
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 10)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(selected ? time.color.opacity(0.12) : Color(.secondarySystemGroupedBackground))
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .strokeBorder(selected ? time.color : Color.clear, lineWidth: 1.5)
                    )
            )
        }
        .buttonStyle(.plain)
    }

    private func experienceRow(_ lvl: ExperienceLevel) -> some View {
        let selected = experience == lvl
        return Button {
            withAnimation(.spring(response: 0.25)) { experience = lvl }
        } label: {
            HStack(spacing: 12) {
                Image(systemName: lvl.icon)
                    .font(.system(size: 18))
                    .foregroundStyle(selected ? .blue : .secondary)
                    .frame(width: 28)
                VStack(alignment: .leading, spacing: 2) {
                    Text(lvl.rawValue)
                        .font(.subheadline.weight(.semibold))
                    Text(lvl.subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Image(systemName: selected ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(selected ? Color.blue : Color(.tertiaryLabel))
            }
            .padding(12)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(selected ? Color.blue.opacity(0.07) : Color(.secondarySystemGroupedBackground))
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .strokeBorder(selected ? Color.blue.opacity(0.4) : Color.clear, lineWidth: 1.5)
                    )
            )
        }
        .buttonStyle(.plain)
    }

    // MARK: Step 4: Intensity

    private var intensityStep: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("How hard do you want to push?")
                        .font(.title2.weight(.bold))
                    Text("You can always adjust individual side quests after.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .padding(.horizontal, 20)
                .padding(.top, 16)

                VStack(spacing: 10) {
                    ForEach(IntensityLevel.allCases, id: \.self) { lvl in
                        intensityCard(lvl)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 20)
            }
        }
    }

    private func intensityCard(_ lvl: IntensityLevel) -> some View {
        let selected = intensity == lvl
        let colors: [IntensityLevel: Color] = [.light: .green, .moderate: .orange, .intense: .red]
        let c = colors[lvl] ?? .blue
        return Button {
            withAnimation(.spring(response: 0.25)) { intensity = lvl }
        } label: {
            HStack(spacing: 14) {
                ZStack {
                    RoundedRectangle(cornerRadius: 10)
                        .fill(selected ? c : Color(.tertiarySystemGroupedBackground))
                        .frame(width: 44, height: 44)
                    Image(systemName: lvl.icon)
                        .font(.system(size: 18, weight: .bold))
                        .foregroundStyle(selected ? .white : c)
                }
                VStack(alignment: .leading, spacing: 3) {
                    Text(lvl.rawValue)
                        .font(.headline)
                    Text(lvl.subtitle)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Image(systemName: selected ? "checkmark.circle.fill" : "circle")
                    .font(.title3)
                    .foregroundStyle(selected ? c : Color(.tertiaryLabel))
            }
            .padding(14)
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .fill(selected ? c.opacity(0.07) : Color(.secondarySystemGroupedBackground))
                    .overlay(
                        RoundedRectangle(cornerRadius: 16)
                            .strokeBorder(selected ? c.opacity(0.4) : Color.clear, lineWidth: 1.5)
                    )
            )
        }
        .buttonStyle(.plain)
    }

    // MARK: Bottom Bar

    private var wizardBottomBar: some View {
        HStack(spacing: 12) {
            if step > 0 {
                Button {
                    withAnimation(.snappy) { step -= 1 }
                } label: {
                    Text("Back")
                        .font(.subheadline.weight(.semibold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(Color(.tertiarySystemGroupedBackground), in: .rect(cornerRadius: 14))
                }
                .buttonStyle(.plain)
            }

            if step < totalSteps - 1 {
                Button {
                    withAnimation(.snappy) { step += 1 }
                } label: {
                    Text("Next")
                        .font(.subheadline.weight(.semibold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(canAdvance ? Color.blue : Color(.tertiarySystemGroupedBackground), in: .rect(cornerRadius: 14))
                        .foregroundStyle(canAdvance ? .white : .secondary)
                }
                .buttonStyle(.plain)
                .disabled(!canAdvance)
            } else {
                Button { startGeneration() } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "wand.and.stars")
                        Text("Build My Quest")
                    }
                    .font(.subheadline.weight(.bold))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(Color.blue, in: .rect(cornerRadius: 14))
                    .foregroundStyle(.white)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(.ultraThinMaterial)
    }

    private var canAdvance: Bool {
        switch step {
        case 0: return !selectedSkills.isEmpty
        default: return true
        }
    }

    // MARK: - Generating View

    private var generatingView: some View {
        VStack(spacing: 32) {
            Spacer()

            ZStack {
                ForEach(0..<3, id: \.self) { i in
                    Circle()
                        .stroke(Color.blue.opacity(0.15 + Double(i) * 0.1), lineWidth: 1.5)
                        .frame(width: CGFloat(80 + i * 40), height: CGFloat(80 + i * 40))
                        .scaleEffect(isGenerating ? 1.0 + Double(i) * 0.05 : 1.0)
                        .animation(
                            .easeInOut(duration: 1.4).repeatForever(autoreverses: true).delay(Double(i) * 0.2),
                            value: isGenerating
                        )
                }
                Image(systemName: "wand.and.stars")
                    .font(.system(size: 36, weight: .semibold))
                    .foregroundStyle(.blue)
                    .rotationEffect(.degrees(isGenerating ? 10 : -10))
                    .animation(.easeInOut(duration: 0.8).repeatForever(autoreverses: true), value: isGenerating)
            }
            .frame(height: 180)

            VStack(spacing: 10) {
                Text("Building your quest...")
                    .font(.title3.weight(.bold))

                Text("Matching side quests to your skills and schedule")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }

            VStack(spacing: 8) {
                ProgressView(value: generatingProgress)
                    .tint(.blue)
                    .frame(width: 200)
                Text("\(Int(generatingProgress * 100))%")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }

            Spacer()
        }
        .padding(.horizontal, 40)
    }

    // MARK: - Result View

    private func resultView(plan: GeneratedCampaignPlan) -> some View {
        ScrollView {
            VStack(spacing: 20) {
                VStack(spacing: 8) {
                    Image(systemName: "checkmark.seal.fill")
                        .font(.system(size: 44))
                        .foregroundStyle(.blue)
                        .symbolEffect(.bounce, value: generatedPlan != nil)

                    Text("Your Quest is Ready")
                        .font(.title2.weight(.bold))
                    Text("Built around your skills and schedule.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
                .padding(.top, 24)
                .padding(.horizontal, 20)

                VStack(alignment: .leading, spacing: 14) {
                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(plan.name)
                                .font(.title3.weight(.bold))
                            HStack(spacing: 10) {
                                Label("\(selectedDuration.label)", systemImage: "calendar")
                                Label("\(plan.questItems.count) side quests", systemImage: "scroll.fill")
                            }
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Image(systemName: "wand.and.stars.inverse")
                            .font(.title2)
                            .foregroundStyle(.blue.opacity(0.5))
                    }
                    .padding(14)
                    .background(Color(.secondarySystemGroupedBackground), in: .rect(cornerRadius: 14))

                    skillSummaryPills
                    questPreviewList(plan: plan)
                }
                .padding(.horizontal, 16)

                VStack(spacing: 10) {
                    Button {
                        planName = plan.name
                        editableQuestItems = plan.questItems
                        showCustomize = true
                        checkCalendarConflicts()
                    } label: {
                        HStack(spacing: 8) {
                            Image(systemName: "pencil")
                            Text("Customize Quest")
                        }
                        .font(.subheadline.weight(.semibold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(Color(.secondarySystemGroupedBackground), in: .rect(cornerRadius: 14))
                    }
                    .buttonStyle(.plain)

                    Button {
                        launchCampaign(plan: plan)
                    } label: {
                        HStack(spacing: 8) {
                            Image(systemName: "bolt.fill")
                            Text("Launch Quest")
                        }
                        .font(.subheadline.weight(.bold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(Color.blue, in: .rect(cornerRadius: 14))
                        .foregroundStyle(.white)
                    }
                    .buttonStyle(.plain)

                    Button {
                        withAnimation(.snappy) {
                            generatedPlan = nil
                            step = 0
                        }
                    } label: {
                        Text("Start Over")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 32)
            }
        }
    }

    private var skillSummaryPills: some View {
        ScrollView(.horizontal) {
            HStack(spacing: 8) {
                ForEach(Array(selectedSkills), id: \.self) { skill in
                    HStack(spacing: 5) {
                        Image(systemName: skill.icon)
                            .font(.system(size: 11, weight: .bold))
                        Text(skill.rawValue)
                            .font(.caption.weight(.semibold))
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(skill.color.opacity(0.12), in: Capsule())
                    .foregroundStyle(skill.color)
                }
            }
        }
        .contentMargins(.horizontal, 0)
        .scrollIndicators(.hidden)
    }

    private func questPreviewList(plan: GeneratedCampaignPlan) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("SIDE QUESTS SELECTED")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)

            ForEach(plan.questItems) { item in
                let quest = appState.allQuests.first(where: { $0.id == item.questId })
                HStack(spacing: 12) {
                    if let q = quest {
                        Image(systemName: q.path.iconName)
                            .font(.caption)
                            .foregroundStyle(PathColorHelper.color(for: q.path))
                            .frame(width: 28, height: 28)
                            .background(PathColorHelper.color(for: q.path).opacity(0.1), in: Circle())
                    }
                    VStack(alignment: .leading, spacing: 2) {
                        Text(quest?.title ?? "Quest")
                            .font(.subheadline.weight(.medium))
                        HStack(spacing: 6) {
                            Text(item.frequency.rawValue)
                            Text("·")
                            Text(item.timeDescription)
                        }
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    }
                    Spacer()
                    if let q = quest {
                        Text(q.difficulty.rawValue)
                            .font(.caption2.weight(.bold))
                            .padding(.horizontal, 7)
                            .padding(.vertical, 3)
                            .background(difficultyColor(q.difficulty).opacity(0.12), in: Capsule())
                            .foregroundStyle(difficultyColor(q.difficulty))
                    }
                }
                .padding(10)
                .background(Color(.secondarySystemGroupedBackground), in: .rect(cornerRadius: 10))
            }
        }
    }

    // MARK: - Customize Sheet

    private var customizeView: some View {
        EmptyView()
    }

    private var customizeSheetContent: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Quest Name")
                            .font(.subheadline.weight(.semibold))
                        TextField("Quest name", text: $planName)
                            .textFieldStyle(.roundedBorder)
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 8)

                    VStack(alignment: .leading, spacing: 10) {
                        Text("SIDE QUESTS")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 16)

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
                        .padding(.horizontal, 16)

                        ForEach(editableQuestItems) { item in
                            let quest = appState.allQuests.first(where: { $0.id == item.questId })
                            if let idx = editableQuestItems.firstIndex(where: { $0.id == item.id }) {
                                VStack(spacing: 4) {
                                    JourneyQuestItemEditor(
                                        item: $editableQuestItems[idx],
                                        quest: quest,
                                        onRemove: { editableQuestItems.removeAll { $0.id == item.id } }
                                    )
                                    if let conflict = calendarConflicts[item.id] {
                                        HStack(spacing: 6) {
                                            Image(systemName: "exclamationmark.triangle.fill")
                                                .font(.caption2)
                                                .foregroundStyle(.orange)
                                            Text(conflict)
                                                .font(.caption2)
                                                .foregroundStyle(.orange)
                                        }
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                        .padding(.horizontal, 4)
                                    }
                                }
                                .padding(.horizontal, 16)
                            }
                        }
                    }
                }
                .padding(.bottom, 24)
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("Customize")
            .navigationBarTitleDisplayMode(.inline)
            .sheet(isPresented: $showQuestPicker) {
                JourneyQuestPickerSheet(
                    allQuests: appState.allQuests,
                    existingQuestIds: Set(editableQuestItems.map(\.questId)),
                    onAdd: { quest in
                        addQuestToCustomize(quest)
                    },
                    customQuests: appState.customQuests,
                    onCreateCustomQuest: { showCreateCustom = true }
                )
            }
            .sheet(isPresented: $showCreateCustom) {
                CreateCustomQuestView(appState: appState)
            }
            .onChange(of: editableQuestItems) { _, _ in
                checkCalendarConflicts()
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { showCustomize = false }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save & Launch") {
                        if var plan = generatedPlan {
                            plan.name = planName
                            plan.questItems = editableQuestItems
                            showCustomize = false
                            launchCampaign(plan: plan)
                        }
                    }
                    .fontWeight(.semibold)
                    .disabled(planName.trimmingCharacters(in: .whitespaces).isEmpty || editableQuestItems.isEmpty)
                }
            }
        }
    }

    // MARK: - Actions

    private func startGeneration() {
        isGenerating = true
        generatingProgress = 0

        Task {
            for i in stride(from: 0.0, to: 1.0, by: 0.05) {
                try? await Task.sleep(for: .milliseconds(60))
                await MainActor.run {
                    withAnimation(.easeInOut(duration: 0.1)) {
                        generatingProgress = i
                    }
                }
            }

            let plan = CampaignGenerator.generate(
                skills: Array(selectedSkills),
                duration: selectedDuration,
                trainTime: preferredTime,
                intensity: intensity,
                experience: experience,
                availableDays: availableDays,
                allQuests: appState.allQuests
            )

            try? await Task.sleep(for: .milliseconds(300))

            await MainActor.run {
                withAnimation(.spring(response: 0.4)) {
                    generatingProgress = 1.0
                }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
                    withAnimation(.spring(response: 0.5)) {
                        generatedPlan = plan
                        isGenerating = false
                    }
                }
            }
        }
    }

    private func launchCampaign(plan: GeneratedCampaignPlan) {
        let _ = appState.createJourney(
            name: plan.name.isEmpty ? "My Quest" : plan.name,
            durationType: plan.durationType,
            startDate: plan.startDate,
            endDate: plan.endDate,
            mode: .solo,
            visibility: .privateJourney,
            questItems: plan.questItems,
            calendarSync: false,
            calendarAlert: .none,
            invitedFriendIds: [],
            verificationMode: .verified
        )
        dismiss()
    }

    private func addQuestToCustomize(_ quest: Quest) {
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
        editableQuestItems.append(item)
        checkCalendarConflicts()
    }

    private func checkCalendarConflicts() {
        var conflicts: [String: String] = [:]
        var scheduled: [(id: String, title: String, hour: Int, minute: Int, days: Set<Weekday>)] = []

        for item in editableQuestItems {
            guard !item.isAnytime, let hour = item.scheduledHour, let minute = item.scheduledMinute else { continue }
            let quest = appState.allQuests.first(where: { $0.id == item.questId })
            let title = quest?.title ?? "Quest"
            let days: Set<Weekday> = item.frequency == .specificDays ? Set(item.specificDays) : Set(Weekday.allCases)
            scheduled.append((id: item.id, title: title, hour: hour, minute: minute, days: days))
        }

        for i in 0..<scheduled.count {
            for j in (i + 1)..<scheduled.count {
                let a = scheduled[i]
                let b = scheduled[j]
                let overlappingDays = a.days.intersection(b.days)
                guard !overlappingDays.isEmpty else { continue }
                let diffMinutes = abs((a.hour * 60 + a.minute) - (b.hour * 60 + b.minute))
                if diffMinutes < 60 {
                    if conflicts[a.id] == nil {
                        conflicts[a.id] = "Overlaps with \(b.title) at the same time"
                    }
                    if conflicts[b.id] == nil {
                        conflicts[b.id] = "Overlaps with \(a.title) at the same time"
                    }
                }
            }
        }

        calendarConflicts = conflicts
    }

    private func difficultyColor(_ d: QuestDifficulty) -> Color {
        switch d {
        case .easy: return .green
        case .medium: return .orange
        case .hard: return .red
        case .expert: return .purple
        }
    }
}
