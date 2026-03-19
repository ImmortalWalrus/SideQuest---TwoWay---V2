import Foundation
import CoreLocation
import CoreMotion

@Observable
class LocationTrackingService: NSObject, CLLocationManagerDelegate {
    private let manager = CLLocationManager()
    private let pedometer = CMPedometer()
    private let motionManager = CMMotionActivityManager()

    private(set) var isTracking: Bool = false
    private(set) var isPaused: Bool = false
    private(set) var currentLocation: CLLocation?
    private(set) var routePoints: [RoutePoint] = []
    private(set) var distanceMiles: Double = 0
    private(set) var elapsedSeconds: TimeInterval = 0
    private(set) var totalPauseSeconds: TimeInterval = 0
    private(set) var goalReached: Bool = false
    private(set) var locationAuthorized: Bool = false
    private(set) var isDisqualified: Bool = false
    private(set) var disqualificationReason: String?
    private(set) var timeLimitRemaining: TimeInterval?
    private(set) var timeLimitExpired: Bool = false
    private(set) var currentSpeedMph: Double = 0
    private(set) var speedWarningActive: Bool = false
    private(set) var pedometerEstimatedDistanceMiles: Double = 0
    private(set) var sessionSteps: Int = 0
    private(set) var gpsGapCount: Int = 0
    private(set) var isUsingPedometerFallback: Bool = false
    var integrityFlags: Set<IntegrityFlag> = []

    private var startTime: Date?
    private var pauseStartTime: Date?
    private var lastValidLocation: CLLocation?
    private var firstValidLocation: CLLocation?
    private var timer: Timer?
    private var targetDistanceMiles: Double = 0
    private var maxPauseMinutes: Int = 3
    private var maxSpeedMph: Double = 18.0
    private var timeLimitSeconds: TimeInterval?

    private var recentSpeeds: [SpeedSample] = []
    private var consecutiveHighSpeedCount: Int = 0
    private var totalSpeedViolations: Int = 0
    private var maxRecordedSpeed: Double = 0
    private(set) var startCheckpoint: TimeCheckpoint?
    private var uptimeAtStart: TimeInterval = 0

    private let sustainedSpeedThreshold: Int = 5
    private let speedWindowDuration: TimeInterval = 30
    private var vehicleSpeedFloor: Double = 20.0
    private let warningSpeedBuffer: Double = 3.0

    private var pedometerSegments: [PedometerSegment] = []
    private var lastGPSTimestamp: Date?
    private let gpsGapThreshold: TimeInterval = 15
    private var gapStartDate: Date?
    private var gapPedometerStartSteps: Int?
    private var cumulativePedometerSteps: Int = 0
    private var strideLength: Double = 0.75

    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyBest
        manager.distanceFilter = 5
        manager.activityType = .fitness
        manager.allowsBackgroundLocationUpdates = false
        locationAuthorized = [.authorizedWhenInUse, .authorizedAlways].contains(manager.authorizationStatus)
    }

    func configure(targetDistance: Double, maxPause: Int, maxSpeed: Double, timeLimit: TimeInterval? = nil) {
        targetDistanceMiles = targetDistance
        maxPauseMinutes = maxPause
        maxSpeedMph = maxSpeed
        timeLimitSeconds = timeLimit
        if maxSpeed > 15 {
            strideLength = 1.2
        }
        if maxSpeed > 20 {
            vehicleSpeedFloor = maxSpeed + 10
        } else {
            vehicleSpeedFloor = 20.0
        }
    }

    func requestPermission() {
        manager.requestWhenInUseAuthorization()
    }

    func startTracking() {
        isTracking = true
        isPaused = false
        startTime = Date()
        startCheckpoint = TimeIntegrityService.shared.recordCheckpoint()
        uptimeAtStart = ProcessInfo.processInfo.systemUptime
        routePoints = []
        distanceMiles = 0
        elapsedSeconds = 0
        totalPauseSeconds = 0
        integrityFlags = []
        goalReached = false
        isDisqualified = false
        disqualificationReason = nil
        timeLimitExpired = false
        timeLimitRemaining = timeLimitSeconds
        currentSpeedMph = 0
        speedWarningActive = false
        lastValidLocation = nil
        firstValidLocation = nil
        recentSpeeds = []
        consecutiveHighSpeedCount = 0
        totalSpeedViolations = 0
        maxRecordedSpeed = 0
        pedometerSegments = []
        pedometerEstimatedDistanceMiles = 0
        sessionSteps = 0
        gpsGapCount = 0
        isUsingPedometerFallback = false
        lastGPSTimestamp = nil
        gapStartDate = nil
        gapPedometerStartSteps = nil
        cumulativePedometerSteps = 0
        manager.startUpdatingLocation()
        startPedometerTracking()
        startTimer()
    }

    func pauseTracking() {
        isPaused = true
        pauseStartTime = Date()
        manager.stopUpdatingLocation()
        stopTimer()
    }

    func resumeTracking() {
        if let pauseStart = pauseStartTime {
            totalPauseSeconds += Date().timeIntervalSince(pauseStart)
        }
        pauseStartTime = nil
        isPaused = false
        manager.startUpdatingLocation()
        startTimer()
    }

    func endTracking() -> TrackingSession {
        isTracking = false
        isPaused = false
        manager.stopUpdatingLocation()
        stopTimer()
        stopPedometerTracking()
        finalizeGPSGap()

        if let pauseStart = pauseStartTime {
            totalPauseSeconds += Date().timeIntervalSince(pauseStart)
            pauseStartTime = nil
        }

        if maxPauseMinutes > 0 && totalPauseSeconds > Double(maxPauseMinutes * 60) {
            integrityFlags.insert(.excessivePause)
        }

        let totalDist = distanceMiles + pedometerEstimatedDistanceMiles
        if elapsedSeconds < 60 && totalDist >= targetDistanceMiles && targetDistanceMiles > 0 {
            integrityFlags.insert(.sessionTooShort)
        }

        if timeLimitExpired {
            integrityFlags.insert(.timeLimitExpired)
        }

        var timeVerified: Bool? = nil
        if let cp = startCheckpoint {
            let result = TimeIntegrityService.shared.verifySessionDuration(startCheckpoint: cp, endWallClock: Date())
            timeVerified = result.isValid
            if !result.isValid {
                integrityFlags.insert(.clockManipulated)
            }
        }

        let loopClosure = computeLoopClosure()
        let continuity = computeRouteContinuity()

        return TrackingSession(
            id: UUID().uuidString,
            routePoints: routePoints,
            startedAt: startTime,
            endedAt: Date(),
            distanceMiles: distanceMiles,
            durationSeconds: elapsedSeconds,
            totalPauseSeconds: totalPauseSeconds,
            integrityFlags: Array(integrityFlags),
            speedViolationCount: totalSpeedViolations,
            maxRecordedSpeedMph: maxRecordedSpeed,
            wasDisqualified: isDisqualified,
            startCheckpoint: startCheckpoint,
            timeIntegrityVerified: timeVerified,
            pedometerSegments: pedometerSegments,
            pedometerEstimatedDistanceMiles: pedometerEstimatedDistanceMiles,
            sessionSteps: sessionSteps,
            gpsGapCount: gpsGapCount,
            routeContinuityScore: continuity,
            isLoopCompleted: loopClosure != nil && loopClosure! < 200,
            loopClosureDistanceMeters: loopClosure
        )
    }

    // MARK: - Pedometer Fallback

    private func startPedometerTracking() {
        guard CMPedometer.isStepCountingAvailable() else { return }
        guard let start = startTime else { return }
        pedometer.startUpdates(from: start) { [weak self] data, _ in
            guard let data else { return }
            Task { @MainActor [weak self] in
                self?.handlePedometerUpdate(data)
            }
        }
    }

    private func stopPedometerTracking() {
        pedometer.stopUpdates()
    }

    private func handlePedometerUpdate(_ data: CMPedometerData) {
        let steps = data.numberOfSteps.intValue
        cumulativePedometerSteps = steps
        sessionSteps = steps
    }

    private func checkGPSGap() {
        guard let lastGPS = lastGPSTimestamp else { return }
        let gap = Date().timeIntervalSince(lastGPS)
        if gap > gpsGapThreshold && gapStartDate == nil {
            gapStartDate = lastGPS
            gapPedometerStartSteps = cumulativePedometerSteps
            gpsGapCount += 1
            isUsingPedometerFallback = true
        }
    }

    private func resolveGPSGap(newLocation: CLLocation) {
        guard let gapStart = gapStartDate,
              let startSteps = gapPedometerStartSteps else { return }
        let gapEnd = newLocation.timestamp
        let stepsInGap = max(0, cumulativePedometerSteps - startSteps)
        let estimatedMeters = Double(stepsInGap) * strideLength
        let estimatedMiles = estimatedMeters / 1609.34

        if stepsInGap > 0 {
            let segment = PedometerSegment(
                startDate: gapStart,
                endDate: gapEnd,
                steps: stepsInGap,
                estimatedDistanceMeters: estimatedMeters,
                reason: "GPS signal lost"
            )
            pedometerSegments.append(segment)
            pedometerEstimatedDistanceMiles += estimatedMiles
        }

        gapStartDate = nil
        gapPedometerStartSteps = nil
        isUsingPedometerFallback = false
    }

    private func finalizeGPSGap() {
        guard let gapStart = gapStartDate,
              let startSteps = gapPedometerStartSteps else { return }
        let stepsInGap = max(0, cumulativePedometerSteps - startSteps)
        let estimatedMeters = Double(stepsInGap) * strideLength
        let estimatedMiles = estimatedMeters / 1609.34

        if stepsInGap > 0 {
            let segment = PedometerSegment(
                startDate: gapStart,
                endDate: Date(),
                steps: stepsInGap,
                estimatedDistanceMeters: estimatedMeters,
                reason: "GPS signal lost until session end"
            )
            pedometerSegments.append(segment)
            pedometerEstimatedDistanceMiles += estimatedMiles
        }

        gapStartDate = nil
        gapPedometerStartSteps = nil
        isUsingPedometerFallback = false
    }

    // MARK: - Loop Detection

    private func computeLoopClosure() -> Double? {
        guard let first = firstValidLocation,
              let last = lastValidLocation else { return nil }
        guard routePoints.count >= 5 else { return nil }
        return last.distance(from: first)
    }

    // MARK: - Route Continuity

    private func computeRouteContinuity() -> Double {
        guard elapsedSeconds > 60 else { return 1.0 }
        let expectedPings = elapsedSeconds / 10.0
        let actualPings = Double(routePoints.count)
        let pedometerCoverage = pedometerSegments.reduce(0.0) { $0 + $1.endDate.timeIntervalSince($1.startDate) } / 10.0
        let totalCoverage = (actualPings + pedometerCoverage) / expectedPings
        return min(1.0, totalCoverage)
    }

    // MARK: - Timer

    private func startTimer() {
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            Task { @MainActor [self] in
                self?.tickTimer()
            }
        }
    }

    private func tickTimer() {
        guard let start = startTime else { return }
        var pause = totalPauseSeconds
        if let pauseStart = pauseStartTime {
            pause += Date().timeIntervalSince(pauseStart)
        }

        let wallElapsed = Date().timeIntervalSince(start) - pause
        let monotonicElapsed = ProcessInfo.processInfo.systemUptime - uptimeAtStart
        let drift = abs(wallElapsed - monotonicElapsed)
        if drift > 10 && !integrityFlags.contains(.clockManipulated) {
            integrityFlags.insert(.clockManipulated)
            disqualify(reason: "Clock manipulation detected")
            return
        }

        elapsedSeconds = wallElapsed

        if let limit = timeLimitSeconds {
            let remaining = limit - elapsedSeconds
            timeLimitRemaining = max(0, remaining)
            if remaining <= 0 && !timeLimitExpired && !goalReached {
                timeLimitExpired = true
                disqualify(reason: "Time limit expired")
            }
        }

        checkGPSGap()

        let totalDist = distanceMiles + pedometerEstimatedDistanceMiles
        if totalDist >= targetDistanceMiles && targetDistanceMiles > 0 && !goalReached {
            goalReached = true
        }
    }

    private func stopTimer() {
        timer?.invalidate()
        timer = nil
    }

    // MARK: - Location Processing

    private func processLocation(_ location: CLLocation) {
        guard !isDisqualified else { return }
        guard location.horizontalAccuracy >= 0 else { return }

        if location.horizontalAccuracy > 50 {
            integrityFlags.insert(.weakGPS)
            return
        }

        if gapStartDate != nil {
            resolveGPSGap(newLocation: location)
        }

        lastGPSTimestamp = location.timestamp
        currentLocation = location

        let point = RoutePoint(
            latitude: location.coordinate.latitude,
            longitude: location.coordinate.longitude,
            timestamp: location.timestamp,
            accuracy: location.horizontalAccuracy,
            speed: max(0, location.speed)
        )
        routePoints.append(point)

        if firstValidLocation == nil {
            firstValidLocation = location
        }

        if let last = lastValidLocation {
            let delta = location.distance(from: last)
            let timeDelta = location.timestamp.timeIntervalSince(last.timestamp)

            guard timeDelta > 0 else {
                lastValidLocation = location
                return
            }

            let speedMps = delta / timeDelta
            let speedMph = speedMps * 2.237

            if speedMph > 0 {
                maxRecordedSpeed = max(maxRecordedSpeed, speedMph)
            }

            currentSpeedMph = speedMph

            if delta > 500 && timeDelta < 5 {
                integrityFlags.insert(.teleportDetected)
                disqualify(reason: "GPS teleport detected — location jumped impossibly far")
                return
            }

            let sample = SpeedSample(speed: speedMph, timestamp: location.timestamp)
            recentSpeeds.append(sample)
            pruneOldSamples(before: location.timestamp)

            if speedMph > maxSpeedMph {
                totalSpeedViolations += 1
                consecutiveHighSpeedCount += 1

                if speedMph > vehicleSpeedFloor {
                    integrityFlags.insert(.carSpeedDetected)
                    disqualify(reason: "Vehicle speed detected (\(Int(speedMph)) mph)")
                    return
                }

                if consecutiveHighSpeedCount >= sustainedSpeedThreshold {
                    integrityFlags.insert(.sustainedDriving)
                    disqualify(reason: "Sustained vehicle speed detected over \(Int(speedWindowDuration))s")
                    return
                }

                let avgWindowSpeed = rollingAverageSpeed()
                if avgWindowSpeed > maxSpeedMph && recentSpeeds.count >= 3 {
                    integrityFlags.insert(.sustainedDriving)
                    disqualify(reason: "Average speed too high (\(Int(avgWindowSpeed)) mph)")
                    return
                }

                speedWarningActive = true
            } else {
                consecutiveHighSpeedCount = max(0, consecutiveHighSpeedCount - 1)
                speedWarningActive = speedMph > (maxSpeedMph - warningSpeedBuffer)
                distanceMiles += delta / 1609.34
            }

            let totalDist = distanceMiles + pedometerEstimatedDistanceMiles
            if totalDist >= targetDistanceMiles && targetDistanceMiles > 0 && !goalReached {
                goalReached = true
            }
        }

        lastValidLocation = location
    }

    private func pruneOldSamples(before now: Date) {
        let cutoff = now.addingTimeInterval(-speedWindowDuration)
        recentSpeeds.removeAll { $0.timestamp < cutoff }
    }

    private func rollingAverageSpeed() -> Double {
        guard !recentSpeeds.isEmpty else { return 0 }
        let total = recentSpeeds.reduce(0.0) { $0 + $1.speed }
        return total / Double(recentSpeeds.count)
    }

    private func disqualify(reason: String) {
        isDisqualified = true
        disqualificationReason = reason
        manager.stopUpdatingLocation()
        stopTimer()
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        Task { @MainActor in
            for location in locations {
                self.processLocation(location)
            }
        }
    }

    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        let status = manager.authorizationStatus
        Task { @MainActor in
            self.locationAuthorized = [.authorizedWhenInUse, .authorizedAlways].contains(status)
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {}
}

private struct SpeedSample {
    let speed: Double
    let timestamp: Date
}
