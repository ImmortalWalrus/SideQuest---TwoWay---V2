import Foundation

nonisolated enum FriendStatus: String, Codable, Sendable {
    case pending = "Pending"
    case accepted = "Accepted"
}

nonisolated struct Friend: Identifiable, Codable, Sendable {
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
    let status: FriendStatus
    let addedAt: Date
    var lastActiveAt: Date
    var isOnline: Bool

    var isAccepted: Bool { status == .accepted }
    var isPending: Bool { status == .pending }
}

nonisolated struct FriendRequest: Identifiable, Codable, Sendable {
    let id: String
    let fromUserId: String
    let fromUsername: String
    let fromAvatarName: String
    let fromCallingCardName: String
    let fromTotalScore: Int
    let fromVerifiedCount: Int
    let sentAt: Date
}
