import Foundation

nonisolated struct Milestone: Identifiable, Codable, Sendable {
    let id: String
    let title: String
    let description: String
    let path: QuestPath
    let requiredCount: Int
    var currentCount: Int
    let questIds: [String]
    let requiresUniqueLocations: Bool
    let uniqueLocationsTarget: Int
    let uniqueLocationsAchieved: Int
    let rewardXP: Int
    let rewardGold: Int
    let isPinned: Bool
    let isCompleted: Bool
}

nonisolated struct MasterContract: Identifiable, Codable, Sendable {
    let id: String
    let title: String
    let subtitle: String
    let description: String
    let path: QuestPath
    let durationDays: Int
    var currentDay: Int
    var graceDaysUsed: Int
    let maxGraceDays: Int
    var requirements: [MasterRequirement]
    let diamondReward: Int
    let xpReward: Int
    var isActive: Bool
    var isCompleted: Bool
    var isFailed: Bool
    var startedAt: Date?
    var timeViolationCount: Int = 0
    var lastIntegrityCheck: Date?
}

nonisolated struct MasterRequirement: Identifiable, Codable, Sendable {
    let id: String
    let title: String
    let target: Int
    var current: Int
    let unit: String

    var progress: Double {
        guard target > 0 else { return 0 }
        return min(1.0, Double(current) / Double(target))
    }
}
