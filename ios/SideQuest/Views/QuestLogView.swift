import SwiftUI
import MapKit

struct QuestLogView: View {
    let appState: AppState
    @Environment(\.dismiss) private var dismiss
    @State private var selectedLogTab: LogTab = .verified

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                Picker("Log", selection: $selectedLogTab) {
                    ForEach(LogTab.allCases) { tab in
                        Text(tab.rawValue).tag(tab)
                    }
                }
                .pickerStyle(.segmented)
                .padding(.horizontal, 16)
                .padding(.vertical, 8)

                List {
                    switch selectedLogTab {
                    case .verified:
                        verifiedHistory
                    case .master:
                        masterHistory
                    case .open:
                        openPlayScrapbook
                    case .custom:
                        customQuestHistory
                    }
                }
                .listStyle(.insetGrouped)
            }
            .navigationTitle("Side Quest Log")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }

    private var verifiedHistory: some View {
        let verified = appState.activeInstances.filter { $0.state == .verified }
        let submitted = appState.activeInstances.filter { $0.state == .submitted }
        let rejected = appState.activeInstances.filter { $0.state == .rejected }
        return Group {
            if verified.isEmpty && submitted.isEmpty && rejected.isEmpty && appState.completedHistory.isEmpty {
                Section {
                    ContentUnavailableView("No Verified Side Quests", systemImage: "checkmark.seal", description: Text("Complete and get verified to see your history here."))
                }
            } else {
                if !submitted.isEmpty {
                    Section("Pending Verification") {
                        ForEach(submitted) { instance in
                            HStack {
                                PathBadgeView(path: instance.quest.path, compact: true)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(instance.quest.title)
                                        .font(.subheadline.weight(.medium))
                                    if let date = instance.submittedAt {
                                        Text("Submitted \(date, style: .relative) ago")
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                }
                                Spacer()
                                ProgressView()
                                    .scaleEffect(0.8)
                            }
                        }
                    }
                }

                if !rejected.isEmpty {
                    Section("Rejected") {
                        ForEach(rejected) { instance in
                            HStack {
                                PathBadgeView(path: instance.quest.path, compact: true)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(instance.quest.title)
                                        .font(.subheadline.weight(.medium))
                                    Text("Submission rejected")
                                        .font(.caption)
                                        .foregroundStyle(.red)
                                }
                                Spacer()
                                Image(systemName: "xmark.circle.fill")
                                    .foregroundStyle(.red)
                            }
                        }
                    }
                }

                if !verified.isEmpty {
                    Section("Recently Verified") {
                        ForEach(verified) { instance in
                            verifiedQuestRow(instance)
                        }
                    }
                }

                Section("Reward History") {
                    ForEach(appState.completedHistory) { event in
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(event.questTitle)
                                    .font(.subheadline.weight(.medium))
                                Text(event.createdAt, style: .relative)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            VStack(alignment: .trailing, spacing: 2) {
                                Text("+\(event.xpEarned) XP")
                                    .font(.caption.weight(.bold))
                                    .foregroundStyle(.orange)
                                if event.goldEarned > 0 {
                                    Text("+\(event.goldEarned) Gold")
                                        .font(.caption2.weight(.medium))
                                        .foregroundStyle(.yellow)
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    private func verifiedQuestRow(_ instance: QuestInstance) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                PathBadgeView(path: instance.quest.path, compact: true)
                VStack(alignment: .leading, spacing: 2) {
                    Text(instance.quest.title)
                        .font(.subheadline.weight(.medium))
                    if let date = instance.verifiedAt {
                        Text(date, style: .relative)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer()
                HStack(spacing: 4) {
                    Image(systemName: "checkmark.seal.fill")
                        .foregroundStyle(.blue)
                    Text("Verified")
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(.blue)
                }
            }

            if let session = appState.completedSessions[instance.id] ?? appState.trackingSessions[instance.id] {
                trackingDataRow(session, quest: instance.quest)
            }
        }
        .padding(.vertical, 4)
    }

    private func trackingDataRow(_ session: TrackingSession, quest: Quest) -> some View {
        VStack(spacing: 8) {
            if session.coordinates.count >= 2 {
                routeMapThumbnail(session: session, quest: quest)
            }

            HStack(spacing: 16) {
                VStack(spacing: 2) {
                    Text(String(format: "%.2f", session.distanceMiles))
                        .font(.caption.monospacedDigit().weight(.bold))
                    Text("miles")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                Divider().frame(height: 24)
                VStack(spacing: 2) {
                    Text(formatDuration(session.durationSeconds))
                        .font(.caption.monospacedDigit().weight(.bold))
                    Text("time")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                Divider().frame(height: 24)
                VStack(spacing: 2) {
                    Text(session.isValid ? "Valid" : "Flagged")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(session.isValid ? .green : .orange)
                    Text("integrity")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 8)
            .background(Color(.tertiarySystemGroupedBackground), in: .rect(cornerRadius: 8))
        }
    }

    private func routeMapThumbnail(session: TrackingSession, quest: Quest) -> some View {
        let region = routeRegion(for: session)
        let pathColor = PathColorHelper.color(for: quest.path)
        return Map(position: .constant(.region(region)), interactionModes: []) {
            if session.coordinates.count >= 2 {
                MapPolyline(coordinates: session.coordinates)
                    .stroke(pathColor.gradient, lineWidth: 3)
            }
        }
        .mapStyle(.standard)
        .frame(height: 120)
        .clipShape(.rect(cornerRadius: 10))
        .allowsHitTesting(false)
    }

    private func routeRegion(for session: TrackingSession) -> MKCoordinateRegion {
        guard !session.routePoints.isEmpty else {
            return MKCoordinateRegion(
                center: CLLocationCoordinate2D(latitude: 37.3346, longitude: -122.0090),
                span: MKCoordinateSpan(latitudeDelta: 0.01, longitudeDelta: 0.01)
            )
        }
        let lats = session.routePoints.map(\.latitude)
        let lons = session.routePoints.map(\.longitude)
        let center = CLLocationCoordinate2D(
            latitude: (lats.min()! + lats.max()!) / 2,
            longitude: (lons.min()! + lons.max()!) / 2
        )
        let span = MKCoordinateSpan(
            latitudeDelta: max(0.005, (lats.max()! - lats.min()!) * 1.5),
            longitudeDelta: max(0.005, (lons.max()! - lons.min()!) * 1.5)
        )
        return MKCoordinateRegion(center: center, span: span)
    }

    private var masterHistory: some View {
        let completed = appState.masterContracts.filter { $0.isCompleted }
        let active = appState.masterContracts.filter { $0.isActive }
        return Group {
            if !active.isEmpty {
                Section("Active Contracts") {
                    ForEach(active) { contract in
                        HStack {
                            Image(systemName: "flame.fill")
                                .foregroundStyle(PathColorHelper.color(for: contract.path))
                            VStack(alignment: .leading) {
                                Text(contract.title)
                                    .font(.subheadline.weight(.semibold))
                                Text("Day \(contract.currentDay)/\(contract.durationDays)")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            ProgressView(value: Double(contract.currentDay), total: Double(contract.durationDays))
                                .frame(width: 60)
                                .tint(PathColorHelper.color(for: contract.path))
                        }
                    }
                }
            }

            if completed.isEmpty && active.isEmpty {
                Section {
                    VStack(spacing: 12) {
                        Image(systemName: "crown.fill")
                            .font(.largeTitle)
                            .foregroundStyle(.purple.opacity(0.3))
                        Text("No Master Completions Yet")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                        Text("Start a Master Contract to begin your quest.")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 24)
                }
            } else if !completed.isEmpty {
                Section("Completed") {
                    ForEach(completed) { contract in
                        HStack {
                            Image(systemName: "crown.fill")
                                .foregroundStyle(.purple)
                            VStack(alignment: .leading) {
                                Text(contract.title)
                                    .font(.subheadline.weight(.semibold))
                                Text(contract.subtitle)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundStyle(.green)
                        }
                    }
                }
            }
        }
    }

    private var openPlayScrapbook: some View {
        Group {
            if appState.openPlayHistory.isEmpty {
                Section {
                    VStack(spacing: 12) {
                        Image(systemName: "book.fill")
                            .font(.largeTitle)
                            .foregroundStyle(.tertiary)
                        Text("Your Personal Journal")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                        Text("Open Play side quest completions appear here as personal records.")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                            .multilineTextAlignment(.center)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 24)
                }
            } else {
                Section("Personal Records") {
                    ForEach(appState.openPlayHistory) { instance in
                        HStack {
                            PathBadgeView(path: instance.quest.path, compact: true)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(instance.quest.title)
                                    .font(.subheadline.weight(.medium))
                                if let date = instance.verifiedAt {
                                    Text(date, style: .relative)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                            Spacer()
                            Text("+\(instance.quest.xpReward) XP")
                                .font(.caption.weight(.medium))
                                .foregroundStyle(.orange)
                        }
                    }
                }
            }
        }
    }

    private var customQuestHistory: some View {
        Group {
            let customCompletions = appState.openPlayHistory.filter { $0.quest.id.hasPrefix("custom_") }
            if appState.customQuests.isEmpty && customCompletions.isEmpty {
                Section {
                    VStack(spacing: 12) {
                        Image(systemName: "sparkle.magnifyingglass")
                            .font(.largeTitle)
                            .foregroundStyle(.tertiary)
                        Text("No Custom Side Quests")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                        Text("Create personal side quests to track your own activities.")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                            .multilineTextAlignment(.center)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 24)
                }
            } else {
                if !appState.customQuests.isEmpty {
                    Section("My Custom Side Quests (\(appState.customQuests.count))") {
                        ForEach(appState.customQuests) { quest in
                            HStack {
                                PathBadgeView(path: quest.path, compact: true)
                                VStack(alignment: .leading, spacing: 2) {
                                    HStack(spacing: 6) {
                                        Text(quest.title)
                                            .font(.subheadline.weight(.medium))
                                        Text("Custom")
                                            .font(.system(size: 9, weight: .bold))
                                            .foregroundStyle(.indigo)
                                            .padding(.horizontal, 5)
                                            .padding(.vertical, 2)
                                            .background(.indigo.opacity(0.12), in: Capsule())
                                    }
                                    Text("\(quest.completionCount)x completed")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                Spacer()
                                Text("+\(quest.toQuest().xpReward) XP")
                                    .font(.caption.weight(.medium))
                                    .foregroundStyle(.orange)
                            }
                        }
                    }
                }

                if !customCompletions.isEmpty {
                    Section("Completion History") {
                        ForEach(customCompletions) { instance in
                            HStack {
                                PathBadgeView(path: instance.quest.path, compact: true)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(instance.quest.title)
                                        .font(.subheadline.weight(.medium))
                                    if let date = instance.verifiedAt {
                                        Text(date, style: .relative)
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                }
                                Spacer()
                                Text("+\(instance.quest.xpReward) XP")
                                    .font(.caption.weight(.medium))
                                    .foregroundStyle(.orange)
                            }
                        }
                    }
                }
            }
        }
    }

    private func formatDuration(_ seconds: TimeInterval) -> String {
        let total = Int(max(0, seconds))
        let h = total / 3600
        let m = (total % 3600) / 60
        let s = total % 60
        if h > 0 {
            return String(format: "%d:%02d:%02d", h, m, s)
        }
        return String(format: "%02d:%02d", m, s)
    }
}

nonisolated enum LogTab: String, CaseIterable, Identifiable {
    case verified = "Verified"
    case master = "Master"
    case open = "Open"
    case custom = "Custom"
    var id: String { rawValue }
}
