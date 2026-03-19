import Foundation

nonisolated enum FocusIntegrityFlag: String, Codable, Sendable {
    case appBackgrounded
    case tooManyPauses
    case totalPauseExceeded
    case tooShort
    case clockManipulated
}

nonisolated struct FocusSession: Identifiable, Codable, Sendable {
    let id: String
    var startedAt: Date?
    var endedAt: Date?
    var focusDurationSeconds: TimeInterval = 0
    var targetDurationSeconds: TimeInterval = 0
    var pauseCount: Int = 0
    var totalPauseSeconds: TimeInterval = 0
    var maxAllowedPauseCount: Int = 0
    var maxAllowedPauseSeconds: Int = 0
    var backgroundEvents: Int = 0
    var longestBackgroundSeconds: TimeInterval = 0
    var integrityFlags: [FocusIntegrityFlag] = []
    var wasDisqualified: Bool = false

    var isValid: Bool {
        !wasDisqualified && integrityFlags.isEmpty
    }

    var hasCriticalViolation: Bool {
        wasDisqualified || integrityFlags.contains(where: { [.appBackgrounded, .clockManipulated].contains($0) })
    }

    var goalReached: Bool {
        focusDurationSeconds >= targetDurationSeconds
    }

    var focusRatio: Double {
        guard let start = startedAt, let end = endedAt else { return 0 }
        let total = end.timeIntervalSince(start)
        guard total > 0 else { return 0 }
        return focusDurationSeconds / total
    }
}
