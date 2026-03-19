import SwiftUI

struct StoryPlayView: View {
    let appState: AppState
    let templateId: String
    var journeyId: String? = nil
    @Environment(\.dismiss) private var dismiss
    @State private var progressKey: String = ""
    @State private var currentNode: StoryNode?
    @State private var nodeHistory: [StoryNode] = []
    @State private var showEndingSummary: Bool = false
    @State private var animateIn: Bool = false

    private var engine: StoryEngine { appState.storyEngine }

    private var template: StoryTemplate? {
        engine.template(for: templateId)
    }

    private var progress: StoryProgress? {
        engine.storyProgressMap[progressKey]
    }

    var body: some View {
        NavigationStack {
            ZStack {
                if showEndingSummary, let progress {
                    endingSummary(progress)
                        .transition(.opacity)
                } else if let node = currentNode, let tmpl = template {
                    StoryEventView(
                        node: node,
                        template: tmpl,
                        onChoice: { choiceId in
                            handleChoice(choiceId)
                        },
                        onContinue: {
                            handleContinue()
                        },
                        onClaim: {
                            handleClaim()
                        }
                    )
                    .id(node.id)
                    .transition(.asymmetric(
                        insertion: .move(edge: .trailing).combined(with: .opacity),
                        removal: .move(edge: .leading).combined(with: .opacity)
                    ))
                } else {
                    ProgressView()
                }
            }
            .animation(.spring(response: 0.4, dampingFraction: 0.85), value: currentNode?.id)
            .animation(.spring(response: 0.4), value: showEndingSummary)
            .navigationTitle(template?.title ?? "Story")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
                if let progress, !progress.isComplete {
                    ToolbarItem(placement: .topBarTrailing) {
                        Menu {
                            Button("Restart Story", systemImage: "arrow.counterclockwise") {
                                restartStory()
                            }
                            if progress.hasSeenFirstDecision {
                                Button(progress.isEnabled ? "Disable Story" : "Enable Story",
                                       systemImage: progress.isEnabled ? "bell.slash" : "bell.fill") {
                                    engine.toggleStoryEnabled(progressKey: progressKey)
                                }
                            }
                        } label: {
                            Image(systemName: "ellipsis.circle")
                        }
                    }
                }
            }
        }
        .onAppear { setupStory() }
    }

    private func endingSummary(_ progress: StoryProgress) -> some View {
        ScrollView {
            VStack(spacing: 24) {
                Image(systemName: "flag.checkered")
                    .font(.system(size: 48))
                    .foregroundStyle(.green.gradient)
                    .padding(.top, 32)

                VStack(spacing: 6) {
                    Text("Story Complete")
                        .font(.title2.weight(.bold))
                    if let ending = progress.endingReached {
                        Text("Ending: \(ending)")
                            .font(.subheadline.weight(.medium))
                            .foregroundStyle(.secondary)
                    }
                }

                VStack(spacing: 8) {
                    HStack(spacing: 20) {
                        statBadge(value: "\(progress.decisionsMade)", label: "Decisions", icon: "arrow.triangle.branch", color: .orange)
                        statBadge(value: "\(progress.inventory.count)", label: "Items", icon: "shippingbox.fill", color: .indigo)
                    }
                    HStack(spacing: 20) {
                        if progress.goldEarned > 0 {
                            statBadge(value: "\(progress.goldEarned)", label: "Gold", icon: "dollarsign.circle.fill", color: .yellow)
                        }
                        if progress.diamondsEarned > 0 {
                            statBadge(value: "\(progress.diamondsEarned)", label: "Diamonds", icon: "diamond.fill", color: .cyan)
                        }
                    }
                }

                if !progress.inventory.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("ITEMS COLLECTED")
                            .font(.caption.weight(.bold))
                            .foregroundStyle(.secondary)
                            .tracking(1)
                        ForEach(progress.inventory) { item in
                            InventoryItemRow(item: item)
                        }
                    }
                    .padding(16)
                    .background(Color(.secondarySystemGroupedBackground), in: .rect(cornerRadius: 14))
                }

                VStack(spacing: 10) {
                    Button {
                        restartStory()
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: "arrow.counterclockwise")
                            Text("Play Again")
                        }
                        .font(.subheadline.weight(.bold))
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(Color.indigo.gradient, in: Capsule())
                    }
                    .buttonStyle(.plain)

                    Button {
                        dismiss()
                    } label: {
                        Text("Done")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 40)
        }
        .background(Color(.systemGroupedBackground))
    }

    private func statBadge(value: String, label: String, icon: String, color: Color) -> some View {
        VStack(spacing: 6) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundStyle(color)
            Text(value)
                .font(.title3.weight(.bold).monospacedDigit())
            Text(label)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 14)
        .background(Color(.secondarySystemGroupedBackground), in: .rect(cornerRadius: 14))
    }

    private func setupStory() {
        let key = journeyId ?? "quickplay_\(templateId)"
        progressKey = key

        if engine.storyProgressMap[key] == nil {
            let _ = engine.startStory(templateId: templateId, journeyId: journeyId)
            if journeyId == nil {
                progressKey = key
                if engine.storyProgressMap[key] == nil {
                    let keys = engine.storyProgressMap.keys.filter { $0.hasPrefix("quickplay_") }
                    if let latestKey = keys.sorted().last {
                        progressKey = latestKey
                    }
                }
            }
        }

        if let progress = engine.storyProgressMap[progressKey] {
            if progress.isComplete {
                showEndingSummary = true
            } else if let tmpl = template {
                currentNode = tmpl.node(for: progress.currentNodeId)
            }
        }
    }

    private func handleChoice(_ choiceId: String) {
        guard let result = engine.makeChoice(progressKey: progressKey, choiceId: choiceId) else { return }
        applyRewards(result.reward)
        withAnimation {
            currentNode = result.node
            if result.node.type == .ending {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                }
            }
        }
    }

    private func handleContinue() {
        guard let result = engine.advanceNarrative(progressKey: progressKey) else { return }
        applyRewards(result.reward)
        withAnimation {
            currentNode = result.node
        }
    }

    private func handleClaim() {
        if let progress, progress.isComplete {
            applyFinalRewards()
            withAnimation { showEndingSummary = true }
        } else {
            guard let result = engine.advanceNarrative(progressKey: progressKey) else {
                if let progress, progress.isComplete {
                    applyFinalRewards()
                    withAnimation { showEndingSummary = true }
                }
                return
            }
            applyRewards(result.reward)
            withAnimation {
                currentNode = result.node
                if result.node.type == .ending {
                }
            }
        }
    }

    private func applyRewards(_ reward: StoryReward?) {
        guard let reward else { return }
        if reward.gold > 0 {
            appState.profile.gold += reward.gold
        }
        if reward.diamonds > 0 {
            appState.profile.diamonds += reward.diamonds
        }
    }

    private func applyFinalRewards() {
        guard let progress else { return }
        if let node = currentNode, let reward = node.reward {
            if reward.gold > 0 {
                appState.profile.gold += reward.gold
            }
            if reward.diamonds > 0 {
                appState.profile.diamonds += reward.diamonds
            }
        }
        appState.saveState()
    }

    private func restartStory() {
        engine.resetProgress(progressKey: progressKey)
        showEndingSummary = false
        if let tmpl = template, let progress = engine.storyProgressMap[progressKey] {
            currentNode = tmpl.node(for: progress.currentNodeId)
        }
    }
}
