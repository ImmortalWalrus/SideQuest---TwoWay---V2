import SwiftUI

struct SpriteShopView: View {
    let appState: AppState
    @Environment(\.dismiss) private var dismiss
    @State private var selectedSlot: SpriteSlot = .hair
    @State private var purchaseTarget: SpriteCosmeticItem?
    @State private var showPurchaseResult: Bool = false
    @State private var purchaseSuccess: Bool = false
    @State private var showBodyColorPicker: Bool = false

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                spritePreview
                currencyBar
                slotPicker
                itemGrid
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("Sprite Shop")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .alert(purchaseSuccess ? "Purchased!" : "Not Enough Currency", isPresented: $showPurchaseResult) {
                Button("OK") {}
            } message: {
                Text(purchaseSuccess ? "Item added to your collection. Tap to equip." : "Earn more by completing quests.")
            }
            .sheet(isPresented: $showBodyColorPicker) {
                bodyColorSheet
            }
        }
    }

    private var spritePreview: some View {
        VStack(spacing: 8) {
            ZStack {
                RoundedRectangle(cornerRadius: 16)
                    .fill(
                        LinearGradient(
                            colors: [Color(red: 0.1, green: 0.08, blue: 0.2), Color(red: 0.2, green: 0.12, blue: 0.35)],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                    .frame(height: 160)

                HStack(spacing: 0) {
                    Spacer()
                    SpriteAvatarView(
                        loadout: appState.profile.spriteLoadout,
                        size: 120,
                        isWalking: true
                    )
                    Spacer()
                }

                VStack {
                    Spacer()
                    HStack {
                        Button {
                            showBodyColorPicker = true
                        } label: {
                            HStack(spacing: 4) {
                                Circle()
                                    .fill(appState.profile.spriteLoadout.bodyColor.color)
                                    .frame(width: 16, height: 16)
                                    .overlay(Circle().strokeBorder(.white.opacity(0.5), lineWidth: 1))
                                Text("Skin")
                                    .font(.caption2.weight(.medium))
                                    .foregroundStyle(.white)
                            }
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .background(.ultraThinMaterial, in: Capsule())
                        }
                        .buttonStyle(.plain)
                        Spacer()
                    }
                    .padding(12)
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)
        }
    }

    private var currencyBar: some View {
        HStack(spacing: 0) {
            HStack(spacing: 6) {
                Image(systemName: "dollarsign.circle.fill")
                    .foregroundStyle(.yellow)
                Text("\(appState.profile.gold)")
                    .font(.subheadline.weight(.bold).monospacedDigit())
                Text("Gold")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity)

            Divider().frame(height: 24)

            HStack(spacing: 6) {
                Image(systemName: "diamond.fill")
                    .foregroundStyle(.cyan)
                Text("\(appState.profile.diamonds)")
                    .font(.subheadline.weight(.bold).monospacedDigit())
                Text("Diamonds")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity)
        }
        .padding(.vertical, 10)
        .padding(.horizontal, 16)
    }

    private var slotPicker: some View {
        ScrollView(.horizontal) {
            HStack(spacing: 6) {
                ForEach(SpriteSlot.allCases) { slot in
                    Button {
                        withAnimation(.snappy) { selectedSlot = slot }
                    } label: {
                        VStack(spacing: 3) {
                            Image(systemName: slot.icon)
                                .font(.caption)
                            Text(slot.rawValue)
                                .font(.system(size: 10, weight: .medium))
                        }
                        .foregroundStyle(selectedSlot == slot ? .white : .primary)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background {
                            if selectedSlot == slot {
                                RoundedRectangle(cornerRadius: 10).fill(.blue)
                            } else {
                                RoundedRectangle(cornerRadius: 10).fill(Color(.tertiarySystemGroupedBackground))
                            }
                        }
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .contentMargins(.horizontal, 16)
        .scrollIndicators(.hidden)
        .padding(.bottom, 8)
    }

    private var itemGrid: some View {
        let items = SpriteCosmeticsCatalog.items(for: selectedSlot)
        let columns = [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)]

        return ScrollView {
            LazyVGrid(columns: columns, spacing: 10) {
                ForEach(items) { item in
                    let owned = appState.profile.ownedSpriteItems.contains(item.id)
                    let equipped = appState.profile.spriteLoadout.item(for: selectedSlot) == item.id

                    Button {
                        if owned {
                            appState.equipSpriteItem(item.id, slot: selectedSlot)
                        } else {
                            purchaseTarget = item
                        }
                    } label: {
                        VStack(spacing: 6) {
                            ZStack {
                                RoundedRectangle(cornerRadius: 12)
                                    .fill(
                                        LinearGradient(
                                            colors: item.colors.isEmpty ? [.gray] : item.colors,
                                            startPoint: .topLeading,
                                            endPoint: .bottomTrailing
                                        )
                                    )
                                    .frame(height: 80)
                                    .overlay(alignment: .topTrailing) {
                                        if equipped {
                                            Image(systemName: "star.circle.fill")
                                                .font(.caption)
                                                .foregroundStyle(.yellow)
                                                .background(.black.opacity(0.5), in: Circle())
                                                .padding(6)
                                        } else if owned {
                                            Image(systemName: "checkmark.circle.fill")
                                                .font(.caption)
                                                .foregroundStyle(.white)
                                                .background(.green, in: Circle())
                                                .padding(6)
                                        }
                                    }
                                    .overlay(alignment: .topLeading) {
                                        Text(item.rarity.rawValue)
                                            .font(.system(size: 8, weight: .heavy))
                                            .foregroundStyle(item.rarity.color)
                                            .padding(.horizontal, 6)
                                            .padding(.vertical, 2)
                                            .background(.black.opacity(0.5), in: Capsule())
                                            .padding(6)
                                    }
                                    .overlay(alignment: .bottom) {
                                        if equipped {
                                            Text("EQUIPPED")
                                                .font(.system(size: 8, weight: .black))
                                                .foregroundStyle(.white)
                                                .padding(.horizontal, 8)
                                                .padding(.vertical, 2)
                                                .background(.yellow.gradient, in: Capsule())
                                                .padding(.bottom, 6)
                                        }
                                    }

                                Image(systemName: selectedSlot.icon)
                                    .font(.title2)
                                    .foregroundStyle(.white.opacity(0.9))
                                    .shadow(color: .black.opacity(0.5), radius: 4)
                            }

                            Text(item.name)
                                .font(.caption.weight(.semibold))
                                .lineLimit(1)

                            if equipped {
                                Text("Tap to Unequip")
                                    .font(.system(size: 9, weight: .bold))
                                    .foregroundStyle(.yellow)
                            } else if owned {
                                Text("Tap to Equip")
                                    .font(.system(size: 9, weight: .bold))
                                    .foregroundStyle(.blue)
                            } else {
                                HStack(spacing: 3) {
                                    Image(systemName: item.currencyType == .gold ? "dollarsign.circle.fill" : "diamond.fill")
                                        .font(.system(size: 9))
                                        .foregroundStyle(item.currencyType == .gold ? .yellow : .cyan)
                                    Text("\(item.price)")
                                        .font(.caption2.weight(.bold))
                                }
                            }
                        }
                        .padding(8)
                        .background(Color(.secondarySystemGroupedBackground), in: .rect(cornerRadius: 14))
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 20)
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
                let currencyLabel = item.currencyType == .gold ? "Gold" : "Diamonds"
                Button("Buy for \(item.price) \(currencyLabel)") {
                    purchaseSuccess = appState.purchaseSpriteItem(item)
                    showPurchaseResult = true
                    purchaseTarget = nil
                }
                Button("Cancel", role: .cancel) { purchaseTarget = nil }
            }
        } message: {
            if let item = purchaseTarget {
                let balance = item.currencyType == .gold ? appState.profile.gold : appState.profile.diamonds
                let label = item.currencyType == .gold ? "gold" : "diamonds"
                Text("You have \(balance) \(label). This costs \(item.price).")
            }
        }
    }

    private var bodyColorSheet: some View {
        NavigationStack {
            VStack(spacing: 20) {
                SpriteAvatarView(
                    loadout: appState.profile.spriteLoadout,
                    size: 100
                )

                VStack(spacing: 12) {
                    Text("Choose Skin Tone")
                        .font(.headline)

                    HStack(spacing: 16) {
                        ForEach(SpriteBodyColor.allCases, id: \.rawValue) { bodyColor in
                            let isSelected = appState.profile.spriteLoadout.bodyColor == bodyColor
                            Button {
                                appState.setSpriteBodyColor(bodyColor)
                            } label: {
                                Circle()
                                    .fill(bodyColor.color)
                                    .frame(width: 48, height: 48)
                                    .overlay {
                                        Circle().strokeBorder(.white, lineWidth: isSelected ? 3 : 0)
                                    }
                                    .overlay {
                                        if isSelected {
                                            Image(systemName: "checkmark")
                                                .font(.caption.weight(.bold))
                                                .foregroundStyle(.white)
                                        }
                                    }
                                    .shadow(color: isSelected ? .blue.opacity(0.5) : .clear, radius: 6)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }

                Spacer()
            }
            .padding(20)
            .navigationTitle("Skin Tone")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { showBodyColorPicker = false }
                }
            }
        }
        .presentationDetents([.medium])
    }
}
