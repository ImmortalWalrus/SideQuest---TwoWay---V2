import Foundation

nonisolated enum ExerciseType: String, Codable, Sendable {
    case pushUp = "Push-Up"
    case plank = "Plank"
    case wallSit = "Wall Sit"
    case jumpRope = "Jump Rope"
}

nonisolated enum ExerciseIntegrityFlag: String, Codable, Sendable {
    case bodyNotDetected
    case lowConfidence
    case tooFastReps
    case poseNotMaintained
    case inconsistentArms
}

nonisolated struct ExerciseSession: Identifiable, Codable, Sendable {
    let id: String
    let exerciseType: ExerciseType
    var startedAt: Date?
    var endedAt: Date?
    var repsCompleted: Int = 0
    var holdDurationSeconds: TimeInterval = 0
    var targetReps: Int = 0
    var targetHoldSeconds: TimeInterval = 0
    var totalFramesAnalyzed: Int = 0
    var framesWithBodyDetected: Int = 0
    var averageConfidence: Double = 0
    var bodyLostCount: Int = 0
    var tooFastRepCount: Int = 0
    var integrityFlags: [ExerciseIntegrityFlag] = []
    var wasDisqualified: Bool = false

    var isValid: Bool {
        !wasDisqualified && integrityFlags.isEmpty
    }

    var hasCriticalViolation: Bool {
        wasDisqualified || integrityFlags.contains(where: { [.bodyNotDetected, .tooFastReps].contains($0) })
    }

    var jumpCount: Int = 0
    var targetJumps: Int = 0
    var bestStreakJumps: Int = 0
    var bpmUsed: Int = 0
    var onBeatJumps: Int = 0

    var goalReached: Bool {
        switch exerciseType {
        case .pushUp: repsCompleted >= targetReps
        case .plank, .wallSit: holdDurationSeconds >= targetHoldSeconds
        case .jumpRope: jumpCount >= targetJumps
        }
    }

    var bodyDetectionRatio: Double {
        guard totalFramesAnalyzed > 0 else { return 0 }
        return Double(framesWithBodyDetected) / Double(totalFramesAnalyzed)
    }
}
