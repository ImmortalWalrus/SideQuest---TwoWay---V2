import Foundation
import CoreMotion

@Observable
class StepCountService {
    private let pedometer: CMPedometer = CMPedometer()
    private(set) var stepsToday: Int = 0
    private(set) var stepsThisWeek: Int = 0
    private(set) var authorizationStatus: CMAuthorizationStatus = CMPedometer.authorizationStatus()

    var isAvailable: Bool {
        CMPedometer.isStepCountingAvailable()
    }

    var isAuthorized: Bool {
        authorizationStatus == .authorized
    }

    var needsSettings: Bool {
        authorizationStatus == .denied || authorizationStatus == .restricted
    }

    func refreshAuthorizationStatus() {
        authorizationStatus = CMPedometer.authorizationStatus()
    }

    func requestAuthorization() async -> Bool {
        guard isAvailable else { return false }
        refreshAuthorizationStatus()

        if isAuthorized {
            await fetchSteps()
            return true
        }

        if needsSettings {
            return false
        }

        let now = Date()
        let start = now.addingTimeInterval(-1)
        let granted = await withCheckedContinuation { continuation in
            pedometer.queryPedometerData(from: start, to: now) { [weak self] _, _ in
                Task { @MainActor [weak self] in
                    self?.refreshAuthorizationStatus()
                    continuation.resume(returning: self?.isAuthorized ?? false)
                }
            }
        }

        if granted {
            await fetchSteps()
        }

        return granted
    }

    func fetchSteps() async {
        refreshAuthorizationStatus()
        guard isAuthorized else {
            stepsToday = 0
            stepsThisWeek = 0
            return
        }

        let calendar = Calendar.current
        let now = Date()
        let todayStart = calendar.startOfDay(for: now)
        stepsToday = await querySteps(from: todayStart, to: now)

        if let weekStart = calendar.date(from: calendar.dateComponents([.yearForWeekOfYear, .weekOfYear], from: todayStart)) {
            stepsThisWeek = await querySteps(from: weekStart, to: now)
        }
    }

    func stepsInWindow(startHour: Int, startMinute: Int, endHour: Int, endMinute: Int) async -> Int {
        refreshAuthorizationStatus()
        guard isAuthorized else { return 0 }

        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        guard let start = calendar.date(bySettingHour: startHour, minute: startMinute, second: 0, of: today),
              let end = calendar.date(bySettingHour: endHour, minute: endMinute, second: 59, of: today) else { return 0 }

        let clampedEnd = min(end, Date())
        guard clampedEnd > start else { return 0 }
        return await querySteps(from: start, to: clampedEnd)
    }

    func stepsTodayLive() async -> Int {
        await fetchSteps()
        return stepsToday
    }

    private func querySteps(from start: Date, to end: Date) async -> Int {
        guard end >= start else { return 0 }
        return await withCheckedContinuation { continuation in
            pedometer.queryPedometerData(from: start, to: end) { data, _ in
                continuation.resume(returning: data?.numberOfSteps.intValue ?? 0)
            }
        }
    }
}
