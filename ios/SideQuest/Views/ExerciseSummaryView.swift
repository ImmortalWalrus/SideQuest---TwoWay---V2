import SwiftUI

struct ExerciseSummaryView: View {
    let session: ExerciseSession
    let quest: Quest
    let onSubmit: () -> Void
    let onDiscard: () -> Void

    private var pathColor: Color { PathColorHelper.color(for: quest.path) }

    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                resultHeader
                statsSection
                actionButtons
            }
            .padding(16)
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle("Session Summary")
        .navigationBarTitleDisplayMode(.inline)
    }

    private var resultHeader: some View {
        VStack(spacing: 16) {
            Image(systemName: session.goalReached ? "checkmark.circle.fill" : "xmark.circle.fill")
                .font(.system(size: 64))
                .foregroundStyle(session.goalReached ? .green : .orange)

            Text(session.goalReached ? "Goal Reached!" : "Not Quite")
                .font(.title.weight(.bold))

            switch session.exerciseType {
            case .pushUp:
                Text("\(session.repsCompleted) of \(session.targetReps) reps")
                    .font(.title3)
                    .foregroundStyle(.secondary)
            case .plank, .wallSit:
                Text("\(formatDuration(session.holdDurationSeconds)) of \(formatDuration(session.targetHoldSeconds))")
                    .font(.title3)
                    .foregroundStyle(.secondary)
            case .jumpRope:
                Text("\(session.jumpCount) of \(session.targetJumps) jumps")
                    .font(.title3)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 20)
    }

    private var statsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Session Stats")
                .font(.headline)

            HStack(spacing: 0) {
                switch session.exerciseType {
                case .pushUp:
                    statItem(
                        icon: "figure.strengthtraining.traditional",
                        value: "\(session.repsCompleted)",
                        label: "Reps"
                    )
                case .plank, .wallSit:
                    statItem(
                        icon: "timer",
                        value: formatDuration(session.holdDurationSeconds),
                        label: "Hold Time"
                    )
                case .jumpRope:
                    statItem(
                        icon: "figure.jumprope",
                        value: "\(session.jumpCount)",
                        label: "Jumps"
                    )
                }

                Divider().frame(height: 44)

                if let start = session.startedAt, let end = session.endedAt {
                    statItem(
                        icon: "clock",
                        value: formatDuration(end.timeIntervalSince(start)),
                        label: "Total Time"
                    )
                    Divider().frame(height: 44)
                }

                statItem(
                    icon: session.goalReached ? "checkmark.shield.fill" : "xmark.shield.fill",
                    value: session.goalReached ? "Yes" : "No",
                    label: "Goal Met"
                )
            }
            .padding(.vertical, 16)
            .background(Color(.secondarySystemGroupedBackground), in: .rect(cornerRadius: 14))

            if session.exerciseType == .jumpRope {
                jumpRopeExtras
            }
        }
    }

    @ViewBuilder
    private var jumpRopeExtras: some View {
        HStack(spacing: 0) {
            statItem(
                icon: "flame.fill",
                value: "\(session.bestStreakJumps)",
                label: "Best Streak"
            )
            Divider().frame(height: 44)
            statItem(
                icon: "waveform.path",
                value: "\(session.onBeatJumps)",
                label: "On Beat"
            )
            if session.bpmUsed > 0 {
                Divider().frame(height: 44)
                statItem(
                    icon: "metronome.fill",
                    value: "\(session.bpmUsed)",
                    label: "BPM"
                )
            }
        }
        .padding(.vertical, 16)
        .background(Color(.secondarySystemGroupedBackground), in: .rect(cornerRadius: 14))
    }

    private func statItem(icon: String, value: String, label: String) -> some View {
        VStack(spacing: 6) {
            Image(systemName: icon)
                .font(.caption)
                .foregroundStyle(pathColor)
            Text(value)
                .font(.headline.monospacedDigit())
            Text(label)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
    }

    private var actionButtons: some View {
        VStack(spacing: 12) {
            Button(action: onSubmit) {
                Label("Submit", systemImage: "paperplane.fill")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 6)
            }
            .buttonStyle(.borderedProminent)
            .tint(pathColor)

            Button(action: onDiscard) {
                Label("Discard", systemImage: "trash")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 6)
            }
            .buttonStyle(.bordered)
        }
        .padding(.top, 8)
    }

    private func formatDuration(_ seconds: TimeInterval) -> String {
        let total = Int(max(0, seconds))
        let m = total / 60
        let s = total % 60
        return String(format: "%d:%02d", m, s)
    }
}
