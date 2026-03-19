import SwiftUI

struct MyQuestsView: View {
    let appState: AppState
    @Environment(\.dismiss) private var dismiss
    @State private var showCreateQuest: Bool = false
    @State private var selectedQuest: CustomQuest?
    @State private var editingQuest: CustomQuest?
    @State private var questToDelete: CustomQuest?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 12) {
                    createButton

                    if appState.customQuests.isEmpty {
                        emptyState
                    } else {
                        ForEach(appState.customQuests) { quest in
                            Button {
                                selectedQuest = quest
                            } label: {
                                customQuestCard(quest)
                            }
                            .buttonStyle(.plain)
                            .contextMenu {
                                if quest.canEdit {
                                    Button {
                                        editingQuest = quest
                                    } label: {
                                        Label("Edit", systemImage: "pencil")
                                    }
                                }
                                Button(role: .destructive) {
                                    questToDelete = quest
                                } label: {
                                    Label("Delete", systemImage: "trash")
                                }
                            }
                        }
                    }
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 20)
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("My Side Quests")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .sheet(isPresented: $showCreateQuest) {
                CreateCustomQuestView(appState: appState)
            }
            .sheet(item: $selectedQuest) { quest in
                CustomQuestDetailView(customQuest: quest, appState: appState)
            }
            .sheet(item: $editingQuest) { quest in
                CreateCustomQuestView(appState: appState, editingQuest: quest)
            }
            .alert("Delete Side Quest?", isPresented: Binding(
                get: { questToDelete != nil },
                set: { if !$0 { questToDelete = nil } }
            )) {
                Button("Delete", role: .destructive) {
                    if let quest = questToDelete {
                        withAnimation(.snappy) {
                            appState.deleteCustomQuest(quest.id)
                        }
                        questToDelete = nil
                    }
                }
                Button("Cancel", role: .cancel) { questToDelete = nil }
            } message: {
                Text("This side quest will be permanently removed.")
            }
        }
    }

    private var createButton: some View {
        Button { showCreateQuest = true } label: {
            HStack(spacing: 10) {
                Image(systemName: "plus.circle.fill")
                    .font(.title3)
                    .foregroundStyle(.indigo)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Create Custom Side Quest")
                        .font(.subheadline.weight(.semibold))
                    Text("Personal open play side quest")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.tertiary)
            }
            .padding(14)
            .background(Color(.secondarySystemGroupedBackground), in: .rect(cornerRadius: 14))
            .overlay(
                RoundedRectangle(cornerRadius: 14)
                    .strokeBorder(.indigo.opacity(0.2), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "sparkle.magnifyingglass")
                .font(.system(size: 40))
                .foregroundStyle(.tertiary)
            Text("No Custom Side Quests Yet")
                .font(.headline)
                .foregroundStyle(.secondary)
            Text("Create your own personal side quests to track activities that matter to you.")
                .font(.subheadline)
                .foregroundStyle(.tertiary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 40)
    }

    private func customQuestCard(_ quest: CustomQuest) -> some View {
        let pathColor = PathColorHelper.color(for: quest.path)
        return VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: quest.path.iconName)
                    .font(.caption)
                    .foregroundStyle(pathColor)
                    .frame(width: 28, height: 28)
                    .background(pathColor.opacity(0.12), in: Circle())

                VStack(alignment: .leading, spacing: 2) {
                    Text(quest.title)
                        .font(.subheadline.weight(.semibold))
                        .lineLimit(1)
                    HStack(spacing: 6) {
                        Text("Custom (Open)")
                            .font(.caption2.weight(.medium))
                            .foregroundStyle(.indigo)
                        Text("·")
                            .foregroundStyle(.tertiary)
                        Text(quest.difficulty.rawValue)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                        Text("·")
                            .foregroundStyle(.tertiary)
                        Text(quest.repeatability.rawValue)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }

                Spacer()

                statusBadge(quest)
            }

            HStack(spacing: 12) {
                Label("\(quest.toQuest().xpReward) XP", systemImage: "bolt.fill")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.orange)
                Label("\(quest.toQuest().goldReward)", systemImage: "dollarsign.circle.fill")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.yellow)
                if quest.completionCount > 0 {
                    Spacer()
                    Text("\(quest.completionCount)x completed")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            }
        }
        .padding(14)
        .background(
            .linearGradient(
                colors: [pathColor.opacity(0.06), Color(.secondarySystemGroupedBackground)],
                startPoint: .leading,
                endPoint: .trailing
            ),
            in: .rect(cornerRadius: 14)
        )
    }

    @ViewBuilder
    private func statusBadge(_ quest: CustomQuest) -> some View {
        switch quest.submissionStatus {
        case .pending:
            HStack(spacing: 3) {
                Image(systemName: "clock.fill")
                    .font(.system(size: 9))
                Text("Pending")
                    .font(.caption2.weight(.bold))
            }
            .foregroundStyle(.orange)
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .background(.orange.opacity(0.12), in: Capsule())
        case .approved:
            HStack(spacing: 3) {
                Image(systemName: "globe")
                    .font(.system(size: 9))
                Text("Published")
                    .font(.caption2.weight(.bold))
            }
            .foregroundStyle(.green)
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .background(.green.opacity(0.12), in: Capsule())
        case .rejected:
            HStack(spacing: 3) {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 9))
                Text("Rejected")
                    .font(.caption2.weight(.bold))
            }
            .foregroundStyle(.red)
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .background(.red.opacity(0.12), in: Capsule())
        case .draft:
            HStack(spacing: 3) {
                Image(systemName: "person.fill")
                    .font(.system(size: 9))
                Text("Only you")
                    .font(.caption2.weight(.bold))
            }
            .foregroundStyle(.secondary)
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .background(Color(.quaternarySystemFill), in: Capsule())
        }
    }
}
