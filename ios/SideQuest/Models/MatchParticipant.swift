import Foundation

struct MatchParticipant: Identifiable, Codable, Sendable {
    let id: String
    let username: String
    let avatarName: String
    let callingCardName: String
    let totalScore: Int
    let verifiedCount: Int
    let currentStreak: Int
    let warriorRank: Int
    let explorerRank: Int
    let mindRank: Int
    var isFriend: Bool = false
    var friendRequestSent: Bool = false
}
