import SwiftUI

struct CharacterSelectionCardView: View {
    let character: PlayerCharacterType
    let isSelected: Bool
    let isEquipped: Bool
    let isOwned: Bool

    private var statusText: String {
        if isSelected {
            return isOwned ? "Selected" : "Previewing"
        }

        return isOwned ? "Tap to preview" : "Locked"
    }

    private var statusColor: Color {
        isOwned ? .secondary : .orange
    }

    private var cardBackgroundColor: Color {
        isSelected ? Color.orange.opacity(0.12) : Color(.secondarySystemGroupedBackground)
    }

    private var cardBorderColor: Color {
        isSelected ? Color.orange.opacity(0.7) : .clear
    }

    private var iconForegroundColor: Color {
        isSelected ? .orange : .secondary
    }

    private var iconBackgroundColor: Color {
        isSelected ? Color.orange.opacity(0.14) : Color(.systemBackground)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            previewCard
            detailsSection
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(cardBackgroundColor, in: .rect(cornerRadius: 20))
        .overlay {
            RoundedRectangle(cornerRadius: 20)
                .stroke(cardBorderColor, lineWidth: 1.5)
        }
    }

    private var previewCard: some View {
        RoundedRectangle(cornerRadius: 16)
            .fill(Color(.tertiarySystemGroupedBackground))
            .frame(height: 104)
            .overlay {
                Character3DView(
                    characterType: character,
                    allowsControl: false,
                    autoRotate: true,
                    framing: .fullBody,
                    modelYawDegrees: 180
                )
                .allowsHitTesting(false)
                .padding(6)
            }
            .clipShape(.rect(cornerRadius: 16))
            .overlay(alignment: .topTrailing) {
                badgeRow
                    .padding(8)
            }
    }

    private var badgeRow: some View {
        HStack(spacing: 6) {
            Image(systemName: character.iconName)
                .font(.caption.weight(.bold))
                .foregroundStyle(iconForegroundColor)
                .frame(width: 28, height: 28)
                .background(iconBackgroundColor, in: Circle())

            accessoryBadge
        }
    }

    @ViewBuilder
    private var accessoryBadge: some View {
        if isEquipped {
            Image(systemName: "checkmark.circle.fill")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.green)
        } else if !isOwned {
            Image(systemName: "lock.fill")
                .font(.caption.weight(.bold))
                .foregroundStyle(.orange)
        }
    }

    private var detailsSection: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(character.displayName)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.primary)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)

            Text(statusText)
                .font(.caption)
                .foregroundStyle(statusColor)
        }
    }
}
