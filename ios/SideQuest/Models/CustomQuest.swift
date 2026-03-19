import Foundation

nonisolated enum CustomQuestRepeatability: String, CaseIterable, Codable, Sendable {
    case oneTime = "One-time"
    case repeatableDaily = "Daily"
    case repeatableWeekly = "Weekly"
}

nonisolated enum SubmissionStatus: String, Codable, Sendable {
    case draft = "Draft"
    case pending = "Pending Review"
    case approved = "Approved"
    case rejected = "Rejected"
}

nonisolated enum SubmissionRejectionReason: String, CaseIterable, Codable, Sendable {
    case unsafe = "Unsafe"
    case tooVague = "Too Vague"
    case duplicative = "Duplicative"
    case notAligned = "Not Aligned"
}

nonisolated struct CustomQuest: Identifiable, Codable, Sendable, Hashable {
    let id: String
    var title: String
    var description: String
    var path: QuestPath
    var difficulty: QuestDifficulty
    var repeatability: CustomQuestRepeatability
    var suggestedTime: String?
    var notes: String?
    let createdAt: Date
    var completionCount: Int
    var submissionStatus: SubmissionStatus
    var rejectionReason: SubmissionRejectionReason?
    var submittedAt: Date?
    var publishedQuestId: String?
    let authorUserId: String
    let authorUsername: String

    var isPublished: Bool { submissionStatus == .approved && publishedQuestId != nil }
    var isPendingReview: Bool { submissionStatus == .pending }
    var canEdit: Bool { submissionStatus == .draft || submissionStatus == .rejected }
    var canSubmit: Bool { submissionStatus == .draft || submissionStatus == .rejected }

    func toQuest() -> Quest {
        Quest(
            id: "custom_\(id)",
            title: title,
            description: description,
            path: path,
            difficulty: difficulty,
            type: .open,
            evidenceType: nil,
            xpReward: difficultyXP,
            goldReward: difficultyGold,
            diamondReward: 0,
            milestoneIds: [],
            minCompletionMinutes: 0,
            isRepeatable: repeatability != .oneTime,
            requiresUniqueLocation: false,
            isFeatured: false,
            featuredExpiresAt: nil,
            completionCount: completionCount
        )
    }

    private var difficultyXP: Int {
        switch difficulty {
        case .easy: 90
        case .medium: 200
        case .hard: 380
        case .expert: 680
        }
    }

    private var difficultyGold: Int {
        switch difficulty {
        case .easy: 45
        case .medium: 100
        case .hard: 190
        case .expert: 340
        }
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }

    static func == (lhs: CustomQuest, rhs: CustomQuest) -> Bool {
        lhs.id == rhs.id
    }
}
