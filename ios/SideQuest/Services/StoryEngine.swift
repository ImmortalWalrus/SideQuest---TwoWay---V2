import Foundation

@Observable
class StoryEngine {
    var storyProgressMap: [String: StoryProgress] = [:]
    var globalInventory: [InventoryItem] = []
    var pendingStoryEvent: (templateId: String, progressId: String)? = nil

    private let templates: [StoryTemplate] = SampleStoryData.allTemplates

    func template(for id: String) -> StoryTemplate? {
        templates.first(where: { $0.id == id })
    }

    var allTemplates: [StoryTemplate] { templates }

    func startStory(templateId: String, journeyId: String? = nil) -> StoryProgress {
        guard let tmpl = template(for: templateId) else {
            fatalError("Unknown story template: \(templateId)")
        }
        let progress = StoryProgress(
            id: UUID().uuidString,
            journeyId: journeyId,
            templateId: templateId,
            currentNodeId: tmpl.startNodeId,
            visitedNodeIds: [tmpl.startNodeId],
            inventory: [],
            isComplete: false,
            isEnabled: true,
            pendingNodeIds: [],
            choicesMade: [:],
            endingReached: nil,
            goldEarned: 0,
            diamondsEarned: 0,
            startedAt: Date(),
            completedAt: nil
        )
        let key = journeyId ?? "quickplay_\(progress.id)"
        storyProgressMap[key] = progress
        return progress
    }

    func currentNode(for progressKey: String) -> StoryNode? {
        guard let progress = storyProgressMap[progressKey],
              let tmpl = template(for: progress.templateId) else { return nil }
        return tmpl.node(for: progress.currentNodeId)
    }

    func makeChoice(progressKey: String, choiceId: String) -> (node: StoryNode, reward: StoryReward?)? {
        guard var progress = storyProgressMap[progressKey],
              let tmpl = template(for: progress.templateId),
              let currentNode = tmpl.node(for: progress.currentNodeId) else { return nil }

        let nextNodeId: String?

        if currentNode.type == .decision {
            guard let choice = currentNode.choices.first(where: { $0.id == choiceId }) else { return nil }
            progress.choicesMade[currentNode.id] = choiceId
            nextNodeId = choice.nextNodeId
        } else {
            nextNodeId = currentNode.nextNodeId
        }

        guard let next = nextNodeId, let nextNode = tmpl.node(for: next) else { return nil }

        progress.currentNodeId = next
        progress.visitedNodeIds.append(next)

        var earnedReward: StoryReward? = nil
        if let reward = nextNode.reward {
            earnedReward = reward
            if let itemName = reward.itemName, let itemDesc = reward.itemDescription {
                let item = InventoryItem(
                    id: UUID().uuidString,
                    name: itemName,
                    itemDescription: itemDesc,
                    rarity: reward.itemRarity ?? .common,
                    storyTitle: tmpl.title,
                    acquiredAt: Date()
                )
                progress.inventory.append(item)
                globalInventory.append(item)
            }
            progress.goldEarned += reward.gold
            progress.diamondsEarned += reward.diamonds
        }

        if nextNode.type == .ending {
            progress.isComplete = true
            progress.endingReached = nextNode.endingTitle
            progress.completedAt = Date()
        }

        storyProgressMap[progressKey] = progress
        return (nextNode, earnedReward)
    }

    func advanceNarrative(progressKey: String) -> (node: StoryNode, reward: StoryReward?)? {
        return makeChoice(progressKey: progressKey, choiceId: "")
    }

    func toggleStoryEnabled(progressKey: String) {
        guard var progress = storyProgressMap[progressKey] else { return }
        progress.isEnabled.toggle()
        storyProgressMap[progressKey] = progress
    }

    func resetProgress(progressKey: String) {
        guard let progress = storyProgressMap[progressKey],
              let tmpl = template(for: progress.templateId) else { return }
        let itemIds = Set(progress.inventory.map(\.id))
        globalInventory.removeAll { itemIds.contains($0.id) }

        storyProgressMap[progressKey] = StoryProgress(
            id: progress.id,
            journeyId: progress.journeyId,
            templateId: progress.templateId,
            currentNodeId: tmpl.startNodeId,
            visitedNodeIds: [tmpl.startNodeId],
            inventory: [],
            isComplete: false,
            isEnabled: progress.isEnabled,
            pendingNodeIds: [],
            choicesMade: [:],
            endingReached: nil,
            goldEarned: 0,
            diamondsEarned: 0,
            startedAt: Date(),
            completedAt: nil
        )
    }

    func progressForJourney(_ journeyId: String) -> StoryProgress? {
        storyProgressMap[journeyId]
    }

    var allActiveProgress: [StoryProgress] {
        storyProgressMap.values.filter { !$0.isComplete }
    }

    var allCompletedProgress: [StoryProgress] {
        storyProgressMap.values.filter { $0.isComplete }
    }

    func queueStoryEvent(progressKey: String) {
        guard let progress = storyProgressMap[progressKey],
              progress.isEnabled, !progress.isComplete else { return }
        pendingStoryEvent = (templateId: progress.templateId, progressId: progressKey)
    }

    func clearPendingEvent() {
        pendingStoryEvent = nil
    }
}
