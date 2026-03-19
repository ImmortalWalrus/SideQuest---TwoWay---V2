import SwiftUI

struct PlayerProfileSheet: View {
    let participant: MatchParticipant
    let pathColor: Color
    let onSendFriendRequest: () -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    avatarSection
                    scoreCard
                    pathRanksSection
                    statsSection
                    friendRequestButton
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 20)
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle(participant.username)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }

    private var avatarSection: some View {
        VStack(spacing: 12) {
            Image(systemName: participant.avatarName)
                .font(.system(size: 44))
                .foregroundStyle(.white)
                .frame(width: 96, height: 96)
                .background(avatarGradient, in: Circle())

            Text(participant.username)
                .font(.title2.weight(.bold))

            HStack(spacing: 12) {
                HStack(spacing: 4) {
                    Image(systemName: "flame.fill")
                        .foregroundStyle(.orange)
                    Text("\(participant.currentStreak) day streak")
                }
                .font(.subheadline)
                .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 20)
        .background(Color(.secondarySystemGroupedBackground), in: .rect(cornerRadius: 16))
    }

    private var scoreCard: some View {
        HStack(spacing: 0) {
            VStack(spacing: 4) {
                Text(participant.totalScore.formatted())
                    .font(.title3.weight(.heavy).monospacedDigit())
                    .foregroundStyle(.orange)
                Text("Score")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity)

            Divider().frame(height: 36)

            VStack(spacing: 4) {
                Text("\(participant.verifiedCount)")
                    .font(.title3.weight(.heavy).monospacedDigit())
                    .foregroundStyle(.blue)
                Text("Verified")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity)

            Divider().frame(height: 36)

            VStack(spacing: 4) {
                Text("\(participant.currentStreak)")
                    .font(.title3.weight(.heavy).monospacedDigit())
                    .foregroundStyle(.green)
                Text("Streak")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity)
        }
        .padding(.vertical, 14)
        .background(Color(.secondarySystemGroupedBackground), in: .rect(cornerRadius: 14))
    }

    private var pathRanksSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Path Ranks")
                .font(.headline)

            HStack(spacing: 12) {
                PathRankPill(path: .warrior, rank: participant.warriorRank)
                PathRankPill(path: .explorer, rank: participant.explorerRank)
                PathRankPill(path: .mind, rank: participant.mindRank)
            }
        }
    }

    private var statsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Stats")
                .font(.headline)

            VStack(spacing: 0) {
                StatRow(icon: "checkmark.seal.fill", label: "Verified Quests", value: "\(participant.verifiedCount)", color: .blue)
                Divider().padding(.leading, 44)
                StatRow(icon: "flame.fill", label: "Current Streak", value: "\(participant.currentStreak) days", color: .orange)
                Divider().padding(.leading, 44)
                StatRow(icon: "bolt.fill", label: "Total Score", value: participant.totalScore.formatted(), color: .yellow)
            }
            .background(Color(.secondarySystemGroupedBackground), in: .rect(cornerRadius: 14))
        }
    }

    @ViewBuilder
    private var friendRequestButton: some View {
        if participant.isFriend {
            HStack(spacing: 8) {
                Image(systemName: "person.badge.checkmark")
                    .foregroundStyle(.green)
                Text("Already Friends")
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .background(Color(.secondarySystemGroupedBackground), in: .rect(cornerRadius: 14))
        } else if participant.friendRequestSent {
            HStack(spacing: 8) {
                Image(systemName: "person.badge.clock.fill")
                    .foregroundStyle(.orange)
                Text("Friend Request Sent")
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .background(Color(.secondarySystemGroupedBackground), in: .rect(cornerRadius: 14))
        } else {
            Button {
                onSendFriendRequest()
            } label: {
                Label("Send Friend Request", systemImage: "person.badge.plus")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 6)
            }
            .buttonStyle(.borderedProminent)
            .tint(pathColor)
        }
    }

    private var avatarGradient: LinearGradient {
        ProfileBackgroundStyle.gradient(named: participant.callingCardName)
    }
}

struct PathRankPill: View {
    let path: QuestPath
    let rank: Int

    private var pathColor: Color { PathColorHelper.color(for: path) }

    var body: some View {
        VStack(spacing: 6) {
            Image(systemName: path.iconName)
                .font(.title2)
                .foregroundStyle(pathColor)
            Text("Rank \(rank)")
                .font(.caption.weight(.bold).monospacedDigit())
            Text(path.rawValue)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 14)
        .background(pathColor.opacity(0.08), in: .rect(cornerRadius: 12))
    }
}

struct StatRow: View {
    let icon: String
    let label: String
    let value: String
    let color: Color

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.body)
                .foregroundStyle(color)
                .frame(width: 32)
            Text(label)
                .font(.subheadline)
            Spacer()
            Text(value)
                .font(.subheadline.weight(.semibold).monospacedDigit())
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
    }
}
