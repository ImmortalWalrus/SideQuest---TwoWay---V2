import Foundation

nonisolated enum JourneyDurationType: String, Codable, Sendable, CaseIterable {
    case oneDay = "One Day"
    case sevenDays = "7 Days"
    case custom = "Custom Dates"
}

nonisolated enum JourneyMode: String, Codable, Sendable, CaseIterable {
    case solo = "Solo"
    case withFriends = "With Friends"

    var icon: String {
        switch self {
        case .solo: "person.fill"
        case .withFriends: "person.2.fill"
        }
    }
}

nonisolated enum JourneyVisibility: String, Codable, Sendable, CaseIterable {
    case privateJourney = "Private"
    case publicTemplate = "Public Template"

    var icon: String {
        switch self {
        case .privateJourney: "lock.fill"
        case .publicTemplate: "globe"
        }
    }
}

nonisolated enum JourneyStatus: String, Codable, Sendable {
    case active = "Active"
    case completed = "Completed"
    case cancelled = "Cancelled"
}

nonisolated enum JourneyVerificationMode: String, Codable, Sendable, CaseIterable {
    case verified = "Verified"
    case nonVerified = "Non-Verified"

    var icon: String {
        switch self {
        case .verified: "checkmark.seal.fill"
        case .nonVerified: "hand.thumbsup.fill"
        }
    }

    var description: String {
        switch self {
        case .verified: "Submit evidence for verified quests. Full XP, coins, and diamond rewards."
        case .nonVerified: "No evidence required. Rewards capped at intrinsic level — no coins or diamonds beyond intrinsic quests."
        }
    }
}

nonisolated enum JourneyQuestFrequency: String, Codable, Sendable, CaseIterable {
    case oneTime = "One-time"
    case daily = "Daily"
    case specificDays = "Specific Days"
}

nonisolated enum Weekday: String, Codable, Sendable, CaseIterable, Identifiable {
    case monday = "Mon"
    case tuesday = "Tue"
    case wednesday = "Wed"
    case thursday = "Thu"
    case friday = "Fri"
    case saturday = "Sat"
    case sunday = "Sun"

    var id: String { rawValue }

    var calendarIndex: Int {
        switch self {
        case .monday: 2
        case .tuesday: 3
        case .wednesday: 4
        case .thursday: 5
        case .friday: 6
        case .saturday: 7
        case .sunday: 1
        }
    }
}

nonisolated enum JourneyQuestStatus: String, Codable, Sendable {
    case notStarted = "Not Started"
    case active = "Active"
    case completed = "Completed"
    case verified = "Verified"
    case skipped = "Skipped"
}

nonisolated enum CalendarAlertOption: String, Codable, Sendable, CaseIterable {
    case none = "None"
    case fiveMin = "5 min before"
    case fifteenMin = "15 min before"
    case oneHour = "1 hour before"

    var seconds: TimeInterval? {
        switch self {
        case .none: nil
        case .fiveMin: -300
        case .fifteenMin: -900
        case .oneHour: -3600
        }
    }
}

nonisolated struct JourneyQuestItem: Identifiable, Codable, Sendable, Equatable {
    let id: String
    let questId: String
    var frequency: JourneyQuestFrequency
    var specificDays: [Weekday]
    var scheduledHour: Int?
    var scheduledMinute: Int?
    var isAnytime: Bool
    var questMode: QuestMode

    var hasSpecificTime: Bool {
        !isAnytime && scheduledHour != nil
    }

    var timeDescription: String {
        guard let hour = scheduledHour, let minute = scheduledMinute else { return "Anytime" }
        let h = hour % 12 == 0 ? 12 : hour % 12
        let ampm = hour < 12 ? "AM" : "PM"
        return String(format: "%d:%02d %@", h, minute, ampm)
    }
}

nonisolated struct JourneyDayProgress: Identifiable, Codable, Sendable {
    let id: String
    let date: Date
    var questStatuses: [String: JourneyQuestStatus]

    var completedCount: Int {
        questStatuses.values.filter { $0 == .completed || $0 == .verified }.count
    }

    var totalCount: Int {
        questStatuses.count
    }

    var completionPercent: Double {
        guard totalCount > 0 else { return 0 }
        return Double(completedCount) / Double(totalCount)
    }
}

nonisolated struct JourneyFriendProgress: Identifiable, Codable, Sendable {
    let id: String
    let friendId: String
    let username: String
    let avatarName: String
    var todayCompleted: Int
    var todayTotal: Int
    var overallPercent: Double
}

nonisolated struct Journey: Identifiable, Codable, Sendable {
    let id: String
    var name: String
    var durationType: JourneyDurationType
    var startDate: Date
    var endDate: Date
    var mode: JourneyMode
    var visibility: JourneyVisibility
    var status: JourneyStatus
    var questItems: [JourneyQuestItem]
    var dayProgress: [JourneyDayProgress]
    var calendarSyncEnabled: Bool
    var calendarAlert: CalendarAlertOption
    var calendarEventIds: [String: String]
    var friendProgress: [JourneyFriendProgress]
    var invitedFriendIds: [String]
    var templateId: String?
    var createdAt: Date
    var streakDays: Int
    var verificationMode: JourneyVerificationMode
    var difficulty: QuestDifficulty
    var campaignBaseXPEarned: Int
    var completionBonusAwarded: Bool
    var earlyBonusAwarded: Bool

    var totalDays: Int {
        let cal = Calendar.current
        let days = cal.dateComponents([.day], from: cal.startOfDay(for: startDate), to: cal.startOfDay(for: endDate)).day ?? 0
        return max(1, days + 1)
    }

    var daysRemaining: Int {
        let cal = Calendar.current
        let today = cal.startOfDay(for: Date())
        let end = cal.startOfDay(for: endDate)
        let remaining = cal.dateComponents([.day], from: today, to: end).day ?? 0
        return max(0, remaining + 1)
    }

    var currentDay: Int {
        let cal = Calendar.current
        let start = cal.startOfDay(for: startDate)
        let today = cal.startOfDay(for: Date())
        let elapsed = cal.dateComponents([.day], from: start, to: today).day ?? 0
        return min(max(1, elapsed + 1), totalDays)
    }

    var overallCompletionPercent: Double {
        guard !dayProgress.isEmpty else { return 0 }
        let total = dayProgress.reduce(0) { $0 + $1.totalCount }
        let completed = dayProgress.reduce(0) { $0 + $1.completedCount }
        guard total > 0 else { return 0 }
        return Double(completed) / Double(total)
    }

    var todayProgress: JourneyDayProgress? {
        let cal = Calendar.current
        let today = cal.startOfDay(for: Date())
        return dayProgress.first { cal.isDate($0.date, inSameDayAs: today) }
    }

    var todayTaskCount: Int {
        todayProgress?.totalCount ?? scheduledQuestsForDate(Date()).count
    }

    var isActive: Bool { status == .active }
    var isCompleted: Bool { status == .completed }

    var completionBonusXP: Int {
        XPGuardrails.campaignCompletionBonus(difficulty: difficulty, baseXP: campaignBaseXPEarned)
    }

    var earlyCompletionBonusXP: Int {
        XPGuardrails.campaignEarlyCompletionBonus(difficulty: difficulty, baseXP: campaignBaseXPEarned)
    }

    var isCompletedEarly: Bool {
        guard status == .completed else { return false }
        let cal = Calendar.current
        let today = cal.startOfDay(for: Date())
        let end = cal.startOfDay(for: endDate)
        return today < end
    }

    func scheduledQuestsForDate(_ date: Date) -> [JourneyQuestItem] {
        let cal = Calendar.current
        let weekday = cal.component(.weekday, from: date)
        return questItems.filter { item in
            switch item.frequency {
            case .oneTime:
                return cal.isDate(date, inSameDayAs: startDate)
            case .daily:
                return true
            case .specificDays:
                return item.specificDays.contains { $0.calendarIndex == weekday }
            }
        }
    }

    func isQuestScheduledOnDate(_ questItemId: String, date: Date) -> Bool {
        guard let item = questItems.first(where: { $0.id == questItemId }) else { return false }
        let cal = Calendar.current
        let weekday = cal.component(.weekday, from: date)
        switch item.frequency {
        case .oneTime:
            return cal.isDate(date, inSameDayAs: startDate)
        case .daily:
            return true
        case .specificDays:
            return item.specificDays.contains { $0.calendarIndex == weekday }
        }
    }

    func questStatusForDate(_ questItemId: String, date: Date) -> JourneyQuestStatus {
        let cal = Calendar.current
        guard let dp = dayProgress.first(where: { cal.isDate($0.date, inSameDayAs: date) }) else {
            return .notStarted
        }
        return dp.questStatuses[questItemId] ?? .notStarted
    }
}

nonisolated struct JourneyTemplate: Identifiable, Codable, Sendable {
    let id: String
    let authorUsername: String
    let authorAvatarName: String
    var title: String
    var description: String
    var difficulty: QuestDifficulty
    var defaultDurationDays: Int
    var questItems: [JourneyQuestItem]
    var timesAreRecommended: Bool
    var joinCount: Int
    var rating: Double
    var createdAt: Date

    var questCount: Int { questItems.count }
}
