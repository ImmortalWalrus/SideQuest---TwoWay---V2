import Foundation

nonisolated enum ReadingIntegrityFlag: String, Codable, Sendable {
    case tooShort
    case noPhoto
}

nonisolated struct ReadingSession: Identifiable, Codable, Sendable {
    let id: String
    var startedAt: Date?
    var endedAt: Date?
    var readingDurationSeconds: TimeInterval = 0
    var targetDurationSeconds: TimeInterval = 0
    var photoTaken: Bool = false
    var integrityFlags: [ReadingIntegrityFlag] = []
    var wasDisqualified: Bool = false

    var isValid: Bool {
        !wasDisqualified && integrityFlags.isEmpty
    }

    var hasCriticalViolation: Bool {
        wasDisqualified
    }

    var goalReached: Bool {
        readingDurationSeconds >= targetDurationSeconds
    }
}
