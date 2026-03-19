import SwiftUI

struct BrowseJourneysView: View {
    let appState: AppState
    @Environment(\.dismiss) private var dismiss
    @State private var selectedTemplate: JourneyTemplate?
    @State private var searchText: String = ""
    @State private var isLoading: Bool = false

    private var filteredTemplates: [JourneyTemplate] {
        guard !searchText.isEmpty else { return appState.journeyTemplates }
        return appState.journeyTemplates.filter {
            $0.title.localizedStandardContains(searchText) ||
            $0.description.localizedStandardContains(searchText)
        }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVStack(spacing: 12) {
                    ForEach(filteredTemplates) { template in
                        Button { selectedTemplate = template } label: {
                            JourneyTemplateCard(template: template, quests: appState.allQuests)
                        }
                        .buttonStyle(.plain)
                    }

                    if filteredTemplates.isEmpty {
                        VStack(spacing: 8) {
                            Image(systemName: "globe")
                                .font(.system(size: 40))
                                .foregroundStyle(.tertiary)
                            Text("No templates found")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 60)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 20)
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("Public Quests")
            .navigationBarTitleDisplayMode(.inline)
            .searchable(text: $searchText, prompt: "Search templates...")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .sheet(item: $selectedTemplate) { template in
                JoinJourneyView(template: template, appState: appState)
            }
            .task {
                await fetchServerTemplates()
            }
            .refreshable {
                await fetchServerTemplates()
            }
        }
    }

    private func fetchServerTemplates() async {
        isLoading = true
        defer { isLoading = false }
        if let serverTemplates: [APIJourneyTemplate]? = nil, let serverTemplates {
            for st in serverTemplates {
                if !appState.journeyTemplates.contains(where: { $0.id == st.id }) {
                    let difficulty = QuestDifficulty(rawValue: st.difficulty) ?? .medium
                    let template = JourneyTemplate(
                        id: st.id,
                        authorUsername: st.authorUsername,
                        authorAvatarName: st.authorAvatarName,
                        title: st.title,
                        description: st.description,
                        difficulty: difficulty,
                        defaultDurationDays: st.defaultDurationDays,
                        questItems: [],
                        timesAreRecommended: true,
                        joinCount: st.joinCount,
                        rating: st.rating,
                        createdAt: ISO8601DateFormatter().date(from: st.createdAt) ?? Date()
                    )
                    appState.journeyTemplates.append(template)
                }
            }
        }
    }
}

struct JourneyTemplateCard: View {
    let template: JourneyTemplate
    let quests: [Quest]

    private var difficultyColor: Color {
        switch template.difficulty {
        case .easy: .green
        case .medium: .orange
        case .hard: .red
        case .expert: .purple
        }
    }

    private var questPaths: [QuestPath] {
        let ids = template.questItems.map(\.questId)
        return Array(Set(ids.compactMap { id in quests.first(where: { $0.id == id })?.path }))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(template.title)
                        .font(.headline)
                        .lineLimit(1)
                    HStack(spacing: 6) {
                        Image(systemName: template.authorAvatarName)
                            .font(.caption)
                        Text(template.authorUsername)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer()
                Text(template.difficulty.rawValue)
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(difficultyColor)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(difficultyColor.opacity(0.12), in: Capsule())
            }

            Text(template.description)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(2)

            HStack(spacing: 16) {
                Label("\(template.defaultDurationDays) days", systemImage: "calendar")
                Label("\(template.questCount) side quests", systemImage: "scroll.fill")
                Spacer()
                HStack(spacing: 4) {
                    Image(systemName: "person.2.fill")
                        .font(.caption2)
                    Text("\(template.joinCount)")
                        .font(.caption.weight(.bold).monospacedDigit())
                }
                .foregroundStyle(.blue)

                if template.rating > 0 {
                    HStack(spacing: 2) {
                        Image(systemName: "star.fill")
                            .font(.caption2)
                            .foregroundStyle(.yellow)
                        Text(String(format: "%.1f", template.rating))
                            .font(.caption.weight(.bold).monospacedDigit())
                    }
                }
            }
            .font(.caption)
            .foregroundStyle(.secondary)

            HStack(spacing: 4) {
                ForEach(questPaths, id: \.self) { path in
                    PathBadgeView(path: path, compact: true)
                }
            }
        }
        .padding(14)
        .background(Color(.secondarySystemGroupedBackground), in: .rect(cornerRadius: 14))
    }
}

struct JoinJourneyView: View {
    let template: JourneyTemplate
    let appState: AppState
    @Environment(\.dismiss) private var dismiss
    @State private var startDate: Date = Date()
    @State private var calendarSync: Bool = false
    @State private var calendarAlert: CalendarAlertOption = .fifteenMin

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    VStack(alignment: .leading, spacing: 12) {
                        Text(template.title)
                            .font(.title2.weight(.bold))
                        Text(template.description)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)

                        HStack(spacing: 16) {
                            Label("\(template.defaultDurationDays) days", systemImage: "calendar")
                            Label("\(template.questCount) side quests", systemImage: "scroll.fill")
                            Label(template.difficulty.rawValue, systemImage: "gauge.medium")
                        }
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    }

                    VStack(alignment: .leading, spacing: 8) {
                        Text("SIDE QUESTS INCLUDED")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)

                        ForEach(template.questItems) { item in
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

                    VStack(alignment: .leading, spacing: 12) {
                        Text("START DATE")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                        DatePicker("Start", selection: $startDate, in: Date()..., displayedComponents: .date)
                    }
                    .padding(14)
                    .background(Color(.secondarySystemGroupedBackground), in: .rect(cornerRadius: 14))

                    VStack(alignment: .leading, spacing: 12) {
                        Toggle(isOn: $calendarSync) {
                            HStack(spacing: 8) {
                                Image(systemName: "calendar.badge.plus")
                                    .foregroundStyle(.blue)
                                Text("Add to Calendar")
                                    .font(.subheadline.weight(.semibold))
                            }
                        }
                        .tint(.blue)

                        if calendarSync {
                            Picker("Alert", selection: $calendarAlert) {
                                ForEach(CalendarAlertOption.allCases, id: \.self) { opt in
                                    Text(opt.rawValue).tag(opt)
                                }
                            }
                            .pickerStyle(.segmented)
                        }
                    }
                    .padding(14)
                    .background(Color(.secondarySystemGroupedBackground), in: .rect(cornerRadius: 14))

                    Button {
                        appState.joinJourneyTemplate(
                            template,
                            startDate: startDate,
                            calendarSync: calendarSync,
                            calendarAlert: calendarAlert
                        )
                        dismiss()
                    } label: {
                        HStack(spacing: 8) {
                            Image(systemName: "play.fill")
                            Text("Join Quest")
                                .font(.headline)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(.blue, in: .rect(cornerRadius: 14))
                        .foregroundStyle(.white)
                    }
                    .buttonStyle(.plain)
                }
                .padding(16)
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("Join Quest")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
    }
}
