import Foundation

nonisolated enum DailyTimeBudget: String, CaseIterable, Codable, Identifiable, Sendable {
    case minimal = "5-10 min"
    case moderate = "15-30 min"
    case committed = "30-60 min"
    case hardcore = "60+ min"

    var id: String { rawValue }

    var maxMinutes: Int {
        switch self {
        case .minimal: 10
        case .moderate: 30
        case .committed: 60
        case .hardcore: 120
        }
    }

    var icon: String {
        switch self {
        case .minimal: "clock"
        case .moderate: "clock.badge"
        case .committed: "clock.arrow.circlepath"
        case .hardcore: "flame.fill"
        }
    }
}

nonisolated enum VerificationPreference: String, CaseIterable, Codable, Identifiable, Sendable {
    case verifiedOnly = "Verified Only"
    case preferVerified = "Prefer Verified"
    case mixed = "Mix of Both"
    case preferOpen = "Prefer Open"

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .verifiedOnly: "checkmark.seal.fill"
        case .preferVerified: "checkmark.seal"
        case .mixed: "circle.grid.2x2.fill"
        case .preferOpen: "person.fill"
        }
    }

    var verifiedBias: Double {
        switch self {
        case .verifiedOnly: 1.0
        case .preferVerified: 0.7
        case .mixed: 0.5
        case .preferOpen: 0.2
        }
    }
}

nonisolated enum PlayerGoal: String, CaseIterable, Codable, Identifiable, Sendable {
    case getfit = "Get Fit"
    case buildHabits = "Build Habits"
    case explorePlaces = "Explore Places"
    case trainMind = "Train My Mind"
    case socialChallenge = "Challenge Friends"
    case relaxAndUnwind = "Relax & Unwind"

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .getfit: "figure.run"
        case .buildHabits: "repeat"
        case .explorePlaces: "map.fill"
        case .trainMind: "brain.head.profile.fill"
        case .socialChallenge: "person.2.fill"
        case .relaxAndUnwind: "leaf.fill"
        }
    }

    var color: String {
        switch self {
        case .getfit: "red"
        case .buildHabits: "orange"
        case .explorePlaces: "green"
        case .trainMind: "purple"
        case .socialChallenge: "blue"
        case .relaxAndUnwind: "teal"
        }
    }
}

nonisolated enum LiveEventPreference: String, CaseIterable, Codable, Identifiable, Sendable {
    case concerts = "Concerts"
    case nightlife = "Nightlife"
    case exclusiveNightlife = "Exclusive Nights"
    case comedy = "Comedy"
    case community = "Community"
    case markets = "Markets"
    case raceEvents = "Race Events"
    case sportsGames = "Sports Games"
    case wellness = "Wellness"
    case foodAndDrink = "Food & Drink"

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .concerts: return "music.mic"
        case .nightlife: return "moon.stars.fill"
        case .exclusiveNightlife: return "sparkles"
        case .comedy: return "theatermasks.fill"
        case .community: return "person.3.fill"
        case .markets: return "basket.fill"
        case .raceEvents: return "figure.run"
        case .sportsGames: return "sportscourt.fill"
        case .wellness: return "sparkles"
        case .foodAndDrink: return "fork.knife"
        }
    }

    var color: String {
        switch self {
        case .concerts: return "pink"
        case .nightlife: return "purple"
        case .exclusiveNightlife: return "mint"
        case .comedy: return "orange"
        case .community: return "green"
        case .markets: return "yellow"
        case .raceEvents: return "red"
        case .sportsGames: return "blue"
        case .wellness: return "teal"
        case .foodAndDrink: return "indigo"
        }
    }
}

nonisolated enum OnboardingMusicGenre: String, CaseIterable, Codable, Identifiable, Sendable {
    case pop = "Pop"
    case hipHop = "Hip-Hop"
    case edm = "EDM"
    case rock = "Rock"
    case indie = "Indie"
    case latin = "Latin"
    case country = "Country"
    case jazz = "Jazz"

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .pop: return "sparkles"
        case .hipHop: return "music.note.tv"
        case .edm: return "waveform.path.ecg"
        case .rock: return "guitars.fill"
        case .indie: return "music.quarternote.3"
        case .latin: return "flame.fill"
        case .country: return "sun.max.fill"
        case .jazz: return "saxophone.fill"
        }
    }

    var matchTokens: [String] {
        switch self {
        case .pop: return ["pop"]
        case .hipHop: return ["hip hop", "hip-hop", "rap", "trap", "r&b", "rnb"]
        case .edm: return ["edm", "dj", "house", "techno", "dance", "electronic"]
        case .rock: return ["rock", "metal", "punk", "alt rock", "alternative"]
        case .indie: return ["indie", "folk", "singer songwriter", "singer-songwriter"]
        case .latin: return ["latin", "reggaeton", "banda", "corridos", "salsa", "bachata"]
        case .country: return ["country", "americana", "bluegrass"]
        case .jazz: return ["jazz", "blues", "soul", "funk"]
        }
    }
}

nonisolated struct OnboardingData: Codable, Sendable {
    var goals: [PlayerGoal]
    var timeBudget: DailyTimeBudget
    var verificationPreference: VerificationPreference
    var preferredEventTypes: [LiveEventPreference]
    var favoriteMusicGenres: [OnboardingMusicGenre]
    var completedAt: Date
    var version: Int

    static let currentVersion = 3
    static let stalenessThresholdDays = 90

    var isComplete: Bool {
        !goals.isEmpty
    }

    var isStale: Bool {
        let daysSince = Calendar.current.dateComponents([.day], from: completedAt, to: Date()).day ?? 0
        return daysSince >= Self.stalenessThresholdDays
    }

    var needsRefresh: Bool {
        !isComplete || isStale || version < Self.currentVersion
    }

    static let empty = OnboardingData(
        goals: [],
        timeBudget: .moderate,
        verificationPreference: .mixed,
        preferredEventTypes: [],
        favoriteMusicGenres: [],
        completedAt: .distantPast,
        version: 0
    )

    private enum CodingKeys: String, CodingKey {
        case goals
        case timeBudget
        case verificationPreference
        case preferredEventTypes
        case favoriteMusicGenres
        case completedAt
        case version
    }

    init(
        goals: [PlayerGoal],
        timeBudget: DailyTimeBudget,
        verificationPreference: VerificationPreference,
        preferredEventTypes: [LiveEventPreference],
        favoriteMusicGenres: [OnboardingMusicGenre],
        completedAt: Date,
        version: Int
    ) {
        self.goals = goals
        self.timeBudget = timeBudget
        self.verificationPreference = verificationPreference
        self.preferredEventTypes = preferredEventTypes
        self.favoriteMusicGenres = favoriteMusicGenres
        self.completedAt = completedAt
        self.version = version
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        goals = try container.decodeIfPresent([PlayerGoal].self, forKey: .goals) ?? []
        timeBudget = try container.decodeIfPresent(DailyTimeBudget.self, forKey: .timeBudget) ?? .moderate
        verificationPreference = try container.decodeIfPresent(VerificationPreference.self, forKey: .verificationPreference) ?? .mixed
        preferredEventTypes = try container.decodeIfPresent([LiveEventPreference].self, forKey: .preferredEventTypes) ?? []
        favoriteMusicGenres = try container.decodeIfPresent([OnboardingMusicGenre].self, forKey: .favoriteMusicGenres) ?? []
        completedAt = try container.decodeIfPresent(Date.self, forKey: .completedAt) ?? .distantPast
        version = try container.decodeIfPresent(Int.self, forKey: .version) ?? 0
    }
}
