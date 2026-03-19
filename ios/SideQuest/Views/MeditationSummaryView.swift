import SwiftUI

struct MeditationSummaryView: View {
    let session: MeditationSession
    let quest: Quest
    let onSubmit: () -> Void
    let onDiscard: () -> Void

    private var pathColor: Color { PathColorHelper.color(for: quest.path) }

    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                resultHeader
                statsSection
                integritySection
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

            Text("\(formatDuration(session.meditationDurationSeconds)) of \(formatDuration(session.targetDurationSeconds))")
                .font(.title3)
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 20)
    }

    private var statsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Session Stats")
                .font(.headline)

            HStack(spacing: 0) {
                statItem(
                    icon: "timer",
                    value: formatDuration(session.meditationDurationSeconds),
                    label: "Meditation"
                )

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
                    icon: "eye.slash.fill",
                    value: "\(Int(session.eyesClosedRatio * 100))%",
                    label: "Eyes Closed"
                )
            }
            .padding(.vertical, 16)
            .background(Color(.secondarySystemGroupedBackground), in: .rect(cornerRadius: 14))

            HStack(spacing: 0) {
                statItem(
                    icon: "faceid",
                    value: "\(Int(session.faceDetectionRatio * 100))%",
                    label: "Face Tracked"
                )

                Divider().frame(height: 44)

                statItem(
                    icon: "hand.raised.fill",
                    value: "\(Int(session.stillnessRatio * 100))%",
                    label: "Stillness"
                )
            }
            .padding(.vertical, 16)
            .background(Color(.secondarySystemGroupedBackground), in: .rect(cornerRadius: 14))
        }
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

    private var integritySection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Integrity Check")
                .font(.headline)

            HStack(spacing: 0) {
                integrityItem(
                    label: "Face Detection",
                    value: "\(Int(session.faceDetectionRatio * 100))%",
                    isOK: session.faceDetectionRatio >= 0.5
                )
                Divider().frame(height: 44)
                integrityItem(
                    label: "Eyes Closed",
                    value: "\(Int(session.eyesClosedRatio * 100))%",
                    isOK: session.eyesClosedRatio >= 0.6
                )
                Divider().frame(height: 44)
                integrityItem(
                    label: "Status",
                    value: session.isValid ? "Valid" : "Flagged",
                    isOK: session.isValid
                )
            }
            .padding(.vertical, 12)
            .background(Color(.secondarySystemGroupedBackground), in: .rect(cornerRadius: 14))

            if !session.integrityFlags.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(session.integrityFlags, id: \.self) { flag in
                        Label(flagDescription(flag), systemImage: "exclamationmark.triangle.fill")
                            .font(.caption)
                            .foregroundStyle(.orange)
                    }
                }
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.orange.opacity(0.08), in: .rect(cornerRadius: 10))
            }

            if session.isValid {
                Label("All integrity checks passed", systemImage: "checkmark.shield.fill")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.green)
            }
        }
    }

    private func integrityItem(label: String, value: String, isOK: Bool) -> some View {
        VStack(spacing: 4) {
            Image(systemName: isOK ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                .foregroundStyle(isOK ? .green : .orange)
            Text(value)
                .font(.subheadline.weight(.bold))
            Text(label)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
    }

    private var actionButtons: some View {
        VStack(spacing: 12) {
            Button(action: onSubmit) {
                Label("Submit for Verification", systemImage: "paperplane.fill")
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

    private func flagDescription(_ flag: MeditationIntegrityFlag) -> String {
        switch flag {
        case .faceNotDetected: "Face detection rate below threshold"
        case .eyesOpenTooMuch: "Eyes were open too frequently during session"
        case .excessiveMovement: "Too much head movement detected"
        case .lowConfidence: "Low face detection confidence"
        case .tooShort: "Session too short to be valid"
        }
    }

    private func formatDuration(_ seconds: TimeInterval) -> String {
        let total = Int(max(0, seconds))
        let m = total / 60
        let s = total % 60
        return String(format: "%d:%02d", m, s)
    }
}
