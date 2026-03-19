import Foundation

nonisolated struct UserProfile: Identifiable, Codable, Sendable {
    var id: String
    var username: String
    var avatarName: String
    var callingCardName: String
    var totalScore: Int
    var gold: Int
    var diamonds: Int
    var verifiedCount: Int
    var masterCount: Int
    var karma: Int
    var currentStreak: Int
    var verifiedStreak: Int
    var stepsToday: Int
    var stepsThisWeek: Int
    var handshakeCount: Int
    var referralCount: Int
    var warriorRank: Int
    var explorerRank: Int
    var mindRank: Int
    var modSessionsCompleted: Int
    var modAccuracy: Double
    var strikes: Int
    var screenshotStrikes: Int
    var isSuspended: Bool
    var modBanUntil: Date?
    var ownedItems: [String]
    var joinedAt: Date
    var equippedSkin: String?
    var equippedCallingCard: String?
    var equippedEffect: String?
    var earnedBadges: [String]
    var spriteLoadout: SpriteLoadout
    var ownedSpriteItems: [String]
    var selectedSkills: [UserSkill]
    var selectedInterests: [UserInterest]
    var selectedCharacter: PlayerCharacterType

    var level: Int {
        LevelSystem.level(for: totalScore)
    }

    var xpForCurrentLevel: Int {
        LevelSystem.xpForCurrentLevel(totalScore: totalScore)
    }

    var xpNeededForNextLevel: Int {
        LevelSystem.xpNeededForNextLevel(totalScore: totalScore)
    }

    var levelProgress: Double {
        let needed = xpNeededForNextLevel
        guard needed > 0 else { return 1.0 }
        return Double(xpForCurrentLevel) / Double(needed)
    }

    var levelTitle: String {
        LevelSystem.title(for: level)
    }

    init(id: String, username: String, avatarName: String, callingCardName: String, totalScore: Int, gold: Int, diamonds: Int, verifiedCount: Int, masterCount: Int, karma: Int, currentStreak: Int, verifiedStreak: Int, stepsToday: Int, stepsThisWeek: Int, handshakeCount: Int, referralCount: Int, warriorRank: Int, explorerRank: Int, mindRank: Int, modSessionsCompleted: Int, modAccuracy: Double, strikes: Int, screenshotStrikes: Int, isSuspended: Bool, modBanUntil: Date? = nil, ownedItems: [String], joinedAt: Date, equippedSkin: String? = nil, equippedCallingCard: String? = nil, equippedEffect: String? = nil, earnedBadges: [String], spriteLoadout: SpriteLoadout = .default, ownedSpriteItems: [String] = ["spiky_black", "basic_tee_blue", "basic_pants_gray", "sneakers_white"], selectedSkills: [UserSkill] = [], selectedInterests: [UserInterest] = [], selectedCharacter: PlayerCharacterType = .knight) {
        self.id = id
        self.username = username
        self.avatarName = avatarName
        self.callingCardName = callingCardName
        self.totalScore = totalScore
        self.gold = gold
        self.diamonds = diamonds
        self.verifiedCount = verifiedCount
        self.masterCount = masterCount
        self.karma = karma
        self.currentStreak = currentStreak
        self.verifiedStreak = verifiedStreak
        self.stepsToday = stepsToday
        self.stepsThisWeek = stepsThisWeek
        self.handshakeCount = handshakeCount
        self.referralCount = referralCount
        self.warriorRank = warriorRank
        self.explorerRank = explorerRank
        self.mindRank = mindRank
        self.modSessionsCompleted = modSessionsCompleted
        self.modAccuracy = modAccuracy
        self.strikes = strikes
        self.screenshotStrikes = screenshotStrikes
        self.isSuspended = isSuspended
        self.modBanUntil = modBanUntil
        self.ownedItems = ownedItems
        self.joinedAt = joinedAt
        self.equippedSkin = equippedSkin
        self.equippedCallingCard = equippedCallingCard
        self.equippedEffect = equippedEffect
        self.earnedBadges = earnedBadges
        self.spriteLoadout = spriteLoadout
        self.ownedSpriteItems = ownedSpriteItems
        self.selectedSkills = selectedSkills
        self.selectedInterests = selectedInterests
        self.selectedCharacter = selectedCharacter
    }
}

nonisolated struct LeaderboardEntry: Identifiable, Codable, Sendable {
    let id: String
    let rank: Int
    let username: String
    let avatarName: String
    let callingCardName: String
    let totalScore: Int
    let verifiedCount: Int
    let masterCount: Int
}
