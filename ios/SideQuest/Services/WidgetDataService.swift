import Foundation
import WidgetKit

enum WidgetDataService {
    static let suiteName = "group.app.rork.sidequest"

    private static var shared: UserDefaults? {
        UserDefaults(suiteName: suiteName)
    }

    private enum Keys {
        static let username = "widget_username"
        static let level = "widget_level"
        static let levelTitle = "widget_levelTitle"
        static let levelIcon = "widget_levelIcon"
        static let xpCurrent = "widget_xpCurrent"
        static let xpNeeded = "widget_xpNeeded"
        static let totalScore = "widget_totalScore"
        static let streak = "widget_streak"
        static let verifiedCount = "widget_verifiedCount"
        static let activeQuestTitle = "widget_activeQuestTitle"
        static let activeQuestPath = "widget_activeQuestPath"
        static let activeQuestIcon = "widget_activeQuestIcon"
        static let dailyCompletions = "widget_dailyCompletions"
        static let weeklyStreakDays = "widget_weeklyStreakDays"
    }

    static func update(
        username: String,
        level: Int,
        levelTitle: String,
        levelIcon: String,
        xpCurrent: Int,
        xpNeeded: Int,
        totalScore: Int,
        streak: Int,
        verifiedCount: Int,
        activeQuestTitle: String?,
        activeQuestPath: String?,
        activeQuestIcon: String?,
        dailyCompletions: Int,
        weeklyStreakDays: [Bool]
    ) {
        guard let defaults = shared else { return }
        defaults.set(username, forKey: Keys.username)
        defaults.set(level, forKey: Keys.level)
        defaults.set(levelTitle, forKey: Keys.levelTitle)
        defaults.set(levelIcon, forKey: Keys.levelIcon)
        defaults.set(xpCurrent, forKey: Keys.xpCurrent)
        defaults.set(xpNeeded, forKey: Keys.xpNeeded)
        defaults.set(totalScore, forKey: Keys.totalScore)
        defaults.set(streak, forKey: Keys.streak)
        defaults.set(verifiedCount, forKey: Keys.verifiedCount)
        defaults.set(activeQuestTitle, forKey: Keys.activeQuestTitle)
        defaults.set(activeQuestPath, forKey: Keys.activeQuestPath)
        defaults.set(activeQuestIcon, forKey: Keys.activeQuestIcon)
        defaults.set(dailyCompletions, forKey: Keys.dailyCompletions)
        defaults.set(weeklyStreakDays, forKey: Keys.weeklyStreakDays)
        WidgetCenter.shared.reloadAllTimelines()
    }

    static func read() -> WidgetData {
        guard let defaults = shared else { return .placeholder }
        return WidgetData(
            username: defaults.string(forKey: Keys.username) ?? "Adventurer",
            level: defaults.integer(forKey: Keys.level).nonZero ?? 1,
            levelTitle: defaults.string(forKey: Keys.levelTitle) ?? "Initiate",
            levelIcon: defaults.string(forKey: Keys.levelIcon) ?? "leaf.fill",
            xpCurrent: defaults.integer(forKey: Keys.xpCurrent),
            xpNeeded: max(1, defaults.integer(forKey: Keys.xpNeeded)),
            totalScore: defaults.integer(forKey: Keys.totalScore),
            streak: defaults.integer(forKey: Keys.streak),
            verifiedCount: defaults.integer(forKey: Keys.verifiedCount),
            activeQuestTitle: defaults.string(forKey: Keys.activeQuestTitle),
            activeQuestPath: defaults.string(forKey: Keys.activeQuestPath),
            activeQuestIcon: defaults.string(forKey: Keys.activeQuestIcon),
            dailyCompletions: defaults.integer(forKey: Keys.dailyCompletions),
            weeklyStreakDays: defaults.array(forKey: Keys.weeklyStreakDays) as? [Bool] ?? Array(repeating: false, count: 7)
        )
    }
}

nonisolated struct WidgetData: Sendable {
    let username: String
    let level: Int
    let levelTitle: String
    let levelIcon: String
    let xpCurrent: Int
    let xpNeeded: Int
    let totalScore: Int
    let streak: Int
    let verifiedCount: Int
    let activeQuestTitle: String?
    let activeQuestPath: String?
    let activeQuestIcon: String?
    let dailyCompletions: Int
    let weeklyStreakDays: [Bool]

    var xpProgress: Double {
        guard xpNeeded > 0 else { return 1.0 }
        return Double(xpCurrent) / Double(xpNeeded)
    }

    static let placeholder = WidgetData(
        username: "Adventurer",
        level: 1,
        levelTitle: "Initiate",
        levelIcon: "leaf.fill",
        xpCurrent: 45,
        xpNeeded: 100,
        totalScore: 45,
        streak: 3,
        verifiedCount: 7,
        activeQuestTitle: "Morning Run",
        activeQuestPath: "Explorer",
        activeQuestIcon: "map.fill",
        dailyCompletions: 2,
        weeklyStreakDays: [true, true, true, false, false, false, false]
    )
}

private extension Int {
    var nonZero: Int? {
        self == 0 ? nil : self
    }
}
