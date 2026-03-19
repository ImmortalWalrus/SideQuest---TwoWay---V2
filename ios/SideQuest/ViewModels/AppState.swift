import SwiftUI
import UIKit
import CoreLocation
import UserNotifications
import AVFoundation

@Observable
class AppState {
    var auth = AuthService.shared
    var api = APIService.shared
    var hasOnboarded: Bool = UserDefaults.standard.bool(forKey: "hasOnboarded")
    var isAuthenticated: Bool = false
    var needsProfileSetup: Bool = false
    var selectedTab: Int = 0
    var profile: UserProfile = SampleData.newUserProfile
    var activeInstances: [QuestInstance] = [] {
        didSet {
            guard hasConfiguredAutoCheckIn, !isPerformingAutoCheckInMutation else { return }
            refreshAutoCheckInMonitoring()
        }
    }
    var allQuests: [Quest] = SampleData.quests
    var notifications: [AppNotification] = []
    var milestones: [Milestone] = SampleData.milestones
    var masterContracts: [MasterContract] = SampleData.masterContracts
    var leaderboard: [LeaderboardEntry] = []
    var activityFeed: [ActivityItem] = []
    var pendingRewards: [RewardEvent] = []
    var showRewardOverlay: Bool = false
    var completedHistory: [RewardEvent] = []
    var openPlayHistory: [QuestInstance] = []
    var notificationsEnabled: Bool = UserDefaults.standard.object(forKey: "notificationsEnabled") as? Bool ?? true
    var stepsEnabled: Bool = UserDefaults.standard.object(forKey: "stepsEnabled") as? Bool ?? false
    var deepLinkQuestId: String?
    var deepLinkDestination: DeepLinkDestination?
    var trackingSessions: [String: TrackingSession] = [:]
    var completedSessions: [String: TrackingSession] = [:]
    var exerciseSessions: [String: ExerciseSession] = [:]
    var completedExerciseSessions: [String: ExerciseSession] = [:]
    var meditationSessions: [String: MeditationSession] = [:]
    var completedMeditationSessions: [String: MeditationSession] = [:]
    var readingSessions: [String: ReadingSession] = [:]
    var completedReadingSessions: [String: ReadingSession] = [:]
    var focusSessions: [String: FocusSession] = [:]
    var completedFocusSessions: [String: FocusSession] = [:]
    var dailyCompletions: [Date: Int] = [:]
    var lastStreakDate: Date? = nil
    var savedQuestIds: [String] = []
    var brainScores: [String: Int] = [:]
    var solarService = SolarEventService()
    var timeIntegrity = TimeIntegrityService.shared
    var stepCountService = StepCountService()
    var groupRunSessions: [String: GroupRunSession] = [:]

    var questCompletionCounts: [String: Int] = [:]
    var pendingFocusLaunchInstanceId: String?
    var dailyQuests: [Quest] = []
    var dailyQuestDate: Date? = nil
    var pathOrder: [QuestPath] = {
        if let saved = UserDefaults.standard.array(forKey: "pathOrder") as? [String] {
            let paths = saved.compactMap { QuestPath(rawValue: $0) }
            if paths.count == 3 { return paths }
        }
        return QuestPath.allCases.map { $0 }
    }()
    var friends: [Friend] = []
    var friendRequests: [FriendRequest] = []
    var isImmersive: Bool = false
    var pendingMapCategory: MapQuestCategory? = nil
    var showLevelUp: Bool = false
    var newLevelReached: Int = 0
    var journeys: [Journey] = []
    var journeyTemplates: [JourneyTemplate] = []
    var customQuests: [CustomQuest] = []
    var communitySubmissions: [CustomQuest] = []
    var externalLocationDiscoverySnapshot: ExternalLocationDiscoverySnapshot?
    var externalEventSnapshot: ExternalEventIngestionSnapshot?
    var externalVenueSnapshot: ExternalVenueDiscoverySnapshot?
    var externalEventFeed: [ExternalEvent] = []
    var eventsTabExternalEventFeed: [ExternalEvent] = []
    var eventsTabExpandedExternalEventFeed: [ExternalEvent] = []
    var exclusiveExternalEventFeed: [ExternalEvent] = []
    var externalEventSearchLocation: ExternalEventSearchLocation?
    var externalEventSortOption: ExternalEventSortOption = .recommended
    var externalEventFilterOption: ExternalEventFilterOption = .all
    var externalEventsLastFetchedAt: Date?
    var externalEventsError: String?
    var isRefreshingExternalEvents: Bool = false
    var isLoadingMoreExternalEvents: Bool = false
    var hasMoreExternalEvents: Bool = false
    var externalEventSpoofPostalCode: String = UserDefaults.standard.string(forKey: "externalEventSpoofPostalCode") ?? ""
    var calendarService = CalendarService.shared
    var dailyXPEarned: [Date: Int] = [:]
    var storyEngine = StoryEngine()
    var showStoryEvent: Bool = false
    var visitedPOIs: [VisitedPOI] = []
    var savedGym: SavedGym? = nil {
        didSet {
            guard hasConfiguredAutoCheckIn else { return }
            refreshAutoCheckInMonitoring()
        }
    }
    var networkMonitor = NetworkMonitorService.shared
    var toastQueue: [ToastItem] = []
    var currentToast: ToastItem? = nil
    var showOfflineBanner: Bool = false
    var onboardingData: OnboardingData = PersistenceService.loadOnboardingData() ?? .empty
    var showOnboardingRefresh: Bool = false
    var stepCoinsAwardedToday: Int = {
        let key = "stepCoinsAwardedDate"
        let today = Calendar.current.startOfDay(for: Date())
        if let saved = UserDefaults.standard.object(forKey: key) as? Date,
           Calendar.current.isDate(saved, inSameDayAs: today) {
            return UserDefaults.standard.integer(forKey: "stepCoinsAwardedCount")
        }
        return 0
    }()
    private var previousLevel: Int = 0
    private var solarUpdateApplied: Bool = false
    private let defaultExternalEventPreviewPostalCode = "90069"
    private var externalEventSourcePageDepth: Int = 2
    private var externalEventNextCursors: [ExternalEventSource: ExternalEventSourceCursor] = [:]
    private var externalEventRefreshGeneration: Int = 0
    private var externalEventFeedBuildGeneration: Int = 0
    private var externalEventSnapshotIntent: ExternalDiscoveryIntent?
    private var externalEventImagePrefetchTask: Task<Void, Never>?
    private var externalEventFeedRebuildTask: Task<Void, Never>?
    private var externalDiscoveryRestoreTask: Task<Void, Never>?
    var externalEventImageRefreshNonce: Int = 0
    private let persistedExternalDiscoveryMaxAge: TimeInterval = 60 * 60 * 24
    private let externalEventService = ExternalEventIngestionService(configuration: .sideQuestPrototype())
    private let externalLiveLocationDiscoveryService = ExternalLiveLocationDiscoveryService(configuration: .sideQuestPrototype())
    private let supabaseEventFeedCacheService = SupabaseEventFeedCacheService(configuration: .fromEnvironment())
    private let questAutoCheckInService = QuestAutoCheckInService()
    private var autoCheckInTickTimer: Timer?
    private var hasConfiguredAutoCheckIn = false
    private var isPerformingAutoCheckInMutation = false

    var todayXPEarned: Int {
        let today = Calendar.current.startOfDay(for: Date())
        return dailyXPEarned[today] ?? 0
    }

    var dailyXPRemaining: Int {
        max(0, XPGuardrails.hardDailyCap - todayXPEarned)
    }

    var isAtDailyCap: Bool {
        todayXPEarned >= XPGuardrails.hardDailyCap
    }

    var isPastSoftCap: Bool {
        todayXPEarned >= XPGuardrails.softDailyCap
    }

    init() {
        loadPersistedData()
        restorePersistedExternalDiscoveryState()
        configureAutoCheckIn()
        normalizeCosmeticState()
        ensureMinimumGoldBalance()
        previousLevel = profile.level
        refreshDailyQuests()
        syncWidgetData()
        loadJourneyData()
        generateSampleTemplates()
        loadCustomQuestData()
        loadStoryData()
        auth.checkExistingSession()
        if auth.isAuthenticated {
            isAuthenticated = true
            if let uid = auth.currentUserId, profile.id.isEmpty {
                profile.id = uid
            }
        }
    }

    private func configureAutoCheckIn() {
        questAutoCheckInService.onLocationUpdate = { [weak self] location in
            self?.handleAutoCheckInLocationUpdate(location)
        }
        questAutoCheckInService.onAuthorizationChange = { [weak self] _ in
            self?.refreshAutoCheckInMonitoring()
        }
        hasConfiguredAutoCheckIn = true
        refreshAutoCheckInMonitoring()
    }

    private func activeAutoCheckInQuestIndices() -> [Int] {
        activeInstances.indices.filter { index in
            let instance = activeInstances[index]
            return instance.state == .active
                && instance.isGPSAutoCheckInQuest
                && verificationTargetCoordinate(for: instance.quest) != nil
                && !instance.isAutoCheckInComplete
        }
    }

    private func verificationTargetCoordinate(for quest: Quest) -> CLLocationCoordinate2D? {
        if quest.requiredPlaceType == .gym {
            return savedGym?.coordinate
        }
        guard let latitude = quest.verificationLatitude,
              let longitude = quest.verificationLongitude else {
            return nil
        }
        return CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }

    private func refreshAutoCheckInMonitoring() {
        let trackedIndices = activeAutoCheckInQuestIndices()
        guard !trackedIndices.isEmpty else {
            questAutoCheckInService.stopMonitoring()
            stopAutoCheckInTicking()
            return
        }

        questAutoCheckInService.startMonitoring()
        if let location = questAutoCheckInService.currentLocation {
            handleAutoCheckInLocationUpdate(location)
        } else {
            updateAutoCheckInTickingState()
        }
    }

    private func handleAutoCheckInLocationUpdate(_ location: CLLocation) {
        let now = Date()
        var didChange = false
        isPerformingAutoCheckInMutation = true

        for index in activeAutoCheckInQuestIndices() {
            guard let target = verificationTargetCoordinate(for: activeInstances[index].quest) else { continue }
            let targetLocation = CLLocation(latitude: target.latitude, longitude: target.longitude)
            let radius = Double(activeInstances[index].quest.requiredPlaceType?.gpsRadiusMeters ?? 100)
            let isInRange = location.distance(from: targetLocation) <= radius

            if activeInstances[index].isAutoCheckInInRange != isInRange {
                activeInstances[index].autoCheckInInRange = isInRange
                didChange = true
            }

            if isInRange {
                if activeInstances[index].autoCheckInStartedAt == nil {
                    activeInstances[index].autoCheckInStartedAt = now
                    didChange = true
                }
                if activeInstances[index].autoCheckInLastTickAt == nil {
                    activeInstances[index].autoCheckInLastTickAt = now
                    didChange = true
                }
            } else if activeInstances[index].autoCheckInLastTickAt != nil {
                activeInstances[index].autoCheckInLastTickAt = nil
                didChange = true
            }
        }
        isPerformingAutoCheckInMutation = false

        if didChange {
            PersistenceService.saveActiveInstances(activeInstances)
        }
        updateAutoCheckInTickingState()
    }

    private func updateAutoCheckInTickingState() {
        let shouldTick = activeInstances.contains { instance in
            instance.state == .active
                && instance.isGPSAutoCheckInQuest
                && instance.isAutoCheckInInRange
                && !instance.isAutoCheckInComplete
        }

        if shouldTick {
            startAutoCheckInTickingIfNeeded()
        } else {
            stopAutoCheckInTicking()
        }
    }

    private func startAutoCheckInTickingIfNeeded() {
        guard autoCheckInTickTimer == nil else { return }
        autoCheckInTickTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            self?.tickAutoCheckIns()
        }
    }

    private func stopAutoCheckInTicking() {
        autoCheckInTickTimer?.invalidate()
        autoCheckInTickTimer = nil
    }

    private func tickAutoCheckIns() {
        let now = Date()
        var didChange = false
        isPerformingAutoCheckInMutation = true

        for index in activeInstances.indices {
            guard activeInstances[index].state == .active,
                  activeInstances[index].isGPSAutoCheckInQuest,
                  activeInstances[index].isAutoCheckInInRange,
                  !activeInstances[index].isAutoCheckInComplete else {
                continue
            }

            let previousTick = activeInstances[index].autoCheckInLastTickAt ?? now
            let delta = now.timeIntervalSince(previousTick)
            guard delta >= 0.5 else { continue }

            let increment = max(1, Int(delta.rounded(.down)))
            let required = activeInstances[index].autoCheckInRequiredSeconds
            let nextElapsed = min(required, activeInstances[index].autoCheckInElapsedSecondsValue + increment)

            if nextElapsed != activeInstances[index].autoCheckInElapsedSecondsValue {
                activeInstances[index].autoCheckInElapsedSeconds = nextElapsed
                didChange = true
            }
            activeInstances[index].autoCheckInLastTickAt = now

            if nextElapsed >= required && activeInstances[index].autoCheckInCompletedAt == nil {
                activeInstances[index].autoCheckInCompletedAt = now
                activeInstances[index].autoCheckInLastTickAt = nil
                didChange = true
                showToast(
                    .success,
                    title: "Check-In Ready",
                    message: "\(activeInstances[index].quest.title) is ready to submit."
                )
            }
        }
        isPerformingAutoCheckInMutation = false

        if didChange {
            PersistenceService.saveActiveInstances(activeInstances)
        }
        updateAutoCheckInTickingState()
    }

    private func ensureMinimumGoldBalance() {
        guard profile.gold < 10_000 else { return }
        profile.gold = 10_000
        saveState()
    }

    func checkNetworkStatus() {
    }

    func showToast(_ style: ToastStyle, title: String, message: String, duration: Double = 3.5) {
        let toast = ToastItem(style: style, title: title, message: message, duration: duration)
        toastQueue.append(toast)
        if currentToast == nil {
            presentNextToast()
        }
    }

    func dismissCurrentToast() {
        currentToast = nil
        presentNextToast()
    }

    private func presentNextToast() {
        guard !toastQueue.isEmpty else { return }
        currentToast = toastQueue.removeFirst()
    }

    func showOfflineErrorIfNeeded(action: String) -> Bool {
        return false
    }

    func onAuthCompleted(isNewUser: Bool) {
        isAuthenticated = true
        if let uid = auth.currentUserId {
            profile.id = uid
        }
        if isNewUser {
            needsProfileSetup = true
        } else {
            if hasOnboarded {
                // Returning user with local data
            } else {
                needsProfileSetup = true
            }
        }
    }

    func completeProfileSetup() {
        needsProfileSetup = false
        saveState()
    }

    func refreshSocialData() async {
    }

    func syncQuestInstanceToBackend(_ instance: QuestInstance) {
    }

    func removeQuestInstanceFromBackend(_ instanceId: String) {
    }

    func refreshSolarTimes() {
        solarService.requestLocationOnce()
    }

    func applySolarTimeWindows() {
        guard solarService.isReady, !solarUpdateApplied else { return }
        solarUpdateApplied = true
        updateSunQuestWindows()
    }

    func updateSunQuestWindows() {
        for i in allQuests.indices {
            guard let sunType = allQuests[i].sunEventType else { continue }
            switch sunType {
            case .sunrise:
                if let start = solarService.sunriseWindowStart(),
                   let end = solarService.sunriseWindowEnd() {
                    allQuests[i].timeWindowStartMinuteOfDay = start.hour * 60 + start.minute
                    allQuests[i].timeWindowEndMinuteOfDay = end.hour * 60 + end.minute
                }
            case .sunset:
                if let start = solarService.sunsetWindowStart(),
                   let end = solarService.sunsetWindowEnd() {
                    allQuests[i].timeWindowStartMinuteOfDay = start.hour * 60 + start.minute
                    allQuests[i].timeWindowEndMinuteOfDay = end.hour * 60 + end.minute
                }
            }
        }
    }

    var unreadNotificationCount: Int {
        notifications.filter { !$0.isRead }.count
    }

    var activeQuestCount: Int {
        activeInstances.filter { $0.state.isActive }.count
    }

    var featuredQuest: Quest? {
        let eligible = allQuests.filter { $0.type != .master }
        guard !eligible.isEmpty else { return nil }
        return PersonalizationEngine.featuredQuest(from: eligible, context: buildPlayerContext())
    }

    var recommendedQuests: [Quest] {
        let skills = Set(profile.selectedSkills)
        let interests = Set(profile.selectedInterests)
        guard !skills.isEmpty || !interests.isEmpty else { return [] }
        return allQuests
            .filter { q in
                let skillMatch = !Set(q.skillTags).isDisjoint(with: skills)
                let interestMatch = !Set(q.interestTags).isDisjoint(with: interests)
                return skillMatch || interestMatch
            }
            .sorted { a, b in
                let aScore = Set(a.skillTags).intersection(skills).count + Set(a.interestTags).intersection(interests).count
                let bScore = Set(b.skillTags).intersection(skills).count + Set(b.interestTags).intersection(interests).count
                return aScore > bScore
            }
    }

    var hasTagsConfigured: Bool {
        !profile.selectedSkills.isEmpty || !profile.selectedInterests.isEmpty
    }

    // MARK: - Skill Trees
    static let skillXPThresholds: [Int] = [0, 250, 700, 1500, 3000]
    static let skillTierNames: [String] = ["Novice", "Apprentice", "Adept", "Expert", "Master"]




    func skillXP(for skill: UserSkill) -> Int {
        questCompletionCounts.reduce(0) { total, pair in
            let (questId, count) = pair
            guard let quest = allQuests.first(where: { $0.id == questId }),
                  quest.skillTags.contains(skill) else { return total }
            return total + quest.xpReward * count
        }
    }

    func skillLevel(for skill: UserSkill) -> Int {
        let xp = skillXP(for: skill)
        for i in stride(from: AppState.skillXPThresholds.count - 1, through: 0, by: -1) {
            if xp >= AppState.skillXPThresholds[i] { return i + 1 }
        }
        return 1
    }

    func skillTierName(for skill: UserSkill) -> String {
        AppState.skillTierNames[skillLevel(for: skill) - 1]
    }

    func skillProgress(for skill: UserSkill) -> Double {
        let xp = skillXP(for: skill)
        let level = skillLevel(for: skill)
        if level >= 5 { return 1.0 }
        let lower = AppState.skillXPThresholds[level - 1]
        let upper = AppState.skillXPThresholds[level]
        guard upper > lower else { return 1.0 }
        return min(1.0, max(0.0, Double(xp - lower) / Double(upper - lower)))
    }

    func skillXPToNextLevel(for skill: UserSkill) -> Int {
        let level = skillLevel(for: skill)
        guard level < 5 else { return 0 }
        return AppState.skillXPThresholds[level] - skillXP(for: skill)
    }

    func prepareOnboarding(username: String, avatar: String) {
        if let uid = auth.currentUserId, profile.id.isEmpty {
            profile.id = uid
        }
        profile.username = username
        profile.avatarName = avatar
        profile.joinedAt = Date()
        saveState()
    }

    func saveTagSelections(skills: [UserSkill], interests: [UserInterest]) {
        profile.selectedSkills = skills
        profile.selectedInterests = interests
        saveState()
    }

    func saveOnboardingData(_ data: OnboardingData) {
        onboardingData = data
        PersistenceService.saveOnboardingData(data)
    }

    var effectiveExternalEventPostalCode: String {
        let trimmedSpoof = externalEventSpoofPostalCode.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmedSpoof.isEmpty ? defaultExternalEventPreviewPostalCode : trimmedSpoof
    }

    func updateExternalEventSpoofPostalCode(_ postalCode: String) {
        let normalized = postalCode
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .components(separatedBy: CharacterSet.decimalDigits.inverted)
            .joined()
        externalEventSpoofPostalCode = String(normalized.prefix(5))
        UserDefaults.standard.set(externalEventSpoofPostalCode, forKey: "externalEventSpoofPostalCode")
    }

    func clearExternalEventSpoofPostalCode() {
        externalEventSpoofPostalCode = ""
        UserDefaults.standard.removeObject(forKey: "externalEventSpoofPostalCode")
    }

    var needsOnboardingRefresh: Bool {
        guard hasOnboarded else { return false }
        return onboardingData.needsRefresh
    }

    func checkOnboardingStaleness() {
        if needsOnboardingRefresh {
            showOnboardingRefresh = true
        }
    }

    func buildPlayerContext() -> PersonalizationEngine.PlayerContext {
        let completedIds = Set(questCompletionCounts.filter { $0.value > 0 }.keys)
        let activeIds = Set(activeInstances.filter { $0.state.isActive }.map { $0.quest.id })
        let completedSkillCounts: [UserSkill: Int] = questCompletionCounts.reduce(into: [:]) { partialResult, pair in
            let (questID, count) = pair
            guard count > 0,
                  let quest = allQuests.first(where: { $0.id == questID })
            else {
                return
            }
            for skill in quest.skillTags {
                partialResult[skill, default: 0] += count
            }
        }
        let completedInterestCounts: [UserInterest: Int] = questCompletionCounts.reduce(into: [:]) { partialResult, pair in
            let (questID, count) = pair
            guard count > 0,
                  let quest = allQuests.first(where: { $0.id == questID })
            else {
                return
            }
            for interest in quest.interestTags {
                partialResult[interest, default: 0] += count
            }
        }
        let recentIds: Set<String> = {
            let recent = completedHistory.prefix(15)
            var ids = Set<String>()
            for reward in recent {
                if let quest = allQuests.first(where: { $0.title == reward.questTitle }) {
                    ids.insert(quest.id)
                }
            }
            return ids
        }()
        let journeyQuestIds: Set<String> = {
            var ids = Set<String>()
            for journey in activeJourneys {
                for item in journey.questItems {
                    ids.insert(item.questId)
                }
            }
            return ids
        }()

        let contextCoordinate: CLLocationCoordinate2D? = {
            if ExternalEventLocationService.usesSimulatorPreviewLocation {
                return externalEventSearchLocation?.coordinate
                    ?? ExternalEventLocationService.fallbackSearchLocation(for: effectiveExternalEventPostalCode).coordinate
                    ?? savedGym?.coordinate
            }
            return solarService.userCoordinate ?? externalEventSearchLocation?.coordinate ?? savedGym?.coordinate
        }()
        let preferredSearchLocation: ExternalEventSearchLocation? = {
            if let externalEventSearchLocation {
                return externalEventSearchLocation
            }
            if ExternalEventLocationService.usesSimulatorPreviewLocation || !externalEventSpoofPostalCode.isEmpty {
                return ExternalEventLocationService.fallbackSearchLocation(for: effectiveExternalEventPostalCode)
            }
            return nil
        }()

        return PersonalizationEngine.PlayerContext(
            onboarding: onboardingData,
            completedQuestIds: completedIds,
            questCompletionCounts: questCompletionCounts,
            completedSkillCounts: completedSkillCounts,
            completedInterestCounts: completedInterestCounts,
            activeQuestIds: activeIds,
            recentlyCompletedIds: recentIds,
            selectedSkills: profile.selectedSkills,
            selectedInterests: profile.selectedInterests,
            currentStreak: profile.currentStreak,
            playerLevel: profile.level,
            verifiedCount: profile.verifiedCount,
            warriorRank: profile.warriorRank,
            explorerRank: profile.explorerRank,
            mindRank: profile.mindRank,
            activeJourneyQuestIds: journeyQuestIds,
            userCoordinate: contextCoordinate,
            preferredCity: preferredSearchLocation?.city,
            preferredState: preferredSearchLocation?.state,
            daypart: PersonalizationEngine.Daypart.current()
        )
    }

    @MainActor
    func ensureExternalEventsLoaded(forceRefresh: Bool = false) async {
        if isRefreshingExternalEvents { return }
        if !forceRefresh, shouldKeepCurrentExternalEventSnapshot() { return }

        if !ExternalEventLocationService.usesSimulatorPreviewLocation,
           solarService.userCoordinate == nil {
            solarService.requestLocationOnce()
        }
        await refreshExternalEvents(forceRefresh: forceRefresh)
    }

    @MainActor
    func refreshExternalEvents(forceRefresh: Bool = false) async {
        if isRefreshingExternalEvents { return }

        isRefreshingExternalEvents = true
        externalEventsError = nil
        externalEventRefreshGeneration += 1
        let refreshGeneration = externalEventRefreshGeneration

        let searchLocation = await ExternalEventLocationService.resolveSearchLocation(
            userCoordinate: solarService.userCoordinate,
            savedCoordinate: savedGym?.coordinate,
            fallbackPostalCode: effectiveExternalEventPostalCode,
            spoofPostalCode: externalEventSpoofPostalCode
        )
        externalEventSearchLocation = searchLocation
        let initialMode = initialExternalDiscoveryMode
        let discoveryIntent = currentExternalDiscoveryIntent
        let shouldPreserveVisibleFeedDuringRefresh =
            forceRefresh
            && externalEventSnapshotIntent == discoveryIntent
            && currentSnapshotHasUsefulEvents(for: externalEventFilterOption)

        if shouldPreserveVisibleFeedDuringRefresh {
            isRefreshingExternalEvents = false
            scheduleBackgroundRefresh(
                searchLocation: searchLocation,
                forceRefresh: true,
                refreshGeneration: refreshGeneration,
                intent: discoveryIntent,
                filterOption: externalEventFilterOption
            )
            return
        }

        if let serverSnapshot = await supabaseEventFeedCacheService.load(
            searchLocation: searchLocation,
            intent: discoveryIntent
        ) {
            let serverDisplaySnapshot = await displaySnapshot(
                from: serverSnapshot,
                searchLocation: searchLocation,
                primaryIntent: discoveryIntent,
                filterOption: externalEventFilterOption
            )
            guard refreshGeneration == externalEventRefreshGeneration else {
                isRefreshingExternalEvents = false
                return
            }
            if shouldApplyCachedDiscoverySnapshot(serverDisplaySnapshot) {
                applyExternalDiscoverySnapshot(serverDisplaySnapshot, intent: discoveryIntent)
                isRefreshingExternalEvents = false
                if shouldRunLocalNightlifeRepair(for: serverSnapshot, intent: discoveryIntent) {
                    scheduleCachedNightlifeRepair(
                        baseSnapshot: serverSnapshot,
                        searchLocation: searchLocation,
                        refreshGeneration: refreshGeneration,
                        intent: discoveryIntent
                    )
                } else if forceRefresh
                            || !SupabaseEventFeedCacheService.isFresh(snapshot: serverSnapshot, intent: discoveryIntent) {
                    scheduleBackgroundRefresh(
                        searchLocation: searchLocation,
                        forceRefresh: true,
                        refreshGeneration: refreshGeneration,
                        intent: discoveryIntent,
                        filterOption: externalEventFilterOption
                    )
                }
                return
            }
        }

        let localSnapshot = await externalLiveLocationDiscoveryService.discover(
            searchLocation: searchLocation,
            forceRefresh: forceRefresh,
            pageSize: initialExternalEventPageSize,
            sourcePageDepth: 1,
            mode: initialMode,
            intent: discoveryIntent
        )
        let displayLocalSnapshot = await displaySnapshot(
            from: localSnapshot,
            searchLocation: searchLocation,
            primaryIntent: discoveryIntent,
            filterOption: externalEventFilterOption
        )
        guard refreshGeneration == externalEventRefreshGeneration else {
            isRefreshingExternalEvents = false
            return
        }
        if shouldApplyQuickDiscoverySnapshot(displayLocalSnapshot) {
            applyExternalDiscoverySnapshot(displayLocalSnapshot, intent: discoveryIntent)
            if shouldPersistDiscoverySnapshot(localSnapshot, mode: initialMode) {
                persistExternalDiscoverySnapshot(localSnapshot, intent: discoveryIntent, quality: .fast)
            }
        }
        isRefreshingExternalEvents = false

        scheduleBackgroundRefresh(
            searchLocation: searchLocation,
            forceRefresh: forceRefresh,
            refreshGeneration: refreshGeneration,
            intent: discoveryIntent,
            filterOption: externalEventFilterOption
        )
    }

    private func scheduleBackgroundRefresh(
        searchLocation: ExternalEventSearchLocation,
        forceRefresh: Bool,
        refreshGeneration: Int,
        intent: ExternalDiscoveryIntent,
        filterOption: ExternalEventFilterOption
    ) {
        scheduleFullExternalEventRefresh(
            searchLocation: searchLocation,
            forceRefresh: forceRefresh,
            refreshGeneration: refreshGeneration,
            intent: intent,
            filterOption: filterOption
        )
    }

    @MainActor
    func loadMoreExternalEvents() async {
        guard !isRefreshingExternalEvents, !isLoadingMoreExternalEvents, hasMoreExternalEvents else { return }
        isLoadingMoreExternalEvents = true

        guard let searchLocation = externalEventSearchLocation else {
            isLoadingMoreExternalEvents = false
            return
        }

        guard let query = externalEventSnapshot?.query else {
            isLoadingMoreExternalEvents = false
            return
        }

        let nextPageResults = await externalEventService.fetchNextPages(
            query: query,
            cursors: externalEventNextCursors,
            forceRefresh: true
        )

        if !nextPageResults.isEmpty {
            let mergedSourceResults = Self.mergedEventSourceResults(
                (externalEventSnapshot?.sourceResults ?? []) + nextPageResults
            )

            let supplementalVenueEvents = externalEventSnapshot?.mergedEvents.filter { $0.recordKind == .venueNight } ?? []
            let mergedEvents = ExternalEventIngestionService.dedupe(events: mergedSourceResults.flatMap(\.events) + supplementalVenueEvents)
            let enrichedEvents = ExternalLiveLocationDiscoveryService.enrich(
                events: mergedEvents.events,
                with: externalVenueSnapshot?.venues ?? [],
                around: searchLocation
            )
            let snapshot = ExternalEventIngestionSnapshot(
                fetchedAt: Date(),
                query: query,
                sourceResults: mergedSourceResults,
                mergedEvents: enrichedEvents,
                dedupeGroups: mergedEvents.groups
            )

            externalEventSnapshot = snapshot
            externalEventsLastFetchedAt = snapshot.fetchedAt
            externalEventNextCursors = Dictionary(uniqueKeysWithValues: mergedSourceResults.compactMap { result in
                result.nextCursor.map { (result.source, $0) }
            })
            hasMoreExternalEvents = !externalEventNextCursors.isEmpty
            rebuildExternalEventFeed()
        } else {
            hasMoreExternalEvents = false
        }

        isLoadingMoreExternalEvents = false
    }

    @MainActor
    func setExternalEventSortOption(_ option: ExternalEventSortOption) {
        externalEventSortOption = option
        rebuildExternalEventFeed()
    }

    @MainActor
    func setExternalEventFilterOption(_ option: ExternalEventFilterOption) {
        guard externalEventFilterOption != option else { return }
        externalEventFilterOption = option
        rebuildExternalEventFeed()
        if shouldRefreshForEventFilter(option) {
            Task { [weak self] in
                await self?.refreshExternalEvents(forceRefresh: true)
            }
        }
    }

    private var currentExternalDiscoveryIntent: ExternalDiscoveryIntent {
        switch externalEventFilterOption {
        case .sports:
            return .biggestTonight
        case .nightlife, .exclusive:
            return .exclusiveHot
        case .today, .tonight, .tomorrow:
            return .lastMinutePlans
        case .all, .concerts, .races, .community, .weekend, .free:
            break
        }

        switch externalEventSortOption {
        case .hottest:
            return .biggestTonight
        case .soonest:
            return .lastMinutePlans
        case .closest, .recommended, .weekend:
            return .nearbyWorthIt
        }
    }

    private var initialExternalDiscoveryMode: ExternalLiveLocationDiscoveryService.DiscoveryMode {
        switch externalEventFilterOption {
        case .nightlife, .exclusive:
            return .preview
        case .all, .today, .tonight, .tomorrow, .sports, .concerts, .races, .community, .weekend, .free:
            return .fast
        }
    }

    private var initialExternalEventPageSize: Int {
        switch externalEventFilterOption {
        case .sports:
            return 32
        case .nightlife, .exclusive, .concerts:
            return 12
        case .all, .today, .tonight, .tomorrow, .races, .community, .weekend, .free:
            return 16
        }
    }

    private func shouldRefreshForEventFilter(_ option: ExternalEventFilterOption) -> Bool {
        if externalEventSnapshotIntent != currentExternalDiscoveryIntent {
            return true
        }

        if eventsTabExternalEventFeed.isEmpty { return true }
        guard let lastFetchedAt = externalEventsLastFetchedAt else { return true }

        let age = Date().timeIntervalSince(lastFetchedAt)
        let freshnessWindow = SupabaseEventFeedCacheService.freshnessWindow(
            for: currentExternalDiscoveryIntent,
            searchLocation: externalEventSearchLocation
                ?? ExternalEventSearchLocation(
                    city: nil,
                    state: nil,
                    postalCode: nil,
                    countryCode: "US",
                    latitude: nil,
                    longitude: nil,
                    displayName: "United States"
                )
        )

        switch option {
        case .nightlife, .exclusive:
            if currentSnapshotHasUsefulEvents(for: option) && age < freshnessWindow {
                return false
            }
            return true
        case .sports, .concerts, .today, .tonight, .tomorrow:
            return age > freshnessWindow
        case .all, .races, .community, .weekend, .free:
            return age > freshnessWindow
        }
    }

    private func currentSnapshotHasUsefulEvents(for option: ExternalEventFilterOption) -> Bool {
        guard let snapshot = externalEventSnapshot else { return false }
        let localizedEvents = localizedExternalEvents(from: snapshot.mergedEvents)
        return localizedEvents.contains { event in
            relaxedFilterMatch(event, filter: option) && event.isUpcoming
        }
    }

    private func shouldKeepCurrentExternalEventSnapshot() -> Bool {
        guard externalEventSnapshotIntent == currentExternalDiscoveryIntent else { return false }
        guard currentSnapshotHasUsefulEvents(for: externalEventFilterOption) else { return false }
        guard let lastFetchedAt = externalEventsLastFetchedAt else { return false }

        let referenceSearchLocation =
            externalEventSearchLocation
            ?? externalLocationDiscoverySnapshot?.searchLocation
            ?? ExternalEventSearchLocation(
                city: nil,
                state: nil,
                postalCode: effectiveExternalEventPostalCode,
                countryCode: "US",
                latitude: nil,
                longitude: nil,
                displayName: "United States"
            )

        let freshnessWindow = SupabaseEventFeedCacheService.freshnessWindow(
            for: currentExternalDiscoveryIntent,
            searchLocation: referenceSearchLocation
        )

        return Date().timeIntervalSince(lastFetchedAt) < freshnessWindow
    }

    private func supplementalDiscoveryIntents(
        for filterOption: ExternalEventFilterOption,
        primaryIntent: ExternalDiscoveryIntent
    ) -> [ExternalDiscoveryIntent] {
        switch filterOption {
        case .all:
            return [
                .nearbyWorthIt,
                .lastMinutePlans,
                .biggestTonight
            ]
            .filter { $0 != primaryIntent }
        case .today, .tonight, .tomorrow, .sports, .concerts, .nightlife, .exclusive, .races, .community, .weekend, .free:
            return []
        }
    }

    @MainActor
    private func displaySnapshot(
        from baseSnapshot: ExternalLocationDiscoverySnapshot,
        searchLocation: ExternalEventSearchLocation,
        primaryIntent: ExternalDiscoveryIntent,
        filterOption: ExternalEventFilterOption
    ) async -> ExternalLocationDiscoverySnapshot {
        let supplementalIntents = supplementalDiscoveryIntents(
            for: filterOption,
            primaryIntent: primaryIntent
        )
        guard !supplementalIntents.isEmpty else {
            return baseSnapshot
        }

        var mergedSnapshot = baseSnapshot
        for intent in supplementalIntents {
            guard let supplementalSnapshot = await supabaseEventFeedCacheService.load(
                searchLocation: searchLocation,
                intent: intent
            ) else {
                continue
            }
            mergedSnapshot = mergeDiscoverySnapshots(
                base: mergedSnapshot,
                repair: supplementalSnapshot
            )
        }
        return mergedSnapshot
    }

    private func usefulEventCount(
        in events: [ExternalEvent],
        for option: ExternalEventFilterOption
    ) -> Int {
        localizedExternalEvents(from: events)
            .filter { event in
                relaxedFilterMatch(event, filter: option)
                    && event.isUpcoming
                    && event.status != .cancelled
                    && event.status != .ended
            }
            .count
    }

    private func usefulEventCount(
        in events: [ExternalEvent],
        for intent: ExternalDiscoveryIntent
    ) -> Int {
        switch intent {
        case .exclusiveHot:
            return max(
                usefulEventCount(in: events, for: .exclusive),
                usefulEventCount(in: events, for: .nightlife)
            )
        case .biggestTonight:
            return max(
                usefulEventCount(in: events, for: .sports),
                usefulEventCount(in: events, for: .concerts)
            )
        case .nearbyWorthIt:
            return usefulEventCount(in: events, for: .all)
        case .lastMinutePlans:
            return max(
                usefulEventCount(in: events, for: .today),
                usefulEventCount(in: events, for: .tonight),
                usefulEventCount(in: events, for: .tomorrow)
            )
        }
    }

    private func shouldApplyQuickDiscoverySnapshot(_ snapshot: ExternalLocationDiscoverySnapshot) -> Bool {
        if externalEventSnapshotIntent != currentExternalDiscoveryIntent {
            return true
        }
        guard let currentSnapshot = externalEventSnapshot else { return true }

        let comparisonIntent = currentExternalDiscoveryIntent
        let currentCount = usefulEventCount(in: currentSnapshot.mergedEvents, for: comparisonIntent)
        let incomingCount = usefulEventCount(in: snapshot.mergedEvents, for: comparisonIntent)

        if incomingCount == 0, currentCount > 0 {
            return false
        }

        if currentCount >= 4 && incomingCount + 2 < currentCount {
            return false
        }

        let currentCoverage = venueReviewCoverage(in: currentSnapshot.mergedEvents)
        let incomingCoverage = venueReviewCoverage(in: snapshot.mergedEvents)
        if materiallyDegradedReviewCoverage(current: currentCoverage, incoming: incomingCoverage) {
            return false
        }

        return true
    }

    private func shouldApplyCachedDiscoverySnapshot(_ snapshot: ExternalLocationDiscoverySnapshot) -> Bool {
        if let currentSnapshot = externalEventSnapshot,
           externalEventSnapshotIntent == currentExternalDiscoveryIntent {
            let currentCoverage = venueReviewCoverage(in: currentSnapshot.mergedEvents)
            let incomingCoverage = venueReviewCoverage(in: snapshot.mergedEvents)
            let materiallyImprovedReviewCoverage =
                incomingCoverage.eligibleCount >= 8
                && incomingCoverage.coveredCount >= currentCoverage.coveredCount + 4
                && incomingCoverage.coverage >= currentCoverage.coverage + 0.15

            if materiallyImprovedReviewCoverage {
                return true
            }

            let currentCount = usefulEventCount(in: currentSnapshot.mergedEvents, for: currentExternalDiscoveryIntent)
            let incomingCount = usefulEventCount(in: snapshot.mergedEvents, for: currentExternalDiscoveryIntent)

            if incomingCount == 0 && currentCount > 0 {
                return false
            }

            if currentCount >= 4 && incomingCount + 2 < currentCount {
                return false
            }
        }

        if externalEventFilterOption == .nightlife || externalEventFilterOption == .exclusive {
            return usefulEventCount(in: snapshot.mergedEvents, for: externalEventFilterOption) >= 2
        }
        return !snapshot.mergedEvents.isEmpty
    }

    private func shouldPersistDiscoverySnapshot(
        _ snapshot: ExternalLocationDiscoverySnapshot,
        mode: ExternalLiveLocationDiscoveryService.DiscoveryMode
    ) -> Bool {
        guard !snapshot.mergedEvents.isEmpty else { return false }
        switch mode {
        case .preview:
            return false
        case .fast, .full:
            return true
        }
    }

    private func shouldRunLocalNightlifeRepair(
        for snapshot: ExternalLocationDiscoverySnapshot,
        intent: ExternalDiscoveryIntent
    ) -> Bool {
        guard intent == .exclusiveHot else { return false }

        let nightlifeEvents = snapshot.mergedEvents.filter { $0.recordKind == .venueNight }
        guard !nightlifeEvents.isEmpty else { return false }

        return nightlifeEvents.contains { event in
            ExternalEventSupport.isWeakAddressLine(
                event.addressLine1,
                city: event.city,
                state: event.state
            )
            || event.postalCode == nil
            || event.imageURL == nil
            || event.startLocal == nil
            || event.openingHoursText == nil
            || ((event.openingHoursText?.count ?? 0) > 100)
        }
    }

    private func shouldScheduleFullRefresh(
        for snapshot: ExternalLocationDiscoverySnapshot,
        requestedSearchLocation: ExternalEventSearchLocation,
        intent: ExternalDiscoveryIntent
    ) -> Bool {
        if cachedSnapshotNeedsLocalRefresh(snapshot, requestedSearchLocation: requestedSearchLocation) {
            return true
        }

        let coverage = venueReviewCoverage(in: snapshot.mergedEvents)
        guard coverage.eligibleCount >= 8 else { return false }

        let minimumCoverage: Double = switch intent {
        case .exclusiveHot, .nearbyWorthIt:
            0.35
        case .lastMinutePlans:
            0.3
        case .biggestTonight:
            0.25
        }

        return coverage.coverage < minimumCoverage
    }

    private func cachedSnapshotNeedsLocalRefresh(
        _ snapshot: ExternalLocationDiscoverySnapshot,
        requestedSearchLocation: ExternalEventSearchLocation
    ) -> Bool {
        if let requestedCoordinate = requestedSearchLocation.coordinate,
           let snapshotCoordinate = snapshot.searchLocation.coordinate {
            let requestedLocation = CLLocation(
                latitude: requestedCoordinate.latitude,
                longitude: requestedCoordinate.longitude
            )
            let snapshotLocation = CLLocation(
                latitude: snapshotCoordinate.latitude,
                longitude: snapshotCoordinate.longitude
            )
            if requestedLocation.distance(from: snapshotLocation) / 1609.344 > 8 {
                return true
            }
        }

        let requestedCity = ExternalEventSupport.normalizeToken(requestedSearchLocation.city)
        let snapshotCity = ExternalEventSupport.normalizeToken(snapshot.searchLocation.city)
        let requestedState = ExternalEventSupport.normalizeStateToken(requestedSearchLocation.state)
        let snapshotState = ExternalEventSupport.normalizeStateToken(snapshot.searchLocation.state)

        return !requestedCity.isEmpty
            && !snapshotCity.isEmpty
            && requestedState == snapshotState
            && requestedCity != snapshotCity
    }

    private func venueReviewCoverage(
        in events: [ExternalEvent]
    ) -> (coveredCount: Int, eligibleCount: Int, coverage: Double) {
        let eligibleEvents = events.filter { event in
            if event.eventType == .partyNightlife || event.recordKind == .venueNight {
                return !ExternalEventSupport.isLikelyClubLikeNightlifeVenue(event)
            }
            return true
        }
        guard !eligibleEvents.isEmpty else {
            return (0, 0, 0)
        }

        let coveredCount = eligibleEvents.filter { event in
            if let rating = event.venueRating, rating >= 1.0, rating <= 5.0 {
                return true
            }
            return false
        }.count

        return (
            coveredCount,
            eligibleEvents.count,
            Double(coveredCount) / Double(eligibleEvents.count)
        )
    }

    private func scheduleCachedNightlifeRepair(
        baseSnapshot: ExternalLocationDiscoverySnapshot,
        searchLocation: ExternalEventSearchLocation,
        refreshGeneration: Int,
        intent: ExternalDiscoveryIntent
    ) {
        Task { [weak self] in
            guard let self else { return }
            let repairSnapshot = await self.externalLiveLocationDiscoveryService.discover(
                searchLocation: searchLocation,
                forceRefresh: true,
                pageSize: max(self.initialExternalEventPageSize, 12),
                sourcePageDepth: 1,
                mode: .full,
                intent: intent
            )
            let mergedSnapshot = await MainActor.run {
                self.mergeDiscoverySnapshots(base: baseSnapshot, repair: repairSnapshot)
            }
            await self.supabaseEventFeedCacheService.save(
                snapshot: mergedSnapshot,
                intent: intent,
                quality: .full
            )
            await MainActor.run {
                guard refreshGeneration == self.externalEventRefreshGeneration else { return }
                self.applyExternalDiscoverySnapshot(mergedSnapshot, intent: intent)
            }
        }
    }

    @MainActor
    private func mergeDiscoverySnapshots(
        base: ExternalLocationDiscoverySnapshot,
        repair: ExternalLocationDiscoverySnapshot
    ) -> ExternalLocationDiscoverySnapshot {
        let mergedVenues = ExternalVenueDiscoveryService.merge(
            (base.venueSnapshot?.venues ?? []) + (repair.venueSnapshot?.venues ?? [])
        )

        let mergedVenueSourceResults = Self.mergedVenueSourceResults(
            (base.venueSnapshot?.sourceResults ?? []) + (repair.venueSnapshot?.sourceResults ?? [])
        )

        let mergedRawEvents = ExternalEventIngestionService.dedupe(
            events: base.eventSnapshot.mergedEvents + repair.eventSnapshot.mergedEvents
        )
        let mergedEvents = ExternalLiveLocationDiscoveryService.enrich(
            events: mergedRawEvents.events,
            with: mergedVenues,
            around: base.searchLocation
        )
        let mergedEventSourceResults = Self.mergedEventSourceResults(
            base.eventSnapshot.sourceResults + repair.eventSnapshot.sourceResults
        )

        let mergedEventSnapshot = ExternalEventIngestionSnapshot(
            fetchedAt: max(base.eventSnapshot.fetchedAt, repair.eventSnapshot.fetchedAt),
            query: base.eventSnapshot.query,
            sourceResults: mergedEventSourceResults,
            mergedEvents: mergedEvents,
            dedupeGroups: base.eventSnapshot.dedupeGroups
        )

        let mergedVenueSnapshot: ExternalVenueDiscoverySnapshot? = {
            guard let query = base.venueSnapshot?.query ?? repair.venueSnapshot?.query else { return nil }
            return ExternalVenueDiscoverySnapshot(
                fetchedAt: max(base.venueSnapshot?.fetchedAt ?? .distantPast, repair.venueSnapshot?.fetchedAt ?? .distantPast),
                query: query,
                sourceResults: mergedVenueSourceResults,
                venues: mergedVenues
            )
        }()

        return ExternalLocationDiscoverySnapshot(
            fetchedAt: max(base.fetchedAt, repair.fetchedAt),
            searchLocation: base.searchLocation,
            appliedProfiles: base.appliedProfiles,
            venueSnapshot: mergedVenueSnapshot,
            eventSnapshot: mergedEventSnapshot,
            mergedEvents: mergedEvents,
            notes: Array(Set(base.notes + repair.notes)).sorted()
        )
    }

    private func scheduleFullExternalEventRefresh(
        searchLocation: ExternalEventSearchLocation,
        forceRefresh: Bool,
        refreshGeneration: Int,
        intent: ExternalDiscoveryIntent,
        filterOption: ExternalEventFilterOption
    ) {
        Task { [weak self] in
            guard let self else { return }
            let fullSnapshot = await self.externalLiveLocationDiscoveryService.discover(
                searchLocation: searchLocation,
                forceRefresh: forceRefresh,
                pageSize: max(self.initialExternalEventPageSize, 20),
                sourcePageDepth: self.externalEventSourcePageDepth,
                mode: .full,
                intent: intent
            )
            let displaySnapshot = await self.displaySnapshot(
                from: fullSnapshot,
                searchLocation: searchLocation,
                primaryIntent: intent,
                filterOption: filterOption
            )
            let shouldApply = await MainActor.run {
                self.shouldApplyFullDiscoverySnapshot(displaySnapshot, intent: intent)
            }
            guard shouldApply else { return }
            await self.supabaseEventFeedCacheService.save(
                snapshot: fullSnapshot,
                intent: intent,
                quality: .full
            )
            await MainActor.run {
                guard refreshGeneration == self.externalEventRefreshGeneration else { return }
                self.applyExternalDiscoverySnapshot(displaySnapshot, intent: intent)
            }
        }
    }

    private func shouldApplyFullDiscoverySnapshot(
        _ snapshot: ExternalLocationDiscoverySnapshot,
        intent: ExternalDiscoveryIntent
    ) -> Bool {
        guard let currentSnapshot = externalEventSnapshot else { return true }
        guard externalEventSnapshotIntent == intent else { return true }

        let currentCount = usefulEventCount(in: currentSnapshot.mergedEvents, for: intent)
        let incomingCount = usefulEventCount(in: snapshot.mergedEvents, for: intent)
        let currentCoverage = venueReviewCoverage(in: currentSnapshot.mergedEvents)
        let incomingCoverage = venueReviewCoverage(in: snapshot.mergedEvents)
        let materiallyImprovedReviewCoverage =
            incomingCoverage.eligibleCount >= 8
            && incomingCoverage.coveredCount >= currentCoverage.coveredCount + 4
            && incomingCoverage.coverage >= currentCoverage.coverage + 0.15

        if materiallyImprovedReviewCoverage {
            return true
        }

        if materiallyDegradedReviewCoverage(current: currentCoverage, incoming: incomingCoverage) {
            return false
        }

        if incomingCount == 0 && currentCount > 0 {
            return false
        }

        if intent == .exclusiveHot, currentCount >= 6, incomingCount + 2 < currentCount {
            return false
        }

        if (intent == .biggestTonight || intent == .lastMinutePlans), currentCount >= 10, incomingCount + 3 < currentCount {
            return false
        }

        return true
    }

    private func materiallyDegradedReviewCoverage(
        current: (coveredCount: Int, eligibleCount: Int, coverage: Double),
        incoming: (coveredCount: Int, eligibleCount: Int, coverage: Double)
    ) -> Bool {
        current.eligibleCount >= 8
            && current.coveredCount >= incoming.coveredCount + 4
            && current.coverage >= incoming.coverage + 0.15
    }

    private func persistExternalDiscoverySnapshot(
        _ snapshot: ExternalLocationDiscoverySnapshot,
        intent: ExternalDiscoveryIntent,
        quality: ExternalDiscoveryCacheQuality
    ) {
        Task { [weak self] in
            guard let self else { return }
            await self.supabaseEventFeedCacheService.save(
                snapshot: snapshot,
                intent: intent,
                quality: quality
            )
        }
    }

    @MainActor
    func relatedExternalEvents(for event: ExternalEvent) -> [ExternalEvent] {
        guard let snapshot = externalEventSnapshot else { return [event] }
        guard let parentID = event.sourceParentID, !parentID.isEmpty else {
            return snapshot.mergedEvents.filter { candidate in
                candidate.id == event.id
            }
        }

        let grouped = snapshot.mergedEvents.filter { candidate in
            candidate.source == event.source && candidate.sourceParentID == parentID
        }
        return grouped.sorted { lhs, rhs in
            (lhs.startAtUTC ?? .distantFuture) < (rhs.startAtUTC ?? .distantFuture)
        }
    }

    @MainActor
    private func rebuildExternalEventFeed() {
        externalEventFeedRebuildTask?.cancel()
        guard let snapshot = externalEventSnapshot else {
            externalEventFeed = []
            eventsTabExternalEventFeed = []
            eventsTabExpandedExternalEventFeed = []
            exclusiveExternalEventFeed = []
            return
        }

        let localizedEvents = localizedExternalEvents(from: snapshot.mergedEvents)
        let context = buildPlayerContext()
        let sortOption = externalEventSortOption
        let filterOption = externalEventFilterOption
        externalEventFeedBuildGeneration += 1
        let buildGeneration = externalEventFeedBuildGeneration

        externalEventFeedRebuildTask = Task.detached(priority: .userInitiated) {
            let rankedHomeEvents = Self.deduplicatedDisplayEvents(
                ExternalEventFeedService.rankedEvents(
                    from: localizedEvents,
                    context: context,
                    sort: .recommended,
                    filter: .all,
                    limit: 72
                )
            )
            let rankedFilteredEvents = Self.deduplicatedDisplayEvents(
                ExternalEventFeedService.rankedEvents(
                    from: localizedEvents,
                    context: context,
                    sort: sortOption,
                    filter: filterOption,
                    limit: 72
                )
            )
            let rankedExpandedEvents = Self.deduplicatedDisplayEvents(
                ExternalEventFeedService.rankedEvents(
                    from: localizedEvents,
                    context: context,
                    sort: .recommended,
                    filter: .all,
                    limit: 240
                )
            )
            let exclusiveEvents = Self.deduplicatedDisplayEvents(
                ExternalEventFeedService.exclusiveEvents(
                    from: localizedEvents,
                    context: context,
                    limit: 4
                )
            )

            guard !Task.isCancelled else { return }

            await MainActor.run {
                guard self.externalEventFeedBuildGeneration == buildGeneration else { return }

                self.externalEventFeed = rankedHomeEvents
                self.eventsTabExpandedExternalEventFeed = rankedExpandedEvents
                let relaxedEvents = self.relaxedFilteredExternalEvents(
                    from: localizedEvents,
                    context: context,
                    sortOption: sortOption,
                    filterOption: filterOption
                )
                self.eventsTabExternalEventFeed = self.mergedDisplayEvents(
                    ranked: rankedFilteredEvents,
                    relaxed: relaxedEvents,
                    filterOption: filterOption
                )
                self.exclusiveExternalEventFeed = exclusiveEvents
            }
        }
    }

    @MainActor
    private func applyExternalDiscoverySnapshot(
        _ discoverySnapshot: ExternalLocationDiscoverySnapshot,
        intent: ExternalDiscoveryIntent
    ) {
        let relocalizedSnapshot = relocalizedExternalDiscoverySnapshot(discoverySnapshot)
        externalLocationDiscoverySnapshot = relocalizedSnapshot
        externalEventSnapshotIntent = intent
        if let venueSnapshot = relocalizedSnapshot.venueSnapshot {
            externalVenueSnapshot = venueSnapshot
        }
        let displayMergedEvents = relocalizedSnapshot.eventSnapshot.mergedEvents.isEmpty
            ? relocalizedSnapshot.mergedEvents
            : relocalizedSnapshot.eventSnapshot.mergedEvents
        let snapshot = ExternalEventIngestionSnapshot(
            fetchedAt: relocalizedSnapshot.eventSnapshot.fetchedAt,
            query: relocalizedSnapshot.eventSnapshot.query,
            sourceResults: Self.mergedEventSourceResults(relocalizedSnapshot.eventSnapshot.sourceResults),
            mergedEvents: displayMergedEvents,
            dedupeGroups: relocalizedSnapshot.eventSnapshot.dedupeGroups
        )
        externalEventSnapshot = snapshot
        externalEventsLastFetchedAt = relocalizedSnapshot.fetchedAt
        externalEventNextCursors = Dictionary(uniqueKeysWithValues: snapshot.sourceResults.compactMap { result in
            result.nextCursor.map { (result.source, $0) }
        })
        hasMoreExternalEvents = !externalEventNextCursors.isEmpty
        if !relocalizedSnapshot.mergedEvents.isEmpty {
            let persistedSearchLocation = externalEventSearchLocation ?? relocalizedSnapshot.searchLocation
            Task(priority: .utility) {
                PersistenceService.saveExternalDiscoveryState(
                    snapshot: relocalizedSnapshot,
                    intent: intent,
                    searchLocation: persistedSearchLocation
                )
            }
        }
        rebuildExternalEventFeed()
        scheduleExternalEventImagePrefetch()

        if externalEventFeed.isEmpty {
            externalEventsError = "No fresh live events matched your area right now."
        } else {
            externalEventsError = nil
        }
    }

    private func relocalizedExternalDiscoverySnapshot(
        _ snapshot: ExternalLocationDiscoverySnapshot
    ) -> ExternalLocationDiscoverySnapshot {
        guard let searchLocation = externalEventSearchLocation else {
            return snapshot
        }

        let relocalizedMergedEvents = snapshot.mergedEvents.map {
            relocalizedExternalEvent($0, around: searchLocation)
        }
        let relocalizedSourceResults = snapshot.eventSnapshot.sourceResults.map { result in
            ExternalEventSourceResult(
                source: result.source,
                usedCache: result.usedCache,
                fetchedAt: result.fetchedAt,
                endpoints: result.endpoints,
                note: result.note,
                nextCursor: result.nextCursor,
                events: result.events.map { relocalizedExternalEvent($0, around: searchLocation) }
            )
        }
        let relocalizedEventSnapshot = ExternalEventIngestionSnapshot(
            fetchedAt: snapshot.eventSnapshot.fetchedAt,
            query: snapshot.eventSnapshot.query,
            sourceResults: relocalizedSourceResults,
            mergedEvents: relocalizedMergedEvents,
            dedupeGroups: snapshot.eventSnapshot.dedupeGroups
        )

        return ExternalLocationDiscoverySnapshot(
            fetchedAt: snapshot.fetchedAt,
            searchLocation: snapshot.searchLocation,
            appliedProfiles: snapshot.appliedProfiles,
            venueSnapshot: snapshot.venueSnapshot,
            eventSnapshot: relocalizedEventSnapshot,
            mergedEvents: relocalizedMergedEvents,
            notes: snapshot.notes
        )
    }

    private static func sanitizedExternalDiscoverySnapshot(
        _ snapshot: ExternalLocationDiscoverySnapshot
    ) -> ExternalLocationDiscoverySnapshot {
        let sanitizedMergedEvents = snapshot.mergedEvents.map(Self.sanitizedPersistedReviewIntegrity)
        let sanitizedSourceResults = snapshot.eventSnapshot.sourceResults.map { result in
            ExternalEventSourceResult(
                source: result.source,
                usedCache: result.usedCache,
                fetchedAt: result.fetchedAt,
                endpoints: result.endpoints,
                note: result.note,
                nextCursor: result.nextCursor,
                events: result.events.map(Self.sanitizedPersistedReviewIntegrity)
            )
        }
        let sanitizedEventSnapshot = ExternalEventIngestionSnapshot(
            fetchedAt: snapshot.eventSnapshot.fetchedAt,
            query: snapshot.eventSnapshot.query,
            sourceResults: sanitizedSourceResults,
            mergedEvents: sanitizedMergedEvents,
            dedupeGroups: snapshot.eventSnapshot.dedupeGroups
        )

        return ExternalLocationDiscoverySnapshot(
            fetchedAt: snapshot.fetchedAt,
            searchLocation: snapshot.searchLocation,
            appliedProfiles: snapshot.appliedProfiles,
            venueSnapshot: snapshot.venueSnapshot,
            eventSnapshot: sanitizedEventSnapshot,
            mergedEvents: sanitizedMergedEvents,
            notes: snapshot.notes
        )
    }

    private static func sanitizedPersistedReviewIntegrity(_ event: ExternalEvent) -> ExternalEvent {
        ExternalEventSupport.sanitizedGoogleReviewIdentity(event)
    }

    private func relocalizedExternalEvent(
        _ event: ExternalEvent,
        around location: ExternalEventSearchLocation
    ) -> ExternalEvent {
        guard let distance = eventDistanceMiles(event, around: location) else {
            return event
        }

        var relocalized = event
        relocalized.distanceFromUser = distance
        return relocalized
    }

    private func eventDistanceMiles(
        _ event: ExternalEvent,
        around location: ExternalEventSearchLocation
    ) -> Double? {
        guard let searchCoordinate = location.coordinate,
              let latitude = event.latitude,
              let longitude = event.longitude
        else {
            return event.distanceFromUser
        }

        let eventLocation = CLLocation(latitude: latitude, longitude: longitude)
        let userLocation = CLLocation(latitude: searchCoordinate.latitude, longitude: searchCoordinate.longitude)
        return userLocation.distance(from: eventLocation) / 1609.344
    }

    private func scheduleExternalEventImagePrefetch() {
        externalEventImagePrefetchTask?.cancel()

        let candidateURLs = Array(
            Set(
                (eventsTabExternalEventFeed.prefix(24) + exclusiveExternalEventFeed.prefix(18) + externalEventFeed.prefix(24))
                    .flatMap { ExternalEventSupport.preferredImageURLs(for: $0, limit: 3) }
            )
        )

        guard !candidateURLs.isEmpty else { return }

        externalEventImagePrefetchTask = Task {
            await ExternalEventImageCacheService.prefetch(urlStrings: candidateURLs, limit: 36)
            guard !Task.isCancelled else { return }
            await MainActor.run {
                externalEventImageRefreshNonce &+= 1
            }
        }
    }

    private func relaxedFilteredExternalEvents(
        from events: [ExternalEvent],
        context: PersonalizationEngine.PlayerContext,
        sortOption: ExternalEventSortOption,
        filterOption: ExternalEventFilterOption
    ) -> [ExternalEvent] {
        guard filterOption != .all else { return [] }

        let candidates = events
            .filter { relaxedFilterMatch($0, filter: filterOption) }
            .filter { $0.isUpcoming }
            .filter { event in
                switch event.status {
                case .cancelled, .ended:
                    return false
                default:
                    return true
                }
            }
            .filter { event in
                switch filterOption {
                case .sports:
                    return event.eventType == .sportsEvent
                        && ExternalEventSupport.qualityScore(for: event) >= 12
                case .nightlife:
                    return (event.eventType == .partyNightlife || ExternalEventSupport.isExclusiveEvent(event))
                        && ExternalEventSupport.qualityScore(for: event) >= 18
                case .concerts:
                    return event.eventType == .concert
                        && ExternalEventSupport.qualityScore(for: event) >= 18
                default:
                    return ExternalEventSupport.qualityScore(for: event) >= 16
                }
            }

        guard !candidates.isEmpty else { return [] }
        return ExternalEventFeedService.rankedEvents(
            from: candidates,
            context: context,
            sort: sortOption,
            filter: .all,
            limit: 72
        )
    }

    private func mergedDisplayEvents(
        ranked: [ExternalEvent],
        relaxed: [ExternalEvent],
        filterOption: ExternalEventFilterOption
    ) -> [ExternalEvent] {
        guard !ranked.isEmpty else { return relaxed }

        let minimumCounts: [ExternalEventFilterOption: Int] = [
            .exclusive: 12,
            .nightlife: 16,
            .sports: 12,
            .concerts: 10
        ]

        guard let minimumCount = minimumCounts[filterOption],
              ranked.count < minimumCount else {
            return ranked
        }

        var merged = ranked

        for event in relaxed {
            if merged.contains(where: { ExternalEventSupport.isLikelyDuplicate($0, event) }) {
                continue
            }
            merged.append(event)
            if merged.count >= minimumCount { break }
        }

        return Self.deduplicatedDisplayEvents(merged)
    }

    private static func deduplicatedDisplayEvents(_ events: [ExternalEvent]) -> [ExternalEvent] {
        var unique: [ExternalEvent] = []

        for event in events {
            if let existingIndex = unique.firstIndex(where: { ExternalEventSupport.isLikelyDuplicate($0, event) }) {
                let existing = unique[existingIndex]
                let preferredPrimary = shouldPreferDisplayEvent(event, over: existing) ? event : existing
                let secondary = preferredPrimary.id == event.id ? existing : event
                unique[existingIndex] = ExternalEventSupport.merge(primary: preferredPrimary, secondary: secondary)
                continue
            }
            unique.append(event)
        }

        return unique
    }

    private static func shouldPreferDisplayEvent(_ candidate: ExternalEvent, over existing: ExternalEvent) -> Bool {
        let candidateQuality = ExternalEventSupport.qualityScore(for: candidate)
        let existingQuality = ExternalEventSupport.qualityScore(for: existing)
        if candidateQuality != existingQuality {
            return candidateQuality > existingQuality
        }

        let candidateCompleteness = displayCompletenessScore(for: candidate)
        let existingCompleteness = displayCompletenessScore(for: existing)
        if candidateCompleteness != existingCompleteness {
            return candidateCompleteness > existingCompleteness
        }

        return false
    }

    private static func displayCompletenessScore(for event: ExternalEvent) -> Int {
        var score = 0
        if event.latitude != nil && event.longitude != nil { score += 6 }
        if event.startAtUTC != nil || event.startLocal != nil { score += 5 }
        if event.timezone != nil { score += 3 }
        if event.venueName != nil { score += 3 }
        if event.addressLine1 != nil { score += 4 }
        if event.city != nil { score += 2 }
        if event.imageURL != nil { score += 4 }
        if event.shortDescription != nil { score += 2 }
        if event.fullDescription != nil { score += 2 }
        if event.registrationURL != nil || event.ticketURL != nil || event.reservationURL != nil { score += 2 }
        if event.venueRating != nil { score += 3 }
        if event.venuePopularityCount != nil { score += 2 }
        return score
    }

    private static func mergedEventSourceResults(
        _ results: [ExternalEventSourceResult]
    ) -> [ExternalEventSourceResult] {
        var mergedBySource: [ExternalEventSource: ExternalEventSourceResult] = [:]

        for result in results {
            if let existing = mergedBySource[result.source] {
                mergedBySource[result.source] = ExternalEventSourceResult(
                    source: result.source,
                    usedCache: existing.usedCache && result.usedCache,
                    fetchedAt: max(existing.fetchedAt, result.fetchedAt),
                    endpoints: existing.endpoints + result.endpoints,
                    note: result.note ?? existing.note,
                    nextCursor: result.nextCursor ?? existing.nextCursor,
                    events: ExternalEventIngestionService.dedupe(events: existing.events + result.events).events
                )
            } else {
                mergedBySource[result.source] = result
            }
        }

        return mergedBySource.values.sorted { $0.source.rawValue < $1.source.rawValue }
    }

    private static func mergedVenueSourceResults(
        _ results: [ExternalVenueSourceResult]
    ) -> [ExternalVenueSourceResult] {
        var mergedBySource: [ExternalEventSource: ExternalVenueSourceResult] = [:]

        for result in results {
            if let existing = mergedBySource[result.source] {
                mergedBySource[result.source] = ExternalVenueSourceResult(
                    source: result.source,
                    fetchedAt: max(existing.fetchedAt, result.fetchedAt),
                    endpoints: existing.endpoints + result.endpoints,
                    note: result.note ?? existing.note,
                    venues: ExternalVenueDiscoveryService.merge(existing.venues + result.venues)
                )
            } else {
                mergedBySource[result.source] = result
            }
        }

        return mergedBySource.values.sorted { $0.source.rawValue < $1.source.rawValue }
    }

    private func relaxedFilterMatch(_ event: ExternalEvent, filter: ExternalEventFilterOption) -> Bool {
        switch filter {
        case .all:
            return true
        case .today:
            return isEventOnRelativeDay(event, dayOffset: 0)
        case .tonight:
            return isEventTonight(event)
        case .tomorrow:
            return isEventOnRelativeDay(event, dayOffset: 1)
        case .sports:
            return event.eventType == .sportsEvent
        case .concerts:
            return event.eventType == .concert
        case .nightlife:
            return event.eventType == .partyNightlife || ExternalEventSupport.isExclusiveEvent(event)
        case .exclusive:
            return ExternalEventSupport.isExclusiveEvent(event)
        case .races:
            switch event.eventType {
            case .groupRun, .race5k, .race10k, .raceHalfMarathon, .raceMarathon:
                return true
            default:
                return false
            }
        case .community:
            return event.eventType == .socialCommunityEvent || event.eventType == .weekendActivity
        case .weekend:
            return isWeekendEvent(event)
        case .free:
            let low = event.priceMin ?? event.priceMax
            let high = event.priceMax ?? event.priceMin
            return low == 0 && high == 0
        }
    }

    private func isEventOnRelativeDay(_ event: ExternalEvent, dayOffset: Int) -> Bool {
        guard let startAtUTC = event.startAtUTC else { return false }
        let timezone = event.timezone.flatMap(TimeZone.init(identifier:)) ?? .current
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timezone
        let target = calendar.date(byAdding: .day, value: dayOffset, to: Date()) ?? Date()
        return calendar.isDate(startAtUTC, inSameDayAs: target)
    }

    private func isEventTonight(_ event: ExternalEvent) -> Bool {
        guard isEventOnRelativeDay(event, dayOffset: 0),
              let startAtUTC = event.startAtUTC else { return false }
        let timezone = event.timezone.flatMap(TimeZone.init(identifier:)) ?? .current
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timezone
        return calendar.component(.hour, from: startAtUTC) >= 17
    }

    private func isWeekendEvent(_ event: ExternalEvent) -> Bool {
        guard let startAtUTC = event.startAtUTC else { return false }
        let timezone = event.timezone.flatMap(TimeZone.init(identifier:)) ?? .current
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timezone
        let weekday = calendar.component(.weekday, from: startAtUTC)
        return weekday == 6 || weekday == 7 || weekday == 1
    }

    private func localizedExternalEvents(from events: [ExternalEvent]) -> [ExternalEvent] {
        guard let location = externalEventSearchLocation,
              let query = externalEventSnapshot?.query else { return events }

        let strictRadius = max(query.nightlifeRadiusMiles, query.headlineRadiusMiles)
        let expandedRadius = max(strictRadius * 1.7, query.headlineRadiusMiles + 10)

        let strictMatches = events.filter { event in
            isLocalMatch(event, around: location, radiusMiles: strictRadius)
        }
        if strictMatches.count >= 12 {
            return strictMatches
        }

        let expandedMatches = events.filter { event in
            isLocalMatch(event, around: location, radiusMiles: expandedRadius)
        }
        if !expandedMatches.isEmpty {
            return expandedMatches
        }
        return strictMatches.isEmpty ? events : strictMatches
    }

    private func isStateLevelMatch(_ event: ExternalEvent, around location: ExternalEventSearchLocation) -> Bool {
        guard let locationState = location.state,
              let eventState = event.state
        else {
            return false
        }
        return ExternalEventSupport.normalizeStateToken(locationState) == ExternalEventSupport.normalizeStateToken(eventState)
    }

    private func isLocalMatch(
        _ event: ExternalEvent,
        around location: ExternalEventSearchLocation,
        radiusMiles: Double
    ) -> Bool {
        if let distance = event.distanceFromUser {
            return distance <= radiusMiles
        }

        if let searchCoordinate = location.coordinate,
           let latitude = event.latitude,
           let longitude = event.longitude {
            let eventLocation = CLLocation(latitude: latitude, longitude: longitude)
            let userLocation = CLLocation(latitude: searchCoordinate.latitude, longitude: searchCoordinate.longitude)
            return userLocation.distance(from: eventLocation) / 1609.344 <= radiusMiles
        }

        if let postalCode = location.postalCode,
           let eventPostalCode = event.postalCode,
           postalCode == eventPostalCode {
            return true
        }

        if let locationCity = location.city,
           let eventCity = event.city,
           ExternalEventSupport.normalizeToken(locationCity) == ExternalEventSupport.normalizeToken(eventCity),
           isStateLevelMatch(event, around: location) {
            return true
        }

        if ExternalEventSupport.sharesMetroArea(
            event: event,
            preferredCity: location.city,
            preferredState: location.state
        ) {
            return true
        }

        return false
    }

    func completeOnboarding(username: String, avatar: String) {
        if let uid = auth.currentUserId, profile.id.isEmpty {
            profile.id = uid
        }
        profile.username = username
        profile.avatarName = avatar
        if profile.joinedAt.timeIntervalSince1970 < 1 {
            profile.joinedAt = Date()
        }
        hasOnboarded = true
        UserDefaults.standard.set(true, forKey: "hasOnboarded")
        saveState()
    }

    func finalizeOnboarding() {
        hasOnboarded = true
        UserDefaults.standard.set(true, forKey: "hasOnboarded")
        saveState()
    }

    func isQuestAlreadyActive(_ questId: String) -> Bool {
        activeInstances.contains { $0.quest.id == questId && $0.state.isActive }
    }

    func acceptQuest(_ quest: Quest, mode: QuestMode, handshakeVerified: Bool = false, groupSize: Int = 1) {
        guard !isQuestAlreadyActive(quest.id) else { return }
        guard activeQuestCount < 5 || mode != .solo else { return }
        let state: QuestInstanceState = {
            switch mode {
            case .solo: return .active
            case .friend: return groupSize > 1 ? .active : .pendingInvite
            case .matchmaker: return .pendingQueue
            }
        }()
        let instance = QuestInstance(
            id: UUID().uuidString,
            quest: quest,
            state: state,
            mode: mode,
            startedAt: Date(),
            submittedAt: nil,
            verifiedAt: nil,
            groupId: mode != .solo ? UUID().uuidString : nil,
            handshakeVerified: handshakeVerified,
            groupSize: groupSize
        )
        activeInstances.append(instance)
        PersistenceService.saveActiveInstances(activeInstances)
        syncQuestInstanceToBackend(instance)
    }

    func dropQuest(_ instanceId: String) {
        activeInstances.removeAll { $0.id == instanceId }
        trackingSessions.removeValue(forKey: instanceId)
        PersistenceService.saveActiveInstances(activeInstances)
        removeQuestInstanceFromBackend(instanceId)
    }

    func failQuest(_ instanceId: String) {
        guard let index = activeInstances.firstIndex(where: { $0.id == instanceId }) else { return }
        activeInstances[index].state = .failed
        syncQuestInstanceToBackend(activeInstances[index])
    }

    func clearFailedQuest(_ instanceId: String) {
        activeInstances.removeAll { $0.id == instanceId }
        focusSessions.removeValue(forKey: instanceId)
        removeQuestInstanceFromBackend(instanceId)
    }

    func clearCompletedQuests() {
        let completedIds = activeInstances.filter { $0.state == .verified }.map(\.id)
        activeInstances.removeAll { $0.state == .verified }
        for id in completedIds {
            removeQuestInstanceFromBackend(id)
        }
    }

    func submitTrackingEvidence(for instanceId: String, session: TrackingSession) {
        guard let index = activeInstances.firstIndex(where: { $0.id == instanceId }) else { return }
        var updatedSession = session
        if session.timeIntegrityVerified == false || timeIntegrity.hasTimeManipulation {
            if !updatedSession.integrityFlags.contains(.clockManipulated) {
                updatedSession.integrityFlags.append(.clockManipulated)
            }
        }
        let quest = activeInstances[index].quest
        if quest.hasTimeWindow, let start = session.startedAt, let end = session.endedAt {
            let timeOk = TrackingSession.verifyTimeWindow(start: start, end: end, quest: quest)
            updatedSession.timeWindowVerified = timeOk
            if !timeOk && !updatedSession.integrityFlags.contains(.outsideTimeWindow) {
                updatedSession.integrityFlags.append(.outsideTimeWindow)
            }
        }
        activeInstances[index].state = .submitted
        activeInstances[index].submittedAt = Date()
        trackingSessions[instanceId] = updatedSession
        scheduleAutoVerification(for: instanceId)
    }

    func scheduleAutoVerification(for instanceId: String) {
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(Double.random(in: 3...8)))
            guard let index = activeInstances.firstIndex(where: { $0.id == instanceId }),
                  activeInstances[index].state == .submitted else { return }
            let instance = activeInstances[index]
            let session = trackingSessions[instanceId]

            let hasCritical = session?.hasCriticalViolation ?? false
            let timeWindowFailed = session?.timeWindowVerified == false
            if hasCritical || timeWindowFailed {
                activeInstances[index].state = .rejected
                let notification = AppNotification(
                    id: UUID().uuidString,
                    type: .questRejected,
                    title: "Side Quest Rejected",
                    message: "Your \(activeInstances[index].quest.title) submission was rejected.",
                    createdAt: Date(),
                    isRead: false,
                    deepLinkId: instanceId
                )
                notifications.insert(notification, at: 0)
            } else {
                simulateVerification(for: instanceId)
            }
        }
    }

    func simulateVerification(for instanceId: String) {
        guard let index = activeInstances.firstIndex(where: { $0.id == instanceId }) else { return }
        let instance = activeInstances[index]
        let quest = instance.quest

        if instance.mode != .solo && instance.groupSize > 1 && quest.isTrackingQuest {
            let pathsOk = simulatePathSimilarityCheck(for: instanceId)
            if !pathsOk {
                activeInstances[index].state = .rejected
                let n = AppNotification(
                    id: UUID().uuidString,
                    type: .questRejected,
                    title: "Group Run Rejected",
                    message: "Group run paths weren't similar enough (70%+ required). All members must run a similar route.",
                    createdAt: Date(),
                    isRead: false,
                    deepLinkId: instanceId
                )
                notifications.insert(n, at: 0)
                return
            }
        }

        activeInstances[index].state = .verified
        activeInstances[index].verifiedAt = Date()
        if notificationsEnabled {
            NotificationService.shared.fireQuestVerified(title: quest.title)
        }
        let activityItem = ActivityItem(
            id: UUID().uuidString,
            username: profile.username,
            avatarName: profile.avatarName,
            questTitle: quest.title,
            path: quest.path,
            isMaster: quest.type == .master,
            completedAt: Date()
        )
        activityFeed.insert(activityItem, at: 0)
        if activityFeed.count > 30 { activityFeed.removeLast() }

        if let session = trackingSessions[instanceId] {
            completedSessions[instanceId] = session
        }

        var xpMultiplier: Double = 1.0
        var goldMultiplier: Double = 1.0
        var bonusBadge: String? = nil

        if instance.mode != .solo && instance.groupSize > 1 {
            xpMultiplier *= 1.2
            goldMultiplier *= 1.2
            bonusBadge = "Group Run 1.2x"
            if instance.handshakeVerified {
                xpMultiplier *= 1.05
                goldMultiplier *= 1.05
                bonusBadge = "Group + Handshake 1.26x"
            }
        }

        let streakMult = LevelSystem.streakMultiplier(for: profile.currentStreak)
        xpMultiplier *= streakMult
        goldMultiplier *= streakMult

        let rawXP = Int(Double(quest.xpReward) * xpMultiplier)
        let finalXP = awardXPWithCap(rawXP)
        let finalGold = Int(Double(quest.goldReward) * goldMultiplier)

        trackCampaignXP(questId: quest.id, xp: finalXP)

        let reward = RewardEvent(
            id: UUID().uuidString,
            questTitle: quest.title,
            xpEarned: finalXP,
            goldEarned: finalGold,
            diamondsEarned: quest.diamondReward,
            streakBonus: streakMult > 1.0,
            streakMultiplier: streakMult,
            newBadge: bonusBadge,
            createdAt: Date()
        )
        pendingRewards.append(reward)
        completedHistory.insert(reward, at: 0)
        showRewardOverlay = true

        profile.totalScore += finalXP
        profile.gold += finalGold
        profile.diamonds += quest.diamondReward
        profile.verifiedCount += 1

        if instance.handshakeVerified {
            profile.handshakeCount += 1
        }

        questCompletionCounts[quest.id, default: 0] += 1
        recordDailyCompletion()
        updateMilestoneProgress(for: quest)
        updatePathRank(for: quest.path)
        checkLevelUp()
        checkAchievements()
        saveState()
    }

    func simulatePathSimilarityCheck(for instanceId: String) -> Bool {
        return true
    }

    func handleBackendVerificationResult(_ result: VerificationResult, instanceId: String) {
        guard let index = activeInstances.firstIndex(where: { $0.id == instanceId }) else { return }
        let quest = activeInstances[index].quest
        let instance = activeInstances[index]

        if result.rejected {
            activeInstances[index].state = .rejected
            let notification = AppNotification(
                id: UUID().uuidString,
                type: .questRejected,
                title: "Side Quest Rejected",
                message: result.reason ?? "Your \(quest.title) submission was rejected.",
                createdAt: Date(),
                isRead: false,
                deepLinkId: instanceId
            )
            notifications.insert(notification, at: 0)
            return
        }

        guard result.verified, let rewards = result.rewards else { return }

        activeInstances[index].state = .verified
        activeInstances[index].verifiedAt = Date()
        if notificationsEnabled {
            NotificationService.shared.fireQuestVerified(title: quest.title)
        }

        if let session = trackingSessions[instanceId] {
            completedSessions[instanceId] = session
        }
        if let session = exerciseSessions[instanceId] {
            completedExerciseSessions[instanceId] = session
        }
        if let session = focusSessions[instanceId] {
            completedFocusSessions[instanceId] = session
        }
        if let session = meditationSessions[instanceId] {
            completedMeditationSessions[instanceId] = session
        }

        postActivityToBackend(quest: quest, instance: instance)

        let finalXP = awardXPWithCap(rewards.xp)
        trackCampaignXP(questId: quest.id, xp: finalXP)

        var bonusBadge: String? = nil
        if instance.mode != .solo && instance.groupSize > 1 {
            bonusBadge = instance.handshakeVerified ? "Group + Handshake 1.26x" : "Group Run 1.2x"
        }

        let reward = RewardEvent(
            id: UUID().uuidString,
            questTitle: quest.title,
            xpEarned: finalXP,
            goldEarned: rewards.gold,
            diamondsEarned: rewards.diamonds,
            streakBonus: rewards.streakMultiplier > 1.0,
            streakMultiplier: rewards.streakMultiplier,
            newBadge: bonusBadge,
            createdAt: Date()
        )
        pendingRewards.append(reward)
        completedHistory.insert(reward, at: 0)
        showRewardOverlay = true

        profile.totalScore += finalXP
        profile.gold += rewards.gold
        profile.diamonds += rewards.diamonds
        profile.verifiedCount += 1

        if instance.handshakeVerified {
            profile.handshakeCount += 1
        }

        questCompletionCounts[quest.id, default: 0] += 1
        recordDailyCompletion()
        updateMilestoneProgress(for: quest)
        updatePathRank(for: quest.path)
        checkLevelUp()
        checkAchievements()
        saveState()
    }

    private func postActivityToBackend(quest: Quest, instance: QuestInstance) {
        let activityItem = ActivityItem(
            id: UUID().uuidString,
            username: profile.username,
            avatarName: profile.avatarName,
            questTitle: quest.title,
            path: quest.path,
            isMaster: quest.type == .master,
            completedAt: Date()
        )
        activityFeed.insert(activityItem, at: 0)
        if activityFeed.count > 30 { activityFeed.removeLast() }
    }

    func completeOpenPlayQuest(_ quest: Quest) {
        let instance = QuestInstance(
            id: UUID().uuidString,
            quest: quest,
            state: .verified,
            mode: .solo,
            startedAt: Date(),
            submittedAt: Date(),
            verifiedAt: Date(),
            groupId: nil
        )
        openPlayHistory.insert(instance, at: 0)
        questCompletionCounts[quest.id, default: 0] += 1

        let openStreakMult = LevelSystem.streakMultiplier(for: profile.currentStreak)
        let rawOpenXP = Int(Double(quest.xpReward) * openStreakMult)
        let openXP = awardXPWithCap(rawOpenXP)
        let openGold = Int(Double(quest.goldReward) * openStreakMult)

        profile.totalScore += openXP
        profile.gold += openGold

        let reward = RewardEvent(
            id: UUID().uuidString,
            questTitle: quest.title,
            xpEarned: openXP,
            goldEarned: openGold,
            diamondsEarned: 0,
            streakBonus: openStreakMult > 1.0,
            streakMultiplier: openStreakMult,
            newBadge: nil,
            createdAt: Date()
        )
        completedHistory.insert(reward, at: 0)
        recordDailyCompletion()
        checkLevelUp()
        checkAchievements()
        saveState()
    }

    func updateProfile(username: String, avatar: String) {
        profile.username = username
        profile.avatarName = avatar
        saveState()
    }

    func isCharacterOwned(_ character: PlayerCharacterType) -> Bool {
        character.isStarterSkin || profile.ownedItems.contains(character.displayName)
    }

    func selectCharacter(_ character: PlayerCharacterType) {
        guard isCharacterOwned(character) else { return }
        profile.selectedCharacter = character
        profile.equippedSkin = character.isStarterSkin ? nil : character.displayName
        saveState()
    }

    func generateReferralCode() -> String {
        "SIDEQUEST-\(profile.username.uppercased().prefix(4))-\(String(format: "%04d", Int.random(in: 1000...9999)))"
    }

    func fetchServerReferralCode() async -> String? {
        return nil
    }

    func redeemReferralCode(_ code: String) async -> ReferralRedeemResult? {
        return nil
    }

    func startTimeIntegrity() {
        timeIntegrity.start()
    }

    func startContract(_ contractId: String) {
        guard let index = masterContracts.firstIndex(where: { $0.id == contractId }) else { return }
        guard !masterContracts[index].isActive && !masterContracts[index].isCompleted else { return }

        if timeIntegrity.hasTimeManipulation {
            let n = AppNotification(
                id: UUID().uuidString,
                type: .questRejected,
                title: "Contract Blocked",
                message: "Clock manipulation detected. Restore automatic time settings to start a contract.",
                createdAt: Date(),
                isRead: false,
                deepLinkId: nil
            )
            notifications.insert(n, at: 0)
            return
        }

        masterContracts[index].isActive = true
        masterContracts[index].startedAt = Date()
        masterContracts[index].currentDay = 1

        let contract = masterContracts[index]
        let notification = AppNotification(
            id: UUID().uuidString,
            type: .featuredQuest,
            title: "Contract Started!",
            message: "You've begun \(contract.title). Stay disciplined!",
            createdAt: Date(),
            isRead: false,
            deepLinkId: contract.id
        )
        notifications.insert(notification, at: 0)
    }

    func purchaseItem(name: String, price: Int) -> Bool {
        guard profile.gold >= price else {
            showToast(.warning, title: "Not Enough Gold", message: "You need \(price - profile.gold) more gold for this item.")
            return false
        }
        guard !profile.ownedItems.contains(name) else { return false }
        profile.gold -= price
        profile.ownedItems.append(name)
        saveState()
        return true
    }

    func equipItem(name: String, category: ShopCategory) {
        switch category {
        case .skins:
            guard let character = PlayerCharacterType.shopCharacter(named: name) else { return }
            selectCharacter(character)
            return
        case .callingCards:
            let nextBackground: String? = profile.equippedCallingCard == name ? nil : name
            profile.equippedCallingCard = nextBackground
            profile.callingCardName = nextBackground ?? "gradient1"
        case .effects:
            profile.equippedEffect = profile.equippedEffect == name ? nil : name
        case .removeAds:
            break
        }
        saveState()
    }

    func purchaseSpriteItem(_ item: SpriteCosmeticItem) -> Bool {
        switch item.currencyType {
        case .gold:
            guard profile.gold >= item.price else { return false }
            profile.gold -= item.price
        case .diamonds:
            guard profile.diamonds >= item.price else { return false }
            profile.diamonds -= item.price
        }
        guard !profile.ownedSpriteItems.contains(item.id) else { return false }
        profile.ownedSpriteItems.append(item.id)
        saveState()
        return true
    }

    func equipSpriteItem(_ itemId: String, slot: SpriteSlot) {
        let current = profile.spriteLoadout.item(for: slot)
        if current == itemId {
            profile.spriteLoadout.equip(nil, slot: slot)
        } else {
            profile.spriteLoadout.equip(itemId, slot: slot)
        }
        saveState()
    }

    func setSpriteBodyColor(_ color: SpriteBodyColor) {
        profile.spriteLoadout.bodyColor = color
        saveState()
    }

    func recordModScreenshotStrike() {
        profile.screenshotStrikes += 1
        if profile.screenshotStrikes >= 3 {
            profile.isSuspended = true
            profile.modBanUntil = Calendar.current.date(byAdding: .hour, value: 24, to: Date())
            profile.karma = max(0, profile.karma - 50)
            let n = AppNotification(
                id: UUID().uuidString,
                type: .questRejected,
                title: "Mod Access Suspended",
                message: "Your moderation privileges have been suspended for 24 hours due to repeated evidence screenshots.",
                createdAt: Date(),
                isRead: false,
                deepLinkId: nil
            )
            notifications.insert(n, at: 0)
        }
    }

    func modVote(_ vote: ModVote) {
        profile.modSessionsCompleted += 1
        if vote == .approve {
            profile.karma += 2
        } else if vote == .reject {
            profile.karma += 1
        }
        let newAccuracy = min(1.0, profile.modAccuracy + 0.001)
        profile.modAccuracy = newAccuracy
    }

    func dismissReward() {
        if !pendingRewards.isEmpty {
            pendingRewards.removeFirst()
        }
        if pendingRewards.isEmpty {
            showRewardOverlay = false
        }
    }

    func markNotificationRead(_ id: String) {
        guard let index = notifications.firstIndex(where: { $0.id == id }) else { return }
        notifications[index].isRead = true
        updateBadgeCount()
    }

    func handleNotificationDeepLink(_ notification: AppNotification) {
        markNotificationRead(notification.id)
        switch notification.type {
        case .questVerified, .questRejected:
            selectedTab = 3
            deepLinkDestination = .questLog
        case .modTask:
            selectedTab = 3
        case .groupInvite:
            selectedTab = 0
        case .featuredQuest:
            if let questId = notification.deepLinkId,
               let quest = allQuests.first(where: { $0.id == questId }) {
                deepLinkQuestId = quest.id
            }
            selectedTab = 0
        case .voteAlignment:
            selectedTab = 3
        case .weeklyReport:
            selectedTab = 3
        case .nudge:
            selectedTab = 0
        }
    }

    func handlePushNotificationTap(type: String, deepLinkId: String) {
        guard let notifType = NotificationType(rawValue: type) else { return }
        let placeholder = AppNotification(
            id: UUID().uuidString,
            type: notifType,
            title: "",
            message: "",
            createdAt: Date(),
            isRead: false,
            deepLinkId: deepLinkId
        )
        handleNotificationDeepLink(placeholder)
        updateBadgeCount()
    }

    func requestNotificationPermissionIfNeeded() {
        let hasAsked = UserDefaults.standard.bool(forKey: "hasAskedNotificationPermission")
        guard !hasAsked else {
            updateBadgeCount()
            return
        }
        UserDefaults.standard.set(true, forKey: "hasAskedNotificationPermission")
        Task {
            let granted = await NotificationService.shared.requestAuthorization()
            if granted {
                notificationsEnabled = true
                UserDefaults.standard.set(true, forKey: "notificationsEnabled")
                NotificationService.shared.scheduleRecurring()
                await MainActor.run {
                    UIApplication.shared.registerForRemoteNotifications()
                }
            }
            updateBadgeCount()
        }
    }

    func requestCameraAndMicIfNeeded() {
        Task {
            let camStatus = AVCaptureDevice.authorizationStatus(for: .video)
            if camStatus == .notDetermined {
                let _ = await AVCaptureDevice.requestAccess(for: .video)
            }
            let micStatus = AVCaptureDevice.authorizationStatus(for: .audio)
            if micStatus == .notDetermined {
                let _ = await AVCaptureDevice.requestAccess(for: .audio)
            }
            if stepCountService.isAvailable && !stepCountService.isAuthorized {
                let authorized = await stepCountService.requestAuthorization()
                if authorized {
                    stepsEnabled = true
                    UserDefaults.standard.set(true, forKey: "stepsEnabled")
                    syncSteps()
                }
            }
        }
    }

    func updateBadgeCount() {
        let count = notifications.filter { !$0.isRead }.count
        UNUserNotificationCenter.current().setBadgeCount(count)
    }

    func refreshDailyQuests() {
        let cal = Calendar.current
        let today = cal.startOfDay(for: Date())
        if let lastDate = dailyQuestDate, cal.isDate(lastDate, inSameDayAs: today) {
            return
        }
        let seed = cal.dateComponents([.year, .day], from: today)
        var rng = SeededRandomNumberGenerator(seed: UInt64(seed.year ?? 0) * 1000 + UInt64(seed.day ?? 0))
        let verified = allQuests.filter { $0.type == .verified && !$0.isFeatured }
        var picked: [Quest] = []
        for path in QuestPath.allCases {
            let pathQuests = verified.filter { $0.path == path }.shuffled(using: &rng)
            if let q = pathQuests.first {
                picked.append(q)
            }
        }
        dailyQuests = picked
        dailyQuestDate = today
    }

    func movePathOrder(from source: IndexSet, to destination: Int) {
        pathOrder.move(fromOffsets: source, toOffset: destination)
        UserDefaults.standard.set(pathOrder.map(\.rawValue), forKey: "pathOrder")
    }

    func dailyQuestForPath(_ path: QuestPath) -> Quest? {
        dailyQuests.first { $0.path == path }
    }

    func questsForPath(_ path: QuestPath, type: QuestType) -> [Quest] {
        allQuests.filter { $0.path == path && $0.type == type }
    }

    func leaderboardForPeriod(_ period: LeaderboardPeriod) -> [LeaderboardEntry] {
        return leaderboard
    }

    var onlineFriends: [Friend] {
        friends.filter { $0.isAccepted && $0.isOnline }
    }

    var acceptedFriends: [Friend] {
        friends.filter { $0.isAccepted }
    }

    var pendingFriendCount: Int {
        friendRequests.count
    }

    func acceptFriendRequest(_ requestId: String) {
        guard let request = friendRequests.first(where: { $0.id == requestId }) else { return }
        friendRequests.removeAll { $0.id == requestId }
        let newFriend = Friend(
            id: request.fromUserId.isEmpty ? UUID().uuidString : request.fromUserId,
            username: request.fromUsername,
            avatarName: request.fromAvatarName,
            callingCardName: request.fromCallingCardName,
            totalScore: request.fromTotalScore,
            verifiedCount: request.fromVerifiedCount,
            currentStreak: 0,
            warriorRank: 1,
            explorerRank: 1,
            mindRank: 1,
            status: .accepted,
            addedAt: Date(),
            lastActiveAt: Date(),
            isOnline: true
        )
        if !friends.contains(where: { $0.id == newFriend.id }) {
            friends.append(newFriend)
        }
        let n = AppNotification(
            id: UUID().uuidString,
            type: .groupInvite,
            title: "New Friend!",
            message: "You and \(request.fromUsername) are now friends.",
            createdAt: Date(),
            isRead: false,
            deepLinkId: nil
        )
        notifications.insert(n, at: 0)
    }

    func declineFriendRequest(_ requestId: String) {
        guard let _ = friendRequests.first(where: { $0.id == requestId }) else {
            friendRequests.removeAll { $0.id == requestId }
            return
        }
        friendRequests.removeAll { $0.id == requestId }
    }

    func removeFriend(_ friendId: String) {
        friends.removeAll { $0.id == friendId }
    }

    func signOut() {
        auth.signOut()
        isAuthenticated = false
        needsProfileSetup = false
        hasOnboarded = false
        UserDefaults.standard.set(false, forKey: "hasOnboarded")
        PersistenceService.clearAll()
        profile = SampleData.newUserProfile
        activeInstances = []
        notifications = []
        completedHistory = []
        openPlayHistory = []
        pendingRewards = []
        showRewardOverlay = false
        selectedTab = 0
        questCompletionCounts = [:]
        brainScores = [:]
        savedQuestIds = []
        dailyCompletions = [:]
        lastStreakDate = nil
        previousLevel = 0
        customQuests = []
        communitySubmissions = []
        dailyXPEarned = [:]
        onboardingData = .empty
        showOnboardingRefresh = false
        stepCoinsAwardedToday = 0
        UserDefaults.standard.removeObject(forKey: "stepCoinsAwardedDate")
        UserDefaults.standard.removeObject(forKey: "stepCoinsAwardedCount")
    }

    func deleteAccount() async {
        signOut()
    }

    func setNotificationsEnabled(_ enabled: Bool) {
        notificationsEnabled = enabled
        UserDefaults.standard.set(enabled, forKey: "notificationsEnabled")
        if enabled {
            Task {
                let granted = await NotificationService.shared.requestAuthorization()
                if granted {
                    NotificationService.shared.scheduleRecurring()
                }
            }
        } else {
            NotificationService.shared.cancelRecurring()
        }
    }

    func setStepsEnabled(_ enabled: Bool) {
        stepsEnabled = enabled
        UserDefaults.standard.set(enabled, forKey: "stepsEnabled")
        if enabled {
            Task {
                let authorized = await stepCountService.requestAuthorization()
                if authorized {
                    syncSteps()
                }
            }
        }
    }

    func syncSteps() {
        stepCountService.refreshAuthorizationStatus()
        if stepCountService.isAuthorized {
            profile.stepsToday = stepCountService.stepsToday
            profile.stepsThisWeek = stepCountService.stepsThisWeek
            awardStepCoins()
        }
    }

    private func awardStepCoins() {
        let today = Calendar.current.startOfDay(for: Date())
        let savedDate = UserDefaults.standard.object(forKey: "stepCoinsAwardedDate") as? Date
        if savedDate == nil || !Calendar.current.isDate(savedDate!, inSameDayAs: today) {
            stepCoinsAwardedToday = 0
            UserDefaults.standard.set(today, forKey: "stepCoinsAwardedDate")
            UserDefaults.standard.set(0, forKey: "stepCoinsAwardedCount")
        }

        let deservedCoins = min(profile.stepsToday / 100, 50)
        let delta = deservedCoins - stepCoinsAwardedToday
        guard delta > 0 else { return }

        profile.gold += delta
        stepCoinsAwardedToday = deservedCoins
        UserDefaults.standard.set(deservedCoins, forKey: "stepCoinsAwardedCount")
        saveState()
    }

    func refreshSteps() {
        stepCountService.refreshAuthorizationStatus()
        guard stepsEnabled, stepCountService.isAuthorized else { return }
        Task {
            await stepCountService.fetchSteps()
            syncSteps()
        }
    }

    func toggleSavedQuest(_ questId: String) {
        if savedQuestIds.contains(questId) {
            savedQuestIds.removeAll { $0 == questId }
        } else {
            savedQuestIds.append(questId)
        }
        saveState()
    }

    func moveSavedQuest(from source: IndexSet, to destination: Int) {
        savedQuestIds.move(fromOffsets: source, toOffset: destination)
        saveState()
    }

    func isQuestSaved(_ questId: String) -> Bool {
        savedQuestIds.contains(questId)
    }

    var savedQuests: [Quest] {
        savedQuestIds.compactMap { id in allQuests.first { $0.id == id } }
    }

    private func updateMilestoneProgress(for quest: Quest) {
        for milestoneId in quest.milestoneIds {
            if let index = milestones.firstIndex(where: { $0.id == milestoneId }) {
                if milestones[index].currentCount < milestones[index].requiredCount {
                    milestones[index].currentCount += 1
                }
            }
        }
    }

    func updatePathRank(for path: QuestPath) {
        let count = completedHistory.count
        let rankUp = count % 5 == 0
        if rankUp {
            switch path {
            case .warrior: profile.warriorRank += 1
            case .explorer: profile.explorerRank += 1
            case .mind: profile.mindRank += 1
            }
        }
    }

    func recordVisitedPOI(_ poi: MapPOI, questTitle: String) {
        guard !hasVisitedPOI(poi) else { return }
        let visited = VisitedPOI(
            id: poi.id,
            name: poi.name,
            latitude: poi.coordinate.latitude,
            longitude: poi.coordinate.longitude,
            category: poi.category.rawValue,
            visitedAt: Date(),
            questTitle: questTitle
        )
        visitedPOIs.append(visited)
        PersistenceService.saveVisitedPOIs(visitedPOIs)
    }

    func hasVisitedPOI(_ poi: MapPOI) -> Bool {
        visitedPOIs.contains { $0.id == poi.id }
    }

    func recordDailyCompletion() {
        let today = Calendar.current.startOfDay(for: Date())
        dailyCompletions[today, default: 0] += 1
        updateStreak()
    }

    private func updateStreak() {
        let cal = Calendar.current
        let today = cal.startOfDay(for: Date())
        if let last = lastStreakDate {
            let lastDay = cal.startOfDay(for: last)
            if lastDay == today {
                return
            } else if cal.isDate(lastDay, equalTo: cal.date(byAdding: .day, value: -1, to: today)!, toGranularity: .day) {
                profile.currentStreak += 1
            } else {
                profile.currentStreak = 1
            }
        } else {
            profile.currentStreak = 1
        }
        lastStreakDate = today
    }

    func weeklyStreakDays() -> [Bool] {
        let cal = Calendar.current
        let today = cal.startOfDay(for: Date())
        guard let weekStart = cal.date(from: cal.dateComponents([.yearForWeekOfYear, .weekOfYear], from: today)) else {
            return Array(repeating: false, count: 7)
        }
        return (0..<7).map { offset in
            guard let day = cal.date(byAdding: .day, value: offset, to: weekStart) else { return false }
            return (dailyCompletions[day] ?? 0) > 0
        }
    }

    func submitEvidence(for instanceId: String) {
        guard let index = activeInstances.firstIndex(where: { $0.id == instanceId }) else { return }
        guard activeInstances[index].canSubmit else { return }
        let quest = activeInstances[index].quest
        if quest.hasTimeWindow && !quest.isWithinTimeWindow {
            return
        }
        if timeIntegrity.hasTimeManipulation {
            activeInstances[index].state = .rejected
            let n = AppNotification(
                id: UUID().uuidString,
                type: .questRejected,
                title: "Submission Rejected",
                message: "Clock manipulation detected during \(quest.title). Evidence invalidated.",
                createdAt: Date(),
                isRead: false,
                deepLinkId: instanceId
            )
            notifications.insert(n, at: 0)
            return
        }
        activeInstances[index].state = .submitted
        activeInstances[index].submittedAt = Date()
        scheduleAutoVerification(for: instanceId)
    }

    func submitStepQuestEvidence(for instanceId: String, stepsRecorded: Int) {
        guard let index = activeInstances.firstIndex(where: { $0.id == instanceId }) else { return }
        activeInstances[index].state = .submitted
        activeInstances[index].submittedAt = Date()
        scheduleStepVerification(for: instanceId, stepsRecorded: stepsRecorded)
    }

    func scheduleStepVerification(for instanceId: String, stepsRecorded: Int) {
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(Double.random(in: 2...5)))
            guard let index = activeInstances.firstIndex(where: { $0.id == instanceId }),
                  activeInstances[index].state == .submitted else { return }
            let quest = activeInstances[index].quest

            let target = quest.targetSteps ?? 0
            if stepsRecorded >= target {
                simulateVerification(for: instanceId)
            } else {
                activeInstances[index].state = .rejected
                let notification = AppNotification(
                    id: UUID().uuidString,
                    type: .questRejected,
                    title: "Side Quest Rejected",
                    message: "Your \(quest.title) submission was rejected. Steps recorded: \(stepsRecorded)/\(target).",
                    createdAt: Date(),
                    isRead: false,
                    deepLinkId: instanceId
                )
                notifications.insert(notification, at: 0)
            }
        }
    }

    func submitExerciseEvidence(for instanceId: String, session: ExerciseSession) {
        guard let index = activeInstances.firstIndex(where: { $0.id == instanceId }) else { return }
        activeInstances[index].state = .submitted
        activeInstances[index].submittedAt = Date()
        exerciseSessions[instanceId] = session
        scheduleExerciseVerification(for: instanceId)
    }

    func submitReadingEvidence(for instanceId: String, session: ReadingSession) {
        guard let index = activeInstances.firstIndex(where: { $0.id == instanceId }) else { return }
        activeInstances[index].state = .submitted
        activeInstances[index].submittedAt = Date()
        readingSessions[instanceId] = session
        scheduleReadingVerification(for: instanceId)
    }

    func scheduleReadingVerification(for instanceId: String) {
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(Double.random(in: 3...8)))
            guard let index = activeInstances.firstIndex(where: { $0.id == instanceId }),
                  activeInstances[index].state == .submitted else { return }
            let session = readingSessions[instanceId]
            if let s = session { completedReadingSessions[instanceId] = s }
            simulateVerification(for: instanceId)
        }
    }

    func submitMeditationEvidence(for instanceId: String, session: MeditationSession) {
        guard let index = activeInstances.firstIndex(where: { $0.id == instanceId }) else { return }
        activeInstances[index].state = .submitted
        activeInstances[index].submittedAt = Date()
        meditationSessions[instanceId] = session
        scheduleMeditationVerification(for: instanceId)
    }

    func submitFocusEvidence(for instanceId: String, session: FocusSession) {
        guard let index = activeInstances.firstIndex(where: { $0.id == instanceId }) else { return }
        activeInstances[index].state = .submitted
        activeInstances[index].submittedAt = Date()
        focusSessions[instanceId] = session
        scheduleFocusVerification(for: instanceId)
    }

    func scheduleFocusVerification(for instanceId: String) {
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(Double.random(in: 3...8)))
            guard let index = activeInstances.firstIndex(where: { $0.id == instanceId }),
                  activeInstances[index].state == .submitted else { return }
            let quest = activeInstances[index].quest
            let session = focusSessions[instanceId]

            let hasCritical = session?.hasCriticalViolation ?? false
            if hasCritical {
                activeInstances[index].state = .rejected
                let notification = AppNotification(
                    id: UUID().uuidString,
                    type: .questRejected,
                    title: "Side Quest Rejected",
                    message: "Your \(quest.title) submission was rejected due to integrity violations.",
                    createdAt: Date(),
                    isRead: false,
                    deepLinkId: instanceId
                )
                notifications.insert(notification, at: 0)
            } else {
                if let s = session { completedFocusSessions[instanceId] = s }
                simulateVerification(for: instanceId)
            }
        }
    }

    func scheduleMeditationVerification(for instanceId: String) {
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(Double.random(in: 3...8)))
            guard let index = activeInstances.firstIndex(where: { $0.id == instanceId }),
                  activeInstances[index].state == .submitted else { return }
            let quest = activeInstances[index].quest
            let session = meditationSessions[instanceId]

            let hasCritical = session?.hasCriticalViolation ?? false
            if hasCritical {
                activeInstances[index].state = .rejected
                let notification = AppNotification(
                    id: UUID().uuidString,
                    type: .questRejected,
                    title: "Side Quest Rejected",
                    message: "Your \(quest.title) submission was rejected due to integrity violations.",
                    createdAt: Date(),
                    isRead: false,
                    deepLinkId: instanceId
                )
                notifications.insert(notification, at: 0)
            } else {
                if let s = session { completedMeditationSessions[instanceId] = s }
                simulateVerification(for: instanceId)
            }
        }
    }

    func scheduleExerciseVerification(for instanceId: String) {
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(Double.random(in: 3...8)))
            guard let index = activeInstances.firstIndex(where: { $0.id == instanceId }),
                  activeInstances[index].state == .submitted else { return }
            let quest = activeInstances[index].quest
            let session = exerciseSessions[instanceId]

            let hasCritical = session?.hasCriticalViolation ?? false
            if hasCritical {
                activeInstances[index].state = .rejected
                let notification = AppNotification(
                    id: UUID().uuidString,
                    type: .questRejected,
                    title: "Side Quest Rejected",
                    message: "Your \(quest.title) submission was rejected due to integrity violations.",
                    createdAt: Date(),
                    isRead: false,
                    deepLinkId: instanceId
                )
                notifications.insert(notification, at: 0)
            } else {
                if let s = session { completedExerciseSessions[instanceId] = s }
                simulateVerification(for: instanceId)
            }
        }
    }

    private func awardXPWithCap(_ rawXP: Int) -> Int {
        let today = Calendar.current.startOfDay(for: Date())
        let earned = dailyXPEarned[today] ?? 0
        let capped = XPGuardrails.applyDailyCap(rawXP: rawXP, alreadyEarnedToday: earned)
        dailyXPEarned[today] = earned + capped
        PersistenceService.saveDailyXPEarned(dailyXPEarned)
        return capped
    }

    private func trackCampaignXP(questId: String, xp: Int) {
        for i in journeys.indices {
            guard journeys[i].isActive else { continue }
            let hasQuest = journeys[i].questItems.contains { $0.questId == questId }
            if hasQuest {
                journeys[i].campaignBaseXPEarned += xp
                saveJourneyData()
            }
        }
    }

    private func checkLevelUp() {
        let currentLevel = profile.level
        if currentLevel > previousLevel && previousLevel > 0 {
            newLevelReached = currentLevel
            showLevelUp = true
        }
        previousLevel = currentLevel
    }

    func checkAchievements() {
        var newBadges: [String] = []
        for achievement in AchievementCatalog.all {
            guard !profile.earnedBadges.contains(achievement.id) else { continue }
            let earned: Bool
            switch achievement.id {
            case "first_quest": earned = profile.verifiedCount >= 1
            case "quest_10": earned = profile.verifiedCount >= 10
            case "quest_25": earned = profile.verifiedCount >= 25
            case "quest_50": earned = profile.verifiedCount >= 50
            case "quest_100": earned = profile.verifiedCount >= 100
            case "streak_3": earned = profile.currentStreak >= 3
            case "streak_7": earned = profile.currentStreak >= 7
            case "streak_14": earned = profile.currentStreak >= 14
            case "streak_30": earned = profile.currentStreak >= 30
            case "friends_1": earned = acceptedFriends.count >= 1
            case "friends_5": earned = acceptedFriends.count >= 5
            case "handshake_3": earned = profile.handshakeCount >= 3
            case "brain_champ": earned = brainScores.values.contains { $0 >= 5 }
            case "level_5": earned = profile.level >= 5
            case "level_10": earned = profile.level >= 10
            case "level_20": earned = profile.level >= 20
            case "level_50": earned = profile.level >= 50
            case "mod_10": earned = profile.modSessionsCompleted >= 10
            case "gold_1000": earned = profile.gold >= 1000
            case "warrior_10": earned = profile.warriorRank >= 10
            case "explorer_10": earned = profile.explorerRank >= 10
            case "mind_10": earned = profile.mindRank >= 10
            default: earned = false
            }
            if earned {
                newBadges.append(achievement.id)
            }
        }
        if !newBadges.isEmpty {
            profile.earnedBadges.append(contentsOf: newBadges)
            saveState()
        }
    }

    func setSavedGym(_ gym: SavedGym?) {
        savedGym = gym
        PersistenceService.saveSavedGym(gym)
    }

    func saveState() {
        PersistenceService.saveProfile(profile)
        PersistenceService.saveCompletedHistory(completedHistory)
        PersistenceService.saveSavedQuestIds(savedQuestIds)
        PersistenceService.saveBrainScores(brainScores)
        PersistenceService.saveDailyCompletions(dailyCompletions)
        PersistenceService.saveLastStreakDate(lastStreakDate)
        PersistenceService.saveEarnedBadges(profile.earnedBadges)
        PersistenceService.saveQuestCompletionCounts(questCompletionCounts)
        PersistenceService.saveVisitedPOIs(visitedPOIs)
        PersistenceService.saveSavedGym(savedGym)
        PersistenceService.saveActiveInstances(activeInstances)
        PersistenceService.saveOpenPlayHistory(openPlayHistory)
        syncWidgetData()
    }

    func syncWidgetData() {
        let activeQuest = activeInstances.first(where: { $0.state.isActive })?.quest
        let today = Calendar.current.startOfDay(for: Date())
        let todayCount = dailyCompletions[today] ?? 0
        WidgetDataService.update(
            username: profile.username,
            level: profile.level,
            levelTitle: profile.levelTitle,
            levelIcon: LevelSystem.iconName(for: profile.level),
            xpCurrent: profile.xpForCurrentLevel,
            xpNeeded: profile.xpNeededForNextLevel,
            totalScore: profile.totalScore,
            streak: profile.currentStreak,
            verifiedCount: profile.verifiedCount,
            activeQuestTitle: activeQuest?.title,
            activeQuestPath: activeQuest?.path.rawValue,
            activeQuestIcon: activeQuest?.path.iconName,
            dailyCompletions: todayCount,
            weeklyStreakDays: weeklyStreakDays()
        )
    }

    private func loadPersistedData() {
        if let saved = PersistenceService.loadProfile() {
            profile = saved
        }
        if let history = PersistenceService.loadCompletedHistory() {
            completedHistory = history
        }
        let ids = PersistenceService.loadSavedQuestIds()
        if !ids.isEmpty { savedQuestIds = ids }
        let scores = PersistenceService.loadBrainScores()
        if !scores.isEmpty { brainScores = scores }
        let completions = PersistenceService.loadDailyCompletions()
        if !completions.isEmpty { dailyCompletions = completions }
        lastStreakDate = PersistenceService.loadLastStreakDate()
        let badges = PersistenceService.loadEarnedBadges()
        if !badges.isEmpty {
            profile.earnedBadges = badges
        } else if profile.earnedBadges.isEmpty {
            let starterBadges = ["first_quest", "streak_3", "streak_7", "friends_1", "brain_champ", "level_5", "gold_1000", "mod_10"]
            profile.earnedBadges = starterBadges
            PersistenceService.saveEarnedBadges(starterBadges)
        }
        let qCounts = PersistenceService.loadQuestCompletionCounts()
        if !qCounts.isEmpty { questCompletionCounts = qCounts }
        let xpEarned = PersistenceService.loadDailyXPEarned()
        if !xpEarned.isEmpty { dailyXPEarned = xpEarned }
        let visited = PersistenceService.loadVisitedPOIs()
        if !visited.isEmpty { visitedPOIs = visited }
        savedGym = PersistenceService.loadSavedGym()
        if let savedInstances = PersistenceService.loadActiveInstances() {
            activeInstances = savedInstances
        }
        if activeInstances.isEmpty {
            activeInstances = []
        }
        if let savedHistory = PersistenceService.loadOpenPlayHistory() {
            openPlayHistory = savedHistory
        }
    }

    private func restorePersistedExternalDiscoveryState() {
        let intent = currentExternalDiscoveryIntent
        let spoofPostalCode = externalEventSpoofPostalCode
        let maxAge = persistedExternalDiscoveryMaxAge
        externalDiscoveryRestoreTask?.cancel()
        externalDiscoveryRestoreTask = Task.detached(priority: .utility) { [weak self] in
            guard let persisted = PersistenceService.loadExternalDiscoveryState(intent: intent) else { return }
            guard !Task.isCancelled else { return }
            guard Date().timeIntervalSince(persisted.savedAt) <= maxAge else {
                return
            }

            if !spoofPostalCode.isEmpty,
               let postalCode = persisted.searchLocation.postalCode,
               postalCode != spoofPostalCode {
                return
            }

            let sanitizedSnapshot = Self.sanitizedExternalDiscoverySnapshot(persisted.snapshot)
            await MainActor.run {
                guard let self else { return }
                guard self.externalEventSnapshot == nil else { return }
                guard self.currentExternalDiscoveryIntent == persisted.intent else { return }
                self.externalEventSearchLocation = persisted.searchLocation
                self.applyExternalDiscoverySnapshot(sanitizedSnapshot, intent: persisted.intent)
                self.schedulePersistedExternalDiscoveryCacheReconciliation(
                    searchLocation: persisted.searchLocation,
                    intent: persisted.intent
                )
            }
        }
    }

    @MainActor
    private func schedulePersistedExternalDiscoveryCacheReconciliation(
        searchLocation: ExternalEventSearchLocation,
        intent: ExternalDiscoveryIntent
    ) {
        Task(priority: .utility) { [weak self] in
            guard let self else { return }
            guard let cachedSnapshot = await self.supabaseEventFeedCacheService.load(
                searchLocation: searchLocation,
                intent: intent
            ) else {
                return
            }

            let displaySnapshot = await self.displaySnapshot(
                from: cachedSnapshot,
                searchLocation: searchLocation,
                primaryIntent: intent,
                filterOption: self.externalEventFilterOption
            )

            await MainActor.run {
                guard self.currentExternalDiscoveryIntent == intent else { return }
                if self.shouldApplyCachedDiscoverySnapshot(displaySnapshot) {
                    self.externalEventSearchLocation = searchLocation
                    self.applyExternalDiscoverySnapshot(displaySnapshot, intent: intent)
                }
            }
        }
    }

    private func normalizeCosmeticState() {
        var didChange: Bool = false

        if !profile.selectedCharacter.isStarterSkin,
           !profile.ownedItems.contains(profile.selectedCharacter.displayName) {
            profile.ownedItems.append(profile.selectedCharacter.displayName)
            didChange = true
        }

        let migratedBackground: String? = profile.equippedCallingCard ?? ProfileBackgroundStyle.shopName(for: profile.callingCardName)
        if profile.equippedCallingCard != migratedBackground {
            profile.equippedCallingCard = migratedBackground
            didChange = true
        }

        if let equippedCallingCard = profile.equippedCallingCard,
           !profile.ownedItems.contains(equippedCallingCard) {
            profile.ownedItems.append(equippedCallingCard)
            didChange = true
        }

        let normalizedCallingCardName: String = profile.equippedCallingCard ?? ProfileBackgroundStyle.normalizedPersistedName(profile.callingCardName)
        if profile.callingCardName != normalizedCallingCardName {
            profile.callingCardName = normalizedCallingCardName
            didChange = true
        }

        if let equippedEffect = profile.equippedEffect,
           !profile.ownedItems.contains(equippedEffect) {
            profile.ownedItems.append(equippedEffect)
            didChange = true
        }

        let normalizedSkin: String? = profile.selectedCharacter.isStarterSkin ? nil : profile.selectedCharacter.displayName
        if profile.equippedSkin != normalizedSkin {
            profile.equippedSkin = normalizedSkin
            didChange = true
        }

        if didChange {
            saveState()
        }
    }

    // MARK: - Journey Methods

    var activeJourneys: [Journey] {
        journeys.filter { $0.status == .active }
    }

    var completedJourneys: [Journey] {
        journeys.filter { $0.status == .completed }
    }

    var maxActiveJourneys: Int { 1 }

    var canCreateJourney: Bool {
        activeJourneys.count < maxActiveJourneys
    }

    func createJourney(
        name: String,
        durationType: JourneyDurationType,
        startDate: Date,
        endDate: Date,
        mode: JourneyMode,
        visibility: JourneyVisibility,
        questItems: [JourneyQuestItem],
        calendarSync: Bool,
        calendarAlert: CalendarAlertOption,
        invitedFriendIds: [String],
        verificationMode: JourneyVerificationMode = .verified,
        difficulty: QuestDifficulty = .medium
    ) -> Journey {
        let journey = Journey(
            id: UUID().uuidString,
            name: name,
            durationType: durationType,
            startDate: startDate,
            endDate: endDate,
            mode: mode,
            visibility: visibility,
            status: .active,
            questItems: questItems,
            dayProgress: [],
            calendarSyncEnabled: calendarSync,
            calendarAlert: calendarAlert,
            calendarEventIds: [:],
            friendProgress: [],
            invitedFriendIds: invitedFriendIds,
            templateId: nil,
            createdAt: Date(),
            streakDays: 0,
            verificationMode: verificationMode,
            difficulty: difficulty,
            campaignBaseXPEarned: 0,
            completionBonusAwarded: false,
            earlyBonusAwarded: false
        )
        journeys.append(journey)
        initializeJourneyDayProgress(journeyId: journey.id)

        if calendarSync {
            Task {
                let granted = await calendarService.requestAccess()
                if granted {
                    let eventIds = calendarService.createJourneyEvents(
                        journey: journey,
                        quests: allQuests,
                        alertOffset: calendarAlert.seconds,
                        calendar: calendarService.sideQuestCalendar()
                    )
                    if let idx = journeys.firstIndex(where: { $0.id == journey.id }) {
                        journeys[idx].calendarEventIds = eventIds
                    }
                }
            }
        }

        if mode == .withFriends {
            setupFriendProgress(journeyId: journey.id, friendIds: invitedFriendIds)
        }

        saveJourneyData()
        return journey
    }

    private func initializeJourneyDayProgress(journeyId: String) {
        guard let idx = journeys.firstIndex(where: { $0.id == journeyId }) else { return }
        let journey = journeys[idx]
        let cal = Calendar.current
        var progress: [JourneyDayProgress] = []
        for dayOffset in 0..<journey.totalDays {
            guard let date = cal.date(byAdding: .day, value: dayOffset, to: cal.startOfDay(for: journey.startDate)) else { continue }
            let scheduled = journey.scheduledQuestsForDate(date)
            var statuses: [String: JourneyQuestStatus] = [:]
            for item in scheduled {
                statuses[item.id] = .notStarted
            }
            if !statuses.isEmpty {
                progress.append(JourneyDayProgress(
                    id: "\(journeyId)_\(dayOffset)",
                    date: date,
                    questStatuses: statuses
                ))
            }
        }
        journeys[idx].dayProgress = progress
    }

    private func setupFriendProgress(journeyId: String, friendIds: [String]) {
        guard let idx = journeys.firstIndex(where: { $0.id == journeyId }) else { return }
        let journey = journeys[idx]
        var fp: [JourneyFriendProgress] = []
        for friendId in friendIds {
            guard let friend = friends.first(where: { $0.id == friendId }) else { continue }
            let todayCount = journey.todayTaskCount
            fp.append(JourneyFriendProgress(
                id: UUID().uuidString,
                friendId: friendId,
                username: friend.username,
                avatarName: friend.avatarName,
                todayCompleted: Int.random(in: 0...max(0, todayCount - 1)),
                todayTotal: todayCount,
                overallPercent: Double.random(in: 0...0.4)
            ))
        }
        journeys[idx].friendProgress = fp
    }

    func addQuestToJourney(journeyId: String, questId: String) {
        guard let idx = journeys.firstIndex(where: { $0.id == journeyId }) else { return }
        let alreadyExists = journeys[idx].questItems.contains { $0.questId == questId }
        guard !alreadyExists else { return }
        let item = JourneyQuestItem(
            id: UUID().uuidString,
            questId: questId,
            frequency: .daily,
            specificDays: [],
            scheduledHour: nil,
            scheduledMinute: nil,
            isAnytime: true,
            questMode: .solo
        )
        journeys[idx].questItems.append(item)
        initializeJourneyDayProgress(journeyId: journeyId)
        saveJourneyData()
    }

    func updateJourneyQuestStatus(journeyId: String, questItemId: String, date: Date, status: JourneyQuestStatus) {
        guard let jIdx = journeys.firstIndex(where: { $0.id == journeyId }) else { return }
        let cal = Calendar.current
        if let dpIdx = journeys[jIdx].dayProgress.firstIndex(where: { cal.isDate($0.date, inSameDayAs: date) }) {
            journeys[jIdx].dayProgress[dpIdx].questStatuses[questItemId] = status
        }
        if status == .completed || status == .verified {
            let todayProgress = journeys[jIdx].todayProgress
            if let tp = todayProgress, tp.completedCount == tp.totalCount {
                journeys[jIdx].streakDays += 1
            }
        }
        checkJourneyCompletion(journeyId: journeyId)
        saveJourneyData()
    }

    func completeJourneyQuestNonVerified(journeyId: String, questItemId: String, quest: Quest) {
        updateJourneyQuestStatus(journeyId: journeyId, questItemId: questItemId, date: Date(), status: .verified)

        let streakMult = LevelSystem.streakMultiplier(for: profile.currentStreak)
        let openXPCap = max(25, quest.xpReward / 3)
        let openGoldCap = max(5, quest.goldReward / 4)
        let rawJourneyXP = Int(Double(openXPCap) * streakMult)
        let finalXP = awardXPWithCap(rawJourneyXP)
        let finalGold = Int(Double(openGoldCap) * streakMult)

        trackCampaignXP(questId: quest.id, xp: finalXP)

        profile.totalScore += finalXP
        profile.gold += finalGold

        let reward = RewardEvent(
            id: UUID().uuidString,
            questTitle: "\(quest.title) (Non-Verified)",
            xpEarned: finalXP,
            goldEarned: finalGold,
            diamondsEarned: 0,
            streakBonus: streakMult > 1.0,
            streakMultiplier: streakMult,
            newBadge: nil,
            createdAt: Date()
        )
        pendingRewards.append(reward)
        completedHistory.insert(reward, at: 0)
        showRewardOverlay = true

        questCompletionCounts[quest.id, default: 0] += 1
        recordDailyCompletion()
        checkLevelUp()
        checkAchievements()
        saveState()
    }

    func isQuestInActiveJourney(_ questId: String, on date: Date) -> String? {
        let cal = Calendar.current
        for journey in activeJourneys {
            for item in journey.questItems where item.questId == questId {
                if journey.isQuestScheduledOnDate(item.id, date: date) {
                    if let dp = journey.dayProgress.first(where: { cal.isDate($0.date, inSameDayAs: date) }),
                       let status = dp.questStatuses[item.id],
                       status != .notStarted {
                        return journey.id
                    }
                }
            }
        }
        return nil
    }

    func canAddQuestToJourney(_ questId: String, on date: Date, excludingJourneyId: String? = nil) -> Bool {
        for journey in activeJourneys {
            guard journey.id != excludingJourneyId else { continue }
            for item in journey.questItems where item.questId == questId {
                if journey.isQuestScheduledOnDate(item.id, date: date) {
                    return false
                }
            }
        }
        return true
    }

    private func checkJourneyCompletion(journeyId: String) {
        guard let idx = journeys.firstIndex(where: { $0.id == journeyId }) else { return }
        let journey = journeys[idx]
        let allDone = journey.dayProgress.allSatisfy { $0.completionPercent >= 1.0 }
        let cal = Calendar.current
        let today = cal.startOfDay(for: Date())
        let end = cal.startOfDay(for: journey.endDate)
        let pastEnd = today >= end
        if allDone {
            journeys[idx].status = .completed
            awardCampaignCompletionBonus(journeyIndex: idx)
        } else if pastEnd && !allDone {
            // Campaign ended without full completion — no bonus
        }
    }

    private func awardCampaignCompletionBonus(journeyIndex idx: Int) {
        guard !journeys[idx].completionBonusAwarded else { return }
        journeys[idx].completionBonusAwarded = true
        let completionXP = journeys[idx].completionBonusXP
        let cappedCompletionXP = awardXPWithCap(completionXP)
        profile.totalScore += cappedCompletionXP

        if journeys[idx].isCompletedEarly && !journeys[idx].earlyBonusAwarded {
            journeys[idx].earlyBonusAwarded = true
            let earlyXP = journeys[idx].earlyCompletionBonusXP
            let cappedEarlyXP = awardXPWithCap(earlyXP)
            profile.totalScore += cappedEarlyXP
        }

        let totalBonus = cappedCompletionXP + (journeys[idx].earlyBonusAwarded ? awardXPWithCap(journeys[idx].earlyCompletionBonusXP) : 0)
        if totalBonus > 0 {
            let reward = RewardEvent(
                id: UUID().uuidString,
                questTitle: "\(journeys[idx].name) Campaign Complete",
                xpEarned: totalBonus,
                goldEarned: 0,
                diamondsEarned: 0,
                streakBonus: false,
                streakMultiplier: 1.0,
                newBadge: "Campaign Complete",
                createdAt: Date()
            )
            pendingRewards.append(reward)
            completedHistory.insert(reward, at: 0)
            showRewardOverlay = true
            checkLevelUp()
            saveState()
        }
        saveJourneyData()
    }

    func endJourneyEarly(journeyId: String) {
        guard let idx = journeys.firstIndex(where: { $0.id == journeyId }) else { return }
        journeys[idx].status = .cancelled
        if journeys[idx].calendarSyncEnabled {
            calendarService.deleteEvents(identifiers: Array(journeys[idx].calendarEventIds.values))
        }
        saveJourneyData()
    }

    func toggleJourneyCalendarSync(journeyId: String, enabled: Bool) {
        guard let idx = journeys.firstIndex(where: { $0.id == journeyId }) else { return }
        journeys[idx].calendarSyncEnabled = enabled
        if !enabled {
            calendarService.deleteEvents(identifiers: Array(journeys[idx].calendarEventIds.values))
            journeys[idx].calendarEventIds = [:]
        } else {
            Task {
                let granted = await calendarService.requestAccess()
                if granted {
                    let eventIds = calendarService.createJourneyEvents(
                        journey: journeys[idx],
                        quests: allQuests,
                        alertOffset: journeys[idx].calendarAlert.seconds,
                        calendar: calendarService.sideQuestCalendar()
                    )
                    journeys[idx].calendarEventIds = eventIds
                }
            }
        }
        saveJourneyData()
    }

    func publishJourneyAsTemplate(journeyId: String, title: String, description: String, difficulty: QuestDifficulty) {
        guard let journey = journeys.first(where: { $0.id == journeyId }) else { return }
        let template = JourneyTemplate(
            id: UUID().uuidString,
            authorUsername: profile.username,
            authorAvatarName: profile.avatarName,
            title: title,
            description: description,
            difficulty: difficulty,
            defaultDurationDays: journey.totalDays,
            questItems: journey.questItems,
            timesAreRecommended: true,
            joinCount: 0,
            rating: 0,
            createdAt: Date()
        )
        journeyTemplates.append(template)
        if let idx = journeys.firstIndex(where: { $0.id == journeyId }) {
            journeys[idx].visibility = .publicTemplate
            journeys[idx].templateId = template.id
        }
        saveJourneyData()
    }

    func joinJourneyTemplate(_ template: JourneyTemplate, startDate: Date, calendarSync: Bool, calendarAlert: CalendarAlertOption) {
        let cal = Calendar.current
        let endDate = cal.date(byAdding: .day, value: template.defaultDurationDays - 1, to: startDate) ?? startDate
        let journey = createJourney(
            name: template.title,
            durationType: template.defaultDurationDays == 1 ? .oneDay : (template.defaultDurationDays == 7 ? .sevenDays : .custom),
            startDate: startDate,
            endDate: endDate,
            mode: .solo,
            visibility: .privateJourney,
            questItems: template.questItems,
            calendarSync: calendarSync,
            calendarAlert: calendarAlert,
            invitedFriendIds: [],
            difficulty: template.difficulty
        )
        if let idx = journeys.firstIndex(where: { $0.id == journey.id }) {
            journeys[idx].templateId = template.id
        }
        if let tIdx = journeyTemplates.firstIndex(where: { $0.id == template.id }) {
            journeyTemplates[tIdx].joinCount += 1
        }
        saveJourneyData()
    }

    func nudgeFriend(journeyId: String, friendId: String) {
        guard let friend = friends.first(where: { $0.id == friendId }) else { return }
        let n = AppNotification(
            id: UUID().uuidString,
            type: .nudge,
            title: "Nudge Sent",
            message: "You nudged \(friend.username) to complete today's journey quests.",
            createdAt: Date(),
            isRead: false,
            deepLinkId: nil
        )
        notifications.insert(n, at: 0)
    }

    func renameJourney(journeyId: String, newName: String) {
        guard let idx = journeys.firstIndex(where: { $0.id == journeyId }) else { return }
        journeys[idx].name = newName
        saveJourneyData()
    }

    private func saveJourneyData() {
        PersistenceService.saveJourneys(journeys)
        PersistenceService.saveJourneyTemplates(journeyTemplates)
        syncJourneysToBackend()
    }

    private func syncJourneysToBackend() {
    }

    private func loadJourneyData() {
        let saved = PersistenceService.loadJourneys()
        if !saved.isEmpty { journeys = saved }
        let templates = PersistenceService.loadJourneyTemplates()
        if !templates.isEmpty { journeyTemplates = templates }
    }

    // MARK: - Custom Quest Methods

    func createCustomQuest(
        title: String,
        description: String,
        path: QuestPath,
        difficulty: QuestDifficulty,
        repeatability: CustomQuestRepeatability,
        suggestedTime: String?,
        notes: String?
    ) -> CustomQuest {
        let quest = CustomQuest(
            id: UUID().uuidString,
            title: title,
            description: description,
            path: path,
            difficulty: difficulty,
            repeatability: repeatability,
            suggestedTime: suggestedTime?.isEmpty == true ? nil : suggestedTime,
            notes: notes?.isEmpty == true ? nil : notes,
            createdAt: Date(),
            completionCount: 0,
            submissionStatus: .draft,
            rejectionReason: nil,
            submittedAt: nil,
            publishedQuestId: nil,
            authorUserId: profile.id,
            authorUsername: profile.username
        )
        customQuests.insert(quest, at: 0)
        saveCustomQuestData()
        return quest
    }

    func updateCustomQuest(_ questId: String, title: String, description: String, path: QuestPath, difficulty: QuestDifficulty, repeatability: CustomQuestRepeatability, suggestedTime: String?, notes: String?) {
        guard let idx = customQuests.firstIndex(where: { $0.id == questId }), customQuests[idx].canEdit else { return }
        customQuests[idx].title = title
        customQuests[idx].description = description
        customQuests[idx].path = path
        customQuests[idx].difficulty = difficulty
        customQuests[idx].repeatability = repeatability
        customQuests[idx].suggestedTime = suggestedTime?.isEmpty == true ? nil : suggestedTime
        customQuests[idx].notes = notes?.isEmpty == true ? nil : notes
        if customQuests[idx].submissionStatus == .rejected {
            customQuests[idx].submissionStatus = .draft
            customQuests[idx].rejectionReason = nil
        }
        saveCustomQuestData()
    }

    func deleteCustomQuest(_ questId: String) {
        customQuests.removeAll { $0.id == questId }
        saveCustomQuestData()
    }

    func completeCustomQuest(_ customQuest: CustomQuest) {
        let quest = customQuest.toQuest()
        let instance = QuestInstance(
            id: UUID().uuidString,
            quest: quest,
            state: .verified,
            mode: .solo,
            startedAt: Date(),
            submittedAt: Date(),
            verifiedAt: Date(),
            groupId: nil
        )
        openPlayHistory.insert(instance, at: 0)

        if let idx = customQuests.firstIndex(where: { $0.id == customQuest.id }) {
            customQuests[idx].completionCount += 1
        }

        let streakMult = LevelSystem.streakMultiplier(for: profile.currentStreak)
        let rawCustomXP = Int(Double(quest.xpReward) * streakMult)
        let xp = awardXPWithCap(rawCustomXP)
        let gold = Int(Double(quest.goldReward) * streakMult)

        profile.totalScore += xp
        profile.gold += gold

        let reward = RewardEvent(
            id: UUID().uuidString,
            questTitle: "\(quest.title) (Custom)",
            xpEarned: xp,
            goldEarned: gold,
            diamondsEarned: 0,
            streakBonus: streakMult > 1.0,
            streakMultiplier: streakMult,
            newBadge: nil,
            createdAt: Date()
        )
        completedHistory.insert(reward, at: 0)
        recordDailyCompletion()
        checkLevelUp()
        checkAchievements()
        saveState()
        saveCustomQuestData()
    }

    func submitCustomQuestForReview(_ questId: String) {
        guard let idx = customQuests.firstIndex(where: { $0.id == questId }), customQuests[idx].canSubmit else { return }
        customQuests[idx].submissionStatus = .pending
        customQuests[idx].submittedAt = Date()
        communitySubmissions.append(customQuests[idx])
        let submitted = customQuests[idx]
        saveCustomQuestData()

        let n = AppNotification(
            id: UUID().uuidString,
            type: .featuredQuest,
            title: "Quest Submitted",
            message: "Your quest \"\(customQuests[idx].title)\" has been submitted for community review.",
            createdAt: Date(),
            isRead: false,
            deepLinkId: nil
        )
        notifications.insert(n, at: 0)
    }

    func approveSubmittedQuest(_ questId: String) {
        guard let subIdx = communitySubmissions.firstIndex(where: { $0.id == questId }) else { return }
        communitySubmissions[subIdx].submissionStatus = .approved

        let custom = communitySubmissions[subIdx]
        let publishedId = "community_\(custom.id)"
        communitySubmissions[subIdx].publishedQuestId = publishedId

        let globalQuest = Quest(
            id: publishedId,
            title: custom.title,
            description: custom.description,
            path: custom.path,
            difficulty: custom.difficulty,
            type: .open,
            evidenceType: nil,
            xpReward: custom.toQuest().xpReward,
            goldReward: custom.toQuest().goldReward,
            diamondReward: 0,
            milestoneIds: [],
            minCompletionMinutes: 0,
            isRepeatable: custom.repeatability != .oneTime,
            requiresUniqueLocation: false,
            isFeatured: false,
            featuredExpiresAt: nil,
            completionCount: 0,
            authorUsername: custom.authorUsername
        )
        allQuests.append(globalQuest)

        if let ownIdx = customQuests.firstIndex(where: { $0.id == questId }) {
            customQuests[ownIdx].submissionStatus = .approved
            customQuests[ownIdx].publishedQuestId = publishedId
        }

        let n = AppNotification(
            id: UUID().uuidString,
            type: .featuredQuest,
            title: "Quest Published!",
            message: "Your quest \"\(custom.title)\" was approved and is now in the global Quest Library!",
            createdAt: Date(),
            isRead: false,
            deepLinkId: nil
        )
        notifications.insert(n, at: 0)
        saveCustomQuestData()
    }

    func rejectSubmittedQuest(_ questId: String, reason: SubmissionRejectionReason) {
        guard let subIdx = communitySubmissions.firstIndex(where: { $0.id == questId }) else { return }
        communitySubmissions[subIdx].submissionStatus = .rejected
        communitySubmissions[subIdx].rejectionReason = reason

        if let ownIdx = customQuests.firstIndex(where: { $0.id == questId }) {
            customQuests[ownIdx].submissionStatus = .rejected
            customQuests[ownIdx].rejectionReason = reason
        }

        let n = AppNotification(
            id: UUID().uuidString,
            type: .questRejected,
            title: "Quest Not Approved",
            message: "Your quest \"\(communitySubmissions[subIdx].title)\" was not approved. Reason: \(reason.rawValue).",
            createdAt: Date(),
            isRead: false,
            deepLinkId: nil
        )
        notifications.insert(n, at: 0)
        saveCustomQuestData()
    }

    var pendingSubmissions: [CustomQuest] {
        communitySubmissions.filter { $0.submissionStatus == .pending }
    }

    func customQuestAsQuest(_ customQuest: CustomQuest) -> Quest {
        customQuest.toQuest()
    }

    private func saveCustomQuestData() {
        PersistenceService.saveCustomQuests(customQuests)
        PersistenceService.saveCommunityQuests(communitySubmissions)
        syncCustomQuestsToAllQuests()
    }

    private func loadCustomQuestData() {
        let saved = PersistenceService.loadCustomQuests()
        if !saved.isEmpty { customQuests = saved }
        let community = PersistenceService.loadCommunityQuests()
        if !community.isEmpty { communitySubmissions = community }
        syncCustomQuestsToAllQuests()
    }

    private func syncCustomQuestsToAllQuests() {
        allQuests.removeAll { $0.id.hasPrefix("custom_") }
        allQuests.append(contentsOf: customQuests.map { $0.toQuest() })
    }

    // MARK: - Story Methods

    func loadStoryData() {
        let saved = PersistenceService.loadStoryProgress()
        if !saved.isEmpty { storyEngine.storyProgressMap = saved }
        let inv = PersistenceService.loadGlobalInventory()
        if !inv.isEmpty { storyEngine.globalInventory = inv }
    }

    func saveStoryData() {
        PersistenceService.saveStoryProgress(storyEngine.storyProgressMap)
        PersistenceService.saveGlobalInventory(storyEngine.globalInventory)
        syncStoryDataToBackend()
    }

    private func syncStoryDataToBackend() {
    }

    func startStoryForJourney(_ journeyId: String, templateId: String) {
        let _ = storyEngine.startStory(templateId: templateId, journeyId: journeyId)
        saveStoryData()
    }

    func triggerStoryEventAfterDailyCompletion(journeyId: String) {
        guard let progress = storyEngine.progressForJourney(journeyId),
              progress.isEnabled, !progress.isComplete else { return }
        storyEngine.queueStoryEvent(progressKey: journeyId)
        showStoryEvent = true
        if notificationsEnabled {
            NotificationService.shared.fireStoryEvent()
        }
    }

    func onStoryChoiceMade() {
        saveStoryData()
    }

    private func generateSampleTemplates() {
        guard journeyTemplates.isEmpty else { return }
        journeyTemplates = [
            JourneyTemplate(
                id: "t1",
                authorUsername: "IronWill",
                authorAvatarName: "figure.martial.arts",
                title: "7-Day Warrior Bootcamp",
                description: "Push-ups, runs, and cold showers every day for a week. Build discipline and physical toughness.",
                difficulty: .hard,
                defaultDurationDays: 7,
                questItems: [
                    JourneyQuestItem(id: "ti1", questId: "w6", frequency: .daily, specificDays: [], scheduledHour: 7, scheduledMinute: 0, isAnytime: false, questMode: .solo),
                    JourneyQuestItem(id: "ti2", questId: "w2", frequency: .specificDays, specificDays: [.monday, .wednesday, .friday], scheduledHour: 17, scheduledMinute: 0, isAnytime: false, questMode: .solo),
                    JourneyQuestItem(id: "ti3", questId: "w3", frequency: .daily, specificDays: [], scheduledHour: nil, scheduledMinute: nil, isAnytime: true, questMode: .solo),
                ],
                timesAreRecommended: true,
                joinCount: 47,
                rating: 4.6,
                createdAt: Date().addingTimeInterval(-604800)
            ),
            JourneyTemplate(
                id: "t2",
                authorUsername: "ZenMaster",
                authorAvatarName: "figure.mind.and.body",
                title: "Mindful Morning Routine",
                description: "Start each day with meditation, journaling, and a focus session. 7 days to build the habit.",
                difficulty: .easy,
                defaultDurationDays: 7,
                questItems: [
                    JourneyQuestItem(id: "ti4", questId: "m3", frequency: .daily, specificDays: [], scheduledHour: 6, scheduledMinute: 30, isAnytime: false, questMode: .solo),
                    JourneyQuestItem(id: "ti5", questId: "m4", frequency: .daily, specificDays: [], scheduledHour: 7, scheduledMinute: 0, isAnytime: false, questMode: .solo),
                    JourneyQuestItem(id: "ti6", questId: "m1", frequency: .daily, specificDays: [], scheduledHour: 8, scheduledMinute: 0, isAnytime: false, questMode: .solo),
                ],
                timesAreRecommended: true,
                joinCount: 123,
                rating: 4.8,
                createdAt: Date().addingTimeInterval(-1209600)
            ),
            JourneyTemplate(
                id: "t3",
                authorUsername: "TrailBlazer",
                authorAvatarName: "figure.hiking",
                title: "Explorer Challenge",
                description: "Walk, hike, and photograph your way through the week. Visit new places every day.",
                difficulty: .medium,
                defaultDurationDays: 7,
                questItems: [
                    JourneyQuestItem(id: "ti7", questId: "e1", frequency: .daily, specificDays: [], scheduledHour: nil, scheduledMinute: nil, isAnytime: true, questMode: .solo),
                    JourneyQuestItem(id: "ti8", questId: "e2", frequency: .specificDays, specificDays: [.wednesday, .saturday], scheduledHour: 10, scheduledMinute: 0, isAnytime: false, questMode: .solo),
                    JourneyQuestItem(id: "ti9", questId: "t1", frequency: .daily, specificDays: [], scheduledHour: 18, scheduledMinute: 0, isAnytime: false, questMode: .solo),
                ],
                timesAreRecommended: true,
                joinCount: 68,
                rating: 4.5,
                createdAt: Date().addingTimeInterval(-864000)
            ),
        ]
    }
}

nonisolated enum DeepLinkDestination: Sendable {
    case questLog
    case modHub
    case shop
}
