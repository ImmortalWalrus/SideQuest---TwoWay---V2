import SwiftUI

struct CreateCustomQuestView: View {
    let appState: AppState
    var editingQuest: CustomQuest? = nil
    @Environment(\.dismiss) private var dismiss
    @State private var title: String = ""
    @State private var questDescription: String = ""
    @State private var selectedPath: QuestPath = .warrior
    @State private var selectedDifficulty: QuestDifficulty = .medium
    @State private var repeatability: CustomQuestRepeatability = .oneTime
    @State private var suggestedTime: String = ""
    @State private var notes: String = ""
    @State private var savedQuest: CustomQuest?
    @State private var showPostSaveOptions: Bool = false
    @State private var showJourneyPicker: Bool = false
    @State private var addedToActive: Bool = false
    @State private var addedToJourney: Bool = false
    @State private var showCreateJourney: Bool = false

    private var isEditing: Bool { editingQuest != nil }

    private var canSave: Bool {
        !title.trimmingCharacters(in: .whitespaces).isEmpty &&
        !questDescription.trimmingCharacters(in: .whitespaces).isEmpty &&
        title.count <= 40 &&
        questDescription.count <= 200
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    openPlayBanner
                    titleSection
                    descriptionSection
                    pathSection
                    difficultySection
                    repeatabilitySection
                    optionalSection
                }
                .padding(16)
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle(isEditing ? "Edit Side Quest" : "Create Side Quest")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { saveQuest() }
                        .fontWeight(.semibold)
                        .disabled(!canSave)
                }
            }
            .onAppear { loadEditingData() }
            .sheet(isPresented: $showPostSaveOptions) {
                if let quest = savedQuest {
                    postSaveSheet(quest)
                }
            }
            .sheet(isPresented: $showJourneyPicker) {
                if let quest = savedQuest {
                    journeyPickerSheet(quest)
                }
            }
            .sheet(isPresented: $showCreateJourney) {
                CreateJourneyView(appState: appState)
            }
        }
    }

    private var openPlayBanner: some View {
        HStack(spacing: 10) {
            Image(systemName: "person.fill")
                .font(.title3)
                .foregroundStyle(.indigo)
            VStack(alignment: .leading, spacing: 2) {
                Text("Personal Open Play Side Quest")
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(.indigo)
                Text("Custom side quests are open play only. Self-verified with adaptive criteria. No milestone progress. Rewards are capped at open play levels.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.indigo.opacity(0.08), in: .rect(cornerRadius: 12))
    }

    private var titleSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Title")
                    .font(.subheadline.weight(.semibold))
                Spacer()
                Text("\(title.count)/40")
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(title.count > 40 ? Color.red : Color.secondary)
            }
            TextField("e.g. Morning Stretching", text: $title)
                .textFieldStyle(.roundedBorder)
                .onChange(of: title) { _, newValue in
                    if newValue.count > 40 {
                        title = String(newValue.prefix(40))
                    }
                }
        }
    }

    private var descriptionSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Description / Instructions")
                    .font(.subheadline.weight(.semibold))
                Spacer()
                Text("\(questDescription.count)/200")
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(questDescription.count > 200 ? Color.red : Color.secondary)
            }
            TextEditor(text: $questDescription)
                .frame(minHeight: 80, maxHeight: 120)
                .scrollContentBackground(.hidden)
                .padding(8)
                .background(Color(.secondarySystemGroupedBackground), in: .rect(cornerRadius: 10))
                .onChange(of: questDescription) { _, newValue in
                    if newValue.count > 200 {
                        questDescription = String(newValue.prefix(200))
                    }
                }
        }
    }

    private var pathSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Path")
                .font(.subheadline.weight(.semibold))
            HStack(spacing: 8) {
                ForEach(QuestPath.allCases) { path in
                    let color = PathColorHelper.color(for: path)
                    Button {
                        withAnimation(.snappy) { selectedPath = path }
                    } label: {
                        VStack(spacing: 6) {
                            Image(systemName: path.iconName)
                                .font(.title3)
                            Text(path.rawValue)
                                .font(.caption.weight(.semibold))
                        }
                        .foregroundStyle(selectedPath == path ? .white : color)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .background(
                            selectedPath == path ? color : color.opacity(0.1),
                            in: .rect(cornerRadius: 12)
                        )
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private var difficultySection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Difficulty")
                .font(.subheadline.weight(.semibold))
            HStack(spacing: 8) {
                ForEach([QuestDifficulty.easy, .medium, .hard], id: \.self) { diff in
                    Button {
                        withAnimation(.snappy) { selectedDifficulty = diff }
                    } label: {
                        Text(diff.rawValue)
                            .font(.subheadline.weight(.medium))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 10)
                            .background(
                                selectedDifficulty == diff ? Color.blue : Color(.tertiarySystemGroupedBackground),
                                in: .rect(cornerRadius: 10)
                            )
                            .foregroundStyle(selectedDifficulty == diff ? .white : .primary)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private var repeatabilitySection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Repeatability")
                .font(.subheadline.weight(.semibold))
            Picker("Repeatability", selection: $repeatability) {
                ForEach(CustomQuestRepeatability.allCases, id: \.self) { r in
                    Text(r.rawValue).tag(r)
                }
            }
            .pickerStyle(.segmented)
        }
    }

    private var optionalSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Optional")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)

            VStack(alignment: .leading, spacing: 6) {
                Text("Suggested Time")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.secondary)
                TextField("e.g. ~10 min", text: $suggestedTime)
                    .textFieldStyle(.roundedBorder)
            }

            VStack(alignment: .leading, spacing: 6) {
                Text("Private Notes")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.secondary)
                TextField("Personal notes (only visible to you)", text: $notes)
                    .textFieldStyle(.roundedBorder)
            }
        }
        .padding(14)
        .background(Color(.secondarySystemGroupedBackground), in: .rect(cornerRadius: 14))
    }

    private func loadEditingData() {
        guard let quest = editingQuest else { return }
        title = quest.title
        questDescription = quest.description
        selectedPath = quest.path
        selectedDifficulty = quest.difficulty
        repeatability = quest.repeatability
        suggestedTime = quest.suggestedTime ?? ""
        notes = quest.notes ?? ""
    }

    private func postSaveSheet(_ quest: CustomQuest) -> some View {
        NavigationStack {
            VStack(spacing: 24) {
                VStack(spacing: 8) {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 48))
                        .foregroundStyle(.green)
                    Text("Side Quest Created!")
                        .font(.title2.weight(.bold))
                    Text(quest.title)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .padding(.top, 8)

                VStack(spacing: 12) {
                    Button {
                        let q = quest.toQuest()
                        if !appState.isQuestAlreadyActive(q.id) && appState.activeQuestCount < 5 {
                            appState.acceptQuest(q, mode: .solo)
                            addedToActive = true
                        }
                    } label: {
                        HStack(spacing: 12) {
                            Image(systemName: addedToActive ? "checkmark.circle.fill" : "bolt.fill")
                                .font(.title3)
                                .foregroundStyle(addedToActive ? .green : .orange)
                                .frame(width: 32)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(addedToActive ? "Added to Active Side Quests" : "Add to Active Side Quests")
                                    .font(.subheadline.weight(.semibold))
                                if !addedToActive {
                                    Text("\(appState.activeQuestCount)/5 slots used")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                            Spacer()
                            if !addedToActive {
                                Image(systemName: "chevron.right")
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(.tertiary)
                            }
                        }
                        .padding(14)
                        .background(
                            addedToActive ? Color.green.opacity(0.08) : Color(.secondarySystemGroupedBackground),
                            in: .rect(cornerRadius: 14)
                        )
                    }
                    .buttonStyle(.plain)
                    .disabled(addedToActive || appState.isQuestAlreadyActive(quest.toQuest().id) || appState.activeQuestCount >= 5)

                    Button {
                        showPostSaveOptions = false
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
                            showJourneyPicker = true
                        }
                    } label: {
                        HStack(spacing: 12) {
                            Image(systemName: addedToJourney ? "checkmark.circle.fill" : "map.fill")
                                .font(.title3)
                                .foregroundStyle(addedToJourney ? .green : .indigo)
                                .frame(width: 32)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(addedToJourney ? "Added to Quest" : "Add to Quest")
                                    .font(.subheadline.weight(.semibold))
                                Text(addedToJourney ? "Side quest scheduled" : "New or existing quest")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            if !addedToJourney {
                                Image(systemName: "chevron.right")
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(.tertiary)
                            }
                        }
                        .padding(14)
                        .background(
                            addedToJourney ? Color.green.opacity(0.08) : Color(.secondarySystemGroupedBackground),
                            in: .rect(cornerRadius: 14)
                        )
                    }
                    .buttonStyle(.plain)
                    .disabled(addedToJourney)
                }

                Spacer()

                Button {
                    showPostSaveOptions = false
                    dismiss()
                } label: {
                    Text("Done")
                        .font(.body.weight(.semibold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(.blue, in: .rect(cornerRadius: 14))
                        .foregroundStyle(.white)
                }
            }
            .padding(20)
            .presentationDetents([.medium])
            .presentationDragIndicator(.visible)
        }
    }

    private func journeyPickerSheet(_ quest: CustomQuest) -> some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    if !appState.activeJourneys.isEmpty {
                        VStack(alignment: .leading, spacing: 10) {
                            Text("Active Quests")
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(.secondary)

                            ForEach(appState.activeJourneys) { journey in
                                let alreadyHas = journey.questItems.contains { $0.questId == quest.toQuest().id }
                                Button {
                                    appState.addQuestToJourney(journeyId: journey.id, questId: quest.toQuest().id)
                                    addedToJourney = true
                                    showJourneyPicker = false
                                } label: {
                                    HStack(spacing: 12) {
                                        Image(systemName: "map.fill")
                                            .font(.title3)
                                            .foregroundStyle(.indigo)
                                            .frame(width: 36, height: 36)
                                            .background(.indigo.opacity(0.1), in: .rect(cornerRadius: 10))
                                        VStack(alignment: .leading, spacing: 2) {
                                            Text(journey.name)
                                                .font(.subheadline.weight(.semibold))
                                            Text("\(journey.questItems.count) quests · Day \(journey.currentDay)/\(journey.totalDays)")
                                                .font(.caption)
                                                .foregroundStyle(.secondary)
                                        }
                                        Spacer()
                                        if alreadyHas {
                                            Text("Already added")
                                                .font(.caption2.weight(.medium))
                                                .foregroundStyle(.secondary)
                                        } else {
                                            Image(systemName: "plus.circle.fill")
                                                .foregroundStyle(.indigo)
                                        }
                                    }
                                    .padding(12)
                                    .background(Color(.secondarySystemGroupedBackground), in: .rect(cornerRadius: 14))
                                }
                                .buttonStyle(.plain)
                                .disabled(alreadyHas)
                            }
                        }
                    }

                    Button {
                        showJourneyPicker = false
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
                            showCreateJourney = true
                        }
                    } label: {
                        HStack(spacing: 12) {
                            Image(systemName: "plus.circle.fill")
                                .font(.title3)
                                .foregroundStyle(.blue)
                                .frame(width: 36, height: 36)
                                .background(.blue.opacity(0.1), in: .rect(cornerRadius: 10))
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Create New Quest")
                                    .font(.subheadline.weight(.semibold))
                                Text("Start a new quest with this side quest")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            Image(systemName: "chevron.right")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.tertiary)
                        }
                        .padding(12)
                        .background(Color(.secondarySystemGroupedBackground), in: .rect(cornerRadius: 14))
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 20)
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("Add to Quest")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { showJourneyPicker = false }
                }
            }
        }
    }

    private func saveQuest() {
        if let existing = editingQuest {
            appState.updateCustomQuest(
                existing.id,
                title: title.trimmingCharacters(in: .whitespaces),
                description: questDescription.trimmingCharacters(in: .whitespaces),
                path: selectedPath,
                difficulty: selectedDifficulty,
                repeatability: repeatability,
                suggestedTime: suggestedTime,
                notes: notes
            )
            dismiss()
        } else {
            let quest = appState.createCustomQuest(
                title: title.trimmingCharacters(in: .whitespaces),
                description: questDescription.trimmingCharacters(in: .whitespaces),
                path: selectedPath,
                difficulty: selectedDifficulty,
                repeatability: repeatability,
                suggestedTime: suggestedTime,
                notes: notes
            )
            savedQuest = quest
            showPostSaveOptions = true
        }
    }
}
