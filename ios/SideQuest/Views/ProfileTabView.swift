import SwiftUI
import UIKit

struct ProfileTabView: View {
    let appState: AppState
    @State private var showShop: Bool = false
    @State private var showModHub: Bool = false
    @State private var showQuestLog: Bool = false
    @State private var showSettings: Bool = false
    @State private var showEditProfile: Bool = false
    @State private var showReferrals: Bool = false
    @State private var showAchievements: Bool = false
    @State private var showMyQuests: Bool = false
    @State private var showSpriteShop: Bool = false
    @State private var showSkillTrees: Bool = false
    @State private var showCharacterCustomizer: Bool = false

    private let darkBg = Color(red: 0.086, green: 0.094, blue: 0.110)
    private let cardBg = Color(white: 1, opacity: 0.06)
    private let cardBorder = Color(white: 1, opacity: 0.08)
    private let slotBg = Color(white: 1, opacity: 0.05)
    private let slotBorder = Color(white: 1, opacity: 0.10)
    private let goldAccent = Color(red: 0.85, green: 0.68, blue: 0.32)

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                characterHeroArea
                    .padding(.bottom, -70)

                levelSection
                    .padding(.horizontal, 16)
                    .padding(.top, 8)

                pathRanksSection
                    .padding(.horizontal, 16)
                    .padding(.top, 6)

                badgesSection
                    .padding(.horizontal, 16)
                    .padding(.top, 16)

                currencyBar
                    .padding(.horizontal, 16)
                    .padding(.top, 14)

                cosmeticCollectiblesSection
                    .padding(.horizontal, 16)
                    .padding(.top, 18)
                    .padding(.bottom, 24)
            }
        }
        .ignoresSafeArea(edges: .top)
        .background(darkBg.ignoresSafeArea())
        .sheet(isPresented: $showShop) { ShopView(appState: appState) }
        .sheet(isPresented: $showQuestLog) { QuestLogView(appState: appState) }
        .sheet(isPresented: $showSettings) { SettingsView(appState: appState) }
        .sheet(isPresented: $showEditProfile) { EditProfileView(appState: appState) }
        .sheet(isPresented: $showAchievements) { AchievementsView(appState: appState) }
        .sheet(isPresented: $showMyQuests) { MyQuestsView(appState: appState) }
        .sheet(isPresented: $showSpriteShop) { SpriteShopView(appState: appState) }
        .sheet(isPresented: $showSkillTrees) { NavigationStack { SkillTreeDetailView(appState: appState) } }
        .sheet(isPresented: $showCharacterCustomizer) { CharacterCustomizerView(appState: appState) }
        .task { appState.refreshSteps() }
        .onChange(of: appState.deepLinkDestination) { _, newValue in
            guard let destination = newValue else { return }
            switch destination {
            case .questLog: showQuestLog = true
            case .modHub: showModHub = true
            case .shop: showShop = true
            }
        }
    }

    // MARK: - Top Bar

    private var topBar: some View {
        HStack {
            Button { showSettings = true } label: {
                Image(systemName: "chevron.left")
                    .font(.body.weight(.semibold))
                    .foregroundStyle(.white)
                    .frame(width: 36, height: 36)
                    .background(Color(white: 1, opacity: 0.1), in: .rect(cornerRadius: 10))
            }

            Spacer()

            Button { showShop = true } label: {
                Image(systemName: "storefront.fill")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.white.opacity(0.7))
                    .frame(width: 36, height: 36)
                    .background(Color(white: 1, opacity: 0.1), in: .rect(cornerRadius: 10))
            }
        }
    }

    // MARK: - Character Hero

    private var characterHeroArea: some View {
        let bg = darkBg
        return ZStack(alignment: .bottom) {
            bg.ignoresSafeArea(edges: .top)

            RadialGradient(
                colors: [
                    Color(white: 0.48, opacity: 0.46),
                    Color(white: 0.36, opacity: 0.30),
                    Color(white: 0.22, opacity: 0.14),
                    Color(white: 0.12, opacity: 0.04),
                    Color.clear
                ],
                center: .init(x: 0.5, y: 0.06),
                startRadius: 4,
                endRadius: 300
            )

            VStack(spacing: 0) {
                Spacer()
                Canvas { context, size in
                    let h = size.height
                    let w = size.width
                    let steps = 48
                    let sliceH = h / CGFloat(steps)
                    for i in 0..<steps {
                        let t = CGFloat(i) / CGFloat(steps - 1)
                        let alpha = t * t * t
                        let y = CGFloat(i) * sliceH
                        let rect = CGRect(x: 0, y: y, width: w, height: sliceH + 1)
                        context.fill(Path(rect), with: .color(bg.opacity(alpha)))
                    }
                }
                .frame(height: 140)
                .allowsHitTesting(false)
            }

            characterPreview
                .frame(maxWidth: .infinity)

            GeometryReader { geo in
                VStack(spacing: 0) {
                    topBar
                        .padding(.horizontal, 16)
                        .padding(.top, 58)
                        .padding(.bottom, 4)

                    HStack(alignment: .top, spacing: 0) {
                        leftIconSlots
                            .frame(width: 72)

                        Spacer(minLength: 0)

                        rightIconSlots
                            .frame(width: 72)
                    }
                    .padding(.horizontal, 8)
                    .padding(.top, 40)

                    Spacer()
                }
            }
        }
        .frame(minHeight: 460)
    }

    private var characterPreview: some View {
        ZStack(alignment: .bottom) {
            Character3DView(
                characterType: appState.profile.selectedCharacter,
                allowsControl: true,
                autoRotate: false,
                framing: .fullBody,
                modelYawDegrees: appState.profile.selectedCharacter.heroProfileYawDegrees,
                sceneStyle: .heroProfile,
                debugMode: .beauty,
                isActive: appState.selectedTab == 3
            )
            .allowsHitTesting(false)
            .padding(.top, 50)

            if let equippedEffect = appState.profile.equippedEffect {
                CharacterEffectView(effectName: equippedEffect, diameter: 200)
            }
        }
        .onTapGesture(count: 2) {
            showCharacterCustomizer = true
        }
    }

    private var leftIconSlots: some View {
        VStack(spacing: 0) {
            equipSlot(
                imageName: "icon_background",
                label: "Skin",
                isFilled: true
            )
            equipSlotEmpty()
            equipSlotEmpty()
            equipSlotEmpty()
        }
    }

    private var rightIconSlots: some View {
        VStack(spacing: 0) {
            equipSlot(
                imageName: "icon_frame",
                label: "Frame",
                isFilled: true
            )
            equipSlot(
                imageName: "icon_skin",
                label: "Background",
                isFilled: true
            )
            equipSlotEmpty()
            equipSlotEmpty()
        }
    }

    private func equipSlot(imageName: String, label: String, isFilled: Bool) -> some View {
        VStack(spacing: 0) {
            ZStack {
                RoundedRectangle(cornerRadius: 10)
                    .fill(slotBg)
                RoundedRectangle(cornerRadius: 10)
                    .strokeBorder(isFilled ? goldAccent.opacity(0.4) : slotBorder, lineWidth: 1)

                if isFilled, let uiImage = UIImage(named: imageName) {
                    Image(uiImage: uiImage)
                        .resizable()
                        .interpolation(.none)
                        .aspectRatio(contentMode: .fit)
                        .padding(6)
                }
            }
            .frame(width: 48, height: 48)

            Text(label)
                .font(.system(size: 9, weight: .medium))
                .foregroundStyle(.white.opacity(0.5))
                .padding(.top, 2)
                .padding(.bottom, 4)
        }
    }

    private func equipSlotEmpty() -> some View {
        VStack(spacing: 0) {
            RoundedRectangle(cornerRadius: 10)
                .fill(slotBg)
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .strokeBorder(slotBorder, lineWidth: 1)
                )
                .frame(width: 48, height: 48)

            Text(" ")
                .font(.system(size: 9))
                .padding(.top, 2)
                .padding(.bottom, 4)
        }
    }

    // MARK: - Level + XP

    private var levelSection: some View {
        VStack(spacing: 6) {
            HStack(alignment: .firstTextBaseline) {
                Text("Level \(appState.profile.level)")
                    .font(.title3.weight(.bold))
                    .foregroundStyle(.white)
                Spacer()
                Text("Total XP")
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.white.opacity(0.4))
            }

            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(Color(white: 1, opacity: 0.08))
                    Capsule()
                        .fill(
                            LinearGradient(
                                colors: [goldAccent, goldAccent.opacity(0.7)],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .frame(width: max(4, geo.size.width * appState.profile.levelProgress))
                }
            }
            .frame(height: 8)
            .clipShape(Capsule())
        }
    }

    private var pathRanksSection: some View {
        HStack(spacing: 12) {
            pathRankPill(
                icon: "⚔️",
                name: "Warrior",
                level: appState.profile.warriorRank,
                color: Color.red
            )
            pathRankPill(
                icon: "🧭",
                name: "Explorer",
                level: appState.profile.explorerRank,
                color: Color.green
            )
            pathRankPill(
                icon: "📜",
                name: "Mind",
                level: appState.profile.mindRank,
                color: Color.indigo
            )
        }
    }

    private func pathRankPill(icon: String, name: String, level: Int, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .center, spacing: 6) {
                Text(icon)
                    .font(.title3)

                VStack(alignment: .leading, spacing: 1) {
                    Text(name)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.white)
                    Text("Level \(level)")
                        .font(.caption2.weight(.medium))
                        .foregroundStyle(.white.opacity(0.45))
                }
            }

            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(Color(white: 1, opacity: 0.08))
                    Capsule()
                        .fill(color)
                        .frame(width: max(2, geo.size.width * min(1, Double(level) / 20.0)))
                }
            }
            .frame(height: 5)
            .clipShape(Capsule())
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - Badges

    private var badgesSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Badges")
                    .font(.title2.weight(.bold))
                    .foregroundStyle(.white)
                Spacer()
                Button {
                    showAchievements = true
                } label: {
                    Text("See All")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(goldAccent)
                }
            }

            let earned = BadgeDisplayMapper.earnedBadges(from: appState.profile)
            if earned.isEmpty {
                emptyBadgesPlaceholder
            } else {
                badgeGrid(badges: earned)
            }
        }
    }

    private var emptyBadgesPlaceholder: some View {
        let columns = Array(repeating: GridItem(.flexible(), spacing: 10), count: 4)
        let defaultBadgeImages = ["badge_quests", "badge_streaks", "badge_social", "badge_mastery", "badge_brain", "badge_milestones", "badge_quests", "badge_streaks"]
        return LazyVGrid(columns: columns, spacing: 10) {
            ForEach(0..<8, id: \.self) { i in
                ZStack {
                    RoundedRectangle(cornerRadius: 12)
                        .fill(cardBg)
                    RoundedRectangle(cornerRadius: 12)
                        .strokeBorder(cardBorder, lineWidth: 1)
                    if let uiImage = UIImage(named: defaultBadgeImages[i]) {
                        Image(uiImage: uiImage)
                            .resizable()
                            .interpolation(.none)
                            .aspectRatio(contentMode: .fit)
                            .padding(10)
                            .saturation(0)
                            .opacity(0.25)
                    }
                }
                .aspectRatio(1, contentMode: .fit)
            }
        }
    }

    private func badgeGrid(badges: [EarnedBadgeDisplay]) -> some View {
        let columns = Array(repeating: GridItem(.flexible(), spacing: 10), count: 4)
        return LazyVGrid(columns: columns, spacing: 10) {
            ForEach(badges) { badge in
                badgeCell(badge)
            }
        }
    }

    private func badgeCell(_ badge: EarnedBadgeDisplay) -> some View {
        Button {
            showAchievements = true
        } label: {
            ZStack {
                RoundedRectangle(cornerRadius: 12)
                    .fill(cardBg)
                RoundedRectangle(cornerRadius: 12)
                    .strokeBorder(cardBorder, lineWidth: 1)

                if let uiImage = UIImage(named: badge.badgeImageName) {
                    Image(uiImage: uiImage)
                        .resizable()
                        .interpolation(.none)
                        .aspectRatio(contentMode: .fit)
                        .padding(10)
                } else {
                    Image(systemName: badge.achievement.iconName)
                        .font(.title2)
                        .foregroundStyle(badgeColor(badge.achievement.badgeColor))
                }
            }
            .aspectRatio(1, contentMode: .fit)
        }
        .buttonStyle(.plain)
    }

    private func badgeColor(_ name: String) -> Color {
        switch name {
        case "green": .green
        case "blue": .blue
        case "purple": .purple
        case "orange": .orange
        case "red": .red
        case "cyan": .cyan
        case "teal": .teal
        case "indigo": .indigo
        case "yellow": .yellow
        default: .white
        }
    }

    // MARK: - Currency Bar

    private var currencyBar: some View {
        HStack(spacing: 10) {
            HStack(spacing: 8) {
                Text("🪙")
                    .font(.body)
                Text("Gold")
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(goldAccent)
                Text(appState.profile.gold.formatted())
                    .font(.subheadline.weight(.bold).monospacedDigit())
                    .foregroundStyle(.white)
                Spacer()
                Button { showShop = true } label: {
                    Image(systemName: "gearshape.fill")
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.4))
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(cardBg, in: .rect(cornerRadius: 12))
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .strokeBorder(goldAccent.opacity(0.25), lineWidth: 1)
            )

            HStack(spacing: 8) {
                Text("💎")
                    .font(.body)
                Text("Diamonds")
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(.cyan)
                Text("\(appState.profile.diamonds)")
                    .font(.subheadline.weight(.bold).monospacedDigit())
                    .foregroundStyle(.white)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(cardBg, in: .rect(cornerRadius: 12))
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .strokeBorder(Color.cyan.opacity(0.2), lineWidth: 1)
            )
        }
    }

    // MARK: - Cosmetic Collectibles

    private var cosmeticCollectiblesSection: some View {
        let columns = Array(repeating: GridItem(.flexible(), spacing: 10), count: 4)
        return VStack(alignment: .leading, spacing: 12) {
            Text("Cosmetic Collectibles")
                .font(.title2.weight(.bold))
                .foregroundStyle(.white)

            LazyVGrid(columns: columns, spacing: 10) {
                ForEach(appState.profile.ownedItems.prefix(8), id: \.self) { item in
                    cosmeticSlot(name: item)
                }

                if appState.profile.ownedItems.count < 4 {
                    ForEach(0..<(4 - appState.profile.ownedItems.prefix(8).count), id: \.self) { _ in
                        cosmeticSlotEmpty()
                    }
                }
            }
        }
    }

    private func cosmeticSlot(name: String) -> some View {
        VStack(spacing: 4) {
            RoundedRectangle(cornerRadius: 12)
                .fill(cardBg)
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .strokeBorder(cardBorder, lineWidth: 1)
                )
                .overlay {
                    Image(systemName: "sparkles")
                        .font(.title3)
                        .foregroundStyle(.white.opacity(0.3))
                }
                .aspectRatio(1, contentMode: .fit)

            Text(name.replacingOccurrences(of: "_", with: " ").capitalized)
                .font(.system(size: 9, weight: .medium))
                .foregroundStyle(.white.opacity(0.5))
                .lineLimit(1)
        }
    }

    private func cosmeticSlotEmpty() -> some View {
        VStack(spacing: 4) {
            RoundedRectangle(cornerRadius: 12)
                .fill(slotBg)
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .strokeBorder(slotBorder, lineWidth: 1)
                )
                .aspectRatio(1, contentMode: .fit)

            Text(" ")
                .font(.system(size: 9))
        }
    }
}
