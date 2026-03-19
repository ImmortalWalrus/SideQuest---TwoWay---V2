import SwiftUI

struct JourneysHomeView: View {
    let appState: AppState
    @State private var showCreateJourney: Bool = false
    @State private var showSmartBuilder: Bool = false
    @State private var showBrowse: Bool = false
    @State private var selectedJourney: Journey?
    @State private var showCompleted: Bool = false
    @State private var showStoryQuickPlay: Bool = false
    @State private var showInventory: Bool = false

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                activeSection
                storySection
                createButton
                browseButton
                if !appState.completedJourneys.isEmpty {
                    completedSection
                }
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 20)
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle("Quests")
        .sheet(isPresented: $showCreateJourney) {
            CreateJourneyView(appState: appState)
        }
        .sheet(isPresented: $showSmartBuilder) {
            SmartCampaignBuilderView(appState: appState)
        }
        .sheet(isPresented: $showBrowse) {
            BrowseJourneysView(appState: appState)
        }
        .sheet(item: $selectedJourney) { journey in
            JourneyDetailView(journeyId: journey.id, appState: appState)
        }
        .sheet(isPresented: $showCompleted) {
            completedHistorySheet
        }
        .sheet(isPresented: $showStoryQuickPlay) {
            StoryPlayView(appState: appState, templateId: SampleStoryData.allTemplates.first?.id ?? "")
        }
        .sheet(isPresented: $showInventory) {
            InventoryView(appState: appState)
        }
    }

    @ViewBuilder
    private var activeSection: some View {
        if appState.activeJourneys.isEmpty {
            emptyState
        } else {
            VStack(alignment: .leading, spacing: 12) {
                Text("ACTIVE QUESTS")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .textCase(.uppercase)

                ForEach(appState.activeJourneys) { journey in
                    Button { selectedJourney = journey } label: {
                        JourneyCard(journey: journey, quests: appState.allQuests)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private var storySection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("CAMPAIGN")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .textCase(.uppercase)
                Spacer()
                if !appState.storyEngine.globalInventory.isEmpty {
                    Button { showInventory = true } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "shippingbox.fill")
                                .font(.caption2)
                            Text("\(appState.storyEngine.globalInventory.count) Items")
                                .font(.caption.weight(.semibold))
                        }
                        .foregroundStyle(.indigo)
                    }
                    .buttonStyle(.plain)
                }
            }

            Button { showStoryQuickPlay = true } label: {
                HStack(spacing: 12) {
                    ZStack {
                        Circle()
                            .fill(.indigo.opacity(0.12))
                            .frame(width: 44, height: 44)
                        Image(systemName: "book.pages.fill")
                            .font(.title3.weight(.semibold))
                            .foregroundStyle(.indigo)
                    }
                    VStack(alignment: .leading, spacing: 3) {
                        Text("Quick Play: The Temple of Echoes")
                            .font(.subheadline.weight(.semibold))
                        Text("Play through the branching story without challenges")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Image(systemName: "play.fill")
                        .font(.caption)
                        .foregroundStyle(.indigo)
                }
                .padding(14)
                .background(
                    LinearGradient(
                        colors: [Color.indigo.opacity(0.08), Color.purple.opacity(0.04)],
                        startPoint: .leading,
                        endPoint: .trailing
                    ),
                    in: .rect(cornerRadius: 14)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 14)
                        .strokeBorder(Color.indigo.opacity(0.15), lineWidth: 1)
                )
            }
            .buttonStyle(.plain)
        }
    }

    private var emptyState: some View {
        VStack(spacing: 16) {
            Image(systemName: "map.fill")
                .font(.system(size: 44))
                .foregroundStyle(.blue.opacity(0.6))
                .padding(.top, 24)

            Text("No Active Quests")
                .font(.title3.weight(.semibold))

            Text("Create a quest to schedule side quests across days and track your progress over time.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 20)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 20)
    }

    private var createButton: some View {
        VStack(spacing: 10) {
            Button {
                showSmartBuilder = true
            } label: {
                HStack(spacing: 10) {
                    ZStack {
                        Circle()
                            .fill(.white.opacity(0.2))
                            .frame(width: 30, height: 30)
                        Image(systemName: "wand.and.stars")
                            .font(.system(size: 14, weight: .bold))
                    }
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Smart Build")
                            .font(.headline)
                        Text("AI picks quests for your skills & schedule")
                            .font(.caption)
                            .opacity(0.85)
                    }
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.caption.weight(.bold))
                        .opacity(0.7)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 14)
                .background(
                    LinearGradient(
                        colors: [Color.blue, Color.indigo],
                        startPoint: .leading,
                        endPoint: .trailing
                    ),
                    in: .rect(cornerRadius: 16)
                )
                .foregroundStyle(.white)
            }
            .buttonStyle(.plain)
            .disabled(!appState.canCreateJourney)
            .sensoryFeedback(.impact(weight: .medium), trigger: showSmartBuilder)

            Button { showCreateJourney = true } label: {
                HStack(spacing: 8) {
                    Image(systemName: "slider.horizontal.3")
                        .font(.subheadline)
                    Text("Manual Build")
                        .font(.subheadline.weight(.semibold))
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
                .background(Color(.secondarySystemGroupedBackground), in: .rect(cornerRadius: 14))
                .foregroundStyle(appState.canCreateJourney ? .primary : .secondary)
            }
            .buttonStyle(.plain)
            .disabled(!appState.canCreateJourney)
            .sensoryFeedback(.impact(weight: .light), trigger: showCreateJourney)

            if !appState.canCreateJourney {
                Text("Maximum \(appState.maxActiveJourneys) active quests reached")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var browseButton: some View {
        Button { showBrowse = true } label: {
            HStack(spacing: 10) {
                Image(systemName: "globe")
                    .font(.title3)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Browse Public Quests")
                        .font(.subheadline.weight(.semibold))
                    Text("\(appState.journeyTemplates.count) templates available")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.tertiary)
            }
            .padding(14)
            .background(Color(.secondarySystemGroupedBackground), in: .rect(cornerRadius: 14))
        }
        .buttonStyle(.plain)
    }

    private var completedSection: some View {
        Button { showCompleted = true } label: {
            HStack(spacing: 10) {
                Image(systemName: "checkmark.circle.fill")
                    .font(.title3)
                    .foregroundStyle(.green)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Completed Quests")
                        .font(.subheadline.weight(.semibold))
                    Text("\(appState.completedJourneys.count) quests finished")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.tertiary)
            }
            .padding(14)
            .background(Color(.secondarySystemGroupedBackground), in: .rect(cornerRadius: 14))
        }
        .buttonStyle(.plain)
    }

    private var completedHistorySheet: some View {
        NavigationStack {
            List {
                ForEach(appState.completedJourneys) { journey in
                    VStack(alignment: .leading, spacing: 6) {
                        Text(journey.name)
                            .font(.headline)
                        HStack(spacing: 12) {
                            Label("\(journey.totalDays) days", systemImage: "calendar")
                            Label("\(journey.questItems.count) side quests", systemImage: "scroll.fill")
                        }
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        Text("Completed \(journey.overallCompletionPercent * 100, specifier: "%.0f")%")
                            .font(.caption.weight(.medium))
                            .foregroundStyle(.green)
                    }
                    .padding(.vertical, 4)
                }
            }
            .navigationTitle("Completed")
            .navigationBarTitleDisplayMode(.inline)
        }
    }
}

struct JourneyCard: View {
    let journey: Journey
    let quests: [Quest]

    private var dominantPath: QuestPath {
        let questIds = journey.questItems.map(\.questId)
        let paths = questIds.compactMap { id in quests.first(where: { $0.id == id })?.path }
        let counts = Dictionary(grouping: paths, by: { $0 }).mapValues(\.count)
        return counts.max(by: { $0.value < $1.value })?.key ?? .warrior
    }

    private var pathColor: Color {
        PathColorHelper.color(for: dominantPath)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(journey.name)
                        .font(.headline)
                        .lineLimit(1)

                    HStack(spacing: 8) {
                        Label(journey.mode.rawValue, systemImage: journey.mode.icon)
                        Text("·")
                        Text("Day \(journey.currentDay)/\(journey.totalDays)")
                        if journey.verificationMode == .nonVerified {
                            Text("·")
                            HStack(spacing: 2) {
                                Image(systemName: "hand.thumbsup.fill")
                                Text("Non-Verified")
                            }
                            .foregroundStyle(.orange)
                        }
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }
                Spacer()
                journeyProgressRing
            }

            HStack(spacing: 16) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Today")
                        .font(.caption2.weight(.medium))
                        .foregroundStyle(.secondary)
                    Text("\(journey.todayTaskCount) side quests")
                        .font(.subheadline.weight(.semibold))
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text("Remaining")
                        .font(.caption2.weight(.medium))
                        .foregroundStyle(.secondary)
                    Text("\(journey.daysRemaining) days")
                        .font(.subheadline.weight(.semibold))
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text("Streak")
                        .font(.caption2.weight(.medium))
                        .foregroundStyle(.secondary)
                    HStack(spacing: 2) {
                        Image(systemName: "flame.fill")
                            .font(.caption)
                            .foregroundStyle(.orange)
                        Text("\(journey.streakDays)")
                            .font(.subheadline.weight(.semibold))
                    }
                }

                Spacer()

                if let nextQuest = nextScheduledQuest {
                    VStack(alignment: .trailing, spacing: 2) {
                        Text("Next")
                            .font(.caption2.weight(.medium))
                            .foregroundStyle(.secondary)
                        Text(nextQuest)
                            .font(.caption.weight(.medium))
                            .foregroundStyle(pathColor)
                    }
                }
            }
        }
        .padding(16)
        .background {
            RoundedRectangle(cornerRadius: 16)
                .fill(.linearGradient(
                    colors: [pathColor.opacity(0.08), Color(.secondarySystemGroupedBackground)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                ))
        }
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .strokeBorder(pathColor.opacity(0.15), lineWidth: 1)
        )
    }

    private var journeyProgressRing: some View {
        ZStack {
            Circle()
                .stroke(.quaternary, lineWidth: 4)
            Circle()
                .trim(from: 0, to: journey.overallCompletionPercent)
                .stroke(pathColor, style: StrokeStyle(lineWidth: 4, lineCap: .round))
                .rotationEffect(.degrees(-90))
            Text("\(Int(journey.overallCompletionPercent * 100))%")
                .font(.system(size: 11, weight: .bold).monospacedDigit())
        }
        .frame(width: 44, height: 44)
    }

    private var nextScheduledQuest: String? {
        let today = journey.scheduledQuestsForDate(Date())
        guard let next = today.first(where: { item in
            let status = journey.questStatusForDate(item.id, date: Date())
            return status == .notStarted
        }) else { return nil }
        return next.timeDescription
    }
}
