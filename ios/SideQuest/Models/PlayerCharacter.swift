import Foundation

nonisolated enum PlayerCharacterType: String, CaseIterable, Codable, Sendable, Identifiable {
    case amazonWarrior = "amazon_warrior"
    case barbarian = "barbarian"
    case gladiator = "gladiator"
    case gunslinger = "gunslinger"
    case knight = "knight"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .amazonWarrior: return "Amazon Warrior"
        case .barbarian: return "Barbarian"
        case .gladiator: return "Gladiator"
        case .gunslinger: return "Gunslinger"
        case .knight: return "Knight"
        }
    }

    var fileName: String {
        switch self {
        case .amazonWarrior: return "AmazonWarrior"
        case .barbarian: return "Barbarian"
        case .gladiator: return "Gladiator"
        case .gunslinger: return "Gunslinger"
        case .knight: return "Knight"
        }
    }

    var lore: String {
        switch self {
        case .amazonWarrior: return "Fierce and fearless, the Amazon strikes with precision and grace."
        case .barbarian: return "Raw power and unstoppable fury define the Barbarian's path."
        case .gladiator: return "Born in the arena, the Gladiator thrives under pressure."
        case .gunslinger: return "Quick on the draw and deadly accurate — the Gunslinger never misses."
        case .knight: return "Honor-bound and armored, the Knight stands as an unbreakable shield."
        }
    }

    var iconName: String {
        switch self {
        case .amazonWarrior: return "bolt.fill"
        case .barbarian: return "flame.fill"
        case .gladiator: return "shield.fill"
        case .gunslinger: return "scope"
        case .knight: return "crown.fill"
        }
    }

    var shopPrice: Int {
        switch self {
        case .amazonWarrior: return 500
        case .barbarian: return 450
        case .gladiator: return 550
        case .gunslinger: return 600
        case .knight: return 0
        }
    }

    var isStarterSkin: Bool {
        self == .knight
    }

    var heroProfileYawDegrees: Int {
        switch self {
        case .knight:
            return 154
        case .amazonWarrior, .barbarian, .gladiator, .gunslinger:
            return 154
        }
    }

    var homeHeroYawDegrees: Int {
        switch self {
        case .knight:
            return 206
        case .amazonWarrior, .barbarian, .gladiator, .gunslinger:
            return 206
        }
    }

    static func shopCharacter(named name: String) -> PlayerCharacterType? {
        allCases.first { $0.displayName == name }
    }
}
