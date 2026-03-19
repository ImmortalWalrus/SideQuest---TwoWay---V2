import SwiftUI
import UIKit

struct AchievementsView: View {
    let appState: AppState
    @Environment(\.dismiss) private var dismiss
    @State private var selectedCategory: AchievementCategory? = nil

    private var filteredAchievements: [Achievement] {
        if let cat = selectedCategory {
            return AchievementCatalog.all.filter { $0.category == cat }
        }
        return AchievementCatalog.all
    }

    private var earnedCount: Int {
        AchievementCatalog.all.filter { appState.profile.earnedBadges.contains($0.id) }.count
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    summaryCard
                    categoryFilter
                    badgeGrid
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 20)
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("Achievements")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }

    private var summaryCard: some View {
        VStack(spacing: 12) {
            ZStack {
                Circle()
                    .stroke(Color(.tertiarySystemGroupedBackground), lineWidth: 6)
                    .frame(width: 80, height: 80)
                Circle()
                    .trim(from: 0, to: Double(earnedCount) / Double(AchievementCatalog.all.count))
                    .stroke(Color.orange, style: StrokeStyle(lineWidth: 6, lineCap: .round))
                    .frame(width: 80, height: 80)
                    .rotationEffect(.degrees(-90))
                VStack(spacing: 0) {
                    Text("\(earnedCount)")
                        .font(.title2.weight(.heavy).monospacedDigit())
                    Text("of \(AchievementCatalog.all.count)")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
            Text("Badges Earned")
                .font(.headline)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 20)
        .background(Color(.secondarySystemGroupedBackground), in: .rect(cornerRadius: 16))
    }

    private var categoryFilter: some View {
        ScrollView(.horizontal) {
            HStack(spacing: 8) {
                Button {
                    withAnimation(.snappy) { selectedCategory = nil }
                } label: {
                    Text("All")
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(selectedCategory == nil ? .white : .primary)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 8)
                        .background {
                            if selectedCategory == nil {
                                Capsule().fill(.blue)
                            } else {
                                Capsule().fill(Color(.tertiarySystemGroupedBackground))
                            }
                        }
                }
                .buttonStyle(.plain)

                ForEach(AchievementCategory.allCases) { cat in
                    Button {
                        withAnimation(.snappy) { selectedCategory = cat }
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: cat.iconName)
                            Text(cat.rawValue)
                        }
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(selectedCategory == cat ? .white : .primary)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 8)
                        .background {
                            if selectedCategory == cat {
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

    private var badgeGrid: some View {
        let columns = [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)]
        return LazyVGrid(columns: columns, spacing: 12) {
            ForEach(filteredAchievements) { achievement in
                let earned = appState.profile.earnedBadges.contains(achievement.id)
                achievementCard(achievement, earned: earned)
            }
        }
    }

    private func achievementCard(_ achievement: Achievement, earned: Bool) -> some View {
        VStack(spacing: 10) {
            ZStack {
                Circle()
                    .fill(earned ? badgeGradient(achievement.badgeColor) : AnyShapeStyle(Color(.tertiarySystemGroupedBackground)))
                    .frame(width: 56, height: 56)

                if let badgeImage = badgeArtImage(for: achievement) {
                    Image(uiImage: badgeImage)
                        .resizable()
                        .interpolation(.none)
                        .aspectRatio(contentMode: .fit)
                        .frame(width: 44, height: 44)
                        .saturation(earned ? 1.0 : 0)
                        .opacity(earned ? 1.0 : 0.5)
                } else {
                    Image(systemName: achievement.iconName)
                        .font(.title2)
                        .foregroundStyle(earned ? .white : .secondary)
                }
            }

            VStack(spacing: 3) {
                Text(achievement.title)
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(1)
                Text(achievement.description)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
            }

            if earned {
                HStack(spacing: 4) {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.caption2)
                    Text("Earned")
                        .font(.caption2.weight(.bold))
                }
                .foregroundStyle(.green)
            } else {
                Text("Locked")
                    .font(.caption2.weight(.medium))
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity)
        .background(Color(.secondarySystemGroupedBackground), in: .rect(cornerRadius: 14))
        .opacity(earned ? 1.0 : 0.55)
    }

    private func badgeArtImage(for achievement: Achievement) -> UIImage? {
        let category = BadgeVisualCategory.category(for: achievement)
        return UIImage(named: category.badgeImageName)
    }

    private func badgeGradient(_ colorName: String) -> AnyShapeStyle {
        let color: Color = switch colorName {
        case "green": .green
        case "blue": .blue
        case "purple": .purple
        case "orange": .orange
        case "red": .red
        case "cyan": .cyan
        case "teal": .teal
        case "indigo": .indigo
        case "yellow": .yellow
        default: .blue
        }
        return AnyShapeStyle(color.gradient)
    }
}
