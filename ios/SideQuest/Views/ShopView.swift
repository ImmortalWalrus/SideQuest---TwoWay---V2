import SwiftUI

struct ShopView: View {
    let appState: AppState
    @Environment(\.dismiss) private var dismiss
    @State private var selectedCategory: ShopCategory = .skins
    @State private var purchaseTarget: ShopItem?
    @State private var showPurchaseResult: Bool = false
    @State private var purchaseSuccess: Bool = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    goldBar
                    categoryPicker
                    shopGrid
                }
                .padding(16)
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("Shop")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .alert(purchaseSuccess ? "Purchased!" : "Not Enough Gold", isPresented: $showPurchaseResult) {
                Button("OK") {}
            } message: {
                Text(purchaseSuccess ? "Item added to your collection." : "Earn more gold by completing quests.")
            }
        }
    }

    private var goldBar: some View {
        HStack(spacing: 16) {
            HStack(spacing: 6) {
                Image(systemName: "dollarsign.circle.fill")
                    .foregroundStyle(.yellow)
                    .font(.title3)
                Text("\(appState.profile.gold)")
                    .font(.headline.monospacedDigit())
                Text("Gold")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            HStack(spacing: 6) {
                Image(systemName: "diamond.fill")
                    .foregroundStyle(.cyan)
                    .font(.title3)
                Text("\(appState.profile.diamonds)")
                    .font(.headline.monospacedDigit())
                Text("Diamonds")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(14)
        .background(Color(.secondarySystemGroupedBackground), in: .rect(cornerRadius: 14))
    }

    private var categoryPicker: some View {
        ScrollView(.horizontal) {
            HStack(spacing: 8) {
                ForEach(ShopCategory.allCases) { category in
                    Button {
                        withAnimation(.snappy) {
                            selectedCategory = category
                        }
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: category.icon)
                            Text(category.rawValue)
                        }
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(selectedCategory == category ? .white : .primary)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 8)
                        .background {
                            if selectedCategory == category {
                                Capsule().fill(.blue)
                            } else {
                                Capsule().fill(Color(.tertiarySystemGroupedBackground))
                            }
                        }
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .contentMargins(.horizontal, 0)
        .scrollIndicators(.hidden)
    }

    private var shopGrid: some View {
        let columns: [GridItem] = [
            GridItem(.flexible(), spacing: 12),
            GridItem(.flexible(), spacing: 12)
        ]

        return LazyVGrid(columns: columns, spacing: 12) {
            ForEach(shopItems, id: \.name) { item in
                let owned: Bool = isOwned(item)
                let equipped: Bool = isEquipped(item)

                Button {
                    handleTap(on: item, owned: owned)
                } label: {
                    VStack(spacing: 8) {
                        previewCard(for: item, equipped: equipped, owned: owned)

                        Text(item.name)
                            .font(.subheadline.weight(.medium))
                            .multilineTextAlignment(.center)
                            .lineLimit(2)
                            .frame(maxWidth: .infinity)

                        itemStatus(for: item, owned: owned, equipped: equipped)
                    }
                    .padding(10)
                    .background(Color(.secondarySystemGroupedBackground), in: .rect(cornerRadius: 14))
                }
                .buttonStyle(.plain)
            }
        }
        .confirmationDialog(
            "Purchase \(purchaseTarget?.name ?? "")?",
            isPresented: Binding(
                get: { purchaseTarget != nil },
                set: { if !$0 { purchaseTarget = nil } }
            ),
            titleVisibility: .visible
        ) {
            if let item = purchaseTarget {
                Button("Buy for \(item.price) Gold") {
                    purchaseSuccess = appState.purchaseItem(name: item.name, price: item.price)
                    showPurchaseResult = true
                    purchaseTarget = nil
                }
                Button("Cancel", role: .cancel) {
                    purchaseTarget = nil
                }
            }
        } message: {
            if let item = purchaseTarget {
                Text("You have \(appState.profile.gold) gold. This costs \(item.price) gold.")
            }
        }
    }

    private func previewCard(for item: ShopItem, equipped: Bool, owned: Bool) -> some View {
        RoundedRectangle(cornerRadius: 12)
            .fill(item.gradient)
            .frame(height: 120)
            .overlay {
                switch selectedCategory {
                case .skins:
                    if let characterType = item.characterType {
                        Character3DView(
                            characterType: characterType,
                            allowsControl: false,
                            autoRotate: true,
                            framing: .fullBody,
                            modelYawDegrees: 180
                        )
                        .padding(6)
                        .allowsHitTesting(false)
                    }
                case .callingCards:
                    VStack(spacing: 10) {
                        Image(systemName: "person.crop.circle.fill")
                            .font(.system(size: 34, weight: .semibold))
                            .foregroundStyle(.white.opacity(0.95))
                        Text("Profile Background")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.white.opacity(0.9))
                    }
                case .effects:
                    ZStack {
                        Circle()
                            .fill(.black.opacity(0.18))
                            .frame(width: 78, height: 78)
                        CharacterEffectView(effectName: item.name, diameter: 82)
                    }
                case .removeAds:
                    Image(systemName: item.icon)
                        .font(.system(size: 36, weight: .semibold))
                        .foregroundStyle(.white)
                }
            }
            .overlay(alignment: .topLeading) {
                if selectedCategory == .skins, let characterType = item.characterType {
                    Image(systemName: characterType.iconName)
                        .font(.caption.weight(.bold))
                        .foregroundStyle(.white)
                        .padding(8)
                }
            }
            .overlay(alignment: .topTrailing) {
                if equipped {
                    Image(systemName: "star.circle.fill")
                        .font(.title3)
                        .foregroundStyle(.yellow)
                        .background(.black.opacity(0.35), in: Circle())
                        .padding(6)
                } else if owned {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.title3)
                        .foregroundStyle(.white)
                        .background(.green, in: Circle())
                        .padding(6)
                }
            }
            .clipShape(.rect(cornerRadius: 12))
    }

    @ViewBuilder
    private func itemStatus(for item: ShopItem, owned: Bool, equipped: Bool) -> some View {
        if equipped {
            Text(selectedCategory == .skins ? "Selected" : "Tap to Unequip")
                .font(.caption.weight(.bold))
                .foregroundStyle(selectedCategory == .skins ? .green : .yellow)
        } else if owned {
            Text(selectedCategory == .skins ? "Tap to Select" : "Tap to Equip")
                .font(.caption.weight(.bold))
                .foregroundStyle(.blue)
        } else {
            HStack(spacing: 4) {
                Image(systemName: "dollarsign.circle.fill")
                    .foregroundStyle(.yellow)
                Text("\(item.price)")
                    .font(.caption.weight(.bold))
            }
        }
    }

    private var shopItems: [ShopItem] {
        switch selectedCategory {
        case .skins:
            return PlayerCharacterType.allCases.map { character in
                ShopItem(
                    name: character.displayName,
                    icon: character.iconName,
                    price: character.shopPrice,
                    gradient: characterGradient(for: character),
                    characterType: character
                )
            }
        case .callingCards:
            return [
                ShopItem(name: "Sunset Blaze", icon: "sun.max.fill", price: 200, gradient: .linearGradient(colors: [.orange, .red], startPoint: .topLeading, endPoint: .bottomTrailing), characterType: nil),
                ShopItem(name: "Arctic Frost", icon: "snowflake", price: 220, gradient: .linearGradient(colors: [.cyan, .blue], startPoint: .topLeading, endPoint: .bottomTrailing), characterType: nil),
                ShopItem(name: "Royal Night", icon: "moon.stars.fill", price: 250, gradient: .linearGradient(colors: [.indigo, .purple], startPoint: .topLeading, endPoint: .bottomTrailing), characterType: nil),
                ShopItem(name: "Emerald Dream", icon: "leaf.fill", price: 220, gradient: .linearGradient(colors: [.green, .mint], startPoint: .topLeading, endPoint: .bottomTrailing), characterType: nil)
            ]
        case .effects:
            return [
                ShopItem(name: "Fire Aura", icon: "flame.fill", price: 800, gradient: .linearGradient(colors: [.red, .orange], startPoint: .topLeading, endPoint: .bottomTrailing), characterType: nil),
                ShopItem(name: "Lightning", icon: "bolt.fill", price: 700, gradient: .linearGradient(colors: [.yellow, .orange], startPoint: .topLeading, endPoint: .bottomTrailing), characterType: nil),
                ShopItem(name: "Frost Ring", icon: "snowflake", price: 750, gradient: .linearGradient(colors: [.cyan, .white], startPoint: .topLeading, endPoint: .bottomTrailing), characterType: nil)
            ]
        case .removeAds:
            return [
                ShopItem(name: "Remove Ads", icon: "xmark.circle.fill", price: 0, gradient: .linearGradient(colors: [.gray, .secondary], startPoint: .topLeading, endPoint: .bottomTrailing), characterType: nil)
            ]
        }
    }

    private func characterGradient(for character: PlayerCharacterType) -> LinearGradient {
        switch character {
        case .amazonWarrior:
            LinearGradient(colors: [.pink, .purple], startPoint: .topLeading, endPoint: .bottomTrailing)
        case .barbarian:
            LinearGradient(colors: [.orange, .red], startPoint: .topLeading, endPoint: .bottomTrailing)
        case .gladiator:
            LinearGradient(colors: [.indigo, .purple], startPoint: .topLeading, endPoint: .bottomTrailing)
        case .gunslinger:
            LinearGradient(colors: [.brown, .orange], startPoint: .topLeading, endPoint: .bottomTrailing)
        case .knight:
            LinearGradient(colors: [.blue, .cyan], startPoint: .topLeading, endPoint: .bottomTrailing)
        }
    }

    private func isOwned(_ item: ShopItem) -> Bool {
        if let characterType = item.characterType {
            return characterType.isStarterSkin || appState.profile.ownedItems.contains(item.name)
        }
        return appState.profile.ownedItems.contains(item.name)
    }

    private func isEquipped(_ item: ShopItem) -> Bool {
        switch selectedCategory {
        case .skins:
            if let characterType = item.characterType {
                return appState.profile.selectedCharacter == characterType
            }
            return appState.profile.equippedSkin == item.name
        case .callingCards:
            return appState.profile.equippedCallingCard == item.name
        case .effects:
            return appState.profile.equippedEffect == item.name
        case .removeAds:
            return false
        }
    }

    private func handleTap(on item: ShopItem, owned: Bool) {
        guard selectedCategory != .removeAds else { return }

        if owned {
            appState.equipItem(name: item.name, category: selectedCategory)
        } else {
            purchaseTarget = item
        }
    }
}

struct ShopItem {
    let name: String
    let icon: String
    let price: Int
    let gradient: LinearGradient
    let characterType: PlayerCharacterType?
}

nonisolated enum ShopCategory: String, CaseIterable, Identifiable {
    case skins = "Skins"
    case callingCards = "Backgrounds"
    case effects = "Effects"
    case removeAds = "Remove Ads"

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .skins: "person.fill"
        case .callingCards: "photo.stack.fill"
        case .effects: "sparkles"
        case .removeAds: "xmark.circle"
        }
    }
}
