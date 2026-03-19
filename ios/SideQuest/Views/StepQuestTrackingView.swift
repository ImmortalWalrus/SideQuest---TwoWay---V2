import SwiftUI
import UIKit

struct StepQuestTrackingView: View {
    let quest: Quest
    let instanceId: String
    let appState: AppState
    @Environment(\.dismiss) private var dismiss
    @State private var currentSteps: Int = 0
    @State private var isLoading: Bool = true
    @State private var refreshTimer: Timer?
    @State private var claimed: Bool = false
    @State private var showNotAuthorized: Bool = false
    @State private var pulseGoal: Bool = false

    private var targetSteps: Int { quest.targetSteps ?? 10000 }
    private var pathColor: Color { PathColorHelper.color(for: quest.path) }

    private var progress: Double {
        guard targetSteps > 0 else { return 0 }
        return min(1.0, Double(currentSteps) / Double(targetSteps))
    }

    private var goalReached: Bool { currentSteps >= targetSteps }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                ScrollView {
                    VStack(spacing: 28) {
                        stepRingSection
                        statsSection
                        if quest.hasTimeWindow {
                            timeWindowInfo
                        }
                        infoSection
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 20)
                    .padding(.bottom, 100)
                }

                claimBar
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle(quest.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
            }
            .onAppear {
                checkAuthAndFetch()
                startAutoRefresh()
            }
            .onDisappear {
                refreshTimer?.invalidate()
            }
            .alert("Motion & Fitness Required", isPresented: $showNotAuthorized) {
                Button("Open Settings") {
                    if let url = URL(string: UIApplication.openSettingsURLString) {
                        UIApplication.shared.open(url)
                    }
                }
                Button("Cancel", role: .cancel) { dismiss() }
            } message: {
                Text("Step quests use Motion & Fitness access. Turn it back on in Settings to keep verifying your steps.")
            }
            .sensoryFeedback(.success, trigger: claimed)
            .onChange(of: currentSteps) { _, newValue in
                if newValue >= targetSteps && !pulseGoal {
                    pulseGoal = true
                }
            }
        }
    }

    private var stepRingSection: some View {
        VStack(spacing: 16) {
            ZStack {
                Circle()
                    .stroke(pathColor.opacity(0.15), lineWidth: 16)
                    .frame(width: 200, height: 200)

                Circle()
                    .trim(from: 0, to: progress)
                    .stroke(
                        pathColor.gradient,
                        style: StrokeStyle(lineWidth: 16, lineCap: .round)
                    )
                    .frame(width: 200, height: 200)
                    .rotationEffect(.degrees(-90))
                    .animation(.spring(response: 0.8, dampingFraction: 0.7), value: progress)

                VStack(spacing: 4) {
                    if isLoading {
                        ProgressView()
                            .scaleEffect(1.2)
                    } else {
                        Image(systemName: goalReached ? "checkmark.circle.fill" : "figure.walk")
                            .font(.title)
                            .foregroundStyle(goalReached ? .green : pathColor)
                            .symbolEffect(.bounce, value: pulseGoal)

                        Text("\(currentSteps.formatted())")
                            .font(.system(size: 36, weight: .bold, design: .rounded))
                            .monospacedDigit()
                            .contentTransition(.numericText())

                        Text("of \(targetSteps.formatted()) steps")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            if goalReached {
                HStack(spacing: 6) {
                    Image(systemName: "checkmark.seal.fill")
                        .foregroundStyle(.green)
                    Text("Goal Reached!")
                        .font(.headline)
                        .foregroundStyle(.green)
                }
                .transition(.scale.combined(with: .opacity))
            }
        }
        .animation(.spring(response: 0.5), value: goalReached)
    }

    private var statsSection: some View {
        HStack(spacing: 0) {
            VStack(spacing: 4) {
                Text("\(max(0, targetSteps - currentSteps).formatted())")
                    .font(.headline.monospacedDigit())
                    .contentTransition(.numericText())
                Text("Remaining")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity)

            Divider().frame(height: 36)

            VStack(spacing: 4) {
                Text("\(Int(progress * 100))%")
                    .font(.headline.monospacedDigit())
                    .contentTransition(.numericText())
                Text("Progress")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity)

            Divider().frame(height: 36)

            VStack(spacing: 4) {
                Text("\(quest.xpReward)")
                    .font(.headline.monospacedDigit())
                    .foregroundStyle(.orange)
                Text("XP Reward")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity)
        }
        .padding(.vertical, 16)
        .background(Color(.secondarySystemGroupedBackground), in: .rect(cornerRadius: 14))
    }

    private var timeWindowInfo: some View {
        HStack(spacing: 12) {
            Image(systemName: "clock.fill")
                .font(.title3)
                .foregroundStyle(quest.isWithinTimeWindow ? .green : .orange)
                .frame(width: 40, height: 40)
                .background(
                    (quest.isWithinTimeWindow ? Color.green : .orange).opacity(0.12),
                    in: .rect(cornerRadius: 10)
                )

            VStack(alignment: .leading, spacing: 4) {
                if let desc = quest.timeWindowDescription {
                    Text(desc)
                        .font(.subheadline.weight(.semibold))
                }
                Text(quest.isWithinTimeWindow ? "Window is open" : "Outside time window")
                    .font(.caption)
                    .foregroundStyle(quest.isWithinTimeWindow ? .green : .orange)
            }

            Spacer()
        }
        .padding(14)
        .background(Color(.secondarySystemGroupedBackground), in: .rect(cornerRadius: 14))
    }

    private var infoSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("How It Works", systemImage: "info.circle.fill")
                .font(.headline)

            VStack(alignment: .leading, spacing: 10) {
                infoRow(icon: "figure.walk", color: .red, text: "Steps are read from Motion & Fitness")
                infoRow(icon: "arrow.clockwise", color: .blue, text: "Auto-refreshes every 30 seconds")
                infoRow(icon: "checkmark.shield.fill", color: .green, text: "Claim when you hit the target")
                if quest.cooldownDays > 1 {
                    infoRow(icon: "clock.arrow.circlepath", color: .orange, text: "\(quest.cooldownDays)-day cooldown after completion")
                }
            }
            .padding(14)
            .background(Color(.secondarySystemGroupedBackground), in: .rect(cornerRadius: 14))
        }
    }

    private func infoRow(icon: String, color: Color, text: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .font(.caption)
                .foregroundStyle(color)
                .frame(width: 24)
            Text(text)
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
    }

    private var claimBar: some View {
        VStack(spacing: 0) {
            Divider()
            VStack(spacing: 8) {
                Button {
                    claimQuest()
                } label: {
                    Label(goalReached ? "Claim Reward" : "Not Enough Steps", systemImage: goalReached ? "checkmark.circle.fill" : "xmark.circle")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(goalReached ? pathColor : .gray)
                .disabled(!goalReached || claimed)

                Button {
                    Task {
                        isLoading = true
                        await appState.stepCountService.fetchSteps()
                        await fetchCurrentSteps()
                        isLoading = false
                    }
                } label: {
                    Label("Refresh Steps", systemImage: "arrow.clockwise")
                        .font(.subheadline)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(.ultraThinMaterial)
        }
    }

    private func checkAuthAndFetch() {
        Task {
            appState.stepCountService.refreshAuthorizationStatus()

            if appState.stepCountService.isAuthorized {
                if !appState.stepsEnabled {
                    appState.stepsEnabled = true
                    UserDefaults.standard.set(true, forKey: "stepsEnabled")
                }
            } else if appState.stepCountService.needsSettings {
                isLoading = false
                showNotAuthorized = true
                return
            } else {
                let authorized = await appState.stepCountService.requestAuthorization()
                if authorized {
                    appState.stepsEnabled = true
                    UserDefaults.standard.set(true, forKey: "stepsEnabled")
                } else {
                    appState.stepCountService.refreshAuthorizationStatus()
                    isLoading = false
                    showNotAuthorized = appState.stepCountService.needsSettings
                    return
                }
            }

            await fetchCurrentSteps()
            isLoading = false
        }
    }

    private func fetchCurrentSteps() async {
        let steps = await appState.stepCountService.stepsTodayLive()
        withAnimation { currentSteps = steps }
    }

    private func startAutoRefresh() {
        refreshTimer = Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { _ in
            Task { @MainActor in
                await fetchCurrentSteps()
            }
        }
    }

    private func claimQuest() {
        guard goalReached, !claimed else { return }
        claimed = true
        appState.submitStepQuestEvidence(for: instanceId, stepsRecorded: currentSteps)
        Task {
            try? await Task.sleep(for: .seconds(1.5))
            dismiss()
        }
    }
}
