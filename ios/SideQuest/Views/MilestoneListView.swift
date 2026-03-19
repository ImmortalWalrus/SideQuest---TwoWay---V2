import SwiftUI

struct MilestoneListView: View {
    let appState: AppState
    let path: QuestPath
    @Environment(\.dismiss) private var dismiss
    @State private var searchText: String = ""
    @State private var selectedMilestone: Milestone?

    private var pathColor: Color {
        PathColorHelper.color(for: path)
    }

    private var filteredMilestones: [Milestone] {
        let pathMilestones = appState.milestones.filter { $0.path == path }
        guard !searchText.isEmpty else { return pathMilestones }
        return pathMilestones.filter { $0.title.localizedStandardContains(searchText) }
    }

    private var pinnedMilestones: [Milestone] {
        filteredMilestones.filter { $0.isPinned }
    }

    private var activeMilestones: [Milestone] {
        filteredMilestones.filter { !$0.isCompleted && !$0.isPinned && $0.currentCount > 0 }
    }

    private var newMilestones: [Milestone] {
        filteredMilestones.filter { !$0.isCompleted && !$0.isPinned && $0.currentCount == 0 }
    }

    private var completedMilestones: [Milestone] {
        filteredMilestones.filter { $0.isCompleted }
    }

    var body: some View {
        NavigationStack {
            List {
                if !pinnedMilestones.isEmpty {
                    Section("Pinned") {
                        ForEach(pinnedMilestones) { milestone in
                            MilestoneRow(milestone: milestone, pathColor: pathColor)
                        }
                    }
                }

                if !activeMilestones.isEmpty {
                    Section("In Progress") {
                        ForEach(activeMilestones) { milestone in
                            MilestoneRow(milestone: milestone, pathColor: pathColor)
                        }
                    }
                }

                if !newMilestones.isEmpty {
                    Section("Not Started") {
                        ForEach(newMilestones) { milestone in
                            MilestoneRow(milestone: milestone, pathColor: pathColor)
                        }
                    }
                }

                if !completedMilestones.isEmpty {
                    Section("Completed") {
                        ForEach(completedMilestones) { milestone in
                            MilestoneRow(milestone: milestone, pathColor: pathColor)
                        }
                    }
                }
            }
            .searchable(text: $searchText, prompt: "Search milestones...")
            .navigationTitle("Milestones")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}

struct MilestoneRow: View {
    let milestone: Milestone
    let pathColor: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                if milestone.isPinned {
                    Image(systemName: "pin.fill")
                        .font(.caption)
                        .foregroundStyle(.orange)
                }
                Text(milestone.title)
                    .font(.subheadline.weight(.semibold))
                Spacer()
                if milestone.isCompleted {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                }
            }

            Text(milestone.description)
                .font(.caption)
                .foregroundStyle(.secondary)

            HStack {
                ProgressView(value: Double(milestone.currentCount), total: Double(milestone.requiredCount))
                    .tint(milestone.isCompleted ? .green : pathColor)
                Text("\(milestone.currentCount)/\(milestone.requiredCount)")
                    .font(.caption.monospacedDigit().weight(.medium))
                    .foregroundStyle(.secondary)
            }

            if milestone.requiresUniqueLocations {
                Label("Unique locations: \(milestone.uniqueLocationsAchieved)/\(milestone.uniqueLocationsTarget)", systemImage: "location.fill")
                    .font(.caption)
                    .foregroundStyle(.green)
            }

            HStack(spacing: 8) {
                Label("\(milestone.rewardXP) XP", systemImage: "bolt.fill")
                    .font(.caption2.weight(.medium))
                    .foregroundStyle(.orange)
                Label("\(milestone.rewardGold) Gold", systemImage: "dollarsign.circle.fill")
                    .font(.caption2.weight(.medium))
                    .foregroundStyle(.yellow)
            }
        }
        .padding(.vertical, 4)
    }
}
