import Foundation

nonisolated enum LevelSystem: Sendable {
    static let maxLevel: Int = 100
    static let totalXPForMax: Int = 90_000

    static let xpThresholds: [Int] = {
        var thresholds: [Int] = [0]
        for i in 1...maxLevel {
            let xpForLevel = 42 + 17 * i
            thresholds.append(thresholds[i - 1] + xpForLevel)
        }
        return thresholds
    }()

    static func level(for totalXP: Int) -> Int {
        for i in (0..<xpThresholds.count).reversed() {
            if totalXP >= xpThresholds[i] {
                return min(i + 1, maxLevel)
            }
        }
        return 1
    }

    static func xpForCurrentLevel(totalScore: Int) -> Int {
        let lvl = level(for: totalScore)
        let threshold = lvl <= xpThresholds.count ? xpThresholds[lvl - 1] : xpThresholds.last ?? 0
        return totalScore - threshold
    }

    static func xpNeededForNextLevel(totalScore: Int) -> Int {
        let lvl = level(for: totalScore)
        guard lvl < xpThresholds.count else { return 0 }
        let current = xpThresholds[lvl - 1]
        let next = xpThresholds[lvl]
        return next - current
    }

    static func title(for level: Int) -> String {
        switch level {
        case 1...5: return "Initiate"
        case 6...10: return "Apprentice"
        case 11...15: return "Adept"
        case 16...20: return "Journeyman"
        case 21...25: return "Veteran"
        case 26...30: return "Elite"
        case 31...40: return "Champion"
        case 41...50: return "Master"
        case 51...60: return "Grandmaster"
        case 61...75: return "Legend"
        case 76...90: return "Mythic"
        case 91...100: return "Transcendent"
        default: return "Ascended"
        }
    }

    static func iconName(for level: Int) -> String {
        switch level {
        case 1...5: return "leaf.fill"
        case 6...10: return "shield.fill"
        case 11...15: return "bolt.shield.fill"
        case 16...20: return "star.fill"
        case 21...30: return "star.circle.fill"
        case 31...40: return "crown.fill"
        case 41...50: return "trophy.fill"
        case 51...60: return "medal.fill"
        case 61...75: return "sparkles"
        case 76...90: return "flame.fill"
        default: return "sun.max.fill"
        }
    }

    static func streakMultiplier(for streak: Int) -> Double {
        switch streak {
        case 0...2: return 1.0
        case 3...6: return 1.1
        case 7...13: return 1.25
        case 14...29: return 1.5
        case 30...59: return 1.75
        default: return 2.0
        }
    }

    static func streakTierName(for streak: Int) -> String {
        switch streak {
        case 0...2: return "No Bonus"
        case 3...6: return "Warming Up"
        case 7...13: return "On Fire"
        case 14...29: return "Blazing"
        case 30...59: return "Inferno"
        default: return "Legendary"
        }
    }

    static func nextStreakMilestone(for streak: Int) -> Int {
        switch streak {
        case 0...2: return 3
        case 3...6: return 7
        case 7...13: return 14
        case 14...29: return 30
        case 30...59: return 60
        default: return streak + 1
        }
    }
}
