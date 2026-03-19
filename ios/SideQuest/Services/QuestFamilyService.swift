import Foundation

enum QuestFamilyService {
    static func buildFamilies(from quests: [Quest], completedQuestIds: Set<String> = [], playerContext: PersonalizationEngine.PlayerContext? = nil) -> [QuestFamily] {
        let grouped = Dictionary(grouping: quests) { QuestCategory.categorize($0) }

        var families: [QuestFamily] = []

        for (category, categoryQuests) in grouped {
            let subFamilies = splitIntoSubFamilies(categoryQuests, category: category)
            for (name, members) in subFamilies {
                let sorted = sortLadder(members)
                let recommended: Quest
                if let ctx = playerContext, sorted.count > 1 {
                    recommended = PersonalizationEngine.bestNextForFamily(quests: sorted, context: ctx)
                } else {
                    recommended = pickBestNext(sorted, completedIds: completedQuestIds)
                }
                let family = QuestFamily(
                    id: "\(category.rawValue)_\(name)",
                    name: name,
                    category: category,
                    quests: sorted,
                    recommendedQuest: recommended,
                    additionalLevels: max(0, sorted.count - 1)
                )
                families.append(family)
            }
        }

        if let ctx = playerContext {
            let scored = families.map { family -> (QuestFamily, Double) in
                let s = PersonalizationEngine.score(quest: family.recommendedQuest, context: ctx)
                return (family, s)
            }
            return scored.sorted { $0.1 > $1.1 }.map(\.0)
        }

        return families.sorted { lhs, rhs in
            if lhs.quests.count != rhs.quests.count {
                return lhs.quests.count > rhs.quests.count
            }
            return lhs.name < rhs.name
        }
    }

    private static func splitIntoSubFamilies(_ quests: [Quest], category: QuestCategory) -> [(String, [Quest])] {
        switch category {
        case .pushUps:
            return splitPushUps(quests)
        case .planks:
            return [("Planks", quests)]
        case .wallSits:
            return [("Wall Sits", quests)]
        case .jumpRope:
            return [("Jump Rope", quests)]
        case .steps:
            return splitSteps(quests)
        case .focus:
            return [("Focus Blocks", quests)]
        case .reading:
            return [("Reading", quests)]
        case .meditation:
            return [("Meditation", quests)]
        case .cycling:
            return splitCycling(quests)

        case .running:
            return splitRunning(quests)
        case .walking:
            return splitWalking(quests)
        case .hiking:
            return splitHiking(quests)
        case .brainTraining:
            return splitBrainTraining(quests)

        case .gymAndPlaces, .coldAndDiscipline, .placesExplore, .photography,
             .socialExperiences, .lifestyle, .digitalDetox, .creative,
             .journaling, .affirmations, .other:
            return splitStandaloneWithLibrary(quests)
        }
    }

    // MARK: - Running (strict intent-based split)

    private static func splitRunning(_ quests: [Quest]) -> [(String, [Quest])] {
        var assigned: Set<String> = []
        var result: [(String, [Quest])] = []

        let extreme = quests.filter { $0.isExtreme }
        if !extreme.isEmpty {
            result.append(("Extreme Running", extreme))
            extreme.forEach { assigned.insert($0.id) }
        }

        let trailQuests = quests.filter { !assigned.contains($0.id) && isTrailRunning($0) }
        if trailQuests.count >= 2 {
            result.append(("Trail Running", trailQuests))
            trailQuests.forEach { assigned.insert($0.id) }
        }

        let paceQuests = quests.filter { !assigned.contains($0.id) && isPaceGoal($0) }
        if paceQuests.count >= 2 {
            result.append(("Running Pace Goals", paceQuests))
            paceQuests.forEach { assigned.insert($0.id) }
        }

        let distanceCompletion = quests.filter { !assigned.contains($0.id) && isDistanceCompletion($0) }
        if distanceCompletion.count >= 2 {
            result.append(("Distance Running", distanceCompletion))
            distanceCompletion.forEach { assigned.insert($0.id) }
        }

        let remaining = quests.filter { !assigned.contains($0.id) }
        result.append(contentsOf: standaloneEntries(remaining))

        return result
    }

    private static func isTrailRunning(_ quest: Quest) -> Bool {
        let lower = quest.title.lowercased()
        return lower.contains("trail") && lower.contains("run")
    }

    private static func isPaceGoal(_ quest: Quest) -> Bool {
        let lower = quest.title.lowercased()
        return lower.contains("under") || lower.contains("pace") || lower.contains("speed")
    }

    private static func isDistanceCompletion(_ quest: Quest) -> Bool {
        let lower = quest.title.lowercased()
        let hasDistance = lower.contains("mile") || lower.contains("km") || lower.contains("5k") || lower.contains("10k")
        return hasDistance && !isPaceGoal(quest)
    }

    // MARK: - Walking (only quantitative progression)

    private static func splitWalking(_ quests: [Quest]) -> [(String, [Quest])] {
        var assigned: Set<String> = []
        var result: [(String, [Quest])] = []

        let paceWalks = quests.filter { isPaceGoal($0) }
        if paceWalks.count >= 2 {
            result.append(("Walking Pace Goals", paceWalks))
            paceWalks.forEach { assigned.insert($0.id) }
        }

        let distanceWalks = quests.filter { !assigned.contains($0.id) && isDistanceWalk($0) }
        if distanceWalks.count >= 2 {
            result.append(("Walking Distance", distanceWalks))
            distanceWalks.forEach { assigned.insert($0.id) }
        }

        let remaining = quests.filter { !assigned.contains($0.id) }
        result.append(contentsOf: standaloneEntries(remaining))

        return result
    }

    private static func isDistanceWalk(_ quest: Quest) -> Bool {
        let lower = quest.title.lowercased()
        return lower.contains("mile") || lower.contains("km") || lower.contains("5k") || lower.contains("3k")
    }

    // MARK: - Hiking (real progression only)

    private static func splitHiking(_ quests: [Quest]) -> [(String, [Quest])] {
        var assigned: Set<String> = []
        var result: [(String, [Quest])] = []

        let trailHikes = quests.filter { isTrailHike($0) }
        if trailHikes.count >= 2 {
            result.append(("Trail Hiking", trailHikes))
            trailHikes.forEach { assigned.insert($0.id) }
        }

        let trailRuns = quests.filter { !assigned.contains($0.id) && isTrailRunning($0) }
        if trailRuns.count >= 2 {
            result.append(("Trail Running", trailRuns))
            trailRuns.forEach { assigned.insert($0.id) }
        }

        let distanceHikes = quests.filter { !assigned.contains($0.id) && isDistanceHike($0) }
        if distanceHikes.count >= 2 {
            result.append(("Distance Hiking", distanceHikes))
            distanceHikes.forEach { assigned.insert($0.id) }
        }

        let remaining = quests.filter { !assigned.contains($0.id) }
        result.append(contentsOf: standaloneEntries(remaining))

        return result
    }

    private static func isTrailHike(_ quest: Quest) -> Bool {
        let lower = quest.title.lowercased()
        let hasTrailKeyword = lower.contains("trail") || lower.contains("trek")
        let hasHikeKeyword = lower.contains("hike") || lower.contains("walk") || lower.contains("trek")
        return hasTrailKeyword && hasHikeKeyword
    }

    private static func isDistanceHike(_ quest: Quest) -> Bool {
        let lower = quest.title.lowercased()
        let hasTrailContext = lower.contains("trail") || lower.contains("trek") || lower.contains("hike")
        let hasDistance = lower.contains("mile") || lower.contains("km") || lower.contains("loop")
        return hasDistance && hasTrailContext
    }

    // MARK: - Brain Training (individual game ladders)

    private static func splitBrainTraining(_ quests: [Quest]) -> [(String, [Quest])] {
        var assigned: Set<String> = []
        var result: [(String, [Quest])] = []

        let families: [(String, [String])] = [
            ("Memory Training", ["memory"]),
            ("Speed Math", ["math"]),
            ("WordForge", ["wordforge"]),
            ("Word Scramble", ["scramble"]),
            ("Chess", ["chess"]),
        ]

        for (name, keys) in families {
            let matching = quests.filter { quest in
                let lower = quest.title.lowercased()
                return keys.contains(where: { lower.contains($0) })
            }
            if matching.count >= 2 {
                result.append((name, matching))
                matching.forEach { assigned.insert($0.id) }
            } else if matching.count == 1 {
                assigned.insert(matching[0].id)
                result.append(contentsOf: standaloneEntries(matching))
            }
        }

        let wordOther = quests.filter { !assigned.contains($0.id) && $0.title.lowercased().contains("word") }
        if wordOther.count >= 2 {
            result.append(("Word Games", wordOther))
            wordOther.forEach { assigned.insert($0.id) }
        }

        let remaining = quests.filter { !assigned.contains($0.id) }
        if remaining.count >= 2 {
            let lower = remaining.allSatisfy { $0.title.lowercased().contains("brain") || $0.title.lowercased().contains("puzzle") }
            if lower {
                result.append(("Brain Training", remaining))
            } else {
                result.append(contentsOf: standaloneEntries(remaining))
            }
        } else {
            result.append(contentsOf: standaloneEntries(remaining))
        }

        return result
    }

    // MARK: - Push-Ups (split by success metric)

    private static func splitPushUps(_ quests: [Quest]) -> [(String, [Quest])] {
        var assigned: Set<String> = []
        var result: [(String, [Quest])] = []

        let timed = quests.filter { isPushUpTimed($0) }
        if timed.count >= 2 {
            result.append(("Push-Ups Timed", timed))
            timed.forEach { assigned.insert($0.id) }
        }

        let unbroken = quests.filter { !assigned.contains($0.id) && isPushUpUnbroken($0) }
        if unbroken.count >= 2 {
            result.append(("Push-Ups Unbroken", unbroken))
            unbroken.forEach { assigned.insert($0.id) }
        }

        let volume = quests.filter { !assigned.contains($0.id) }
        if volume.count >= 2 {
            result.append(("Push-Ups Volume", volume))
        } else {
            result.append(contentsOf: standaloneEntries(volume))
        }

        return result
    }

    private static func isPushUpTimed(_ quest: Quest) -> Bool {
        let lower = quest.title.lowercased()
        return lower.contains("under") || lower.contains("min") || quest.timeLimitSeconds ?? 0 > 0
    }

    private static func isPushUpUnbroken(_ quest: Quest) -> Bool {
        let lower = quest.title.lowercased()
        return lower.contains("unbroken")
    }

    // MARK: - Steps (daily ladder vs conditional standalone)

    private static func splitSteps(_ quests: [Quest]) -> [(String, [Quest])] {
        var assigned: Set<String> = []
        var result: [(String, [Quest])] = []

        let conditional = quests.filter { isConditionalSteps($0) }
        conditional.forEach { assigned.insert($0.id) }

        let daily = quests.filter { !assigned.contains($0.id) }
        if daily.count >= 2 {
            result.append(("Daily Steps", daily))
        } else {
            result.append(contentsOf: standaloneEntries(daily))
        }

        result.append(contentsOf: standaloneEntries(conditional))

        return result
    }

    private static func isConditionalSteps(_ quest: Quest) -> Bool {
        let lower = quest.title.lowercased()
        return lower.contains("before") || lower.contains("after") || lower.contains("morning") || quest.timeWindowStartHour != nil
    }

    // MARK: - Cycling (distance ladder vs commute standalone)

    private static func splitCycling(_ quests: [Quest]) -> [(String, [Quest])] {
        var assigned: Set<String> = []
        var result: [(String, [Quest])] = []

        let commute = quests.filter { $0.title.lowercased().contains("commute") }
        commute.forEach { assigned.insert($0.id) }

        let distance = quests.filter { !assigned.contains($0.id) }
        if distance.count >= 2 {
            result.append(("Bike Ride Distance", distance))
        } else {
            result.append(contentsOf: standaloneEntries(distance))
        }

        result.append(contentsOf: standaloneEntries(commute))

        return result
    }

    // MARK: - Standalone with Library Deep Work extraction

    private static func splitStandaloneWithLibrary(_ quests: [Quest]) -> [(String, [Quest])] {
        var assigned: Set<String> = []
        var result: [(String, [Quest])] = []

        let library = quests.filter { isLibraryDeepWork($0) }
        if library.count >= 2 {
            result.append(("Library Deep Work", library))
            library.forEach { assigned.insert($0.id) }
        }

        let remaining = quests.filter { !assigned.contains($0.id) }
        result.append(contentsOf: standaloneEntries(remaining))

        return result
    }

    private static func isLibraryDeepWork(_ quest: Quest) -> Bool {
        let lower = quest.title.lowercased()
        return lower.contains("library")
    }

    // MARK: - Standalone (each quest is its own entry)

    private static func standaloneEntries(_ quests: [Quest]) -> [(String, [Quest])] {
        quests.map { ($0.title, [$0]) }
    }

    // MARK: - Sorting & Recommendation

    private static func sortLadder(_ quests: [Quest]) -> [Quest] {
        let diffOrder: [QuestDifficulty: Int] = [.easy: 0, .medium: 1, .hard: 2, .expert: 3]
        return quests.sorted { lhs, rhs in
            let ld = diffOrder[lhs.difficulty] ?? 0
            let rd = diffOrder[rhs.difficulty] ?? 0
            if ld != rd { return ld < rd }
            return lhs.xpReward < rhs.xpReward
        }
    }

    private static func pickBestNext(_ sorted: [Quest], completedIds: Set<String>) -> Quest {
        for quest in sorted {
            if !completedIds.contains(quest.id) {
                return quest
            }
        }
        return sorted.last ?? sorted[0]
    }
}
