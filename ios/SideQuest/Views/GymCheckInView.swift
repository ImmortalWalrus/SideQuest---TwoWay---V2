import SwiftUI
import CoreLocation

struct GymCheckInView: View {
    let quest: Quest
    let instanceId: String
    let appState: AppState
    @Environment(\.dismiss) private var dismiss

    @State private var phase: GymCheckInPhase = .intro
    @State private var locationManager = GymLocationManager()
    @State private var elapsedSeconds: Int = 0
    @State private var timerTask: Task<Void, Never>?
    @State private var showSubmitConfirm: Bool = false
    @State private var showSetGymSheet: Bool = false
    @State private var gymSearchText: String = ""
    @State private var pulsing: Bool = false

    private var placeType: VerifiedPlaceType {
        quest.requiredPlaceType ?? .gym
    }

    private var hasDefaultGym: Bool {
        appState.savedGym != nil
    }

    private var requiredSeconds: Int {
        max(60, quest.effectivePresenceMinutes * 60)
    }

    private var isGymCheckIn: Bool {
        placeType == .gym
    }

    private var targetCoordinate: CLLocationCoordinate2D? {
        if isGymCheckIn {
            return appState.savedGym?.coordinate
        }
        guard let latitude = quest.verificationLatitude,
              let longitude = quest.verificationLongitude else {
            return nil
        }
        return CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }

    private var targetVenueLine: String? {
        if isGymCheckIn {
            return appState.savedGym?.name
        }
        return quest.verificationAddressText ?? quest.verificationVenueName
    }

    private var heroTitle: String {
        isGymCheckIn ? "Gym GPS Check-In" : "Location Check-In"
    }

    private var heroSubtitle: String {
        isGymCheckIn ? "Location-based verification" : "\(placeType.rawValue) verification"
    }

    private var heroDescription: String {
        "Stay on-site for at least \(quest.effectivePresenceMinutes) minute\(quest.effectivePresenceMinutes == 1 ? "" : "s"). GPS tracks your presence by location, and no photo is required."
    }

    private var targetLabel: String {
        isGymCheckIn ? "Gym" : placeType.rawValue
    }

    private var progressFraction: Double {
        min(1.0, Double(elapsedSeconds) / Double(requiredSeconds))
    }

    private var timeRemaining: String {
        let remaining = max(0, requiredSeconds - elapsedSeconds)
        let mins = remaining / 60
        let secs = remaining % 60
        return String(format: "%d:%02d", mins, secs)
    }

    private var isComplete: Bool {
        elapsedSeconds >= requiredSeconds
    }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            RadialGradient(
                colors: [Color.orange.opacity(0.12), Color.clear],
                center: .center,
                startRadius: 0,
                endRadius: 380
            )
            .ignoresSafeArea()
            .allowsHitTesting(false)

            switch phase {
            case .intro:
                introContent
            case .tracking:
                trackingContent
            case .completed:
                completedContent
            case .outOfRange:
                outOfRangeContent
            }
        }
        .ignoresSafeArea(edges: .bottom)
        .toolbar(.hidden, for: .navigationBar)
        .onAppear { appState.isImmersive = true }
        .onDisappear {
            timerTask?.cancel()
            appState.isImmersive = false
        }
        .sheet(isPresented: $showSetGymSheet) {
            SetDefaultGymSheet(appState: appState)
        }
        .alert("Submit Verification?", isPresented: $showSubmitConfirm) {
            Button("Submit") {
                submitGymCheckin()
                appState.submitEvidence(for: instanceId)
                dismiss()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Your gym check-in will be submitted as evidence.")
        }
    }

    private var introContent: some View {
        VStack(spacing: 0) {
            HStack {
                Button {
                    dismiss()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.title2)
                        .foregroundStyle(.white.opacity(0.6))
                }
                Spacer()
            }
            .padding(.horizontal, 20)
            .padding(.top, 60)

            Spacer()

            VStack(spacing: 32) {
                ZStack {
                    Circle()
                        .fill(Color.orange.opacity(0.12))
                        .frame(width: 120, height: 120)
                    Circle()
                        .strokeBorder(Color.orange.opacity(0.4), lineWidth: 2)
                        .frame(width: 120, height: 120)
                    Image(systemName: "dumbbell.fill")
                        .font(.system(size: 48, weight: .medium))
                        .foregroundStyle(.orange)
                        .symbolEffect(.bounce, value: phase)
                }

                VStack(spacing: 12) {
                    Text(heroTitle)
                        .font(.title.weight(.black))
                        .foregroundStyle(.white)
                        .tracking(1)

                    Text(heroSubtitle)
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(.orange)

                    Text(heroDescription)
                        .font(.subheadline)
                        .foregroundStyle(.white.opacity(0.6))
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.horizontal, 16)
                }

                VStack(spacing: 10) {
                    infoBadge(icon: "location.fill", text: "GPS verifies you're at the venue")
                    infoBadge(icon: "timer", text: "\(quest.effectivePresenceMinutes) minute minimum presence")
                    infoBadge(icon: "checkmark.shield.fill", text: "No photo or camera required")
                }

                if isGymCheckIn, let gym = appState.savedGym {
                    HStack(spacing: 10) {
                        Image(systemName: "mappin.circle.fill")
                            .foregroundStyle(.green)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Default Gym")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.white.opacity(0.5))
                            Text(gym.name)
                                .font(.subheadline.weight(.medium))
                                .foregroundStyle(.white)
                        }
                        Spacer()
                        Button {
                            showSetGymSheet = true
                        } label: {
                            Text("Change")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.orange)
                        }
                    }
                    .padding(12)
                    .background(.white.opacity(0.06), in: .rect(cornerRadius: 12))
                    .padding(.horizontal, 20)
                } else if isGymCheckIn {
                    Button {
                        showSetGymSheet = true
                    } label: {
                        HStack(spacing: 8) {
                            Image(systemName: "mappin.and.ellipse")
                                .font(.subheadline)
                            Text("Set Default Gym")
                                .font(.subheadline.weight(.semibold))
                        }
                        .foregroundStyle(.orange)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 10)
                        .background(.orange.opacity(0.12), in: Capsule())
                    }
                    .buttonStyle(.plain)
                }
            }

            Spacer()

            VStack(spacing: 12) {
                Button {
                    startTracking()
                } label: {
                    HStack(spacing: 10) {
                        Image(systemName: "location.fill")
                            .font(.headline)
                        Text("Start Check-In")
                            .font(.headline.weight(.bold))
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                    .background(.orange, in: .rect(cornerRadius: 16))
                    .foregroundStyle(.white)
                }
                .buttonStyle(.plain)
                .sensoryFeedback(.impact(weight: .medium), trigger: phase)

                Button("Cancel") { dismiss() }
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.white.opacity(0.4))
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 48)
        }
    }

    private var trackingContent: some View {
        VStack(spacing: 0) {
            HStack {
                Button {
                    timerTask?.cancel()
                    withAnimation(.snappy) { phase = .intro }
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "chevron.left")
                            .font(.subheadline.weight(.semibold))
                        Text("Stop")
                            .font(.subheadline.weight(.medium))
                    }
                    .foregroundStyle(.white)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .background(.black.opacity(0.45), in: Capsule())
                }
                .buttonStyle(.plain)

                Spacer()

                Label(targetLabel, systemImage: placeType.icon)
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.orange)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(.black.opacity(0.5), in: Capsule())
            }
            .padding(.horizontal, 20)
            .padding(.top, 60)

            Spacer()

            VStack(spacing: 36) {
                ZStack {
                    Circle()
                        .stroke(Color.white.opacity(0.06), lineWidth: 8)
                        .frame(width: 200, height: 200)

                    Circle()
                        .trim(from: 0, to: progressFraction)
                        .stroke(
                            LinearGradient(colors: [.orange, .yellow], startPoint: .topLeading, endPoint: .bottomTrailing),
                            style: StrokeStyle(lineWidth: 8, lineCap: .round)
                        )
                        .frame(width: 200, height: 200)
                        .rotationEffect(.degrees(-90))
                        .animation(.easeInOut(duration: 1), value: progressFraction)

                    VStack(spacing: 8) {
                        Text(timeRemaining)
                            .font(.system(size: 44, weight: .black, design: .monospaced))
                            .foregroundStyle(.white)
                            .contentTransition(.numericText())

                        Text(isComplete ? "COMPLETE" : "remaining")
                            .font(.caption.weight(.bold))
                            .foregroundStyle(isComplete ? .green : .orange)
                            .tracking(1)
                    }
                }

                if locationManager.isInRange {
                    HStack(spacing: 8) {
                        Circle()
                            .fill(.green)
                            .frame(width: 8, height: 8)
                            .scaleEffect(pulsing ? 1.3 : 1.0)
                            .animation(.easeInOut(duration: 0.8).repeatForever(autoreverses: true), value: pulsing)
                            .onAppear { pulsing = true }
                        Text(isGymCheckIn ? "At gym location" : "At venue location")
                            .font(.subheadline.weight(.medium))
                            .foregroundStyle(.green)
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .background(.green.opacity(0.12), in: Capsule())
                } else {
                    HStack(spacing: 8) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundStyle(.yellow)
                        Text(isGymCheckIn ? "Move closer to your gym" : "Move closer to the venue")
                            .font(.subheadline.weight(.medium))
                            .foregroundStyle(.yellow)
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .background(.yellow.opacity(0.12), in: Capsule())
                }

                if let venueLine = targetVenueLine {
                    HStack(spacing: 6) {
                        Image(systemName: "mappin.circle.fill")
                            .foregroundStyle(.orange.opacity(0.6))
                        Text(venueLine)
                            .font(.caption.weight(.medium))
                            .foregroundStyle(.white.opacity(0.5))
                    }
                }
            }

            Spacer()

            if isComplete {
                VStack(spacing: 10) {
                    Button {
                        withAnimation(.spring(duration: 0.5)) { phase = .completed }
                    } label: {
                        Label("Complete Check-In", systemImage: "checkmark.circle.fill")
                            .font(.headline.weight(.bold))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 16)
                            .background(.green, in: .rect(cornerRadius: 16))
                            .foregroundStyle(.white)
                    }
                    .buttonStyle(.plain)
                    .sensoryFeedback(.success, trigger: isComplete)
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 48)
            } else {
                Text("Keep the app open during check-in")
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.25))
                    .padding(.bottom, 48)
            }
        }
    }

    private var completedContent: some View {
        VStack(spacing: 0) {
            Spacer()

            VStack(spacing: 28) {
                ZStack {
                    Circle()
                        .fill(Color.green.opacity(0.12))
                        .frame(width: 100, height: 100)
                    Circle()
                        .strokeBorder(Color.green.opacity(0.4), lineWidth: 2)
                        .frame(width: 100, height: 100)
                    Image(systemName: "checkmark.seal.fill")
                        .font(.system(size: 44, weight: .medium))
                        .foregroundStyle(.green)
                        .symbolEffect(.bounce, value: phase)
                }

                VStack(spacing: 10) {
                    Text(isGymCheckIn ? "GYM VERIFIED" : "LOCATION VERIFIED")
                        .font(.title2.weight(.black))
                        .foregroundStyle(.white)
                        .tracking(2)

                    Text("\(max(quest.effectivePresenceMinutes, elapsedSeconds / 60))+ minutes on-site")
                        .font(.headline)
                        .foregroundStyle(.orange)
                }

                VStack(spacing: 0) {
                    completedRow(icon: "location.fill", color: .blue, text: "GPS location confirmed")
                    Divider().background(.white.opacity(0.08))
                    completedRow(icon: "timer", color: .orange, text: "\(elapsedSeconds / 60) min presence verified")
                    Divider().background(.white.opacity(0.08))
                    completedRow(icon: "checkmark.shield.fill", color: .green, text: "Check-in validated")
                }
                .background(.white.opacity(0.05), in: .rect(cornerRadius: 14))
                .padding(.horizontal, 20)
            }

            Spacer()

            VStack(spacing: 10) {
                Button {
                    showSubmitConfirm = true
                } label: {
                    Label("Submit Evidence", systemImage: "paperplane.fill")
                        .font(.headline.weight(.bold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                        .background(.green, in: .rect(cornerRadius: 16))
                        .foregroundStyle(.white)
                }
                .buttonStyle(.plain)
                .sensoryFeedback(.success, trigger: showSubmitConfirm)

                Button("Cancel") { dismiss() }
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.white.opacity(0.4))
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 48)
        }
    }

    private var outOfRangeContent: some View {
        VStack(spacing: 0) {
            Spacer()

            VStack(spacing: 28) {
                ZStack {
                    Circle()
                        .fill(Color.yellow.opacity(0.12))
                        .frame(width: 100, height: 100)
                    Image(systemName: "location.slash.fill")
                        .font(.system(size: 44))
                        .foregroundStyle(.yellow)
                }

                VStack(spacing: 10) {
                    Text(isGymCheckIn ? "NOT AT GYM" : "NOT IN RANGE")
                        .font(.title2.weight(.black))
                        .foregroundStyle(.white)
                        .tracking(2)

                    Text("GPS couldn't verify your location. Make sure you're within \(placeType.gpsRadiusMeters)m of \(targetVenueLine ?? placeType.rawValue).")
                        .font(.subheadline)
                        .foregroundStyle(.white.opacity(0.5))
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 24)
                }

                if isGymCheckIn, !hasDefaultGym {
                    Button {
                        showSetGymSheet = true
                    } label: {
                        HStack(spacing: 8) {
                            Image(systemName: "mappin.and.ellipse")
                            Text("Set Your Default Gym")
                        }
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.orange)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 10)
                        .background(.orange.opacity(0.12), in: Capsule())
                    }
                    .buttonStyle(.plain)
                }
            }

            Spacer()

            VStack(spacing: 10) {
                Button {
                    withAnimation(.snappy) { phase = .intro }
                } label: {
                    Label("Try Again", systemImage: "arrow.counterclockwise")
                        .font(.headline.weight(.bold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                        .background(.orange, in: .rect(cornerRadius: 16))
                        .foregroundStyle(.white)
                }
                .buttonStyle(.plain)

                Button("Cancel") { dismiss() }
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.white.opacity(0.4))
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 48)
        }
    }

    private func startTracking() {
        locationManager.startTracking(gymLocation: targetCoordinate, radiusMeters: Double(placeType.gpsRadiusMeters))

        Task { @MainActor in
            try? await Task.sleep(for: .seconds(2))

            #if targetEnvironment(simulator)
            locationManager.isInRange = true
            #endif

            guard locationManager.isInRange else {
                withAnimation(.snappy) { phase = .outOfRange }
                return
            }

            withAnimation(.snappy) { phase = .tracking }
            elapsedSeconds = 0

            timerTask = Task { @MainActor in
                while !Task.isCancelled {
                    try? await Task.sleep(for: .seconds(1))
                    guard !Task.isCancelled else { return }
                    if locationManager.isInRange {
                        elapsedSeconds += 1
                    }
                }
            }
        }
    }

    private func submitGymCheckin() {
    }

    private func infoBadge(icon: String, text: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.subheadline)
                .foregroundStyle(.orange)
                .frame(width: 28)
            Text(text)
                .font(.subheadline)
                .foregroundStyle(.white.opacity(0.6))
            Spacer()
        }
        .padding(.horizontal, 20)
    }

    private func completedRow(icon: String, color: Color, text: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.subheadline)
                .foregroundStyle(color)
                .frame(width: 28)
            Text(text)
                .font(.subheadline)
                .foregroundStyle(.white.opacity(0.7))
            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }
}

nonisolated enum GymCheckInPhase: Equatable {
    case intro
    case tracking
    case completed
    case outOfRange
}

@Observable
class GymLocationManager: NSObject, CLLocationManagerDelegate {
    var isInRange: Bool = false
    var currentLocation: CLLocation?

    private let manager = CLLocationManager()
    private var targetLocation: CLLocationCoordinate2D?
    private var radiusMeters: Double = 75

    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyBest
    }

    func startTracking(gymLocation: CLLocationCoordinate2D?, radiusMeters: Double) {
        self.targetLocation = gymLocation
        self.radiusMeters = radiusMeters
        manager.requestWhenInUseAuthorization()
        manager.startUpdatingLocation()
    }

    func stopTracking() {
        manager.stopUpdatingLocation()
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let location = locations.last else { return }
        Task { @MainActor in
            currentLocation = location
            if let target = targetLocation {
                let targetLoc = CLLocation(latitude: target.latitude, longitude: target.longitude)
                let distance = location.distance(from: targetLoc)
                isInRange = distance <= radiusMeters
            } else {
                isInRange = true
            }
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
    }
}

struct SetDefaultGymSheet: View {
    let appState: AppState
    @Environment(\.dismiss) private var dismiss
    @State private var searchText: String = ""
    @State private var searchResults: [GymSearchResult] = []
    @State private var isSearching: Bool = false
    @State private var locationManager = GymLocationManager()
    @State private var useCurrentLocation: Bool = false

    var body: some View {
        NavigationStack {
            List {
                if let currentGym = appState.savedGym {
                    Section {
                        HStack(spacing: 12) {
                            Image(systemName: "dumbbell.fill")
                                .foregroundStyle(.orange)
                                .frame(width: 32)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(currentGym.name)
                                    .font(.subheadline.weight(.semibold))
                                Text("Current default gym")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundStyle(.green)
                        }
                    } header: {
                        Text("Current Gym")
                    }

                    Section {
                        Button(role: .destructive) {
                            appState.setSavedGym(nil)
                            dismiss()
                        } label: {
                            Label("Remove Default Gym", systemImage: "trash")
                        }
                    }
                }

                Section {
                    Button {
                        setCurrentLocationAsGym()
                    } label: {
                        HStack(spacing: 12) {
                            Image(systemName: "location.fill")
                                .foregroundStyle(.blue)
                                .frame(width: 32)
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Use Current Location")
                                    .font(.subheadline.weight(.semibold))
                                Text("Set wherever you are now as your gym")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                } header: {
                    Text("Set Gym")
                } footer: {
                    Text("Go to your gym and tap \"Use Current Location\" to set it. Your GPS coordinates will be saved for future check-ins.")
                }

                Section {
                    ForEach(sampleGyms) { gym in
                        Button {
                            appState.setSavedGym(SavedGym(
                                name: gym.name,
                                latitude: gym.latitude,
                                longitude: gym.longitude,
                                savedAt: .now
                            ))
                            dismiss()
                        } label: {
                            HStack(spacing: 12) {
                                Image(systemName: "mappin.circle.fill")
                                    .foregroundStyle(.orange)
                                    .frame(width: 32)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(gym.name)
                                        .font(.subheadline.weight(.semibold))
                                        .foregroundStyle(.primary)
                                    Text(gym.address)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                Spacer()
                            }
                        }
                    }
                } header: {
                    Text("Nearby Gyms")
                }
            }
            .navigationTitle("Default Gym")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .onAppear {
                locationManager.startTracking(gymLocation: nil, radiusMeters: 75)
            }
        }
    }

    private func setCurrentLocationAsGym() {
        locationManager.startTracking(gymLocation: nil, radiusMeters: 75)

        Task { @MainActor in
            try? await Task.sleep(for: .seconds(1))

            let lat: Double
            let lon: Double

            if let loc = locationManager.currentLocation {
                lat = loc.coordinate.latitude
                lon = loc.coordinate.longitude
            } else {
                lat = 37.7850
                lon = -122.4094
            }

            appState.setSavedGym(SavedGym(
                name: "My Gym",
                latitude: lat,
                longitude: lon,
                savedAt: .now
            ))
            dismiss()
        }
    }

    private var sampleGyms: [GymSearchResult] {
        [
            GymSearchResult(id: "g1", name: "Planet Fitness", address: "123 Main St", latitude: 37.7850, longitude: -122.4094),
            GymSearchResult(id: "g2", name: "Gold's Gym", address: "456 Oak Ave", latitude: 37.7860, longitude: -122.4080),
            GymSearchResult(id: "g3", name: "24 Hour Fitness", address: "789 Elm Blvd", latitude: 37.7840, longitude: -122.4110),
            GymSearchResult(id: "g4", name: "Anytime Fitness", address: "321 Pine St", latitude: 37.7870, longitude: -122.4060),
            GymSearchResult(id: "g5", name: "LA Fitness", address: "654 Maple Dr", latitude: 37.7830, longitude: -122.4130),
        ]
    }
}

nonisolated struct GymSearchResult: Identifiable, Sendable {
    let id: String
    let name: String
    let address: String
    let latitude: Double
    let longitude: Double
}
