import SwiftUI

struct GroupHandshakeView: View {
    let quest: Quest
    let appState: AppState
    let onStart: (Bool, Int) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var nfcService = NFCHandshakeService()
    @State private var handshakeVerified: Bool = false

    private var pathColor: Color {
        PathColorHelper.color(for: quest.path)
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 24) {
                Spacer()

                questHeader

                nfcHandshakeSection

                bonusInfo

                Spacer()

                startButtons
            }
            .padding(16)
            .background(Color(.systemGroupedBackground))
            .navigationTitle("Run Bonus")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
    }

    private var questHeader: some View {
        HStack(spacing: 12) {
            Image(systemName: quest.path.iconName)
                .font(.title2)
                .foregroundStyle(.white)
                .frame(width: 48, height: 48)
                .background(pathColor.gradient, in: .rect(cornerRadius: 12))

            VStack(alignment: .leading, spacing: 4) {
                Text(quest.title)
                    .font(.headline)
                HStack(spacing: 8) {
                    DifficultyBadge(difficulty: quest.difficulty)
                    if let target = quest.targetDistanceMiles {
                        Text("\(String(format: "%.1f", target)) mi")
                            .font(.caption.weight(.bold).monospacedDigit())
                            .foregroundStyle(pathColor)
                    }
                }
            }
            Spacer()
        }
        .padding(14)
        .background(Color(.secondarySystemGroupedBackground), in: .rect(cornerRadius: 14))
    }

    private var nfcHandshakeSection: some View {
        VStack(spacing: 16) {
            ZStack {
                Circle()
                    .fill(handshakeVerified ? Color.green.opacity(0.15) : Color.blue.opacity(0.1))
                    .frame(width: 100, height: 100)

                Image(systemName: handshakeVerified ? "checkmark.circle.fill" : "antenna.radiowaves.left.and.right")
                    .font(.system(size: 40))
                    .foregroundStyle(handshakeVerified ? .green : .blue)
                    .symbolEffect(.pulse, isActive: nfcService.isScanning)
            }

            VStack(spacing: 6) {
                Text(handshakeVerified ? "Shake Verified!" : "Shake Bonus")
                    .font(.title3.weight(.bold))
                Text("Tap phones with a friend before your run for +5% XP")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }

            if nfcService.isNFCAvailable {
                Button {
                    nfcService.scanForGroupToken()
                } label: {
                    Label(
                        nfcService.isScanning ? "Scanning..." : "Scan NFC",
                        systemImage: "wave.3.right"
                    )
                    .font(.subheadline.weight(.semibold))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
                }
                .buttonStyle(.bordered)
                .tint(.blue)
                .disabled(nfcService.isScanning || handshakeVerified)
            } else {
                HStack(spacing: 8) {
                    Image(systemName: "info.circle.fill")
                        .foregroundStyle(.blue)
                    Text("NFC available on physical devices via the Rork App.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Button {
                    withAnimation(.spring(response: 0.3)) {
                        handshakeVerified = true
                    }
                } label: {
                    Label("Simulate Shake", systemImage: "hand.wave.fill")
                        .font(.subheadline.weight(.semibold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                }
                .buttonStyle(.bordered)
                .tint(.blue)
                .disabled(handshakeVerified)
            }

            if let error = nfcService.errorMessage {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.red)
            }
        }
        .padding(16)
        .background(Color(.secondarySystemGroupedBackground), in: .rect(cornerRadius: 16))
    }

    private var bonusInfo: some View {
        HStack(spacing: 0) {
            VStack(spacing: 4) {
                Text(handshakeVerified ? "+5%" : "—")
                    .font(.title3.weight(.heavy).monospacedDigit())
                    .foregroundStyle(handshakeVerified ? .green : .secondary)
                Text("Shake Bonus")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity)

            Divider().frame(height: 36)

            VStack(spacing: 4) {
                Text(handshakeVerified ? "1.05x" : "1.0x")
                    .font(.title3.weight(.heavy).monospacedDigit())
                    .foregroundStyle(.orange)
                Text("Total XP")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity)
        }
        .padding(14)
        .background(Color(.secondarySystemGroupedBackground), in: .rect(cornerRadius: 14))
    }

    private var startButtons: some View {
        VStack(spacing: 10) {
            Button {
                onStart(handshakeVerified, 1)
                dismiss()
            } label: {
                Label("Start Run", systemImage: "figure.run")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 6)
            }
            .buttonStyle(.borderedProminent)
            .tint(pathColor)

            if !handshakeVerified {
                Button {
                    onStart(false, 1)
                    dismiss()
                } label: {
                    Text("Skip & Start Without Bonus")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }
}
