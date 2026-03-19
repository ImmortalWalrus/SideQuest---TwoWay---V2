import SwiftUI

struct GoalsView: View {
    let appState: AppState
    @State private var selectedQuest: Quest?
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Group {
                if appState.savedQuests.isEmpty {
                    emptyState
                } else {
                    questList
                }
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("Favorites")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .sheet(item: $selectedQuest) { quest in
                QuestDetailView(quest: quest, appState: appState)
            }
        }
    }

    private var questList: some View {
        List {
            Section {
                ForEach(appState.savedQuests) { quest in
                    goalRow(quest: quest)
                        .listRowBackground(Color.clear)
                        .listRowSeparator(.hidden)
                        .listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 4, trailing: 8))
                }
                .onMove { from, to in
                    appState.moveSavedQuest(from: from, to: to)
                }
            } header: {
                header
                    .textCase(nil)
                    .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 4, trailing: 16))
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .background(Color(.systemGroupedBackground))
        .environment(\.editMode, .constant(.active))
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("\(appState.savedQuests.count) saved \(appState.savedQuests.count == 1 ? "quest" : "quests")")
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.secondary)
            Text("Tap any quest to accept it when you're ready.")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
        .padding(.top, 4)
    }

    private func goalRow(quest: Quest) -> some View {
        let pathColor = PathColorHelper.color(for: quest.path)
        let isActive = appState.activeInstances.contains { $0.quest.id == quest.id && $0.state.isActive }

        return Button { selectedQuest = quest } label: {
            HStack(spacing: 12) {
                RoundedRectangle(cornerRadius: 4)
                    .fill(pathColor.gradient)
                    .frame(width: 4)

                VStack(alignment: .leading, spacing: 5) {
                    HStack(spacing: 6) {
                        PathBadgeView(path: quest.path, compact: true)
                        DifficultyBadge(difficulty: quest.difficulty)
                        Spacer()
                        if isActive {
                            Text("Active")
                                .font(.system(size: 10, weight: .semibold))
                                .foregroundStyle(.green)
                                .padding(.horizontal, 7)
                                .padding(.vertical, 3)
                                .background(.green.opacity(0.12), in: Capsule())
                        }
                        Button {
                            withAnimation(.spring(response: 0.3, dampingFraction: 0.6)) {
                                appState.toggleSavedQuest(quest.id)
                            }
                        } label: {
                            Image(systemName: "heart.fill")
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundStyle(.red)
                        }
                        .buttonStyle(.plain)
                    }

                    Text(quest.title)
                        .font(.headline)

                    Text(quest.description)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)

                    HStack(spacing: 12) {
                        Label("\(quest.xpReward) XP", systemImage: "bolt.fill")
                            .font(.caption.weight(.medium))
                            .foregroundStyle(.orange)
                        Label("\(quest.goldReward)", systemImage: "dollarsign.circle.fill")
                            .font(.caption.weight(.medium))
                            .foregroundStyle(.yellow)
                        if quest.diamondReward > 0 {
                            Label("\(quest.diamondReward)", systemImage: "diamond.fill")
                                .font(.caption.weight(.medium))
                                .foregroundStyle(.cyan)
                        }
                    }
                }
            }
            .padding(12)
            .background(Color(.secondarySystemGroupedBackground), in: .rect(cornerRadius: 12))
        }
        .buttonStyle(.plain)
    }

    private var emptyState: some View {
        VStack(spacing: 20) {
            ZStack {
                Circle()
                    .fill(Color(.secondarySystemGroupedBackground))
                    .frame(width: 88, height: 88)
                Image(systemName: "heart")
                    .font(.system(size: 36, weight: .light))
                    .foregroundStyle(.secondary)
            }

            VStack(spacing: 8) {
                Text("No Favorites Yet")
                    .font(.title3.weight(.bold))
                Text("Tap the heart icon on any quest to save it here for later.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.horizontal, 40)
    }
}
