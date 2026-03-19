import Foundation

nonisolated struct QuestFamily: Identifiable, Sendable {
    let id: String
    let name: String
    let category: QuestCategory
    let quests: [Quest]
    let recommendedQuest: Quest
    let additionalLevels: Int

    var path: QuestPath { recommendedQuest.path }
    var difficulty: QuestDifficulty { recommendedQuest.difficulty }
    var evidenceType: EvidenceType? { recommendedQuest.evidenceType }
    var xpRange: ClosedRange<Int> {
        let xps = quests.map(\.xpReward)
        return (xps.min() ?? 0)...(xps.max() ?? 0)
    }
    var difficulties: [QuestDifficulty] {
        let order: [QuestDifficulty] = [.easy, .medium, .hard, .expert]
        let unique = Set(quests.map(\.difficulty))
        return order.filter { unique.contains($0) }
    }
    var isLadder: Bool { quests.count > 1 }
    var isStandalone: Bool { quests.count == 1 }
}
