import SwiftUI

struct StoryEventView: View {
    let node: StoryNode
    let template: StoryTemplate
    let onChoice: (String) -> Void
    let onContinue: () -> Void
    let onClaim: () -> Void

    @State private var revealedText: String = ""
    @State private var showChoices: Bool = false
    @State private var showReward: Bool = false
    @State private var textComplete: Bool = false

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                storyHeader
                narrativeSection
                if node.type == .itemPickup || node.type == .ending {
                    rewardSection
                }
                if node.type == .decision && showChoices {
                    choicesSection
                }
                if (node.type == .narrative || ((node.type == .itemPickup || node.type == .ending) && showReward)) && textComplete {
                    actionButton
                }
            }
            .padding(.bottom, 40)
        }
        .background(
            LinearGradient(
                colors: [Color(.systemBackground), Color(.systemBackground).opacity(0.95), Color.indigo.opacity(0.08)],
                startPoint: .top,
                endPoint: .bottom
            )
        )
        .onAppear {
            animateText()
        }
    }

    private var storyHeader: some View {
        VStack(spacing: 10) {
            Image(systemName: headerIcon)
                .font(.system(size: 36))
                .foregroundStyle(headerGradient)
                .padding(.top, 32)

            Text(template.title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .textCase(.uppercase)
                .tracking(1.5)

            Text(node.title)
                .font(.title2.weight(.bold))
                .multilineTextAlignment(.center)

            Capsule()
                .fill(headerGradient)
                .frame(width: 40, height: 3)
        }
        .padding(.horizontal, 24)
        .padding(.bottom, 20)
    }

    private var narrativeSection: some View {
        Text(textComplete ? node.text : revealedText)
            .font(.body.leading(.loose))
            .foregroundStyle(.primary.opacity(0.9))
            .multilineTextAlignment(.leading)
            .padding(.horizontal, 24)
            .padding(.vertical, 16)
            .onTapGesture {
                if !textComplete {
                    withAnimation(.easeOut(duration: 0.15)) {
                        revealedText = node.text
                        textComplete = true
                        triggerPostText()
                    }
                }
            }
    }

    @ViewBuilder
    private var rewardSection: some View {
        if let reward = node.reward, textComplete {
            VStack(spacing: 12) {
                if let itemName = reward.itemName {
                    HStack(spacing: 12) {
                        ZStack {
                            Circle()
                                .fill(rarityColor(reward.itemRarity).opacity(0.15))
                                .frame(width: 48, height: 48)
                            Image(systemName: rarityIcon(reward.itemRarity))
                                .font(.title3.weight(.semibold))
                                .foregroundStyle(rarityColor(reward.itemRarity))
                        }
                        VStack(alignment: .leading, spacing: 3) {
                            Text(itemName)
                                .font(.subheadline.weight(.bold))
                            Text(reward.itemRarity?.rawValue ?? "Common")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(rarityColor(reward.itemRarity))
                            if let desc = reward.itemDescription {
                                Text(desc)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(3)
                            }
                        }
                        Spacer()
                    }
                }
                if reward.gold > 0 || reward.diamonds > 0 {
                    HStack(spacing: 16) {
                        if reward.gold > 0 {
                            Label("+\(reward.gold)", systemImage: "dollarsign.circle.fill")
                                .font(.subheadline.weight(.bold))
                                .foregroundStyle(.yellow)
                        }
                        if reward.diamonds > 0 {
                            Label("+\(reward.diamonds)", systemImage: "diamond.fill")
                                .font(.subheadline.weight(.bold))
                                .foregroundStyle(.cyan)
                        }
                        Spacer()
                    }
                }
            }
            .padding(16)
            .background(rarityColor(node.reward?.itemRarity).opacity(0.06), in: .rect(cornerRadius: 14))
            .overlay(
                RoundedRectangle(cornerRadius: 14)
                    .strokeBorder(rarityColor(node.reward?.itemRarity).opacity(0.2), lineWidth: 1)
            )
            .padding(.horizontal, 24)
            .padding(.top, 12)
            .transition(.asymmetric(insertion: .scale(scale: 0.9).combined(with: .opacity), removal: .opacity))
            .onAppear {
                withAnimation(.spring(response: 0.3).delay(0.2)) {
                    showReward = true
                }
            }
        }
    }

    private var choicesSection: some View {
        VStack(spacing: 10) {
            ForEach(node.choices) { choice in
                Button {
                    onChoice(choice.id)
                } label: {
                    HStack(spacing: 12) {
                        Image(systemName: "chevron.right.circle.fill")
                            .font(.title3)
                            .foregroundStyle(.indigo)
                        Text(choice.text)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.primary)
                            .multilineTextAlignment(.leading)
                        Spacer()
                    }
                    .padding(14)
                    .background(Color.indigo.opacity(0.08), in: .rect(cornerRadius: 12))
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .strokeBorder(Color.indigo.opacity(0.2), lineWidth: 1)
                    )
                }
                .buttonStyle(.plain)
                .transition(.asymmetric(insertion: .move(edge: .trailing).combined(with: .opacity), removal: .opacity))
            }
        }
        .padding(.horizontal, 24)
        .padding(.top, 20)
    }

    @ViewBuilder
    private var actionButton: some View {
        let isEnding = node.type == .ending
        Button {
            if isEnding {
                onClaim()
            } else if node.type == .itemPickup {
                onClaim()
            } else {
                onContinue()
            }
        } label: {
            HStack(spacing: 8) {
                Text(isEnding ? "Complete Story" : (node.type == .itemPickup ? "Claim & Continue" : "Continue"))
                    .font(.subheadline.weight(.bold))
                Image(systemName: isEnding ? "checkmark.circle.fill" : "arrow.right")
                    .font(.subheadline.weight(.semibold))
            }
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .background(isEnding ? Color.green.gradient : Color.indigo.gradient, in: Capsule())
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 24)
        .padding(.top, 20)
        .transition(.move(edge: .bottom).combined(with: .opacity))
    }

    private var headerIcon: String {
        switch node.type {
        case .narrative: "book.pages.fill"
        case .decision: "arrow.triangle.branch"
        case .itemPickup: "shippingbox.fill"
        case .ending: "flag.checkered"
        }
    }

    private var headerGradient: LinearGradient {
        switch node.type {
        case .narrative: LinearGradient(colors: [.indigo, .purple], startPoint: .topLeading, endPoint: .bottomTrailing)
        case .decision: LinearGradient(colors: [.orange, .red], startPoint: .topLeading, endPoint: .bottomTrailing)
        case .itemPickup: LinearGradient(colors: [.yellow, .orange], startPoint: .topLeading, endPoint: .bottomTrailing)
        case .ending: LinearGradient(colors: [.green, .teal], startPoint: .topLeading, endPoint: .bottomTrailing)
        }
    }

    private func rarityColor(_ rarity: ItemRarity?) -> Color {
        switch rarity {
        case .common: .gray
        case .uncommon: .green
        case .rare: .blue
        case .legendary: .purple
        case nil: .gray
        }
    }

    private func rarityIcon(_ rarity: ItemRarity?) -> String {
        switch rarity {
        case .common: "circle.fill"
        case .uncommon: "diamond.fill"
        case .rare: "star.fill"
        case .legendary: "sparkles"
        case nil: "circle.fill"
        }
    }

    private func animateText() {
        let fullText = node.text
        let words = fullText.split(separator: " ")
        var accumulated = ""
        let baseDelay: Double = 0.03

        for (i, word) in words.enumerated() {
            let delay = baseDelay * Double(i)
            accumulated += (i == 0 ? "" : " ") + String(word)
            let snapshot = accumulated
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
                guard !textComplete else { return }
                revealedText = snapshot
                if i == words.count - 1 {
                    textComplete = true
                    triggerPostText()
                }
            }
        }
    }

    private func triggerPostText() {
        if node.type == .decision {
            withAnimation(.spring(response: 0.4).delay(0.3)) {
                showChoices = true
            }
        }
    }
}
