import SwiftUI

private let questPageBg = Color(red: 0.086, green: 0.094, blue: 0.110)
private let questCardSurface = Color(red: 0.161, green: 0.169, blue: 0.204)
private let questPillSurface = Color(red: 0.16, green: 0.175, blue: 0.20)

nonisolated enum QuestsMode: String, CaseIterable, Identifiable {
    case forYou = "For You"
    case programs = "Programs"
    case events = "Events"
    case browse = "Browse"

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .forYou: "sparkles"
        case .programs: "map.fill"
        case .events: "calendar.badge.clock"
        case .browse: "square.grid.2x2.fill"
        }
    }
}

nonisolated enum BrowseChip: String, CaseIterable, Identifiable {
    case all = "All"
    case verified = "Verified"
    case open = "Open"
    case warrior = "Warrior"
    case explorer = "Explorer"
    case mind = "Mind"
    case nearby = "Nearby"
    case easy = "Easy"
    case medium = "Medium"
    case hard = "Hard"
    case quick = "Quick"

    var id: String { rawValue }

    var icon: String? {
        switch self {
        case .all: nil
        case .verified: "checkmark.seal.fill"
        case .open: "person.fill"
        case .warrior: "flame.fill"
        case .explorer: "map.fill"
        case .mind: "brain.head.profile.fill"
        case .nearby: "location.fill"
        case .easy: nil
        case .medium: nil
        case .hard: nil
        case .quick: "clock.fill"
        }
    }
}

nonisolated enum EventsCategory: String, CaseIterable, Identifiable {
    case all = "All"
    case concerts = "Concerts"
    case sports = "Sports"
    case comedy = "Comedy"
    case nightlife = "Nightlife"
    case community = "Community"
    case races = "Races"

    var id: String { rawValue }

    var iconName: String {
        switch self {
        case .all: "generic_live_event"
        case .concerts: "concert_generic_01"
        case .sports: "basketball"
        case .comedy: "comedy_show"
        case .nightlife: "nightlife_party_v1"
        case .community: "community_social"
        case .races: "race_short_v1"
        }
    }

    var baseFilterOption: ExternalEventFilterOption {
        switch self {
        case .all, .comedy: .all
        case .concerts: .concerts
        case .sports: .sports
        case .nightlife: .nightlife
        case .community: .community
        case .races: .races
        }
    }
}

nonisolated enum EventFilterChip: String, CaseIterable, Identifiable {
    case tonight = "Tonight"
    case tomorrow = "Tomorrow"
    case thisWeek = "This Week"
    case weekend = "Weekend"
    case exclusive = "Exclusive"
    case free = "Free"
    case nearby = "Nearby"
    case underThirty = "Under $30"
    case sellingFast = "Selling Fast"
    case hasPhotos = "Has Photos"
    case topRated = "Top Rated"
    case indoor = "Indoor"
    case outdoor = "Outdoor"
    case twentyOnePlus = "21+"
    case walkable = "Walkable"
    case verifiedVenue = "Verified Venue"

    var id: String { rawValue }
}

private struct EventFeedSectionItem: Identifiable {
    let index: Int
    let event: ExternalEvent

    var id: String { event.id }
}

private struct EventFeedSectionData: Identifiable {
    let id: String
    let title: String
    let subtitle: String?
    let items: [EventFeedSectionItem]
}

private struct ForYouSnapshot {
    let featuredQuest: Quest?
    let todaysPicks: [Quest]
    let weeklyChallenge: Quest?
    let recommendedFamilies: [QuestFamily]
}

struct QuestsTabView: View {
    let appState: AppState
    @State private var selectedMode: QuestsMode = .forYou
    @State private var searchText: String = ""
    @State private var selectedQuest: Quest?
    @State private var selectedExternalEvent: ExternalEvent?
    @State private var showGoals: Bool = false
    @State private var showCreateCustomQuest: Bool = false
    @State private var showMyQuests: Bool = false
    @State private var selectedCustomQuest: CustomQuest?
    @State private var showTagSetup: Bool = false
    @State private var showJourneys: Bool = false
    @State private var selectedContractId: String?
    @State private var browseChips: Set<BrowseChip> = [.all]
    @State private var selectedFamily: QuestFamily?
    @State private var browseCatalogQuests: [Quest] = []
    @State private var browseCatalogFamilies: [QuestFamily] = []
    @State private var browseCatalogSignature: String = ""
    @State private var browseCatalogGeneration: Int = 0
    @State private var isPreparingBrowseCatalog: Bool = false
    @State private var browseVisibleItemCount: Int = 12
    @State private var deferredEventLoadTask: Task<Void, Never>?
    @State private var isPullRefreshing: Bool = false
    @State private var pullRefreshHasTriggered: Bool = false
    @State private var isPullRefreshHintVisible: Bool = false
    @State private var isPullRefreshArmed: Bool = false
    @State private var eventVisibleItemCount: Int = 10
    @State private var preparedForYouSnapshot: ForYouSnapshot?
    @State private var forYouSnapshotSignature: String = ""
    @State private var forYouSnapshotGeneration: Int = 0
    @State private var isPreparingForYouSnapshot: Bool = false
    @State private var selectedEventsCategory: EventsCategory = .all
    @State private var selectedEventFilterChips: Set<EventFilterChip> = []

    var body: some View {
        NavigationStack {
            mainContent
                .safeAreaInset(edge: .top, spacing: 0) {
                    modeSelector
                }
                .background(questPageBg)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    Text("QUESTS")
                        .font(.system(size: 20, weight: .black))
                        .tracking(2)
                        .foregroundStyle(.white)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    HStack(spacing: 12) {
                        Button { showCreateCustomQuest = true } label: {
                            Image(systemName: "plus.circle.fill")
                        }
                        Button { showGoals = true } label: {
                            ZStack(alignment: .topTrailing) {
                                Image(systemName: appState.savedQuestIds.isEmpty ? "heart" : "heart.fill")
                                    .foregroundStyle(appState.savedQuestIds.isEmpty ? Color.secondary : Color.red)
                                if !appState.savedQuestIds.isEmpty {
                                    Text("\(appState.savedQuestIds.count)")
                                        .font(.system(size: 9, weight: .bold))
                                        .foregroundStyle(.white)
                                        .padding(3)
                                        .background(.red, in: Circle())
                                        .offset(x: 8, y: -8)
                                }
                            }
                            .frame(width: 32, height: 32)
                        }
                    }
                }
            }
            .toolbarBackground(questPageBg, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .searchable(text: $searchText, prompt: "Search quests...")
            .task {
                if selectedMode == .forYou, searchText.isEmpty {
                    scheduleForYouSnapshotRefresh()
                }
                if selectedMode == .browse {
                    scheduleBrowseCatalogRefresh()
                }
                if appState.externalEventFeed.isEmpty {
                    scheduleExternalEventWarmup(delayNanoseconds: 350_000_000)
                }
            }
            .task(id: forYouDependencyKey) {
                guard selectedMode == .forYou, searchText.isEmpty else { return }
                scheduleForYouSnapshotRefresh()
            }
            .task(id: browseCatalogDependencyKey) {
                guard selectedMode == .browse else { return }
                scheduleBrowseCatalogRefresh()
            }
            .sheet(item: $selectedQuest) { quest in
                QuestDetailView(quest: quest, appState: appState)
            }
            .sheet(item: $selectedExternalEvent) { event in
                NavigationStack {
                    ExternalEventDetailView(event: event, appState: appState)
                }
            }
            .sheet(isPresented: $showGoals) {
                GoalsView(appState: appState)
            }
            .sheet(isPresented: $showCreateCustomQuest) {
                CreateCustomQuestView(appState: appState)
            }
            .sheet(isPresented: $showMyQuests) {
                MyQuestsView(appState: appState)
            }
            .sheet(item: $selectedCustomQuest) { quest in
                CustomQuestDetailView(customQuest: quest, appState: appState)
            }
            .sheet(isPresented: $showTagSetup) {
                TagSetupSheet(appState: appState)
            }
            .sheet(isPresented: $showJourneys) {
                NavigationStack {
                    JourneysHomeView(appState: appState)
                }
            }
            .sheet(isPresented: Binding(
                get: { selectedContractId != nil },
                set: { if !$0 { selectedContractId = nil } }
            )) {
                if let contractId = selectedContractId {
                    MasterDashboardView(contractId: contractId, appState: appState)
                }
            }
            .sheet(item: $selectedFamily) { family in
                QuestFamilyDetailSheet(
                    family: family,
                    appState: appState,
                    onSelectQuest: { quest in
                        selectedFamily = nil
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                            selectedQuest = quest
                        }
                    }
                )
            }
            .onDisappear {
                deferredEventLoadTask?.cancel()
                forYouSnapshotGeneration += 1
                browseCatalogGeneration += 1
            }
        }
    }

    // MARK: - Mode Selector

    private var modeSelector: some View {
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                ForEach(Array(QuestsMode.allCases.enumerated()), id: \.element.id) { index, mode in
                    if index > 0 {
                        Rectangle()
                            .fill(Color.white.opacity(0.08))
                            .frame(width: 1, height: 14)
                    }
                    Button {
                        selectedMode = mode
                    } label: {
                        VStack(spacing: 4) {
                            HStack(spacing: 5) {
                                Image(systemName: mode.icon)
                                    .font(.system(size: 10, weight: .bold))
                                Text(mode.rawValue)
                                    .font(.system(size: 13, weight: selectedMode == mode ? .heavy : .medium))
                            }
                            .foregroundStyle(selectedMode == mode ? .white : .white.opacity(0.35))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 10)
                        }
                        .overlay(alignment: .bottom) {
                            if selectedMode == mode {
                                Capsule()
                                    .fill(modeAccentColor(mode))
                                    .frame(height: 2.5)
                                    .padding(.horizontal, 12)
                            }
                        }
                    }
                    .buttonStyle(.plain)
                    .sensoryFeedback(.selection, trigger: selectedMode)
                }
            }
            .padding(.horizontal, 12)

            Rectangle()
                .fill(Color.white.opacity(0.05))
                .frame(height: 0.5)
                .padding(.top, 2)
        }
        .background(questPageBg)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(Color.white.opacity(0.05))
                .frame(height: 0.5)
        }
    }

    private func modeAccentColor(_ mode: QuestsMode) -> Color {
        switch mode {
        case .forYou: .purple
        case .programs: .blue
        case .events: .orange
        case .browse: .white.opacity(0.6)
        }
    }

    // MARK: - Main Content

    private var mainContent: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 14) {
                    Color.clear
                        .frame(height: 0)
                        .id("quests-mode-top")

                    pullToRefreshHeader
                    pullToRefreshOffsetReader

                    switch selectedMode {
                    case .forYou:
                        forYouContent
                    case .programs:
                        programsContent
                    case .events:
                        eventsContent
                    case .browse:
                        browseContent
                    }
                }
                .padding(.horizontal, 14)
                .padding(.bottom, 20)
                .padding(.top, 8)
            }
            .coordinateSpace(name: "questsMainScroll")
            .background(questPageBg)
            .scrollIndicators(.hidden)
            .onPreferenceChange(QuestsPullOffsetPreferenceKey.self) { offset in
                handlePullOffsetChange(offset)
            }
            .onChange(of: selectedMode) { _, _ in
                DispatchQueue.main.async {
                    proxy.scrollTo("quests-mode-top", anchor: .top)
                }
            }
            .task(id: selectedMode) {
                DispatchQueue.main.async {
                    proxy.scrollTo("quests-mode-top", anchor: .top)
                }

                switch selectedMode {
                case .events:
                    if eventVisibleItemCount > 10 {
                        eventVisibleItemCount = 10
                    }
                    if shouldWarmEventsOnModeSwitch {
                        scheduleExternalEventWarmup(delayNanoseconds: 150_000_000)
                    }
                case .forYou:
                    if searchText.isEmpty {
                        scheduleForYouSnapshotRefresh()
                    }
                    if appState.externalEventFeed.isEmpty {
                        scheduleExternalEventWarmup(delayNanoseconds: 300_000_000)
                    }
                case .browse:
                    scheduleBrowseCatalogRefresh()
                case .programs:
                    break
                }
            }
        }
    }

    private var supportsPullToRefresh: Bool {
        selectedMode == .events || selectedMode == .forYou
    }

    private var shouldWarmEventsOnModeSwitch: Bool {
        if appState.eventsTabExternalEventFeed.isEmpty {
            return true
        }
        guard let lastFetchedAt = appState.externalEventsLastFetchedAt else {
            return true
        }
        return Date().timeIntervalSince(lastFetchedAt) > 60 * 15
    }

    private var pullToRefreshHeader: some View {
        Group {
            if supportsPullToRefresh && (isPullRefreshHintVisible || isPullRefreshing) {
                HStack(spacing: 10) {
                    Group {
                        if isPullRefreshing {
                            ProgressView()
                                .tint(.orange)
                        } else {
                            Image(systemName: isPullRefreshArmed ? "arrow.down.circle.fill" : "arrow.down")
                                .font(.system(size: 12, weight: .bold))
                                .foregroundStyle(.white.opacity(0.7))
                                .rotationEffect(.degrees(isPullRefreshArmed ? 180 : 0))
                        }
                    }

                    Text(isPullRefreshing ? "Refreshing live events..." : "Pull to refresh")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.white.opacity(0.72))
                }
                .frame(maxWidth: .infinity)
                .frame(height: 34)
                .background(questPageBg)
                .clipped()
            }
        }
    }

    private var pullToRefreshOffsetReader: some View {
        GeometryReader { proxy in
            Color.clear
                .preference(
                    key: QuestsPullOffsetPreferenceKey.self,
                    value: proxy.frame(in: .named("questsMainScroll")).minY
                )
        }
        .frame(height: 0)
    }

    // MARK: - For You (Discovery)

    private var playerContext: PersonalizationEngine.PlayerContext {
        appState.buildPlayerContext()
    }

    private var forYouContent: some View {
        Group {
            if !searchText.isEmpty {
                forYouSearchResultsContent
            } else if !appState.hasTagsConfigured && !appState.onboardingData.isComplete {
                forYouSetupPrompt
            } else if let snapshot = preparedForYouSnapshot {
                if snapshot.featuredQuest != nil {
                    featuredQuestSection(snapshot: snapshot)
                }
                todaysPicksSection(snapshot: snapshot)
                weeklyChallengeSection(snapshot: snapshot)
                recommendedFamilySection(snapshot: snapshot)
                nearbyEventTeaser
            } else if isPreparingForYouSnapshot {
                placeholderCard("Personalizing your quest feed...", icon: "sparkles")
            } else {
                nearbyEventTeaser
            }
        }
    }

    private var forYouSearchResultsContent: some View {
        let results = Self.filteredBrowseQuests(
            from: appState.allQuests,
            chips: [.all],
            searchText: searchText
        )
        let visibleResultCount = min(browseVisibleItemCount, results.count)

        return VStack(alignment: .leading, spacing: 10) {
            sectionHeader(title: "Search Results", icon: "magnifyingglass", color: .white)

            if results.isEmpty {
                placeholderCard("No quests match your search", icon: "magnifyingglass")
            } else {
                ForEach(Array(results.prefix(visibleResultCount).enumerated()), id: \.element.id) { index, quest in
                    questRow(quest: quest)
                        .task {
                            await loadMoreBrowseResultsIfNeeded(
                                visibleIndex: index,
                                totalCount: results.count
                            )
                        }
                }
            }
        }
    }

    private func featuredQuestSection(snapshot: ForYouSnapshot) -> some View {
        Group {
            if let quest = snapshot.featuredQuest {
                VStack(alignment: .leading, spacing: 10) {
                    sectionHeader(title: "Featured Quest", icon: "star.circle.fill", color: .yellow)

                    Button { selectedQuest = quest } label: {
                        QuestCardView(quest: quest, showCompletionCount: true, isFeaturedCard: true)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private func todaysPicksSection(snapshot: ForYouSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionHeader(title: "Today's Picks", icon: "star.fill", color: .yellow)

            let picks = snapshot.todaysPicks
            if picks.isEmpty {
                placeholderCard("Check back soon for personalized picks", icon: "sparkles")
            } else {
                ForEach(picks) { quest in
                    questRow(quest: quest)
                }
            }
        }
    }

    private func weeklyChallengeSection(snapshot: ForYouSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionHeader(title: "Weekly Challenge", icon: "flame.fill", color: .orange)

            if let quest = snapshot.weeklyChallenge {
                ZStack(alignment: .topLeading) {
                    Button { selectedQuest = quest } label: {
                        QuestCardView(quest: quest)
                    }
                    .buttonStyle(.plain)

                    weeklyChallengeTag
                }
            } else {
                placeholderCard("No weekly challenge right now", icon: "flame")
            }
        }
    }

    private var weeklyChallengeTag: some View {
        HStack(spacing: 4) {
            Image(systemName: "flame.fill")
                .font(.system(size: 9, weight: .bold))
            Text("Weekly Challenge")
                .font(.system(size: 10, weight: .bold))
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(.orange.gradient, in: Capsule())
        .padding(10)
    }

    private func recommendedFamilySection(snapshot: ForYouSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionHeader(title: "Recommended for You", icon: "sparkles", color: .purple)

            let visibleFamilies = snapshot.recommendedFamilies

            if visibleFamilies.isEmpty {
                placeholderCard("Set up your profile for personalized recommendations", icon: "sparkles")
            } else {
                ForEach(visibleFamilies) { family in
                    QuestFamilyCardView(family: family) {
                        if family.isLadder {
                            selectedFamily = family
                        } else {
                            selectedQuest = family.recommendedQuest
                        }
                    }
                }
            }
        }
    }

    private var nearbyEventTeaser: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionHeader(title: "Nearby & Events", icon: "location.fill", color: .green)
            ZStack(alignment: .topTrailing) {
                if appState.isRefreshingExternalEvents && appState.externalEventFeed.isEmpty {
                    placeholderCard("Pulling nearby live events...", icon: "dot.radiowaves.left.and.right")
                } else if appState.externalEventFeed.isEmpty {
                    placeholderCard("No nearby events right now. Check back later!", icon: "mappin.and.ellipse")
                } else {
                    ForEach(Array(appState.externalEventFeed.prefix(2))) { event in
                        Button { selectedExternalEvent = event } label: {
                            ExternalEventCardView(
                                event: event,
                                imageRefreshNonce: appState.externalEventImageRefreshNonce
                            )
                                .equatable()
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                }

                if appState.isRefreshingExternalEvents && !appState.externalEventFeed.isEmpty {
                    liveEventsUpdatingBadge
                        .padding(.top, 10)
                        .padding(.trailing, 10)
                }
            }
        }
    }

    private var forYouSetupPrompt: some View {
        VStack(spacing: 20) {
            ZStack {
                Circle()
                    .fill(
                        LinearGradient(
                            colors: [.purple.opacity(0.2), .blue.opacity(0.2)],
                            startPoint: .topLeading, endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 80, height: 80)
                Image(systemName: "sparkles")
                    .font(.system(size: 34))
                    .foregroundStyle(
                        .linearGradient(colors: [.purple, .blue], startPoint: .topLeading, endPoint: .bottomTrailing)
                    )
            }

            VStack(spacing: 8) {
                Text("Personalized Side Quests")
                    .font(.title3.weight(.bold))
                    .foregroundStyle(.white)
                Text("Pick your skills and interests to see quests matched to you.")
                    .font(.subheadline)
                    .foregroundStyle(.white.opacity(0.5))
                    .multilineTextAlignment(.center)
            }

            Button { showTagSetup = true } label: {
                Label("Set Up My Profile", systemImage: "slider.horizontal.3")
                    .font(.subheadline.weight(.semibold))
                    .padding(.horizontal, 20)
                    .padding(.vertical, 12)
            }
            .buttonStyle(.borderedProminent)
            .tint(.purple)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 60)
        .padding(.horizontal, 24)
    }

    // MARK: - Programs

    private var programsContent: some View {
        let filteredJourneys = appState.activeJourneys.filter {
            Self.journeyMatchesSearch($0, searchText: searchText)
        }
        let filteredTemplates = appState.journeyTemplates.filter {
            Self.templateMatchesSearch($0, searchText: searchText)
        }

        return VStack(spacing: 16) {
            if !filteredJourneys.isEmpty {
                VStack(alignment: .leading, spacing: 10) {
                    sectionHeader(title: "Active Programs", icon: "play.fill", color: .green)
                    ForEach(filteredJourneys) { journey in
                        Button { showJourneys = true } label: {
                            programCard(journey)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }

            VStack(alignment: .leading, spacing: 10) {
                sectionHeader(title: "Browse Programs", icon: "rectangle.stack.fill", color: .blue)

                if filteredTemplates.isEmpty {
                    placeholderCard(
                        searchText.isEmpty ? "No program templates available yet" : "No programs match your search",
                        icon: "map"
                    )
                } else {
                    ForEach(filteredTemplates.prefix(5)) { template in
                        Button { showJourneys = true } label: {
                            programTemplateRow(template)
                        }
                        .buttonStyle(.plain)
                    }
                    if filteredTemplates.count > 5 {
                        Button { showJourneys = true } label: {
                            HStack(spacing: 6) {
                                Text("View all \(filteredTemplates.count) programs")
                                    .font(.caption.weight(.semibold))
                                Image(systemName: "arrow.right")
                                    .font(.system(size: 10, weight: .bold))
                            }
                            .foregroundStyle(.blue)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }

    private func programCard(_ journey: Journey) -> some View {
        HStack(spacing: 14) {
            ZStack {
                Circle()
                    .stroke(.green.opacity(0.3), lineWidth: 3)
                    .frame(width: 48, height: 48)
                Circle()
                    .trim(from: 0, to: journey.overallCompletionPercent)
                    .stroke(.green, style: StrokeStyle(lineWidth: 3, lineCap: .round))
                    .frame(width: 48, height: 48)
                    .rotationEffect(.degrees(-90))
                Text("\(Int(journey.overallCompletionPercent * 100))%")
                    .font(.system(size: 11, weight: .bold).monospacedDigit())
                    .foregroundStyle(.white)
            }

            VStack(alignment: .leading, spacing: 3) {
                Text(journey.name)
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                Text("Day \(journey.currentDay)/\(journey.totalDays)")
                    .font(.caption2.weight(.medium))
                    .foregroundStyle(.white.opacity(0.4))
            }

            Spacer()

            Image(systemName: "chevron.right")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.white.opacity(0.3))
        }
        .padding(14)
        .background(questCardSurface.opacity(0.7), in: .rect(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(.green.opacity(0.12), lineWidth: 1))
    }

    private func programTemplateRow(_ template: JourneyTemplate) -> some View {
        HStack(spacing: 12) {
            Image(systemName: "map.fill")
                .font(.caption.weight(.bold))
                .foregroundStyle(.blue)
                .frame(width: 38, height: 38)
                .background(.blue.opacity(0.12), in: .rect(cornerRadius: 10))

            VStack(alignment: .leading, spacing: 2) {
                Text(template.title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                Text(template.description)
                    .font(.caption2)
                    .foregroundStyle(.white.opacity(0.4))
                    .lineLimit(1)
            }

            Spacer()

            Image(systemName: "chevron.right")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.white.opacity(0.3))
        }
        .padding(12)
        .background(questCardSurface.opacity(0.6), in: .rect(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(.white.opacity(0.06), lineWidth: 1))
    }

    // MARK: - Events

    private var eventsContent: some View {
        let displayedEvents = Array(visibleEventFeed.prefix(eventVisibleItemCount))
        let displayedSections = buildEventSections(from: displayedEvents)

        return VStack(spacing: 16) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 6) {
                    sectionHeader(title: "Live Event Quests", icon: "calendar.badge.clock", color: .orange)
                    Text(eventsStatusLine)
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.42))
                }

                Spacer()

                if appState.isRefreshingExternalEvents {
                    ProgressView()
                        .tint(.orange)
                        .scaleEffect(0.9)
                }
            }

            eventCategoryBar
            eventRefinementBar

            if selectedEventsCategory == .all,
               selectedEventFilterChips.isEmpty,
               !appState.exclusiveExternalEventFeed.isEmpty {
                exclusiveEventsSection
            }

            ZStack(alignment: .topTrailing) {
                if appState.isRefreshingExternalEvents && appState.eventsTabExternalEventFeed.isEmpty {
                    eventLoadingCard
                } else if !visibleEventFeed.isEmpty {
                    LazyVStack(spacing: 14) {
                        ForEach(displayedSections) { section in
                            VStack(alignment: .leading, spacing: 10) {
                                eventSectionHeader(title: section.title, subtitle: section.subtitle)

                                ForEach(section.items) { item in
                                    Button { selectedExternalEvent = item.event } label: {
                                        ExternalEventCardView(
                                            event: item.event,
                                            imageRefreshNonce: appState.externalEventImageRefreshNonce
                                        )
                                            .equatable()
                                            .contentShape(Rectangle())
                                    }
                                    .buttonStyle(.plain)
                                    .task {
                                        let isLastVisible = item.index >= displayedEvents.count - 2
                                        if isLastVisible {
                                            if eventVisibleItemCount < visibleEventFeed.count {
                                                eventVisibleItemCount = min(visibleEventFeed.count, eventVisibleItemCount + 10)
                                            } else {
                                                await appState.loadMoreExternalEvents()
                                            }
                                        }
                                    }
                                }
                            }
                        }

                        if appState.isLoadingMoreExternalEvents {
                            HStack(spacing: 10) {
                                ProgressView()
                                    .tint(.orange)
                                Text("Loading more nearby events...")
                                    .font(.caption.weight(.medium))
                                    .foregroundStyle(.white.opacity(0.55))
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 10)
                        }
                    }
                } else {
                    placeholderCard(
                        visibleEventEmptyMessage,
                        icon: "calendar.badge.exclamationmark"
                    )
                }

                if appState.isRefreshingExternalEvents && !visibleEventFeed.isEmpty {
                    liveEventsUpdatingBadge
                        .padding(.top, 10)
                        .padding(.trailing, 2)
                }
            }
        }
    }

    // MARK: - Browse (Catalog)

    private var browseContent: some View {
        VStack(spacing: 12) {
            browseChipBar
            browseCatalog
        }
    }

    private var eventCategoryBar: some View {
        ScrollView(.horizontal) {
            HStack(spacing: 14) {
                ForEach(EventsCategory.allCases) { category in
                    Button {
                        selectEventsCategory(category)
                    } label: {
                        VStack(spacing: 8) {
                            if let icon = QuestAssetMapping.bundleImage(named: category.iconName, ext: "png", folder: "EventIcons") {
                                Image(uiImage: icon)
                                    .resizable()
                                    .interpolation(.none)
                                    .scaledToFit()
                                    .frame(width: 46, height: 46)
                            }

                            Text(category.rawValue)
                                .font(.system(size: 12, weight: selectedEventsCategory == category ? .bold : .medium))
                                .foregroundStyle(selectedEventsCategory == category ? .white : .white.opacity(0.62))
                                .lineLimit(1)
                                .frame(maxWidth: 72)
                                .multilineTextAlignment(.center)

                            Capsule()
                                .fill(selectedEventsCategory == category ? Color.orange : Color.clear)
                                .frame(width: 26, height: 3)
                        }
                        .frame(width: 72)
                        .padding(.vertical, 4)
                        .background(
                            RoundedRectangle(cornerRadius: 16)
                                .fill(selectedEventsCategory == category ? Color.white.opacity(0.04) : Color.clear)
                        )
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .contentMargins(.horizontal, 0)
        .scrollIndicators(.hidden)
    }

    private var eventRefinementBar: some View {
        ZStack(alignment: .trailing) {
            ScrollView(.horizontal) {
                HStack(spacing: 8) {
                    ForEach(EventFilterChip.allCases) { chip in
                        Button {
                            toggleEventFilterChip(chip)
                        } label: {
                            Text(chip.rawValue)
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(selectedEventFilterChips.contains(chip) ? .white : .white.opacity(0.58))
                                .padding(.horizontal, 14)
                                .padding(.vertical, 8)
                                .background {
                                    if selectedEventFilterChips.contains(chip) {
                                        Capsule()
                                            .fill(Color.white.opacity(0.14))
                                            .overlay(Capsule().strokeBorder(.white.opacity(0.18), lineWidth: 1))
                                    } else {
                                        Capsule()
                                            .fill(questPillSurface.opacity(0.4))
                                            .overlay(Capsule().strokeBorder(.white.opacity(0.07), lineWidth: 1))
                                    }
                                }
                        }
                        .buttonStyle(.plain)
                    }

                    Menu {
                        ForEach(eventSortMenuOptions, id: \.id) { option in
                            Button {
                                withAnimation(.snappy) {
                                    eventVisibleItemCount = 10
                                    appState.setExternalEventSortOption(option)
                                }
                            } label: {
                                if option == appState.externalEventSortOption {
                                    Label(eventSortDisplayName(option), systemImage: "checkmark")
                                } else {
                                    Text(eventSortDisplayName(option))
                                }
                            }
                        }
                    } label: {
                        HStack(spacing: 6) {
                            Text("Sort")
                            Text(eventSortDisplayName(appState.externalEventSortOption))
                                .foregroundStyle(.white.opacity(0.88))
                            Image(systemName: "chevron.down")
                                .font(.system(size: 10, weight: .bold))
                        }
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.72))
                        .padding(.horizontal, 14)
                        .padding(.vertical, 8)
                        .background(
                            Capsule()
                                .fill(questPillSurface.opacity(0.55))
                                .overlay(Capsule().strokeBorder(.white.opacity(0.08), lineWidth: 1))
                        )
                    }
                    .buttonStyle(.plain)
                }
                .padding(.trailing, 28)
            }
            .contentMargins(.horizontal, 0)
            .scrollIndicators(.hidden)

            HStack(spacing: 0) {
                LinearGradient(
                    colors: [Color.clear, questPageBg.opacity(0.82), questPageBg],
                    startPoint: .leading,
                    endPoint: .trailing
                )
                .frame(width: 52)

                Image(systemName: "chevron.right")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(.white.opacity(0.42))
                    .padding(.trailing, 2)
            }
            .allowsHitTesting(false)
        }
    }

    private var exclusiveEventsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionHeader(title: "Exclusive Tonight", icon: "sparkles", color: .pink)
            ForEach(appState.exclusiveExternalEventFeed.prefix(3)) { event in
                Button { selectedExternalEvent = event } label: {
                    ExternalEventCardView(
                        event: event,
                        imageRefreshNonce: appState.externalEventImageRefreshNonce
                    )
                        .equatable()
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var browseChipBar: some View {
        ScrollView(.horizontal) {
            HStack(spacing: 8) {
                ForEach(BrowseChip.allCases) { chip in
                    Button {
                        withAnimation(.snappy) {
                            if chip == .all {
                                browseChips = [.all]
                            } else {
                                browseChips.remove(.all)
                                if browseChips.contains(chip) {
                                    browseChips.remove(chip)
                                    if browseChips.isEmpty { browseChips = [.all] }
                                } else {
                                    browseChips.insert(chip)
                                }
                            }
                        }
                    } label: {
                        HStack(spacing: 5) {
                            if let icon = chip.icon {
                                Image(systemName: icon)
                                    .font(.system(size: 10, weight: .bold))
                            }
                            Text(chip.rawValue)
                                .font(.system(size: 12, weight: .semibold))
                        }
                        .foregroundStyle(browseChips.contains(chip) ? .white : .white.opacity(0.45))
                        .padding(.horizontal, 14)
                        .padding(.vertical, 8)
                        .background {
                            if browseChips.contains(chip) {
                                Capsule().fill(chipColor(chip).opacity(0.25))
                                    .overlay(Capsule().strokeBorder(chipColor(chip).opacity(0.4), lineWidth: 1))
                            } else {
                                Capsule().fill(questPillSurface.opacity(0.4))
                                    .overlay(Capsule().strokeBorder(.white.opacity(0.07), lineWidth: 1))
                            }
                        }
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .contentMargins(.horizontal, 0)
        .scrollIndicators(.hidden)
    }

    private func chipColor(_ chip: BrowseChip) -> Color {
        switch chip {
        case .all: .white.opacity(0.5)
        case .verified: .green
        case .open: .indigo
        case .warrior: .red
        case .explorer: .teal
        case .mind: .purple
        case .nearby: .green
        case .easy: .green
        case .medium: .orange
        case .hard: .red
        case .quick: .blue
        }
    }

    private var browseCatalog: some View {
        let quests = browseCatalogQuests
        let families = browseCatalogFamilies
        let visibleQuestCount = min(browseVisibleItemCount, quests.count)
        let visibleFamilyCount = min(browseVisibleItemCount, families.count)
        return Group {
            if isPreparingBrowseCatalog && quests.isEmpty {
                placeholderCard("Loading quest catalog...", icon: "square.grid.2x2")
            } else if quests.isEmpty {
                emptyState("No quests match your filters", icon: "magnifyingglass")
            } else if !searchText.isEmpty {
                ForEach(Array(quests.prefix(visibleQuestCount).enumerated()), id: \.element.id) { index, quest in
                    questRow(quest: quest)
                        .task {
                            await loadMoreBrowseResultsIfNeeded(
                                visibleIndex: index,
                                totalCount: quests.count
                            )
                        }
                }
            } else {
                ForEach(Array(families.prefix(visibleFamilyCount).enumerated()), id: \.element.id) { index, family in
                    QuestFamilyCardView(family: family) {
                        if family.isLadder {
                            selectedFamily = family
                        } else {
                            selectedQuest = family.recommendedQuest
                        }
                    }
                    .task {
                        await loadMoreBrowseResultsIfNeeded(
                            visibleIndex: index,
                            totalCount: families.count
                        )
                    }
                }
            }

            if !appState.customQuests.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("MY CUSTOM QUESTS")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.indigo)
                        Spacer()
                        Button { showMyQuests = true } label: {
                            Text("See All")
                                .font(.caption.weight(.medium))
                        }
                    }
                    ForEach(appState.customQuests.prefix(3)) { custom in
                        Button { selectedCustomQuest = custom } label: {
                            customQuestRow(custom)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.top, 8)
            }

            createCustomQuestPrompt
        }
    }

    private static func filteredBrowseQuests(
        from sourceQuests: [Quest],
        chips: Set<BrowseChip>,
        searchText: String
    ) -> [Quest] {
        var quests = sourceQuests

        if !chips.contains(.all) {
            if chips.contains(.verified) || chips.contains(.open) {
                let types: Set<QuestType> = {
                    var t = Set<QuestType>()
                    if chips.contains(.verified) { t.insert(.verified) }
                    if chips.contains(.open) { t.insert(.open) }
                    return t
                }()
                quests = quests.filter { types.contains($0.type) }
            }

            if chips.contains(.warrior) || chips.contains(.explorer) || chips.contains(.mind) {
                let paths: Set<QuestPath> = {
                    var p = Set<QuestPath>()
                    if chips.contains(.warrior) { p.insert(.warrior) }
                    if chips.contains(.explorer) { p.insert(.explorer) }
                    if chips.contains(.mind) { p.insert(.mind) }
                    return p
                }()
                quests = quests.filter { paths.contains($0.path) }
            }

            if chips.contains(.nearby) {
                quests = quests.filter { $0.isLocationDependent }
            }

            if chips.contains(.easy) || chips.contains(.medium) || chips.contains(.hard) {
                let diffs: Set<String> = {
                    var d = Set<String>()
                    if chips.contains(.easy) { d.insert(QuestDifficulty.easy.rawValue) }
                    if chips.contains(.medium) { d.insert(QuestDifficulty.medium.rawValue) }
                    if chips.contains(.hard) {
                        d.insert(QuestDifficulty.hard.rawValue)
                        d.insert(QuestDifficulty.expert.rawValue)
                    }
                    return d
                }()
                quests = quests.filter { diffs.contains($0.difficulty.rawValue) }
            }

            if chips.contains(.quick) {
                quests = quests.filter { $0.minCompletionMinutes <= 15 }
            }
        }

        if !searchText.isEmpty {
            quests = quests.filter {
                $0.title.localizedStandardContains(searchText)
                    || $0.description.localizedStandardContains(searchText)
            }
        }

        return quests
    }

    private var browseCatalogDependencyKey: String {
        let chipKey = browseChips.map(\.rawValue).sorted().joined(separator: ",")
        let skillKey = appState.profile.selectedSkills.map(\.rawValue).sorted().joined(separator: ",")
        let interestKey = appState.profile.selectedInterests.map(\.rawValue).sorted().joined(separator: ",")
        let completionKey = "\(appState.questCompletionCounts.count)-\(appState.completedHistory.count)-\(appState.activeJourneys.count)"
        let locationKey = appState.externalEventSearchLocation?.displayName ?? ""

        return [
            String(appState.allQuests.count),
            chipKey,
            searchText,
            skillKey,
            interestKey,
            completionKey,
            String(appState.profile.currentStreak),
            String(appState.profile.level),
            String(appState.profile.verifiedCount),
            locationKey
        ].joined(separator: "|")
    }

    private var forYouDependencyKey: String {
        let completionKey = appState.questCompletionCounts
            .sorted { $0.key < $1.key }
            .map { "\($0.key):\($0.value)" }
            .joined(separator: ",")
        let activeKey = appState.activeInstances
            .filter { $0.state.isActive }
            .map { $0.quest.id }
            .sorted()
            .joined(separator: ",")
        let recentKey = appState.completedHistory
            .prefix(15)
            .map(\.questTitle)
            .joined(separator: ",")
        let skillKey = appState.profile.selectedSkills.map(\.rawValue).sorted().joined(separator: ",")
        let interestKey = appState.profile.selectedInterests.map(\.rawValue).sorted().joined(separator: ",")
        let locationKey = appState.externalEventSearchLocation?.displayName ?? ""
        let components: [String] = [
            String(appState.allQuests.count),
            searchText,
            completionKey,
            activeKey,
            recentKey,
            skillKey,
            interestKey,
            String(appState.profile.currentStreak),
            String(appState.profile.level),
            String(appState.profile.verifiedCount),
            String(appState.profile.warriorRank),
            String(appState.profile.explorerRank),
            String(appState.profile.mindRank),
            String(appState.activeJourneys.count),
            appState.hasTagsConfigured ? "1" : "0",
            appState.onboardingData.isComplete ? "1" : "0",
            locationKey
        ]
        return components.joined(separator: "|")
    }

    private func scheduleBrowseCatalogRefresh() {
        let nextSignature = browseCatalogDependencyKey
        guard nextSignature != browseCatalogSignature || browseCatalogQuests.isEmpty else { return }

        let sourceQuests = appState.allQuests
        let chips = browseChips
        let currentSearchText = searchText
        let context = playerContext

        browseCatalogSignature = nextSignature
        browseCatalogGeneration += 1
        let generation = browseCatalogGeneration
        isPreparingBrowseCatalog = true
        browseVisibleItemCount = 12

        DispatchQueue.global(qos: .userInitiated).async {
            let filteredQuests = Self.filteredBrowseQuests(
                from: sourceQuests,
                chips: chips,
                searchText: currentSearchText
            )
            let families = currentSearchText.isEmpty
                ? QuestFamilyService.buildFamilies(from: filteredQuests, playerContext: context)
                : []

            DispatchQueue.main.async {
                guard browseCatalogGeneration == generation else { return }
                browseCatalogQuests = filteredQuests
                browseCatalogFamilies = families
                isPreparingBrowseCatalog = false
            }
        }
    }

    private static func questMatchesSearch(_ quest: Quest, searchText: String) -> Bool {
        guard !searchText.isEmpty else { return true }
        return quest.title.localizedStandardContains(searchText)
            || quest.description.localizedStandardContains(searchText)
    }

    private static func journeyMatchesSearch(_ journey: Journey, searchText: String) -> Bool {
        guard !searchText.isEmpty else { return true }
        return journey.name.localizedStandardContains(searchText)
    }

    private static func templateMatchesSearch(_ template: JourneyTemplate, searchText: String) -> Bool {
        guard !searchText.isEmpty else { return true }
        return template.title.localizedStandardContains(searchText)
            || template.description.localizedStandardContains(searchText)
            || template.authorUsername.localizedStandardContains(searchText)
    }

    private static func familyMatchesSearch(_ family: QuestFamily, searchText: String) -> Bool {
        guard !searchText.isEmpty else { return true }
        return family.name.localizedStandardContains(searchText)
            || questMatchesSearch(family.recommendedQuest, searchText: searchText)
    }

    private static func eventMatchesSearch(_ event: ExternalEvent, searchText: String) -> Bool {
        guard !searchText.isEmpty else { return true }
        let fields = [
            event.title,
            event.shortDescription,
            event.fullDescription,
            event.category,
            event.subcategory,
            event.venueName,
            event.city,
            event.state,
            event.addressLine1
        ]
        return fields.compactMap { $0 }.contains { $0.localizedStandardContains(searchText) }
    }

    private static func buildForYouSnapshot(
        from sourceQuests: [Quest],
        searchText: String,
        context: PersonalizationEngine.PlayerContext
    ) -> ForYouSnapshot {
        let eligible = sourceQuests.filter { $0.type != .master }
        let featuredPool = eligible.filter { questMatchesSearch($0, searchText: searchText) }
        let featuredQuest = featuredPool.isEmpty
            ? nil
            : PersonalizationEngine.featuredQuest(from: featuredPool, context: context)

        let featuredQuestID = featuredQuest?.id
        let featuredThemeKey = featuredQuest.map { PersonalizationEngine.contentThemeKey(for: $0) }
        let todaysPool = eligible.filter { quest in
            guard quest.id != featuredQuestID else { return false }
            guard let featuredThemeKey else { return true }
            return PersonalizationEngine.contentThemeKey(for: quest) != featuredThemeKey
        }
        let rankedTodaysPicks = PersonalizationEngine.todaysPicks(from: todaysPool, context: context, count: 3)
        let todaysPicks = searchText.isEmpty
            ? rankedTodaysPicks
            : rankedTodaysPicks.filter { questMatchesSearch($0, searchText: searchText) }

        var usedThemeKeys = Set(todaysPicks.map { PersonalizationEngine.contentThemeKey(for: $0) })
        if let featuredQuest {
            usedThemeKeys.insert(PersonalizationEngine.contentThemeKey(for: featuredQuest))
        }

        let excludedQuestIDs = Set(todaysPicks.map(\.id) + [featuredQuestID].compactMap { $0 })
        let strictWeeklyPool = sourceQuests.filter {
            !$0.id.isEmpty
                && !excludedQuestIDs.contains($0.id)
                && !usedThemeKeys.contains(PersonalizationEngine.contentThemeKey(for: $0))
                && questMatchesSearch($0, searchText: searchText)
        }
        let weeklyChallenge = PersonalizationEngine.weeklyChallenge(from: strictWeeklyPool, context: context)

        let families = QuestFamilyService.buildFamilies(from: eligible, playerContext: context)
        let diversifiedFamilies = PersonalizationEngine.diversifyFamilyFeed(families, maxCount: 6)
        let allUsedThemeKeys = usedThemeKeys.union(
            weeklyChallenge.map { [PersonalizationEngine.contentThemeKey(for: $0)] } ?? []
        )
        let filteredFamilies = diversifiedFamilies.filter {
            !allUsedThemeKeys.contains(PersonalizationEngine.contentThemeKey(for: $0.recommendedQuest))
                && familyMatchesSearch($0, searchText: searchText)
        }

        return ForYouSnapshot(
            featuredQuest: featuredQuest,
            todaysPicks: todaysPicks,
            weeklyChallenge: weeklyChallenge,
            recommendedFamilies: filteredFamilies
        )
    }

    private func scheduleForYouSnapshotRefresh() {
        guard appState.hasTagsConfigured || appState.onboardingData.isComplete else {
            preparedForYouSnapshot = nil
            isPreparingForYouSnapshot = false
            return
        }

        let nextSignature = forYouDependencyKey
        guard nextSignature != forYouSnapshotSignature || preparedForYouSnapshot == nil else { return }

        let sourceQuests = appState.allQuests
        let currentSearchText = searchText
        let context = playerContext
        let hadPreparedSnapshot = preparedForYouSnapshot != nil

        forYouSnapshotSignature = nextSignature
        forYouSnapshotGeneration += 1
        let generation = forYouSnapshotGeneration
        if !hadPreparedSnapshot {
            isPreparingForYouSnapshot = true
        }

        DispatchQueue.global(qos: .userInitiated).async {
            let snapshot = Self.buildForYouSnapshot(
                from: sourceQuests,
                searchText: currentSearchText,
                context: context
            )

            DispatchQueue.main.async {
                guard forYouSnapshotGeneration == generation else { return }
                preparedForYouSnapshot = snapshot
                isPreparingForYouSnapshot = false
            }
        }
    }

    @MainActor
    private func loadMoreBrowseResultsIfNeeded(visibleIndex: Int, totalCount: Int) async {
        guard visibleIndex >= browseVisibleItemCount - 3 else { return }
        guard browseVisibleItemCount < totalCount else { return }
        browseVisibleItemCount = min(totalCount, browseVisibleItemCount + 12)
    }

    private func scheduleExternalEventWarmup(delayNanoseconds: UInt64) {
        deferredEventLoadTask?.cancel()
        deferredEventLoadTask = Task {
            if delayNanoseconds > 0 {
                try? await Task.sleep(nanoseconds: delayNanoseconds)
            }
            guard !Task.isCancelled else { return }
            await appState.ensureExternalEventsLoaded(forceRefresh: false)
        }
    }

    private func handlePullOffsetChange(_ offset: CGFloat) {
        guard supportsPullToRefresh else {
            pullRefreshHasTriggered = false
            isPullRefreshHintVisible = false
            isPullRefreshArmed = false
            return
        }

        let clampedOffset = max(0, offset)
        let shouldShowHint = clampedOffset >= 16
        let shouldArm = clampedOffset >= 84

        if isPullRefreshHintVisible != shouldShowHint {
            isPullRefreshHintVisible = shouldShowHint
        }
        if isPullRefreshArmed != shouldArm {
            isPullRefreshArmed = shouldArm
        }

        guard !isPullRefreshing else { return }

        if clampedOffset >= 84, !pullRefreshHasTriggered {
            pullRefreshHasTriggered = true
            Task {
                await runPullToRefresh()
            }
        } else if clampedOffset <= 10 {
            pullRefreshHasTriggered = false
        }
    }

    @MainActor
    private func runPullToRefresh() async {
        guard supportsPullToRefresh else { return }
        guard !isPullRefreshing else { return }
        isPullRefreshing = true
        await appState.refreshExternalEvents(forceRefresh: true)
        try? await Task.sleep(for: .milliseconds(250))
        isPullRefreshing = false
        isPullRefreshHintVisible = false
        isPullRefreshArmed = false
    }

    // MARK: - Shared Components

    private func sectionHeader(title: String, icon: String, color: Color) -> some View {
        HStack(spacing: 7) {
            Image(systemName: icon)
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(color)
            Text(title)
                .font(.subheadline.weight(.bold))
                .foregroundStyle(.white.opacity(0.85))
            Spacer()
        }
    }

    private func placeholderCard(_ message: String, icon: String) -> some View {
        HStack(spacing: 12) {
            if message.localizedCaseInsensitiveContains("pulling")
                || message.localizedCaseInsensitiveContains("loading") {
                ProgressView()
                    .tint(.orange)
            } else {
                Image(systemName: icon)
                    .font(.title3)
                    .foregroundStyle(.white.opacity(0.2))
            }
            Text(message)
                .font(.subheadline)
                .foregroundStyle(.white.opacity(0.35))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(questCardSurface.opacity(0.4), in: .rect(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(.white.opacity(0.05), lineWidth: 1))
    }

    private var liveEventsUpdatingBadge: some View {
        HStack(spacing: 8) {
            ProgressView()
                .tint(.white)
                .scaleEffect(0.85)
            Text("Updating")
                .font(.caption2.weight(.bold))
                .foregroundStyle(.white.opacity(0.92))
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(Color.black.opacity(0.38), in: Capsule())
        .overlay(Capsule().strokeBorder(.white.opacity(0.1), lineWidth: 1))
        .allowsHitTesting(false)
    }

    private func eventSectionHeader(title: String, subtitle: String?) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(title)
                .font(.caption.weight(.heavy))
                .foregroundStyle(.white.opacity(0.88))
                .textCase(.uppercase)

            if let subtitle, !subtitle.isEmpty {
                Text(subtitle)
                    .font(.caption2.weight(.medium))
                    .foregroundStyle(.white.opacity(0.42))
            }

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 2)
    }

    private func buildEventSections(from events: [ExternalEvent]) -> [EventFeedSectionData] {
        guard !events.isEmpty else { return [] }

        var orderedKeys: [String] = []
        var buckets: [String: EventFeedSectionData] = [:]

        for (index, event) in events.enumerated() {
            let descriptor = eventSectionDescriptor(for: event)
            let item = EventFeedSectionItem(index: index, event: event)

            if var existing = buckets[descriptor.id] {
                existing = EventFeedSectionData(
                    id: existing.id,
                    title: existing.title,
                    subtitle: existing.subtitle,
                    items: existing.items + [item]
                )
                buckets[descriptor.id] = existing
            } else {
                orderedKeys.append(descriptor.id)
                buckets[descriptor.id] = EventFeedSectionData(
                    id: descriptor.id,
                    title: descriptor.title,
                    subtitle: descriptor.subtitle,
                    items: [item]
                )
            }
        }

        return orderedKeys.compactMap { buckets[$0] }
    }

    private func eventSectionDescriptor(for event: ExternalEvent) -> (id: String, title: String, subtitle: String?) {
        let calendar = Calendar.current
        let now = Date()

        guard let startAtUTC = event.startAtUTC else {
            return ("radar", "On Your Radar", "Open venues and unscheduled finds")
        }

        if calendar.isDateInToday(startAtUTC) {
            let hour = calendar.component(.hour, from: startAtUTC)
            if hour >= 17 || event.eventType == .partyNightlife || event.recordKind == .venueNight {
                return ("tonight", "Tonight", "Best near-term picks")
            }
            return ("today", "Today", "Happening soon")
        }

        if calendar.isDateInTomorrow(startAtUTC) {
            return ("tomorrow", "Tomorrow", "Worth planning ahead")
        }

        if let weekOut = calendar.date(byAdding: .day, value: 7, to: now),
           startAtUTC < weekOut {
            return ("this_week", "This Week", "Coming up next")
        }

        return ("later", "Later", "Still worth saving")
    }

    private var eventsStatusLine: String {
        if let fetchedAt = appState.externalEventsLastFetchedAt {
            let area = appState.externalEventSearchLocation?.displayName ?? "Nearby"
            return "\(area) • updated \(relativeTimestamp(from: fetchedAt))"
        }
        if appState.isRefreshingExternalEvents {
            return "Loading live events in \(appState.externalEventSearchLocation?.displayName ?? "your area")"
        }
        return "Live in \(appState.externalEventSearchLocation?.displayName ?? "your area")"
    }

    private var visibleEventFeed: [ExternalEvent] {
        let shouldUseExpandedBase =
            selectedEventsCategory != .all
            || !selectedEventFilterChips.isEmpty
            || !searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        let base = shouldUseExpandedBase
            ? appState.eventsTabExpandedExternalEventFeed
            : appState.eventsTabExternalEventFeed
        let dedupedBase: [ExternalEvent]
        if selectedEventsCategory == .all && selectedEventFilterChips.isEmpty {
            let exclusiveIDs = Set(appState.exclusiveExternalEventFeed.prefix(3).map(\.id))
            dedupedBase = base.filter { !exclusiveIDs.contains($0.id) }
        } else {
            dedupedBase = base
        }

        let filtered = dedupedBase.filter { event in
            matchesEventsCategory(event)
                && matchesSelectedEventFilters(event)
                && matchesImplicitEventTimingWindow(event)
                && Self.eventMatchesSearch(event, searchText: searchText)
        }
        return staggerSimilarEvents(in: filtered)
    }

    private var visibleEventEmptyMessage: String {
        let area = appState.externalEventSearchLocation?.displayName ?? "your area"
        if !searchText.isEmpty {
            return "No events match your search near \(area)."
        }

        let categoryLabel = selectedEventsCategory == .all
            ? "events"
            : selectedEventsCategory.rawValue.lowercased()
        if !selectedEventFilterChips.isEmpty {
            return "No \(categoryLabel) match your filters near \(area) right now. Pull to refresh and try again."
        }
        return "No \(categoryLabel) are surfacing near \(area) right now. Pull to refresh and try again."
    }

    private var eventSortMenuOptions: [ExternalEventSortOption] {
        [.recommended, .soonest, .closest, .hottest]
    }

    private func eventSortDisplayName(_ option: ExternalEventSortOption) -> String {
        switch option {
        case .recommended: "Recommended"
        case .soonest: "Soonest"
        case .closest: "Closest"
        case .hottest: "Trending"
        case .weekend: "This Weekend"
        }
    }

    @MainActor
    private func selectEventsCategory(_ category: EventsCategory) {
        guard selectedEventsCategory != category else { return }
        selectedEventsCategory = category
        appState.setExternalEventFilterOption(category.baseFilterOption)
        eventVisibleItemCount = 10
    }

    private func toggleEventFilterChip(_ chip: EventFilterChip) {
        withAnimation(.snappy) {
            if selectedEventFilterChips.contains(chip) {
                selectedEventFilterChips.remove(chip)
            } else {
                selectedEventFilterChips.insert(chip)
            }
            eventVisibleItemCount = 10
        }
    }

    private func matchesEventsCategory(_ event: ExternalEvent) -> Bool {
        switch selectedEventsCategory {
        case .all:
            return true
        case .concerts:
            return event.eventType == .concert
        case .sports:
            return event.eventType == .sportsEvent
        case .comedy:
            return eventLooksLikeComedy(event)
        case .nightlife:
            return event.eventType == .partyNightlife || event.recordKind == .venueNight
        case .community:
            return eventLooksLikeCommunity(event)
        case .races:
            return event.eventType == .groupRun
                || event.eventType == .race5k
                || event.eventType == .race10k
                || event.eventType == .raceHalfMarathon
                || event.eventType == .raceMarathon
        }
    }

    private func matchesSelectedEventFilters(_ event: ExternalEvent) -> Bool {
        selectedEventFilterChips.allSatisfy { matchesEventFilterChip($0, event: event) }
    }

    private func matchesImplicitEventTimingWindow(_ event: ExternalEvent) -> Bool {
        guard searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return true }
        guard !selectedEventFilterChips.contains(where: isTimingEventFilterChip(_:)) else { return true }

        guard let startAtUTC = event.startAtUTC else {
            return selectedEventsCategory == .nightlife
        }

        guard startAtUTC >= Date() else { return false }
        guard let cutoff = Calendar.current.date(byAdding: .day, value: defaultEventTimingWindowDays, to: Date()) else {
            return true
        }

        return startAtUTC <= cutoff
    }

    private var defaultEventTimingWindowDays: Int {
        switch selectedEventsCategory {
        case .nightlife:
            return 21
        case .community, .comedy:
            return 45
        case .all:
            return 30
        case .concerts, .sports, .races:
            return 90
        }
    }

    private func isTimingEventFilterChip(_ chip: EventFilterChip) -> Bool {
        switch chip {
        case .tonight, .tomorrow, .thisWeek, .weekend:
            return true
        default:
            return false
        }
    }

    private func staggerSimilarEvents(in events: [ExternalEvent]) -> [ExternalEvent] {
        guard events.count > 2 else { return events }

        var pending = events
        var result: [ExternalEvent] = []

        while !pending.isEmpty {
            guard let previous = result.last else {
                result.append(pending.removeFirst())
                continue
            }

            let nextIndex = pending.firstIndex { candidate in
                !shouldSeparateAdjacentEvents(previous, candidate)
            } ?? 0

            result.append(pending.remove(at: nextIndex))
        }

        return result
    }

    private func shouldSeparateAdjacentEvents(_ lhs: ExternalEvent, _ rhs: ExternalEvent) -> Bool {
        let leftKey = adjacentSimilarityKey(for: lhs)
        guard !leftKey.isEmpty else { return false }
        return leftKey == adjacentSimilarityKey(for: rhs)
    }

    private func adjacentSimilarityKey(for event: ExternalEvent) -> String {
        let titleKey = ExternalEventSupport.dedupeTitleFingerprint(
            event.title,
            eventType: event.eventType,
            venueName: event.venueName
        )
        let venueKey = ExternalEventSupport.normalizeToken(event.venueName ?? event.addressLine1 ?? event.city)
        guard !titleKey.isEmpty else { return "" }
        return "\(event.eventType.rawValue)::\(titleKey)::\(venueKey)"
    }

    private func matchesEventFilterChip(_ chip: EventFilterChip, event: ExternalEvent) -> Bool {
        switch chip {
        case .tonight:
            return eventMatchesTiming(event, target: .tonight)
        case .tomorrow:
            return eventMatchesTiming(event, target: .tomorrow)
        case .thisWeek:
            return eventMatchesTiming(event, target: .thisWeek)
        case .weekend:
            return eventMatchesTiming(event, target: .weekend)
        case .exclusive:
            return ExternalEventSupport.isExclusiveEvent(event)
        case .free:
            return eventLooksFree(event)
        case .nearby:
            return eventDistanceMiles(event).map { $0 <= 10 } ?? false
        case .underThirty:
            return eventPriceCeiling(event).map { $0 <= 30 } ?? false
        case .sellingFast:
            return event.urgencyBadge != nil
        case .hasPhotos:
            return !ExternalEventSupport.preferredImageURLs(for: event, limit: 1).isEmpty
        case .topRated:
            return (event.venueRating ?? 0) >= 4.5
        case .indoor:
            return eventMatchesEnvironment(event, tokens: ["arena", "auditorium", "club", "comedy club", "dome", "hall", "hotel", "indoor", "lounge", "theater", "theatre", "venue"])
        case .outdoor:
            return eventMatchesEnvironment(event, tokens: ["amphitheater", "beach", "garden", "outdoor", "park", "patio", "plaza", "rooftop", "stadium", "trail"])
        case .twentyOnePlus:
            return (event.ageMinimum ?? 0) >= 21 || event.eventType == .partyNightlife
        case .walkable:
            return eventDistanceMiles(event).map { $0 <= 1.2 } ?? false
        case .verifiedVenue:
            return eventHasVerifiedVenueSignal(event)
        }
    }

    private enum EventTimingTarget {
        case tonight
        case tomorrow
        case thisWeek
        case weekend
    }

    private func eventMatchesTiming(_ event: ExternalEvent, target: EventTimingTarget) -> Bool {
        guard let startAtUTC = event.startAtUTC else { return false }
        let timeZone = TimeZone(identifier: event.timezone ?? "") ?? .current
        var calendar = Calendar.current
        calendar.timeZone = timeZone
        let now = Date()

        switch target {
        case .tonight:
            guard calendar.isDate(startAtUTC, inSameDayAs: now) else { return false }
            let hour = calendar.component(.hour, from: startAtUTC)
            return hour >= 17 || event.eventType == .partyNightlife || event.recordKind == .venueNight
        case .tomorrow:
            return calendar.isDateInTomorrow(startAtUTC)
        case .thisWeek:
            guard let weekOut = calendar.date(byAdding: .day, value: 7, to: now) else { return false }
            return startAtUTC >= now && startAtUTC < weekOut
        case .weekend:
            let weekday = calendar.component(.weekday, from: startAtUTC)
            let isWeekendDay = weekday == 6 || weekday == 7 || weekday == 1
            guard isWeekendDay else { return false }
            guard let tenDaysOut = calendar.date(byAdding: .day, value: 10, to: now) else { return false }
            return startAtUTC >= now && startAtUTC < tenDaysOut
        }
    }

    private func eventLooksFree(_ event: ExternalEvent) -> Bool {
        if let max = event.priceMax, max <= 0 { return true }
        if let min = event.priceMin, min <= 0, event.priceMax == nil { return true }
        let haystack = eventFilterHaystack(for: event)
        return haystack.contains("free admission")
            || haystack.contains("free entry")
            || haystack.contains("free event")
            || haystack.contains("free show")
            || haystack.contains("no cover")
    }

    private func eventDistanceMiles(_ event: ExternalEvent) -> Double? {
        if let miles = event.distanceFromUser {
            return miles
        }
        guard let value = event.distanceValue else { return nil }
        switch (event.distanceUnit ?? "").lowercased() {
        case "mi", "mile", "miles":
            return value
        case "ft", "feet":
            return value / 5280
        case "km", "kilometer", "kilometers":
            return value * 0.621371
        case "m", "meter", "meters":
            return value / 1609.34
        default:
            return value
        }
    }

    private func eventPriceCeiling(_ event: ExternalEvent) -> Double? {
        if let max = event.priceMax {
            return max
        }
        return event.priceMin
    }

    private func eventMatchesEnvironment(_ event: ExternalEvent, tokens: [String]) -> Bool {
        let haystack = eventFilterHaystack(for: event)
        return tokens.contains(where: haystack.contains)
    }

    private func eventHasVerifiedVenueSignal(_ event: ExternalEvent) -> Bool {
        if event.organizerVerified == true { return true }
        if let sourceConfidence = event.sourceConfidence, sourceConfidence >= 0.8 { return true }
        if event.mergedSources.contains(.appleMaps) || event.mergedSources.contains(.googlePlaces) || event.mergedSources.contains(.venueWebsite) {
            return true
        }
        return (event.venueRating ?? 0) >= 4.2
    }

    private func eventLooksLikeComedy(_ event: ExternalEvent) -> Bool {
        if event.eventType == .partyNightlife || event.recordKind == .venueNight {
            return false
        }
        let haystack = comedyClassificationHaystack(for: event)
        return haystack.contains("comedy")
            || haystack.contains("stand-up")
            || haystack.contains("standup")
            || haystack.contains("comic")
            || haystack.contains("improv")
            || haystack.contains("open mic")
            || haystack.contains("laugh factory")
            || haystack.contains("comedy store")
    }

    private func eventLooksLikeCommunity(_ event: ExternalEvent) -> Bool {
        switch event.eventType {
        case .partyNightlife, .concert, .sportsEvent, .groupRun, .race5k, .race10k, .raceHalfMarathon, .raceMarathon:
            return false
        case .socialCommunityEvent:
            return true
        case .weekendActivity, .otherLiveEvent:
            break
        }

        if eventLooksLikeComedy(event) {
            return false
        }

        let haystack = eventFilterHaystack(for: event)
        return haystack.contains("community")
            || haystack.contains("street fair")
            || haystack.contains("farmers market")
            || haystack.contains("farmer's market")
            || haystack.contains("night market")
            || haystack.contains("market")
            || haystack.contains("festival")
            || haystack.contains("fair")
            || haystack.contains("expo")
            || haystack.contains("pop up")
            || haystack.contains("charity")
            || haystack.contains("fundraiser")
            || haystack.contains("volunteer")
            || haystack.contains("networking")
            || haystack.contains("family day")
    }

    private func comedyClassificationHaystack(for event: ExternalEvent) -> String {
        var components: [String] = [event.title]
        if let value = event.shortDescription { components.append(value) }
        if let value = event.category { components.append(value) }
        if let value = event.subcategory { components.append(value) }
        if let value = event.venueName { components.append(value) }
        if !event.tags.isEmpty { components.append(event.tags.joined(separator: " ")) }

        return components
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .map { $0.lowercased() }
            .joined(separator: " ")
    }

    private func eventFilterHaystack(for event: ExternalEvent) -> String {
        var components: [String] = []
        components.append(event.title)
        if let value = event.shortDescription { components.append(value) }
        if let value = event.fullDescription { components.append(value) }
        if let value = event.category { components.append(value) }
        if let value = event.subcategory { components.append(value) }
        if let value = event.venueName { components.append(value) }
        if let value = event.addressLine1 { components.append(value) }
        if let value = event.city { components.append(value) }
        if let value = event.state { components.append(value) }
        if let value = event.neighborhood { components.append(value) }
        if let value = event.socialProofLabel { components.append(value) }
        if let value = event.entryPolicySummary { components.append(value) }
        if let value = event.doorPolicyText { components.append(value) }
        if let value = event.dressCodeText { components.append(value) }
        if let value = event.raceType { components.append(value) }
        if !event.tags.isEmpty { components.append(event.tags.joined(separator: " ")) }

        return components
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .map { $0.lowercased() }
            .joined(separator: " ")
    }

    private var eventLoadingCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 10) {
                ProgressView()
                    .tint(.orange)
                VStack(alignment: .leading, spacing: 4) {
                    Text(eventLoadingTitle)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.white)
                    Text(eventLoadingSubtitle)
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.58))
                }
            }

            VStack(alignment: .leading, spacing: 8) {
                ForEach(eventLoadingSteps, id: \.self) { step in
                    HStack(spacing: 8) {
                        Circle()
                            .fill(Color.orange.opacity(0.75))
                            .frame(width: 6, height: 6)
                        Text(step)
                            .font(.caption.weight(.medium))
                            .foregroundStyle(.white.opacity(0.72))
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(questCardSurface.opacity(0.46), in: .rect(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(.white.opacity(0.06), lineWidth: 1))
    }

    private var eventLoadingTitle: String {
        let area = appState.externalEventSearchLocation?.displayName ?? "your area"
        switch selectedEventsCategory {
        case .nightlife:
            return "Scanning nightlife near \(area)"
        case .sports:
            return "Checking major games near \(area)"
        case .concerts:
            return "Checking concerts near \(area)"
        case .races:
            return "Checking local races near \(area)"
        case .comedy:
            return "Checking comedy shows near \(area)"
        case .community:
            return "Checking community events near \(area)"
        case .all:
            return "Loading live events near \(area)"
        }
    }

    private var eventLoadingSubtitle: String {
        switch selectedEventsCategory {
        case .nightlife:
            return "Pulling venue calendars, reservation links, and local nightlife data."
        case .sports:
            return "Pulling arena schedules and ticketed sports inventory."
        case .concerts:
            return "Pulling mainstream ticket inventory and nearby venue data."
        case .races:
            return "Pulling local races and group runs near you."
        case .comedy:
            return "Pulling stand-up shows and local comedy listings."
        case .community:
            return "Pulling festivals, markets, fairs, and neighborhood happenings."
        case .all:
            return "Combining mainstream events, local happenings, and venue context."
        }
    }

    private var eventLoadingSteps: [String] {
        switch selectedEventsCategory {
        case .nightlife:
            return [
                "Checking premium nightlife venues and club calendars",
                "Matching reservation, guest-list, and venue details",
                "Ranking what feels hottest nearby right now"
            ]
        case .sports:
            return [
                "Checking arena and stadium inventory",
                "Merging live event listings across ticket sources",
                "Ranking the biggest nearby games first"
            ]
        case .concerts:
            return [
                "Checking headline venues and concert listings",
                "Matching artist events to real venue details",
                "Ranking the strongest nearby shows"
            ]
        case .races:
            return [
                "Checking race calendars and local runs",
                "Matching dates, locations, and registration status",
                "Ranking the best nearby runs"
            ]
        case .comedy:
            return [
                "Checking stand-up and club listings",
                "Matching showtimes, venues, and ticket links",
                "Ranking the strongest local comedy picks"
            ]
        case .community:
            return [
                "Checking markets, fairs, and local happenings",
                "Matching dates, venues, and event details",
                "Ranking what is most worth doing nearby"
            ]
        case .all:
            return [
                "Checking live events across the area",
                "Matching venues, addresses, and source details",
                "Ranking the best options for your feed"
            ]
        }
    }

    private func relativeTimestamp(from date: Date) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .short
        return formatter.localizedString(for: date, relativeTo: Date())
    }

    private func questRow(quest: Quest) -> some View {
        let saved = appState.isQuestSaved(quest.id)
        return ZStack(alignment: .topTrailing) {
            Button { selectedQuest = quest } label: {
                QuestCardView(quest: quest, showCompletionCount: true)
            }
            .buttonStyle(.plain)

            Button {
                withAnimation(.spring(response: 0.3, dampingFraction: 0.6)) {
                    appState.toggleSavedQuest(quest.id)
                }
            } label: {
                Image(systemName: saved ? "heart.fill" : "heart")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(saved ? .red : .white.opacity(0.6))
                    .padding(10)
                    .background(.ultraThinMaterial, in: Circle())
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .padding(8)
            .sensoryFeedback(.impact(weight: .light), trigger: saved)
        }
    }

    private func customQuestRow(_ quest: CustomQuest) -> some View {
        let pathColor = PathColorHelper.color(for: quest.path)
        return HStack(spacing: 12) {
            Image(systemName: quest.path.iconName)
                .font(.caption)
                .foregroundStyle(pathColor)
                .frame(width: 36, height: 36)
                .background(pathColor.opacity(0.12), in: .rect(cornerRadius: 10))

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(quest.title)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.white)
                        .lineLimit(1)
                    HStack(spacing: 3) {
                        Image(systemName: "person.fill")
                            .font(.system(size: 8))
                        Text("Custom")
                            .font(.system(size: 10, weight: .bold))
                    }
                    .foregroundStyle(.indigo)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(.indigo.opacity(0.12), in: Capsule())
                }
                HStack(spacing: 8) {
                    Label("\(quest.toQuest().xpReward) XP", systemImage: "bolt.fill")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.orange)
                    DifficultyBadge(difficulty: quest.difficulty)
                }
            }

            Spacer()

            Image(systemName: "chevron.right")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.white.opacity(0.3))
        }
        .padding(12)
        .background(questCardSurface.opacity(0.7), in: .rect(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(.white.opacity(0.06), lineWidth: 1))
    }

    private var createCustomQuestPrompt: some View {
        Button { showCreateCustomQuest = true } label: {
            HStack(spacing: 10) {
                Image(systemName: "plus.circle.fill")
                    .font(.title3)
                    .foregroundStyle(.indigo)
                Text("Create Custom Side Quest")
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.white.opacity(0.7))
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.white.opacity(0.3))
            }
            .padding(12)
            .background(questCardSurface.opacity(0.6), in: .rect(cornerRadius: 12))
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .strokeBorder(.indigo.opacity(0.2), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .padding(.bottom, 4)
    }

    private func emptyState(_ message: String, icon: String) -> some View {
        VStack(spacing: 8) {
            Image(systemName: icon)
                .font(.largeTitle)
                .foregroundStyle(.white.opacity(0.2))
            Text(message)
                .font(.subheadline)
                .foregroundStyle(.white.opacity(0.4))
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 40)
    }
}

private struct QuestsPullOffsetPreferenceKey: PreferenceKey {
    static var defaultValue: CGFloat = 0

    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}

// MARK: - Keep MasterContractCard for other usages

struct MasterContractCard: View {
    let contract: MasterContract

    private var pathColor: Color {
        PathColorHelper.color(for: contract.path)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(contract.title)
                        .font(.title3.weight(.bold))
                        .foregroundStyle(.white)
                    Text(contract.subtitle)
                        .font(.subheadline)
                        .foregroundStyle(.white.opacity(0.5))
                }
                Spacer()
                if contract.isActive {
                    Text("Day \(contract.currentDay)/\(contract.durationDays)")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(pathColor, in: Capsule())
                } else if contract.isCompleted {
                    Image(systemName: "crown.fill")
                        .foregroundStyle(.yellow)
                        .font(.title2)
                } else {
                    Image(systemName: "chevron.right")
                        .foregroundStyle(.white.opacity(0.3))
                }
            }

            if contract.isActive {
                VStack(spacing: 6) {
                    ForEach(contract.requirements) { req in
                        HStack {
                            Text(req.title)
                                .font(.caption)
                                .foregroundStyle(.white.opacity(0.5))
                            Spacer()
                            Text("\(req.current)/\(req.target)")
                                .font(.caption.monospacedDigit().weight(.medium))
                                .foregroundStyle(.white.opacity(0.7))
                        }
                        ProgressView(value: req.progress)
                            .tint(pathColor)
                    }
                }
            }

            HStack(spacing: 16) {
                Label("\(contract.xpReward.formatted()) XP", systemImage: "bolt.fill")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.orange)
                Label("\(contract.diamondReward)", systemImage: "diamond.fill")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.cyan)
            }
        }
        .padding(16)
        .background {
            RoundedRectangle(cornerRadius: 16)
                .fill(.linearGradient(
                    colors: [pathColor.opacity(0.10), questCardSurface.opacity(0.7)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                ))
                .overlay(
                    RoundedRectangle(cornerRadius: 16)
                        .strokeBorder(.white.opacity(0.06), lineWidth: 1)
                )
        }
    }
}
