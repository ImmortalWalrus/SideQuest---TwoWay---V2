import SwiftUI
import UIKit

private let familyCardSurface = Color(red: 0.161, green: 0.169, blue: 0.204)

struct QuestFamilyCardView: View {
    let family: QuestFamily
    var onTap: () -> Void = {}

    private var quest: Quest { family.recommendedQuest }
    private var pathColor: Color { PathColorHelper.color(for: quest.path) }

    private var assetPair: QuestAssetPair {
        QuestAssetMapping.assets(for: quest.title)
    }

    private let cardAspectRatio: CGFloat = 2.2

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

    private var proofLabel: String? {
        guard let ev = quest.evidenceType else { return nil }
        switch ev {
        case .video: return "Video"
        case .dualPhoto: return "Photo"
        case .gpsTracking: return "GPS"
        case .pushUpTracking: return "Tracking"
        case .plankTracking: return "Tracking"
        case .wallSitTracking: return "Tracking"
        case .stepTracking: return "Steps"
        case .meditationTracking: return "Timer"
        case .focusTracking: return "Timer"
        case .gratitudePhoto: return "Photo"
        case .affirmationPhoto: return "Photo"
        case .placeVerification: return "Check-In"
        case .readingTracking: return "Timer"
        case .jumpRopeTracking: return "Tracking"
        }
    }

    private var durationLabel: String {
        let mins = quest.minCompletionMinutes
        if mins < 60 { return "\(mins)m" }
        return "\(mins / 60)h \(mins % 60)m"
    }

    var body: some View {
        Button(action: onTap) {
            GeometryReader { geo in
                let cardWidth = geo.size.width
                let cardHeight = cardWidth / cardAspectRatio

                ZStack(alignment: .topLeading) {
                    familyCardSurface
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
                            colors: [pathColor.opacity(0.2), familyCardSurface],
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
                        let iconSize = cardHeight * 0.85
                        Image(uiImage: icon)
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .frame(width: iconSize, height: iconSize)
                            .shadow(color: .black.opacity(0.5), radius: 8, y: 4)
                            .position(x: cardWidth - iconSize / 2 - 2, y: cardHeight / 2)
                            .allowsHitTesting(false)
                    }

                    VStack(alignment: .leading, spacing: 4) {
                        Spacer()

                        HStack(spacing: 8) {
                            Text(family.isLadder ? family.name : quest.title)
                                .font(.subheadline.weight(.bold))
                                .foregroundStyle(.white)
                                .lineLimit(2)
                                .shadow(color: .black.opacity(0.5), radius: 4, y: 2)

                            if family.isLadder {
                                Text("\(family.quests.count) levels")
                                    .font(.system(size: 10, weight: .bold))
                                    .foregroundStyle(.white)
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 3)
                                    .background(pathColor.opacity(0.6), in: Capsule())
                            }
                        }

                        if family.isLadder {
                            Text("Next: \(quest.title)")
                                .font(.caption.weight(.medium))
                                .foregroundStyle(.white.opacity(0.6))
                                .lineLimit(1)
                                .shadow(color: .black.opacity(0.4), radius: 2, y: 1)
                        }

                        HStack(spacing: 6) {
                            DifficultyBadge(difficulty: quest.difficulty)

                            HStack(spacing: 3) {
                                Image(systemName: "bolt.fill")
                                    .font(.system(size: 9))
                                if family.isLadder && family.xpRange.lowerBound != family.xpRange.upperBound {
                                    Text("\(family.xpRange.lowerBound)–\(family.xpRange.upperBound) XP")
                                        .font(.caption2.weight(.bold))
                                } else {
                                    Text("\(quest.xpReward) XP")
                                        .font(.caption2.weight(.bold))
                                }
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

                            if let proof = proofLabel {
                                HStack(spacing: 3) {
                                    Image(systemName: "checkmark.shield.fill")
                                        .font(.system(size: 8))
                                    Text(proof)
                                        .font(.system(size: 10, weight: .semibold))
                                }
                                .foregroundStyle(.white.opacity(0.5))
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

                    RoundedRectangle(cornerRadius: 16)
                        .strokeBorder(.white.opacity(0.08), lineWidth: 1)
                        .frame(width: cardWidth, height: cardHeight)
                }
                .frame(width: cardWidth, height: cardHeight)
                .clipShape(.rect(cornerRadius: 16))
            }
            .aspectRatio(cardAspectRatio, contentMode: .fit)
        }
        .buttonStyle(.plain)
    }
}
