import UserNotifications
import Foundation

nonisolated final class NotificationService: Sendable {
    static let shared = NotificationService()
    private init() {}

    @discardableResult
    func requestAuthorization() async -> Bool {
        do {
            return try await UNUserNotificationCenter.current()
                .requestAuthorization(options: [.alert, .sound, .badge])
        } catch {
            return false
        }
    }

    func scheduleRecurring() {
        scheduleMorningNudge()
        scheduleEveningStreakReminder()
        scheduleWeeklyReport()
    }

    func cancelRecurring() {
        UNUserNotificationCenter.current().removePendingNotificationRequests(
            withIdentifiers: ["morning_nudge", "evening_streak", "weekly_report"]
        )
    }

    func fireQuestVerified(title: String) {
        schedule(
            id: "verified_\(UUID().uuidString)",
            title: "Side Quest Verified! ✅",
            body: "\"\(title)\" was approved. XP rewarded!",
            delay: 2
        )
    }

    func fireStoryEvent() {
        schedule(
            id: "story_\(UUID().uuidString)",
            title: "A new chapter unfolds 📜",
            body: "Your campaign has progressed. Open the app to make your next choice.",
            delay: 1
        )
    }

    func fireModerationAvailable(count: Int) {
        schedule(
            id: "mod_\(UUID().uuidString)",
            title: "Moderation Needed ⚖️",
            body: "\(count) submission\(count == 1 ? "" : "s") await your review. Earn karma!",
            delay: 1
        )
    }

    private func schedule(id: String, title: String, body: String, delay: TimeInterval) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: delay, repeats: false)
        UNUserNotificationCenter.current().add(
            UNNotificationRequest(identifier: id, content: content, trigger: trigger)
        )
    }

    // MARK: - Focus Block Notifications

    func scheduleFocusBlockWarning(graceSeconds: Int) {
        let warningDelay = max(1, graceSeconds - 10)
        let warningContent = UNMutableNotificationContent()
        warningContent.title = "⚠️ Get Back Now!"
        warningContent.body = "You have 10 seconds before your focus challenge is lost!"
        warningContent.sound = .default
        warningContent.interruptionLevel = .timeSensitive
        let warningTrigger = UNTimeIntervalNotificationTrigger(timeInterval: TimeInterval(warningDelay), repeats: false)
        UNUserNotificationCenter.current().add(
            UNNotificationRequest(identifier: "focus_grace_warning", content: warningContent, trigger: warningTrigger)
        )

        let failContent = UNMutableNotificationContent()
        failContent.title = "Challenge Failed ❌"
        failContent.body = "You were away too long. Your focus block has been lost."
        failContent.sound = .default
        failContent.interruptionLevel = .timeSensitive
        let failTrigger = UNTimeIntervalNotificationTrigger(timeInterval: TimeInterval(graceSeconds), repeats: false)
        UNUserNotificationCenter.current().add(
            UNNotificationRequest(identifier: "focus_grace_fail", content: failContent, trigger: failTrigger)
        )
    }

    func scheduleFocusMilestoneWarnings(remainingSeconds: TimeInterval) {
        var milestones: [(delay: TimeInterval, label: String)] = []

        if remainingSeconds > 3600 {
            let delay = remainingSeconds - 3600
            if delay > 0 { milestones.append((delay, "1 hour remaining")) }
        }
        if remainingSeconds > 1800 {
            let delay = remainingSeconds - 1800
            if delay > 0 { milestones.append((delay, "30 minutes remaining")) }
        }
        if remainingSeconds > 600 {
            let delay = remainingSeconds - 600
            if delay > 0 { milestones.append((delay, "10 minutes remaining")) }
        }
        if remainingSeconds > 300 {
            let delay = remainingSeconds - 300
            if delay > 0 { milestones.append((delay, "5 minutes remaining")) }
        }
        if remainingSeconds > 60 {
            let delay = remainingSeconds - 60
            if delay > 0 { milestones.append((delay, "1 minute remaining")) }
        }

        for (index, milestone) in milestones.enumerated() {
            let content = UNMutableNotificationContent()
            content.title = "Focus Block ⏱️"
            content.body = "\(milestone.label) — stay focused!"
            content.sound = .default
            let trigger = UNTimeIntervalNotificationTrigger(timeInterval: milestone.delay, repeats: false)
            UNUserNotificationCenter.current().add(
                UNNotificationRequest(identifier: "focus_milestone_\(index)", content: content, trigger: trigger)
            )
        }
    }

    func scheduleFocusReminder(at date: Date, questTitle: String, instanceId: String) {
        let content = UNMutableNotificationContent()
        content.title = "Time to Focus 🔒"
        content.body = "Your scheduled \(questTitle) is starting now. Open the app to begin."
        content.sound = .default
        content.interruptionLevel = .timeSensitive
        let comps = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: date)
        let trigger = UNCalendarNotificationTrigger(dateMatching: comps, repeats: false)
        UNUserNotificationCenter.current().add(
            UNNotificationRequest(identifier: "focus_reminder_\(instanceId)", content: content, trigger: trigger)
        )
    }

    func cancelFocusReminder(instanceId: String) {
        UNUserNotificationCenter.current().removePendingNotificationRequests(
            withIdentifiers: ["focus_reminder_\(instanceId)"]
        )
    }

    func cancelFocusBlockNotifications() {
        var ids = ["focus_grace_warning", "focus_grace_fail"]
        for i in 0..<5 {
            ids.append("focus_milestone_\(i)")
        }
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: ids)
    }

    private func scheduleMorningNudge() {
        let content = UNMutableNotificationContent()
        content.title = "Your quests await 🛡️"
        content.body = "Start strong today. Even one quest keeps the streak alive."
        content.sound = .default
        var dc = DateComponents()
        dc.hour = 7
        dc.minute = 0
        UNUserNotificationCenter.current().add(
            UNNotificationRequest(
                identifier: "morning_nudge",
                content: content,
                trigger: UNCalendarNotificationTrigger(dateMatching: dc, repeats: true)
            )
        )
    }

    private func scheduleEveningStreakReminder() {
        let content = UNMutableNotificationContent()
        content.title = "Don't break your streak! 🔥"
        content.body = "Complete a quest before midnight to keep the fire going."
        content.sound = .default
        var dc = DateComponents()
        dc.hour = 20
        dc.minute = 0
        UNUserNotificationCenter.current().add(
            UNNotificationRequest(
                identifier: "evening_streak",
                content: content,
                trigger: UNCalendarNotificationTrigger(dateMatching: dc, repeats: true)
            )
        )
    }

    private func scheduleWeeklyReport() {
        let content = UNMutableNotificationContent()
        content.title = "Weekly Quest Report 📊"
        content.body = "Review your week and plan your next challenges. Every rep counts."
        content.sound = .default
        var dc = DateComponents()
        dc.weekday = 1
        dc.hour = 18
        dc.minute = 0
        UNUserNotificationCenter.current().add(
            UNNotificationRequest(
                identifier: "weekly_report",
                content: content,
                trigger: UNCalendarNotificationTrigger(dateMatching: dc, repeats: true)
            )
        )
    }
}
