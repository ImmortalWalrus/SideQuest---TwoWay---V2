import Foundation

nonisolated struct RewardEvent: Identifiable, Codable, Sendable {
    let id: String
    let questTitle: String
    let xpEarned: Int
    let goldEarned: Int
    let diamondsEarned: Int
    let streakBonus: Bool
    let streakMultiplier: Double
    let newBadge: String?
    let createdAt: Date
}

nonisolated struct ActivityItem: Identifiable, Codable, Sendable {
    let id: String
    let username: String
    let avatarName: String
    let questTitle: String
    let path: QuestPath
    let isMaster: Bool
    let completedAt: Date
}
