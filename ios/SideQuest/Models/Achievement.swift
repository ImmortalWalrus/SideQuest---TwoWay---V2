import Foundation

nonisolated struct Achievement: Identifiable, Codable, Sendable {
    let id: String
    let title: String
    let description: String
    let iconName: String
    let category: AchievementCategory
    let requirement: Int
    let badgeColor: String
}

nonisolated enum AchievementCategory: String, CaseIterable, Identifiable, Codable, Sendable {
    case quests = "Quests"
    case streaks = "Streaks"
    case social = "Social"
    case brain = "Brain"
    case mastery = "Mastery"
    case milestones = "Milestones"

    var id: String { rawValue }

    var iconName: String {
        switch self {
        case .quests: return "checkmark.seal.fill"
        case .streaks: return "flame.fill"
        case .social: return "person.2.fill"
        case .brain: return "brain.head.profile.fill"
        case .mastery: return "crown.fill"
        case .milestones: return "flag.fill"
        }
    }
}

enum AchievementCatalog {
    static let all: [Achievement] = [
        Achievement(id: "first_quest", title: "First Steps", description: "Complete your first quest", iconName: "figure.walk", category: .quests, requirement: 1, badgeColor: "green"),
        Achievement(id: "quest_10", title: "Dedicated", description: "Complete 10 quests", iconName: "checkmark.seal.fill", category: .quests, requirement: 10, badgeColor: "blue"),
        Achievement(id: "quest_25", title: "Committed", description: "Complete 25 quests", iconName: "checkmark.seal.fill", category: .quests, requirement: 25, badgeColor: "blue"),
        Achievement(id: "quest_50", title: "Relentless", description: "Complete 50 quests", iconName: "bolt.fill", category: .quests, requirement: 50, badgeColor: "purple"),
        Achievement(id: "quest_100", title: "Centurion", description: "Complete 100 quests", iconName: "shield.checkered", category: .quests, requirement: 100, badgeColor: "orange"),

        Achievement(id: "streak_3", title: "Warming Up", description: "Reach a 3-day streak", iconName: "flame.fill", category: .streaks, requirement: 3, badgeColor: "orange"),
        Achievement(id: "streak_7", title: "On Fire", description: "Reach a 7-day streak", iconName: "flame.fill", category: .streaks, requirement: 7, badgeColor: "orange"),
        Achievement(id: "streak_14", title: "Unstoppable", description: "Reach a 14-day streak", iconName: "flame.circle.fill", category: .streaks, requirement: 14, badgeColor: "red"),
        Achievement(id: "streak_30", title: "Iron Will", description: "Reach a 30-day streak", iconName: "flame.circle.fill", category: .streaks, requirement: 30, badgeColor: "red"),

        Achievement(id: "friends_1", title: "Social Butterfly", description: "Add your first friend", iconName: "person.badge.plus", category: .social, requirement: 1, badgeColor: "cyan"),
        Achievement(id: "friends_5", title: "Squad Goals", description: "Have 5 friends", iconName: "person.3.fill", category: .social, requirement: 5, badgeColor: "cyan"),
        Achievement(id: "handshake_3", title: "Team Player", description: "Complete 3 handshake quests", iconName: "hand.raised.fingers.spread.fill", category: .social, requirement: 3, badgeColor: "teal"),

        Achievement(id: "brain_champ", title: "Brain Champion", description: "Score 5+ in any brain game", iconName: "brain.head.profile.fill", category: .brain, requirement: 5, badgeColor: "indigo"),
        Achievement(id: "level_5", title: "Rising Star", description: "Reach Level 5", iconName: "star.fill", category: .mastery, requirement: 5, badgeColor: "yellow"),
        Achievement(id: "level_10", title: "Proven", description: "Reach Level 10", iconName: "star.circle.fill", category: .mastery, requirement: 10, badgeColor: "yellow"),
        Achievement(id: "level_20", title: "Ascendant", description: "Reach Level 20", iconName: "crown.fill", category: .mastery, requirement: 20, badgeColor: "orange"),
        Achievement(id: "level_50", title: "Legendary", description: "Reach Level 50", iconName: "trophy.fill", category: .mastery, requirement: 50, badgeColor: "red"),

        Achievement(id: "mod_10", title: "Justice Served", description: "Complete 10 mod sessions", iconName: "shield.checkered", category: .milestones, requirement: 10, badgeColor: "green"),
        Achievement(id: "gold_1000", title: "Rich", description: "Accumulate 1,000 gold spent lifetime", iconName: "dollarsign.circle.fill", category: .milestones, requirement: 1000, badgeColor: "yellow"),
        Achievement(id: "warrior_10", title: "Warrior Path", description: "Reach Warrior Rank 10", iconName: "flame.fill", category: .milestones, requirement: 10, badgeColor: "red"),
        Achievement(id: "explorer_10", title: "Explorer Path", description: "Reach Explorer Rank 10", iconName: "map.fill", category: .milestones, requirement: 10, badgeColor: "green"),
        Achievement(id: "mind_10", title: "Mind Path", description: "Reach Mind Rank 10", iconName: "brain.head.profile.fill", category: .milestones, requirement: 10, badgeColor: "indigo"),
    ]
}
