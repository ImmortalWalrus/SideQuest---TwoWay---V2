import SwiftUI

enum SpriteCosmeticsCatalog {
    static func items(for slot: SpriteSlot) -> [SpriteCosmeticItem] {
        switch slot {
        case .hair: hairItems
        case .hat: hatItems
        case .top: topItems
        case .bottom: bottomItems
        case .shoes: shoeItems
        case .weapon: weaponItems
        case .cape: capeItems
        case .aura: auraItems
        }
    }

    static let hairItems: [SpriteCosmeticItem] = [
        SpriteCosmeticItem(id: "spiky_black", name: "Spiky", slot: .hair, price: 0, rarity: .common, colors: [Color(white: 0.15)]),
        SpriteCosmeticItem(id: "spiky_blonde", name: "Spiky Blonde", slot: .hair, price: 100, rarity: .common, colors: [Color(red: 0.95, green: 0.85, blue: 0.4)]),
        SpriteCosmeticItem(id: "flow_brown", name: "Flow", slot: .hair, price: 150, rarity: .common, colors: [Color(red: 0.45, green: 0.3, blue: 0.15)]),
        SpriteCosmeticItem(id: "mohawk_red", name: "Mohawk", slot: .hair, price: 300, rarity: .rare, colors: [.red]),
        SpriteCosmeticItem(id: "long_silver", name: "Long Silver", slot: .hair, price: 500, rarity: .rare, colors: [Color(white: 0.8)]),
        SpriteCosmeticItem(id: "flame_hair", name: "Flame Hair", slot: .hair, price: 1200, currencyType: .gold, rarity: .epic, colors: [.orange, .red]),
        SpriteCosmeticItem(id: "galaxy_hair", name: "Galaxy Hair", slot: .hair, price: 50, currencyType: .diamonds, rarity: .legendary, colors: [.purple, .blue, .cyan]),
    ]

    static let hatItems: [SpriteCosmeticItem] = [
        SpriteCosmeticItem(id: "headband_white", name: "Headband", slot: .hat, price: 100, rarity: .common, colors: [.white]),
        SpriteCosmeticItem(id: "cap_red", name: "Cap", slot: .hat, price: 200, rarity: .common, colors: [.red]),
        SpriteCosmeticItem(id: "warrior_helm", name: "Warrior Helm", slot: .hat, price: 600, rarity: .rare, colors: [Color(white: 0.6)], secondaryColors: [.orange]),
        SpriteCosmeticItem(id: "wizard_hat", name: "Wizard Hat", slot: .hat, price: 800, rarity: .rare, colors: [.indigo], secondaryColors: [.yellow]),
        SpriteCosmeticItem(id: "crown_gold", name: "Gold Crown", slot: .hat, price: 2000, rarity: .epic, colors: [.yellow, .orange]),
        SpriteCosmeticItem(id: "halo", name: "Halo", slot: .hat, price: 80, currencyType: .diamonds, rarity: .legendary, colors: [.yellow, .white]),
    ]

    static let topItems: [SpriteCosmeticItem] = [
        SpriteCosmeticItem(id: "basic_tee_blue", name: "Blue Tee", slot: .top, price: 0, rarity: .common, colors: [.blue]),
        SpriteCosmeticItem(id: "basic_tee_red", name: "Red Tee", slot: .top, price: 100, rarity: .common, colors: [.red]),
        SpriteCosmeticItem(id: "basic_tee_green", name: "Green Tee", slot: .top, price: 100, rarity: .common, colors: [.green]),
        SpriteCosmeticItem(id: "tank_black", name: "Black Tank", slot: .top, price: 150, rarity: .common, colors: [Color(white: 0.15)]),
        SpriteCosmeticItem(id: "hoodie_gray", name: "Gray Hoodie", slot: .top, price: 300, rarity: .rare, colors: [Color(white: 0.45)]),
        SpriteCosmeticItem(id: "armor_iron", name: "Iron Armor", slot: .top, price: 800, rarity: .rare, colors: [Color(white: 0.6)], secondaryColors: [Color(white: 0.4)]),
        SpriteCosmeticItem(id: "armor_gold", name: "Gold Armor", slot: .top, price: 1500, rarity: .epic, colors: [.yellow, .orange], secondaryColors: [Color(red: 0.7, green: 0.55, blue: 0.1)]),
        SpriteCosmeticItem(id: "robe_mystic", name: "Mystic Robe", slot: .top, price: 60, currencyType: .diamonds, rarity: .legendary, colors: [.purple, .indigo], secondaryColors: [.cyan]),
    ]

    static let bottomItems: [SpriteCosmeticItem] = [
        SpriteCosmeticItem(id: "basic_pants_gray", name: "Gray Pants", slot: .bottom, price: 0, rarity: .common, colors: [Color(white: 0.4)]),
        SpriteCosmeticItem(id: "basic_pants_blue", name: "Blue Jeans", slot: .bottom, price: 100, rarity: .common, colors: [Color(red: 0.2, green: 0.3, blue: 0.6)]),
        SpriteCosmeticItem(id: "shorts_black", name: "Black Shorts", slot: .bottom, price: 150, rarity: .common, colors: [Color(white: 0.15)]),
        SpriteCosmeticItem(id: "combat_pants", name: "Combat Pants", slot: .bottom, price: 400, rarity: .rare, colors: [Color(red: 0.3, green: 0.35, blue: 0.25)]),
        SpriteCosmeticItem(id: "leg_armor", name: "Leg Armor", slot: .bottom, price: 800, rarity: .epic, colors: [Color(white: 0.55)], secondaryColors: [.orange]),
        SpriteCosmeticItem(id: "astral_legs", name: "Astral Greaves", slot: .bottom, price: 40, currencyType: .diamonds, rarity: .legendary, colors: [.cyan, .blue]),
    ]

    static let shoeItems: [SpriteCosmeticItem] = [
        SpriteCosmeticItem(id: "sneakers_white", name: "White Sneakers", slot: .shoes, price: 0, rarity: .common, colors: [.white]),
        SpriteCosmeticItem(id: "sneakers_red", name: "Red Kicks", slot: .shoes, price: 150, rarity: .common, colors: [.red]),
        SpriteCosmeticItem(id: "boots_brown", name: "Hiking Boots", slot: .shoes, price: 300, rarity: .rare, colors: [Color(red: 0.5, green: 0.35, blue: 0.2)]),
        SpriteCosmeticItem(id: "boots_iron", name: "Iron Boots", slot: .shoes, price: 600, rarity: .rare, colors: [Color(white: 0.5)]),
        SpriteCosmeticItem(id: "boots_flame", name: "Flame Boots", slot: .shoes, price: 1000, rarity: .epic, colors: [.orange, .red]),
        SpriteCosmeticItem(id: "hover_boots", name: "Hover Boots", slot: .shoes, price: 50, currencyType: .diamonds, rarity: .legendary, colors: [.cyan, .white]),
    ]

    static let weaponItems: [SpriteCosmeticItem] = [
        SpriteCosmeticItem(id: "wooden_sword", name: "Wooden Sword", slot: .weapon, price: 200, rarity: .common, colors: [Color(red: 0.6, green: 0.4, blue: 0.2)]),
        SpriteCosmeticItem(id: "iron_sword", name: "Iron Sword", slot: .weapon, price: 500, rarity: .rare, colors: [Color(white: 0.7)], secondaryColors: [Color(red: 0.5, green: 0.35, blue: 0.2)]),
        SpriteCosmeticItem(id: "fire_sword", name: "Fire Sword", slot: .weapon, price: 1200, rarity: .epic, colors: [.orange, .red], secondaryColors: [.yellow]),
        SpriteCosmeticItem(id: "staff_arcane", name: "Arcane Staff", slot: .weapon, price: 1000, rarity: .epic, colors: [.purple], secondaryColors: [.cyan]),
        SpriteCosmeticItem(id: "blade_void", name: "Void Blade", slot: .weapon, price: 100, currencyType: .diamonds, rarity: .legendary, colors: [.purple, .black], secondaryColors: [.cyan]),
    ]

    static let capeItems: [SpriteCosmeticItem] = [
        SpriteCosmeticItem(id: "cape_red", name: "Red Cape", slot: .cape, price: 300, rarity: .common, colors: [.red]),
        SpriteCosmeticItem(id: "cape_blue", name: "Blue Cape", slot: .cape, price: 300, rarity: .common, colors: [.blue]),
        SpriteCosmeticItem(id: "cape_shadow", name: "Shadow Cloak", slot: .cape, price: 800, rarity: .rare, colors: [Color(white: 0.15), Color(white: 0.3)]),
        SpriteCosmeticItem(id: "cape_royal", name: "Royal Mantle", slot: .cape, price: 1500, rarity: .epic, colors: [.purple, .indigo], secondaryColors: [.yellow]),
        SpriteCosmeticItem(id: "cape_phoenix", name: "Phoenix Wings", slot: .cape, price: 80, currencyType: .diamonds, rarity: .legendary, colors: [.orange, .red, .yellow]),
    ]

    static let auraItems: [SpriteCosmeticItem] = [
        SpriteCosmeticItem(id: "aura_green", name: "Nature Glow", slot: .aura, price: 400, rarity: .rare, colors: [.green, .mint]),
        SpriteCosmeticItem(id: "aura_fire", name: "Fire Aura", slot: .aura, price: 800, rarity: .rare, colors: [.orange, .red]),
        SpriteCosmeticItem(id: "aura_ice", name: "Frost Aura", slot: .aura, price: 800, rarity: .rare, colors: [.cyan, .blue]),
        SpriteCosmeticItem(id: "aura_lightning", name: "Lightning", slot: .aura, price: 1200, rarity: .epic, colors: [.yellow, .white]),
        SpriteCosmeticItem(id: "aura_void", name: "Void Energy", slot: .aura, price: 100, currencyType: .diamonds, rarity: .legendary, colors: [.purple, .black, .cyan]),
    ]

    static var allItems: [SpriteCosmeticItem] {
        hairItems + hatItems + topItems + bottomItems + shoeItems + weaponItems + capeItems + auraItems
    }

    static func item(withId id: String) -> SpriteCosmeticItem? {
        allItems.first { $0.id == id }
    }
}
