import SwiftUI
import UIKit

struct QuestDetailView: View {
    let quest: Quest
    let appState: AppState
    @Environment(\.dismiss) private var dismiss
    @State private var showModeSelection: Bool = false
    @State private var showOpenPlayComplete: Bool = false
    @State private var openPlayCompleted: Bool = false
    @State private var showGroupHandshake: Bool = false
    @State private var showFocusSchedule: Bool = false
    @State private var focusScheduleMode: QuestMode = .solo
    @State private var showFocusDatePicker: Bool = false
    @State private var focusScheduledDate: Date = Date().addingTimeInterval(3600)
    @State private var focusScheduledConfirmed: Bool = false

    private var assetPair: QuestAssetPair {
        QuestAssetMapping.assets(for: quest.title)
    }

    private var pathColor: Color {
        PathColorHelper.color(for: quest.path)
    }

    private func loadBundleImage(_ name: String, ext: String, folder: String) -> UIImage? {
        if let url = Bundle.main.url(forResource: name, withExtension: ext, subdirectory: "Resources/\(folder)"),
           let img = UIImage(contentsOfFile: url.path) {
            return img
        }
        if let url = Bundle.main.url(forResource: name, withExtension: ext),
           let img = UIImage(contentsOfFile: url.path) {
            return img
        }
        return UIImage(named: name)
    }

    private var userCompletionCount: Int {
        appState.questCompletionCounts[quest.id] ?? 0
    }

    private var hasCompletedQuestBefore: Bool {
        userCompletionCount > 0
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    questHeroImage
                    headerSection
                    rewardSection
                    descriptionSection
                    if !quest.milestoneIds.isEmpty {
                        milestoneSection
                    }
                    if quest.hasTimeWindow {
                        timeWindowSection
                    }
                    if quest.type == .verified {
                        evidenceInfoSection
                    }
                    if quest.isTrackingQuest {
                        trackingInfoSection
                        if quest.trailMapCategory != nil {
                            viewTrailsOnMapButton
                        }
                    }
                    if quest.isPoseTrackingQuest {
                        exerciseInfoSection
                    }
                    if quest.isMeditationQuest {
                        meditationInfoSection
                    }
                    if quest.isReadingQuest {
                        readingInfoSection
                    }
                    if quest.isFocusQuest {
                        focusInfoSection
                    }
                    if quest.isStepQuest {
                        stepInfoSection
                    }
                    if quest.isGratitudeQuest {
                        gratitudeInfoSection
                    }
                    if quest.isAffirmationQuest {
                        affirmationInfoSection
                    }
                    if quest.isPlaceVerificationQuest {
                        placeVerificationInfoSection
                        SuggestedLocationsSection(quest: quest, appState: appState)
                    }
                    acceptSection
                }
                .padding(16)
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("Side Quest Detail")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
            }
            .onChange(of: showModeSelection) { _, show in
                if show {
                    showModeSelection = false
                    if quest.isFocusQuest {
                        focusScheduleMode = .solo
                        showFocusSchedule = true
                    } else {
                        appState.acceptQuest(quest, mode: .solo)
                        dismiss()
                    }
                }
            }
            .sheet(isPresented: $showFocusSchedule) {
                focusScheduleSheet
            }
            .alert("Side Quest Logged!", isPresented: $openPlayCompleted) {
                Button("Done") { dismiss() }
            } message: {
                Text("+\(quest.xpReward) XP, +\(quest.goldReward) Gold")
            }
        }
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
    }

    private var questHeroImage: some View {
        Color(.secondarySystemGroupedBackground)
            .frame(height: 200)
            .overlay {
                if let img = loadBundleImage(assetPair.banner, ext: "jpg", folder: "QuestBanners") {
                    Image(uiImage: img)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .allowsHitTesting(false)
                }
            }
            .clipShape(.rect(cornerRadius: 16))
            .overlay(alignment: .bottom) {
                LinearGradient(
                    colors: [.clear, .clear, Color.black.opacity(0.3), Color.black.opacity(0.7)],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .frame(height: 100)
                .clipShape(.rect(cornerRadius: 16))
                .allowsHitTesting(false)
            }
            .overlay(alignment: .bottomTrailing) {
                if let icon = loadBundleImage(assetPair.icon, ext: "png", folder: "QuestIcons") {
                    Image(uiImage: icon)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(width: 100, height: 100)
                        .shadow(color: .black.opacity(0.5), radius: 8, y: 4)
                        .padding(.trailing, 12)
                        .padding(.bottom, 8)
                        .allowsHitTesting(false)
                }
            }
    }

    private var headerSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                PathBadgeView(path: quest.path)
                DifficultyBadge(difficulty: quest.difficulty)
                if quest.type == .verified {
                    VerifiedBadge(isVerified: true)
                }
                Spacer()
                if quest.isFeatured {
                    Label("Featured", systemImage: "star.fill")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(.orange)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(.orange.opacity(0.12), in: Capsule())
                }
            }

            Text(quest.title)
                .font(.title.weight(.bold))

            if let author = quest.authorUsername {
                HStack(spacing: 6) {
                    Image(systemName: "person.circle.fill")
                        .font(.subheadline)
                    Text("Created by @\(author)")
                        .font(.subheadline.weight(.medium))
                }
                .foregroundStyle(.indigo)
            }

            HStack(spacing: 16) {
                if quest.completionCount > 0 {
                    Label("\(quest.completionCount.formatted()) global", systemImage: "globe")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                if let myCount = appState.questCompletionCounts[quest.id], myCount > 0 {
                    Label("\(myCount) by you", systemImage: "person.fill")
                        .font(.subheadline)
                        .foregroundStyle(pathColor)
                }
            }
        }
    }

    private var rewardSection: some View {
        HStack(spacing: 0) {
            VStack(spacing: 4) {
                Image(systemName: "bolt.fill")
                    .font(.title3)
                    .foregroundStyle(.orange)
                Text("\(quest.xpReward)")
                    .font(.headline.monospacedDigit())
                Text("XP")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity)

            Divider().frame(height: 40)

            VStack(spacing: 4) {
                Image(systemName: "dollarsign.circle.fill")
                    .font(.title3)
                    .foregroundStyle(.yellow)
                Text("\(quest.goldReward)")
                    .font(.headline.monospacedDigit())
                Text("Gold")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity)

            if quest.diamondReward > 0 {
                Divider().frame(height: 40)
                VStack(spacing: 4) {
                    Image(systemName: "diamond.fill")
                        .font(.title3)
                        .foregroundStyle(.cyan)
                    Text("\(quest.diamondReward)")
                        .font(.headline.monospacedDigit())
                    Text("Diamonds")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity)
            }
        }
        .padding(.vertical, 16)
        .background(Color(.secondarySystemGroupedBackground), in: .rect(cornerRadius: 14))
    }

    private var descriptionSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Description")
                .font(.headline)
            Text(quest.description)
                .font(.body)
                .foregroundStyle(.secondary)
        }
    }

    private var milestoneSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Contributes to Milestones")
                .font(.headline)

            let relatedMilestones = appState.milestones.filter { quest.milestoneIds.contains($0.id) }
            ForEach(relatedMilestones) { milestone in
                HStack {
                    Image(systemName: "flag.fill")
                        .foregroundStyle(pathColor)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(milestone.title)
                            .font(.subheadline.weight(.medium))
                        Text("\(milestone.currentCount)/\(milestone.requiredCount)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    ProgressView(value: Double(milestone.currentCount), total: Double(milestone.requiredCount))
                        .tint(pathColor)
                        .frame(width: 60)
                }
                .padding(10)
                .background(Color(.tertiarySystemGroupedBackground), in: .rect(cornerRadius: 10))
            }

            if quest.requiresUniqueLocation {
                Label("Unique locations count for Explorer milestones", systemImage: "location.fill")
                    .font(.caption)
                    .foregroundStyle(.green)
            }
        }
    }

    private var timeWindowSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Time Window")
                .font(.headline)

            HStack(spacing: 12) {
                Image(systemName: sunEventIcon)
                    .font(.title2)
                    .foregroundStyle(quest.isWithinTimeWindow ? .green : .orange)
                    .frame(width: 44, height: 44)
                    .background(
                        (quest.isWithinTimeWindow ? Color.green : Color.orange).opacity(0.12),
                        in: .rect(cornerRadius: 10)
                    )

                VStack(alignment: .leading, spacing: 4) {
                    if let desc = quest.timeWindowDescription {
                        Text(desc)
                            .font(.subheadline.weight(.semibold))
                    }
                    if quest.isSunEventQuest {
                        if appState.solarService.isReady {
                            Label("Based on your location", systemImage: "location.fill")
                                .font(.caption2)
                                .foregroundStyle(.blue)
                        } else {
                            Label("Enable location for exact times", systemImage: "location.slash")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    }
                    if quest.isWithinTimeWindow {
                        Label("Window is open now", systemImage: "checkmark.circle.fill")
                            .font(.caption)
                            .foregroundStyle(.green)
                    } else if let next = quest.nextWindowOpensDescription {
                        Label(next, systemImage: "moon.zzz.fill")
                            .font(.caption)
                            .foregroundStyle(.orange)
                    }
                    if quest.timeWindowGraceMinutes > 0 {
                        Text("+\(quest.timeWindowGraceMinutes) min grace after window closes")
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }
                }
            }

            HStack(spacing: 6) {
                Image(systemName: "lock.shield.fill")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text("Verified by device clock at start and end of session")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var sunEventIcon: String {
        switch quest.sunEventType {
        case .sunrise: "sunrise.fill"
        case .sunset: "sunset.fill"
        case nil: "clock.fill"
        }
    }

    private var evidenceInfoSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Evidence Required")
                .font(.headline)

            HStack(spacing: 12) {
                Image(systemName: evidenceIcon)
                    .font(.title2)
                    .foregroundStyle(pathColor)
                    .frame(width: 44, height: 44)
                    .background(pathColor.opacity(0.12), in: .rect(cornerRadius: 10))

                VStack(alignment: .leading, spacing: 2) {
                    Text(quest.evidenceType?.rawValue ?? "None")
                        .font(.subheadline.weight(.medium))
                    if quest.isGratitudeQuest {
                        Text("Photo of handwritten entry required. No digital text.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    } else if quest.isStepQuest {
                        Text("Steps verified with Motion & Fitness access. Enable step tracking in Settings.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    } else if quest.isTrackingQuest {
                        Text("Your route will be tracked in real-time with GPS.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    } else if quest.isPoseTrackingQuest {
                        Text("Live camera verification. Your form is analyzed in real-time.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    } else if quest.isMeditationQuest {
                        Text("Face & eye tracking verifies eyes closed, stillness, and presence.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    } else if quest.isReadingQuest {
                        Text("Book detection + eye gaze tracking verifies you're actually reading.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    } else if quest.isFocusQuest {
                        Text("Stay in-app for the full duration. No app switching allowed.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    } else if quest.isAffirmationQuest {
                        Text("Photo of handwritten affirmations required. No digital text.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    } else if quest.isPlaceVerificationQuest {
                        if quest.requiredPlaceType?.isGPSOnly == true {
                            Text("GPS verifies your location. Stay for the required duration — no photo needed.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        } else {
                            Text("On-device AI scans your environment to confirm you're at the right place.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    } else {
                        Text("Must be captured in-app. No camera roll uploads.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            if quest.isTrackingQuest, let target = quest.targetDistanceMiles {
                Label("Target: \(String(format: "%.2f", target)) miles", systemImage: "figure.walk")
                    .font(.caption)
                    .foregroundStyle(pathColor)
            }

            if quest.isStepQuest, let target = quest.targetSteps {
                Label("Target: \(target.formatted()) steps", systemImage: "figure.walk")
                    .font(.caption)
                    .foregroundStyle(pathColor)
            }

            if quest.minCompletionMinutes > 0 {
                Label("Submit available after \(quest.minCompletionMinutes) minutes", systemImage: "clock.fill")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var evidenceIcon: String {
        switch quest.evidenceType {
        case .video: "video.fill"
        case .dualPhoto: "camera.fill"
        case .gpsTracking: "location.fill"
        case .pushUpTracking: "figure.strengthtraining.traditional"
        case .jumpRopeTracking: "figure.jumprope"
        case .plankTracking: "figure.core.training"
        case .wallSitTracking: "figure.seated.side"
        case .meditationTracking: "brain.head.profile.fill"
        case .readingTracking: "book.fill"
        case .gratitudePhoto: "square.and.pencil"
        case .stepTracking: "figure.walk"
        case .focusTracking: "timer"
        case .affirmationPhoto: "sparkles"
        case .placeVerification: "brain.filled.head.profile"
        case nil: "questionmark.circle"
        }
    }

    private var exerciseInfoSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Camera Verification")
                .font(.headline)

            VStack(spacing: 8) {
                HStack(spacing: 12) {
                    Image(systemName: quest.evidenceType == .pushUpTracking ? "figure.strengthtraining.traditional" : quest.evidenceType == .wallSitTracking ? "figure.seated.side" : quest.evidenceType == .jumpRopeTracking ? "figure.jumprope" : "figure.core.training")
                        .font(.title2)
                        .foregroundStyle(pathColor)
                        .frame(width: 44, height: 44)
                        .background(pathColor.opacity(0.12), in: .rect(cornerRadius: 10))

                    VStack(alignment: .leading, spacing: 4) {
                        if quest.evidenceType == .pushUpTracking, let reps = quest.targetReps {
                            Text("Target: \(reps) reps")
                                .font(.subheadline.weight(.semibold))
                        } else if quest.evidenceType == .jumpRopeTracking, let jumps = quest.targetReps {
                            Text("Target: \(jumps) jumps")
                                .font(.subheadline.weight(.semibold))
                        } else if (quest.evidenceType == .plankTracking || quest.evidenceType == .wallSitTracking), let hold = quest.targetHoldSeconds {
                            let m = Int(hold) / 60
                            let s = Int(hold) % 60
                            Text("Hold: \(m > 0 ? "\(m)m " : "")\(s > 0 ? "\(s)s" : "")")
                                .font(.subheadline.weight(.semibold))
                        }
                        Text("Real-time pose tracking with anti-cheat")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                HStack(spacing: 16) {
                    Label("Front camera", systemImage: "camera.fill")
                    Label("Body tracking", systemImage: "person.fill.viewfinder")
                    Label("Anti-fraud", systemImage: "checkmark.shield.fill")
                }
                .font(.caption2.weight(.medium))
                .foregroundStyle(.secondary)
            }
            .padding(12)
            .background(Color(.tertiarySystemGroupedBackground), in: .rect(cornerRadius: 12))
        }
    }

    private var readingInfoSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Reading Verification")
                .font(.headline)

            VStack(spacing: 8) {
                HStack(spacing: 12) {
                    Image(systemName: "book.fill")
                        .font(.title2)
                        .foregroundStyle(.teal)
                        .frame(width: 44, height: 44)
                        .background(.teal.opacity(0.12), in: .rect(cornerRadius: 10))

                    VStack(alignment: .leading, spacing: 4) {
                        if let hold = quest.targetHoldSeconds {
                            let m = Int(hold) / 60
                            Text("Duration: \(m) min")
                                .font(.subheadline.weight(.semibold))
                        }
                        Text("Book detection + eye gaze tracking")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                HStack(spacing: 16) {
                    Label("Front camera", systemImage: "camera.fill")
                    Label("Eye tracking", systemImage: "eye.fill")
                    Label("Book detection", systemImage: "book.closed.fill")
                }
                .font(.caption2.weight(.medium))
                .foregroundStyle(.secondary)
            }
            .padding(12)
            .background(Color(.tertiarySystemGroupedBackground), in: .rect(cornerRadius: 12))
        }
    }

    private var meditationInfoSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Meditation Verification")
                .font(.headline)

            VStack(spacing: 8) {
                HStack(spacing: 12) {
                    Image(systemName: "brain.head.profile.fill")
                        .font(.title2)
                        .foregroundStyle(.indigo)
                        .frame(width: 44, height: 44)
                        .background(.indigo.opacity(0.12), in: .rect(cornerRadius: 10))

                    VStack(alignment: .leading, spacing: 4) {
                        if let hold = quest.targetHoldSeconds {
                            let m = Int(hold) / 60
                            let s = Int(hold) % 60
                            Text("Duration: \(m > 0 ? "\(m)m " : "")\(s > 0 ? "\(s)s" : "")")
                                .font(.subheadline.weight(.semibold))
                        }
                        Text("Face & eye tracking with anti-cheat")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                HStack(spacing: 16) {
                    Label("Front camera", systemImage: "camera.fill")
                    Label("Eyes closed", systemImage: "eye.slash.fill")
                    Label("Stillness", systemImage: "hand.raised.fill")
                }
                .font(.caption2.weight(.medium))
                .foregroundStyle(.secondary)
            }
            .padding(12)
            .background(Color(.tertiarySystemGroupedBackground), in: .rect(cornerRadius: 12))
        }
    }

    private var trackingInfoSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("GPS Tracking")
                .font(.headline)

            VStack(spacing: 8) {
                HStack(spacing: 12) {
                    Image(systemName: "location.fill")
                        .font(.title2)
                        .foregroundStyle(pathColor)
                        .frame(width: 44, height: 44)
                        .background(pathColor.opacity(0.12), in: .rect(cornerRadius: 10))

                    VStack(alignment: .leading, spacing: 4) {
                        if let target = quest.targetDistanceMiles {
                            Text("Distance: \(String(format: "%.2f", target)) miles")
                                .font(.subheadline.weight(.semibold))
                        }
                        Text("Route tracked live with anti-cheat")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                HStack(spacing: 16) {
                    Label("Max \(Int(quest.maxSpeedMph)) mph", systemImage: "speedometer")
                    if quest.maxPauseMinutes > 0 {
                        Label("\(quest.maxPauseMinutes)m pause", systemImage: "pause.circle")
                    } else {
                        Label("No pausing", systemImage: "pause.circle")
                    }
                    if quest.isTimedChallenge, let desc = quest.timeLimitDescription {
                        Label(desc, systemImage: "timer")
                            .foregroundStyle(.red)
                    }
                }
                .font(.caption2.weight(.medium))
                .foregroundStyle(.secondary)
            }
            .padding(12)
            .background(Color(.tertiarySystemGroupedBackground), in: .rect(cornerRadius: 12))
        }
    }

    private var stepInfoSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Step Verification")
                .font(.headline)

            VStack(spacing: 8) {
                HStack(spacing: 12) {
                    Image(systemName: "figure.walk")
                        .font(.title2)
                        .foregroundStyle(pathColor)
                        .frame(width: 44, height: 44)
                        .background(pathColor.opacity(0.12), in: .rect(cornerRadius: 10))

                    VStack(alignment: .leading, spacing: 4) {
                        if let target = quest.targetSteps {
                            Text("Target: \(target.formatted()) steps")
                                .font(.subheadline.weight(.semibold))
                        }
                        Text("Verified via Motion & Fitness")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                HStack(spacing: 16) {
                    Label("Motion & Fitness", systemImage: "figure.walk")
                    Label("Auto-refresh", systemImage: "arrow.clockwise")
                    Label("Anti-fraud", systemImage: "checkmark.shield.fill")
                }
                .font(.caption2.weight(.medium))
                .foregroundStyle(.secondary)
            }
            .padding(12)
            .background(Color(.tertiarySystemGroupedBackground), in: .rect(cornerRadius: 12))
        }
    }

    private var focusInfoSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Focus Verification")
                .font(.headline)

            VStack(spacing: 8) {
                HStack(spacing: 12) {
                    Image(systemName: "timer")
                        .font(.title2)
                        .foregroundStyle(.cyan)
                        .frame(width: 44, height: 44)
                        .background(.cyan.opacity(0.12), in: .rect(cornerRadius: 10))

                    VStack(alignment: .leading, spacing: 4) {
                        if let mins = quest.targetFocusMinutes {
                            Text("Duration: \(mins) minutes")
                                .font(.subheadline.weight(.semibold))
                        }
                        Text("Stay in-app for the full duration")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                HStack(spacing: 16) {
                    Label("In-app lock", systemImage: "iphone.gen3")
                    if let maxP = quest.maxPauseCount, maxP > 0 {
                        Label("\(maxP) pause(s)", systemImage: "pause.circle")
                    } else {
                        Label("No pausing", systemImage: "xmark.circle")
                    }
                    Label("Anti-cheat", systemImage: "checkmark.shield.fill")
                }
                .font(.caption2.weight(.medium))
                .foregroundStyle(.secondary)
            }
            .padding(12)
            .background(Color(.tertiarySystemGroupedBackground), in: .rect(cornerRadius: 12))
        }
    }

    private var affirmationInfoSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Affirmation Verification")
                .font(.headline)

            VStack(spacing: 8) {
                HStack(spacing: 12) {
                    Image(systemName: "sparkles")
                        .font(.title2)
                        .foregroundStyle(.purple)
                        .frame(width: 44, height: 44)
                        .background(.purple.opacity(0.12), in: .rect(cornerRadius: 10))

                    VStack(alignment: .leading, spacing: 4) {
                        Text("Write affirmations by hand, then photograph")
                            .font(.subheadline.weight(.semibold))
                        Text("Your handwritten affirmations are analyzed for authenticity")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                HStack(spacing: 16) {
                    Label("Pen & paper", systemImage: "pencil.line")
                    Label("Photo proof", systemImage: "camera.fill")
                    Label("Anti-fraud", systemImage: "checkmark.shield.fill")
                }
                .font(.caption2.weight(.medium))
                .foregroundStyle(.secondary)
            }
            .padding(12)
            .background(Color(.tertiarySystemGroupedBackground), in: .rect(cornerRadius: 12))
        }
    }

    private var placeVerificationInfoSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Location Verification")
                .font(.headline)

            let placeType = quest.requiredPlaceType ?? .gym

            VStack(spacing: 12) {
                HStack(spacing: 12) {
                    Image(systemName: "location.fill")
                        .font(.title2)
                        .foregroundStyle(.blue)
                        .frame(width: 44, height: 44)
                        .background(.blue.opacity(0.12), in: .rect(cornerRadius: 10))

                    VStack(alignment: .leading, spacing: 4) {
                        Text("GPS Check-In Required")
                            .font(.subheadline.weight(.semibold))
                        Text("You must be within \(placeType.gpsRadiusMeters)m of the location and stay for at least \(quest.effectivePresenceMinutes) min.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                if placeType.isGPSOnly {
                    Divider()

                    HStack(spacing: 12) {
                        Image(systemName: placeType.icon)
                            .font(.title2)
                            .foregroundStyle(placeType.accentColor)
                            .frame(width: 44, height: 44)
                            .background(placeType.accentColor.opacity(0.12), in: .rect(cornerRadius: 10))

                        VStack(alignment: .leading, spacing: 4) {
                            Text("GPS-Only: \(placeType.rawValue)")
                                .font(.subheadline.weight(.semibold))
                            Text(placeType.captureInstructions)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }

                    if placeType == .gym {
                        HStack(spacing: 8) {
                            Image(systemName: "mappin.and.ellipse")
                                .foregroundStyle(.orange)
                            Text("Set your default gym in Settings for faster check-ins")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }

                    HStack(spacing: 16) {
                        Label("\(placeType.gpsRadiusMeters)m radius", systemImage: "location.circle.fill")
                        Label("\(quest.effectivePresenceMinutes) min", systemImage: "timer")
                        Label("No photo", systemImage: "camera.slash")
                    }
                    .font(.caption2.weight(.medium))
                    .foregroundStyle(.secondary)
                } else {
                    Divider()

                    HStack(spacing: 12) {
                        Image(systemName: placeType.icon)
                            .font(.title2)
                            .foregroundStyle(placeType.accentColor)
                            .frame(width: 44, height: 44)
                            .background(placeType.accentColor.opacity(0.12), in: .rect(cornerRadius: 10))

                        VStack(alignment: .leading, spacing: 4) {
                            Text("AI Scene Verification: \(placeType.rawValue)")
                                .font(.subheadline.weight(.semibold))
                            Text(placeType.captureInstructions)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }

                    HStack(spacing: 16) {
                        Label("\(placeType.gpsRadiusMeters)m radius", systemImage: "location.circle.fill")
                        Label("\(quest.effectivePresenceMinutes) min", systemImage: "timer")
                        Label("Anti-spoof", systemImage: "checkmark.shield.fill")
                    }
                    .font(.caption2.weight(.medium))
                    .foregroundStyle(.secondary)

                    if quest.hasExpertFocusChallenge, let focusMins = quest.expertFocusMinutes {
                        Divider()

                        HStack(spacing: 12) {
                            Image(systemName: "lock.shield.fill")
                                .font(.title2)
                                .foregroundStyle(.purple)
                                .frame(width: 44, height: 44)
                                .background(.purple.opacity(0.12), in: .rect(cornerRadius: 10))

                            VStack(alignment: .leading, spacing: 4) {
                                HStack(spacing: 6) {
                                    Text("Expert Challenge")
                                        .font(.subheadline.weight(.semibold))
                                    Text("OPTIONAL")
                                        .font(.caption2.weight(.heavy))
                                        .foregroundStyle(.purple)
                                        .padding(.horizontal, 6)
                                        .padding(.vertical, 2)
                                        .background(.purple.opacity(0.15), in: Capsule())
                                }
                                Text("Complete a \(focusMins)-minute Focus Mode lock session on your phone for bonus XP. No app switching allowed.")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            }
            .padding(12)
            .background(Color(.tertiarySystemGroupedBackground), in: .rect(cornerRadius: 12))
        }
    }

    private var gratitudeInfoSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Handwriting Verification")
                .font(.headline)

            VStack(spacing: 8) {
                HStack(spacing: 12) {
                    Image(systemName: "square.and.pencil")
                        .font(.title2)
                        .foregroundStyle(.orange)
                        .frame(width: 44, height: 44)
                        .background(.orange.opacity(0.12), in: .rect(cornerRadius: 10))

                    VStack(alignment: .leading, spacing: 4) {
                        Text("Write by hand, then photograph")
                            .font(.subheadline.weight(.semibold))
                        Text("Your handwritten entry is analyzed for authenticity")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                HStack(spacing: 16) {
                    Label("Pen & paper", systemImage: "pencil.line")
                    Label("Photo proof", systemImage: "camera.fill")
                    Label("Anti-fraud", systemImage: "checkmark.shield.fill")
                }
                .font(.caption2.weight(.medium))
                .foregroundStyle(.secondary)
            }
            .padding(12)
            .background(Color(.tertiarySystemGroupedBackground), in: .rect(cornerRadius: 12))
        }
    }

    private var viewTrailsOnMapButton: some View {
        Button {
            if let category = quest.trailMapCategory {
                appState.pendingMapCategory = category
                appState.selectedTab = 2
                dismiss()
            }
        } label: {
            HStack(spacing: 10) {
                Image(systemName: quest.isBikeQuest ? "bicycle" : "figure.hiking")
                    .font(.title3)
                    .foregroundStyle(.white)
                    .frame(width: 40, height: 40)
                    .background(quest.trailMapCategory?.mapColor ?? .mint, in: .rect(cornerRadius: 10))
                VStack(alignment: .leading, spacing: 2) {
                    Text(quest.isBikeQuest ? "View Bike Paths on Map" : "View Trails on Map")
                        .font(.subheadline.weight(.semibold))
                    Text("Find nearby \(quest.isBikeQuest ? "bike paths" : "trails") to start your quest")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Image(systemName: "map.fill")
                    .font(.body)
                    .foregroundStyle(quest.trailMapCategory?.mapColor ?? .mint)
            }
            .padding(12)
            .background(Color(.tertiarySystemGroupedBackground), in: .rect(cornerRadius: 12))
        }
        .buttonStyle(.plain)
    }

    private var acceptSection: some View {
        VStack(spacing: 12) {
            if quest.type == .open {
                Button {
                    appState.completeOpenPlayQuest(quest)
                    openPlayCompleted = true
                } label: {
                    Label("Log Completion", systemImage: "checkmark.circle.fill")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(pathColor)
                .sensoryFeedback(.success, trigger: openPlayCompleted)

                Text("Personal logging — no verification required")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                let isAtCap = appState.activeQuestCount >= 5
                let isAlreadyActive = appState.isQuestAlreadyActive(quest.id)
                let outsideWindow = quest.hasTimeWindow && !quest.isWithinTimeWindow
                let isLockedByCompletion = hasCompletedQuestBefore && !quest.isRepeatable

                if isAlreadyActive {
                    Label("Side Quest Already Active", systemImage: "bolt.circle.fill")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .foregroundStyle(.blue)
                        .padding(.vertical, 12)
                        .background(.blue.opacity(0.1), in: .rect(cornerRadius: 10))
                } else if isLockedByCompletion {
                    Label("Already Completed", systemImage: "checkmark.circle.fill")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .foregroundStyle(.green)
                        .padding(.vertical, 12)
                        .background(.green.opacity(0.1), in: .rect(cornerRadius: 10))
                } else {
                    Button {
                        showModeSelection = true
                    } label: {
                        Label(hasCompletedQuestBefore ? "Complete Again" : "Accept Side Quest", systemImage: "plus.circle.fill")
                            .font(.headline)
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(pathColor)
                    .disabled(isAtCap || outsideWindow || isLockedByCompletion)

                    if outsideWindow {
                        if let next = quest.nextWindowOpensDescription {
                            Label(next, systemImage: "clock.fill")
                                .font(.caption)
                                .foregroundStyle(.orange)
                        }
                    } else if isLockedByCompletion {
                        Text("This quest can only be completed once.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                    } else if isAtCap {
                        Text("You have 5 active side quests. Complete or drop one first.")
                            .font(.caption)
                            .foregroundStyle(.red)
                            .multilineTextAlignment(.center)
                    } else if hasCompletedQuestBefore && quest.isRepeatable {
                        Text("You’ve completed this before, so you can run it again.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                    }
                }
            }
        }
        .padding(.top, 8)
    }

    private var focusTargetDuration: TimeInterval { Double((quest.targetFocusMinutes ?? 10) * 60) }

    private func focusFormatDuration(_ seconds: TimeInterval) -> String {
        let total = Int(max(0, seconds))
        let h = total / 3600
        let m = (total % 3600) / 60
        let s = total % 60
        if h > 0 {
            return String(format: "%d:%02d:%02d", h, m, s)
        }
        return String(format: "%d:%02d", m, s)
    }

    private var focusScheduleSheet: some View {
        NavigationStack {
            ZStack {
                Color.black.ignoresSafeArea()

                MeshGradient(
                    width: 3, height: 3,
                    points: [
                        [0, 0], [0.5, 0], [1, 0],
                        [0, 0.5], [0.5, 0.5], [1, 0.5],
                        [0, 1], [0.5, 1], [1, 1]
                    ],
                    colors: [
                        .black, .black, .black,
                        Color.cyan.opacity(0.1), .black, Color.cyan.opacity(0.05),
                        .black, Color.cyan.opacity(0.08), .black
                    ]
                )
                .ignoresSafeArea()

                if focusScheduledConfirmed {
                    focusScheduledConfirmationContent
                } else {
                    focusScheduleChoiceContent
                }
            }
            .toolbar(.hidden, for: .navigationBar)
        }
        .presentationDetents([.large])
        .presentationDragIndicator(.hidden)
    }

    private var focusScheduleChoiceContent: some View {
        VStack(spacing: 0) {
            Spacer()

            VStack(spacing: 24) {
                ZStack {
                    Circle()
                        .fill(Color.cyan.opacity(0.12))
                        .frame(width: 100, height: 100)
                    Circle()
                        .stroke(Color.cyan.opacity(0.3), lineWidth: 2)
                        .frame(width: 100, height: 100)
                    Image(systemName: "timer")
                        .font(.system(size: 40, weight: .medium))
                        .foregroundStyle(.cyan)
                }

                VStack(spacing: 8) {
                    Text(quest.title)
                        .font(.title2.weight(.bold))
                        .foregroundStyle(.white)
                        .multilineTextAlignment(.center)
                    Text(focusFormatDuration(focusTargetDuration) + " Focus Block")
                        .font(.title3.weight(.semibold).monospacedDigit())
                        .foregroundStyle(.cyan)
                }
            }

            Spacer()
                .frame(height: 48)

            VStack(spacing: 14) {
                Button {
                    appState.acceptQuest(quest, mode: focusScheduleMode)
                    if let instance = appState.activeInstances.last(where: { $0.quest.id == quest.id }) {
                        appState.pendingFocusLaunchInstanceId = instance.id
                    }
                    showFocusSchedule = false
                    dismiss()
                } label: {
                    HStack(spacing: 12) {
                        Image(systemName: "bolt.fill")
                            .font(.title3)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Focus Now")
                                .font(.headline.weight(.bold))
                            Text("Start the session immediately")
                                .font(.caption)
                                .foregroundStyle(.white.opacity(0.6))
                        }
                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.white.opacity(0.4))
                    }
                    .foregroundStyle(.white)
                    .padding(16)
                    .background(Color.cyan.opacity(0.15), in: .rect(cornerRadius: 14))
                    .overlay(
                        RoundedRectangle(cornerRadius: 14)
                            .stroke(Color.cyan.opacity(0.3), lineWidth: 1)
                    )
                }

                Button {
                    withAnimation(.spring(response: 0.4)) {
                        showFocusDatePicker.toggle()
                    }
                } label: {
                    HStack(spacing: 12) {
                        Image(systemName: "clock.badge")
                            .font(.title3)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Focus Later")
                                .font(.headline.weight(.bold))
                            Text("Schedule a time & get reminded")
                                .font(.caption)
                                .foregroundStyle(.white.opacity(0.6))
                        }
                        Spacer()
                        Image(systemName: showFocusDatePicker ? "chevron.down" : "chevron.right")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.white.opacity(0.4))
                    }
                    .foregroundStyle(.white)
                    .padding(16)
                    .background(Color.white.opacity(0.06), in: .rect(cornerRadius: 14))
                    .overlay(
                        RoundedRectangle(cornerRadius: 14)
                            .stroke(Color.white.opacity(0.1), lineWidth: 1)
                    )
                }

                if showFocusDatePicker {
                    VStack(spacing: 16) {
                        DatePicker(
                            "Select Time",
                            selection: $focusScheduledDate,
                            in: Date().addingTimeInterval(60)...,
                            displayedComponents: [.date, .hourAndMinute]
                        )
                        .datePickerStyle(.compact)
                        .tint(.cyan)
                        .colorScheme(.dark)
                        .labelsHidden()

                        HStack(spacing: 8) {
                            Image(systemName: "bell.fill")
                                .foregroundStyle(.cyan)
                                .font(.caption)
                            Text("You'll get a notification at **\(focusScheduledDate.formatted(date: .abbreviated, time: .shortened))**")
                                .font(.caption)
                                .foregroundStyle(.white.opacity(0.7))
                        }

                        Button {
                            appState.acceptQuest(quest, mode: focusScheduleMode)
                            if let instance = appState.activeInstances.last(where: { $0.quest.id == quest.id }) {
                                NotificationService.shared.scheduleFocusReminder(
                                    at: focusScheduledDate,
                                    questTitle: quest.title,
                                    instanceId: instance.id
                                )
                            }
                            withAnimation(.spring(response: 0.4)) {
                                focusScheduledConfirmed = true
                            }
                        } label: {
                            HStack(spacing: 10) {
                                Image(systemName: "bell.badge.fill")
                                Text("Schedule & Remind Me")
                            }
                            .font(.headline.weight(.bold))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(.cyan)
                    }
                    .padding(16)
                    .background(Color.white.opacity(0.06), in: .rect(cornerRadius: 14))
                    .transition(.opacity.combined(with: .move(edge: .top)))
                }

                Button {
                    appState.acceptQuest(quest, mode: focusScheduleMode)
                    showFocusSchedule = false
                    dismiss()
                } label: {
                    HStack(spacing: 12) {
                        Image(systemName: "tray.full")
                            .font(.title3)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Just Accept")
                                .font(.headline.weight(.bold))
                            Text("Add to active quests, start anytime")
                                .font(.caption)
                                .foregroundStyle(.white.opacity(0.6))
                        }
                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.white.opacity(0.4))
                    }
                    .foregroundStyle(.white)
                    .padding(16)
                    .background(Color.white.opacity(0.06), in: .rect(cornerRadius: 14))
                    .overlay(
                        RoundedRectangle(cornerRadius: 14)
                            .stroke(Color.white.opacity(0.1), lineWidth: 1)
                    )
                }
            }
            .padding(.horizontal, 20)

            Spacer()

            Button {
                showFocusSchedule = false
            } label: {
                Text("Cancel")
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.white.opacity(0.5))
            }
            .padding(.bottom, 40)
        }
    }

    private var focusScheduledConfirmationContent: some View {
        VStack(spacing: 0) {
            Spacer()

            VStack(spacing: 24) {
                ZStack {
                    Circle()
                        .fill(Color.green.opacity(0.12))
                        .frame(width: 100, height: 100)
                    Circle()
                        .stroke(Color.green.opacity(0.3), lineWidth: 2)
                        .frame(width: 100, height: 100)
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 48, weight: .medium))
                        .foregroundStyle(.green)
                        .symbolEffect(.bounce, value: focusScheduledConfirmed)
                }

                VStack(spacing: 8) {
                    Text("SCHEDULED")
                        .font(.title.weight(.black))
                        .foregroundStyle(.white)
                        .tracking(3)
                    Text(focusScheduledDate.formatted(date: .abbreviated, time: .shortened))
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(.cyan)
                }

                VStack(spacing: 6) {
                    HStack(spacing: 8) {
                        Image(systemName: "bell.fill")
                            .foregroundStyle(.cyan)
                        Text("You'll be notified when it's time")
                            .foregroundStyle(.white.opacity(0.7))
                    }
                    .font(.subheadline)

                    Text("You can also start early from your active quests")
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.4))
                }
            }

            Spacer()

            Button {
                showFocusSchedule = false
                dismiss()
            } label: {
                Text("Done")
                    .font(.headline.weight(.bold))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
            }
            .buttonStyle(.borderedProminent)
            .tint(.cyan)
            .padding(.horizontal, 20)
            .padding(.bottom, 40)
        }
        .sensoryFeedback(.success, trigger: focusScheduledConfirmed)
    }
}
