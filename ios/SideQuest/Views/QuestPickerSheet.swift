import SwiftUI

struct QuestPickerSheet: View {
    let path: QuestPath
    let allQuests: [Quest]
    let pathColor: Color
    let onSelect: (Quest) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var selectedDifficulty: QuestDifficulty?

    private var filteredQuests: [Quest] {
        let pathQuests = allQuests.filter { $0.path == path && $0.type == .verified }
        if let diff = selectedDifficulty {
            return pathQuests.filter { $0.difficulty == diff }
        }
        return pathQuests
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    difficultyFilter

                    ForEach(filteredQuests) { quest in
                        Button {
                            onSelect(quest)
                            dismiss()
                        } label: {
                            QuestCardView(quest: quest)
                        }
                        .buttonStyle(.plain)
                    }

                    if filteredQuests.isEmpty {
                        VStack(spacing: 12) {
                            Image(systemName: "scroll")
                                .font(.largeTitle)
                                .foregroundStyle(.secondary)
                            Text("No quests found")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 40)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 20)
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("Pick a Challenge")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
    }

    private var difficultyFilter: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                FilterChip(label: "All", isSelected: selectedDifficulty == nil) {
                    withAnimation(.spring(response: 0.3)) { selectedDifficulty = nil }
                }
                ForEach(QuestDifficulty.allCases, id: \.rawValue) { diff in
                    FilterChip(label: diff.rawValue, isSelected: selectedDifficulty == diff) {
                        withAnimation(.spring(response: 0.3)) { selectedDifficulty = diff }
                    }
                }
            }
        }
        .contentMargins(.horizontal, 0)
    }
}

struct FilterChip: View {
    let label: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(label)
                .font(.caption.weight(.semibold))
                .padding(.horizontal, 14)
                .padding(.vertical, 7)
                .background(isSelected ? Color.blue : Color(.secondarySystemGroupedBackground), in: Capsule())
                .foregroundStyle(isSelected ? .white : .primary)
        }
        .buttonStyle(.plain)
    }
}
