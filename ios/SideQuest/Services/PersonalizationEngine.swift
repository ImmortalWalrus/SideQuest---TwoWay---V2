import Foundation
import CoreLocation

enum PersonalizationEngine {

    struct PlayerContext: Sendable {
        let onboarding: OnboardingData
        let completedQuestIds: Set<String>
        let questCompletionCounts: [String: Int]
        let completedSkillCounts: [UserSkill: Int]
        let completedInterestCounts: [UserInterest: Int]
        let activeQuestIds: Set<String>
        let recentlyCompletedIds: Set<String>
        let selectedSkills: [UserSkill]
        let selectedInterests: [UserInterest]
        let currentStreak: Int
        let playerLevel: Int
        let verifiedCount: Int
        let warriorRank: Int
        let explorerRank: Int
        let mindRank: Int
        let activeJourneyQuestIds: Set<String>
        let userCoordinate: CLLocationCoordinate2D?
        let preferredCity: String?
        let preferredState: String?
        let daypart: Daypart
    }

    nonisolated enum Daypart: Sendable {
        case earlyMorning
        case morning
        case midday
        case afternoon
        case evening
        case night

        static func current() -> Daypart {
            let hour = Calendar.current.component(.hour, from: Date())
            switch hour {
            case 5..<7: return .earlyMorning
            case 7..<11: return .morning
            case 11..<14: return .midday
            case 14..<17: return .afternoon
            case 17..<21: return .evening
            default: return .night
            }
        }
    }

    // MARK: - Score a single quest for a player context

    static func score(quest: Quest, context: PlayerContext) -> Double {
        var s: Double = 0

        s += goalAlignmentScore(quest: quest, goals: context.onboarding.goals)
        s += skillInterestScore(quest: quest, skills: context.selectedSkills, interests: context.selectedInterests)
        s += timeBudgetScore(quest: quest, budget: context.onboarding.timeBudget)
        s += verificationPreferenceScore(quest: quest, pref: context.onboarding.verificationPreference)
        s += difficultyProgressionScore(quest: quest, context: context)
        s += timeRelevanceScore(quest: quest, context: context)
        s += daypartScore(quest: quest, daypart: context.daypart)
        s += streakFreshnessScore(quest: quest, context: context)
        s += programBoostScore(quest: quest, context: context)

        s += penaltyForAlreadyActive(quest: quest, context: context)
        s += penaltyForRecentlyCompleted(quest: quest, context: context)
        s += penaltyForTooHard(quest: quest, context: context)

        return s
    }

    // MARK: - Rank a list of quests

    static func rank(quests: [Quest], context: PlayerContext) -> [Quest] {
        let scored = quests.map { (quest: $0, score: score(quest: $0, context: context)) }
        return scored.sorted { $0.score > $1.score }.map(\.quest)
    }

    // MARK: - Pick best next variant for a family ladder

    static func bestNextForFamily(quests: [Quest], context: PlayerContext) -> Quest {
        let diffOrder: [QuestDifficulty: Int] = [.easy: 0, .medium: 1, .hard: 2, .expert: 3]
        let sorted = quests.sorted {
            (diffOrder[$0.difficulty] ?? 0) < (diffOrder[$1.difficulty] ?? 0)
        }

        for quest in sorted {
            if context.completedQuestIds.contains(quest.id) { continue }

            let questDiffLevel = diffOrder[quest.difficulty] ?? 0
            let maxAllowed = maxDifficultyLevel(context: context, path: quest.path)
            if questDiffLevel <= maxAllowed + 1 {
                if quest.minCompletionMinutes <= context.onboarding.timeBudget.maxMinutes {
                    return quest
                }
            }
        }

        for quest in sorted {
            if !context.completedQuestIds.contains(quest.id) {
                return quest
            }
        }

        return sorted.last ?? quests[0]
    }

    // MARK: - For You section builders

    static func todaysPicks(from quests: [Quest], context: PlayerContext, count: Int = 3) -> [Quest] {
        let eligible = quests.filter { !context.activeQuestIds.contains($0.id) && !context.recentlyCompletedIds.contains($0.id) }
        let ranked = rank(quests: eligible, context: context)

        var picks: [Quest] = []
        var usedCategories: Set<String> = []
        var usedFamilyKeys: Set<String> = []

        let quickWin = ranked.first { $0.minCompletionMinutes <= 15 && $0.difficulty == .easy && !usedCategories.contains(QuestCategory.categorize($0).rawValue) }
        if let q = quickWin {
            picks.append(q)
            usedCategories.insert(QuestCategory.categorize(q).rawValue)
            usedFamilyKeys.insert(familyKey(for: q))
        }

        let progression = ranked.first { q in
            !picks.contains(where: { $0.id == q.id })
            && !usedCategories.contains(QuestCategory.categorize(q).rawValue)
            && (q.difficulty == .medium || q.difficulty == .hard)
            && q.minCompletionMinutes > 10
        }
        if let q = progression {
            picks.append(q)
            usedCategories.insert(QuestCategory.categorize(q).rawValue)
            usedFamilyKeys.insert(familyKey(for: q))
        }

        let nearby = ranked.first { q in
            !picks.contains(where: { $0.id == q.id })
            && !usedCategories.contains(QuestCategory.categorize(q).rawValue)
            && q.isLocationDependent
        }
        if let q = nearby {
            picks.append(q)
            usedCategories.insert(QuestCategory.categorize(q).rawValue)
            usedFamilyKeys.insert(familyKey(for: q))
        }

        if picks.count < count {
            for q in ranked {
                if picks.count >= count { break }
                if picks.contains(where: { $0.id == q.id }) { continue }
                let cat = QuestCategory.categorize(q).rawValue
                let fk = familyKey(for: q)
                if usedCategories.contains(cat) && picks.count < count - 1 { continue }
                if usedFamilyKeys.contains(fk) { continue }
                picks.append(q)
                usedCategories.insert(cat)
                usedFamilyKeys.insert(fk)
            }
        }

        if picks.count < count {
            for q in ranked where picks.count < count && !picks.contains(where: { $0.id == q.id }) {
                picks.append(q)
            }
        }

        return Array(picks.prefix(count))
    }

    static func featuredQuest(from quests: [Quest], context: PlayerContext) -> Quest? {
        let eligible = quests.filter {
            $0.type != .master
                && !context.activeQuestIds.contains($0.id)
                && !context.recentlyCompletedIds.contains($0.id)
        }
        guard !eligible.isEmpty else { return nil }

        let scored = eligible.map { quest in
            (
                quest: quest,
                score: score(quest: quest, context: context) + featuredSpotlightScore(quest: quest, context: context)
            )
        }

        return scored.sorted { lhs, rhs in
            if lhs.score == rhs.score {
                if lhs.quest.completionCount == rhs.quest.completionCount {
                    return lhs.quest.title < rhs.quest.title
                }
                return lhs.quest.completionCount > rhs.quest.completionCount
            }
            return lhs.score > rhs.score
        }
        .first?
        .quest
    }

    static func diversifyFamilyFeed(_ families: [QuestFamily], maxCount: Int = 6) -> [QuestFamily] {
        guard families.count > 1 else { return Array(families.prefix(maxCount)) }

        var result: [QuestFamily] = []
        var remaining = families

        while result.count < maxCount && !remaining.isEmpty {
            var bestIdx = 0
            var bestPenalty = Double.infinity

            for (i, candidate) in remaining.enumerated() {
                var penalty: Double = 0
                if let prev = result.last {
                    if candidate.category == prev.category { penalty += 100 }
                    if candidate.recommendedQuest.path == prev.recommendedQuest.path { penalty += 30 }
                    if isSameTheme(candidate, prev) { penalty += 80 }
                }
                if result.count >= 2 {
                    let prev2 = result[result.count - 2]
                    if candidate.category == prev2.category { penalty += 40 }
                    if candidate.recommendedQuest.path == prev2.recommendedQuest.path { penalty += 15 }
                }
                let positionCost = Double(i) * 0.5
                let total = penalty + positionCost
                if total < bestPenalty {
                    bestPenalty = total
                    bestIdx = i
                }
            }

            result.append(remaining.remove(at: bestIdx))
        }

        return result
    }

    private static func isSameTheme(_ a: QuestFamily, _ b: QuestFamily) -> Bool {
        if a.category == b.category { return true }
        let brainCats: Set<QuestCategory> = [.brainTraining]
        if brainCats.contains(a.category) && brainCats.contains(b.category) { return true }
        let fitnessCats: Set<QuestCategory> = [.pushUps, .planks, .wallSits, .jumpRope]
        if fitnessCats.contains(a.category) && fitnessCats.contains(b.category) { return true }
        let outdoorCats: Set<QuestCategory> = [.running, .walking, .hiking, .cycling]
        if outdoorCats.contains(a.category) && outdoorCats.contains(b.category) { return true }
        return false
    }

    private static func familyKey(for quest: Quest) -> String {
        let cat = QuestCategory.categorize(quest)
        let lower = quest.title.lowercased()
        switch cat {
        case .pushUps: return "pushups"
        case .planks: return "planks"
        case .wallSits: return "wallsits"
        case .jumpRope: return "jumprope"
        case .steps: return "steps"
        case .focus: return "focus"
        case .meditation: return "meditation"
        case .reading: return "reading"
        case .brainTraining:
            if lower.contains("memory") { return "brain_memory" }
            if lower.contains("math") { return "brain_math" }
            if lower.contains("chess") { return "brain_chess" }
            if lower.contains("wordforge") { return "brain_wordforge" }
            if lower.contains("scramble") { return "brain_scramble" }
            return "brain_other"
        default:
            return cat.rawValue
        }
    }

    static func contentThemeKey(for quest: Quest) -> String {
        familyKey(for: quest)
    }

    static func weeklyChallenge(from quests: [Quest], context: PlayerContext) -> Quest? {
        let hard = quests.filter {
            ($0.difficulty == .hard || $0.difficulty == .expert)
                && !context.activeQuestIds.contains($0.id)
                && !context.recentlyCompletedIds.contains($0.id)
        }
        guard !hard.isEmpty else { return nil }
        let ranked = hard
            .map { quest in
                (
                    quest: quest,
                    score: score(quest: quest, context: context) + weeklyChallengeSpotlightScore(quest: quest, context: context)
                )
            }
            .sorted { lhs, rhs in
                if lhs.score == rhs.score {
                    return lhs.quest.title < rhs.quest.title
                }
                return lhs.score > rhs.score
            }

        return ranked.first?.quest
    }

    private static func featuredSpotlightScore(quest: Quest, context: PlayerContext) -> Double {
        var score: Double = 0

        if quest.hasTimeWindow {
            if quest.isWithinTimeWindow {
                score += quest.isSunEventQuest ? 28.0 : 20.0
            } else if let minutesUntilNextWindowStart = minutesUntilNextWindowStart(for: quest),
                      minutesUntilNextWindowStart < 90 {
                score += 4.0
            } else {
                score -= quest.isSunEventQuest ? 24.0 : 14.0
            }
        }

        if quest.isLocationDependent, context.userCoordinate != nil {
            score += 14.0
        }

        if quest.type == .verified {
            score += 10.0
        } else if quest.type == .open {
            score += 4.0
        }

        switch quest.difficulty {
        case .easy:
            score += 4.0
        case .medium:
            score += 11.0
        case .hard:
            score += 15.0
        case .expert:
            score += context.playerLevel >= 8 ? 9.0 : -6.0
        }

        if quest.isExtreme {
            score += 9.0
        }

        if quest.minCompletionMinutes > 0, quest.minCompletionMinutes <= 45 {
            score += 6.0
        }

        if quest.isRepeatable, context.currentStreak >= 3 {
            score += 5.0
        }

        if quest.completionCount > 0 {
            score += min(Double(quest.completionCount) / 600.0, 9.0)
        }

        return score
    }

    private static func weeklyChallengeSpotlightScore(quest: Quest, context: PlayerContext) -> Double {
        var score: Double = 0

        if quest.isFeatured {
            score += 3.0
        }

        if quest.type == .verified {
            score += 8.0
        }

        switch quest.difficulty {
        case .hard:
            score += 10.0
        case .expert:
            score += context.playerLevel >= 8 ? 8.0 : -4.0
        default:
            break
        }

        if quest.hasTimeWindow && !quest.isWithinTimeWindow {
            score -= 8.0
        }

        if quest.minCompletionMinutes >= 15 && quest.minCompletionMinutes <= context.onboarding.timeBudget.maxMinutes {
            score += 4.0
        }

        if quest.isLocationDependent, context.userCoordinate != nil {
            score += 4.0
        }

        return score
    }

    // MARK: - Scoring Components

    private static func goalAlignmentScore(quest: Quest, goals: [PlayerGoal]) -> Double {
        guard !goals.isEmpty else { return 0 }
        var matches = 0
        for goal in goals {
            switch goal {
            case .getfit:
                if quest.path == .warrior { matches += 1 }
            case .buildHabits:
                if quest.isRepeatable { matches += 1 }
            case .explorePlaces:
                if quest.path == .explorer || quest.isLocationDependent { matches += 1 }
            case .trainMind:
                if quest.path == .mind { matches += 1 }
            case .socialChallenge:
                break
            case .relaxAndUnwind:
                if quest.isMeditationQuest || quest.isReadingQuest { matches += 1 }
            }
        }
        return Double(matches) * 15.0
    }

    private static func skillInterestScore(quest: Quest, skills: [UserSkill], interests: [UserInterest]) -> Double {
        let skillSet = Set(skills)
        let interestSet = Set(interests)
        let skillMatches = Set(quest.skillTags).intersection(skillSet).count
        let interestMatches = Set(quest.interestTags).intersection(interestSet).count
        return Double(skillMatches) * 10.0 + Double(interestMatches) * 8.0
    }

    private static func timeBudgetScore(quest: Quest, budget: DailyTimeBudget) -> Double {
        let questTime = quest.minCompletionMinutes
        let budgetMax = budget.maxMinutes
        if questTime <= budgetMax {
            let ratio = Double(questTime) / Double(max(1, budgetMax))
            return 10.0 * (1.0 - abs(ratio - 0.6))
        } else {
            return -20.0
        }
    }

    private static func timeRelevanceScore(quest: Quest, context: PlayerContext) -> Double {
        if quest.hasTimeWindow {
            return explicitTimeWindowScore(for: quest)
        }
        return temporalKeywordScore(for: quest, daypart: context.daypart)
    }

    private static func verificationPreferenceScore(quest: Quest, pref: VerificationPreference) -> Double {
        let isVerified = quest.type == .verified
        switch pref {
        case .verifiedOnly:
            return isVerified ? 10.0 : -30.0
        case .preferVerified:
            return isVerified ? 8.0 : -5.0
        case .mixed:
            return 0
        case .preferOpen:
            return isVerified ? -5.0 : 8.0
        }
    }

    private static func difficultyProgressionScore(quest: Quest, context: PlayerContext) -> Double {
        let diffOrder: [QuestDifficulty: Int] = [.easy: 0, .medium: 1, .hard: 2, .expert: 3]
        let questLevel = diffOrder[quest.difficulty] ?? 0
        let maxAllowed = maxDifficultyLevel(context: context, path: quest.path)

        if questLevel == maxAllowed {
            return 12.0
        } else if questLevel == maxAllowed + 1 {
            return 6.0
        } else if questLevel < maxAllowed {
            return 2.0
        } else {
            return -15.0
        }
    }

    private static func daypartScore(quest: Quest, daypart: Daypart) -> Double {
        if quest.isMeditationQuest || quest.isReadingQuest {
            switch daypart {
            case .earlyMorning, .evening, .night: return 5.0
            default: return 0
            }
        }
        if quest.isPoseTrackingQuest || quest.isTrackingQuest {
            switch daypart {
            case .morning, .midday, .afternoon: return 5.0
            case .night: return -5.0
            default: return 0
            }
        }
        if quest.isFocusQuest {
            switch daypart {
            case .morning, .midday: return 5.0
            case .night: return -3.0
            default: return 0
            }
        }
        return 0
    }

    private static func streakFreshnessScore(quest: Quest, context: PlayerContext) -> Double {
        var s: Double = 0
        if context.currentStreak == 0 && quest.difficulty == .easy {
            s += 8.0
        }
        if context.currentStreak >= 7 && (quest.difficulty == .medium || quest.difficulty == .hard) {
            s += 5.0
        }
        if context.recentlyCompletedIds.contains(quest.id) {
            s -= 20.0
        }
        return s
    }

    private static func programBoostScore(quest: Quest, context: PlayerContext) -> Double {
        if context.activeJourneyQuestIds.contains(quest.id) {
            return 20.0
        }
        return 0
    }

    // MARK: - Penalties

    private static func penaltyForAlreadyActive(quest: Quest, context: PlayerContext) -> Double {
        context.activeQuestIds.contains(quest.id) ? -50.0 : 0
    }

    private static func penaltyForRecentlyCompleted(quest: Quest, context: PlayerContext) -> Double {
        context.recentlyCompletedIds.contains(quest.id) ? -25.0 : 0
    }

    private static func penaltyForTooHard(quest: Quest, context: PlayerContext) -> Double {
        let diffOrder: [QuestDifficulty: Int] = [.easy: 0, .medium: 1, .hard: 2, .expert: 3]
        let questLevel = diffOrder[quest.difficulty] ?? 0
        let maxAllowed = maxDifficultyLevel(context: context, path: quest.path)
        if questLevel > maxAllowed + 1 {
            return -30.0
        }
        return 0
    }

    // MARK: - Helpers

    private static func maxDifficultyLevel(context: PlayerContext, path: QuestPath) -> Int {
        let rank: Int
        switch path {
        case .warrior: rank = context.warriorRank
        case .explorer: rank = context.explorerRank
        case .mind: rank = context.mindRank
        }

        if rank >= 10 { return 3 }
        if rank >= 5 { return 2 }
        if rank >= 2 || context.verifiedCount >= 5 { return 1 }
        return 0
    }

    private static func explicitTimeWindowScore(for quest: Quest) -> Double {
        if quest.isWithinTimeWindow {
            return quest.isSunEventQuest ? 30.0 : 24.0
        }

        guard let minutesUntilNextWindowStart = minutesUntilNextWindowStart(for: quest) else {
            return 0
        }

        switch minutesUntilNextWindowStart {
        case 0..<60:
            return 8.0
        case 60..<180:
            return 2.0
        case 180..<360:
            return -12.0
        default:
            return quest.isSunEventQuest ? -42.0 : -34.0
        }
    }

    private static func minutesUntilNextWindowStart(for quest: Quest) -> Int? {
        guard let startMin = quest.effectiveStartMinuteOfDay else { return nil }
        let now = Calendar.current.dateComponents([.hour, .minute], from: Date())
        guard let hour = now.hour, let minute = now.minute else { return nil }
        let currentMinutes = hour * 60 + minute
        if startMin >= currentMinutes {
            return startMin - currentMinutes
        }
        return (24 * 60 - currentMinutes) + startMin
    }

    private static func temporalKeywordScore(for quest: Quest, daypart: Daypart) -> Double {
        let haystack = "\(quest.title) \(quest.description)".lowercased()

        if containsAny(haystack, tokens: ["sunrise", "pre-dawn", "predawn", "dawn", "wake up early"]) {
            switch daypart {
            case .earlyMorning: return 18.0
            case .morning: return 8.0
            case .midday: return -12.0
            case .afternoon: return -18.0
            case .evening: return -28.0
            case .night: return -34.0
            }
        }

        if containsAny(haystack, tokens: ["sunset", "golden hour", "evening"]) {
            switch daypart {
            case .afternoon: return 6.0
            case .evening: return 16.0
            case .night: return -8.0
            case .earlyMorning: return -18.0
            case .morning: return -12.0
            case .midday: return -6.0
            }
        }

        if containsAny(haystack, tokens: ["stargazer", "stargazing", "late-night", "late night", "night sky", "moonlight"]) {
            switch daypart {
            case .evening: return 5.0
            case .night: return 16.0
            case .earlyMorning: return -10.0
            case .morning: return -20.0
            case .midday: return -14.0
            case .afternoon: return -8.0
            }
        }

        if containsAny(haystack, tokens: ["breakfast", "morning"]) {
            switch daypart {
            case .earlyMorning, .morning: return 10.0
            case .midday: return -4.0
            case .afternoon: return -10.0
            case .evening, .night: return -18.0
            }
        }

        if containsAny(haystack, tokens: ["lunch", "midday", "noon"]) {
            switch daypart {
            case .midday: return 12.0
            case .afternoon: return 4.0
            case .earlyMorning, .night: return -14.0
            case .morning, .evening: return -6.0
            }
        }

        return 0
    }

    private static func containsAny(_ haystack: String, tokens: [String]) -> Bool {
        tokens.contains { haystack.contains($0) }
    }
}
