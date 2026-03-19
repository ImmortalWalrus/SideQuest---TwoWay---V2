import SwiftUI
import UIKit

private let sheetBg = Color(red: 0.086, green: 0.094, blue: 0.110)
private let sheetCard = Color(red: 0.161, green: 0.169, blue: 0.204)

struct QuestFamilyDetailSheet: View {
    let family: QuestFamily
    let appState: AppState
    let onSelectQuest: (Quest) -> Void

    private var pathColor: Color { PathColorHelper.color(for: family.path) }

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                headerSection
                    .padding(.bottom, 16)

                ladderSection
                    .padding(.horizontal, 16)
                    .padding(.bottom, 24)
            }
            .padding(.top, 20)
        }
        .scrollIndicators(.hidden)
        .background(sheetBg)
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
        .presentationContentInteraction(.scrolls)
    }

    private var headerSection: some View {
        VStack(spacing: 12) {
            Image(systemName: family.category.icon)
                .font(.system(size: 28, weight: .bold))
                .foregroundStyle(pathColor)
                .frame(width: 56, height: 56)
                .background(pathColor.opacity(0.15), in: .rect(cornerRadius: 16))

            Text(family.name)
                .font(.title2.weight(.bold))
                .foregroundStyle(.white)

            HStack(spacing: 16) {
                HStack(spacing: 4) {
                    Image(systemName: "list.number")
                        .font(.caption2.weight(.bold))
                    Text("\(family.quests.count) levels")
                        .font(.caption.weight(.semibold))
                }
                .foregroundStyle(.white.opacity(0.5))

                HStack(spacing: 4) {
                    difficultyRange
                }

                HStack(spacing: 4) {
                    Image(systemName: "bolt.fill")
                        .font(.caption2)
                    if family.xpRange.lowerBound == family.xpRange.upperBound {
                        Text("\(family.xpRange.lowerBound) XP")
                            .font(.caption.weight(.semibold))
                    } else {
                        Text("\(family.xpRange.lowerBound)–\(family.xpRange.upperBound) XP")
                            .font(.caption.weight(.semibold))
                    }
                }
                .foregroundStyle(.orange)
            }
        }
        .frame(maxWidth: .infinity)
    }

    private var difficultyRange: some View {
        HStack(spacing: 3) {
            ForEach(family.difficulties, id: \.rawValue) { diff in
                Text(diff.rawValue)
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(diffColor(diff))
            }
        }
    }

    private var ladderSection: some View {
        VStack(spacing: 0) {
            ForEach(Array(family.quests.enumerated()), id: \.element.id) { index, quest in
                let isRecommended = quest.id == family.recommendedQuest.id
                let isLast = index == family.quests.count - 1

                HStack(spacing: 0) {
                    ladderIndicator(index: index, isLast: isLast, isRecommended: isRecommended)
                        .frame(width: 36)

                    ladderQuestRow(quest: quest, index: index, isRecommended: isRecommended)
                }
            }
        }
    }

    private func ladderIndicator(index: Int, isLast: Bool, isRecommended: Bool) -> some View {
        VStack(spacing: 0) {
            if index > 0 {
                Rectangle()
                    .fill(pathColor.opacity(0.2))
                    .frame(width: 2)
                    .frame(maxHeight: .infinity)
            } else {
                Spacer()
                    .frame(maxHeight: .infinity)
            }

            ZStack {
                Circle()
                    .fill(isRecommended ? pathColor : sheetCard)
                    .frame(width: 22, height: 22)
                if isRecommended {
                    Image(systemName: "star.fill")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(.white)
                } else {
                    Text("\(index + 1)")
                        .font(.system(size: 10, weight: .bold).monospacedDigit())
                        .foregroundStyle(.white.opacity(0.5))
                }
            }

            if !isLast {
                Rectangle()
                    .fill(pathColor.opacity(0.2))
                    .frame(width: 2)
                    .frame(maxHeight: .infinity)
            } else {
                Spacer()
                    .frame(maxHeight: .infinity)
            }
        }
    }

    private func ladderQuestRow(quest: Quest, index: Int, isRecommended: Bool) -> some View {
        let saved = appState.isQuestSaved(quest.id)
        return Button {
            onSelectQuest(quest)
        } label: {
            HStack(spacing: 12) {
                thumbnailForQuest(quest)
                    .frame(width: 52, height: 52)
                    .clipShape(.rect(cornerRadius: 10))

                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 6) {
                        Text(quest.title)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.white)
                            .lineLimit(1)
                        if isRecommended {
                            Text("NEXT")
                                .font(.system(size: 9, weight: .black))
                                .foregroundStyle(pathColor)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(pathColor.opacity(0.15), in: Capsule())
                        }
                    }

                    HStack(spacing: 8) {
                        DifficultyBadge(difficulty: quest.difficulty)

                        HStack(spacing: 3) {
                            Image(systemName: "bolt.fill")
                                .font(.system(size: 9))
                            Text("\(quest.xpReward) XP")
                                .font(.caption2.weight(.bold))
                        }
                        .foregroundStyle(.orange)

                        HStack(spacing: 3) {
                            Image(systemName: "clock.fill")
                                .font(.system(size: 8))
                            Text("\(quest.minCompletionMinutes)m")
                                .font(.caption2.weight(.semibold))
                        }
                        .foregroundStyle(.white.opacity(0.4))

                        if quest.goldReward > 0 {
                            HStack(spacing: 2) {
                                Image(systemName: "dollarsign.circle.fill")
                                    .font(.system(size: 8))
                                Text("\(quest.goldReward)")
                                    .font(.caption2.weight(.bold))
                            }
                            .foregroundStyle(.yellow)
                        }
                    }
                }

                Spacer(minLength: 0)

                VStack(spacing: 6) {
                    Button {
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.6)) {
                            appState.toggleSavedQuest(quest.id)
                        }
                    } label: {
                        Image(systemName: saved ? "heart.fill" : "heart")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(saved ? .red : .white.opacity(0.4))
                    }
                    .buttonStyle(.plain)

                    Image(systemName: "chevron.right")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.2))
                }
            }
            .padding(12)
            .background {
                if isRecommended {
                    sheetCard.opacity(0.9)
                        .overlay(
                            RoundedRectangle(cornerRadius: 14)
                                .strokeBorder(pathColor.opacity(0.2), lineWidth: 1)
                        )
                } else {
                    sheetCard.opacity(0.5)
                        .overlay(
                            RoundedRectangle(cornerRadius: 14)
                                .strokeBorder(.white.opacity(0.05), lineWidth: 1)
                        )
                }
            }
            .clipShape(.rect(cornerRadius: 14))
        }
        .buttonStyle(.plain)
        .padding(.vertical, 4)
    }

    private func thumbnailForQuest(_ quest: Quest) -> some View {
        let pair = QuestAssetMapping.assets(for: quest.title)
        return ZStack {
            sheetCard

            if let url = Bundle.main.url(forResource: pair.banner, withExtension: "jpg", subdirectory: "Resources/QuestBanners"),
               let img = UIImage(contentsOfFile: url.path) {
                Image(uiImage: img)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .allowsHitTesting(false)
            } else {
                PathColorHelper.color(for: quest.path).opacity(0.2)
            }
        }
    }

    private func diffColor(_ diff: QuestDifficulty) -> Color {
        switch diff {
        case .easy: .green
        case .medium: .orange
        case .hard: .red
        case .expert: .purple
        }
    }
}
