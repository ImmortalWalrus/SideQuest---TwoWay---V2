import Foundation

nonisolated enum MeditationIntegrityFlag: String, Codable, Sendable {
    case faceNotDetected
    case eyesOpenTooMuch
    case excessiveMovement
    case lowConfidence
    case tooShort
}

nonisolated struct MeditationSession: Identifiable, Codable, Sendable {
    let id: String
    var startedAt: Date?
    var endedAt: Date?
    var meditationDurationSeconds: TimeInterval = 0
    var targetDurationSeconds: TimeInterval = 0
    var totalFramesAnalyzed: Int = 0
    var framesWithFaceDetected: Int = 0
    var framesWithEyesClosed: Int = 0
    var framesHeadStill: Int = 0
    var averageConfidence: Double = 0
    var faceLostCount: Int = 0
    var integrityFlags: [MeditationIntegrityFlag] = []
    var wasDisqualified: Bool = false

    var isValid: Bool {
        !wasDisqualified && integrityFlags.isEmpty
    }

    var hasCriticalViolation: Bool {
        wasDisqualified || integrityFlags.contains(where: { [.faceNotDetected, .eyesOpenTooMuch].contains($0) })
    }

    var goalReached: Bool {
        meditationDurationSeconds >= targetDurationSeconds
    }

    var faceDetectionRatio: Double {
        guard totalFramesAnalyzed > 0 else { return 0 }
        return Double(framesWithFaceDetected) / Double(totalFramesAnalyzed)
    }

    var eyesClosedRatio: Double {
        guard framesWithFaceDetected > 0 else { return 0 }
        return Double(framesWithEyesClosed) / Double(framesWithFaceDetected)
    }

    var stillnessRatio: Double {
        guard framesWithFaceDetected > 0 else { return 0 }
        return Double(framesHeadStill) / Double(framesWithFaceDetected)
    }
}
