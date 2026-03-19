import SwiftUI
import UIKit
import Combine

extension String: @retroactive Identifiable {
    public var id: String { self }
}

struct FocusBlockLaunch: Identifiable {
    let id = UUID()
    let quest: Quest
    let instanceId: String
}

struct ExerciseLaunch: Identifiable {
    let id = UUID()
    let quest: Quest
    let instanceId: String
}

struct QuickTabView: View {
    let appState: AppState
    @State private var showNotifications: Bool = false
    @State private var showStepsDetail: Bool = false
    @State private var selectedQuest: Quest?
    @State private var showEvidenceCapture: Bool = false
    @State private var evidenceInstanceId: String?
    @State private var showAllActive: Bool = false
    @State private var showTrackingSession: Bool = false
    @State private var trackingInstanceId: String?
    @State private var pushUpLaunch: ExerciseLaunch?
    @State private var showPlankChallenge: Bool = false
    @State private var showWallSitChallenge: Bool = false
    @State private var jumpRopeLaunch: ExerciseLaunch?
    @State private var showMeditationSession: Bool = false
    @State private var exerciseInstanceId: String?
    @State private var meditationInstanceId: String?
    @State private var showGratitudeLog: Bool = false
    @State private var gratitudeInstanceId: String?
    @State private var focusBlockLaunch: FocusBlockLaunch?
    @State private var showAffirmationLog: Bool = false
    @State private var affirmationInstanceId: String?
    @State private var showDualPhoto: Bool = false
    @State private var dualPhotoInstanceId: String?
    @State private var showPlaceVerification: Bool = false
    @State private var placeVerificationInstanceId: String?
    @State private var showGymCheckIn: Bool = false
    @State private var gymCheckInInstanceId: String?
    @State private var showReadingSession: Bool = false
    @State private var readingInstanceId: String?
    @State private var showJourneyReading: Bool = false
    @State private var showStepQuest: Bool = false
    @State private var stepQuestInstanceId: String?
    @State private var selectedActivityProfile: MatchParticipant?
    @State private var selectedActivityQuest: Quest?
    @State private var showStats: Bool = false
    @State private var selectedActiveInstance: QuestInstance?
    @State private var isEditingPaths: Bool = false
    @State private var showStreakDetail: Bool = false
    @State private var expandedQuestId: String?
    @State private var pathQuestIndices: [String: Int] = [:]
    @State private var selectedJourneyId: String?
    @State private var showJourneysHome: Bool = false
    @State private var journeyEvidenceInstanceId: String?
    @State private var journeyEvidenceQuest: Quest?
    @State private var showJourneyEvidence: Bool = false
    @State private var showJourneyTracking: Bool = false
    @State private var journeyPushUpLaunch: ExerciseLaunch?
    @State private var showJourneyPlank: Bool = false
    @State private var showJourneyWallSit: Bool = false
    @State private var journeyJumpRopeLaunch: ExerciseLaunch?
    @State private var showJourneyMeditation: Bool = false
    @State private var showJourneyGratitude: Bool = false
    @State private var journeyFocusBlockLaunch: FocusBlockLaunch?
    @State private var showJourneyAffirmation: Bool = false
    @State private var showJourneyDualPhoto: Bool = false
    @State private var showJourneyStepQuest: Bool = false
    @State private var pendingJourneyQuestItemId: String?
    @State private var showSettings: Bool = false
    @State private var selectedExternalEvent: ExternalEvent?
    @State private var homePullOffset: CGFloat = 0
    @State private var isHomePullRefreshing: Bool = false
    @State private var homePullHasTriggered: Bool = false
    @State private var isHomePullRefreshArmed: Bool = false

    var body: some View {
        NavigationStack {
            ZStack(alignment: .top) {
                homePageBg
                    .ignoresSafeArea()

                homeHeroStretchBackground

                ScrollView {
                    VStack(spacing: 0) {
                        heroAndStatsSection
                            .background {
                                GeometryReader { proxy in
                                    Color.clear
                                        .preference(
                                            key: QuickHomePullOffsetPreferenceKey.self,
                                            value: proxy.frame(in: .named("quickHomeScroll")).minY
                                        )
                                }
                            }
                        homeActiveQuestsSection
                            .padding(.top, 8)
                        liveEventsSection
                            .padding(.top, 16)
                    }
                    .padding(.bottom, 24)
                }
                homePullToRefreshHeader
            }
            .coordinateSpace(name: "quickHomeScroll")
            .onPreferenceChange(QuickHomePullOffsetPreferenceKey.self) { offset in
                handleHomePullOffsetChange(offset)
            }
            .ignoresSafeArea(edges: .top)
            .toolbar(.hidden, for: .navigationBar)

            .sheet(isPresented: $showStepsDetail) {
                StepsDetailSheet(profile: appState.profile, stepCoinsAwardedToday: appState.stepCoinsAwardedToday)
            }
            .sheet(item: $selectedQuest) { quest in
                QuestDetailView(quest: quest, appState: appState)
            }
            .sheet(item: $selectedExternalEvent) { event in
                NavigationStack {
                    ExternalEventDetailView(event: event, appState: appState)
                }
            }
            .sheet(isPresented: $showEvidenceCapture) {
                EvidenceCaptureView(instanceId: evidenceInstanceId ?? "", appState: appState)
            }
            .fullScreenCover(isPresented: $showTrackingSession) {
                if let id = trackingInstanceId,
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
                if let id = exerciseInstanceId,
                   let instance = appState.activeInstances.first(where: { $0.id == id }) {
                    PlankChallengeView(quest: instance.quest, instanceId: id, appState: appState)
                } else {
                    QuestSessionUnavailableView { showPlankChallenge = false }
                }
            }
            .fullScreenCover(isPresented: $showWallSitChallenge) {
                if let id = exerciseInstanceId,
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
                if let id = meditationInstanceId,
                   let instance = appState.activeInstances.first(where: { $0.id == id }) {
                    MeditationSessionView(quest: instance.quest, instanceId: id, appState: appState)
                } else {
                    QuestSessionUnavailableView { showMeditationSession = false }
                }
            }
            .fullScreenCover(isPresented: $showReadingSession) {
                if let id = readingInstanceId,
                   let instance = appState.activeInstances.first(where: { $0.id == id }) {
                    ReadingSessionView(quest: instance.quest, instanceId: id, appState: appState)
                } else {
                    QuestSessionUnavailableView { showReadingSession = false }
                }
            }
            .sheet(isPresented: $showGratitudeLog) {
                if let id = gratitudeInstanceId,
                   let instance = appState.activeInstances.first(where: { $0.id == id }) {
                    GratitudeLogView(quest: instance.quest, instanceId: id, appState: appState)
                } else {
                    QuestSessionUnavailableView { showGratitudeLog = false }
                }
            }
            .fullScreenCover(item: $focusBlockLaunch) { launch in
                FocusBlockSessionView(quest: launch.quest, instanceId: launch.instanceId, appState: appState)
            }
            .sheet(isPresented: $showAffirmationLog) {
                if let id = affirmationInstanceId,
                   let instance = appState.activeInstances.first(where: { $0.id == id }) {
                    AffirmationsLogView(quest: instance.quest, instanceId: id, appState: appState)
                } else {
                    QuestSessionUnavailableView { showAffirmationLog = false }
                }
            }
            .fullScreenCover(isPresented: $showDualPhoto) {
                if let id = dualPhotoInstanceId,
                   let instance = appState.activeInstances.first(where: { $0.id == id }) {
                    DualPhotoCaptureView(quest: instance.quest, instanceId: id, appState: appState)
                } else {
                    QuestSessionUnavailableView { showDualPhoto = false }
                }
            }
            .fullScreenCover(isPresented: $showPlaceVerification) {
                if let id = placeVerificationInstanceId,
                   let instance = appState.activeInstances.first(where: { $0.id == id }) {
                    PlaceVerificationView(quest: instance.quest, instanceId: id, appState: appState)
                } else {
                    QuestSessionUnavailableView { showPlaceVerification = false }
                }
            }
            .fullScreenCover(isPresented: $showGymCheckIn) {
                if let id = gymCheckInInstanceId,
                   let instance = appState.activeInstances.first(where: { $0.id == id }) {
                    GymCheckInView(quest: instance.quest, instanceId: id, appState: appState)
                } else {
                    QuestSessionUnavailableView { showGymCheckIn = false }
                }
            }
            .sheet(isPresented: $showStepQuest) {
                if let id = stepQuestInstanceId,
                   let instance = appState.activeInstances.first(where: { $0.id == id }) {
                    StepQuestTrackingView(quest: instance.quest, instanceId: id, appState: appState)
                } else {
                    QuestSessionUnavailableView { showStepQuest = false }
                }
            }
            .sheet(isPresented: $showStats) {
                StatsAnalyticsView(appState: appState)
            }
            .sheet(isPresented: $showStreakDetail) {
                StreakDetailSheet(appState: appState)
            }
            .sheet(isPresented: $showSettings) {
                SettingsView(appState: appState)
            }
            .task {
                let initialDelay: Duration
                if appState.externalEventFeed.isEmpty {
                    initialDelay = .milliseconds(450)
                } else {
                    initialDelay = .milliseconds(1800)
                }
                try? await Task.sleep(for: initialDelay)
                await appState.ensureExternalEventsLoaded()
            }
            .sheet(item: $selectedActiveInstance) { instance in
                ActiveQuestDetailSheet(
                    instance: instance,
                    appState: appState,
                    onSubmit: {
                        let captured = instance
                        selectedActiveInstance = nil
                        Task { @MainActor in
                            try? await Task.sleep(for: .milliseconds(400))
                            handleActiveQuestSubmit(captured)
                        }
                    },
                    onDrop: {
                        withAnimation(.snappy) {
                            appState.dropQuest(instance.id)
                        }
                    }
                )
            }
            .sheet(item: $selectedJourneyId) { journeyId in
                JourneyDetailView(journeyId: journeyId, appState: appState)
            }
            .sheet(isPresented: $showJourneysHome) {
                NavigationStack {
                    JourneysHomeView(appState: appState)
                }
            }
            .sheet(isPresented: $showJourneyEvidence) {
                EvidenceCaptureView(instanceId: journeyEvidenceInstanceId ?? "", appState: appState)
            }
            .fullScreenCover(isPresented: $showJourneyTracking) {
                if let quest = journeyEvidenceQuest, let id = journeyEvidenceInstanceId {
                    TrackingSessionView(quest: quest, instanceId: id, appState: appState)
                } else {
                    QuestSessionUnavailableView { showJourneyTracking = false }
                }
            }
            .fullScreenCover(item: $journeyPushUpLaunch) { launch in
                PushUpChallengeView(quest: launch.quest, instanceId: launch.instanceId, appState: appState)
            }
            .fullScreenCover(isPresented: $showJourneyPlank) {
                if let quest = journeyEvidenceQuest, let id = journeyEvidenceInstanceId {
                    PlankChallengeView(quest: quest, instanceId: id, appState: appState)
                } else {
                    QuestSessionUnavailableView { showJourneyPlank = false }
                }
            }
            .fullScreenCover(isPresented: $showJourneyWallSit) {
                if let quest = journeyEvidenceQuest, let id = journeyEvidenceInstanceId {
                    WallSitChallengeView(quest: quest, instanceId: id, appState: appState)
                } else {
                    QuestSessionUnavailableView { showJourneyWallSit = false }
                }
            }
            .fullScreenCover(item: $journeyJumpRopeLaunch) { launch in
                JumpRopeSessionView(quest: launch.quest, instanceId: launch.instanceId, appState: appState)
            }
            .fullScreenCover(isPresented: $showJourneyMeditation) {
                if let quest = journeyEvidenceQuest, let id = journeyEvidenceInstanceId {
                    MeditationSessionView(quest: quest, instanceId: id, appState: appState)
                } else {
                    QuestSessionUnavailableView { showJourneyMeditation = false }
                }
            }
            .fullScreenCover(isPresented: $showJourneyReading) {
                if let quest = journeyEvidenceQuest, let id = journeyEvidenceInstanceId {
                    ReadingSessionView(quest: quest, instanceId: id, appState: appState)
                } else {
                    QuestSessionUnavailableView { showJourneyReading = false }
                }
            }
            .sheet(isPresented: $showJourneyGratitude) {
                if let quest = journeyEvidenceQuest, let id = journeyEvidenceInstanceId {
                    GratitudeLogView(quest: quest, instanceId: id, appState: appState)
                } else {
                    QuestSessionUnavailableView { showJourneyGratitude = false }
                }
            }
            .fullScreenCover(item: $journeyFocusBlockLaunch) { launch in
                FocusBlockSessionView(quest: launch.quest, instanceId: launch.instanceId, appState: appState)
            }
            .sheet(isPresented: $showJourneyAffirmation) {
                if let quest = journeyEvidenceQuest, let id = journeyEvidenceInstanceId {
                    AffirmationsLogView(quest: quest, instanceId: id, appState: appState)
                } else {
                    QuestSessionUnavailableView { showJourneyAffirmation = false }
                }
            }
            .fullScreenCover(isPresented: $showJourneyDualPhoto) {
                if let quest = journeyEvidenceQuest, let id = journeyEvidenceInstanceId {
                    DualPhotoCaptureView(quest: quest, instanceId: id, appState: appState)
                } else {
                    QuestSessionUnavailableView { showJourneyDualPhoto = false }
                }
            }
            .sheet(isPresented: $showJourneyStepQuest) {
                if let quest = journeyEvidenceQuest, let id = journeyEvidenceInstanceId {
                    StepQuestTrackingView(quest: quest, instanceId: id, appState: appState)
                } else {
                    QuestSessionUnavailableView { showJourneyStepQuest = false }
                }
            }
            .onChange(of: appState.pendingFocusLaunchInstanceId) { _, newValue in
                guard let instanceId = newValue,
                      let instance = appState.activeInstances.first(where: { $0.id == instanceId }) else { return }
                appState.pendingFocusLaunchInstanceId = nil
                focusBlockLaunch = FocusBlockLaunch(quest: instance.quest, instanceId: instanceId)
            }
        }
    }

    private var streakToolbarButton: some View {
        let streak = appState.profile.currentStreak
        let multiplier = LevelSystem.streakMultiplier(for: streak)
        let hoursLeft = streakHoursRemaining
        let isUrgent = hoursLeft < 4 && streak > 0

        return HStack(spacing: 6) {
            ZStack {
                Image(systemName: "flame.fill")
                    .font(.subheadline)
                    .foregroundStyle(
                        streak >= 3
                            ? LinearGradient(colors: [.yellow, .orange, .red], startPoint: .top, endPoint: .bottom)
                            : LinearGradient(colors: [.gray, .gray.opacity(0.6)], startPoint: .top, endPoint: .bottom)
                    )
                    .symbolEffect(.variableColor.iterative, options: .repeating, value: streak >= 3)

                Image(systemName: "chart.bar.fill")
                    .font(.system(size: 7, weight: .bold))
                    .foregroundStyle(streak >= 3 ? .orange : .secondary)
                    .offset(x: 8, y: -6)
            }

            Text("\(streak)")
                .font(.subheadline.weight(.black).monospacedDigit())
                .foregroundStyle(streak >= 3 ? .primary : .secondary)

            if multiplier > 1.0 {
                Text("\(String(format: "%.1f", multiplier))x")
                    .font(.system(size: 10, weight: .black))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 4)
                    .padding(.vertical, 1)
                    .background(.orange, in: Capsule())
            }

            if isUrgent && streak > 0 {
                HStack(spacing: 2) {
                    Image(systemName: "clock.fill")
                        .font(.system(size: 9))
                    Text(streakTimeLabel(hoursLeft: hoursLeft))
                        .font(.system(size: 10, weight: .bold).monospacedDigit())
                }
                .foregroundStyle(.red)
                .padding(.horizontal, 5)
                .padding(.vertical, 2)
                .background(.red.opacity(0.12), in: Capsule())
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(
            isUrgent
                ? AnyShapeStyle(.red.opacity(0.08))
                : streak >= 3
                    ? AnyShapeStyle(.orange.opacity(0.1))
                    : AnyShapeStyle(Color(.quaternarySystemFill)),
            in: Capsule()
        )
    }

    private var streakHoursRemaining: Double {
        let cal = Calendar.current
        let now = Date()
        let todayStart = cal.startOfDay(for: now)
        let hasCompletedToday: Bool = {
            if let last = appState.lastStreakDate {
                return cal.isDate(cal.startOfDay(for: last), inSameDayAs: now)
            }
            return false
        }()
        if hasCompletedToday {
            guard let tomorrowEnd = cal.date(byAdding: .day, value: 2, to: todayStart) else { return 48 }
            return tomorrowEnd.timeIntervalSince(now) / 3600
        } else {
            guard let todayEnd = cal.date(byAdding: .day, value: 1, to: todayStart) else { return 24 }
            return todayEnd.timeIntervalSince(now) / 3600
        }
    }

    private func streakTimeLabel(hoursLeft: Double) -> String {
        let total = Int(hoursLeft * 3600)
        let h = total / 3600
        let m = (total % 3600) / 60
        if h > 0 {
            return "\(h)h \(m)m"
        }
        return "\(m)m"
    }

    private let homeCardBg = Color(white: 1, opacity: 0.06)
    private let homeCardBorder = Color(white: 1, opacity: 0.08)
    private let homeGold = Color(red: 0.85, green: 0.68, blue: 0.32)
    private let homePageBg = Color(red: 0.086, green: 0.094, blue: 0.110)

    private func loadQuestIcon(_ name: String) -> UIImage? {
        if let url = Bundle.main.url(forResource: name, withExtension: "png", subdirectory: "Resources/QuestIcons"),
           let img = UIImage(contentsOfFile: url.path) { return img }
        if let url = Bundle.main.url(forResource: name, withExtension: "png"),
           let img = UIImage(contentsOfFile: url.path) { return img }
        return UIImage(named: name)
    }

    private func loadQuestBanner(_ name: String) -> UIImage? {
        if let url = Bundle.main.url(forResource: name, withExtension: "jpg", subdirectory: "Resources/QuestBanners"),
           let img = UIImage(contentsOfFile: url.path) { return img }
        if let url = Bundle.main.url(forResource: name, withExtension: "jpg"),
           let img = UIImage(contentsOfFile: url.path) { return img }
        return UIImage(named: name)
    }

    private func loadCoinsSprite() -> UIImage? {
        if let url = Bundle.main.url(forResource: "coins_sprite", withExtension: "png", subdirectory: "Resources"),
           let img = UIImage(contentsOfFile: url.path) { return img }
        if let url = Bundle.main.url(forResource: "coins_sprite", withExtension: "png"),
           let img = UIImage(contentsOfFile: url.path) { return img }
        return UIImage(named: "coins_sprite")
    }

    private var homePullHeaderHeight: CGFloat {
        if isHomePullRefreshing {
            return 48
        }
        return min(max(homePullOffset - 8, 0), 72)
    }

    private var homePullToRefreshHeader: some View {
        let height = homePullHeaderHeight

        return VStack(spacing: 8) {
            VStack(spacing: 8) {
                Group {
                    if isHomePullRefreshing {
                        ProgressView()
                            .tint(.orange)
                    } else {
                        Image(systemName: isHomePullRefreshArmed ? "arrow.down.circle.fill" : "arrow.down")
                            .font(.system(size: 12, weight: .bold))
                            .foregroundStyle(.white.opacity(0.72))
                            .rotationEffect(.degrees(isHomePullRefreshArmed ? 180 : 0))
                    }
                }

                if height >= 28 || isHomePullRefreshing {
                    Text(isHomePullRefreshing ? "Refreshing live events..." : "Pull to refresh")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.white.opacity(0.72))
                }
            }
            .opacity(isHomePullRefreshing ? 1 : min(1, max(height / 22, 0)))
        }
        .frame(maxWidth: .infinity)
        .frame(height: max(0, height))
        .padding(.top, 50)
        .offset(y: min(max(homePullOffset, 0) * 0.18, 16))
        .allowsHitTesting(false)
    }

    private func handleHomePullOffsetChange(_ offset: CGFloat) {
        let clampedOffset = max(0, offset)
        homePullOffset = clampedOffset

        let shouldArm = clampedOffset >= 84
        if isHomePullRefreshArmed != shouldArm {
            isHomePullRefreshArmed = shouldArm
        }

        guard !isHomePullRefreshing else { return }

        if clampedOffset >= 84, !homePullHasTriggered {
            homePullHasTriggered = true
            Task {
                await runHomePullToRefresh()
            }
        } else if clampedOffset <= 10 {
            homePullHasTriggered = false
        }
    }

    @MainActor
    private func runHomePullToRefresh() async {
        guard !isHomePullRefreshing else { return }
        isHomePullRefreshing = true
        await appState.refreshExternalEvents(forceRefresh: true)
        try? await Task.sleep(for: .milliseconds(250))
        isHomePullRefreshing = false
        isHomePullRefreshArmed = false
        homePullHasTriggered = false
    }

    private var homeHeroStretchBackground: some View {
        GeometryReader { geo in
            let extraStretch = min(max(homePullOffset, 0), 140)
            let stretchHeight = 300 + extraStretch

            ZStack(alignment: .top) {
                RadialGradient(
                    colors: [
                        Color(white: 0.48, opacity: 0.38),
                        Color(white: 0.36, opacity: 0.24),
                        Color(white: 0.22, opacity: 0.11),
                        Color(white: 0.12, opacity: 0.03),
                        Color.clear
                    ],
                    center: .init(x: 0.52, y: 0.04),
                    startRadius: 4,
                    endRadius: 280
                )
                .frame(width: geo.size.width, height: stretchHeight)

                LinearGradient(
                    colors: [Color.clear, homePageBg.opacity(0.62), homePageBg],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .frame(width: geo.size.width, height: 270 + extraStretch)
            }
            .frame(width: geo.size.width, height: stretchHeight, alignment: .top)
        }
        .ignoresSafeArea(edges: .top)
        .allowsHitTesting(false)
    }

    private var heroAndStatsSection: some View {
        VStack(spacing: 0) {
            ZStack(alignment: .topTrailing) {
                HStack(alignment: .center, spacing: 2) {
                    Color.clear
                        .frame(width: 146, height: 154)
                        .overlay(alignment: .bottom) {
                            Character3DView(
                                characterType: appState.profile.selectedCharacter,
                                allowsControl: false,
                                autoRotate: false,
                                framing: .upperBody,
                                modelYawDegrees: appState.profile.selectedCharacter.homeHeroYawDegrees,
                                sceneStyle: .homeHero,
                                debugMode: .beauty,
                                isActive: appState.selectedTab == 0
                            )
                            .frame(width: 146, height: 184)
                            .allowsHitTesting(false)
                            .scaleEffect(1.28, anchor: .trailing)
                            .offset(x: 14, y: 40)
                            .mask(alignment: .top) {
                                Rectangle()
                                    .frame(width: 146, height: 176)
                            }
                        }

                    VStack(alignment: .leading, spacing: 0) {
                        Text("YOUR")
                        Text("ADVENTURE")
                        Text("TODAY")
                    }
                    .font(.system(size: 24, weight: .semibold))
                    .foregroundStyle(Color(white: 0.55))
                    .fixedSize(horizontal: true, vertical: false)
                    .lineSpacing(-1)
                    .frame(height: 154, alignment: .center)
                    .offset(y: 10)

                    Spacer(minLength: 0)
                }
                .padding(.leading, 6)
                .padding(.top, 10)

                Button { showSettings = true } label: {
                    Image(systemName: "gearshape.fill")
                        .font(.title3)
                        .foregroundStyle(.white.opacity(0.5))
                        .frame(width: 38, height: 38)
                        .background(Color(white: 1, opacity: 0.1), in: .rect(cornerRadius: 10))
                }
                .padding(.trailing, 16)
                .padding(.top, 42)
            }

            homeStatsBar
                .offset(y: -10)
                .zIndex(1)
        }
        .padding(.top, 4)
    }

    private var homeStatsBar: some View {
        return HStack(spacing: 0) {
            homeProgressStatCell(
                title: "Level",
                value: "\(appState.profile.level)",
                progress: appState.profile.levelProgress,
                gradient: [.blue, .cyan.opacity(0.8)],
                showsChevron: true
            )

            homeStatsDivider

            homeProgressStatCell(
                title: "Steps Today",
                value: "\(appState.profile.stepsToday.formatted()) / 10,000",
                progress: min(Double(appState.profile.stepsToday) / 10000.0, 1.0),
                gradient: [.orange, homeGold]
            )

            homeStatsDivider

            homeValueStatCell(
                title: "Coins Today",
                value: "\(appState.stepCoinsAwardedToday)",
                symbol: "\u{1FA99}"
            )
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(Color(red: 0.16, green: 0.17, blue: 0.20))
        .clipShape(.rect(cornerRadius: 13))
        .overlay(RoundedRectangle(cornerRadius: 13).strokeBorder(Color(white: 1, opacity: 0.18), lineWidth: 1))
        .padding(.horizontal, 16)
    }

    private var homeStatsDivider: some View {
        Rectangle()
            .fill(Color(white: 1, opacity: 0.10))
            .frame(width: 1, height: 36)
            .padding(.horizontal, 10)
    }

    private func homeProgressStatCell(
        title: String,
        value: String,
        progress: Double,
        gradient: [Color],
        showsChevron: Bool = false
    ) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(.white.opacity(0.48))
                .lineLimit(1)

            Text(value)
                .font(.system(size: 15, weight: .bold))
                .foregroundStyle(.white)
                .lineLimit(1)
                .minimumScaleFactor(0.78)

            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color(white: 1, opacity: 0.12))
                    Capsule()
                        .fill(LinearGradient(colors: gradient, startPoint: .leading, endPoint: .trailing))
                        .frame(width: max(4, geo.size.width * progress))
                        .overlay(alignment: .trailing) {
                            if showsChevron {
                                Text("\u{00BB}")
                                    .font(.system(size: 10, weight: .black))
                                    .foregroundStyle(.white)
                                    .padding(.trailing, 3)
                            }
                        }
                }
            }
            .frame(height: 7)
            .clipShape(Capsule())
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func homeValueStatCell(
        title: String,
        value: String,
        symbol: String
    ) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(.white.opacity(0.48))
                .lineLimit(1)

            HStack(spacing: 4) {
                Text(symbol)
                    .font(.system(size: 13))
                Text(value)
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(.white)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Color.clear
                .frame(height: 7)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var homeActiveQuestsSection: some View {
        let allActive = appState.activeInstances.filter { $0.state != .verified }
        return VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Active Quests")
                    .font(.title2.weight(.black))
                    .foregroundStyle(.white)
                Spacer()
                Button { showStepsDetail = true } label: {
                    Text("Learn more")
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(.cyan.opacity(0.8))
                }
            }
            .padding(.horizontal, 16)

            VStack(spacing: 0) {
                if allActive.isEmpty {
                    VStack(spacing: 8) {
                        Image(systemName: "scroll")
                            .font(.largeTitle)
                            .foregroundStyle(.white.opacity(0.2))
                        Text("No active quests")
                            .font(.subheadline.weight(.medium))
                            .foregroundStyle(.white.opacity(0.4))
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 24)
                } else {
                    ForEach(Array(allActive.enumerated()), id: \.element.id) { index, instance in
                        if index > 0 {
                            Divider()
                                .background(Color(white: 1, opacity: 0.06))
                                .padding(.horizontal, 14)
                        }
                        homeActiveQuestRow(instance)
                    }
                }
            }
            .background(homeCardBg, in: .rect(cornerRadius: 14))
            .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(homeCardBorder, lineWidth: 1))
            .padding(.horizontal, 16)
        }
    }

    private func homeActiveQuestRow(_ instance: QuestInstance) -> some View {
        return Button {
            selectedActiveInstance = instance
        } label: {
            HStack(spacing: 12) {
                if let icon = activeQuestIcon(for: instance) {
                    Image(uiImage: icon)
                        .resizable()
                        .interpolation(.none)
                        .aspectRatio(contentMode: .fit)
                        .frame(width: 56, height: 56)
                } else {
                    Image(systemName: instance.quest.path.iconName)
                        .font(.title)
                        .foregroundStyle(PathColorHelper.color(for: instance.quest.path))
                        .frame(width: 56, height: 56)
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text(instance.quest.title)
                        .font(.subheadline.weight(.bold))
                        .foregroundStyle(.white)
                        .lineLimit(1)

                    Text(questSubtitle(instance))
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.5))
                        .lineLimit(1)

                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            Capsule().fill(Color(white: 1, opacity: 0.10))
                            Capsule()
                                .fill(LinearGradient(colors: [.orange, homeGold], startPoint: .leading, endPoint: .trailing))
                                .frame(width: max(4, geo.size.width * questProgressFraction(instance)))
                        }
                    }
                    .frame(height: 6)
                    .clipShape(Capsule())
                }

                Spacer(minLength: 4)

                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.white.opacity(0.3))
            }
            .padding(14)
        }
        .buttonStyle(.plain)
    }

    private func questSubtitle(_ instance: QuestInstance) -> String {
        switch instance.state {
        case .active:
            if instance.isGPSAutoCheckInQuest {
                if instance.canSubmit { return "Ready to submit" }
                if instance.isAutoCheckInInRange {
                    let remaining = instance.timeUntilSubmit
                    let minutes = Int(remaining) / 60
                    let seconds = Int(remaining) % 60
                    return "Auto check-in • \(minutes)m \(seconds)s left"
                }
                return "Arrive to auto check in"
            }
            if instance.canSubmit { return "Ready to submit" }
            let remaining = instance.timeUntilSubmit
            let minutes = Int(remaining) / 60
            return "\(minutes)m remaining"
        case .submitted: return "Pending verification"
        case .rejected: return "Needs resubmission"
        case .failed: return "Challenge failed"
        default: return instance.quest.path.rawValue
        }
    }

    private func questProgressFraction(_ instance: QuestInstance) -> Double {
        switch instance.state {
        case .verified: return 1.0
        case .submitted: return 0.85
        case .active:
            if instance.isGPSAutoCheckInQuest {
                return max(0.12, instance.autoCheckInProgressFraction)
            }
            let elapsed = Date().timeIntervalSince(instance.startedAt)
            let required = Double(instance.quest.minCompletionMinutes) * 60
            guard required > 0 else { return 0.5 }
            return min(1.0, elapsed / required)
        default: return 0.3
        }
    }

    private func activeQuestIcon(for instance: QuestInstance) -> UIImage? {
        if let externalIconName = instance.quest.externalEventIconName,
           let image = QuestAssetMapping.bundleImage(named: externalIconName, ext: "png", folder: "EventIcons") {
            return image
        }
        if instance.quest.id.hasPrefix("external_event_") {
            let fallbackName: String = {
                switch instance.quest.requiredPlaceType {
                case .nightclub?, .barLounge?:
                    return "nightlife_party_v1"
                case .concertVenue?:
                    return "concert_generic_01"
                case .arena?, .stadium?:
                    return "generic_live_event"
                case .park?:
                    return "race_short_v1"
                case .restaurant?:
                    return "food_drink"
                case .communityCenter?:
                    return "community_social"
                default:
                    return "generic_live_event"
                }
            }()
            if let image = QuestAssetMapping.bundleImage(named: fallbackName, ext: "png", folder: "EventIcons") {
                return image
            }
        }
        let assetPair = QuestAssetMapping.assets(for: instance.quest.title)
        return loadQuestIcon(assetPair.icon)
    }

    private var liveEventsSection: some View {
        return VStack(alignment: .leading, spacing: 10) {
            VStack(alignment: .leading, spacing: 4) {
                Text("LIVE LOCAL EVENTS")
                    .font(.system(size: 18, weight: .black))
                    .tracking(1.5)
                    .foregroundStyle(.white)

                if let locationName = appState.externalEventSearchLocation?.displayName {
                    Text(locationName.uppercased())
                        .font(.system(size: 10, weight: .bold))
                        .tracking(1.2)
                        .foregroundStyle(.white.opacity(0.45))
                }
            }
            .padding(.horizontal, 16)

            ZStack(alignment: .topTrailing) {
                if appState.isRefreshingExternalEvents && appState.externalEventFeed.isEmpty {
                    placeholderLiveEventsCard(message: "Pulling live events near you...")
                        .padding(.horizontal, 16)
                } else if appState.externalEventFeed.isEmpty {
                    placeholderLiveEventsCard(message: "No live events nearby yet.")
                        .padding(.horizontal, 16)
                } else {
                    ScrollView(.horizontal) {
                        HStack(spacing: 12) {
                            ForEach(Array(appState.externalEventFeed.prefix(6))) { event in
                                Button {
                                    selectedExternalEvent = event
                                } label: {
                                    ExternalEventCardView(
                                        event: event,
                                        imageRefreshNonce: appState.externalEventImageRefreshNonce
                                    )
                                        .frame(width: 304)
                                        .contentShape(Rectangle())
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                    .scrollIndicators(.hidden)
                    .contentMargins(.horizontal, 16)
                }

                if appState.isRefreshingExternalEvents && !appState.externalEventFeed.isEmpty {
                    liveEventsUpdatingBadge
                        .padding(.top, 8)
                        .padding(.trailing, 16)
                }

                if let coinsImg = loadCoinsSprite() {
                    Image(uiImage: coinsImg)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(width: 110, height: 110)
                        .allowsHitTesting(false)
                        .offset(x: -4, y: -30)
                }
            }
        }
    }

    private func placeholderLiveEventsCard(message: String) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                if appState.isRefreshingExternalEvents {
                    ProgressView()
                        .tint(.orange)
                } else {
                    Image(systemName: "calendar.badge.clock")
                        .foregroundStyle(.orange)
                }
                Text(message)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.white)
            }

            if appState.isRefreshingExternalEvents {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Checking nearby venues, ticketed events, and nightlife details.")
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.62))
                    Text("The first pass is live, then richer venue details keep filling in.")
                        .font(.caption2)
                        .foregroundStyle(.white.opacity(0.46))
                }
            } else {
                Text("Open the Events tab for the full live feed once it finishes loading.")
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.58))
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, minHeight: 120, alignment: .leading)
        .background(Color(red: 0.161, green: 0.169, blue: 0.204), in: RoundedRectangle(cornerRadius: 18))
        .overlay(RoundedRectangle(cornerRadius: 18).strokeBorder(.white.opacity(0.08), lineWidth: 1))
    }

    private var liveEventsUpdatingBadge: some View {
        HStack(spacing: 8) {
            ProgressView()
                .tint(.white)
                .scaleEffect(0.85)
            Text("Updating")
                .font(.caption2.weight(.bold))
                .foregroundStyle(.white.opacity(0.92))
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(Color.black.opacity(0.38), in: Capsule())
        .overlay(Capsule().strokeBorder(.white.opacity(0.1), lineWidth: 1))
        .allowsHitTesting(false)
    }

    private func eventCard(title: String, subtitle: String, bannerName: String, iconName: String, friendCount: Int) -> some View {
        let cardWidth: CGFloat = 280
        let cardHeight: CGFloat = 200
        let gradColor = Color(red: 0.145, green: 0.165, blue: 0.204)

        return ZStack(alignment: .bottomLeading) {
            Color(red: 0.161, green: 0.169, blue: 0.204)

            if let img = loadQuestBanner(bannerName) {
                Image(uiImage: img)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: cardWidth, height: cardHeight)
                    .clipped()
                    .allowsHitTesting(false)
            }

            VStack(spacing: 0) {
                Spacer()
                LinearGradient(
                    stops: [
                        .init(color: gradColor.opacity(0), location: 0),
                        .init(color: gradColor.opacity(0.5), location: 0.3),
                        .init(color: gradColor.opacity(0.85), location: 0.6),
                        .init(color: gradColor, location: 0.85)
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .frame(height: cardHeight * 0.6)
            }
            .allowsHitTesting(false)

            if let icon = loadQuestIcon(iconName) {
                let iconSize = cardHeight * 0.55
                Image(uiImage: icon)
                    .resizable()
                    .interpolation(.none)
                    .aspectRatio(contentMode: .fit)
                    .frame(width: iconSize, height: iconSize)
                    .shadow(color: .black.opacity(0.5), radius: 8, y: 4)
                    .position(x: cardWidth - iconSize / 2 + 4, y: cardHeight * 0.38)
                    .allowsHitTesting(false)
            }

            VStack(alignment: .leading, spacing: 4) {
                Spacer()
                Text(title)
                    .font(.headline.weight(.bold))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                    .shadow(color: .black.opacity(0.5), radius: 4, y: 2)

                HStack {
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.7))
                        .lineLimit(1)
                    Spacer()
                    friendAvatarCluster(count: friendCount)
                }
            }
            .padding(14)
        }
        .frame(width: cardWidth, height: cardHeight)
        .clipShape(.rect(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(.white.opacity(0.08), lineWidth: 1))
    }

    private func friendAvatarCluster(count: Int) -> some View {
        HStack(spacing: -8) {
            ForEach(0..<count, id: \.self) { i in
                Circle()
                    .fill(
                        LinearGradient(
                            colors: [
                                [Color.orange, Color.brown],
                                [Color.teal, Color.blue],
                                [Color.purple, Color.pink]
                            ][i % 3],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                    .frame(width: 26, height: 26)
                    .overlay {
                        Image(systemName: "person.fill")
                            .font(.system(size: 11))
                            .foregroundStyle(.white)
                    }
                    .overlay(Circle().strokeBorder(Color(red: 0.145, green: 0.165, blue: 0.204), lineWidth: 2))
            }
        }
    }

    private var stepsBar: some View {
        Button {
            showStepsDetail = true
        } label: {
            HStack(spacing: 12) {
                Image(systemName: "figure.walk.motion")
                    .font(.title3)
                    .foregroundStyle(.green)

                VStack(alignment: .leading, spacing: 2) {
                    Text("\(appState.profile.stepsToday.formatted()) steps")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.primary)
                    Text("+\(appState.stepCoinsAwardedToday) coins today")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                CircularProgressView(progress: min(Double(appState.profile.stepsToday) / 10000.0, 1.0), color: .green)
                    .frame(width: 36, height: 36)
            }
            .padding(14)
            .background(Color(.secondarySystemGroupedBackground), in: .rect(cornerRadius: 14))
        }
        .buttonStyle(.plain)
    }

    private var activeCampaignsSection: some View {
        let active = appState.activeJourneys
        return VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 6) {
                Image(systemName: "map.fill")
                    .font(.subheadline)
                    .foregroundStyle(.blue)
                Text("Active Quests")
                    .font(.title3.weight(.bold))
                Spacer()
                Text("\(active.count)/3")
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.secondary)
            }

            ForEach(active) { journey in
                journeyGroupCard(journey)
            }
        }
    }

    private var addCampaignPrompt: some View {
        Button {
            showJourneysHome = true
        } label: {
            HStack(spacing: 12) {
                Image(systemName: "map.fill")
                    .font(.title3)
                    .foregroundStyle(.blue)
                    .frame(width: 36, height: 36)
                    .background(.blue.opacity(0.12), in: .rect(cornerRadius: 10))

                VStack(alignment: .leading, spacing: 2) {
                    Text("Add a Quest")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.primary)
                    Text("Multi-day structured side quest paths")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Image(systemName: "plus.circle.fill")
                    .font(.title2)
                    .foregroundStyle(.blue)
            }
            .padding(14)
            .background(Color(.secondarySystemGroupedBackground), in: .rect(cornerRadius: 14))
        }
        .buttonStyle(.plain)
    }

    private func journeyGroupCard(_ journey: Journey) -> some View {
        let scheduled = journey.scheduledQuestsForDate(Date())
            .sorted { a, b in
                if a.isAnytime != b.isAnytime { return !a.isAnytime }
                return (a.scheduledHour ?? 99) < (b.scheduledHour ?? 99)
            }
        let todayCompleted = journey.todayProgress?.completedCount ?? 0
        let todayTotal = scheduled.count

        return VStack(alignment: .leading, spacing: 0) {
            Button {
                selectedJourneyId = journey.id
            } label: {
                HStack(spacing: 10) {
                    ZStack {
                        Circle()
                            .stroke(.quaternary, lineWidth: 3)
                        Circle()
                            .trim(from: 0, to: journey.overallCompletionPercent)
                            .stroke(Color.blue, style: StrokeStyle(lineWidth: 3, lineCap: .round))
                            .rotationEffect(.degrees(-90))
                        Text("\(Int(journey.overallCompletionPercent * 100))")
                            .font(.system(size: 11, weight: .bold).monospacedDigit())
                    }
                    .frame(width: 32, height: 32)

                    VStack(alignment: .leading, spacing: 2) {
                        Text(journey.name)
                            .font(.subheadline.weight(.bold))
                            .lineLimit(1)
                        HStack(spacing: 8) {
                            Text("Day \(journey.currentDay)/\(journey.totalDays)")
                                .font(.caption2.weight(.medium))
                                .foregroundStyle(.secondary)
                            Text("·")
                                .foregroundStyle(.tertiary)
                            Text("\(todayCompleted)/\(todayTotal) done")
                                .font(.caption2.weight(.medium))
                                .foregroundStyle(todayCompleted == todayTotal && todayTotal > 0 ? .green : .secondary)
                        }
                    }

                    Spacer()

                    Image(systemName: "chevron.right")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.tertiary)
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
            }
            .buttonStyle(.plain)

            if !scheduled.isEmpty {
                Divider()
                    .padding(.horizontal, 14)

                VStack(spacing: 0) {
                    ForEach(scheduled) { item in
                        let quest = appState.allQuests.first(where: { $0.id == item.questId })
                        let status = journey.questStatusForDate(item.id, date: Date())
                        compactJourneyTaskRow(
                            item: item,
                            quest: quest,
                            status: status,
                            journey: journey
                        )
                    }
                }
                .padding(.horizontal, 14)
                .padding(.bottom, 8)
                .padding(.top, 4)
            }
        }
        .background(Color(.secondarySystemGroupedBackground), in: .rect(cornerRadius: 14))
    }

    private func compactJourneyTaskRow(item: JourneyQuestItem, quest: Quest?, status: JourneyQuestStatus, journey: Journey) -> some View {
        let pathColor = quest.map { PathColorHelper.color(for: $0.path) } ?? .secondary
        let isDone = status == .completed || status == .verified

        return HStack(spacing: 10) {
            Image(systemName: isDone ? "checkmark.circle.fill" : "circle")
                .font(.body)
                .foregroundStyle(isDone ? .green : .secondary.opacity(0.4))
                .contentTransition(.symbolEffect(.replace))

            if let quest {
                Image(systemName: quest.path.iconName)
                    .font(.caption2)
                    .foregroundStyle(pathColor)
                    .frame(width: 20)
            }

            VStack(alignment: .leading, spacing: 1) {
                Text(quest?.title ?? "Unknown")
                    .font(.subheadline.weight(.medium))
                    .lineLimit(1)
                    .strikethrough(isDone, color: .secondary)
                    .foregroundStyle(isDone ? .secondary : .primary)
                Text(item.timeDescription)
                    .font(.caption2.weight(.medium).monospacedDigit())
                    .foregroundStyle(item.isAnytime ? .tertiary : .secondary)
            }

            Spacer()

            if !isDone {
                if journey.verificationMode == .nonVerified && quest?.type == .verified {
                    Button {
                        if let quest {
                            appState.completeJourneyQuestNonVerified(
                                journeyId: journey.id,
                                questItemId: item.id,
                                quest: quest
                            )
                        }
                    } label: {
                        Text("Done")
                            .font(.caption2.weight(.bold))
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(.orange, in: Capsule())
                            .foregroundStyle(.white)
                    }
                    .buttonStyle(.plain)
                } else if quest?.type == .open || quest?.type == .event {
                    Button {
                        appState.updateJourneyQuestStatus(
                            journeyId: journey.id,
                            questItemId: item.id,
                            date: Date(),
                            status: .verified
                        )
                    } label: {
                        Text("Done")
                            .font(.caption2.weight(.bold))
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(.green, in: Capsule())
                            .foregroundStyle(.white)
                    }
                    .buttonStyle(.plain)
                } else if let quest, quest.type == .verified {
                    Button {
                        launchJourneyQuestEvidence(quest: quest, journeyId: journey.id, questItemId: item.id)
                    } label: {
                        HStack(spacing: 3) {
                            Image(systemName: "camera.fill")
                                .font(.system(size: 9))
                            Text("Submit")
                                .font(.caption2.weight(.bold))
                        }
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(pathColor, in: Capsule())
                        .foregroundStyle(.white)
                    }
                    .buttonStyle(.plain)
                }
            } else {
                Image(systemName: status == .verified ? "checkmark.seal.fill" : "checkmark")
                    .font(.caption)
                    .foregroundStyle(status == .verified ? .blue : .green)
            }
        }
        .padding(.vertical, 6)
    }

    private func launchJourneyQuestEvidence(quest: Quest, journeyId: String, questItemId: String) {
        pendingJourneyQuestItemId = questItemId
        let tempId = "journey_\(journeyId)_\(questItemId)"
        journeyEvidenceInstanceId = tempId
        journeyEvidenceQuest = quest

        let instance = QuestInstance(
            id: tempId,
            quest: quest,
            state: .active,
            mode: .solo,
            startedAt: Date().addingTimeInterval(-Double(quest.minCompletionMinutes) * 60),
            submittedAt: nil,
            verifiedAt: nil,
            groupId: nil
        )
        if !appState.activeInstances.contains(where: { $0.id == tempId }) {
            appState.activeInstances.append(instance)
        }

        if quest.isStepQuest {
            showJourneyStepQuest = true
        } else if quest.isTrackingQuest {
            showJourneyTracking = true
        } else if quest.evidenceType == .pushUpTracking {
            journeyPushUpLaunch = ExerciseLaunch(quest: quest, instanceId: journeyEvidenceInstanceId ?? tempId)
        } else if quest.evidenceType == .plankTracking {
            showJourneyPlank = true
        } else if quest.evidenceType == .wallSitTracking {
            showJourneyWallSit = true
        } else if quest.evidenceType == .jumpRopeTracking {
            journeyJumpRopeLaunch = ExerciseLaunch(quest: quest, instanceId: journeyEvidenceInstanceId ?? tempId)
        } else if quest.evidenceType == .meditationTracking {
            showJourneyMeditation = true
        } else if quest.evidenceType == .readingTracking {
            showJourneyReading = true
        } else if quest.isFocusQuest {
            journeyFocusBlockLaunch = FocusBlockLaunch(quest: quest, instanceId: journeyEvidenceInstanceId ?? tempId)
        } else if quest.isGratitudeQuest {
            showJourneyGratitude = true
        } else if quest.isAffirmationQuest {
            showJourneyAffirmation = true
        } else if quest.evidenceType == .dualPhoto {
            showJourneyDualPhoto = true
        } else if quest.isPlaceVerificationQuest {
            if quest.requiredPlaceType?.isGPSOnly == true {
                if let instanceId = journeyEvidenceInstanceId,
                   let instance = appState.activeInstances.first(where: { $0.id == instanceId }) {
                    if instance.canSubmit {
                        appState.submitEvidence(for: instance.id)
                    } else {
                        selectedActiveInstance = instance
                    }
                }
            } else {
                placeVerificationInstanceId = journeyEvidenceInstanceId
                showPlaceVerification = true
            }
        } else {
            showJourneyEvidence = true
        }
    }

    private var activeQuestsSection: some View {
        let inProgress = appState.activeInstances.filter { $0.state != .verified }
        let completed = appState.activeInstances.filter { $0.state == .verified }

        return VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Active Side Quests")
                    .font(.title3.weight(.bold))
                Text("\(appState.activeQuestCount)/5")
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.secondary)
                Spacer()
                if appState.activeInstances.count > 3 {
                    Button {
                        withAnimation(.snappy) { showAllActive.toggle() }
                    } label: {
                        Text(showAllActive ? "Show Less" : "Show All")
                            .font(.subheadline.weight(.medium))
                    }
                }
            }

            let visibleInProgress = showAllActive ? inProgress : Array(inProgress.prefix(3))

            ForEach(visibleInProgress) { instance in
                activeQuestCardItem(instance)
            }

            if !completed.isEmpty {
                completedQuestsSection(completed)
            }

            if appState.activeInstances.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "scroll")
                        .font(.largeTitle)
                        .foregroundStyle(.tertiary)
                    Text("No active side quests")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    Text("Accept a side quest below to get started!")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 24)
            }
        }
    }

    private func completedQuestsSection(_ completed: [QuestInstance]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: "checkmark.circle.fill")
                    .font(.subheadline)
                    .foregroundStyle(.green)
                Text("Completed")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.secondary)
                Text("\(completed.count)")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.green)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(.green.opacity(0.12), in: Capsule())
            }

            ForEach(completed) { instance in
                activeQuestCardItem(instance)
                    .opacity(0.7)
            }

            Button {
                withAnimation(.spring(response: 0.5, dampingFraction: 0.75)) {
                    appState.clearCompletedQuests()
                }
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "sparkles")
                        .font(.subheadline)
                        .foregroundStyle(.green)
                    Text("Clear \(completed.count) Completed")
                        .font(.subheadline.weight(.semibold))
                    Spacer()
                    Image(systemName: "xmark.circle.fill")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .padding(12)
                .frame(maxWidth: .infinity)
                .background(.green.opacity(0.08), in: .rect(cornerRadius: 12))
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .strokeBorder(.green.opacity(0.2), lineWidth: 1)
                )
            }
            .buttonStyle(.plain)
            .sensoryFeedback(.success, trigger: completed.count)
        }
    }

    private func activeQuestCardItem(_ instance: QuestInstance) -> some View {
        ActiveQuestCard(instance: instance, onSubmit: {
            if instance.quest.isStepQuest {
                stepQuestInstanceId = instance.id
                showStepQuest = true
            } else if instance.quest.isTrackingQuest {
                trackingInstanceId = instance.id
                showTrackingSession = true
            } else if instance.quest.evidenceType == .pushUpTracking {
                pushUpLaunch = ExerciseLaunch(quest: instance.quest, instanceId: instance.id)
            } else if instance.quest.evidenceType == .plankTracking {
                exerciseInstanceId = instance.id
                showPlankChallenge = true
            } else if instance.quest.evidenceType == .wallSitTracking {
                exerciseInstanceId = instance.id
                showWallSitChallenge = true
            } else if instance.quest.evidenceType == .jumpRopeTracking {
                jumpRopeLaunch = ExerciseLaunch(quest: instance.quest, instanceId: instance.id)
            } else if instance.quest.evidenceType == .meditationTracking {
                meditationInstanceId = instance.id
                showMeditationSession = true
            } else if instance.quest.evidenceType == .readingTracking {
                readingInstanceId = instance.id
                showReadingSession = true
            } else if instance.quest.isFocusQuest {
                focusBlockLaunch = FocusBlockLaunch(quest: instance.quest, instanceId: instance.id)
            } else if instance.quest.isGratitudeQuest {
                gratitudeInstanceId = instance.id
                showGratitudeLog = true
            } else if instance.quest.isAffirmationQuest {
                affirmationInstanceId = instance.id
                showAffirmationLog = true
            } else if instance.quest.evidenceType == .dualPhoto {
                dualPhotoInstanceId = instance.id
                showDualPhoto = true
            } else if instance.quest.isPlaceVerificationQuest {
                if instance.quest.requiredPlaceType?.isGPSOnly == true {
                    if instance.canSubmit {
                        appState.submitEvidence(for: instance.id)
                    }
                } else {
                    placeVerificationInstanceId = instance.id
                    showPlaceVerification = true
                }
            } else {
                evidenceInstanceId = instance.id
                showEvidenceCapture = true
            }
        }, onDrop: {
            withAnimation(.snappy) {
                appState.dropQuest(instance.id)
            }
        }, onClearFailed: {
            withAnimation(.snappy) {
                appState.clearFailedQuest(instance.id)
            }
        }, onDetail: {
            selectedActiveInstance = instance
        })
        .sensoryFeedback(.selection, trigger: instance.state)
        .transition(.asymmetric(
            insertion: .scale.combined(with: .opacity),
            removal: .scale(scale: 0.5).combined(with: .opacity).combined(with: .move(edge: .trailing))
        ))
    }

    private var discoverPathsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Quick Add")
                    .font(.title3.weight(.bold))
                Spacer()
                Button {
                    withAnimation(.snappy) { isEditingPaths.toggle() }
                } label: {
                    Image(systemName: isEditingPaths ? "checkmark.circle.fill" : "arrow.up.arrow.down.circle")
                        .font(.title3)
                        .foregroundStyle(isEditingPaths ? .green : .secondary)
                        .contentTransition(.symbolEffect(.replace))
                }
            }

            let orderedPaths = appState.pathOrder

            if isEditingPaths {
                reorderablePathList(orderedPaths)
            } else {
                ForEach(orderedPaths) { path in
                    if let quest = nextQuestForPath(path) {
                        QuickAddQuestCard(
                            quest: quest,
                            path: path,
                            hasCompleted: false,
                            isExpanded: expandedQuestId == quest.id,
                            isSaved: appState.isQuestSaved(quest.id),
                            isAlreadyActive: false,
                            streakMultiplier: LevelSystem.streakMultiplier(for: appState.profile.currentStreak),
                            isAtCap: appState.activeQuestCount >= 5,
                            onTap: {
                                withAnimation(.snappy(duration: 0.3)) {
                                    expandedQuestId = expandedQuestId == quest.id ? nil : quest.id
                                }
                            },
                            onAccept: {
                                appState.acceptQuest(quest, mode: .solo)
                                withAnimation(.snappy) {
                                    expandedQuestId = nil
                                    advancePathIndex(path)
                                }
                            },
                            onDismiss: {
                                withAnimation(.snappy) {
                                    expandedQuestId = nil
                                    advancePathIndex(path)
                                }
                            },
                            onToggleSave: { appState.toggleSavedQuest(quest.id) }
                        )
                    }
                }
            }
        }
    }

    private func handleActiveQuestSubmit(_ instance: QuestInstance) {
        if instance.quest.isStepQuest {
            stepQuestInstanceId = instance.id
            showStepQuest = true
        } else if instance.quest.isTrackingQuest {
            trackingInstanceId = instance.id
            showTrackingSession = true
        } else if instance.quest.evidenceType == .pushUpTracking {
            pushUpLaunch = ExerciseLaunch(quest: instance.quest, instanceId: instance.id)
        } else if instance.quest.evidenceType == .plankTracking {
            exerciseInstanceId = instance.id
            showPlankChallenge = true
        } else if instance.quest.evidenceType == .wallSitTracking {
            exerciseInstanceId = instance.id
            showWallSitChallenge = true
        } else if instance.quest.evidenceType == .jumpRopeTracking {
            jumpRopeLaunch = ExerciseLaunch(quest: instance.quest, instanceId: instance.id)
        } else if instance.quest.evidenceType == .meditationTracking {
            meditationInstanceId = instance.id
            showMeditationSession = true
        } else if instance.quest.evidenceType == .readingTracking {
            readingInstanceId = instance.id
            showReadingSession = true
        } else if instance.quest.isFocusQuest {
            focusBlockLaunch = FocusBlockLaunch(quest: instance.quest, instanceId: instance.id)
        } else if instance.quest.isGratitudeQuest {
            gratitudeInstanceId = instance.id
            showGratitudeLog = true
        } else if instance.quest.isAffirmationQuest {
            affirmationInstanceId = instance.id
            showAffirmationLog = true
        } else if instance.quest.evidenceType == .dualPhoto {
            dualPhotoInstanceId = instance.id
            showDualPhoto = true
        } else if instance.quest.isPlaceVerificationQuest {
            if instance.quest.requiredPlaceType?.isGPSOnly == true {
                if instance.canSubmit {
                    appState.submitEvidence(for: instance.id)
                }
            } else {
                placeVerificationInstanceId = instance.id
                showPlaceVerification = true
            }
        } else {
            evidenceInstanceId = instance.id
            showEvidenceCapture = true
        }
    }

    private func questsForQuickAdd(_ path: QuestPath) -> [Quest] {
        appState.allQuests.filter { $0.path == path && $0.type != .master && $0.type != .event }
    }

    private func nextQuestForPath(_ path: QuestPath) -> Quest? {
        let quests = questsForQuickAdd(path)
        guard !quests.isEmpty else { return nil }
        let startIndex = pathQuestIndices[path.rawValue] ?? 0
        for offset in 0..<quests.count {
            let quest = quests[(startIndex + offset) % quests.count]
            if !appState.isQuestAlreadyActive(quest.id) {
                return quest
            }
        }
        return nil
    }

    private func advancePathIndex(_ path: QuestPath) {
        let count = questsForQuickAdd(path).count
        guard count > 0 else { return }
        let current = pathQuestIndices[path.rawValue] ?? 0
        pathQuestIndices[path.rawValue] = (current + 1) % count
    }

    private func reorderablePathList(_ paths: [QuestPath]) -> some View {
        VStack(spacing: 8) {
            ForEach(paths) { path in
                reorderablePathRow(path)
            }

            Text("Drag to reorder your preferred path priority")
                .font(.caption)
                .foregroundStyle(.tertiary)
                .frame(maxWidth: .infinity)
                .padding(.top, 4)
        }
    }

    private func reorderablePathRow(_ path: QuestPath) -> some View {
        let pathColor = PathColorHelper.color(for: path)
        let quest = appState.dailyQuestForPath(path)
        let completed = quest.map { (appState.questCompletionCounts[$0.id] ?? 0) > 0 } ?? false

        return HStack(spacing: 12) {
            Image(systemName: "line.3.horizontal")
                .font(.body.weight(.medium))
                .foregroundStyle(.tertiary)

            Image(systemName: path.iconName)
                .font(.title3)
                .foregroundStyle(pathColor)
                .frame(width: 36, height: 36)
                .background(pathColor.opacity(0.12), in: .rect(cornerRadius: 10))

            VStack(alignment: .leading, spacing: 2) {
                Text(path.rawValue)
                    .font(.subheadline.weight(.bold))
                if let q = quest {
                    Text(q.title)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }

            Spacer()

            Image(systemName: completed ? "checkmark.circle.fill" : "xmark.circle")
                .font(.title3)
                .foregroundStyle(completed ? .green : .secondary.opacity(0.4))
        }
        .padding(12)
        .background(Color(.secondarySystemGroupedBackground), in: .rect(cornerRadius: 14))
        .draggable(path.rawValue) {
            HStack(spacing: 8) {
                Image(systemName: path.iconName)
                    .foregroundStyle(pathColor)
                Text(path.rawValue)
                    .font(.subheadline.weight(.bold))
            }
            .padding(10)
            .background(.ultraThinMaterial, in: .rect(cornerRadius: 10))
        }
        .dropDestination(for: String.self) { items, _ in
            guard let droppedRaw = items.first,
                  let droppedPath = QuestPath(rawValue: droppedRaw),
                  let fromIdx = appState.pathOrder.firstIndex(of: droppedPath),
                  let toIdx = appState.pathOrder.firstIndex(of: path) else { return false }
            withAnimation(.snappy) {
                appState.movePathOrder(from: IndexSet(integer: fromIdx), to: toIdx > fromIdx ? toIdx + 1 : toIdx)
            }
            return true
        }
    }
}

struct QuickAddQuestCard: View {
    let quest: Quest
    let path: QuestPath
    let hasCompleted: Bool
    let isExpanded: Bool
    let isSaved: Bool
    let isAlreadyActive: Bool
    let streakMultiplier: Double
    let isAtCap: Bool
    let onTap: () -> Void
    let onAccept: () -> Void
    let onDismiss: () -> Void
    let onToggleSave: () -> Void

    private var pathColor: Color {
        PathColorHelper.color(for: path)
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                HStack(spacing: 14) {
                    Image(systemName: path.iconName)
                        .font(.title3)
                        .foregroundStyle(pathColor)
                        .frame(width: 36, height: 36)
                        .background(pathColor.opacity(0.12), in: .rect(cornerRadius: 10))

                    VStack(alignment: .leading, spacing: 3) {
                        HStack(spacing: 6) {
                            Text(path.rawValue)
                                .font(.caption.weight(.bold))
                                .foregroundStyle(pathColor)
                            if quest.type == .verified {
                                Image(systemName: "checkmark.seal.fill")
                                    .font(.system(size: 9))
                                    .foregroundStyle(.blue)
                            }
                        }
                        Text(quest.title)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.primary)
                            .lineLimit(1)
                        HStack(spacing: 8) {
                            Label("\(Int(Double(quest.xpReward) * streakMultiplier)) XP", systemImage: "bolt.fill")
                                .font(.caption2.weight(.semibold))
                                .foregroundStyle(.orange)
                            if streakMultiplier > 1.0 {
                                Text("\(String(format: "%.1f", streakMultiplier))x")
                                    .font(.system(size: 9, weight: .black))
                                    .foregroundStyle(.white)
                                    .padding(.horizontal, 4)
                                    .padding(.vertical, 1)
                                    .background(.orange, in: Capsule())
                            }
                            Label("\(Int(Double(quest.goldReward) * streakMultiplier))", systemImage: "dollarsign.circle.fill")
                                .font(.caption2.weight(.semibold))
                                .foregroundStyle(.yellow)
                        }
                    }
                }
                .contentShape(Rectangle())
                .onTapGesture { onTap() }

                Spacer(minLength: 4)

                if hasCompleted {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.title2)
                        .foregroundStyle(.green)
                } else if isAlreadyActive {
                    HStack(spacing: 4) {
                        Image(systemName: "bolt.circle.fill")
                            .font(.title2)
                            .foregroundStyle(.blue)
                        Text("Active")
                            .font(.caption2.weight(.bold))
                            .foregroundStyle(.blue)
                    }
                } else {
                    HStack(spacing: 8) {
                        Button {
                            onAccept()
                        } label: {
                            Image(systemName: "checkmark.circle.fill")
                                .font(.title2)
                                .foregroundStyle(isAtCap ? Color.secondary.opacity(0.3) : Color.green)
                                .frame(width: 44, height: 44)
                                .contentShape(Rectangle())
                        }
                        .disabled(isAtCap)

                        Button {
                            onDismiss()
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .font(.title2)
                                .foregroundStyle(.secondary.opacity(0.35))
                                .frame(width: 44, height: 44)
                                .contentShape(Rectangle())
                        }
                    }
                }
            }
            .padding(14)

            if isExpanded && !hasCompleted && !isAlreadyActive {
                expandedDetail
            }
        }
        .background {
            RoundedRectangle(cornerRadius: 16)
                .fill(
                    .linearGradient(
                        colors: [pathColor.opacity(0.08), Color(.secondarySystemGroupedBackground)],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                )
        }
        .clipShape(.rect(cornerRadius: 16))
    }

    private var expandedDetail: some View {
        VStack(alignment: .leading, spacing: 12) {
            Divider()
                .padding(.horizontal, 14)

            VStack(alignment: .leading, spacing: 8) {
                Text(quest.description)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                HStack(spacing: 12) {
                    Label(quest.difficulty.rawValue, systemImage: "gauge.with.dots.needle.33percent")
                        .font(.caption2.weight(.medium))
                        .foregroundStyle(.secondary)
                    Label(quest.type.rawValue, systemImage: quest.type == .verified ? "checkmark.seal" : "sparkles")
                        .font(.caption2.weight(.medium))
                        .foregroundStyle(.secondary)
                    if let evidenceType = quest.evidenceType {
                        Label(evidenceType.rawValue, systemImage: "camera")
                            .font(.caption2.weight(.medium))
                            .foregroundStyle(.secondary)
                    }
                }

                if quest.hasTimeWindow, let desc = quest.timeWindowDescription {
                    HStack(spacing: 4) {
                        Image(systemName: "clock.fill")
                            .font(.caption2)
                        Text(desc)
                            .font(.caption2.weight(.medium))
                    }
                    .foregroundStyle(quest.isWithinTimeWindow ? .green : .orange)
                }

                HStack(spacing: 12) {
                    Label("\(Int(Double(quest.xpReward) * streakMultiplier)) XP", systemImage: "bolt.fill")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.orange)
                    Label("\(Int(Double(quest.goldReward) * streakMultiplier))", systemImage: "dollarsign.circle.fill")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.yellow)
                    if quest.diamondReward > 0 {
                        Label("\(quest.diamondReward)", systemImage: "diamond.fill")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.cyan)
                    }
                    Spacer()
                    Button {
                        onToggleSave()
                    } label: {
                        Image(systemName: isSaved ? "heart.fill" : "heart")
                            .font(.body)
                            .foregroundStyle(isSaved ? .pink : .secondary.opacity(0.4))
                            .contentTransition(.symbolEffect(.replace))
                    }
                    .buttonStyle(.plain)
                }

                HStack(spacing: 10) {
                    Button {
                        onAccept()
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: "plus.circle.fill")
                                .font(.subheadline)
                            Text("Accept Side Quest")
                                .font(.subheadline.weight(.semibold))
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .background(isAtCap ? Color(.quaternarySystemFill) : pathColor, in: Capsule())
                        .foregroundStyle(isAtCap ? Color.secondary : Color.white)
                    }
                    .buttonStyle(.plain)
                    .disabled(isAtCap)

                    Button {
                        onDismiss()
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: "xmark")
                                .font(.subheadline.weight(.medium))
                            Text("Skip")
                                .font(.subheadline.weight(.semibold))
                        }
                        .padding(.horizontal, 20)
                        .padding(.vertical, 10)
                        .background(Color(.quaternarySystemFill), in: Capsule())
                        .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                }

                if isAtCap {
                    Text("Quest cap reached (5/5)")
                        .font(.caption2)
                        .foregroundStyle(.orange)
                        .frame(maxWidth: .infinity)
                }
            }
            .padding(.horizontal, 14)
            .padding(.bottom, 14)
        }
        .transition(.opacity.combined(with: .move(edge: .top)))
    }
}

struct FeaturedCountdown: View {
    let expiresAt: Date
    @State private var timeRemaining: TimeInterval = 0
    private let timer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: "timer")
                .font(.caption2)
            Text(formattedTime)
                .font(.caption.weight(.bold).monospacedDigit())
        }
        .foregroundStyle(timeRemaining < 3600 ? .red : .orange)
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background((timeRemaining < 3600 ? Color.red : Color.orange).opacity(0.12), in: Capsule())
        .onAppear { timeRemaining = max(0, expiresAt.timeIntervalSinceNow) }
        .onReceive(timer) { _ in
            timeRemaining = max(0, expiresAt.timeIntervalSinceNow)
        }
    }

    private var formattedTime: String {
        let total = Int(timeRemaining)
        let hours = total / 3600
        let minutes = (total % 3600) / 60
        let seconds = total % 60
        if hours > 0 {
            return "\(hours)h \(minutes)m"
        }
        return "\(minutes):\(String(format: "%02d", seconds))"
    }
}

struct CircularProgressView: View {
    let progress: Double
    var color: Color = .blue
    var lineWidth: CGFloat = 3

    var body: some View {
        ZStack {
            Circle()
                .stroke(color.opacity(0.2), lineWidth: lineWidth)
            Circle()
                .trim(from: 0, to: progress)
                .stroke(color, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                .rotationEffect(.degrees(-90))
        }
    }
}

struct StreakDetailSheet: View {
    let appState: AppState

    private var streak: Int { appState.profile.currentStreak }
    private var multiplier: Double { LevelSystem.streakMultiplier(for: streak) }
    private var tierName: String { LevelSystem.streakTierName(for: streak) }
    private var nextMilestone: Int { LevelSystem.nextStreakMilestone(for: streak) }

    private var progress: Double {
        let prev = previousMilestone(for: streak)
        let next = nextMilestone
        guard next > prev else { return 1.0 }
        return Double(streak - prev) / Double(next - prev)
    }

    private var hasCompletedToday: Bool {
        if let last = appState.lastStreakDate {
            return Calendar.current.isDate(Calendar.current.startOfDay(for: last), inSameDayAs: Date())
        }
        return false
    }

    private var todayQuestCount: Int {
        appState.activeInstances.count
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    VStack(spacing: 16) {
                        ZStack {
                            Circle()
                                .fill(
                                    RadialGradient(
                                        colors: streak >= 3 ? [.orange.opacity(0.3), .red.opacity(0.15)] : [Color(.tertiarySystemFill), Color(.quaternarySystemFill)],
                                        center: .center,
                                        startRadius: 8,
                                        endRadius: 40
                                    )
                                )
                                .frame(width: 80, height: 80)

                            Image(systemName: "flame.fill")
                                .font(.system(size: 36))
                                .foregroundStyle(
                                    streak >= 3
                                        ? LinearGradient(colors: [.yellow, .orange, .red], startPoint: .top, endPoint: .bottom)
                                        : LinearGradient(colors: [.gray, .gray.opacity(0.6)], startPoint: .top, endPoint: .bottom)
                                )
                                .symbolEffect(.variableColor.iterative, options: .repeating, value: streak >= 3)
                        }

                        Text("\(streak) Day Streak")
                            .font(.title.weight(.black))

                        Text(tierName)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(streak >= 3 ? .orange : .secondary)

                        if multiplier > 1.0 {
                            Text("\(String(format: "%.1f", multiplier))x XP & Gold")
                                .font(.headline.weight(.bold))
                                .foregroundStyle(.orange)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 6)
                                .background(.orange.opacity(0.12), in: Capsule())
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
                    .listRowBackground(Color.clear)
                }

                Section {
                    if hasCompletedToday {
                        HStack(spacing: 12) {
                            Image(systemName: "checkmark.seal.fill")
                                .font(.title2)
                                .foregroundStyle(.green)
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Streak Secured")
                                    .font(.subheadline.weight(.bold))
                                    .foregroundStyle(.green)
                                Text("You've completed a quest today. Keep it up tomorrow!")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .padding(.vertical, 4)
                    } else {
                        HStack(spacing: 12) {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .font(.title2)
                                .foregroundStyle(.orange)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(streak > 0 ? "Streak at Risk" : "Start Your Streak")
                                    .font(.subheadline.weight(.bold))
                                    .foregroundStyle(streak > 0 ? .orange : .primary)
                                Text(streak > 0
                                     ? "Complete any quest before midnight to keep your \(streak)-day streak alive."
                                     : "Complete any quest today to start building your streak.")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .padding(.vertical, 4)

                        if todayQuestCount > 0 {
                            HStack(spacing: 8) {
                                Image(systemName: "scroll.fill")
                                    .foregroundStyle(.blue)
                                Text("You have \(todayQuestCount) active quest\(todayQuestCount == 1 ? "" : "s") to complete")
                                    .font(.subheadline)
                            }
                        } else {
                            HStack(spacing: 8) {
                                Image(systemName: "plus.circle.fill")
                                    .foregroundStyle(.blue)
                                Text("Accept a quest to keep your streak going")
                                    .font(.subheadline)
                            }
                        }
                    }
                } header: {
                    Text("Today's Status")
                }

                Section("Multiplier") {
                    HStack {
                        Label("Current Bonus", systemImage: "bolt.fill")
                        Spacer()
                        Text("\(String(format: "%.1f", multiplier))x XP & Gold")
                            .foregroundStyle(.orange)
                            .fontWeight(.bold)
                    }
                    if streak < 60 {
                        HStack {
                            Label("Next Tier", systemImage: "arrow.up.circle")
                            Spacer()
                            Text("\(nextMilestone) days")
                                .foregroundStyle(.secondary)
                        }
                        VStack(alignment: .leading, spacing: 6) {
                            HStack {
                                Text("Progress")
                                    .font(.subheadline)
                                Spacer()
                                Text("\(streak)/\(nextMilestone)")
                                    .font(.caption.weight(.semibold).monospacedDigit())
                                    .foregroundStyle(.secondary)
                            }
                            GeometryReader { geo in
                                ZStack(alignment: .leading) {
                                    Capsule()
                                        .fill(Color(.quaternarySystemFill))
                                    Capsule()
                                        .fill(
                                            LinearGradient(colors: [.orange, .red], startPoint: .leading, endPoint: .trailing)
                                        )
                                        .frame(width: max(0, geo.size.width * progress))
                                }
                            }
                            .frame(height: 6)
                        }
                    }
                }

                Section("Streak Tiers") {
                    streakTierRow("No Bonus", range: "0–2 days", mult: "1.0x", active: streak < 3)
                    streakTierRow("Warming Up", range: "3–6 days", mult: "1.1x", active: streak >= 3 && streak < 7)
                    streakTierRow("On Fire", range: "7–13 days", mult: "1.25x", active: streak >= 7 && streak < 14)
                    streakTierRow("Blazing", range: "14–29 days", mult: "1.5x", active: streak >= 14 && streak < 30)
                    streakTierRow("Inferno", range: "30–59 days", mult: "1.75x", active: streak >= 30 && streak < 60)
                    streakTierRow("Legendary", range: "60+ days", mult: "2.0x", active: streak >= 60)
                }
            }
            .navigationTitle("Streak")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {}
                }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }

    private func streakTierRow(_ name: String, range: String, mult: String, active: Bool) -> some View {
        HStack {
            if active {
                Image(systemName: "flame.fill")
                    .foregroundStyle(.orange)
            } else {
                Image(systemName: "circle")
                    .foregroundStyle(.tertiary)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(name)
                    .font(.subheadline.weight(active ? .bold : .regular))
                Text(range)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Text(mult)
                .font(.subheadline.weight(.semibold).monospacedDigit())
                .foregroundStyle(active ? .orange : .secondary)
        }
    }

    private func previousMilestone(for streak: Int) -> Int {
        switch streak {
        case 0...2: return 0
        case 3...6: return 3
        case 7...13: return 7
        case 14...29: return 14
        case 30...59: return 30
        default: return 60
        }
    }
}

struct StepsDetailSheet: View {
    let profile: UserProfile
    let stepCoinsAwardedToday: Int

    var body: some View {
        NavigationStack {
            List {
                Section {
                    HStack {
                        Label("Today", systemImage: "figure.walk")
                        Spacer()
                        Text("\(profile.stepsToday.formatted()) steps")
                            .foregroundStyle(.secondary)
                    }
                    HStack {
                        Label("This Week", systemImage: "calendar")
                        Spacer()
                        Text("\(profile.stepsThisWeek.formatted()) steps")
                            .foregroundStyle(.secondary)
                    }
                }
                Section("Rewards") {
                    HStack {
                        Label("Coins Earned Today", systemImage: "dollarsign.circle.fill")
                        Spacer()
                        Text("\(stepCoinsAwardedToday)")
                            .foregroundStyle(.orange)
                    }
                    HStack {
                        Label("Daily Cap", systemImage: "info.circle")
                        Spacer()
                        Text("50 coins / 10,000 steps")
                            .foregroundStyle(.secondary)
                            .font(.caption)
                    }
                }
            }
            .navigationTitle("Steps")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {}
                }
            }
        }
        .presentationDetents([.medium])
        .presentationDragIndicator(.visible)
    }
}

private struct QuickHomePullOffsetPreferenceKey: PreferenceKey {
    static var defaultValue: CGFloat = 0

    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}
