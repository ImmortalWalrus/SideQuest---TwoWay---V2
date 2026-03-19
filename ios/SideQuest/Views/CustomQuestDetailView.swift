import SwiftUI

struct CustomQuestDetailView: View {
    let customQuest: CustomQuest
    let appState: AppState
    @Environment(\.dismiss) private var dismiss
    @State private var showSubmitConfirmation: Bool = false
    @State private var completionConfirmed: Bool = false
    @State private var showEditSheet: Bool = false

    private var pathColor: Color {
        PathColorHelper.color(for: customQuest.path)
    }

    private var liveQuest: CustomQuest {
        appState.customQuests.first(where: { $0.id == customQuest.id }) ?? customQuest
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    headerSection
                    rewardSection
                    descriptionSection
                    detailsSection
                    if let notes = liveQuest.notes, !notes.isEmpty {
                        notesSection(notes)
                    }
                    submissionStatusSection
                    actionSection
                }
                .padding(16)
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("Custom Side Quest")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
                if liveQuest.canEdit {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button {
                            showEditSheet = true
                        } label: {
                            Image(systemName: "pencil")
                        }
                    }
                }
            }
            .alert("Side Quest Logged!", isPresented: $completionConfirmed) {
                Button("Done") { dismiss() }
            } message: {
                let quest = liveQuest.toQuest()
                Text("+\(quest.xpReward) XP, +\(quest.goldReward) Gold")
            }
            .sheet(isPresented: $showSubmitConfirmation) {
                SubmitToCommunitySheet(customQuest: liveQuest, appState: appState)
            }
            .sheet(isPresented: $showEditSheet) {
                CreateCustomQuestView(appState: appState, editingQuest: liveQuest)
            }
        }
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
    }

    private var headerSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                PathBadgeView(path: liveQuest.path)
                DifficultyBadge(difficulty: liveQuest.difficulty)

                HStack(spacing: 4) {
                    Image(systemName: "person.fill")
                        .font(.system(size: 9))
                    Text("Custom (Open)")
                        .font(.caption2.weight(.bold))
                }
                .foregroundStyle(.indigo)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(.indigo.opacity(0.12), in: Capsule())

                Spacer()
            }

            Text(liveQuest.title)
                .font(.title.weight(.bold))

            HStack(spacing: 16) {
                if liveQuest.completionCount > 0 {
                    Label("\(liveQuest.completionCount) by you", systemImage: "person.fill")
                        .font(.subheadline)
                        .foregroundStyle(pathColor)
                }
                if liveQuest.isPublished {
                    Label("Published", systemImage: "globe")
                        .font(.subheadline)
                        .foregroundStyle(.green)
                }
            }
        }
    }

    private var rewardSection: some View {
        let quest = liveQuest.toQuest()
        return HStack(spacing: 0) {
            VStack(spacing: 4) {
                Image(systemName: "bolt.fill")
                    .font(.title3)
                    .foregroundStyle(.orange)
                Text("\(quest.xpReward)")
                    .font(.headline.monospacedDigit())
                Text("XP")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity)

            Divider().frame(height: 40)

            VStack(spacing: 4) {
                Image(systemName: "dollarsign.circle.fill")
                    .font(.title3)
                    .foregroundStyle(.yellow)
                Text("\(quest.goldReward)")
                    .font(.headline.monospacedDigit())
                Text("Gold")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity)
        }
        .padding(.vertical, 16)
        .background(Color(.secondarySystemGroupedBackground), in: .rect(cornerRadius: 14))
    }

    private var descriptionSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Description")
                .font(.headline)
            Text(liveQuest.description)
                .font(.body)
                .foregroundStyle(.secondary)
        }
    }

    private var detailsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Details")
                .font(.headline)

            HStack(spacing: 16) {
                Label(liveQuest.repeatability.rawValue, systemImage: "repeat")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                if let time = liveQuest.suggestedTime, !time.isEmpty {
                    Label(time, systemImage: "clock")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }

            HStack(spacing: 8) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
                    .font(.caption)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Open Play Only")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(.orange)
                    Text("Does not count toward Verified, Master, Events, or Milestones.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(10)
            .background(.orange.opacity(0.08), in: .rect(cornerRadius: 10))
        }
    }

    private func notesSection(_ notes: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: "lock.fill")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text("Private Notes")
                    .font(.headline)
            }
            Text(notes)
                .font(.body)
                .foregroundStyle(.secondary)
        }
        .padding(12)
        .background(Color(.secondarySystemGroupedBackground), in: .rect(cornerRadius: 12))
    }

    private var submissionStatusSection: some View {
        Group {
            switch liveQuest.submissionStatus {
            case .pending:
                HStack(spacing: 10) {
                    ProgressView()
                        .scaleEffect(0.8)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Under Review")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.orange)
                        Text("Your side quest is being reviewed for inclusion in the global library.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(.orange.opacity(0.08), in: .rect(cornerRadius: 12))
            case .approved:
                HStack(spacing: 10) {
                    Image(systemName: "checkmark.seal.fill")
                        .font(.title3)
                        .foregroundStyle(.green)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Published to Community")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.green)
                        Text("Created by @\(liveQuest.authorUsername)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(.green.opacity(0.08), in: .rect(cornerRadius: 12))
            case .rejected:
                HStack(spacing: 10) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.title3)
                        .foregroundStyle(.red)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Not Approved")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.red)
                        if let reason = liveQuest.rejectionReason {
                            Text("Reason: \(reason.rawValue)")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Text("You can edit and resubmit.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(.red.opacity(0.08), in: .rect(cornerRadius: 12))
            case .draft:
                EmptyView()
            }
        }
    }

    private var actionSection: some View {
        VStack(spacing: 12) {
            Button {
                appState.completeCustomQuest(liveQuest)
                completionConfirmed = true
            } label: {
                Label("Log Completion", systemImage: "checkmark.circle.fill")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .tint(pathColor)
            .sensoryFeedback(.success, trigger: completionConfirmed)

            Text("Personal logging — no verification required")
                .font(.caption)
                .foregroundStyle(.secondary)

            if liveQuest.canSubmit {
                Button {
                    showSubmitConfirmation = true
                } label: {
                    Label("Submit to Community", systemImage: "globe")
                        .font(.subheadline.weight(.semibold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .background(Color(.tertiarySystemGroupedBackground), in: .rect(cornerRadius: 10))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.top, 8)
    }
}

struct SubmitToCommunitySheet: View {
    let customQuest: CustomQuest
    let appState: AppState
    @Environment(\.dismiss) private var dismiss
    @State private var agreedToTerms: Bool = false
    @State private var submitted: Bool = false

    var body: some View {
        NavigationStack {
            VStack(spacing: 20) {
                VStack(spacing: 12) {
                    Image(systemName: "globe")
                        .font(.system(size: 40))
                        .foregroundStyle(.indigo)

                    Text("Submit Side Quest")
                        .font(.title2.weight(.bold))
                }

                VStack(alignment: .leading, spacing: 10) {
                    bulletPoint("Your quest will be reviewed by moderators.")
                    bulletPoint("If approved, it will appear in the global Side Quest Library as an Open Play side quest.")
                    bulletPoint("You will be credited as the author on the side quest.")
                    bulletPoint("Do not submit dangerous or harmful challenges.")
                }
                .padding(14)
                .background(Color(.secondarySystemGroupedBackground), in: .rect(cornerRadius: 14))

                VStack(alignment: .leading, spacing: 8) {
                    Text("SIDE QUEST PREVIEW")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)

                    HStack(spacing: 10) {
                        Image(systemName: customQuest.path.iconName)
                            .font(.caption)
                            .foregroundStyle(PathColorHelper.color(for: customQuest.path))
                            .frame(width: 28, height: 28)
                            .background(PathColorHelper.color(for: customQuest.path).opacity(0.12), in: Circle())
                        VStack(alignment: .leading, spacing: 2) {
                            Text(customQuest.title)
                                .font(.subheadline.weight(.semibold))
                            Text("\(customQuest.path.rawValue) · \(customQuest.difficulty.rawValue) · Open")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .padding(12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color(.tertiarySystemGroupedBackground), in: .rect(cornerRadius: 10))
                }

                Button {
                    agreedToTerms.toggle()
                } label: {
                    HStack(spacing: 10) {
                        Image(systemName: agreedToTerms ? "checkmark.square.fill" : "square")
                            .font(.title3)
                            .foregroundStyle(agreedToTerms ? .indigo : .secondary)
                        Text("I understand and agree to the submission terms.")
                            .font(.subheadline)
                            .foregroundStyle(.primary)
                            .multilineTextAlignment(.leading)
                        Spacer()
                    }
                }
                .buttonStyle(.plain)

                Spacer()

                HStack(spacing: 12) {
                    Button {
                        dismiss()
                    } label: {
                        Text("Cancel")
                            .font(.subheadline.weight(.semibold))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                            .background(Color(.tertiarySystemGroupedBackground), in: .rect(cornerRadius: 12))
                    }
                    .buttonStyle(.plain)

                    Button {
                        appState.submitCustomQuestForReview(customQuest.id)
                        submitted = true
                        dismiss()
                    } label: {
                        Text("Submit")
                            .font(.subheadline.weight(.semibold))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                            .background(agreedToTerms ? Color.indigo : Color(.tertiarySystemFill), in: .rect(cornerRadius: 12))
                            .foregroundStyle(agreedToTerms ? .white : .secondary)
                    }
                    .buttonStyle(.plain)
                    .disabled(!agreedToTerms)
                }
            }
            .padding(16)
            .navigationTitle("Submit to Community")
            .navigationBarTitleDisplayMode(.inline)
        }
        .presentationDetents([.large])
    }

    private func bulletPoint(_ text: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Circle()
                .fill(.secondary)
                .frame(width: 5, height: 5)
                .padding(.top, 6)
            Text(text)
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
    }
}
