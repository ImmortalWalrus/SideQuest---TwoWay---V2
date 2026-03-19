import SwiftUI

struct SkillTreeDetailView: View {
    let appState: AppState

    var body: some View {
        ScrollView {
            LazyVStack(spacing: 14) {
                skillSummaryHeader
                ForEach(appState.profile.selectedSkills) { skill in
                    SkillTreeCard(skill: skill, appState: appState)
                }
                footerHint
            }
            .padding(.horizontal, 16)
            .padding(.top, 4)
            .padding(.bottom, 24)
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle("Skill Trees")
        .navigationBarTitleDisplayMode(.large)
    }

    private var skillSummaryHeader: some View {
        let masteredCount = appState.profile.selectedSkills.filter { appState.skillLevel(for: $0) >= 5 }.count
        let totalXP = appState.profile.selectedSkills.reduce(0) { $0 + appState.skillXP(for: $1) }

        return HStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 2) {
                Text("\(appState.profile.selectedSkills.count) Skills Active")
                    .font(.subheadline.weight(.semibold))
                Text("Earn skill XP by completing tagged quests")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Divider().frame(height: 36)

            VStack(spacing: 2) {
                Text("\(totalXP.formatted())")
                    .font(.title3.weight(.black))
                    .foregroundStyle(.orange)
                Text("Total XP")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity)

            if masteredCount > 0 {
                Divider().frame(height: 36)

                VStack(spacing: 2) {
                    Text("\(masteredCount)")
                        .font(.title3.weight(.black))
                        .foregroundStyle(.yellow)
                    Text("Mastered")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity)
            }
        }
        .padding(.vertical, 14)
        .padding(.horizontal, 16)
        .background(Color(.secondarySystemGroupedBackground), in: .rect(cornerRadius: 14))
    }

    private var footerHint: some View {
        Text("Complete quests tagged with a skill to earn XP and level up your skill tree.")
            .font(.caption)
            .foregroundStyle(.tertiary)
            .multilineTextAlignment(.center)
            .padding(.horizontal, 8)
            .padding(.vertical, 8)
    }
}

struct SkillTreeCard: View {
    let skill: UserSkill
    let appState: AppState

    private var level: Int { appState.skillLevel(for: skill) }
    private var xp: Int { appState.skillXP(for: skill) }
    private var progress: Double { appState.skillProgress(for: skill) }
    private var tierName: String { appState.skillTierName(for: skill) }
    private var xpToNext: Int { appState.skillXPToNextLevel(for: skill) }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            skillHeader
            tierProgressNodes
            xpProgressSection
        }
        .padding(16)
        .background(skill.color.opacity(0.04), in: .rect(cornerRadius: 16))
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .strokeBorder(skill.color.opacity(0.15), lineWidth: 1)
        )
    }

    private var skillHeader: some View {
        HStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 12)
                    .fill(skill.color.opacity(0.12))
                    .frame(width: 48, height: 48)
                Image(systemName: skill.icon)
                    .font(.title3)
                    .foregroundStyle(skill.color)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(skill.rawValue)
                    .font(.headline)
                Text(skill.description)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 2) {
                Text("Lv \(level)")
                    .font(.title2.weight(.black))
                    .foregroundStyle(skill.color)
                Text(tierName)
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(skill.color.opacity(0.8))
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(skill.color.opacity(0.12), in: Capsule())
            }
        }
    }

    private var tierProgressNodes: some View {
        HStack(alignment: .top, spacing: 0) {
            ForEach(0..<5, id: \.self) { i in
                VStack(spacing: 5) {
                    ZStack {
                        Circle()
                            .fill(i < level ? skill.color : Color(.tertiarySystemGroupedBackground))
                            .frame(width: 26, height: 26)
                        if i < level {
                            Image(systemName: i == level - 1 ? "star.fill" : "checkmark")
                                .font(.system(size: 10, weight: .bold))
                                .foregroundStyle(.white)
                        } else {
                            Image(systemName: "lock.fill")
                                .font(.system(size: 8))
                                .foregroundStyle(Color(.tertiaryLabel))
                        }
                    }
                    .overlay {
                        if i == level - 1 {
                            Circle()
                                .strokeBorder(skill.color.opacity(0.4), lineWidth: 2)
                                .frame(width: 34, height: 34)
                        }
                    }

                    Text(AppState.skillTierNames[i])
                        .font(.system(size: 8, weight: .semibold))
                        .foregroundStyle(i < level ? skill.color : Color(.tertiaryLabel))
                        .minimumScaleFactor(0.5)
                        .lineLimit(1)
                }
                .frame(width: 52)

                if i < 4 {
                    Rectangle()
                        .fill(i < level - 1 ? skill.color : Color(.tertiarySystemGroupedBackground))
                        .frame(maxWidth: .infinity)
                        .frame(height: 2)
                        .padding(.top, 12)
                }
            }
        }
    }

    @ViewBuilder
    private var xpProgressSection: some View {
        if level >= 5 {
            HStack(spacing: 6) {
                Image(systemName: "crown.fill")
                    .font(.caption2)
                    .foregroundStyle(.yellow)
                Text("MAX LEVEL  ·  \(xp.formatted()) XP earned")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.yellow.opacity(0.08), in: Capsule())
        } else {
            VStack(spacing: 5) {
                HStack {
                    Text("\(xp.formatted()) XP")
                        .font(.caption2.weight(.medium))
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text("\(xpToNext.formatted()) XP to \(AppState.skillTierNames[level])")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule()
                            .fill(Color(.tertiarySystemGroupedBackground))
                        Capsule()
                            .fill(skill.color.gradient)
                            .frame(width: max(4, geo.size.width * progress))
                    }
                }
                .frame(height: 6)
                .clipShape(Capsule())
            }
        }
    }
}
