import Foundation

nonisolated enum QuestPath: String, CaseIterable, Identifiable, Codable, Sendable {
    case warrior = "Warrior"
    case explorer = "Explorer"
    case mind = "Mind"

    var id: String { rawValue }

    var iconName: String {
        switch self {
        case .warrior: "flame.fill"
        case .explorer: "map.fill"
        case .mind: "brain.head.profile.fill"
        }
    }
}

nonisolated enum QuestDifficulty: String, CaseIterable, Codable, Sendable {
    case easy = "Easy"
    case medium = "Medium"
    case hard = "Hard"
    case expert = "Expert"

    var multiplier: Double {
        switch self {
        case .easy: 1.0
        case .medium: 1.5
        case .hard: 2.5
        case .expert: 4.0
        }
    }
}

nonisolated enum QuestType: String, CaseIterable, Codable, Sendable {
    case verified = "Verified"
    case open = "Open"
    case master = "Master"
    case event = "Event"
}

nonisolated enum SunEventType: String, Codable, Sendable {
    case sunrise = "Sunrise"
    case sunset = "Sunset"
}

nonisolated enum EvidenceType: String, Codable, Sendable {
    case video = "Video"
    case dualPhoto = "Dual Photo"
    case gpsTracking = "GPS Tracking"
    case pushUpTracking = "Push-Up Tracking"
    case plankTracking = "Plank Tracking"
    case wallSitTracking = "Wall Sit Tracking"
    case gratitudePhoto = "Handwritten Photo"
    case stepTracking = "Step Tracking"
    case meditationTracking = "Meditation Tracking"
    case focusTracking = "Focus Tracking"
    case affirmationPhoto = "Affirmation Photo"
    case placeVerification = "Place Verification"
    case readingTracking = "Reading Tracking"
    case jumpRopeTracking = "Jump Rope Tracking"

    nonisolated init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let rawValue = try container.decode(String.self)

        switch rawValue {
        case EvidenceType.video.rawValue, "timelapse", "Timelapse":
            self = .video
        case EvidenceType.dualPhoto.rawValue:
            self = .dualPhoto
        case EvidenceType.gpsTracking.rawValue:
            self = .gpsTracking
        case EvidenceType.pushUpTracking.rawValue:
            self = .pushUpTracking
        case EvidenceType.plankTracking.rawValue:
            self = .plankTracking
        case EvidenceType.wallSitTracking.rawValue:
            self = .wallSitTracking
        case EvidenceType.gratitudePhoto.rawValue:
            self = .gratitudePhoto
        case EvidenceType.stepTracking.rawValue:
            self = .stepTracking
        case EvidenceType.meditationTracking.rawValue:
            self = .meditationTracking
        case EvidenceType.focusTracking.rawValue:
            self = .focusTracking
        case EvidenceType.affirmationPhoto.rawValue:
            self = .affirmationPhoto
        case EvidenceType.placeVerification.rawValue:
            self = .placeVerification
        case EvidenceType.readingTracking.rawValue:
            self = .readingTracking
        case EvidenceType.jumpRopeTracking.rawValue:
            self = .jumpRopeTracking
        default:
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "Unknown evidence type: \(rawValue)")
        }
    }

    nonisolated func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }
}

nonisolated struct Quest: Identifiable, Hashable, Codable, Sendable {
    let id: String
    let title: String
    let description: String
    let path: QuestPath
    let difficulty: QuestDifficulty
    let type: QuestType
    let evidenceType: EvidenceType?
    let xpReward: Int
    let goldReward: Int
    let diamondReward: Int
    let milestoneIds: [String]
    let minCompletionMinutes: Int
    let isRepeatable: Bool
    let requiresUniqueLocation: Bool
    let isFeatured: Bool
    let featuredExpiresAt: Date?
    let completionCount: Int
    var authorUsername: String? = nil
    var targetDistanceMiles: Double? = nil
    var maxPauseMinutes: Int = 3
    var maxSpeedMph: Double = 18.0
    var timeWindowStartHour: Int? = nil
    var timeWindowEndHour: Int? = nil
    var timeWindowGraceMinutes: Int = 15
    var isExtreme: Bool = false
    var timeLimitSeconds: TimeInterval? = nil
    var targetReps: Int? = nil
    var targetHoldSeconds: TimeInterval? = nil
    var sunEventType: SunEventType? = nil
    var timeWindowStartMinuteOfDay: Int? = nil
    var timeWindowEndMinuteOfDay: Int? = nil
    var targetSteps: Int? = nil
    var cooldownDays: Int = 1
    var targetFocusMinutes: Int? = nil
    var maxTotalPauseSeconds: Int? = nil
    var maxPauseCount: Int? = nil
    var skillTags: [UserSkill] = []
    var interestTags: [UserInterest] = []
    var requiredPlaceType: VerifiedPlaceType? = nil
    var presenceMinutes: Int? = nil
    var hasExpertFocusChallenge: Bool = false
    var expertFocusMinutes: Int? = nil
    var verificationLatitude: Double? = nil
    var verificationLongitude: Double? = nil
    var verificationVenueName: String? = nil
    var verificationAddressText: String? = nil
    var externalEventIconName: String? = nil

    var effectivePresenceMinutes: Int {
        if let override = presenceMinutes { return override }
        return requiredPlaceType?.presenceTimerMinutes ?? 5
    }

    var isTrackingQuest: Bool {
        evidenceType == .gpsTracking
    }

    var isPoseTrackingQuest: Bool {
        evidenceType == .pushUpTracking || evidenceType == .plankTracking || evidenceType == .wallSitTracking || evidenceType == .jumpRopeTracking
    }

    var isJumpRopeQuest: Bool {
        evidenceType == .jumpRopeTracking
    }

    var isMeditationQuest: Bool {
        evidenceType == .meditationTracking
    }

    var isStepQuest: Bool {
        evidenceType == .stepTracking
    }

    var isGratitudeQuest: Bool {
        evidenceType == .gratitudePhoto
    }

    var isFocusQuest: Bool {
        evidenceType == .focusTracking
    }

    var isAffirmationQuest: Bool {
        evidenceType == .affirmationPhoto
    }

    var isPlaceVerificationQuest: Bool {
        evidenceType == .placeVerification
    }

    var isLocationDependent: Bool {
        if evidenceType == .placeVerification { return true }
        if requiresUniqueLocation { return true }
        if requiredPlaceType != nil { return true }
        if isTrailQuest || isBikeQuest { return true }
        return false
    }

    var isReadingQuest: Bool {
        evidenceType == .readingTracking
    }

    var isTrailQuest: Bool {
        id.hasPrefix("tr_") || id == "e3" || id == "t3"
    }

    var isBikeQuest: Bool {
        id.hasPrefix("bk_")
    }

    var trailMapCategory: MapQuestCategory? {
        if isTrailQuest { return .trail }
        if isBikeQuest { return .bikePath }
        return nil
    }

    var isTimedChallenge: Bool {
        isExtreme && timeLimitSeconds != nil
    }

    var timeLimitDescription: String? {
        guard let limit = timeLimitSeconds else { return nil }
        let minutes = Int(limit) / 60
        let seconds = Int(limit) % 60
        if seconds == 0 {
            return "\(minutes) min"
        }
        return "\(minutes):\(String(format: "%02d", seconds))"
    }

    var isSunEventQuest: Bool {
        sunEventType != nil
    }

    var hasTimeWindow: Bool {
        effectiveStartMinuteOfDay != nil && effectiveEndMinuteOfDay != nil
    }

    var effectiveStartMinuteOfDay: Int? {
        if let m = timeWindowStartMinuteOfDay { return m }
        if let h = timeWindowStartHour { return h * 60 }
        return nil
    }

    var effectiveEndMinuteOfDay: Int? {
        if let m = timeWindowEndMinuteOfDay { return m }
        if let h = timeWindowEndHour { return h * 60 }
        return nil
    }

    var isWithinTimeWindow: Bool {
        guard let startMin = effectiveStartMinuteOfDay, let endMin = effectiveEndMinuteOfDay else { return true }
        let now = Calendar.current.dateComponents([.hour, .minute], from: Date())
        guard let hour = now.hour, let minute = now.minute else { return true }
        let currentMinutes = hour * 60 + minute
        let endWithGrace = endMin + timeWindowGraceMinutes
        if startMin <= endWithGrace {
            return currentMinutes >= startMin && currentMinutes <= endWithGrace
        } else {
            return currentMinutes >= startMin || currentMinutes <= endWithGrace
        }
    }

    var timeWindowDescription: String? {
        guard let startMin = effectiveStartMinuteOfDay, let endMin = effectiveEndMinuteOfDay else { return nil }
        let formatter = DateFormatter()
        formatter.dateFormat = "h:mm a"
        var startComps = DateComponents()
        startComps.hour = startMin / 60
        startComps.minute = startMin % 60
        var endComps = DateComponents()
        endComps.hour = endMin / 60
        endComps.minute = endMin % 60
        let cal = Calendar.current
        guard let startDate = cal.date(from: startComps),
              let endDate = cal.date(from: endComps) else { return nil }
        let prefix: String
        if let sunType = sunEventType {
            prefix = sunType == .sunrise ? "☀️ Sunrise: " : "🌅 Sunset: "
        } else {
            prefix = ""
        }
        return "\(prefix)\(formatter.string(from: startDate)) – \(formatter.string(from: endDate))"
    }

    var nextWindowOpensDescription: String? {
        guard let startMin = effectiveStartMinuteOfDay, !isWithinTimeWindow else { return nil }
        let now = Date()
        let cal = Calendar.current
        let startHour = startMin / 60
        let startMinute = startMin % 60
        var target = cal.date(bySettingHour: startHour, minute: startMinute, second: 0, of: now) ?? now
        if target < now {
            target = cal.date(byAdding: .day, value: 1, to: target) ?? target
        }
        let diff = cal.dateComponents([.hour, .minute], from: now, to: target)
        if let h = diff.hour, let m = diff.minute {
            if h > 0 {
                return "Opens in \(h)h \(m)m"
            }
            return "Opens in \(m)m"
        }
        return nil
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }

    static func == (lhs: Quest, rhs: Quest) -> Bool {
        lhs.id == rhs.id
    }
}
