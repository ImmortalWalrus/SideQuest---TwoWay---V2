import Foundation

nonisolated enum QuestInstanceState: String, Codable, Sendable {
    case pendingInvite = "Pending Invite"
    case pendingQueue = "Pending Queue"
    case active = "Active"
    case submitted = "Submitted"
    case verified = "Verified"
    case rejected = "Rejected"
    case failed = "Failed"

    var isActive: Bool { self == .active }
    var isPending: Bool { self == .pendingInvite || self == .pendingQueue }
}

nonisolated enum QuestMode: String, Codable, Sendable {
    case solo = "Solo"
    case friend = "With Friend"
    case matchmaker = "Matchmaker"
}

nonisolated struct QuestInstance: Identifiable, Codable, Sendable {
    let id: String
    let quest: Quest
    var state: QuestInstanceState
    let mode: QuestMode
    let startedAt: Date
    var submittedAt: Date?
    var verifiedAt: Date?
    let groupId: String?
    var handshakeVerified: Bool = false
    var groupSize: Int = 1
    var autoCheckInStartedAt: Date? = nil
    var autoCheckInLastTickAt: Date? = nil
    var autoCheckInElapsedSeconds: Int? = nil
    var autoCheckInCompletedAt: Date? = nil
    var autoCheckInInRange: Bool? = nil

    var isGPSAutoCheckInQuest: Bool {
        quest.isPlaceVerificationQuest && quest.requiredPlaceType?.isGPSOnly == true
    }

    var autoCheckInRequiredSeconds: Int {
        max(60, quest.effectivePresenceMinutes * 60)
    }

    var autoCheckInElapsedSecondsValue: Int {
        max(0, autoCheckInElapsedSeconds ?? 0)
    }

    var autoCheckInRemainingSeconds: Int {
        max(0, autoCheckInRequiredSeconds - autoCheckInElapsedSecondsValue)
    }

    var autoCheckInProgressFraction: Double {
        guard autoCheckInRequiredSeconds > 0 else { return 0 }
        return min(1.0, Double(autoCheckInElapsedSecondsValue) / Double(autoCheckInRequiredSeconds))
    }

    var isAutoCheckInInRange: Bool {
        autoCheckInInRange ?? false
    }

    var isAutoCheckInComplete: Bool {
        isGPSAutoCheckInQuest && (autoCheckInCompletedAt != nil || autoCheckInElapsedSecondsValue >= autoCheckInRequiredSeconds)
    }

    var canSubmit: Bool {
        guard state == .active else { return false }
        if isGPSAutoCheckInQuest {
            return isAutoCheckInComplete
        }
        let elapsed = Date().timeIntervalSince(startedAt)
        let requiredMinutes = Double(quest.minCompletionMinutes)
        return elapsed >= requiredMinutes * 60
    }

    var timeUntilSubmit: TimeInterval {
        if isGPSAutoCheckInQuest {
            return TimeInterval(autoCheckInRemainingSeconds)
        }
        let elapsed = Date().timeIntervalSince(startedAt)
        let required = Double(quest.minCompletionMinutes) * 60
        return max(0, required - elapsed)
    }
}
