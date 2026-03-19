import SwiftUI

struct DevModeView: View {
    let appState: AppState
    @State private var testedMethods: Set<EvidenceType> = []
    @State private var spoofZIPInput: String
    @State private var showTrackingSession: Bool = false
    @State private var trackingInstanceId: String?
    @State private var pushUpLaunch: ExerciseLaunch?
    @State private var showPlankChallenge: Bool = false
    @State private var showWallSitChallenge: Bool = false
    @State private var jumpRopeLaunch: ExerciseLaunch?
    @State private var showMeditationSession: Bool = false
    @State private var showReadingSession: Bool = false
    @State private var showGratitudeLog: Bool = false
    @State private var showAffirmationLog: Bool = false
    @State private var focusBlockLaunch: FocusBlockLaunch?
    @State private var showDualPhoto: Bool = false
    @State private var showPlaceVerification: Bool = false
    @State private var showStepQuest: Bool = false
    @State private var showEvidenceCapture: Bool = false
    @State private var activeInstanceId: String?

    private let testQuests: [(evidenceType: EvidenceType, quest: Quest)] = [
        (.pushUpTracking, Quest(id: "dev_pushup", title: "DEV: 3 Push-Ups", description: "Test push-up tracking", path: .warrior, difficulty: .easy, type: .verified, evidenceType: .pushUpTracking, xpReward: 10, goldReward: 5, diamondReward: 0, milestoneIds: [], minCompletionMinutes: 0, isRepeatable: true, requiresUniqueLocation: false, isFeatured: false, featuredExpiresAt: nil, completionCount: 0, targetReps: 3)),
        (.plankTracking, Quest(id: "dev_plank", title: "DEV: 5s Plank", description: "Test plank tracking", path: .warrior, difficulty: .easy, type: .verified, evidenceType: .plankTracking, xpReward: 10, goldReward: 5, diamondReward: 0, milestoneIds: [], minCompletionMinutes: 0, isRepeatable: true, requiresUniqueLocation: false, isFeatured: false, featuredExpiresAt: nil, completionCount: 0, targetHoldSeconds: 5)),
        (.wallSitTracking, Quest(id: "dev_wallsit", title: "DEV: 5s Wall Sit", description: "Test wall sit tracking", path: .warrior, difficulty: .easy, type: .verified, evidenceType: .wallSitTracking, xpReward: 10, goldReward: 5, diamondReward: 0, milestoneIds: [], minCompletionMinutes: 0, isRepeatable: true, requiresUniqueLocation: false, isFeatured: false, featuredExpiresAt: nil, completionCount: 0, targetHoldSeconds: 5)),
        (.jumpRopeTracking, Quest(id: "dev_jumprope", title: "DEV: 5 Jump Rope", description: "Test jump rope tracking", path: .warrior, difficulty: .easy, type: .verified, evidenceType: .jumpRopeTracking, xpReward: 10, goldReward: 5, diamondReward: 0, milestoneIds: [], minCompletionMinutes: 0, isRepeatable: true, requiresUniqueLocation: false, isFeatured: false, featuredExpiresAt: nil, completionCount: 0, targetReps: 5)),
        (.gpsTracking, Quest(id: "dev_gps", title: "DEV: 0.01mi Walk", description: "Test GPS tracking", path: .explorer, difficulty: .easy, type: .verified, evidenceType: .gpsTracking, xpReward: 10, goldReward: 5, diamondReward: 0, milestoneIds: [], minCompletionMinutes: 0, isRepeatable: true, requiresUniqueLocation: false, isFeatured: false, featuredExpiresAt: nil, completionCount: 0, targetDistanceMiles: 0.01, maxPauseMinutes: 99, maxSpeedMph: 50.0)),
        (.stepTracking, Quest(id: "dev_steps", title: "DEV: 10 Steps", description: "Test step tracking", path: .warrior, difficulty: .easy, type: .verified, evidenceType: .stepTracking, xpReward: 10, goldReward: 5, diamondReward: 0, milestoneIds: [], minCompletionMinutes: 0, isRepeatable: true, requiresUniqueLocation: false, isFeatured: false, featuredExpiresAt: nil, completionCount: 0, targetSteps: 10)),
        (.meditationTracking, Quest(id: "dev_meditation", title: "DEV: 5s Meditation", description: "Test meditation tracking", path: .mind, difficulty: .easy, type: .verified, evidenceType: .meditationTracking, xpReward: 10, goldReward: 5, diamondReward: 0, milestoneIds: [], minCompletionMinutes: 0, isRepeatable: true, requiresUniqueLocation: false, isFeatured: false, featuredExpiresAt: nil, completionCount: 0, targetHoldSeconds: 5)),
        (.readingTracking, Quest(id: "dev_reading", title: "DEV: 5s Reading", description: "Test reading tracking", path: .mind, difficulty: .easy, type: .verified, evidenceType: .readingTracking, xpReward: 10, goldReward: 5, diamondReward: 0, milestoneIds: [], minCompletionMinutes: 0, isRepeatable: true, requiresUniqueLocation: false, isFeatured: false, featuredExpiresAt: nil, completionCount: 0, targetHoldSeconds: 5)),
        (.focusTracking, Quest(id: "dev_focus", title: "DEV: 10s Focus", description: "Test focus tracking", path: .mind, difficulty: .easy, type: .verified, evidenceType: .focusTracking, xpReward: 10, goldReward: 5, diamondReward: 0, milestoneIds: [], minCompletionMinutes: 0, isRepeatable: true, requiresUniqueLocation: false, isFeatured: false, featuredExpiresAt: nil, completionCount: 0, targetFocusMinutes: 1, maxTotalPauseSeconds: 999, maxPauseCount: nil)),
        (.gratitudePhoto, Quest(id: "dev_gratitude", title: "DEV: Gratitude Photo", description: "Test gratitude photo", path: .mind, difficulty: .easy, type: .verified, evidenceType: .gratitudePhoto, xpReward: 10, goldReward: 5, diamondReward: 0, milestoneIds: [], minCompletionMinutes: 0, isRepeatable: true, requiresUniqueLocation: false, isFeatured: false, featuredExpiresAt: nil, completionCount: 0)),
        (.affirmationPhoto, Quest(id: "dev_affirmation", title: "DEV: Affirmation Photo", description: "Test affirmation photo", path: .mind, difficulty: .easy, type: .verified, evidenceType: .affirmationPhoto, xpReward: 10, goldReward: 5, diamondReward: 0, milestoneIds: [], minCompletionMinutes: 0, isRepeatable: true, requiresUniqueLocation: false, isFeatured: false, featuredExpiresAt: nil, completionCount: 0)),
        (.dualPhoto, Quest(id: "dev_dualphoto", title: "DEV: Dual Photo", description: "Test dual photo capture", path: .warrior, difficulty: .easy, type: .verified, evidenceType: .dualPhoto, xpReward: 10, goldReward: 5, diamondReward: 0, milestoneIds: [], minCompletionMinutes: 0, isRepeatable: true, requiresUniqueLocation: false, isFeatured: false, featuredExpiresAt: nil, completionCount: 0)),
        (.placeVerification, Quest(id: "dev_place", title: "DEV: Place Verify", description: "Test place verification", path: .explorer, difficulty: .easy, type: .verified, evidenceType: .placeVerification, xpReward: 10, goldReward: 5, diamondReward: 0, milestoneIds: [], minCompletionMinutes: 0, isRepeatable: true, requiresUniqueLocation: false, isFeatured: false, featuredExpiresAt: nil, completionCount: 0, requiredPlaceType: .park)),
        (.video, Quest(id: "dev_video", title: "DEV: 3s Video", description: "Test video evidence", path: .warrior, difficulty: .easy, type: .verified, evidenceType: .video, xpReward: 10, goldReward: 5, diamondReward: 0, milestoneIds: [], minCompletionMinutes: 0, isRepeatable: true, requiresUniqueLocation: false, isFeatured: false, featuredExpiresAt: nil, completionCount: 0)),
    ]

    init(appState: AppState) {
        self.appState = appState
        _spoofZIPInput = State(initialValue: appState.externalEventSpoofPostalCode)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 12) {
                    spoofZIPCard

                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("\(testedMethods.count)/\(testQuests.count) tested")
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(.secondary)
                            if testedMethods.count == testQuests.count {
                                Text("All verification methods tested!")
                                    .font(.caption)
                                    .foregroundStyle(.green)
                            }
                        }
                        Spacer()
                        Button {
                            withAnimation(.snappy) { testedMethods.removeAll() }
                        } label: {
                            Label("Reset All", systemImage: "arrow.counterclockwise")
                                .font(.subheadline.weight(.medium))
                        }
                        .buttonStyle(.bordered)
                        .tint(.red)
                    }
                    .padding(.bottom, 4)

                    ForEach(Array(testQuests.enumerated()), id: \.element.evidenceType.rawValue) { index, item in
                        devTestCard(
                            index: index + 1,
                            evidenceType: item.evidenceType,
                            quest: item.quest,
                            isTested: testedMethods.contains(item.evidenceType)
                        )
                    }
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 20)
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("Dev Mode")
            .fullScreenCover(isPresented: $showTrackingSession) {
                if let id = activeInstanceId,
                   let instance = appState.activeInstances.first(where: { $0.id == id }) {
                    TrackingSessionView(quest: instance.quest, instanceId: id, appState: appState)
                } else {
                    QuestSessionUnavailableView { showTrackingSession = false }
                }
            }
            .fullScreenCover(item: $pushUpLaunch) { launch in
                PushUpChallengeView(quest: launch.quest, instanceId: launch.instanceId, appState: appState)
            }
            .fullScreenCover(isPresented: $showPlankChallenge) {
                if let id = activeInstanceId,
                   let instance = appState.activeInstances.first(where: { $0.id == id }) {
                    PlankChallengeView(quest: instance.quest, instanceId: id, appState: appState)
                } else {
                    QuestSessionUnavailableView { showPlankChallenge = false }
                }
            }
            .fullScreenCover(isPresented: $showWallSitChallenge) {
                if let id = activeInstanceId,
                   let instance = appState.activeInstances.first(where: { $0.id == id }) {
                    WallSitChallengeView(quest: instance.quest, instanceId: id, appState: appState)
                } else {
                    QuestSessionUnavailableView { showWallSitChallenge = false }
                }
            }
            .fullScreenCover(item: $jumpRopeLaunch) { launch in
                JumpRopeSessionView(quest: launch.quest, instanceId: launch.instanceId, appState: appState)
            }
            .fullScreenCover(isPresented: $showMeditationSession) {
                if let id = activeInstanceId,
                   let instance = appState.activeInstances.first(where: { $0.id == id }) {
                    MeditationSessionView(quest: instance.quest, instanceId: id, appState: appState)
                } else {
                    QuestSessionUnavailableView { showMeditationSession = false }
                }
            }
            .fullScreenCover(isPresented: $showReadingSession) {
                if let id = activeInstanceId,
                   let instance = appState.activeInstances.first(where: { $0.id == id }) {
                    ReadingSessionView(quest: instance.quest, instanceId: id, appState: appState)
                } else {
                    QuestSessionUnavailableView { showReadingSession = false }
                }
            }
            .sheet(isPresented: $showGratitudeLog) {
                if let id = activeInstanceId,
                   let instance = appState.activeInstances.first(where: { $0.id == id }) {
                    GratitudeLogView(quest: instance.quest, instanceId: id, appState: appState)
                } else {
                    QuestSessionUnavailableView { showGratitudeLog = false }
                }
            }
            .sheet(isPresented: $showAffirmationLog) {
                if let id = activeInstanceId,
                   let instance = appState.activeInstances.first(where: { $0.id == id }) {
                    AffirmationsLogView(quest: instance.quest, instanceId: id, appState: appState)
                } else {
                    QuestSessionUnavailableView { showAffirmationLog = false }
                }
            }
            .fullScreenCover(item: $focusBlockLaunch) { launch in
                FocusBlockSessionView(quest: launch.quest, instanceId: launch.instanceId, appState: appState)
            }
            .fullScreenCover(isPresented: $showDualPhoto) {
                if let id = activeInstanceId,
                   let instance = appState.activeInstances.first(where: { $0.id == id }) {
                    DualPhotoCaptureView(quest: instance.quest, instanceId: id, appState: appState)
                } else {
                    QuestSessionUnavailableView { showDualPhoto = false }
                }
            }
            .fullScreenCover(isPresented: $showPlaceVerification) {
                if let id = activeInstanceId,
                   let instance = appState.activeInstances.first(where: { $0.id == id }) {
                    PlaceVerificationView(quest: instance.quest, instanceId: id, appState: appState)
                } else {
                    QuestSessionUnavailableView { showPlaceVerification = false }
                }
            }
            .sheet(isPresented: $showStepQuest) {
                if let id = activeInstanceId,
                   let instance = appState.activeInstances.first(where: { $0.id == id }) {
                    StepQuestTrackingView(quest: instance.quest, instanceId: id, appState: appState)
                } else {
                    QuestSessionUnavailableView { showStepQuest = false }
                }
            }
            .sheet(isPresented: $showEvidenceCapture) {
                EvidenceCaptureView(instanceId: activeInstanceId ?? "", appState: appState)
            }
        }
    }

    private var spoofZIPCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Spoof ZIP")
                        .font(.subheadline.weight(.bold))
                    Text(spoofLocationSummary)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                if !appState.externalEventSpoofPostalCode.isEmpty {
                    Text("ACTIVE")
                        .font(.caption2.weight(.black))
                        .foregroundStyle(.orange)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(.orange.opacity(0.14), in: Capsule())
                }
            }

            HStack(spacing: 10) {
                TextField("Enter US ZIP", text: $spoofZIPInput)
                    .keyboardType(.numberPad)
                    .textInputAutocapitalization(.never)
                    .disableAutocorrection(true)
                    .font(.system(.body, design: .monospaced))
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)
                    .background(Color(.tertiarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 12))

                Button("Apply") {
                    appState.updateExternalEventSpoofPostalCode(spoofZIPInput)
                    spoofZIPInput = appState.externalEventSpoofPostalCode
                    Task { await appState.refreshExternalEvents(forceRefresh: true) }
                }
                .buttonStyle(.borderedProminent)

                Button("Clear") {
                    appState.clearExternalEventSpoofPostalCode()
                    spoofZIPInput = ""
                    Task { await appState.refreshExternalEvents(forceRefresh: true) }
                }
                .buttonStyle(.bordered)
                .disabled(appState.externalEventSpoofPostalCode.isEmpty && spoofZIPInput.isEmpty)
            }

            if appState.isRefreshingExternalEvents {
                HStack(spacing: 8) {
                    ProgressView()
                        .controlSize(.small)
                    Text("Refreshing live events for this test market...")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(14)
        .background(Color(.secondarySystemGroupedBackground), in: .rect(cornerRadius: 16))
    }

    private var spoofLocationSummary: String {
        let zip = appState.externalEventSpoofPostalCode.isEmpty ? "Auto location" : appState.externalEventSpoofPostalCode
        let resolved = appState.externalEventSearchLocation?.displayName ?? "Refresh to resolve"
        return "\(zip) • \(resolved)"
    }

    private func devTestCard(index: Int, evidenceType: EvidenceType, quest: Quest, isTested: Bool) -> some View {
        HStack(spacing: 14) {
            ZStack {
                RoundedRectangle(cornerRadius: 12)
                    .fill(isTested ? Color.green.opacity(0.15) : iconColor(for: evidenceType).opacity(0.12))
                    .frame(width: 48, height: 48)
                if isTested {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.title2)
                        .foregroundStyle(.green)
                } else {
                    Image(systemName: iconName(for: evidenceType))
                        .font(.title3)
                        .foregroundStyle(iconColor(for: evidenceType))
                }
            }

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text("#\(index)")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                    Text(evidenceType.rawValue)
                        .font(.subheadline.weight(.bold))
                }
                Text(quest.title)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Button {
                launchTest(evidenceType: evidenceType, quest: quest)
            } label: {
                Text(isTested ? "Retest" : "Test")
                    .font(.subheadline.weight(.bold))
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
            }
            .buttonStyle(.borderedProminent)
            .tint(isTested ? .green : .blue)
        }
        .padding(14)
        .background(Color(.secondarySystemGroupedBackground), in: .rect(cornerRadius: 16))
    }

    private func launchTest(evidenceType: EvidenceType, quest: Quest) {
        let devQuestIds = Set(testQuests.map { $0.quest.id })
        for inst in appState.activeInstances where devQuestIds.contains(inst.quest.id) {
            appState.dropQuest(inst.id)
        }

        appState.acceptQuest(quest, mode: .solo)

        guard let instance = appState.activeInstances.first(where: { $0.quest.id == quest.id }) else { return }
        activeInstanceId = instance.id

        switch evidenceType {
        case .pushUpTracking:
            pushUpLaunch = ExerciseLaunch(quest: quest, instanceId: instance.id)
        case .plankTracking:
            showPlankChallenge = true
        case .wallSitTracking:
            showWallSitChallenge = true
        case .jumpRopeTracking:
            jumpRopeLaunch = ExerciseLaunch(quest: quest, instanceId: instance.id)
        case .gpsTracking:
            showTrackingSession = true
        case .stepTracking:
            showStepQuest = true
        case .meditationTracking:
            showMeditationSession = true
        case .readingTracking:
            showReadingSession = true
        case .focusTracking:
            focusBlockLaunch = FocusBlockLaunch(quest: quest, instanceId: instance.id)
        case .gratitudePhoto:
            showGratitudeLog = true
        case .affirmationPhoto:
            showAffirmationLog = true
        case .dualPhoto:
            showDualPhoto = true
        case .placeVerification:
            showPlaceVerification = true
        case .video:
            showEvidenceCapture = true
        }
    }

    private func iconName(for type: EvidenceType) -> String {
        switch type {
        case .pushUpTracking: "figure.strengthtraining.traditional"
        case .plankTracking: "figure.core.training"
        case .wallSitTracking: "figure.seated.side"
        case .jumpRopeTracking: "figure.jumprope"
        case .gpsTracking: "location.fill"
        case .stepTracking: "figure.walk"
        case .meditationTracking: "brain.head.profile.fill"
        case .readingTracking: "book.fill"
        case .focusTracking: "timer"
        case .gratitudePhoto: "square.and.pencil"
        case .affirmationPhoto: "sparkles"
        case .dualPhoto: "camera.fill"
        case .placeVerification: "mappin.and.ellipse"
        case .video: "video.fill"
        }
    }

    private func iconColor(for type: EvidenceType) -> Color {
        switch type {
        case .pushUpTracking, .plankTracking, .wallSitTracking, .jumpRopeTracking: .red
        case .gpsTracking, .stepTracking: .orange
        case .meditationTracking, .readingTracking, .focusTracking: .purple
        case .gratitudePhoto, .affirmationPhoto: .mint
        case .dualPhoto, .video: .blue
        case .placeVerification: .green
        }
    }
}
