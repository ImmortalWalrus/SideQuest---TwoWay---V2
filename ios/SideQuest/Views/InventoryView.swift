import SwiftUI

struct InventoryView: View {
    let appState: AppState
    @Environment(\.dismiss) private var dismiss
    @State private var selectedRarity: ItemRarity? = nil

    private var inventory: [InventoryItem] {
        let items = appState.storyEngine.globalInventory
        if let rarity = selectedRarity {
            return items.filter { $0.rarity == rarity }
        }
        return items
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                if appState.storyEngine.globalInventory.isEmpty {
                    emptyState
                } else {
                    VStack(spacing: 16) {
                        rarityFilter
                        itemsList
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 8)
                }
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("Inventory")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "shippingbox")
                .font(.system(size: 44))
                .foregroundStyle(.tertiary)
            Text("No Items Yet")
                .font(.title3.weight(.semibold))
            Text("Play through campaigns to collect items, gold, and diamonds.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding(40)
        .frame(maxWidth: .infinity)
    }

    private var rarityFilter: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                filterChip(label: "All", rarity: nil, count: appState.storyEngine.globalInventory.count)
                ForEach(ItemRarity.allCases, id: \.self) { rarity in
                    let count = appState.storyEngine.globalInventory.filter { $0.rarity == rarity }.count
                    if count > 0 {
                        filterChip(label: rarity.rawValue, rarity: rarity, count: count)
                    }
                }
            }
        }
        .contentMargins(.horizontal, 0)
    }

    private func filterChip(label: String, rarity: ItemRarity?, count: Int) -> some View {
        let isSelected = selectedRarity == rarity
        return Button {
            withAnimation(.snappy) { selectedRarity = rarity }
        } label: {
            HStack(spacing: 4) {
                if let rarity {
                    Image(systemName: rarity.iconName)
                        .font(.caption2)
                        .foregroundStyle(rarityColor(rarity))
                }
                Text(label)
                    .font(.caption.weight(.semibold))
                Text("\(count)")
                    .font(.caption2.weight(.bold).monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .background(isSelected ? Color.indigo.opacity(0.15) : Color(.secondarySystemGroupedBackground), in: Capsule())
            .overlay(
                Capsule().strokeBorder(isSelected ? Color.indigo.opacity(0.3) : .clear, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }

    private var itemsList: some View {
        LazyVStack(spacing: 8) {
            ForEach(inventory) { item in
                InventoryItemRow(item: item)
                    .padding(14)
                    .background(Color(.secondarySystemGroupedBackground), in: .rect(cornerRadius: 14))
            }
        }
    }

    private func rarityColor(_ rarity: ItemRarity) -> Color {
        switch rarity {
        case .common: .gray
        case .uncommon: .green
        case .rare: .blue
        case .legendary: .purple
        }
    }
}

struct InventoryItemRow: View {
    let item: InventoryItem

    private var color: Color {
        switch item.rarity {
        case .common: .gray
        case .uncommon: .green
        case .rare: .blue
        case .legendary: .purple
        }
    }

    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(color.opacity(0.12))
                    .frame(width: 40, height: 40)
                Image(systemName: item.rarity.iconName)
                    .font(.body.weight(.semibold))
                    .foregroundStyle(color)
            }
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(item.name)
                        .font(.subheadline.weight(.semibold))
                    Text(item.rarity.rawValue)
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(color)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 2)
                        .background(color.opacity(0.12), in: Capsule())
                }
                Text(item.itemDescription)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                Text(item.storyTitle)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
            Spacer()
        }
    }
}
