import SwiftUI

struct FocusSummaryView: View {
    let session: FocusSession
    let quest: Quest
    let onSubmit: () -> Void
    let onDiscard: () -> Void

    private var pathColor: Color { PathColorHelper.color(for: quest.path) }

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                resultHeader
                statsGrid
                integritySection
                actionButtons
            }
            .padding(16)
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle("Focus Summary")
        .navigationBarTitleDisplayMode(.inline)
    }

    private var resultHeader: some View {
        VStack(spacing: 16) {
            ZStack {
                Circle()
                    .fill(session.goalReached ? Color.green.opacity(0.15) : Color.orange.opacity(0.15))
                    .frame(width: 100, height: 100)
                Image(systemName: session.goalReached ? "checkmark.circle.fill" : "xmark.circle.fill")
                    .font(.system(size: 48))
                    .foregroundStyle(session.goalReached ? .green : .orange)
            }

            Text(session.goalReached ? "Focus Complete!" : "Session Ended Early")
                .font(.title2.weight(.bold))

            Text(formatDuration(session.focusDurationSeconds) + " of " + formatDuration(session.targetDurationSeconds))
                .font(.headline.monospacedDigit())
                .foregroundStyle(.secondary)

            if session.goalReached && session.isValid {
                Label("Ready for verification", systemImage: "checkmark.seal.fill")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.green)
            } else if session.hasCriticalViolation {
                Label("Integrity violation detected", systemImage: "exclamationmark.triangle.fill")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.red)
            }
        }
        .padding(.vertical, 8)
    }

    private var statsGrid: some View {
        VStack(spacing: 1) {
            HStack(spacing: 1) {
                statCell(title: "Focus Time", value: formatDuration(session.focusDurationSeconds), icon: "timer", color: .cyan)
                statCell(title: "Elapsed", value: formatDuration((session.endedAt ?? Date()).timeIntervalSince(session.startedAt ?? Date())), icon: "clock", color: .secondary)
            }
            HStack(spacing: 1) {
                statCell(title: "Pauses", value: "\(session.pauseCount)", icon: "pause.circle", color: session.pauseCount > 0 ? .orange : .green)
                statCell(title: "Pause Time", value: "\(Int(session.totalPauseSeconds))s", icon: "hourglass", color: session.totalPauseSeconds > 0 ? .orange : .green)
            }
            HStack(spacing: 1) {
                statCell(title: "Focus Ratio", value: "\(Int(session.focusRatio * 100))%", icon: "chart.pie.fill", color: session.focusRatio > 0.9 ? .green : .orange)
                statCell(title: "BG Events", value: "\(session.backgroundEvents)", icon: "arrow.uturn.left.circle", color: session.backgroundEvents > 0 ? .red : .green)
            }
        }
        .clipShape(.rect(cornerRadius: 14))
    }

    private func statCell(title: String, value: String, icon: String, color: Color) -> some View {
        VStack(spacing: 6) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundStyle(color)
            Text(value)
                .font(.headline.monospacedDigit())
            Text(title)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 16)
        .background(Color(.secondarySystemGroupedBackground))
    }

    private var integritySection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("Integrity Check", systemImage: "checkmark.shield.fill")
                .font(.headline)

            if session.integrityFlags.isEmpty && !session.wasDisqualified {
                HStack(spacing: 10) {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                    Text("All checks passed")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.green.opacity(0.08), in: .rect(cornerRadius: 10))
            } else {
                ForEach(session.integrityFlags, id: \.rawValue) { flag in
                    HStack(spacing: 10) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundStyle(.red)
                        Text(flagDescription(flag))
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    .padding(12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.red.opacity(0.08), in: .rect(cornerRadius: 10))
                }
            }
        }
    }

    private var actionButtons: some View {
        VStack(spacing: 12) {
            if session.goalReached && !session.hasCriticalViolation {
                Button {
                    onSubmit()
                } label: {
                    Label("Submit for Verification", systemImage: "paperplane.fill")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(.cyan)
            }

            Button {
                onDiscard()
            } label: {
                Text("Discard")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
        }
        .padding(.top, 8)
    }

    private func flagDescription(_ flag: FocusIntegrityFlag) -> String {
        switch flag {
        case .appBackgrounded: "App was backgrounded during session"
        case .tooManyPauses: "Too many pauses detected"
        case .totalPauseExceeded: "Total pause time exceeded limit"
        case .tooShort: "Session too short (< 1 minute)"
        case .clockManipulated: "Clock manipulation detected"
        }
    }

    private func formatDuration(_ seconds: TimeInterval) -> String {
        let total = Int(max(0, seconds))
        let h = total / 3600
        let m = (total % 3600) / 60
        let s = total % 60
        if h > 0 {
            return String(format: "%d:%02d:%02d", h, m, s)
        }
        return String(format: "%d:%02d", m, s)
    }
}
