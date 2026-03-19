import SwiftUI
import UIKit

private let cardSurface = Color(red: 0.161, green: 0.169, blue: 0.204)

struct QuestCardView: View {
    let quest: Quest
    var showCompletionCount: Bool = true
    var isFeaturedCard: Bool = false

    private var assetPair: QuestAssetPair {
        QuestAssetMapping.assets(for: quest.title)
    }

    private var pathColor: Color {
        PathColorHelper.color(for: quest.path)
    }

    private var cardAspectRatio: CGFloat {
        isFeaturedCard ? (1.6 / 1.0) : (2.2 / 1.0)
    }

    private func loadBundleImage(_ name: String, ext: String, folder: String) -> UIImage? {
        if let url = Bundle.main.url(forResource: name, withExtension: ext, subdirectory: "Resources/\(folder)"),
           let img = UIImage(contentsOfFile: url.path) {
            return img
        }
        if let url = Bundle.main.url(forResource: name, withExtension: ext),
           let img = UIImage(contentsOfFile: url.path) {
            return img
        }
        return UIImage(named: name)
    }

    var body: some View {
        GeometryReader { geo in
            let cardWidth = geo.size.width
            let cardHeight = cardWidth / cardAspectRatio
            ZStack(alignment: .topLeading) {
                cardSurface
                    .frame(width: cardWidth, height: cardHeight)

                if let img = loadBundleImage(assetPair.banner, ext: "jpg", folder: "QuestBanners") {
                    Image(uiImage: img)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(width: cardWidth, height: cardHeight)
                        .clipped()
                        .allowsHitTesting(false)
                } else {
                    LinearGradient(
                        colors: [pathColor.opacity(0.2), cardSurface],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                    .frame(width: cardWidth, height: cardHeight)
                }

                VStack(spacing: 0) {
                    Spacer()
                    let gradColor = Color(red: 0.145, green: 0.165, blue: 0.204)
                    LinearGradient(
                        stops: [
                            .init(color: gradColor.opacity(0), location: 0),
                            .init(color: gradColor.opacity(0.3), location: 0.2),
                            .init(color: gradColor.opacity(0.7), location: 0.45),
                            .init(color: gradColor, location: 0.7)
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                    .frame(height: cardHeight * 0.55)
                }
                .frame(width: cardWidth, height: cardHeight)
                .allowsHitTesting(false)

                if let icon = loadBundleImage(assetPair.icon, ext: "png", folder: "QuestIcons") {
                    if isFeaturedCard {
                        let standardCardHeight = cardWidth / 2.2
                        let iconSize = standardCardHeight * 0.85
                        Image(uiImage: icon)
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .frame(width: iconSize, height: iconSize)
                            .shadow(color: .black.opacity(0.6), radius: 12, y: 4)
                            .position(x: cardWidth - iconSize / 2 + 2, y: cardHeight - iconSize / 2 + 16)
                            .allowsHitTesting(false)
                    } else {
                        let iconSize = cardHeight * 0.85
                        Image(uiImage: icon)
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .frame(width: iconSize, height: iconSize)
                            .shadow(color: .black.opacity(0.5), radius: 8, y: 4)
                            .position(x: cardWidth - iconSize / 2 - 2, y: cardHeight / 2)
                            .allowsHitTesting(false)
                    }
                }

                VStack(alignment: .leading, spacing: 4) {
                    Spacer()
                    Text(quest.title)
                        .font(isFeaturedCard ? .title3.weight(.bold) : .subheadline.weight(.bold))
                        .foregroundStyle(.white)
                        .lineLimit(2)
                        .shadow(color: .black.opacity(0.5), radius: 4, y: 2)

                    HStack(spacing: 6) {
                        DifficultyBadge(difficulty: quest.difficulty)

                        HStack(spacing: 3) {
                            Image(systemName: "bolt.fill")
                                .font(.system(size: 9))
                            Text("\(quest.xpReward) XP")
                                .font(.caption2.weight(.bold))
                        }
                        .foregroundStyle(.orange)

                        HStack(spacing: 2) {
                            Image(systemName: "dollarsign.circle.fill")
                                .font(.system(size: 8))
                            Text("\(quest.goldReward)")
                                .font(.caption2.weight(.bold))
                        }
                        .foregroundStyle(.yellow)

                        if quest.diamondReward > 0 {
                            HStack(spacing: 2) {
                                Image(systemName: "diamond.fill")
                                    .font(.system(size: 8))
                                Text("\(quest.diamondReward)")
                                    .font(.caption2.weight(.bold))
                            }
                            .foregroundStyle(.cyan)
                        }

                        if quest.isExtreme {
                            Text("EXTREME")
                                .font(.system(size: 9, weight: .black))
                                .foregroundStyle(.red)
                                .padding(.horizontal, 5)
                                .padding(.vertical, 2)
                                .background(.red.opacity(0.25), in: Capsule())
                        }
                    }
                }
                .padding(14)
                .frame(width: cardWidth, height: cardHeight, alignment: .bottomLeading)

                if isFeaturedCard {
                    Text("Featured Quest")
                        .font(.system(size: 15, weight: .bold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 7)
                        .background(Color(white: 0.3).opacity(0.85), in: .rect(cornerRadius: 8))
                        .position(x: 80, y: 24)
                        .allowsHitTesting(false)
                }

                if isFeaturedCard {
                    if let badge = loadBundleImage("featured_award_overlay", ext: "png", folder: "Badges") {
                        let badgeSize: CGFloat = 110
                        Image(uiImage: badge)
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .frame(width: badgeSize, height: badgeSize)
                            .shadow(color: .black.opacity(0.5), radius: 8, y: 3)
                            .position(x: cardWidth - badgeSize / 2 + 4, y: badgeSize / 2 - 8)
                            .allowsHitTesting(false)
                    }
                }

                RoundedRectangle(cornerRadius: 16)
                    .strokeBorder(.white.opacity(0.08), lineWidth: 1)
                    .frame(width: cardWidth, height: cardHeight)
            }
            .frame(width: cardWidth, height: cardHeight)
            .clipShape(.rect(cornerRadius: 16))
        }
        .aspectRatio(cardAspectRatio, contentMode: .fit)
    }
}

struct ActiveQuestCard: View {
    let instance: QuestInstance
    let onSubmit: () -> Void
    var onDrop: (() -> Void)? = nil
    var onClearFailed: (() -> Void)? = nil
    var onDetail: (() -> Void)? = nil
    @State private var showDropConfirm: Bool = false

    private var pathColor: Color {
        PathColorHelper.color(for: instance.quest.path)
    }

    private var leadingIconImage: UIImage? {
        if let externalIconName = instance.quest.externalEventIconName,
           let image = QuestAssetMapping.bundleImage(named: externalIconName, ext: "png", folder: "EventIcons") {
            return image
        }
        if let fallbackEventIconName {
            return QuestAssetMapping.bundleImage(named: fallbackEventIconName, ext: "png", folder: "EventIcons")
        }
        return nil
    }

    private var fallbackEventIconName: String? {
        guard instance.quest.id.hasPrefix("external_event_") else { return nil }
        switch instance.quest.requiredPlaceType {
        case .nightclub?, .barLounge?:
            return "nightlife_party_v1"
        case .concertVenue?:
            return "concert_generic_01"
        case .arena?, .stadium?:
            return "generic_live_event"
        case .park?:
            return "race_short_v1"
        case .restaurant?:
            return "food_drink"
        case .communityCenter?:
            return "community_social"
        default:
            return "generic_live_event"
        }
    }

    private var stateLabel: String {
        switch instance.state {
        case .active: "Active"
        case .submitted: "Pending"
        case .verified: "Verified"
        case .rejected: "Rejected"
        case .failed: "Failed"
        default: instance.state.rawValue
        }
    }

    private var stateColor: Color {
        switch instance.state {
        case .active: .green
        case .submitted: .orange
        case .verified: .blue
        case .rejected: .red
        case .failed: .red
        default: .secondary
        }
    }

    private var exerciseButtonLabel: String {
        if instance.quest.isStepQuest { return "Check Steps" }
        if instance.quest.isTrackingQuest { return "Start Tracking" }
        if instance.quest.evidenceType == .pushUpTracking { return "Start Push-Ups" }
        if instance.quest.evidenceType == .plankTracking { return "Start Plank" }
        if instance.quest.evidenceType == .wallSitTracking { return "Start Wall Sit" }
        if instance.quest.evidenceType == .jumpRopeTracking { return "Start Jump Rope" }
        if instance.quest.isFocusQuest { return "Start Focus" }
        if instance.quest.isGratitudeQuest { return "Log Entry" }
        if instance.quest.isAffirmationQuest { return "Log Affirmations" }
        if instance.quest.evidenceType == .dualPhoto { return "Take Photos" }
        if instance.quest.isPlaceVerificationQuest {
            return instance.quest.requiredPlaceType?.isGPSOnly == true ? "Submit Check-In" : "Start Verification"
        }
        return "Submit Evidence"
    }

    private var exerciseButtonIcon: String {
        if instance.quest.isStepQuest { return "figure.walk" }
        if instance.quest.isTrackingQuest { return "location.fill" }
        if instance.quest.evidenceType == .pushUpTracking { return "figure.strengthtraining.traditional" }
        if instance.quest.evidenceType == .plankTracking { return "figure.core.training" }
        if instance.quest.evidenceType == .wallSitTracking { return "figure.seated.side" }
        if instance.quest.evidenceType == .jumpRopeTracking { return "figure.jumprope" }
        if instance.quest.isFocusQuest { return "timer" }
        if instance.quest.isGratitudeQuest { return "square.and.pencil" }
        if instance.quest.isAffirmationQuest { return "sparkles" }
        if instance.quest.evidenceType == .dualPhoto { return "camera.fill" }
        if instance.quest.isPlaceVerificationQuest { return "location.fill" }
        return "camera.fill"
    }

    var body: some View {
        Button {
            onDetail?()
        } label: {
            HStack(spacing: 0) {
                RoundedRectangle(cornerRadius: 2)
                    .fill(pathColor.gradient)
                    .frame(width: 4)
                    .padding(.vertical, 6)

                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 6) {
                        if let leadingIconImage {
                            Image(uiImage: leadingIconImage)
                                .resizable()
                                .aspectRatio(contentMode: .fit)
                                .frame(width: 18, height: 18)
                        } else {
                            Image(systemName: instance.quest.path.iconName)
                                .font(.caption2)
                                .foregroundStyle(pathColor)
                        }
                        Text(instance.quest.title)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.white)
                            .lineLimit(1)
                        Spacer(minLength: 4)
                        rewardsRow
                        stateBadge
                    }

                    if instance.state == .active {
                        activeActionRow
                    } else if instance.state == .failed {
                        failedActionRow
                    }
                }
                .padding(.leading, 10)
            }
            .padding(.vertical, 10)
            .padding(.horizontal, 12)
            .background(cardSurface.opacity(0.7), in: .rect(cornerRadius: 12))
            .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(.white.opacity(0.06), lineWidth: 1))
        }
        .buttonStyle(.plain)
        .contextMenu {
            if instance.state == .active || instance.state == .rejected {
                Button(role: .destructive) {
                    showDropConfirm = true
                } label: {
                    Label("Drop Quest", systemImage: "xmark.circle")
                }
            }
            if instance.state == .failed {
                Button(role: .destructive) {
                    onClearFailed?()
                } label: {
                    Label("Clear Challenge", systemImage: "trash")
                }
            }
        }
        .confirmationDialog("Drop Quest?", isPresented: $showDropConfirm, titleVisibility: .visible) {
            Button("Drop \(instance.quest.title)", role: .destructive) {
                onDrop?()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("You'll lose progress on this quest.")
        }
    }

    private var rewardsRow: some View {
        HStack(spacing: 6) {
            HStack(spacing: 2) {
                Image(systemName: "bolt.fill")
                    .font(.system(size: 9))
                Text("\(instance.quest.xpReward)")
                    .font(.caption2.weight(.bold).monospacedDigit())
            }
            .foregroundStyle(.orange)

            HStack(spacing: 2) {
                Image(systemName: "dollarsign.circle.fill")
                    .font(.system(size: 9))
                Text("\(instance.quest.goldReward)")
                    .font(.caption2.weight(.bold).monospacedDigit())
            }
            .foregroundStyle(.yellow)

            if instance.quest.diamondReward > 0 {
                HStack(spacing: 2) {
                    Image(systemName: "diamond.fill")
                        .font(.system(size: 9))
                    Text("\(instance.quest.diamondReward)")
                        .font(.caption2.weight(.bold).monospacedDigit())
                }
                .foregroundStyle(.cyan)
            }
        }
    }

    private var stateBadge: some View {
        Text(stateLabel)
            .font(.system(size: 10, weight: .semibold))
            .foregroundStyle(stateColor)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(stateColor.opacity(0.12), in: Capsule())
    }

    private var failedActionRow: some View {
        Button {
            onClearFailed?()
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "xmark.circle.fill")
                    .font(.caption2)
                Text("Clear Challenge")
                    .font(.caption.weight(.semibold))
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(.red.opacity(0.15), in: Capsule())
            .foregroundStyle(.red)
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private var activeActionRow: some View {
        let outsideWindow = instance.quest.hasTimeWindow && !instance.quest.isWithinTimeWindow
        if outsideWindow {
            HStack(spacing: 4) {
                Image(systemName: "clock.fill")
                    .font(.caption2)
                    .foregroundStyle(.orange)
                if let desc = instance.quest.timeWindowDescription {
                    Text(desc)
                        .font(.caption2.weight(.medium))
                        .foregroundStyle(.white.opacity(0.5))
                }
                if let next = instance.quest.nextWindowOpensDescription {
                    Text("·")
                        .foregroundStyle(.white.opacity(0.3))
                    Text(next)
                        .font(.caption2.weight(.medium))
                        .foregroundStyle(.orange)
                }
                Spacer()
            }
        } else if instance.isGPSAutoCheckInQuest && !instance.canSubmit {
            let remaining = instance.timeUntilSubmit
            let minutes = Int(remaining) / 60
            let seconds = Int(remaining) % 60
            HStack(spacing: 4) {
                Image(systemName: instance.isAutoCheckInInRange ? "location.fill" : "location.slash")
                    .font(.caption2)
                    .foregroundStyle(instance.isAutoCheckInInRange ? .green : .white.opacity(0.45))
                Text(
                    instance.isAutoCheckInInRange
                        ? "Auto check-in active • \(minutes)m \(seconds)s left"
                        : "Arrive to auto check in"
                )
                .font(.caption2)
                .foregroundStyle(instance.isAutoCheckInInRange ? .green.opacity(0.86) : .white.opacity(0.45))
            }
        } else if instance.canSubmit {
            Button {
                onSubmit()
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: exerciseButtonIcon)
                        .font(.caption2)
                    Text(exerciseButtonLabel)
                        .font(.caption.weight(.semibold))
                    if instance.quest.hasTimeWindow {
                        Image(systemName: "clock.badge.checkmark.fill")
                            .font(.system(size: 9))
                    }
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(pathColor, in: Capsule())
                .foregroundStyle(.white)
            }
            .buttonStyle(.plain)
        } else {
            let remaining = instance.timeUntilSubmit
            let minutes = Int(remaining) / 60
            let seconds = Int(remaining) % 60
            HStack(spacing: 4) {
                Image(systemName: "clock.fill")
                    .font(.caption2)
                    .foregroundStyle(.white.opacity(0.4))
                Text("Ready in \(minutes)m \(seconds)s")
                    .font(.caption2)
                    .foregroundStyle(.white.opacity(0.4))
            }
        }
    }
}
