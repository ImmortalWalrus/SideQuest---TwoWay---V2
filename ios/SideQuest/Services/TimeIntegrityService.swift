import Foundation

nonisolated struct TimeCheckpoint: Codable, Sendable {
    let wallClock: Date
    let uptime: TimeInterval
}

nonisolated enum TimeViolationType: String, Codable, Sendable {
    case clockJumpForward
    case clockJumpBackward
    case ntpMismatch
    case uptimeMismatch

    var isCritical: Bool {
        switch self {
        case .clockJumpForward, .clockJumpBackward, .uptimeMismatch:
            return true
        case .ntpMismatch:
            return false
        }
    }
}

nonisolated struct TimeViolation: Codable, Sendable {
    let type: TimeViolationType
    let detectedAt: Date
    let uptimeAtDetection: TimeInterval
    let wallClockDelta: TimeInterval
    let uptimeDelta: TimeInterval
}

@Observable
class TimeIntegrityService {
    private(set) var violations: [TimeViolation] = []
    private(set) var lastCheckpoint: TimeCheckpoint?
    private(set) var ntpOffset: TimeInterval?
    private(set) var hasTimeManipulation: Bool = false
    private var monitorTimer: Timer?

    private static let driftToleranceSeconds: TimeInterval = 5.0
    private static let ntpToleranceSeconds: TimeInterval = 30.0
    private static let checkIntervalSeconds: TimeInterval = 10.0
    private static let ntpHost = "time.apple.com"

    static let shared = TimeIntegrityService()

    func start() {
        recordCheckpoint()
        fetchNTPOffset()
        monitorTimer?.invalidate()
        monitorTimer = Timer.scheduledTimer(withTimeInterval: Self.checkIntervalSeconds, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.performIntegrityCheck()
            }
        }
    }

    func stop() {
        monitorTimer?.invalidate()
        monitorTimer = nil
    }

    func recordCheckpoint() -> TimeCheckpoint {
        let cp = TimeCheckpoint(
            wallClock: Date(),
            uptime: ProcessInfo.processInfo.systemUptime
        )
        lastCheckpoint = cp
        return cp
    }

    func performIntegrityCheck() {
        guard let prev = lastCheckpoint else {
            _ = recordCheckpoint()
            return
        }

        let now = Date()
        let currentUptime = ProcessInfo.processInfo.systemUptime

        let wallDelta = now.timeIntervalSince(prev.wallClock)
        let uptimeDelta = currentUptime - prev.uptime

        let drift = wallDelta - uptimeDelta

        if drift > Self.driftToleranceSeconds {
            let violation = TimeViolation(
                type: .clockJumpForward,
                detectedAt: now,
                uptimeAtDetection: currentUptime,
                wallClockDelta: wallDelta,
                uptimeDelta: uptimeDelta
            )
            violations.append(violation)
            hasTimeManipulation = true
        } else if drift < -Self.driftToleranceSeconds {
            let violation = TimeViolation(
                type: .clockJumpBackward,
                detectedAt: now,
                uptimeAtDetection: currentUptime,
                wallClockDelta: wallDelta,
                uptimeDelta: uptimeDelta
            )
            violations.append(violation)
            hasTimeManipulation = true
        }

        _ = recordCheckpoint()
    }

    func verifySessionDuration(startCheckpoint: TimeCheckpoint, endWallClock: Date) -> (isValid: Bool, violation: TimeViolation?) {
        let endUptime = ProcessInfo.processInfo.systemUptime

        let wallDelta = endWallClock.timeIntervalSince(startCheckpoint.wallClock)
        let uptimeDelta = endUptime - startCheckpoint.uptime

        let drift = abs(wallDelta - uptimeDelta)

        if drift > Self.driftToleranceSeconds {
            let type: TimeViolationType = wallDelta > uptimeDelta ? .clockJumpForward : .clockJumpBackward
            let violation = TimeViolation(
                type: type,
                detectedAt: endWallClock,
                uptimeAtDetection: endUptime,
                wallClockDelta: wallDelta,
                uptimeDelta: uptimeDelta
            )
            violations.append(violation)
            hasTimeManipulation = true
            return (false, violation)
        }

        return (true, nil)
    }

    func verifyElapsedTime(startCheckpoint: TimeCheckpoint, claimedDurationSeconds: TimeInterval) -> Bool {
        let currentUptime = ProcessInfo.processInfo.systemUptime
        let actualElapsed = currentUptime - startCheckpoint.uptime
        let drift = abs(claimedDurationSeconds - actualElapsed)
        return drift <= Self.driftToleranceSeconds
    }

    func currentMonotonicTime() -> TimeInterval {
        ProcessInfo.processInfo.systemUptime
    }

    func resetViolations() {
        violations = []
        hasTimeManipulation = false
    }

    private func fetchNTPOffset() {
        Task.detached { [weak self] in
            guard let offset = await self?.queryNTP() else { return }
            await MainActor.run {
                self?.ntpOffset = offset
                if abs(offset) > TimeIntegrityService.ntpToleranceSeconds {
                    let violation = TimeViolation(
                        type: .ntpMismatch,
                        detectedAt: Date(),
                        uptimeAtDetection: ProcessInfo.processInfo.systemUptime,
                        wallClockDelta: offset,
                        uptimeDelta: 0
                    )
                    self?.violations.append(violation)
                }
            }
        }
    }

    nonisolated private func queryNTP() async -> TimeInterval? {
        let ntpEpochOffset: TimeInterval = 2208988800
        let serverPort: UInt16 = 123
        let packetSize = 48

        guard let hostEntry = Self.ntpHost.withCString({ gethostbyname($0) }),
              hostEntry.pointee.h_length > 0 else {
            return nil
        }

        let sock = socket(AF_INET, SOCK_DGRAM, IPPROTO_UDP)
        guard sock >= 0 else { return nil }
        defer { close(sock) }

        var timeout = timeval(tv_sec: 3, tv_usec: 0)
        setsockopt(sock, SOL_SOCKET, SO_RCVTIMEO, &timeout, socklen_t(MemoryLayout<timeval>.size))
        setsockopt(sock, SOL_SOCKET, SO_SNDTIMEO, &timeout, socklen_t(MemoryLayout<timeval>.size))

        var addr = sockaddr_in()
        addr.sin_family = sa_family_t(AF_INET)
        addr.sin_port = serverPort.bigEndian
        memcpy(&addr.sin_addr, hostEntry.pointee.h_addr_list[0]!, Int(hostEntry.pointee.h_length))

        var packet = [UInt8](repeating: 0, count: packetSize)
        packet[0] = 0x1B

        let sendTime = Date()

        let sent = withUnsafePointer(to: &addr) { ptr in
            ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) { sockPtr in
                sendto(sock, &packet, packetSize, 0, sockPtr, socklen_t(MemoryLayout<sockaddr_in>.size))
            }
        }
        guard sent == packetSize else { return nil }

        var response = [UInt8](repeating: 0, count: packetSize)
        let received = recv(sock, &response, packetSize, 0)
        let receiveTime = Date()

        guard received >= packetSize else { return nil }

        let txSeconds = UInt32(response[40]) << 24 | UInt32(response[41]) << 16 |
                        UInt32(response[42]) << 8  | UInt32(response[43])
        let txFraction = UInt32(response[44]) << 24 | UInt32(response[45]) << 16 |
                         UInt32(response[46]) << 8  | UInt32(response[47])

        let serverTime = Double(txSeconds) - ntpEpochOffset + Double(txFraction) / Double(UInt32.max)
        let roundTrip = receiveTime.timeIntervalSince(sendTime)
        let estimatedServerNow = serverTime + (roundTrip / 2.0)
        let localNow = receiveTime.timeIntervalSince1970

        return localNow - estimatedServerNow
    }
}
