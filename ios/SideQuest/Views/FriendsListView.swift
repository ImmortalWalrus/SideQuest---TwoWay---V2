import SwiftUI

struct FriendsListView: View {
    let appState: AppState
    @Environment(\.dismiss) private var dismiss
    @State private var searchText: String = ""
    @State private var selectedTab: FriendsTab = .all
    @State private var friendToRemove: Friend?
    @State private var showRemoveAlert: Bool = false
    @State private var searchResults: [APIUserSearchResult] = []
    @State private var isSearching: Bool = false
    @State private var searchTask: Task<Void, Never>?

    private var filteredFriends: [Friend] {
        let base: [Friend]
        switch selectedTab {
        case .all: base = appState.acceptedFriends
        case .online: base = appState.onlineFriends
        case .find: base = appState.acceptedFriends
        }
        if searchText.isEmpty { return base }
        return base.filter { $0.username.localizedStandardContains(searchText) }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    if !appState.friendRequests.isEmpty {
                        requestsSection
                    }
                    filterPicker
                    if selectedTab == .find {
                        findFriendsSection
                    } else {
                        friendsList
                    }
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 20)
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("Friends")
            .navigationBarTitleDisplayMode(.inline)
            .searchable(text: $searchText, prompt: "Search friends")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .onChange(of: searchText) { _, newValue in
                guard selectedTab == .find else { return }
                searchTask?.cancel()
                guard !newValue.isEmpty else {
                    searchResults = []
                    return
                }
                searchTask = Task {
                    try? await Task.sleep(for: .milliseconds(400))
                    guard !Task.isCancelled else { return }
                    isSearching = true
                    if let results: [APIUserSearchResult]? = nil, let results {
                        searchResults = results
                    }
                    isSearching = false
                }
            }
            .alert("Remove Friend", isPresented: $showRemoveAlert, presenting: friendToRemove) { friend in
                Button("Remove", role: .destructive) {
                    withAnimation(.snappy) {
                        appState.removeFriend(friend.id)
                    }
                }
                Button("Cancel", role: .cancel) {}
            } message: { friend in
                Text("Are you sure you want to remove \(friend.username) from your friends?")
            }
        }
    }

    private var requestsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: "person.badge.plus")
                    .foregroundStyle(.orange)
                Text("Friend Requests")
                    .font(.headline)
                Spacer()
                Text("\(appState.friendRequests.count)")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(.orange, in: Capsule())
            }

            ForEach(appState.friendRequests) { request in
                FriendRequestRow(request: request) {
                    withAnimation(.snappy) {
                        appState.acceptFriendRequest(request.id)
                    }
                } onDecline: {
                    withAnimation(.snappy) {
                        appState.declineFriendRequest(request.id)
                    }
                }
            }
        }
    }

    private var filterPicker: some View {
        HStack(spacing: 0) {
            ForEach(FriendsTab.allCases) { tab in
                Button {
                    withAnimation(.snappy) { selectedTab = tab }
                } label: {
                    HStack(spacing: 6) {
                        if tab == .online {
                            Circle()
                                .fill(.green)
                                .frame(width: 7, height: 7)
                        }
                        if tab == .find {
                            Image(systemName: "magnifyingglass")
                                .font(.caption)
                        }
                        Text(tab.label(allCount: appState.acceptedFriends.count, onlineCount: appState.onlineFriends.count))
                            .font(.subheadline.weight(.medium))
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                    .background(selectedTab == tab ? Color(.tertiarySystemGroupedBackground) : .clear, in: .rect(cornerRadius: 10))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(4)
        .background(Color(.secondarySystemGroupedBackground), in: .rect(cornerRadius: 14))
    }

    private func sendRequest(to user: APIUserSearchResult) {
    }

    @ViewBuilder
    private var findFriendsSection: some View {
        if searchText.isEmpty {
            VStack(spacing: 12) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 36))
                    .foregroundStyle(.secondary)
                Text("Search by username to find friends")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 60)
        } else if isSearching {
            ProgressView()
                .frame(maxWidth: .infinity)
                .padding(.vertical, 60)
        } else if searchResults.isEmpty {
            VStack(spacing: 12) {
                Image(systemName: "person.slash")
                    .font(.system(size: 36))
                    .foregroundStyle(.secondary)
                Text("No users found")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 60)
        } else {
            LazyVStack(spacing: 0) {
                ForEach(searchResults) { user in
                    HStack(spacing: 12) {
                        Image(systemName: user.avatarName)
                            .font(.title3)
                            .foregroundStyle(.white)
                            .frame(width: 44, height: 44)
                            .background(LinearGradient(colors: [.blue, .indigo], startPoint: .topLeading, endPoint: .bottomTrailing), in: Circle())

                        VStack(alignment: .leading, spacing: 3) {
                            Text(user.username)
                                .font(.subheadline.weight(.semibold))
                            Text("\(user.totalScore.formatted()) XP · \(user.verifiedCount) verified")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }

                        Spacer()

                        if user.isFriend {
                            Text("Friends")
                                .font(.caption.weight(.medium))
                                .foregroundStyle(.green)
                        } else if user.requestPending {
                            Text("Pending")
                                .font(.caption.weight(.medium))
                                .foregroundStyle(.orange)
                        } else {
                            Button {
                                sendRequest(to: user)
                            } label: {
                                Image(systemName: "person.badge.plus")
                                    .font(.body)
                                    .foregroundStyle(.blue)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 12)

                    if user.id != searchResults.last?.id {
                        Divider()
                            .padding(.leading, 68)
                    }
                }
            }
            .background(Color(.secondarySystemGroupedBackground), in: .rect(cornerRadius: 14))
        }
    }

    @ViewBuilder
    private var friendsList: some View {
        if filteredFriends.isEmpty {
            VStack(spacing: 12) {
                Image(systemName: searchText.isEmpty ? "person.2.slash" : "magnifyingglass")
                    .font(.system(size: 36))
                    .foregroundStyle(.secondary)
                Text(searchText.isEmpty ? (selectedTab == .online ? "No friends online" : "No friends yet") : "No results")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 60)
        } else {
            LazyVStack(spacing: 0) {
                ForEach(filteredFriends) { friend in
                    FriendRow(friend: friend) {
                        friendToRemove = friend
                        showRemoveAlert = true
                    }

                    if friend.id != filteredFriends.last?.id {
                        Divider()
                            .padding(.leading, 68)
                    }
                }
            }
            .background(Color(.secondarySystemGroupedBackground), in: .rect(cornerRadius: 14))
        }
    }
}

struct FriendRow: View {
    let friend: Friend
    let onRemove: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            ZStack(alignment: .bottomTrailing) {
                Image(systemName: friend.avatarName)
                    .font(.title3)
                    .foregroundStyle(.white)
                    .frame(width: 48, height: 48)
                    .background(avatarGradient, in: Circle())

                if friend.isOnline {
                    Circle()
                        .fill(.green)
                        .frame(width: 14, height: 14)
                        .overlay(Circle().strokeBorder(Color(.secondarySystemGroupedBackground), lineWidth: 2.5))
                        .offset(x: 2, y: 2)
                }
            }

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(friend.username)
                        .font(.body.weight(.semibold))

                    if friend.currentStreak >= 30 {
                        Image(systemName: "flame.fill")
                            .font(.caption2)
                            .foregroundStyle(.orange)
                    }
                }

                HStack(spacing: 8) {
                    Text("\(friend.totalScore.formatted()) XP")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    Text("\u{2022}")
                        .font(.caption2)
                        .foregroundStyle(.quaternary)

                    Text(friend.isOnline ? "Online" : lastSeenText)
                        .font(.caption)
                        .foregroundStyle(friend.isOnline ? Color.green : Color.secondary)
                }
            }

            Spacer()

            HStack(spacing: -6) {
                PathMicroBadge(path: .warrior, rank: friend.warriorRank)
                PathMicroBadge(path: .explorer, rank: friend.explorerRank)
                PathMicroBadge(path: .mind, rank: friend.mindRank)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .contextMenu {
            Button(role: .destructive) {
                onRemove()
            } label: {
                Label("Remove Friend", systemImage: "person.badge.minus")
            }
        }
    }

    private var lastSeenText: String {
        let interval = Date().timeIntervalSince(friend.lastActiveAt)
        if interval < 3600 {
            return "\(Int(interval / 60))m ago"
        } else if interval < 86400 {
            return "\(Int(interval / 3600))h ago"
        } else {
            return "\(Int(interval / 86400))d ago"
        }
    }

    private var avatarGradient: LinearGradient {
        ProfileBackgroundStyle.gradient(named: friend.callingCardName)
    }
}

struct PathMicroBadge: View {
    let path: QuestPath
    let rank: Int

    var body: some View {
        ZStack {
            Circle()
                .fill(PathColorHelper.color(for: path))
                .frame(width: 26, height: 26)
            Text("\(rank)")
                .font(.caption2.weight(.bold).monospacedDigit())
                .foregroundStyle(.white)
        }
    }
}

struct FriendRequestRow: View {
    let request: FriendRequest
    let onAccept: () -> Void
    let onDecline: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: request.fromAvatarName)
                .font(.title3)
                .foregroundStyle(.white)
                .frame(width: 44, height: 44)
                .background(avatarGradient, in: Circle())

            VStack(alignment: .leading, spacing: 3) {
                Text(request.fromUsername)
                    .font(.subheadline.weight(.semibold))
                HStack(spacing: 6) {
                    Text("\(request.fromTotalScore.formatted()) XP")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text("\u{2022}")
                        .font(.caption2)
                        .foregroundStyle(.quaternary)
                    Text("\(request.fromVerifiedCount) verified")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer()

            HStack(spacing: 8) {
                Button {
                    onDecline()
                } label: {
                    Image(systemName: "xmark")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(.secondary)
                        .frame(width: 34, height: 34)
                        .background(Color(.tertiarySystemGroupedBackground), in: Circle())
                }
                .buttonStyle(.plain)

                Button {
                    onAccept()
                } label: {
                    Image(systemName: "checkmark")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(.white)
                        .frame(width: 34, height: 34)
                        .background(.green, in: Circle())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(12)
        .background(Color(.secondarySystemGroupedBackground), in: .rect(cornerRadius: 12))
    }

    private var avatarGradient: LinearGradient {
        ProfileBackgroundStyle.gradient(named: request.fromCallingCardName)
    }
}

nonisolated enum FriendsTab: String, CaseIterable, Identifiable {
    case all
    case online
    case find

    var id: String { rawValue }

    func label(allCount: Int, onlineCount: Int) -> String {
        switch self {
        case .all: "All (\(allCount))"
        case .online: "Online (\(onlineCount))"
        case .find: "Find"
        }
    }
}
