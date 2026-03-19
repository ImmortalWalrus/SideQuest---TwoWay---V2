import SwiftUI

struct SocialTabView: View {
    let appState: AppState
    @State private var showLeaderboard: Bool = false
    @State private var showFriendsList: Bool = false
    @State private var selectedGroupQuest: Quest?


    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    SideScrollJourneyView(appState: appState)
                        .padding(.horizontal, -16)
                    friendsBanner
                    leaderboardPreview
                    activityFeedSection
                    groupQuestSection
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 20)
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("Social")
            .refreshable {
                await appState.refreshSocialData()
            }
            .sheet(isPresented: $showLeaderboard) {
                LeaderboardView(appState: appState)
            }
            .sheet(item: $selectedGroupQuest) { quest in
                QuestDetailView(quest: quest, appState: appState)
            }
            .sheet(isPresented: $showFriendsList) {
                FriendsListView(appState: appState)
            }

        }
    }

    private var friendsBanner: some View {
        Button {
            showFriendsList = true
        } label: {
            VStack(spacing: 0) {
                HStack(spacing: 14) {
                    ZStack {
                        Circle()
                            .fill(.linearGradient(colors: [.green, .teal], startPoint: .topLeading, endPoint: .bottomTrailing))
                            .frame(width: 52, height: 52)
                        Image(systemName: "person.2.fill")
                            .font(.title3)
                            .foregroundStyle(.white)
                    }

                    VStack(alignment: .leading, spacing: 3) {
                        HStack(spacing: 8) {
                            Text("Friends")
                                .font(.headline)
                            if appState.pendingFriendCount > 0 {
                                Text("\(appState.pendingFriendCount) new")
                                    .font(.caption2.weight(.bold))
                                    .foregroundStyle(.white)
                                    .padding(.horizontal, 7)
                                    .padding(.vertical, 2)
                                    .background(.orange, in: Capsule())
                            }
                        }
                        Text("\(appState.acceptedFriends.count) friends · \(appState.onlineFriends.count) online")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    Spacer()

                    if !appState.onlineFriends.isEmpty {
                        HStack(spacing: -8) {
                            ForEach(appState.onlineFriends.prefix(3)) { friend in
                                Image(systemName: friend.avatarName)
                                    .font(.caption2)
                                    .foregroundStyle(.white)
                                    .frame(width: 28, height: 28)
                                    .background(.green.gradient, in: Circle())
                                    .overlay(Circle().strokeBorder(Color(.secondarySystemGroupedBackground), lineWidth: 2))
                            }
                        }
                    }

                    Image(systemName: "chevron.right.circle.fill")
                        .font(.title3)
                        .foregroundStyle(.green.opacity(0.6))
                }
            }
            .padding(14)
            .background(
                LinearGradient(colors: [.green.opacity(0.08), .teal.opacity(0.05)], startPoint: .leading, endPoint: .trailing),
                in: .rect(cornerRadius: 16)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 16)
                    .strokeBorder(.green.opacity(0.15), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }

    private var leaderboardPreview: some View {
        VStack(spacing: 12) {
            HStack {
                Image(systemName: "trophy.fill")
                    .foregroundStyle(.yellow)
                Text("Leaderboard")
                    .font(.title3.weight(.bold))
                Spacer()
                Button {
                    showLeaderboard = true
                } label: {
                    Text("See All")
                        .font(.subheadline.weight(.medium))
                }
            }

            VStack(spacing: 0) {
                ForEach(appState.leaderboard.prefix(5)) { entry in
                    HStack(spacing: 12) {
                        Text("#\(entry.rank)")
                            .font(.subheadline.weight(.bold).monospacedDigit())
                            .foregroundStyle(entry.rank <= 3 ? rankColor(entry.rank) : .secondary)
                            .frame(width: 32)

                        Image(systemName: entry.avatarName)
                            .font(.body)
                            .foregroundStyle(.white)
                            .frame(width: 32, height: 32)
                            .background(avatarGradient(entry.callingCardName), in: Circle())

                        VStack(alignment: .leading, spacing: 1) {
                            Text(entry.username)
                                .font(.subheadline.weight(.semibold))
                            HStack(spacing: 6) {
                                Text("\(entry.verifiedCount) verified")
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                                if entry.masterCount > 0 {
                                    Text("\u{2022} \(entry.masterCount) master")
                                        .font(.caption2)
                                        .foregroundStyle(.purple)
                                }
                            }
                        }

                        Spacer()

                        Text(entry.totalScore.formatted())
                            .font(.subheadline.weight(.bold).monospacedDigit())
                            .foregroundStyle(.primary)
                    }
                    .padding(.vertical, 10)

                    if entry.rank < 5 {
                        Divider()
                    }
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 4)
            .background(Color(.secondarySystemGroupedBackground), in: .rect(cornerRadius: 14))
        }
    }

    private var activityFeedSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Image(systemName: "bolt.fill")
                    .foregroundStyle(.orange)
                Text("Recent Activity")
                    .font(.title3.weight(.bold))
                Spacer()
            }

            if appState.activityFeed.isEmpty {
                HStack {
                    Spacer()
                    VStack(spacing: 8) {
                        Image(systemName: "tray")
                            .font(.title2)
                            .foregroundStyle(.tertiary)
                        Text("No activity yet")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 20)
                    Spacer()
                }
                .background(Color(.secondarySystemGroupedBackground), in: .rect(cornerRadius: 14))
            } else {
                VStack(spacing: 0) {
                    ForEach(appState.activityFeed.prefix(5)) { item in
                        HStack(spacing: 12) {
                            Image(systemName: item.avatarName)
                                .font(.caption)
                                .foregroundStyle(.white)
                                .frame(width: 32, height: 32)
                                .background(PathColorHelper.color(for: item.path).gradient, in: Circle())

                            VStack(alignment: .leading, spacing: 2) {
                                HStack(spacing: 4) {
                                    Text(item.username)
                                        .font(.subheadline.weight(.semibold))
                                    if item.isMaster {
                                        Image(systemName: "crown.fill")
                                            .font(.caption2)
                                            .foregroundStyle(.purple)
                                    }
                                }
                                Text(item.questTitle)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                            }

                            Spacer()

                            Text(item.completedAt, style: .relative)
                                .font(.caption2)
                                .foregroundStyle(.tertiary)
                        }
                        .padding(.vertical, 10)
                        .padding(.horizontal, 14)

                        if item.id != appState.activityFeed.prefix(5).last?.id {
                            Divider().padding(.leading, 58)
                        }
                    }
                }
                .background(Color(.secondarySystemGroupedBackground), in: .rect(cornerRadius: 14))
            }
        }
    }

    private var groupQuestSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Image(systemName: "person.3.fill")
                    .foregroundStyle(.blue)
                Text("Group Quests")
                    .font(.title3.weight(.bold))
                Spacer()
                Text("1.2x bonus")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.blue)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(.blue.opacity(0.12), in: Capsule())
            }

            let groupQuests = appState.allQuests.filter { $0.type == .verified && ($0.isTrackingQuest || $0.difficulty == .medium || $0.difficulty == .hard) }.prefix(4)

            ForEach(Array(groupQuests)) { quest in
                Button {
                    selectedGroupQuest = quest
                } label: {
                    HStack(spacing: 12) {
                        Image(systemName: quest.path.iconName)
                            .font(.title3)
                            .foregroundStyle(PathColorHelper.color(for: quest.path))
                            .frame(width: 40, height: 40)
                            .background(PathColorHelper.color(for: quest.path).opacity(0.12), in: .rect(cornerRadius: 10))

                        VStack(alignment: .leading, spacing: 2) {
                            Text(quest.title)
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(.primary)
                            HStack(spacing: 8) {
                                DifficultyBadge(difficulty: quest.difficulty)
                                Text("\(Int(Double(quest.xpReward) * 1.2)) XP with group")
                                    .font(.caption2)
                                    .foregroundStyle(.blue)
                            }
                        }

                        Spacer()

                        Image(systemName: "chevron.right")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                    }
                    .padding(12)
                    .background(Color(.secondarySystemGroupedBackground), in: .rect(cornerRadius: 12))
                }
                .buttonStyle(.plain)
            }

            HStack(spacing: 12) {
                Image(systemName: "antenna.radiowaves.left.and.right")
                    .font(.title3)
                    .foregroundStyle(.white)
                    .frame(width: 40, height: 40)
                    .background(.blue.gradient, in: .rect(cornerRadius: 10))
                VStack(alignment: .leading, spacing: 2) {
                    Text("NFC Handshake Bonus")
                        .font(.subheadline.weight(.semibold))
                    Text("Tap phones before a group run for +5% XP")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Text("+5% XP")
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(.green)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(.green.opacity(0.12), in: Capsule())
            }
            .padding(12)
            .background(Color(.secondarySystemGroupedBackground), in: .rect(cornerRadius: 12))

            HStack(spacing: 8) {
                Image(systemName: "map.fill")
                    .font(.caption)
                    .foregroundStyle(.orange)
                Text("Group run paths must be 70%+ similar for XP")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 4)
        }
    }

    private func rankColor(_ rank: Int) -> Color {
        switch rank {
        case 1: .yellow
        case 2: .gray
        case 3: .orange
        default: .secondary
        }
    }

    private func avatarGradient(_ card: String) -> LinearGradient {
        ProfileBackgroundStyle.gradient(named: card)
    }
}
