import SwiftUI

struct RewardOverlayView: View {
    let reward: RewardEvent
    let hasMore: Bool
    let onNext: () -> Void
    let onDone: () -> Void
    let onShop: () -> Void

    @State private var appeared: Bool = false
    @State private var showDetails: Bool = false
    @State private var showButtons: Bool = false
    @State private var trophyBounce: Int = 0

    var body: some View {
        ZStack {
            Color.black.opacity(0.88)
                .ignoresSafeArea()

            VStack(spacing: 28) {
                Spacer()

                ZStack {
                    Circle()
                        .fill(.yellow.opacity(0.08))
                        .frame(width: 180, height: 180)
                        .scaleEffect(appeared ? 1.1 : 0.3)
                        .opacity(appeared ? 1 : 0)

                    Circle()
                        .fill(
                            RadialGradient(
                                colors: [.yellow.opacity(0.3), .clear],
                                center: .center,
                                startRadius: 30,
                                endRadius: 90
                            )
                        )
                        .frame(width: 160, height: 160)
                        .scaleEffect(appeared ? 1 : 0.5)

                    Image(systemName: "trophy.fill")
                        .font(.system(size: 64))
                        .foregroundStyle(
                            LinearGradient(
                                colors: [.yellow, .orange],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )
                        .shadow(color: .yellow.opacity(0.4), radius: 16)
                        .symbolEffect(.bounce.up, value: trophyBounce)
                        .scaleEffect(appeared ? 1 : 0.1)
                }

                VStack(spacing: 6) {
                    Text("Side Quest Verified!")
                        .font(.title.weight(.bold))
                        .foregroundStyle(.white)

                    Text(reward.questTitle)
                        .font(.title3)
                        .foregroundStyle(.white.opacity(0.6))
                }
                .opacity(appeared ? 1 : 0)
                .offset(y: appeared ? 0 : 20)

                VStack(spacing: 14) {
                    rewardRow(icon: "bolt.fill", label: "XP Earned", value: "+\(reward.xpEarned)", color: .orange, delay: 0)
                    rewardRow(icon: "dollarsign.circle.fill", label: "Gold Earned", value: "+\(reward.goldEarned)", color: .yellow, delay: 0.08)
                    if reward.diamondsEarned > 0 {
                        rewardRow(icon: "diamond.fill", label: "Diamonds", value: "+\(reward.diamondsEarned)", color: .cyan, delay: 0.16)
                    }
                    if reward.streakBonus {
                        rewardRow(icon: "flame.fill", label: "Streak Bonus", value: "\(String(format: "%.1f", reward.streakMultiplier))x", color: .orange, delay: 0.24)
                    }
                    if let badge = reward.newBadge {
                        rewardRow(icon: "star.circle.fill", label: "New Badge", value: badge, color: .purple, delay: 0.32)
                    }
                }
                .padding(20)
                .background(.ultraThinMaterial, in: .rect(cornerRadius: 20))
                .padding(.horizontal, 24)
                .opacity(showDetails ? 1 : 0)
                .offset(y: showDetails ? 0 : 30)

                Spacer()

                VStack(spacing: 12) {
                    if hasMore {
                        Button {
                            onNext()
                        } label: {
                            Text("Next Reward")
                                .font(.headline)
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.borderedProminent)
                    }

                    HStack(spacing: 12) {
                        Button {
                            onDone()
                        } label: {
                            Text("Done")
                                .font(.headline)
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.bordered)

                        Button {
                            onShop()
                        } label: {
                            Label("Shop", systemImage: "storefront.fill")
                                .font(.headline)
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.bordered)
                    }
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 20)
                .opacity(showButtons ? 1 : 0)
                .offset(y: showButtons ? 0 : 15)
            }
        }
        .onAppear {
            withAnimation(.spring(response: 0.5, dampingFraction: 0.55)) {
                appeared = true
            }
            withAnimation(.spring(response: 0.5, dampingFraction: 0.7).delay(0.35)) {
                showDetails = true
            }
            withAnimation(.easeOut(duration: 0.35).delay(0.65)) {
                showButtons = true
            }
            Task {
                try? await Task.sleep(for: .seconds(0.3))
                trophyBounce += 1
            }
        }
        .sensoryFeedback(.success, trigger: appeared)
        .sensoryFeedback(.impact(weight: .medium), trigger: showDetails)
    }

    private func rewardRow(icon: String, label: String, value: String, color: Color, delay: Double) -> some View {
        HStack {
            Image(systemName: icon)
                .foregroundStyle(color)
                .frame(width: 28)
            Text(label)
                .foregroundStyle(.white.opacity(0.7))
            Spacer()
            Text(value)
                .font(.headline.monospacedDigit())
                .foregroundStyle(.white)
        }
    }
}
