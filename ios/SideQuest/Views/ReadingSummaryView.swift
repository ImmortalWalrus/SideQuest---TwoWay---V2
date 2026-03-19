import SwiftUI
import UIKit

struct ReadingSummaryView: View {
    let session: ReadingSession
    let quest: Quest
    let capturedPhoto: UIImage?
    let onSubmit: () -> Void
    let onDiscard: () -> Void

    private var pathColor: Color { PathColorHelper.color(for: quest.path) }

    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                resultHeader
                if let photo = capturedPhoto {
                    photoSection(photo)
                }
                statsSection
                actionButtons
            }
            .padding(16)
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle("Reading Summary")
        .navigationBarTitleDisplayMode(.inline)
    }

    private var resultHeader: some View {
        VStack(spacing: 16) {
            Image(systemName: session.goalReached ? "checkmark.circle.fill" : "xmark.circle.fill")
                .font(.system(size: 64))
                .foregroundStyle(session.goalReached ? .green : .orange)

            Text(session.goalReached ? "Goal Reached!" : "Not Quite")
                .font(.title.weight(.bold))

            Text("\(formatDuration(session.readingDurationSeconds)) of \(formatDuration(session.targetDurationSeconds))")
                .font(.title3)
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 20)
    }

    private func photoSection(_ photo: UIImage) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Photo Evidence")
                .font(.headline)

            Color(.secondarySystemGroupedBackground)
                .frame(height: 220)
                .overlay {
                    Image(uiImage: photo)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .allowsHitTesting(false)
                }
                .clipShape(.rect(cornerRadius: 14))

            Label("Photo captured in-app", systemImage: "checkmark.shield.fill")
                .font(.caption.weight(.medium))
                .foregroundStyle(.green)
        }
    }

    private var statsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Session Stats")
                .font(.headline)

            HStack(spacing: 0) {
                statItem(
                    icon: "timer",
                    value: formatDuration(session.readingDurationSeconds),
                    label: "Reading"
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
                    icon: "camera.fill",
                    value: session.photoTaken ? "Yes" : "No",
                    label: "Photo"
                )
            }
            .padding(.vertical, 16)
            .background(Color(.secondarySystemGroupedBackground), in: .rect(cornerRadius: 14))

            if session.isValid {
                Label("Session looks good", systemImage: "checkmark.shield.fill")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.green)
            }

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

    private func flagDescription(_ flag: ReadingIntegrityFlag) -> String {
        switch flag {
        case .tooShort: "Session too short to count"
        case .noPhoto: "No photo evidence provided"
        }
    }

    private func formatDuration(_ seconds: TimeInterval) -> String {
        let total = Int(max(0, seconds))
        let m = total / 60
        let s = total % 60
        return String(format: "%d:%02d", m, s)
    }
}
