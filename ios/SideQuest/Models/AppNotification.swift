import Foundation

nonisolated enum NotificationType: String, Codable, Sendable {
    case questVerified
    case questRejected
    case groupInvite
    case modTask
    case featuredQuest
    case voteAlignment
    case weeklyReport
    case nudge
}

nonisolated struct AppNotification: Identifiable, Codable, Sendable {
    let id: String
    let type: NotificationType
    let title: String
    let message: String
    let createdAt: Date
    var isRead: Bool
    let deepLinkId: String?
}
