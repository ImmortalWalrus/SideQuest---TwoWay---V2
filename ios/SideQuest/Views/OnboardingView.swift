import SwiftUI

struct OnboardingView: View {
    let appState: AppState
    var isRefresh: Bool = false
    @State private var step: OnboardingStep = .createProfile
    @State private var showPermissions: Bool = false
    @State private var username: String = ""
    @State private var selectedAvatar: String = "figure.run"
    @State private var selectedSkills: Set<UserSkill> = []
    @State private var selectedInterests: Set<UserInterest> = []
    @State private var selectedGoals: Set<PlayerGoal> = []
    @State private var selectedEventTypes: Set<LiveEventPreference> = []
    @State private var selectedMusicGenres: Set<OnboardingMusicGenre> = []

    @State private var usernameError: String = ""
    @State private var isCheckingUsername: Bool = false

    private let totalSteps = 5

    private let avatars = [
        "figure.run", "figure.hiking", "figure.martial.arts",
        "figure.strengthtraining.traditional", "figure.mind.and.body",
        "figure.walk", "figure.cooldown", "figure.yoga"
    ]

    var body: some View {
        ZStack {
            MeshGradient(
                width: 3, height: 3,
                points: [
                    [0.0, 0.0], [0.5, 0.0], [1.0, 0.0],
                    [0.0, 0.5], [0.5, 0.5], [1.0, 0.5],
                    [0.0, 1.0], [0.5, 1.0], [1.0, 1.0]
                ],
                colors: [
                    .black, .indigo.opacity(0.3), .black,
                    .red.opacity(0.2), .black, .green.opacity(0.2),
                    .black, .blue.opacity(0.2), .black
                ]
            )
            .ignoresSafeArea()

            if showPermissions {
                PermissionsView(appState: appState) {
                    withAnimation(.spring(response: 0.4)) {
                        showPermissions = false
                    }
                }
                .transition(.asymmetric(insertion: .move(edge: .trailing), removal: .opacity))
            } else {
                switch step {
                case .createProfile:
                    createProfileContent
                case .pickGoals:
                    pickGoalsContent
                case .pickSkills:
                    pickSkillsContent
                case .pickInterests:
                    pickInterestsContent
                case .pickEventPrefs:
                    pickEventPrefsContent
                }
            }
        }
        .onAppear {
            if isRefresh {
                let existing = appState.onboardingData
                selectedGoals = Set(existing.goals)
                selectedSkills = Set(appState.profile.selectedSkills)
                selectedInterests = Set(appState.profile.selectedInterests)
                selectedEventTypes = Set(existing.preferredEventTypes)
                selectedMusicGenres = Set(existing.favoriteMusicGenres)
                username = appState.profile.username
                selectedAvatar = appState.profile.avatarName
                step = .pickGoals
            }
        }
    }

    // MARK: - Step 1: Create Profile

    private var createProfileContent: some View {
        VStack(spacing: 32) {
            stepHeader(current: 1, total: totalSteps)

            Text("Create Your Profile")
                .font(.title.weight(.bold))
                .foregroundStyle(.white)

            VStack(spacing: 20) {
                ZStack {
                    Circle()
                        .fill(.linearGradient(colors: [.blue, .indigo], startPoint: .topLeading, endPoint: .bottomTrailing))
                        .frame(width: 80, height: 80)
                    Image(systemName: selectedAvatar)
                        .font(.system(size: 36))
                        .foregroundStyle(.white)
                }

                ScrollView(.horizontal) {
                    HStack(spacing: 12) {
                        ForEach(avatars, id: \.self) { avatar in
                            Button {
                                selectedAvatar = avatar
                            } label: {
                                Image(systemName: avatar)
                                    .font(.title3)
                                    .foregroundStyle(selectedAvatar == avatar ? .white : .white.opacity(0.4))
                                    .frame(width: 48, height: 48)
                                    .background(selectedAvatar == avatar ? .blue : .white.opacity(0.1), in: Circle())
                            }
                        }
                    }
                }
                .contentMargins(.horizontal, 16)
                .scrollIndicators(.hidden)

                TextField("Username", text: $username)
                    .font(.body)
                    .padding(14)
                    .background(.white.opacity(0.1), in: .rect(cornerRadius: 12))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 24)
            }

            Spacer()

            if !usernameError.isEmpty {
                Text(usernameError)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .padding(.horizontal, 24)
            }

            Button {
                Task { await validateAndProceed() }
            } label: {
                if isCheckingUsername {
                    ProgressView()
                        .frame(maxWidth: .infinity)
                } else {
                    Text("Next")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                }
            }
            .buttonStyle(.borderedProminent)
            .disabled(isCheckingUsername)
            .padding(.horizontal, 24)
            .padding(.bottom, 20)
        }
    }

    // MARK: - Step 2: Goals

    private var pickGoalsContent: some View {
        VStack(spacing: 0) {
            stepHeader(current: 2, total: totalSteps)
                .padding(.top, 16)

            VStack(spacing: 6) {
                Text("What Are Your Goals?")
                    .font(.title.weight(.bold))
                    .foregroundStyle(.white)
                Text("Pick what you want to achieve.\nThis shapes your quest feed.")
                    .font(.subheadline)
                    .foregroundStyle(.white.opacity(0.6))
                    .multilineTextAlignment(.center)
            }
            .padding(.top, 24)
            .padding(.horizontal, 24)

            ScrollView {
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                    ForEach(PlayerGoal.allCases) { goal in
                        goalCard(goal: goal, isSelected: selectedGoals.contains(goal)) {
                            withAnimation(.spring(response: 0.3)) {
                                if selectedGoals.contains(goal) {
                                    selectedGoals.remove(goal)
                                } else {
                                    selectedGoals.insert(goal)
                                }
                            }
                        }
                    }
                }
                .padding(.horizontal, 20)
                .padding(.top, 24)
                .padding(.bottom, 24)
            }

            VStack(spacing: 12) {
                if !selectedGoals.isEmpty {
                    Text("\(selectedGoals.count) selected")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.white.opacity(0.6))
                }
                Button {
                    withAnimation(.spring(response: 0.4)) { step = .pickSkills }
                } label: {
                    Text(selectedGoals.isEmpty ? "Skip" : "Next")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 20)
        }
    }

    private func goalCard(goal: PlayerGoal, isSelected: Bool, action: @escaping () -> Void) -> some View {
        let color = goalColor(goal)
        return Button(action: action) {
            VStack(spacing: 10) {
                Image(systemName: goal.icon)
                    .font(.title2)
                    .foregroundStyle(isSelected ? color : color.opacity(0.6))
                Text(goal.rawValue)
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(.white)
                    .multilineTextAlignment(.center)
            }
            .padding(16)
            .frame(maxWidth: .infinity)
            .background {
                RoundedRectangle(cornerRadius: 14)
                    .fill(isSelected ? color.opacity(0.2) : Color.white.opacity(0.06))
                    .overlay {
                        RoundedRectangle(cornerRadius: 14)
                            .strokeBorder(isSelected ? color.opacity(0.5) : Color.white.opacity(0.1), lineWidth: 1)
                    }
            }
        }
        .buttonStyle(.plain)
        .sensoryFeedback(.selection, trigger: isSelected)
    }

    private func goalColor(_ goal: PlayerGoal) -> Color {
        switch goal {
        case .getfit: .red
        case .buildHabits: .orange
        case .explorePlaces: .green
        case .trainMind: .purple
        case .socialChallenge: .blue
        case .relaxAndUnwind: .teal
        }
    }

    // MARK: - Step 3: Skills

    private var pickSkillsContent: some View {
        VStack(spacing: 0) {
            stepHeader(current: 3, total: totalSteps)
                .padding(.top, 16)

            VStack(spacing: 6) {
                Text("Choose Your Skills")
                    .font(.title.weight(.bold))
                    .foregroundStyle(.white)
                Text("Select the skills you want to develop.\nThese shape your quest recommendations.")
                    .font(.subheadline)
                    .foregroundStyle(.white.opacity(0.6))
                    .multilineTextAlignment(.center)
            }
            .padding(.top, 24)
            .padding(.horizontal, 24)

            ScrollView {
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                    ForEach(UserSkill.allCases) { skill in
                        tagToggleCard(
                            title: skill.rawValue,
                            subtitle: skill.description,
                            icon: skill.icon,
                            color: skill.color,
                            isSelected: selectedSkills.contains(skill)
                        ) {
                            withAnimation(.spring(response: 0.3)) {
                                if selectedSkills.contains(skill) {
                                    selectedSkills.remove(skill)
                                } else {
                                    selectedSkills.insert(skill)
                                }
                            }
                        }
                    }
                }
                .padding(.horizontal, 20)
                .padding(.top, 24)
                .padding(.bottom, 24)
            }

            VStack(spacing: 12) {
                if !selectedSkills.isEmpty {
                    Text("\(selectedSkills.count) selected")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.white.opacity(0.6))
                }
                Button {
                    withAnimation(.spring(response: 0.4)) { step = .pickInterests }
                } label: {
                    Text(selectedSkills.isEmpty ? "Skip" : "Next")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 20)
        }
    }

    // MARK: - Step 4: Interests

    private var pickInterestsContent: some View {
        VStack(spacing: 0) {
            stepHeader(current: 4, total: totalSteps)
                .padding(.top, 16)

            VStack(spacing: 6) {
                Text("Your Interests")
                    .font(.title.weight(.bold))
                    .foregroundStyle(.white)
                Text("Pick what excites you.\nWe'll surface quests you'll actually enjoy.")
                    .font(.subheadline)
                    .foregroundStyle(.white.opacity(0.6))
                    .multilineTextAlignment(.center)
            }
            .padding(.top, 24)
            .padding(.horizontal, 24)

            ScrollView {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 100))], spacing: 10) {
                    ForEach(UserInterest.allCases) { interest in
                        interestChip(
                            interest: interest,
                            isSelected: selectedInterests.contains(interest)
                        ) {
                            withAnimation(.spring(response: 0.3)) {
                                if selectedInterests.contains(interest) {
                                    selectedInterests.remove(interest)
                                } else {
                                    selectedInterests.insert(interest)
                                }
                            }
                        }
                    }
                }
                .padding(.horizontal, 20)
                .padding(.top, 24)
                .padding(.bottom, 24)
            }

            VStack(spacing: 12) {
                if !selectedInterests.isEmpty {
                    Text("\(selectedInterests.count) selected")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.white.opacity(0.6))
                }
                Button {
                    withAnimation(.spring(response: 0.4)) { step = .pickEventPrefs }
                } label: {
                    Text(selectedInterests.isEmpty ? "Skip" : "Next")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 20)
        }
    }

    // MARK: - Step 5: Event Preferences

    private var pickEventPrefsContent: some View {
        VStack(spacing: 0) {
            stepHeader(current: 5, total: totalSteps)
                .padding(.top, 16)

            VStack(spacing: 6) {
                Text("Live Event Preferences")
                    .font(.title.weight(.bold))
                    .foregroundStyle(.white)
                Text("Tell us what kinds of events you want to see.\nThis improves your event recommendations.")
                    .font(.subheadline)
                    .foregroundStyle(.white.opacity(0.6))
                    .multilineTextAlignment(.center)
            }
            .padding(.top, 24)
            .padding(.horizontal, 24)

            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("What sounds fun?")
                            .font(.headline.weight(.bold))
                            .foregroundStyle(.white)

                        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                            ForEach(LiveEventPreference.allCases) { preference in
                                tagToggleCard(
                                    title: preference.rawValue,
                                    subtitle: liveEventPreferenceSubtitle(preference),
                                    icon: preference.icon,
                                    color: eventPreferenceColor(preference),
                                    isSelected: selectedEventTypes.contains(preference)
                                ) {
                                    withAnimation(.spring(response: 0.3)) {
                                        if selectedEventTypes.contains(preference) {
                                            selectedEventTypes.remove(preference)
                                        } else {
                                            selectedEventTypes.insert(preference)
                                        }
                                    }
                                }
                            }
                        }
                    }

                    VStack(alignment: .leading, spacing: 10) {
                        Text("Favorite music genres")
                            .font(.headline.weight(.bold))
                            .foregroundStyle(.white)

                        LazyVGrid(columns: [GridItem(.adaptive(minimum: 100))], spacing: 10) {
                            ForEach(OnboardingMusicGenre.allCases) { genre in
                                musicGenreChip(
                                    genre: genre,
                                    isSelected: selectedMusicGenres.contains(genre)
                                ) {
                                    withAnimation(.spring(response: 0.3)) {
                                        if selectedMusicGenres.contains(genre) {
                                            selectedMusicGenres.remove(genre)
                                        } else {
                                            selectedMusicGenres.insert(genre)
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
                .padding(.horizontal, 20)
                .padding(.top, 24)
                .padding(.bottom, 24)
            }

            VStack(spacing: 12) {
                if !selectedEventTypes.isEmpty || !selectedMusicGenres.isEmpty {
                    Text("\(selectedEventTypes.count + selectedMusicGenres.count) selected")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.white.opacity(0.6))
                }
                Button {
                    finalizeOnboardingData()
                } label: {
                    Text(selectedEventTypes.isEmpty && selectedMusicGenres.isEmpty ? "Skip" : "Begin Your Quest")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 20)
        }
    }

    // MARK: - Finalize

    private func finalizeOnboardingData() {
        appState.saveTagSelections(
            skills: Array(selectedSkills),
            interests: Array(selectedInterests)
        )

        let data = OnboardingData(
            goals: Array(selectedGoals),
            timeBudget: .moderate,
            verificationPreference: .mixed,
            preferredEventTypes: Array(selectedEventTypes),
            favoriteMusicGenres: Array(selectedMusicGenres),
            completedAt: Date(),
            version: OnboardingData.currentVersion
        )
        appState.saveOnboardingData(data)

        if isRefresh {
            appState.showOnboardingRefresh = false
        } else {
            appState.completeProfileSetup()
            withAnimation(.spring(response: 0.4)) {
                showPermissions = true
            }
        }
    }

    // MARK: - Validation

    private func validateAndProceed() async {
        let name = username.trimmingCharacters(in: .whitespacesAndNewlines)
        usernameError = ""

        guard !name.isEmpty else {
            usernameError = "Username is required."
            return
        }

        guard name.count >= 3 else {
            usernameError = "Username must be at least 3 characters."
            return
        }

        guard name.range(of: "^[a-zA-Z0-9_]+$", options: .regularExpression) != nil else {
            usernameError = "Only letters, numbers, and underscores allowed."
            return
        }

        isCheckingUsername = false

        appState.prepareOnboarding(username: name, avatar: selectedAvatar)
        withAnimation(.spring(response: 0.4)) {
            step = .pickGoals
        }
    }

    // MARK: - Shared Components

    private func stepHeader(current: Int, total: Int) -> some View {
        HStack(spacing: 8) {
            ForEach(1...max(1, total), id: \.self) { i in
                Capsule()
                    .fill(i <= current ? Color.white : Color.white.opacity(0.2))
                    .frame(height: 4)
            }
        }
        .padding(.horizontal, 32)
        .animation(.spring(response: 0.4), value: current)
    }

    private func tagToggleCard(
        title: String,
        subtitle: String,
        icon: String,
        color: Color,
        isSelected: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Image(systemName: icon)
                        .font(.title2)
                        .foregroundStyle(isSelected ? color : color.opacity(0.6))
                    Spacer()
                    if isSelected {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.subheadline)
                            .foregroundStyle(.white)
                    }
                }
                Text(title)
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(.white)
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.6))
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background {
                RoundedRectangle(cornerRadius: 14)
                    .fill(isSelected ? color.opacity(0.2) : Color.white.opacity(0.06))
                    .overlay {
                        RoundedRectangle(cornerRadius: 14)
                            .strokeBorder(isSelected ? color.opacity(0.5) : Color.white.opacity(0.1), lineWidth: 1)
                    }
            }
        }
        .buttonStyle(.plain)
        .sensoryFeedback(.selection, trigger: isSelected)
    }

    private func interestChip(
        interest: UserInterest,
        isSelected: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: interest.icon)
                    .font(.callout)
                    .foregroundStyle(isSelected ? .white : interest.color)
                Text(interest.rawValue)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(isSelected ? .white : .white.opacity(0.8))
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .frame(maxWidth: .infinity)
            .background {
                Capsule()
                    .fill(isSelected ? interest.color : Color.white.opacity(0.08))
                    .overlay {
                        Capsule()
                            .strokeBorder(isSelected ? interest.color : Color.white.opacity(0.15), lineWidth: 1)
                    }
            }
        }
        .buttonStyle(.plain)
        .sensoryFeedback(.selection, trigger: isSelected)
    }

    private func eventPreferenceColor(_ preference: LiveEventPreference) -> Color {
        switch preference {
        case .concerts: return .pink
        case .nightlife: return .purple
        case .exclusiveNightlife: return .mint
        case .comedy: return .orange
        case .community: return .green
        case .markets: return .yellow
        case .raceEvents: return .red
        case .sportsGames: return .blue
        case .wellness: return .teal
        case .foodAndDrink: return .indigo
        }
    }

    private func liveEventPreferenceSubtitle(_ preference: LiveEventPreference) -> String {
        switch preference {
        case .concerts: return "Live music, touring artists, and big nights out."
        case .nightlife: return "Dance parties, DJ sets, club nights, and after-dark energy."
        case .exclusiveNightlife: return "Velvet-rope spots, celebrity rooms, bottle-service energy, and the hardest doors."
        case .comedy: return "Stand-up, improv, and nights that feel social and funny."
        case .community: return "Gatherings, volunteer moments, and culture-driven local events."
        case .markets: return "Street fairs, markets, pop-ups, and local discovery."
        case .raceEvents: return "5Ks, group runs, and race weekends worth training for."
        case .sportsGames: return "NBA, soccer, UFC, wrestling, and big-ticket live games with real crowd energy."
        case .wellness: return "Yoga, recovery, sound baths, and feel-good reset plans."
        case .foodAndDrink: return "Brunches, tastings, food festivals, and drink-led nights."
        }
    }

    private func musicGenreChip(
        genre: OnboardingMusicGenre,
        isSelected: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: genre.icon)
                    .font(.callout)
                    .foregroundStyle(isSelected ? .white : eventPreferenceColor(.concerts))
                Text(genre.rawValue)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(isSelected ? .white : .white.opacity(0.82))
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .frame(maxWidth: .infinity)
            .background {
                Capsule()
                    .fill(isSelected ? eventPreferenceColor(.concerts) : Color.white.opacity(0.08))
                    .overlay {
                        Capsule()
                            .strokeBorder(isSelected ? eventPreferenceColor(.concerts) : Color.white.opacity(0.15), lineWidth: 1)
                    }
            }
        }
        .buttonStyle(.plain)
        .sensoryFeedback(.selection, trigger: isSelected)
    }
}

nonisolated enum OnboardingStep {
    case createProfile
    case pickGoals
    case pickSkills
    case pickInterests
    case pickEventPrefs
}
