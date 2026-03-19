import Foundation

nonisolated enum BadgeVisualCategory: String, CaseIterable, Sendable {
    case quests
    case streaks
    case social
    case mastery
    case brain
    case milestones

    var badgeImageName: String {
        switch self {
        case .quests: "badge_quests"
        case .streaks: "badge_streaks"
        case .social: "badge_social"
        case .mastery: "badge_mastery"
        case .brain: "badge_brain"
        case .milestones: "badge_milestones"
        }
    }

    static func category(for achievement: Achievement) -> BadgeVisualCategory {
        switch achievement.category {
        case .quests: .quests
        case .streaks: .streaks
        case .social: .social
        case .brain: .brain
        case .mastery: .mastery
        case .milestones: .milestones
        }
    }
}

struct EarnedBadgeDisplay: Identifiable {
    let id: String
    let achievement: Achievement
    let visualCategory: BadgeVisualCategory

    var badgeImageName: String { visualCategory.badgeImageName }
}

enum BadgeDisplayMapper {
    static func earnedBadges(from profile: UserProfile) -> [EarnedBadgeDisplay] {
        profile.earnedBadges.compactMap { badgeId in
            guard let achievement = AchievementCatalog.all.first(where: { $0.id == badgeId }) else { return nil }
            let category = BadgeVisualCategory.category(for: achievement)
            return EarnedBadgeDisplay(id: badgeId, achievement: achievement, visualCategory: category)
        }
    }
}
