import SwiftUI

struct QuestSubmissionReviewCard: View {
    let submission: CustomQuest
    let appState: AppState
    @State private var showRejectPicker: Bool = false
    @State private var selectedReason: SubmissionRejectionReason = .tooVague

    private var pathColor: Color {
        PathColorHelper.color(for: submission.path)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                Image(systemName: submission.path.iconName)
                    .font(.caption)
                    .foregroundStyle(pathColor)
                    .frame(width: 28, height: 28)
                    .background(pathColor.opacity(0.12), in: Circle())

                VStack(alignment: .leading, spacing: 2) {
                    Text(submission.title)
                        .font(.subheadline.weight(.semibold))
                    HStack(spacing: 6) {
                        Text(submission.path.rawValue)
                        Text("·")
                        Text(submission.difficulty.rawValue)
                        Text("·")
                        Text("Open")
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }

                Spacer()

                Text("by @\(submission.authorUsername)")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }

            Text(submission.description)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(3)

            if let time = submission.suggestedTime, !time.isEmpty {
                Label(time, systemImage: "clock")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }

            if showRejectPicker {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Rejection Reason")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                    ForEach(SubmissionRejectionReason.allCases, id: \.self) { reason in
                        Button {
                            selectedReason = reason
                        } label: {
                            HStack(spacing: 8) {
                                Image(systemName: selectedReason == reason ? "circle.inset.filled" : "circle")
                                    .font(.caption)
                                    .foregroundStyle(selectedReason == reason ? .red : .secondary)
                                Text(reason.rawValue)
                                    .font(.caption)
                                    .foregroundStyle(.primary)
                            }
                        }
                        .buttonStyle(.plain)
                    }
                    HStack(spacing: 8) {
                        Button {
                            appState.rejectSubmittedQuest(submission.id, reason: selectedReason)
                        } label: {
                            Text("Confirm Reject")
                                .font(.caption.weight(.bold))
                                .padding(.horizontal, 12)
                                .padding(.vertical, 6)
                                .background(.red, in: Capsule())
                                .foregroundStyle(.white)
                        }
                        .buttonStyle(.plain)

                        Button {
                            withAnimation(.snappy) { showRejectPicker = false }
                        } label: {
                            Text("Cancel")
                                .font(.caption.weight(.medium))
                                .padding(.horizontal, 12)
                                .padding(.vertical, 6)
                                .background(Color(.quaternarySystemFill), in: Capsule())
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(10)
                .background(Color(.tertiarySystemGroupedBackground), in: .rect(cornerRadius: 10))
            } else {
                HStack(spacing: 8) {
                    Button {
                        appState.approveSubmittedQuest(submission.id)
                    } label: {
                        Label("Approve", systemImage: "checkmark.circle.fill")
                            .font(.caption.weight(.bold))
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(.green, in: Capsule())
                            .foregroundStyle(.white)
                    }
                    .buttonStyle(.plain)

                    Button {
                        withAnimation(.snappy) { showRejectPicker = true }
                    } label: {
                        Label("Reject", systemImage: "xmark.circle.fill")
                            .font(.caption.weight(.bold))
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(.red.opacity(0.12), in: Capsule())
                            .foregroundStyle(.red)
                    }
                    .buttonStyle(.plain)

                    Spacer()

                    if let date = submission.submittedAt {
                        Text(date, style: .relative)
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }
                }
            }
        }
        .padding(14)
        .background(Color(.secondarySystemGroupedBackground), in: .rect(cornerRadius: 14))
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .strokeBorder(.orange.opacity(0.2), lineWidth: 1)
        )
    }
}
