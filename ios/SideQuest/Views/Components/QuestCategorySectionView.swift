import SwiftUI

struct QuestCategorySectionView: View {
    let category: QuestCategory
    let quests: [Quest]
    let pathColor: Color
    let savedQuestIds: [String]
    let onSelectQuest: (Quest) -> Void
    let onToggleSave: (String) -> Void

    @State private var isExpanded: Bool = false

    private var recommendedQuest: Quest {
        quests.first(where: { $0.isFeatured }) ??
        quests.sorted(by: { $0.completionCount > $1.completionCount }).first ??
        quests[0]
    }

    private var remainingQuests: [Quest] {
        quests.filter { $0.id != recommendedQuest.id }
    }

    var body: some View {
        VStack(spacing: 8) {
            Button {
                withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
                    isExpanded.toggle()
                }
            } label: {
                categoryHeader
            }
            .buttonStyle(.plain)
            .sensoryFeedback(.impact(weight: .light), trigger: isExpanded)

            questCardWithSave(quest: recommendedQuest)

            if isExpanded {
                ForEach(remainingQuests) { quest in
                    questCardWithSave(quest: quest)
                        .transition(.opacity.combined(with: .move(edge: .top)))
                }
            }
        }
        .padding(.vertical, 4)
    }

    private var categoryHeader: some View {
        HStack(spacing: 10) {
            Image(systemName: category.icon)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(pathColor)
                .frame(width: 30, height: 30)
                .background(pathColor.opacity(0.12), in: .rect(cornerRadius: 8))

            VStack(alignment: .leading, spacing: 1) {
                Text(category.rawValue)
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(.white)
                Text("\(quests.count) challenge\(quests.count == 1 ? "" : "s")")
                    .font(.caption2)
                    .foregroundStyle(.white.opacity(0.4))
            }

            Spacer()

            if !remainingQuests.isEmpty {
                HStack(spacing: 4) {
                    Text(isExpanded ? "Show less" : "+\(remainingQuests.count) more")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(pathColor)
                    Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(pathColor)
                }
            }
        }
    }

    private func questCardWithSave(quest: Quest) -> some View {
        let saved = savedQuestIds.contains(quest.id)
        return ZStack(alignment: .topTrailing) {
            Button { onSelectQuest(quest) } label: {
                QuestCardView(quest: quest)
            }
            .buttonStyle(.plain)

            Button {
                withAnimation(.spring(response: 0.3, dampingFraction: 0.6)) {
                    onToggleSave(quest.id)
                }
            } label: {
                Image(systemName: saved ? "heart.fill" : "heart")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(saved ? .red : .white.opacity(0.7))
                    .padding(10)
                    .background(.ultraThinMaterial, in: Circle())
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .padding(8)
            .sensoryFeedback(.impact(weight: .light), trigger: saved)
        }
    }
}
