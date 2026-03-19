import Foundation

@Observable
final class APIService {
    static let shared = APIService()

    private(set) var isAvailable: Bool = false
    private(set) var lastSyncAt: Date?

    private init() {}

    func checkHealth() async {
        isAvailable = false
    }
}

nonisolated struct TRPCInput<T: Encodable>: Encodable, Sendable where T: Sendable {
    let json: T
}

nonisolated struct TRPCResponse<T: Decodable>: Decodable, Sendable where T: Sendable {
    let result: TRPCResult<T>
}

nonisolated struct TRPCResult<T: Decodable>: Decodable, Sendable where T: Sendable {
    let data: TRPCData<T>
}

nonisolated struct TRPCData<T: Decodable>: Decodable, Sendable where T: Sendable {
    let json: T
}

nonisolated enum APIError: Error, Sendable {
    case noBaseURL
    case serverError
    case decodingError
}

nonisolated struct APIQuestInput: Codable, Sendable {
    let id: String
    let type: String
    let path: String
    let difficulty: String
    let xpReward: Int
    let goldReward: Int
    let diamondReward: Int
    let minCompletionMinutes: Int
    let targetDistanceMiles: Double?
    let maxSpeedMph: Double
    let maxPauseMinutes: Int
    let isRepeatable: Bool
    let hasTimeWindow: Bool
    let isTrackingQuest: Bool
    let targetSteps: Int?
    let targetReps: Int?
    let targetHoldSeconds: Double?
    let targetFocusMinutes: Int?
}

nonisolated struct APITrackingSession: Codable, Sendable {
    let id: String
    let distanceMiles: Double
    let durationSeconds: Double
    let totalPauseSeconds: Double
    let maxRecordedSpeedMph: Double
    let speedViolationCount: Int
    let routePingCount: Int
    let gpsGapCount: Int
    let routeContinuityScore: Double
    let isLoopCompleted: Bool
    let loopClosureDistanceMeters: Double?
    let pedometerEstimatedDistanceMiles: Double
    let timeIntegrityVerified: Bool?
    let timeWindowVerified: Bool?
    let integrityFlags: [String]
    let startedAt: String?
    let endedAt: String?
}

nonisolated struct VerificationResult: Codable, Sendable {
    let verified: Bool
    let rejected: Bool
    let reason: String?
    let violations: [String]?
    let rewards: VerificationRewards?
}

nonisolated struct VerificationRewards: Codable, Sendable {
    let xp: Int
    let gold: Int
    let diamonds: Int
    let streakMultiplier: Double
}

nonisolated struct ProfileSyncResult: Codable, Sendable {
    let accepted: Bool
    let reason: String?
}

nonisolated struct LeaderboardSubmitResult: Codable, Sendable {
    let accepted: Bool
    let reason: String?
}

nonisolated struct APILeaderboardEntry: Codable, Sendable {
    let id: String
    let rank: Int
    let username: String
    let avatarName: String
    let callingCardName: String
    let totalScore: Int
    let verifiedCount: Int
    let masterCount: Int

    func toLocal() -> LeaderboardEntry {
        LeaderboardEntry(
            id: id,
            rank: rank,
            username: username,
            avatarName: avatarName,
            callingCardName: callingCardName,
            totalScore: totalScore,
            verifiedCount: verifiedCount,
            masterCount: masterCount
        )
    }
}

nonisolated struct APICommunityQuest: Codable, Sendable {
    let id: String
    let title: String
    let description: String
    let path: String
    let difficulty: String
    let repeatability: String?
    let suggestedTime: String?
    let notes: String?
    let publishedQuestId: String?
    let authorUserId: String?
    let authorUsername: String
    let status: String
    let completionCount: Int
}

nonisolated struct QuestSubmitResult: Codable, Sendable {
    let submitted: Bool
    let questId: String
}

nonisolated struct SimpleResult: Codable, Sendable {
    let success: Bool
}

nonisolated struct HealthResponse: Codable, Sendable {
    let status: String
    let timestamp: String
    let profileCount: Int
}

nonisolated struct PlaceVerificationAPIResult: Codable, Sendable {
    let verified: Bool
    let reason: String?
    let isNewPlace: Bool?
}

nonisolated struct APIVisitedPlace: Codable, Sendable {
    let id: String
    let placeName: String
    let placeType: String
    let latitude: Double
    let longitude: Double
    let visitedAt: String
    let questId: String
}

nonisolated struct PlaceNewCheckResult: Codable, Sendable {
    let isNew: Bool
}

nonisolated struct APIActivityFeedItem: Codable, Sendable {
    let id: String
    let username: String
    let avatarName: String
    let questTitle: String
    let path: String
    let isMaster: Bool
    let completedAt: String
}

nonisolated struct APIFriendRequest: Codable, Sendable {
    let id: String
    let fromUserId: String
    let fromUsername: String
    let fromAvatarName: String
    let fromCallingCardName: String
    let fromTotalScore: Int
    let fromVerifiedCount: Int
    let sentAt: String
}

nonisolated struct FriendRequestResult: Codable, Sendable {
    let success: Bool
    let requestId: String?
}

nonisolated struct AcceptFriendResult: Codable, Sendable {
    let success: Bool
}

nonisolated struct APIFriendEntry: Codable, Sendable {
    let friendId: String
    let username: String
    let avatarName: String
    let callingCardName: String
    let totalScore: Int
    let verifiedCount: Int
    let currentStreak: Int
    let warriorRank: Int
    let explorerRank: Int
    let mindRank: Int
    let addedAt: String
    let lastActiveAt: String
    let isOnline: Bool
}

nonisolated struct APIServerNotification: Codable, Sendable {
    let id: String
    let type: String
    let title: String
    let message: String
    let isRead: Bool
    let deepLinkId: String?
    let createdAt: String
}

nonisolated struct APIAchievementEntry: Codable, Sendable {
    let badgeId: String
    let unlockedAt: String
}

nonisolated struct APIServerProfile: Codable, Sendable {
    let userId: String
    let username: String
    let avatarName: String
    let callingCardName: String?
    let totalScore: Int
    let gold: Int
    let diamonds: Int
    let verifiedCount: Int
    let masterCount: Int
    let karma: Int?
    let currentStreak: Int
    let verifiedStreak: Int?
    let handshakeCount: Int?
    let referralCount: Int?
    let warriorRank: Int
    let explorerRank: Int
    let mindRank: Int
    let modSessionsCompleted: Int?
    let modAccuracy: Double?
    let strikes: Int?
    let screenshotStrikes: Int?
    let isSuspended: Bool?
    let ownedItems: [String]?
    let selectedSkills: [String]?
    let selectedInterests: [String]?
    let earnedBadges: [String]
}

nonisolated struct APIDailyXPResult: Codable, Sendable {
    let xpEarned: Int
    let date: String
}

nonisolated struct APIXPHistoryEntry: Codable, Sendable {
    let date: String
    let xpEarned: Int
}

nonisolated struct UnreadCountResult: Codable, Sendable {
    let count: Int
}

nonisolated struct AchievementSyncResult: Codable, Sendable {
    let synced: Bool
}

nonisolated struct AchievementUnlockResult: Codable, Sendable {
    let unlocked: Bool
}

nonisolated struct EmptyInput: Codable, Sendable {}

nonisolated struct UsernameCheckInput: Codable, Sendable {
    let username: String
}

nonisolated struct UsernameCheckResult: Codable, Sendable {
    let available: Bool
}

nonisolated struct APIPublicProfile: Codable, Sendable {
    let userId: String
    let username: String
    let avatarName: String
    let callingCardName: String
    let totalScore: Int
    let verifiedCount: Int
    let masterCount: Int
    let currentStreak: Int
    let warriorRank: Int
    let explorerRank: Int
    let mindRank: Int
    let earnedBadges: [String]
}

nonisolated struct APIUserSearchResult: Codable, Sendable, Identifiable {
    let userId: String
    let username: String
    let avatarName: String
    let callingCardName: String
    let totalScore: Int
    let verifiedCount: Int
    var isFriend: Bool = false
    var requestPending: Bool = false
    var id: String { userId }
}

nonisolated struct APIEvidenceRecord: Codable, Sendable {
    let id: String
    let questId: String
    let questTitle: String
    let evidenceType: String
    let status: String
    let createdAt: String
}

nonisolated struct APIEvidenceForReview: Codable, Sendable, Identifiable {
    let id: String
    let userId: String
    let questId: String
    let questTitle: String
    let evidenceType: String
    let metadata: [String: String]?
    let createdAt: String
    var submittedAt: String { createdAt }
}

nonisolated struct EvidenceSubmitResult: Codable, Sendable {
    let success: Bool
    let evidenceId: String?
}

nonisolated struct EvidenceStatsResult: Codable, Sendable {
    let totalSubmitted: Int
    let approved: Int
    let rejected: Int
    let pending: Int
}

nonisolated struct ReferralRedeemResult: Codable, Sendable {
    let success: Bool
    let reason: String?
    let bonusGold: Int?
}

nonisolated struct APIReferralCode: Codable, Sendable {
    let code: String
}

nonisolated struct APIReferralRedemption: Codable, Sendable {
    let id: String
    let redeemedBy: String
    let redeemedAt: String
}

nonisolated struct FeedbackSubmitResult: Codable, Sendable {
    let success: Bool
    let ticketId: String?
}

nonisolated struct APIFeedbackTicket: Codable, Sendable {
    let id: String
    let type: String
    let subject: String
    let status: String
    let createdAt: String
}

nonisolated struct SessionHistoryInput: Codable, Sendable {
    let instanceId: String
    let questId: String
    let questTitle: String
    let sessionType: String
    let verified: Bool
    let durationSeconds: Double
    let targetDurationSeconds: Double
    let repsCompleted: Int
    let targetReps: Int
    let holdDurationSeconds: Double
    let targetHoldSeconds: Double
    let jumpCount: Int
    let targetJumps: Int
    let pauseCount: Int
    let totalPauseSeconds: Double
    let backgroundEvents: Int
    let distanceMiles: Double
    let stepsRecorded: Int
    let averageConfidence: Double
    let integrityFlags: [String]
    let metadata: [String: String]
    let xpAwarded: Int
    let goldAwarded: Int
    let diamondsAwarded: Int
    let startedAt: String?
    let endedAt: String?
}

nonisolated struct SessionSaveResult: Codable, Sendable {
    let saved: Bool
}

nonisolated struct APISessionHistoryEntry: Codable, Sendable {
    let id: String
    let sessionType: String
    let questTitle: String
    let verified: Bool
    let createdAt: String
}

nonisolated struct APISessionStats: Codable, Sendable {
    let totalSessions: Int
    let totalVerified: Int
}

nonisolated struct GymGetResult: Codable, Sendable {
    let gym: GymData?
}

nonisolated struct GymData: Codable, Sendable {
    let name: String
    let latitude: Double
    let longitude: Double
    let savedAt: String
}

nonisolated struct GymCheckinResult: Codable, Sendable {
    let verified: Bool
    let reason: String?
}

nonisolated struct APIGymCheckinEntry: Codable, Sendable {
    let id: String
    let gymName: String
    let durationSeconds: Int
    let createdAt: String
}

nonisolated struct APIGymCheckinStats: Codable, Sendable {
    let totalCheckins: Int
    let totalSeconds: Int
}

nonisolated struct WellnessEntrySaveResult: Codable, Sendable {
    let saved: Bool
    let entryId: String?
}

nonisolated struct APIWellnessEntry: Codable, Sendable {
    let id: String
    let type: String
    let content: String
    let prompt: String
    let createdAt: String
}

nonisolated struct APIWellnessStats: Codable, Sendable {
    let totalEntries: Int
    let gratitudeCount: Int
    let affirmationCount: Int
}

nonisolated struct FavoriteQuestsResult: Codable, Sendable {
    let questIds: [String]
}

nonisolated struct HeatmapSyncEntry: Codable, Sendable {
    let date: String
    let count: Int
}

nonisolated struct HeatmapSyncResult: Codable, Sendable {
    let synced: Bool
}

nonisolated struct APIHeatmapEntry: Codable, Sendable {
    let date: String
    let count: Int
}

nonisolated struct APIHeatmapStreak: Codable, Sendable {
    let currentStreak: Int
    let longestStreak: Int
}

nonisolated struct ShopPurchaseResult: Codable, Sendable {
    let success: Bool
    let reason: String?
}

nonisolated struct APIShopTransaction: Codable, Sendable {
    let id: String
    let itemName: String
    let price: Int
    let currencyType: String
    let createdAt: String
}

nonisolated struct APIShopBalance: Codable, Sendable {
    let gold: Int
    let diamonds: Int
}

nonisolated struct BrainGameSaveResult: Codable, Sendable {
    let saved: Bool
}

nonisolated struct APIBrainGameHighScore: Codable, Sendable {
    let gameType: String
    let score: Int
}

nonisolated struct APIBrainGameLeaderboardEntry: Codable, Sendable {
    let username: String
    let score: Int
    let rank: Int
}

nonisolated struct POISyncResult: Codable, Sendable {
    let synced: Bool
}

nonisolated struct APIPOIHistoryEntry: Codable, Sendable {
    let id: String
    let name: String
    let category: String
    let visitedAt: String
}

nonisolated struct APIPOIStats: Codable, Sendable {
    let totalVisited: Int
    let uniqueCategories: Int
}

nonisolated struct StoryProgressSyncEntry: Codable, Sendable {
    let id: String
    let journeyId: String?
    let templateId: String
    let currentNodeId: String
    let visitedNodeIds: [String]
    let inventory: [StoryInventoryItemInput]
    let isComplete: Bool
    let isEnabled: Bool
    let pendingNodeIds: [String]
    let choicesMade: [String: String]
    let endingReached: String?
    let goldEarned: Int
    let diamondsEarned: Int
    let startedAt: String
    let completedAt: String?
}

nonisolated struct StoryInventoryItemInput: Codable, Sendable {
    let id: String
    let name: String
    let itemDescription: String
    let rarity: String
    let storyTitle: String
    let acquiredAt: String
}

nonisolated struct StorySyncResult: Codable, Sendable {
    let synced: Bool
}

nonisolated struct APIStoryProgressEntry: Codable, Sendable {
    let id: String
    let journeyId: String?
    let templateId: String
    let currentNodeId: String
    let visitedNodeIds: [String]
    let inventory: [StoryInventoryItemInput]
    let isComplete: Bool
    let isEnabled: Bool
    let pendingNodeIds: [String]
    let choicesMade: [String: String]
    let endingReached: String?
    let goldEarned: Int
    let diamondsEarned: Int
    let startedAt: String
    let completedAt: String?
}

nonisolated struct APIStoryInventoryResult: Codable, Sendable {
    let items: [StoryInventoryItemInput]
}

nonisolated struct QuestInstanceSyncResult: Codable, Sendable {
    let synced: Bool
}

nonisolated struct QuestInstanceUpsertResult: Codable, Sendable {
    let success: Bool
}

nonisolated struct QuestInstanceInput: Codable, Sendable {
    let id: String
    let questId: String
    let questData: String
    let state: String
    let mode: String
    let startedAt: String
    let submittedAt: String?
    let verifiedAt: String?
    let groupId: String?
    let handshakeVerified: Bool
    let groupSize: Int
}

nonisolated struct QuestInstanceSyncInput: Codable, Sendable {
    let instances: [QuestInstanceInput]
}

nonisolated struct QuestInstanceRemoveInput: Codable, Sendable {
    let instanceId: String
}

nonisolated struct APIQuestInstanceRow: Codable, Sendable {
    let id: String
    let questId: String
    let questData: String
    let state: String
    let mode: String
    let startedAt: String
    let submittedAt: String?
    let verifiedAt: String?
    let groupId: String?
    let handshakeVerified: Bool
    let groupSize: Int

    func toQuestInstance() -> QuestInstance? {
        let formatter = ISO8601DateFormatter()
        guard let quest = try? JSONDecoder().decode(Quest.self, from: Data((questData).utf8)),
              let qState = QuestInstanceState(rawValue: state),
              let qMode = QuestMode(rawValue: mode),
              let start = formatter.date(from: startedAt) else { return nil }
        return QuestInstance(
            id: id,
            quest: quest,
            state: qState,
            mode: qMode,
            startedAt: start,
            submittedAt: submittedAt.flatMap { formatter.date(from: $0) },
            verifiedAt: verifiedAt.flatMap { formatter.date(from: $0) },
            groupId: groupId,
            handshakeVerified: handshakeVerified,
            groupSize: groupSize
        )
    }
}

nonisolated struct JourneySyncResult: Codable, Sendable {
    let synced: Bool
}

nonisolated struct JourneyDayProgressInput: Codable, Sendable {
    let date: String
    let completedCount: Int
    let totalCount: Int
}

nonisolated struct JourneySyncInput: Codable, Sendable {
    let journeyId: String
    let name: String
    let status: String
    let startDate: String
    let endDate: String
    let currentDay: Int
    let totalDays: Int
    let streakDays: Int
    let overallCompletionPercent: Double
    let dayProgress: [JourneyDayProgressInput]
}

nonisolated struct JourneyProgressQueryInput: Codable, Sendable {
    let journeyId: String?
}

nonisolated struct APIJourneyProgress: Codable, Sendable {
    let journeyId: String
    let name: String
    let status: String
    let currentDay: Int
    let totalDays: Int
    let streakDays: Int
    let overallCompletionPercent: Double
}

nonisolated struct PublishTemplateInput: Codable, Sendable {
    let id: String
    let title: String
    let description: String
    let difficulty: String
    let defaultDurationDays: Int
    let questCount: Int
    let questItems: [APIJourneyQuestItemInput]
    let timesAreRecommended: Bool
    let authorUsername: String
    let authorAvatarName: String
}

nonisolated struct APIJourneyQuestItemInput: Codable, Sendable {
    let id: String
    let questId: String
    let frequency: String
    let specificDays: [String]
    let scheduledHour: Int?
    let scheduledMinute: Int?
    let isAnytime: Bool
    let questMode: String
}

nonisolated struct BrowseTemplatesInput: Codable, Sendable {
    let difficulty: String?
    let limit: Int
}

nonisolated struct APIJourneyTemplate: Codable, Sendable {
    let id: String
    let authorUsername: String
    let authorAvatarName: String
    let title: String
    let description: String
    let difficulty: String
    let defaultDurationDays: Int
    let questItems: [APIJourneyQuestItemInput]?
    let timesAreRecommended: Bool?
    let joinCount: Int
    let rating: Double
    let createdAt: String
}

nonisolated struct JoinTemplateInput: Codable, Sendable {
    let templateId: String
}

nonisolated struct FriendJourneyProgressInput: Codable, Sendable {
    let journeyId: String
    let friendIds: [String]
}

nonisolated struct APIFriendJourneyProgress: Codable, Sendable {
    let friendId: String
    let overallPercent: Double
    let todayCompleted: Int
    let todayTotal: Int
}

nonisolated struct SendNotificationResult: Codable, Sendable {
    let sent: Bool
}
