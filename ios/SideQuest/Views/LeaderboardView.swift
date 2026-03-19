import SwiftUI

struct LeaderboardView: View {
    let appState: AppState
    @Environment(\.dismiss) private var dismiss
    @State private var selectedPeriod: LeaderboardPeriod = .allTime

    private var entries: [LeaderboardEntry] {
        appState.leaderboardForPeriod(selectedPeriod)
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                Picker("Period", selection: $selectedPeriod) {
                    ForEach(LeaderboardPeriod.allCases) { period in
                        Text(period.rawValue).tag(period)
                    }
                }
                .pickerStyle(.segmented)
                .padding(.horizontal, 16)
                .padding(.vertical, 8)

                List {
                    ForEach(entries) { entry in
                        HStack(spacing: 14) {
                            rankBadge(entry.rank)

                            Image(systemName: entry.avatarName)
                                .font(.body)
                                .foregroundStyle(.white)
                                .frame(width: 40, height: 40)
                                .background(avatarGradient(entry.callingCardName), in: Circle())

                            VStack(alignment: .leading, spacing: 2) {
                                HStack(spacing: 4) {
                                    Text(entry.username)
                                        .font(.body.weight(.semibold))
                                    if entry.username == appState.profile.username {
                                        Text("You")
                                            .font(.caption2.weight(.bold))
                                            .foregroundStyle(.white)
                                            .padding(.horizontal, 6)
                                            .padding(.vertical, 1)
                                            .background(.blue, in: Capsule())
                                    }
                                }
                                HStack(spacing: 8) {
                                    Label("\(entry.verifiedCount)", systemImage: "checkmark.seal.fill")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                    if entry.masterCount > 0 {
                                        Label("\(entry.masterCount)", systemImage: "crown.fill")
                                            .font(.caption)
                                            .foregroundStyle(.purple)
                                    }
                                }
                            }

                            Spacer()

                            Text(entry.totalScore.formatted())
                                .font(.headline.monospacedDigit())
                        }
                        .listRowBackground(entry.username == appState.profile.username ? Color.blue.opacity(0.08) : nil)
                    }
                }
                .listStyle(.plain)
                .animation(.snappy, value: selectedPeriod)
            }
            .navigationTitle("Leaderboard")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }

    @ViewBuilder
    private func rankBadge(_ rank: Int) -> some View {
        if rank <= 3 {
            Image(systemName: "medal.fill")
                .font(.title2)
                .foregroundStyle(medalColor(rank))
                .frame(width: 32)
        } else {
            Text("#\(rank)")
                .font(.subheadline.weight(.bold).monospacedDigit())
                .foregroundStyle(.secondary)
                .frame(width: 32)
        }
    }

    private func medalColor(_ rank: Int) -> Color {
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

nonisolated enum LeaderboardPeriod: String, CaseIterable, Identifiable {
    case allTime = "All Time"
    case past30Days = "Past 30 Days"
    var id: String { rawValue }
}
