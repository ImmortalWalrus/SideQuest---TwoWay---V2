import SwiftUI

struct TagSetupSheet: View {
    let appState: AppState
    @Environment(\.dismiss) private var dismiss
    @State private var selectedSkills: Set<UserSkill>
    @State private var selectedInterests: Set<UserInterest>
    @State private var page: Int = 0

    init(appState: AppState) {
        self.appState = appState
        _selectedSkills = State(initialValue: Set(appState.profile.selectedSkills))
        _selectedInterests = State(initialValue: Set(appState.profile.selectedInterests))
    }

    var body: some View {
        NavigationStack {
            Group {
                if page == 0 {
                    skillsPage
                } else {
                    interestsPage
                }
            }
            .navigationTitle(page == 0 ? "Skills" : "Interests")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    if page == 0 {
                        Button("Next") {
                            withAnimation(.spring(response: 0.4)) { page = 1 }
                        }
                        .fontWeight(.semibold)
                    } else {
                        Button("Save") {
                            appState.saveTagSelections(
                                skills: Array(selectedSkills),
                                interests: Array(selectedInterests)
                            )
                            dismiss()
                        }
                        .fontWeight(.semibold)
                    }
                }
            }
        }
    }

    private var skillsPage: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("What do you want to develop?")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    if !selectedSkills.isEmpty {
                        Text("\(selectedSkills.count) selected")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.purple)
                    }
                }
                .padding(.top, 4)

                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                    ForEach(UserSkill.allCases) { skill in
                        skillCard(skill: skill, isSelected: selectedSkills.contains(skill)) {
                            withAnimation(.spring(response: 0.3)) {
                                if selectedSkills.contains(skill) {
                                    selectedSkills.remove(skill)
                                } else {
                                    selectedSkills.insert(skill)
                                }
                            }
                        }
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 32)
        }
        .background(Color(.systemGroupedBackground))
    }

    private var interestsPage: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("What lights you up?")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    if !selectedInterests.isEmpty {
                        Text("\(selectedInterests.count) selected")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.blue)
                    }
                }
                .padding(.top, 4)

                LazyVGrid(columns: [GridItem(.adaptive(minimum: 100))], spacing: 10) {
                    ForEach(UserInterest.allCases) { interest in
                        interestChip(interest: interest, isSelected: selectedInterests.contains(interest)) {
                            withAnimation(.spring(response: 0.3)) {
                                if selectedInterests.contains(interest) {
                                    selectedInterests.remove(interest)
                                } else {
                                    selectedInterests.insert(interest)
                                }
                            }
                        }
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 32)
        }
        .background(Color(.systemGroupedBackground))
    }

    private func skillCard(skill: UserSkill, isSelected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Image(systemName: skill.icon)
                        .font(.title2)
                        .foregroundStyle(isSelected ? skill.color : skill.color.opacity(0.5))
                    Spacer()
                    if isSelected {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(skill.color)
                            .font(.subheadline)
                    }
                }
                Text(skill.rawValue)
                    .font(.subheadline.weight(.bold))
                Text(skill.description)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background {
                RoundedRectangle(cornerRadius: 14)
                    .fill(isSelected ? skill.color.opacity(0.1) : Color(.secondarySystemGroupedBackground))
                    .overlay {
                        RoundedRectangle(cornerRadius: 14)
                            .strokeBorder(isSelected ? skill.color.opacity(0.4) : Color.clear, lineWidth: 1.5)
                    }
            }
        }
        .buttonStyle(.plain)
        .sensoryFeedback(.selection, trigger: isSelected)
    }

    private func interestChip(interest: UserInterest, isSelected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: interest.icon)
                    .font(.callout)
                    .foregroundStyle(isSelected ? .white : interest.color)
                Text(interest.rawValue)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(isSelected ? .white : .primary)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .frame(maxWidth: .infinity)
            .background {
                Capsule()
                    .fill(isSelected ? interest.color : Color(.secondarySystemGroupedBackground))
                    .overlay {
                        Capsule()
                            .strokeBorder(isSelected ? interest.color : Color(.separator).opacity(0.4), lineWidth: 1)
                    }
            }
        }
        .buttonStyle(.plain)
        .sensoryFeedback(.selection, trigger: isSelected)
    }
}
