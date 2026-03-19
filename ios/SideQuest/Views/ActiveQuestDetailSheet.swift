import SwiftUI
import MapKit

struct ActiveQuestDetailSheet: View {
    let instance: QuestInstance
    let appState: AppState
    let onSubmit: () -> Void
    let onDrop: () -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var poiService = MapPOIService()
    @State private var nearbyPOIs: [MapPOI] = []
    @State private var isLoadingPOIs: Bool = false
    @State private var hasFetchedPOIs: Bool = false
    @State private var showDropConfirm: Bool = false

    private var quest: Quest { instance.quest }

    private var pathColor: Color {
        PathColorHelper.color(for: quest.path)
    }

    private var placeType: VerifiedPlaceType? {
        quest.requiredPlaceType
    }

    private var mapCategory: MapQuestCategory? {
        placeType?.mapQuestCategory
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    headerSection
                    rewardSection

                    if quest.isPlaceVerificationQuest {
                        navigateSection
                    }

                    descriptionSection
                    actionSection
                }
                .padding(16)
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("Active Side Quest")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
            }
            .task {
                if quest.isPlaceVerificationQuest, let category = mapCategory, !hasFetchedPOIs {
                    await fetchNearbyPOIs(for: category)
                }
            }
        }
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
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
                Text("Active")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(.green)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(.green.opacity(0.12), in: Capsule())
            }

            Text(quest.title)
                .font(.title.weight(.bold))

            if let started = instance.startedAt as Date? {
                let elapsed = Date().timeIntervalSince(started)
                let minutes = Int(elapsed) / 60
                Label("Started \(minutes < 60 ? "\(minutes)m ago" : "\(minutes / 60)h ago")", systemImage: "clock.fill")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
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

    private var navigateSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Image(systemName: "location.fill")
                    .font(.headline)
                    .foregroundStyle(placeType?.accentColor ?? .blue)
                Text("Navigate to \(placeType?.rawValue ?? "Location")")
                    .font(.headline)
            }

            if isLoadingPOIs {
                HStack(spacing: 10) {
                    ProgressView()
                    Text("Finding nearby locations...")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(16)
                .background(Color(.secondarySystemGroupedBackground), in: .rect(cornerRadius: 14))
            } else if let firstPOI = nearbyPOIs.first {
                Button {
                    openInMaps(poi: firstPOI)
                } label: {
                    HStack(spacing: 14) {
                        ZStack {
                            RoundedRectangle(cornerRadius: 14)
                                .fill((placeType?.accentColor ?? .blue).opacity(0.15))
                                .frame(width: 56, height: 56)
                            Image(systemName: "arrow.triangle.turn.up.right.diamond.fill")
                                .font(.title2)
                                .foregroundStyle(placeType?.accentColor ?? .blue)
                        }

                        VStack(alignment: .leading, spacing: 4) {
                            Text("Navigate to \(firstPOI.name)")
                                .font(.headline)
                                .foregroundStyle(.primary)
                                .lineLimit(2)
                                .multilineTextAlignment(.leading)
                            if let address = firstPOI.address {
                                Text(address)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                            }
                            if let distance = firstPOI.distance {
                                Text(formatDistance(distance))
                                    .font(.caption.weight(.bold).monospacedDigit())
                                    .foregroundStyle(placeType?.accentColor ?? .blue)
                            }
                        }

                        Spacer()

                        Image(systemName: "chevron.right")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.secondary)
                    }
                    .padding(16)
                    .background(Color(.secondarySystemGroupedBackground), in: .rect(cornerRadius: 16))
                    .overlay(
                        RoundedRectangle(cornerRadius: 16)
                            .strokeBorder((placeType?.accentColor ?? .blue).opacity(0.3), lineWidth: 1.5)
                    )
                }
                .buttonStyle(.plain)

                if nearbyPOIs.count > 1 {
                    VStack(spacing: 0) {
                        ForEach(Array(nearbyPOIs.dropFirst().prefix(3).enumerated()), id: \.element.id) { index, poi in
                            Button {
                                openInMaps(poi: poi)
                            } label: {
                                poiRow(poi: poi)
                            }
                            .buttonStyle(.plain)

                            if index < min(nearbyPOIs.count - 1, 3) - 1 {
                                Divider()
                                    .padding(.leading, 48)
                            }
                        }
                    }
                    .background(Color(.secondarySystemGroupedBackground), in: .rect(cornerRadius: 14))
                }

                Button {
                    if let category = mapCategory {
                        appState.pendingMapCategory = category
                        appState.selectedTab = 2
                        dismiss()
                    }
                } label: {
                    HStack {
                        Image(systemName: "map.fill")
                            .font(.caption)
                        Text("See all on map")
                            .font(.subheadline.weight(.medium))
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                }
                .buttonStyle(.bordered)
                .tint(placeType?.accentColor ?? .blue)
            } else if hasFetchedPOIs {
                VStack(spacing: 10) {
                    Image(systemName: "location.slash")
                        .font(.title3)
                        .foregroundStyle(.secondary)
                    Text("No \(placeType?.rawValue.lowercased() ?? "location") found nearby")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)

                    Button {
                        if let category = mapCategory {
                            appState.pendingMapCategory = category
                            appState.selectedTab = 2
                            dismiss()
                        }
                    } label: {
                        Label("Search on Map", systemImage: "map.fill")
                            .font(.subheadline.weight(.semibold))
                    }
                    .buttonStyle(.bordered)
                    .tint(placeType?.accentColor ?? .blue)
                }
                .frame(maxWidth: .infinity)
                .padding(20)
                .background(Color(.secondarySystemGroupedBackground), in: .rect(cornerRadius: 14))
            }
        }
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

    private var actionSection: some View {
        VStack(spacing: 12) {
            if instance.state == .active {
                let outsideWindow = quest.hasTimeWindow && !quest.isWithinTimeWindow

                Button {
                    onSubmit()
                    dismiss()
                } label: {
                    Label(submitButtonLabel, systemImage: submitButtonIcon)
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(pathColor)
                .disabled(outsideWindow || !instance.canSubmit)

                if outsideWindow, let next = quest.nextWindowOpensDescription {
                    Label(next, systemImage: "clock.fill")
                        .font(.caption)
                        .foregroundStyle(.orange)
                } else if instance.isGPSAutoCheckInQuest && !instance.canSubmit {
                    let remaining = instance.timeUntilSubmit
                    let minutes = Int(remaining) / 60
                    let seconds = Int(remaining) % 60
                    Label(
                        instance.isAutoCheckInInRange
                            ? "Auto check-in active • \(minutes)m \(seconds)s left"
                            : "Arrive on-site to auto check in",
                        systemImage: instance.isAutoCheckInInRange ? "location.fill" : "location.slash"
                    )
                    .font(.caption)
                    .foregroundStyle(instance.isAutoCheckInInRange ? .green : .secondary)
                } else if !instance.canSubmit {
                    let remaining = instance.timeUntilSubmit
                    let minutes = Int(remaining) / 60
                    let seconds = Int(remaining) % 60
                    Label("Ready in \(minutes)m \(seconds)s", systemImage: "clock.fill")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Button(role: .destructive) {
                showDropConfirm = true
            } label: {
                Label("Drop Quest", systemImage: "xmark.circle")
                    .font(.subheadline.weight(.medium))
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .tint(.red)
            .confirmationDialog("Drop Quest?", isPresented: $showDropConfirm, titleVisibility: .visible) {
                Button("Drop \(quest.title)", role: .destructive) {
                    onDrop()
                    dismiss()
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("You'll lose progress on this quest.")
            }
        }
        .padding(.top, 8)
    }

    private var submitButtonLabel: String {
        if quest.isStepQuest { return "Check Steps" }
        if quest.isTrackingQuest { return "Start Tracking" }
        if quest.evidenceType == .pushUpTracking { return "Start Push-Ups" }
        if quest.evidenceType == .plankTracking { return "Start Plank" }
        if quest.evidenceType == .wallSitTracking { return "Start Wall Sit" }
        if quest.evidenceType == .jumpRopeTracking { return "Start Jump Rope" }
        if quest.isFocusQuest { return "Start Focus" }
        if quest.isGratitudeQuest { return "Log Entry" }
        if quest.isAffirmationQuest { return "Log Affirmations" }
        if quest.evidenceType == .dualPhoto { return "Take Photos" }
        if quest.isPlaceVerificationQuest {
            return quest.requiredPlaceType?.isGPSOnly == true ? "Submit Check-In" : "Start Verification"
        }
        return "Submit Evidence"
    }

    private var submitButtonIcon: String {
        if quest.isStepQuest { return "figure.walk" }
        if quest.isTrackingQuest { return "location.fill" }
        if quest.evidenceType == .pushUpTracking { return "figure.strengthtraining.traditional" }
        if quest.evidenceType == .plankTracking { return "figure.core.training" }
        if quest.evidenceType == .wallSitTracking { return "figure.seated.side" }
        if quest.evidenceType == .jumpRopeTracking { return "figure.jumprope" }
        if quest.isFocusQuest { return "timer" }
        if quest.isGratitudeQuest { return "square.and.pencil" }
        if quest.isAffirmationQuest { return "sparkles" }
        if quest.evidenceType == .dualPhoto { return "camera.fill" }
        if quest.isPlaceVerificationQuest { return "location.fill" }
        return "camera.fill"
    }

    private func poiRow(poi: MapPOI) -> some View {
        HStack(spacing: 12) {
            Image(systemName: mapCategory?.icon ?? "mappin")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 32, height: 32)
                .background(placeType?.accentColor ?? .blue, in: .rect(cornerRadius: 8))

            VStack(alignment: .leading, spacing: 2) {
                Text(poi.name)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                if let address = poi.address {
                    Text(address)
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                }
            }

            Spacer()

            if let distance = poi.distance {
                Text(formatDistance(distance))
                    .font(.caption.weight(.semibold).monospacedDigit())
                    .foregroundStyle(.secondary)
            }

            Image(systemName: "arrow.triangle.turn.up.right.diamond.fill")
                .font(.system(size: 14))
                .foregroundStyle(.blue)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
    }

    private func fetchNearbyPOIs(for category: MapQuestCategory) async {
        isLoadingPOIs = true
        if poiService.locationAuthorized {
            poiService.requestLocation()
            try? await Task.sleep(for: .seconds(2))
        }
        await poiService.searchPOIs(for: category)
        nearbyPOIs = poiService.pois
        isLoadingPOIs = false
        hasFetchedPOIs = true
    }

    private func formatDistance(_ meters: Double) -> String {
        if meters < 1000 {
            return "\(Int(meters))m"
        }
        return String(format: "%.1fkm", meters / 1000)
    }

    private func openInMaps(poi: MapPOI) {
        let placemark = MKPlacemark(coordinate: poi.coordinate)
        let mapItem = MKMapItem(placemark: placemark)
        mapItem.name = poi.name
        mapItem.openInMaps(launchOptions: [
            MKLaunchOptionsDirectionsModeKey: MKLaunchOptionsDirectionsModeWalking
        ])
    }
}
