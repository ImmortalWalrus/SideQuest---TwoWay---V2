import Foundation
import CoreLocation

nonisolated enum IntegrityFlag: String, Codable, Sendable {
    case teleportDetected
    case carSpeedDetected
    case sustainedDriving
    case excessivePause
    case weakGPS
    case sessionTooShort
    case outsideTimeWindow
    case timeLimitExpired
    case clockManipulated

    var isCritical: Bool {
        switch self {
        case .carSpeedDetected, .sustainedDriving, .teleportDetected, .timeLimitExpired, .clockManipulated:
            return true
        case .excessivePause, .weakGPS, .sessionTooShort, .outsideTimeWindow:
            return false
        }
    }
}

nonisolated struct RoutePoint: Codable, Sendable {
    let latitude: Double
    let longitude: Double
    let timestamp: Date
    let accuracy: Double
    let speed: Double
}

nonisolated struct PedometerSegment: Codable, Sendable {
    let startDate: Date
    let endDate: Date
    let steps: Int
    let estimatedDistanceMeters: Double
    let reason: String
}

nonisolated struct TrackingSession: Identifiable, Codable, Sendable {
    let id: String
    var routePoints: [RoutePoint]
    var startedAt: Date?
    var endedAt: Date?
    var distanceMiles: Double
    var durationSeconds: TimeInterval
    var totalPauseSeconds: TimeInterval
    var integrityFlags: [IntegrityFlag]
    var timeWindowVerified: Bool?
    var speedViolationCount: Int = 0
    var maxRecordedSpeedMph: Double = 0
    var wasDisqualified: Bool = false
    var startCheckpoint: TimeCheckpoint?
    var timeIntegrityVerified: Bool?
    var pedometerSegments: [PedometerSegment] = []
    var pedometerEstimatedDistanceMiles: Double = 0
    var sessionSteps: Int? = nil
    var gpsGapCount: Int = 0
    var routeContinuityScore: Double = 1.0
    var isLoopCompleted: Bool = false
    var loopClosureDistanceMeters: Double?

    var isValid: Bool {
        !wasDisqualified && integrityFlags.isEmpty
    }

    var hasCriticalViolation: Bool {
        wasDisqualified || integrityFlags.contains(where: \.isCritical)
    }

    static func verifyTimeWindow(start: Date, end: Date, quest: Quest) -> Bool {
        guard let windowStartMin = quest.effectiveStartMinuteOfDay,
              let windowEndMin = quest.effectiveEndMinuteOfDay else { return true }
        let cal = Calendar.current
        let startHour = cal.component(.hour, from: start)
        let startMinute = cal.component(.minute, from: start)
        let endHour = cal.component(.hour, from: end)
        let endMinute = cal.component(.minute, from: end)
        let startMinutes = startHour * 60 + startMinute
        let endMinutes = endHour * 60 + endMinute
        let windowEnd = windowEndMin + quest.timeWindowGraceMinutes
        if windowStartMin <= windowEnd {
            return startMinutes >= windowStartMin && endMinutes <= windowEnd
        } else {
            let startOk = startMinutes >= windowStartMin || startMinutes <= windowEnd
            let endOk = endMinutes >= windowStartMin || endMinutes <= windowEnd
            return startOk && endOk
        }
    }

    var averagePaceMinutesPerMile: Double? {
        let miles = totalEstimatedDistanceMiles
        guard miles > 0.01 else { return nil }
        return (durationSeconds / 60.0) / miles
    }

    var coordinates: [CLLocationCoordinate2D] {
        routePoints.map { CLLocationCoordinate2D(latitude: $0.latitude, longitude: $0.longitude) }
    }

    var totalEstimatedDistanceMiles: Double {
        distanceMiles + pedometerEstimatedDistanceMiles
    }

    var routePingCount: Int {
        routePoints.count
    }

    var hasAdequateRouteCoverage: Bool {
        guard durationSeconds > 60 else { return true }
        let expectedPings = durationSeconds / 10.0
        let coverage = Double(routePingCount) / expectedPings
        return coverage > 0.3
    }
}
