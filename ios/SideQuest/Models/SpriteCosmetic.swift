import SwiftUI

nonisolated enum SpriteSlot: String, Codable, Sendable, CaseIterable, Identifiable {
    case hair = "Hair"
    case hat = "Hat"
    case top = "Top"
    case bottom = "Bottom"
    case shoes = "Shoes"
    case weapon = "Weapon"
    case cape = "Cape"
    case aura = "Aura"

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .hair: "scissors"
        case .hat: "crown.fill"
        case .top: "tshirt.fill"
        case .bottom: "figure.stand"
        case .shoes: "shoe.fill"
        case .weapon: "bolt.fill"
        case .cape: "wind"
        case .aura: "sparkles"
        }
    }
}

nonisolated enum SpriteBodyColor: String, Codable, Sendable, CaseIterable {
    case peach
    case tan
    case brown
    case dark
    case pale

    var color: Color {
        switch self {
        case .peach: Color(red: 1.0, green: 0.82, blue: 0.7)
        case .tan: Color(red: 0.87, green: 0.72, blue: 0.53)
        case .brown: Color(red: 0.65, green: 0.45, blue: 0.3)
        case .dark: Color(red: 0.4, green: 0.28, blue: 0.2)
        case .pale: Color(red: 1.0, green: 0.9, blue: 0.85)
        }
    }
}

nonisolated struct SpriteLoadout: Codable, Sendable, Equatable {
    var bodyColor: SpriteBodyColor
    var equippedHair: String?
    var equippedHat: String?
    var equippedTop: String?
    var equippedBottom: String?
    var equippedShoes: String?
    var equippedWeapon: String?
    var equippedCape: String?
    var equippedAura: String?

    static let `default` = SpriteLoadout(
        bodyColor: .peach,
        equippedHair: "spiky_black",
        equippedHat: nil,
        equippedTop: "basic_tee_blue",
        equippedBottom: "basic_pants_gray",
        equippedShoes: "sneakers_white",
        equippedWeapon: nil,
        equippedCape: nil,
        equippedAura: nil
    )

    func item(for slot: SpriteSlot) -> String? {
        switch slot {
        case .hair: equippedHair
        case .hat: equippedHat
        case .top: equippedTop
        case .bottom: equippedBottom
        case .shoes: equippedShoes
        case .weapon: equippedWeapon
        case .cape: equippedCape
        case .aura: equippedAura
        }
    }

    mutating func equip(_ itemId: String?, slot: SpriteSlot) {
        switch slot {
        case .hair: equippedHair = itemId
        case .hat: equippedHat = itemId
        case .top: equippedTop = itemId
        case .bottom: equippedBottom = itemId
        case .shoes: equippedShoes = itemId
        case .weapon: equippedWeapon = itemId
        case .cape: equippedCape = itemId
        case .aura: equippedAura = itemId
        }
    }
}

nonisolated struct SpriteCosmeticItem: Identifiable, Sendable {
    let id: String
    let name: String
    let slot: SpriteSlot
    let price: Int
    let currencyType: SpriteCurrency
    let rarity: SpriteRarity
    let colors: [Color]
    let secondaryColors: [Color]
    let unlockLevel: Int

    init(id: String, name: String, slot: SpriteSlot, price: Int, currencyType: SpriteCurrency = .gold, rarity: SpriteRarity = .common, colors: [Color], secondaryColors: [Color] = [], unlockLevel: Int = 1) {
        self.id = id
        self.name = name
        self.slot = slot
        self.price = price
        self.currencyType = currencyType
        self.rarity = rarity
        self.colors = colors
        self.secondaryColors = secondaryColors
        self.unlockLevel = unlockLevel
    }
}

nonisolated enum SpriteCurrency: String, Sendable {
    case gold
    case diamonds
}

nonisolated enum SpriteRarity: String, Sendable {
    case common = "Common"
    case rare = "Rare"
    case epic = "Epic"
    case legendary = "Legendary"

    var color: Color {
        switch self {
        case .common: .secondary
        case .rare: .blue
        case .epic: .purple
        case .legendary: .orange
        }
    }
}
