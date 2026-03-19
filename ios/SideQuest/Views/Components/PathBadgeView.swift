import SwiftUI

struct PathBadgeView: View {
    let path: QuestPath
    var compact: Bool = false

    private var pathColor: Color {
        switch path {
        case .warrior: .red
        case .explorer: .green
        case .mind: .indigo
        }
    }

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: path.iconName)
                .font(compact ? .caption2 : .caption)
            if !compact {
                Text(path.rawValue)
                    .font(.caption.weight(.semibold))
            }
        }
        .foregroundStyle(pathColor)
        .padding(.horizontal, compact ? 6 : 10)
        .padding(.vertical, 4)
        .background(pathColor.opacity(0.15), in: Capsule())
    }
}

struct DifficultyBadge: View {
    let difficulty: QuestDifficulty

    private var color: Color {
        switch difficulty {
        case .easy: .green
        case .medium: .orange
        case .hard: .red
        case .expert: .purple
        }
    }

    var body: some View {
        Text(difficulty.rawValue)
            .font(.caption2.weight(.bold))
            .foregroundStyle(color)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(color.opacity(0.12), in: Capsule())
    }
}

struct VerifiedBadge: View {
    let isVerified: Bool

    var body: some View {
        Image(systemName: isVerified ? "checkmark.seal.fill" : "info.circle")
            .font(.caption)
            .foregroundStyle(isVerified ? .blue : .secondary)
    }
}

struct PathColorHelper {
    static func color(for path: QuestPath) -> Color {
        switch path {
        case .warrior: .red
        case .explorer: .green
        case .mind: .indigo
        }
    }
}

struct StatPill: View {
    let icon: String
    let value: String
    let label: String
    var color: Color = .secondary

    var body: some View {
        VStack(spacing: 4) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundStyle(color)
            Text(value)
                .font(.headline.monospacedDigit())
            Text(label)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
    }
}
