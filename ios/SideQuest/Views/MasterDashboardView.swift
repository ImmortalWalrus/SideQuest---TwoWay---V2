import SwiftUI

struct MasterDashboardView: View {
    let contractId: String
    let appState: AppState
    @Environment(\.dismiss) private var dismiss
    @State private var showStartConfirmation: Bool = false

    private var contract: MasterContract? {
        appState.masterContracts.first { $0.id == contractId }
    }

    private var pathColor: Color {
        guard let contract else { return .blue }
        return PathColorHelper.color(for: contract.path)
    }

    var body: some View {
        NavigationStack {
            Group {
                if let contract {
                    ScrollView {
                        VStack(spacing: 24) {
                            if appState.timeIntegrity.hasTimeManipulation {
                                timeManipulationBanner
                            }
                            headerCard(contract)
                            if contract.isActive {
                                integrityStatusRow(contract)
                                progressSection(contract)
                                graceSection(contract)
                            }
                            rewardsSection(contract)
                            if !contract.isActive && !contract.isCompleted {
                                startSection
                            }
                            if contract.isCompleted {
                                completedBanner
                            }
                        }
                        .padding(16)
                    }
                } else {
                    ContentUnavailableView("Contract Not Found", systemImage: "exclamationmark.triangle")
                }
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle(contract?.title ?? "Contract")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
            }
        }
        .presentationDragIndicator(.visible)
    }

    private func headerCard(_ contract: MasterContract) -> some View {
        VStack(spacing: 16) {
            Image(systemName: contract.path == .warrior ? "flame.circle.fill" : contract.path == .explorer ? "globe.americas.fill" : "brain")
                .font(.system(size: 56))
                .foregroundStyle(pathColor)

            Text(contract.title)
                .font(.title.weight(.bold))

            Text(contract.subtitle)
                .font(.subheadline)
                .foregroundStyle(.secondary)

            if contract.isActive {
                HStack(spacing: 24) {
                    VStack(spacing: 2) {
                        Text("\(contract.currentDay)")
                            .font(.title.weight(.heavy).monospacedDigit())
                            .foregroundStyle(pathColor)
                        Text("Day")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    VStack(spacing: 2) {
                        Text("\(contract.durationDays - contract.currentDay)")
                            .font(.title.weight(.heavy).monospacedDigit())
                        Text("Remaining")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            Text(contract.description)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(20)
        .background {
            RoundedRectangle(cornerRadius: 20)
                .fill(.linearGradient(
                    colors: [pathColor.opacity(0.12), Color(.secondarySystemGroupedBackground)],
                    startPoint: .top,
                    endPoint: .bottom
                ))
        }
    }

    private func progressSection(_ contract: MasterContract) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Progress")
                .font(.headline)

            ForEach(contract.requirements) { req in
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text(req.title)
                            .font(.subheadline.weight(.medium))
                        Spacer()
                        Text("\(req.current)/\(req.target) \(req.unit)")
                            .font(.caption.monospacedDigit().weight(.medium))
                            .foregroundStyle(.secondary)
                    }
                    ProgressView(value: req.progress)
                        .tint(pathColor)
                }
                .padding(12)
                .background(Color(.secondarySystemGroupedBackground), in: .rect(cornerRadius: 10))
            }
        }
    }

    private func graceSection(_ contract: MasterContract) -> some View {
        HStack {
            Image(systemName: "heart.fill")
                .foregroundStyle(.red)
            Text("Grace Days Used")
                .font(.subheadline)
            Spacer()
            Text("\(contract.graceDaysUsed) / \(contract.maxGraceDays)")
                .font(.subheadline.weight(.semibold).monospacedDigit())
                .foregroundStyle(contract.graceDaysUsed >= contract.maxGraceDays ? .red : .secondary)
        }
        .padding(14)
        .background(Color(.secondarySystemGroupedBackground), in: .rect(cornerRadius: 12))
    }

    private func rewardsSection(_ contract: MasterContract) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Rewards")
                .font(.headline)

            HStack(spacing: 0) {
                VStack(spacing: 4) {
                    Image(systemName: "bolt.fill")
                        .font(.title3)
                        .foregroundStyle(.orange)
                    Text("\(contract.xpReward.formatted())")
                        .font(.headline.monospacedDigit())
                    Text("XP")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity)

                Divider().frame(height: 40)

                VStack(spacing: 4) {
                    Image(systemName: "diamond.fill")
                        .font(.title3)
                        .foregroundStyle(.cyan)
                    Text("\(contract.diamondReward)")
                        .font(.headline.monospacedDigit())
                    Text("Diamonds")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity)
            }
            .padding(.vertical, 16)
            .background(Color(.secondarySystemGroupedBackground), in: .rect(cornerRadius: 14))
        }
    }

    private var startSection: some View {
        Button {
            showStartConfirmation = true
        } label: {
            Label("Start Contract", systemImage: "flag.checkered")
                .font(.headline)
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(.borderedProminent)
        .tint(pathColor)
        .sensoryFeedback(.impact(weight: .medium), trigger: showStartConfirmation)
        .confirmationDialog("Start Contract?", isPresented: $showStartConfirmation, titleVisibility: .visible) {
            Button("Begin \(contract?.title ?? "Contract")") {
                if let contract {
                    appState.startContract(contract.id)
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This is a \(contract?.durationDays ?? 30)-day commitment. You'll have \(contract?.maxGraceDays ?? 2) grace days. Are you ready?")
        }
    }

    private var timeManipulationBanner: some View {
        HStack(spacing: 12) {
            Image(systemName: "exclamationmark.shield.fill")
                .font(.title3)
                .foregroundStyle(.red)
            VStack(alignment: .leading, spacing: 2) {
                Text("Clock Tampering Detected")
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(.red)
                Text("Your device clock doesn't match real time. Enable automatic date & time in Settings to continue.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer()
        }
        .padding(14)
        .background(.red.opacity(0.08), in: .rect(cornerRadius: 14))
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .stroke(Color.red.opacity(0.25), lineWidth: 1)
        )
    }

    private func integrityStatusRow(_ contract: MasterContract) -> some View {
        HStack(spacing: 10) {
            Image(systemName: contract.timeViolationCount > 0 ? "shield.lefthalf.filled.badge.checkmark" : "checkmark.shield.fill")
                .foregroundStyle(contract.timeViolationCount > 0 ? .orange : .green)
            VStack(alignment: .leading, spacing: 2) {
                Text("Time Integrity")
                    .font(.subheadline.weight(.medium))
                Text(contract.timeViolationCount > 0
                     ? "\(contract.timeViolationCount) violation\(contract.timeViolationCount == 1 ? "" : "s") detected"
                     : "No violations")
                    .font(.caption)
                    .foregroundStyle(contract.timeViolationCount > 0 ? .orange : .secondary)
            }
            Spacer()
            Image(systemName: "clock.badge.checkmark")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(14)
        .background(Color(.secondarySystemGroupedBackground), in: .rect(cornerRadius: 12))
    }

    private var completedBanner: some View {
        VStack(spacing: 12) {
            Image(systemName: "crown.fill")
                .font(.system(size: 44))
                .foregroundStyle(.yellow)
            Text("Contract Completed!")
                .font(.title3.weight(.bold))
            Text("You've earned the \(contract?.title ?? "") title.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(24)
        .background(.yellow.opacity(0.08), in: .rect(cornerRadius: 16))
    }
}
