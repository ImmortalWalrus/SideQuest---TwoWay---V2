import Foundation

struct PersistedExternalDiscoveryState: Codable {
    let snapshot: ExternalLocationDiscoverySnapshot
    let intent: ExternalDiscoveryIntent
    let searchLocation: ExternalEventSearchLocation
    let savedAt: Date
}

enum PersistenceService {
    private static let encoder = JSONEncoder()
    private static let decoder = JSONDecoder()

    private enum Keys {
        static let profile = "persisted_profile"
        static let completedHistory = "persisted_completedHistory"
        static let savedQuestIds = "persisted_savedQuestIds"
        static let brainScores = "persisted_brainScores"
        static let dailyCompletions = "persisted_dailyCompletions"
        static let lastStreakDate = "persisted_lastStreakDate"
        static let earnedBadges = "persisted_earnedBadges"
        static let questCompletionCounts = "persisted_questCompletionCounts"
        static let journeys = "persisted_journeys"
        static let journeyTemplates = "persisted_journeyTemplates"
        static let customQuests = "persisted_customQuests"
        static let communityQuests = "persisted_communityQuests"
        static let dailyXPEarned = "persisted_dailyXPEarned"
        static let storyProgress = "persisted_storyProgress"
        static let globalInventory = "persisted_globalInventory"
        static let visitedPOIs = "persisted_visitedPOIs"
        static let savedGym = "persisted_savedGym"
        static let activeInstances = "persisted_activeInstances"
        static let openPlayHistory = "persisted_openPlayHistory"
        static let onboardingData = "persisted_onboardingData"
        static let externalDiscoveryState = "persisted_externalDiscoveryState"
    }

    static func saveProfile(_ profile: UserProfile) {
        if let data = try? encoder.encode(profile) {
            UserDefaults.standard.set(data, forKey: Keys.profile)
        }
    }

    static func loadProfile() -> UserProfile? {
        guard let data = UserDefaults.standard.data(forKey: Keys.profile) else { return nil }
        return try? decoder.decode(UserProfile.self, from: data)
    }

    static func saveCompletedHistory(_ history: [RewardEvent]) {
        if let data = try? encoder.encode(history) {
            UserDefaults.standard.set(data, forKey: Keys.completedHistory)
        }
    }

    static func loadCompletedHistory() -> [RewardEvent]? {
        guard let data = UserDefaults.standard.data(forKey: Keys.completedHistory) else { return nil }
        return try? decoder.decode([RewardEvent].self, from: data)
    }

    static func saveSavedQuestIds(_ ids: [String]) {
        UserDefaults.standard.set(ids, forKey: Keys.savedQuestIds)
    }

    static func loadSavedQuestIds() -> [String] {
        UserDefaults.standard.stringArray(forKey: Keys.savedQuestIds) ?? []
    }

    static func saveBrainScores(_ scores: [String: Int]) {
        if let data = try? encoder.encode(scores) {
            UserDefaults.standard.set(data, forKey: Keys.brainScores)
        }
    }

    static func loadBrainScores() -> [String: Int] {
        guard let data = UserDefaults.standard.data(forKey: Keys.brainScores) else { return [:] }
        return (try? decoder.decode([String: Int].self, from: data)) ?? [:]
    }

    static func saveDailyCompletions(_ completions: [Date: Int]) {
        let stringKeyed = Dictionary(uniqueKeysWithValues: completions.map { (key, value) in
            (String(key.timeIntervalSince1970), value)
        })
        if let data = try? encoder.encode(stringKeyed) {
            UserDefaults.standard.set(data, forKey: Keys.dailyCompletions)
        }
    }

    static func loadDailyCompletions() -> [Date: Int] {
        guard let data = UserDefaults.standard.data(forKey: Keys.dailyCompletions),
              let stringKeyed = try? decoder.decode([String: Int].self, from: data) else { return [:] }
        return Dictionary(uniqueKeysWithValues: stringKeyed.compactMap { (key, value) in
            guard let interval = Double(key) else { return nil }
            return (Date(timeIntervalSince1970: interval), value)
        })
    }

    static func saveLastStreakDate(_ date: Date?) {
        UserDefaults.standard.set(date?.timeIntervalSince1970, forKey: Keys.lastStreakDate)
    }

    static func loadLastStreakDate() -> Date? {
        let interval = UserDefaults.standard.double(forKey: Keys.lastStreakDate)
        return interval > 0 ? Date(timeIntervalSince1970: interval) : nil
    }

    static func saveEarnedBadges(_ badges: [String]) {
        UserDefaults.standard.set(badges, forKey: Keys.earnedBadges)
    }

    static func loadEarnedBadges() -> [String] {
        UserDefaults.standard.stringArray(forKey: Keys.earnedBadges) ?? []
    }

    static func saveQuestCompletionCounts(_ counts: [String: Int]) {
        if let data = try? encoder.encode(counts) {
            UserDefaults.standard.set(data, forKey: Keys.questCompletionCounts)
        }
    }

    static func loadQuestCompletionCounts() -> [String: Int] {
        guard let data = UserDefaults.standard.data(forKey: Keys.questCompletionCounts) else { return [:] }
        return (try? decoder.decode([String: Int].self, from: data)) ?? [:]
    }

    static func saveJourneys(_ journeys: [Journey]) {
        if let data = try? encoder.encode(journeys) {
            UserDefaults.standard.set(data, forKey: Keys.journeys)
        }
    }

    static func loadJourneys() -> [Journey] {
        guard let data = UserDefaults.standard.data(forKey: Keys.journeys) else { return [] }
        return (try? decoder.decode([Journey].self, from: data)) ?? []
    }

    static func saveJourneyTemplates(_ templates: [JourneyTemplate]) {
        if let data = try? encoder.encode(templates) {
            UserDefaults.standard.set(data, forKey: Keys.journeyTemplates)
        }
    }

    static func loadJourneyTemplates() -> [JourneyTemplate] {
        guard let data = UserDefaults.standard.data(forKey: Keys.journeyTemplates) else { return [] }
        return (try? decoder.decode([JourneyTemplate].self, from: data)) ?? []
    }

    static func saveCustomQuests(_ quests: [CustomQuest]) {
        if let data = try? encoder.encode(quests) {
            UserDefaults.standard.set(data, forKey: Keys.customQuests)
        }
    }

    static func loadCustomQuests() -> [CustomQuest] {
        guard let data = UserDefaults.standard.data(forKey: Keys.customQuests) else { return [] }
        return (try? decoder.decode([CustomQuest].self, from: data)) ?? []
    }

    static func saveCommunityQuests(_ quests: [CustomQuest]) {
        if let data = try? encoder.encode(quests) {
            UserDefaults.standard.set(data, forKey: Keys.communityQuests)
        }
    }

    static func loadCommunityQuests() -> [CustomQuest] {
        guard let data = UserDefaults.standard.data(forKey: Keys.communityQuests) else { return [] }
        return (try? decoder.decode([CustomQuest].self, from: data)) ?? []
    }

    static func saveDailyXPEarned(_ earned: [Date: Int]) {
        let stringKeyed = Dictionary(uniqueKeysWithValues: earned.map { (key, value) in
            (String(key.timeIntervalSince1970), value)
        })
        if let data = try? encoder.encode(stringKeyed) {
            UserDefaults.standard.set(data, forKey: Keys.dailyXPEarned)
        }
    }

    static func loadDailyXPEarned() -> [Date: Int] {
        guard let data = UserDefaults.standard.data(forKey: Keys.dailyXPEarned),
              let stringKeyed = try? decoder.decode([String: Int].self, from: data) else { return [:] }
        return Dictionary(uniqueKeysWithValues: stringKeyed.compactMap { (key, value) in
            guard let interval = Double(key) else { return nil }
            return (Date(timeIntervalSince1970: interval), value)
        })
    }

    static func saveStoryProgress(_ progress: [String: StoryProgress]) {
        if let data = try? encoder.encode(progress) {
            UserDefaults.standard.set(data, forKey: Keys.storyProgress)
        }
    }

    static func loadStoryProgress() -> [String: StoryProgress] {
        guard let data = UserDefaults.standard.data(forKey: Keys.storyProgress) else { return [:] }
        return (try? decoder.decode([String: StoryProgress].self, from: data)) ?? [:]
    }

    static func saveGlobalInventory(_ inventory: [InventoryItem]) {
        if let data = try? encoder.encode(inventory) {
            UserDefaults.standard.set(data, forKey: Keys.globalInventory)
        }
    }

    static func loadGlobalInventory() -> [InventoryItem] {
        guard let data = UserDefaults.standard.data(forKey: Keys.globalInventory) else { return [] }
        return (try? decoder.decode([InventoryItem].self, from: data)) ?? []
    }

    static func saveVisitedPOIs(_ pois: [VisitedPOI]) {
        if let data = try? encoder.encode(pois) {
            UserDefaults.standard.set(data, forKey: Keys.visitedPOIs)
        }
    }

    static func loadVisitedPOIs() -> [VisitedPOI] {
        guard let data = UserDefaults.standard.data(forKey: Keys.visitedPOIs) else { return [] }
        return (try? decoder.decode([VisitedPOI].self, from: data)) ?? []
    }

    static func saveSavedGym(_ gym: SavedGym?) {
        if let gym, let data = try? encoder.encode(gym) {
            UserDefaults.standard.set(data, forKey: Keys.savedGym)
        } else {
            UserDefaults.standard.removeObject(forKey: Keys.savedGym)
        }
    }

    static func loadSavedGym() -> SavedGym? {
        guard let data = UserDefaults.standard.data(forKey: Keys.savedGym) else { return nil }
        return try? decoder.decode(SavedGym.self, from: data)
    }

    static func saveActiveInstances(_ instances: [QuestInstance]) {
        if let data = try? encoder.encode(instances) {
            UserDefaults.standard.set(data, forKey: Keys.activeInstances)
        }
    }

    static func loadActiveInstances() -> [QuestInstance]? {
        guard let data = UserDefaults.standard.data(forKey: Keys.activeInstances) else { return nil }
        return try? decoder.decode([QuestInstance].self, from: data)
    }

    static func saveOpenPlayHistory(_ history: [QuestInstance]) {
        let limited = Array(history.prefix(50))
        if let data = try? encoder.encode(limited) {
            UserDefaults.standard.set(data, forKey: Keys.openPlayHistory)
        }
    }

    static func loadOpenPlayHistory() -> [QuestInstance]? {
        guard let data = UserDefaults.standard.data(forKey: Keys.openPlayHistory) else { return nil }
        return try? decoder.decode([QuestInstance].self, from: data)
    }

    static func saveOnboardingData(_ data: OnboardingData) {
        if let encoded = try? encoder.encode(data) {
            UserDefaults.standard.set(encoded, forKey: Keys.onboardingData)
        }
    }

    static func loadOnboardingData() -> OnboardingData? {
        guard let data = UserDefaults.standard.data(forKey: Keys.onboardingData) else { return nil }
        return try? decoder.decode(OnboardingData.self, from: data)
    }

    static func saveExternalDiscoveryState(
        snapshot: ExternalLocationDiscoverySnapshot,
        intent: ExternalDiscoveryIntent,
        searchLocation: ExternalEventSearchLocation
    ) {
        guard let url = externalDiscoveryStateURL(for: intent) else { return }
        let payload = PersistedExternalDiscoveryState(
            snapshot: compactExternalDiscoverySnapshot(snapshot),
            intent: intent,
            searchLocation: searchLocation,
            savedAt: Date()
        )
        writeExternalDiscoveryState(payload, to: url)
    }

    static func loadExternalDiscoveryState(
        intent: ExternalDiscoveryIntent
    ) -> PersistedExternalDiscoveryState? {
        if let url = externalDiscoveryStateURL(for: intent),
           let data = try? Data(contentsOf: url, options: [.mappedIfSafe]),
           let payload = try? decoder.decode(PersistedExternalDiscoveryState.self, from: data) {
            let compactedPayload = compactExternalDiscoveryState(payload)
            if externalDiscoveryStateNeedsCompaction(payload) {
                writeExternalDiscoveryState(compactedPayload, to: url)
            }
            return compactedPayload
        }

        return migrateLegacyExternalDiscoveryState(intent: intent)
    }

    static func clearExternalDiscoveryState() {
        ExternalDiscoveryIntent.allCases.forEach { intent in
            guard let url = externalDiscoveryStateURL(for: intent) else { return }
            try? FileManager.default.removeItem(at: url)
        }
    }

    static func clearAll() {
        let keys = [Keys.profile, Keys.completedHistory, Keys.savedQuestIds,
                    Keys.brainScores, Keys.dailyCompletions, Keys.lastStreakDate,
                    Keys.earnedBadges, Keys.questCompletionCounts,
                    Keys.journeys, Keys.journeyTemplates, Keys.customQuests,
                    Keys.communityQuests, Keys.dailyXPEarned,
                    Keys.storyProgress, Keys.globalInventory,
                    Keys.visitedPOIs, Keys.savedGym,
                    Keys.activeInstances, Keys.openPlayHistory]
        keys.forEach { UserDefaults.standard.removeObject(forKey: $0) }
        UserDefaults.standard.removeObject(forKey: Keys.onboardingData)
        clearExternalDiscoveryState()
    }

    private static func externalDiscoveryStateURL(
        for intent: ExternalDiscoveryIntent
    ) -> URL? {
        guard let applicationSupportURL = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else {
            return nil
        }
        let directoryURL = applicationSupportURL.appendingPathComponent("sidequest_persistence", isDirectory: true)
        try? FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true, attributes: nil)
        return directoryURL.appendingPathComponent("external_discovery_\(intent.rawValue).json")
    }

    private static func writeExternalDiscoveryState(
        _ payload: PersistedExternalDiscoveryState,
        to url: URL
    ) {
        guard let data = try? encoder.encode(payload) else { return }
        try? data.write(to: url, options: .atomic)
    }

    private static func compactExternalDiscoveryState(
        _ payload: PersistedExternalDiscoveryState
    ) -> PersistedExternalDiscoveryState {
        PersistedExternalDiscoveryState(
            snapshot: compactExternalDiscoverySnapshot(payload.snapshot),
            intent: payload.intent,
            searchLocation: payload.searchLocation,
            savedAt: payload.savedAt
        )
    }

    private static func externalDiscoveryStateNeedsCompaction(
        _ payload: PersistedExternalDiscoveryState
    ) -> Bool {
        let eventSnapshot = payload.snapshot.eventSnapshot
        if !eventSnapshot.mergedEvents.isEmpty || !eventSnapshot.dedupeGroups.isEmpty {
            return true
        }
        if eventSnapshot.sourceResults.contains(where: { !$0.endpoints.isEmpty || $0.note != nil || !$0.events.isEmpty }) {
            return true
        }
        if let venueSnapshot = payload.snapshot.venueSnapshot,
           venueSnapshot.sourceResults.contains(where: { !$0.endpoints.isEmpty || $0.note != nil || !$0.venues.isEmpty }) {
            return true
        }
        return false
    }

    private static func compactExternalDiscoverySnapshot(
        _ snapshot: ExternalLocationDiscoverySnapshot
    ) -> ExternalLocationDiscoverySnapshot {
        ExternalLocationDiscoverySnapshot(
            fetchedAt: snapshot.fetchedAt,
            searchLocation: snapshot.searchLocation,
            appliedProfiles: snapshot.appliedProfiles,
            venueSnapshot: snapshot.venueSnapshot.map(compactVenueDiscoverySnapshot),
            eventSnapshot: compactEventIngestionSnapshot(snapshot.eventSnapshot),
            mergedEvents: snapshot.mergedEvents,
            notes: snapshot.notes
        )
    }

    private static func compactEventIngestionSnapshot(
        _ snapshot: ExternalEventIngestionSnapshot
    ) -> ExternalEventIngestionSnapshot {
        let compactSourceResults = snapshot.sourceResults.map { result in
            ExternalEventSourceResult(
                source: result.source,
                usedCache: result.usedCache,
                fetchedAt: result.fetchedAt,
                endpoints: [],
                note: nil,
                nextCursor: result.nextCursor,
                events: []
            )
        }
        return ExternalEventIngestionSnapshot(
            fetchedAt: snapshot.fetchedAt,
            query: snapshot.query,
            sourceResults: compactSourceResults,
            mergedEvents: [],
            dedupeGroups: []
        )
    }

    private static func compactVenueDiscoverySnapshot(
        _ snapshot: ExternalVenueDiscoverySnapshot
    ) -> ExternalVenueDiscoverySnapshot {
        let compactSourceResults = snapshot.sourceResults.map { result in
            ExternalVenueSourceResult(
                source: result.source,
                fetchedAt: result.fetchedAt,
                endpoints: [],
                note: nil,
                venues: []
            )
        }
        return ExternalVenueDiscoverySnapshot(
            fetchedAt: snapshot.fetchedAt,
            query: snapshot.query,
            sourceResults: compactSourceResults,
            venues: snapshot.venues
        )
    }

    private static func migrateLegacyExternalDiscoveryState(
        intent: ExternalDiscoveryIntent
    ) -> PersistedExternalDiscoveryState? {
        guard let data = UserDefaults.standard.data(forKey: Keys.externalDiscoveryState) else {
            return nil
        }

        struct LegacyPersistedExternalDiscoveryState: Codable {
            let snapshot: ExternalLocationDiscoverySnapshot
            let intent: ExternalDiscoveryIntent
        }

        guard let legacyPayload = try? decoder.decode(LegacyPersistedExternalDiscoveryState.self, from: data),
              legacyPayload.intent == intent else {
            return nil
        }

        let migrated = PersistedExternalDiscoveryState(
            snapshot: legacyPayload.snapshot,
            intent: legacyPayload.intent,
            searchLocation: legacyPayload.snapshot.searchLocation,
            savedAt: legacyPayload.snapshot.fetchedAt
        )
        saveExternalDiscoveryState(
            snapshot: migrated.snapshot,
            intent: migrated.intent,
            searchLocation: migrated.searchLocation
        )
        UserDefaults.standard.removeObject(forKey: Keys.externalDiscoveryState)
        return migrated
    }
}
