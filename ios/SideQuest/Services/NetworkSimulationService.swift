import Foundation

@Observable
class NetworkSimulationService {
    private var friendStatusTask: Task<Void, Never>?
    private var activityFeedTask: Task<Void, Never>?
    private var leaderboardTask: Task<Void, Never>?

    private let questTitles = [
        "100 Push-Ups", "5K Run", "Cold Shower", "Gym Before 7AM",
        "Sunrise Walk", "Visit a New Park", "Hike a Trail",
        "30-Min Focus Session", "Read for 1 Hour", "Meditation",
        "2 Mile Run", "50 Push-Ups", "1 Min Plank", "2 Min Plank",
        "Gratitude Log", "Street Photography", "Journal Entry"
    ]

    private let botNames = [
        ("IronWill", "figure.martial.arts", "gradient2"),
        ("TrailBlazer", "figure.hiking", "gradient3"),
        ("MindForge", "brain.head.profile.fill", "gradient1"),
        ("SteelPath", "figure.strengthtraining.traditional", "gradient4"),
        ("Wanderer", "figure.walk", "gradient2"),
        ("ZenMaster", "figure.mind.and.body", "gradient3"),
        ("NightOwl", "moon.fill", "gradient1"),
        ("PhoenixRise", "flame.fill", "gradient2"),
        ("SkyRunner", "figure.run", "gradient3"),
        ("IronClad", "shield.fill", "gradient4"),
    ]

    func startSimulation(
        updateFriends: @escaping () -> Void,
        addActivity: @escaping (ActivityItem) -> Void,
        updateLeaderboard: @escaping () -> Void
    ) {
        stopSimulation()

        friendStatusTask = Task { @MainActor in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(Double.random(in: 15...30)))
                guard !Task.isCancelled else { return }
                updateFriends()
            }
        }

        activityFeedTask = Task { @MainActor in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(Double.random(in: 20...45)))
                guard !Task.isCancelled else { return }
                let bot = botNames.randomElement()!
                let quest = questTitles.randomElement()!
                let paths: [QuestPath] = [.warrior, .explorer, .mind]
                let item = ActivityItem(
                    id: UUID().uuidString,
                    username: bot.0,
                    avatarName: bot.1,
                    questTitle: quest,
                    path: paths.randomElement()!,
                    isMaster: Int.random(in: 0...20) == 0,
                    completedAt: Date()
                )
                addActivity(item)
            }
        }

        leaderboardTask = Task { @MainActor in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(Double.random(in: 40...90)))
                guard !Task.isCancelled else { return }
                updateLeaderboard()
            }
        }
    }

    func stopSimulation() {
        friendStatusTask?.cancel()
        activityFeedTask?.cancel()
        leaderboardTask?.cancel()
        friendStatusTask = nil
        activityFeedTask = nil
        leaderboardTask = nil
    }
}
