import Foundation

nonisolated enum StoryNodeType: String, Codable, Sendable {
    case narrative
    case decision
    case itemPickup
    case ending
}

nonisolated enum ItemRarity: String, Codable, Sendable, CaseIterable {
    case common = "Common"
    case uncommon = "Uncommon"
    case rare = "Rare"
    case legendary = "Legendary"

    var color: String {
        switch self {
        case .common: "gray"
        case .uncommon: "green"
        case .rare: "blue"
        case .legendary: "purple"
        }
    }

    var iconName: String {
        switch self {
        case .common: "circle.fill"
        case .uncommon: "diamond.fill"
        case .rare: "star.fill"
        case .legendary: "sparkles"
        }
    }
}

nonisolated struct StoryReward: Codable, Sendable, Equatable {
    var itemName: String?
    var itemDescription: String?
    var itemRarity: ItemRarity?
    var gold: Int
    var diamonds: Int
}

nonisolated struct StoryChoice: Identifiable, Codable, Sendable, Equatable {
    let id: String
    let text: String
    let nextNodeId: String
}

nonisolated struct StoryNode: Identifiable, Codable, Sendable, Equatable {
    let id: String
    let title: String
    let text: String
    let type: StoryNodeType
    var choices: [StoryChoice]
    var reward: StoryReward?
    var nextNodeId: String?
    var endingTitle: String?
}

nonisolated struct StoryTemplate: Identifiable, Codable, Sendable {
    let id: String
    let title: String
    let themeDescription: String
    let iconName: String
    let nodes: [StoryNode]
    let startNodeId: String

    func node(for id: String) -> StoryNode? {
        nodes.first(where: { $0.id == id })
    }

    var decisionCount: Int {
        nodes.filter { $0.type == .decision }.count
    }

    var endingCount: Int {
        nodes.filter { $0.type == .ending }.count
    }
}

nonisolated struct InventoryItem: Identifiable, Codable, Sendable, Equatable {
    let id: String
    let name: String
    let itemDescription: String
    let rarity: ItemRarity
    let storyTitle: String
    let acquiredAt: Date
}

nonisolated struct StoryProgress: Identifiable, Codable, Sendable {
    let id: String
    var journeyId: String?
    let templateId: String
    var currentNodeId: String
    var visitedNodeIds: [String]
    var inventory: [InventoryItem]
    var isComplete: Bool
    var isEnabled: Bool
    var pendingNodeIds: [String]
    var choicesMade: [String: String]
    var endingReached: String?
    var goldEarned: Int
    var diamondsEarned: Int
    var startedAt: Date
    var completedAt: Date?

    var hasSeenFirstDecision: Bool {
        visitedNodeIds.contains(where: { nodeId in
            choicesMade.keys.contains(nodeId)
        })
    }

    var decisionsMade: Int {
        choicesMade.count
    }
}
