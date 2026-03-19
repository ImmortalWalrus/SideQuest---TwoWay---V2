import SwiftUI

struct CharacterCustomizerView: View {
    let appState: AppState
    @Environment(\.dismiss) private var dismiss
    @State private var selectedCharacter: PlayerCharacterType

    init(appState: AppState) {
        self.appState = appState
        _selectedCharacter = State(initialValue: appState.profile.selectedCharacter)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    previewCard
                    characterInfoCard
                    characterSelector
                }
                .padding(.horizontal, 16)
                .padding(.top, 16)
                .padding(.bottom, 24)
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("Choose Character")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button(selectedCharacterOwned ? "Equip" : "Shop First") {
                        appState.selectCharacter(selectedCharacter)
                        dismiss()
                    }
                    .fontWeight(.semibold)
                    .disabled(!selectedCharacterOwned)
                }
            }
        }
        .sensoryFeedback(.selection, trigger: selectedCharacter)
    }

    private var previewCard: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 28)
                .fill(Color(.secondarySystemGroupedBackground))

            RoundedRectangle(cornerRadius: 28)
                .fill(
                    RadialGradient(
                        colors: [Color.orange.opacity(0.2), .clear],
                        center: .center,
                        startRadius: 10,
                        endRadius: 180
                    )
                )

            Image(systemName: selectedCharacter.iconName)
                .font(.system(size: 72, weight: .bold))
                .foregroundStyle(.orange.opacity(0.18))

            Character3DView(
                characterType: selectedCharacter,
                allowsControl: true,
                autoRotate: false,
                framing: .fullBody,
                modelYawDegrees: 180
            )
            .id(selectedCharacter)
            .padding(12)

            if let equippedEffect = appState.profile.equippedEffect {
                CharacterEffectView(effectName: equippedEffect, diameter: 246)
            }
        }
        .frame(height: 360)
        .clipShape(.rect(cornerRadius: 28))
        .overlay(alignment: .bottomLeading) {
            VStack(alignment: .leading, spacing: 6) {
                Text(selectedCharacter.displayName)
                    .font(.title2.weight(.bold))

                Text("Drag to inspect")
                    .font(.footnote.weight(.medium))
                    .foregroundStyle(.secondary)
            }
            .padding(18)
        }
    }

    private var characterInfoCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 10) {
                Image(systemName: selectedCharacter.iconName)
                    .font(.headline.weight(.bold))
                    .foregroundStyle(.orange)
                    .frame(width: 34, height: 34)
                    .background(Color.orange.opacity(0.12), in: Circle())

                VStack(alignment: .leading, spacing: 2) {
                    Text(selectedCharacter.displayName)
                        .font(.headline)

                    if selectedCharacter == appState.profile.selectedCharacter {
                        Text("Currently Equipped")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.green)
                    } else if selectedCharacterOwned {
                        Text("Owned")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.blue)
                    } else {
                        Text("Unlock in Shop · \(selectedCharacter.shopPrice) gold")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.orange)
                    }
                }

                Spacer()
            }

            Text(selectedCharacter.lore)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(18)
        .background(Color(.secondarySystemGroupedBackground), in: .rect(cornerRadius: 22))
    }

    private var characterSelector: some View {
        let columns: [GridItem] = [
            GridItem(.adaptive(minimum: 150, maximum: 220), spacing: 12)
        ]

        return VStack(alignment: .leading, spacing: 12) {
            Text("Classes")
                .font(.headline)
                .padding(.horizontal, 2)

            LazyVGrid(columns: columns, spacing: 12) {
                ForEach(PlayerCharacterType.allCases) { character in
                    characterCard(character)
                }
            }
        }
    }

    private var selectedCharacterOwned: Bool {
        appState.isCharacterOwned(selectedCharacter)
    }

    private func characterCard(_ character: PlayerCharacterType) -> some View {
        let isSelected: Bool = character == selectedCharacter
        let isEquipped: Bool = character == appState.profile.selectedCharacter
        let isOwned: Bool = appState.isCharacterOwned(character)

        return Button {
            withAnimation(.spring(response: 0.32, dampingFraction: 0.82)) {
                selectedCharacter = character
            }
        } label: {
            CharacterSelectionCardView(
                character: character,
                isSelected: isSelected,
                isEquipped: isEquipped,
                isOwned: isOwned
            )
        }
        .buttonStyle(.plain)
    }
}

