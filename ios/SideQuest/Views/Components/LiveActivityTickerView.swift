import SwiftUI
import UIKit

struct LiveActivityTickerView: View {
    let appState: AppState
    @Binding var isExpanded: Bool
    @State private var scrollOffset: CGFloat = 0
    @State private var isTouching: Bool = false
    @State private var tickerWidth: CGFloat = 0
    @State private var containerWidth: CGFloat = 0
    @State private var selectedProfile: MatchParticipant?
    @State private var selectedQuest: Quest?

    private var feed: [ActivityItem] { appState.activityFeed }

    private var tickerText: String {
        feed.map { item in
            let crown = item.isMaster ? " \u{1F451}" : ""
            return "\(item.username)\(crown) completed \(item.questTitle)"
        }.joined(separator: "  \u{2022}  ")
    }

    var body: some View {
        VStack(spacing: 0) {
            if isExpanded {
                expandedFeed
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }

            tickerBar
        }
        .sheet(item: $selectedProfile) { participant in
            PlayerProfileSheet(
                participant: participant,
                pathColor: .blue,
                onSendFriendRequest: {}
            )
        }
        .sheet(item: $selectedQuest) { quest in
            QuestDetailView(quest: quest, appState: appState)
        }
    }

    private var tickerBar: some View {
        Button {
            isExpanded.toggle()
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "bolt.fill")
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(.green)

                GeometryReader { geo in
                    let w = geo.size.width
                    TimelineView(.animation(minimumInterval: 1.0 / 60.0, paused: isTouching)) { context in
                        let totalW = tickerWidth + w
                        let speed: CGFloat = 40
                        let elapsed = context.date.timeIntervalSinceReferenceDate
                        let offset = totalW > 0 ? CGFloat(elapsed.truncatingRemainder(dividingBy: Double(totalW / speed))) * speed : 0
                        let x = w - offset

                        Text(tickerText + "  \u{2022}  " + tickerText)
                            .font(.caption.weight(.medium))
                            .foregroundStyle(.primary.opacity(0.85))
                            .fixedSize()
                            .offset(x: x)
                            .background(
                                GeometryReader { textGeo in
                                    Color.clear
                                        .onAppear {
                                            tickerWidth = textGeo.size.width / 2
                                            containerWidth = w
                                        }
                                }
                            )
                    }
                    .clipped()
                }
                .frame(height: 16)

                Image(systemName: isExpanded ? "chevron.down" : "chevron.up")
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(.ultraThinMaterial)
            .overlay(alignment: .top) {
                Rectangle()
                    .fill(.separator)
                    .frame(height: 0.5)
            }
        }
        .buttonStyle(.plain)
        .simultaneousGesture(
            LongPressGesture(minimumDuration: 0.01)
                .onChanged { _ in isTouching = true }
                .onEnded { _ in isTouching = false }
        )
    }

    private var expandedFeed: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Activity Feed")
                    .font(.headline.weight(.bold))
                Spacer()
                Button {
                    isExpanded = false
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.title3)
                        .symbolRenderingMode(.hierarchical)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 14)
            .padding(.bottom, 8)

            ScrollView {
                LazyVStack(spacing: 2) {
                    ForEach(feed) { item in
                        expandedRow(item)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 16)
            }
        }
        .frame(maxHeight: UIScreen.main.bounds.height * 0.55)
        .background(.ultraThinMaterial)
        .overlay(alignment: .top) {
            Rectangle()
                .fill(.separator)
                .frame(height: 0.5)
        }
    }

    private func expandedRow(_ item: ActivityItem) -> some View {
        HStack(spacing: 10) {
            Button {
                selectedProfile = participantFromActivity(item)
            } label: {
                Image(systemName: item.avatarName)
                    .font(.caption2)
                    .foregroundStyle(.white)
                    .frame(width: 28, height: 28)
                    .background(PathColorHelper.color(for: item.path).gradient, in: Circle())
            }

            VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: 4) {
                    Button {
                        selectedProfile = participantFromActivity(item)
                    } label: {
                        Text(item.username)
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.primary)
                    }
                    .buttonStyle(.plain)

                    if item.isMaster {
                        Image(systemName: "crown.fill")
                            .font(.system(size: 8))
                            .foregroundStyle(.purple)
                    }
                }

                Button {
                    if let quest = appState.allQuests.first(where: { $0.title == item.questTitle }) {
                        selectedQuest = quest
                    }
                } label: {
                    Text(item.questTitle)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .underline(color: .secondary.opacity(0.3))
                }
                .buttonStyle(.plain)
            }

            Spacer()

            Text(item.completedAt, style: .relative)
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 8)
        .background(Color(.secondarySystemGroupedBackground).opacity(0.5), in: .rect(cornerRadius: 10))
        .padding(.vertical, 2)
    }

    private func participantFromActivity(_ item: ActivityItem) -> MatchParticipant {
        if let entry = appState.leaderboard.first(where: { $0.username == item.username }) {
            return MatchParticipant(
                id: entry.id,
                username: entry.username,
                avatarName: entry.avatarName,
                callingCardName: entry.callingCardName,
                totalScore: entry.totalScore,
                verifiedCount: entry.verifiedCount,
                currentStreak: Int.random(in: 5...30),
                warriorRank: Int.random(in: 5...25),
                explorerRank: Int.random(in: 5...25),
                mindRank: Int.random(in: 5...25),
                isFriend: appState.friends.contains(where: { $0.username == item.username })
            )
        }
        return MatchParticipant(
            id: item.id,
            username: item.username,
            avatarName: item.avatarName,
            callingCardName: "gradient1",
            totalScore: 0,
            verifiedCount: 0,
            currentStreak: 0,
            warriorRank: 1,
            explorerRank: 1,
            mindRank: 1,
            isFriend: appState.friends.contains(where: { $0.username == item.username })
        )
    }
}
