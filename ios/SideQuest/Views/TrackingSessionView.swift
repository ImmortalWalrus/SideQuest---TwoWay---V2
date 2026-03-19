import SwiftUI
import MapKit

struct TrackingSessionView: View {
    let quest: Quest
    let instanceId: String
    let appState: AppState
    @Environment(\.dismiss) private var dismiss
    @State private var trackingService = LocationTrackingService()
    @State private var completedSession: TrackingSession?
    @State private var cameraPosition: MapCameraPosition = .userLocation(fallback: .automatic)
    @State private var showDiscardConfirm: Bool = false
    @State private var pulseGoal: Bool = false
    @State private var showDQAlert: Bool = false

    private var currentInstance: QuestInstance? {
        appState.activeInstances.first { $0.id == instanceId }
    }

    private var pathColor: Color {
        PathColorHelper.color(for: quest.path)
    }

    private var targetDistance: Double {
        quest.targetDistanceMiles ?? 1.0
    }

    private var totalTrackedDistance: Double {
        trackingService.distanceMiles + trackingService.pedometerEstimatedDistanceMiles
    }

    private var progress: Double {
        guard targetDistance > 0 else { return 0 }
        return min(1.0, totalTrackedDistance / targetDistance)
    }

    private var routeCoordinates: [CLLocationCoordinate2D] {
        trackingService.routePoints.map {
            CLLocationCoordinate2D(latitude: $0.latitude, longitude: $0.longitude)
        }
    }

    private var timeLimitProgress: Double? {
        guard let limit = quest.timeLimitSeconds, limit > 0 else { return nil }
        return min(1.0, trackingService.elapsedSeconds / limit)
    }

    var body: some View {
        NavigationStack {
            if let session = completedSession {
                SessionSummaryView(
                    session: session,
                    quest: quest,
                    isGroupRun: currentInstance?.mode != .solo && (currentInstance?.groupSize ?? 1) > 1,
                    handshakeVerified: currentInstance?.handshakeVerified ?? false,
                    groupSize: currentInstance?.groupSize ?? 1,
                    onSubmit: {
                        appState.submitTrackingEvidence(for: instanceId, session: session)
                        dismiss()
                    },
                    onDiscard: {
                        dismiss()
                    }
                )
            } else {
                trackingContent
            }
        }
        .interactiveDismissDisabled(trackingService.isTracking || trackingService.isPaused)
        .onAppear {
            trackingService.configure(
                targetDistance: targetDistance,
                maxPause: quest.maxPauseMinutes,
                maxSpeed: quest.maxSpeedMph,
                timeLimit: quest.timeLimitSeconds
            )
            if !trackingService.locationAuthorized {
                trackingService.requestPermission()
            }
            appState.isImmersive = true
        }
        .onDisappear {
            appState.isImmersive = false
        }
        .sensoryFeedback(.success, trigger: trackingService.goalReached)
        .sensoryFeedback(.error, trigger: trackingService.isDisqualified)
        .onChange(of: trackingService.goalReached) { _, reached in
            if reached {
                withAnimation(.easeInOut(duration: 0.8).repeatForever(autoreverses: true)) {
                    pulseGoal = true
                }
            }
        }
        .onChange(of: trackingService.isDisqualified) { _, dq in
            if dq {
                showDQAlert = true
            }
        }
        .alert("Session Disqualified", isPresented: $showDQAlert) {
            Button("View Summary") {
                let session = trackingService.endTracking()
                withAnimation(.spring(response: 0.4)) {
                    completedSession = session
                }
            }
            Button("Dismiss", role: .cancel) {
                dismiss()
            }
        } message: {
            Text(trackingService.disqualificationReason ?? "Anti-cheat violation detected.")
        }
    }

    private var trackingContent: some View {
        mapView
            .overlay {
                if trackingService.isPaused {
                    Color.black.opacity(0.3)
                        .overlay {
                            Text("PAUSED")
                                .font(.title.weight(.heavy))
                                .foregroundStyle(.white)
                                .padding(.horizontal, 24)
                                .padding(.vertical, 12)
                                .background(.ultraThinMaterial, in: Capsule())
                        }
                        .allowsHitTesting(false)
                }
            }
            .overlay(alignment: .top) {
                if trackingService.speedWarningActive && !trackingService.isDisqualified {
                    speedWarningBanner
                        .transition(.move(edge: .top).combined(with: .opacity))
                }
            }
            .safeAreaInset(edge: .bottom) {
                controlPanel
            }
            .navigationTitle(quest.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    if !trackingService.isTracking && !trackingService.isPaused {
                        Button("Close") { dismiss() }
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    if trackingService.isTracking || trackingService.isPaused {
                        HStack(spacing: 8) {
                            if quest.hasTimeWindow {
                                Image(systemName: "clock.badge.checkmark.fill")
                                    .font(.caption)
                                    .foregroundStyle(quest.isWithinTimeWindow ? .green : .orange)
                            }
                            if quest.isTimedChallenge, let remaining = trackingService.timeLimitRemaining {
                                Label(formatDuration(remaining), systemImage: "timer")
                                    .font(.subheadline.monospacedDigit().weight(.bold))
                                    .foregroundStyle(remaining < 60 ? .red : remaining < 120 ? .orange : pathColor)
                            } else {
                                Text(formatDuration(trackingService.elapsedSeconds))
                                    .font(.subheadline.monospacedDigit().weight(.semibold))
                                    .foregroundStyle(pathColor)
                            }
                        }
                    }
                }
            }
    }

    private var speedWarningBanner: some View {
        HStack(spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.yellow)
            Text("Slow down — speed limit \(Int(quest.maxSpeedMph)) mph")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.white)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(.red.opacity(0.85), in: Capsule())
        .padding(.top, 8)
        .animation(.spring(response: 0.3), value: trackingService.speedWarningActive)
    }

    private var mapView: some View {
        Map(position: $cameraPosition) {
            if routeCoordinates.count >= 2 {
                MapPolyline(coordinates: routeCoordinates)
                    .stroke(pathColor.gradient, lineWidth: 5)
            }
            UserAnnotation()
        }
        .mapStyle(.standard(elevation: .realistic))
        .mapControls {
            MapUserLocationButton()
            MapCompass()
        }
    }

    private var controlPanel: some View {
        VStack(spacing: 16) {
            if trackingService.isTracking || trackingService.isPaused {
                if quest.isTimedChallenge {
                    timeLimitBar
                }
                progressSection
                statsRow
            } else {
                readyInfo
            }
            controlButtons
        }
        .padding(20)
        .padding(.bottom, 8)
        .background(.ultraThinMaterial)
    }

    @ViewBuilder
    private var timeLimitBar: some View {
        if let remaining = trackingService.timeLimitRemaining, let limit = quest.timeLimitSeconds {
            VStack(spacing: 4) {
                HStack {
                    Label("TIME LIMIT", systemImage: "timer")
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text(formatDuration(remaining))
                        .font(.subheadline.monospacedDigit().weight(.heavy))
                        .foregroundStyle(remaining < 60 ? .red : remaining < 120 ? .orange : .primary)
                }
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        RoundedRectangle(cornerRadius: 4)
                            .fill(Color(.systemGray5))
                        RoundedRectangle(cornerRadius: 4)
                            .fill(
                                remaining < 60
                                    ? Color.red.gradient
                                    : remaining < 120
                                        ? Color.orange.gradient
                                        : pathColor.gradient
                            )
                            .frame(width: geo.size.width * (1.0 - (trackingService.elapsedSeconds / limit)))
                            .animation(.linear(duration: 1), value: trackingService.elapsedSeconds)
                    }
                }
                .frame(height: 6)
            }
        }
    }

    private var readyInfo: some View {
        VStack(spacing: 8) {
            HStack(spacing: 8) {
                PathBadgeView(path: quest.path)
                if quest.type == .verified {
                    VerifiedBadge(isVerified: true)
                }
                if quest.isExtreme {
                    Text("EXTREME")
                        .font(.caption2.weight(.black))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(.red.gradient, in: Capsule())
                }
            }

            Text("\(quest.isExtreme ? "Run" : "Walk") \(String(format: "%.2f", targetDistance)) miles")
                .font(.title3.weight(.semibold))

            if quest.isTimedChallenge, let desc = quest.timeLimitDescription {
                Label("Complete within \(desc)", systemImage: "timer")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.red)
            }

            Label("GPS Tracking Session", systemImage: "location.fill")
                .font(.caption)
                .foregroundStyle(.secondary)

            HStack(spacing: 16) {
                Label("Max \(Int(quest.maxSpeedMph)) mph", systemImage: "speedometer")
                if quest.maxPauseMinutes > 0 {
                    Label("Pause \(quest.maxPauseMinutes)m max", systemImage: "pause.circle")
                } else {
                    Label("No pausing", systemImage: "pause.circle")
                }
            }
            .font(.caption2.weight(.medium))
            .foregroundStyle(.secondary)

            if quest.hasTimeWindow {
                timeWindowBanner
            }
        }
    }

    @ViewBuilder
    private var timeWindowBanner: some View {
        HStack(spacing: 8) {
            Image(systemName: quest.isWithinTimeWindow ? "clock.badge.checkmark.fill" : "clock.badge.exclamationmark.fill")
                .foregroundStyle(quest.isWithinTimeWindow ? .green : .orange)
            VStack(alignment: .leading, spacing: 2) {
                if let desc = quest.timeWindowDescription {
                    Text(desc)
                        .font(.caption.weight(.semibold))
                }
                Text(quest.isWithinTimeWindow ? "Window is open" : "Outside time window")
                    .font(.caption2)
                    .foregroundStyle(quest.isWithinTimeWindow ? .green : .orange)
            }
            Spacer()
        }
        .padding(10)
        .background(
            (quest.isWithinTimeWindow ? Color.green : Color.orange).opacity(0.1),
            in: .rect(cornerRadius: 10)
        )
    }

    private var progressSection: some View {
        VStack(spacing: 6) {
            HStack {
                Text("\(formatDistance(totalTrackedDistance)) / \(formatDistance(targetDistance)) mi")
                    .font(.subheadline.monospacedDigit().weight(.semibold))
                Spacer()
                if trackingService.goalReached {
                    Label("Goal Reached!", systemImage: "checkmark.circle.fill")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(.green)
                        .transition(.scale.combined(with: .opacity))
                }
            }

            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 4)
                        .fill(Color(.systemGray5))
                    RoundedRectangle(cornerRadius: 4)
                        .fill(
                            trackingService.goalReached
                                ? Color.green.gradient
                                : pathColor.gradient
                        )
                        .frame(width: geo.size.width * progress)
                        .animation(.spring(response: 0.4), value: progress)
                }
            }
            .frame(height: 8)
        }
    }

    private var statsRow: some View {
        HStack(spacing: 0) {
            statItem(
                value: formatDistance(totalTrackedDistance),
                label: "DISTANCE",
                unit: "mi"
            )

            Divider().frame(height: 36)

            statItem(
                value: formatDuration(trackingService.elapsedSeconds),
                label: "TIME",
                unit: nil
            )

            Divider().frame(height: 36)

            statItem(
                value: formatPace(trackingService.elapsedSeconds, miles: totalTrackedDistance),
                label: "PACE",
                unit: "/mi"
            )

            Divider().frame(height: 36)

            statItem(
                value: trackingService.sessionSteps.formatted(),
                label: "STEPS",
                unit: nil
            )
        }
    }

    private func statItem(value: String, label: String, unit: String?) -> some View {
        VStack(spacing: 4) {
            HStack(spacing: 2) {
                Text(value)
                    .font(.title3.monospacedDigit().weight(.bold))
                if let unit {
                    Text(unit)
                        .font(.caption2.weight(.medium))
                        .foregroundStyle(.secondary)
                }
            }
            Text(label)
                .font(.caption2.weight(.medium))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
    }

    @ViewBuilder
    private var controlButtons: some View {
        if !trackingService.isTracking && !trackingService.isPaused {
            if !trackingService.locationAuthorized {
                Button {
                    trackingService.requestPermission()
                } label: {
                    Label("Enable Location", systemImage: "location.fill")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 6)
                }
                .buttonStyle(.borderedProminent)
                .tint(.orange)
            } else {
                Button {
                    withAnimation(.spring(response: 0.3)) {
                        trackingService.startTracking()
                    }
                } label: {
                    Label("Start", systemImage: "play.fill")
                        .font(.title3.weight(.bold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                }
                .buttonStyle(.borderedProminent)
                .tint(quest.isExtreme ? .red : pathColor)
            }
        } else if trackingService.isPaused {
            HStack(spacing: 12) {
                Button {
                    withAnimation(.spring(response: 0.3)) {
                        trackingService.resumeTracking()
                    }
                } label: {
                    Label("Resume", systemImage: "play.fill")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 6)
                }
                .buttonStyle(.borderedProminent)
                .tint(pathColor)

                Button {
                    endSession()
                } label: {
                    Label("End", systemImage: "stop.fill")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 6)
                }
                .buttonStyle(.bordered)
            }
        } else {
            HStack(spacing: 12) {
                if quest.maxPauseMinutes > 0 {
                    Button {
                        withAnimation(.spring(response: 0.3)) {
                            trackingService.pauseTracking()
                        }
                    } label: {
                        Label("Pause", systemImage: "pause.fill")
                            .font(.headline)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 6)
                    }
                    .buttonStyle(.bordered)
                }

                Button {
                    endSession()
                } label: {
                    Label(
                        trackingService.goalReached ? "End \(quest.isExtreme ? "Run" : "Walk")" : "End",
                        systemImage: trackingService.goalReached ? "checkmark.circle.fill" : "stop.fill"
                    )
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 6)
                }
                .buttonStyle(.borderedProminent)
                .tint(trackingService.goalReached ? .green : .secondary)
                .scaleEffect(pulseGoal && trackingService.goalReached ? 1.03 : 1.0)
            }
        }
    }

    private func endSession() {
        let session = trackingService.endTracking()
        withAnimation(.spring(response: 0.4)) {
            completedSession = session
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

    private func formatDistance(_ miles: Double) -> String {
        String(format: "%.2f", miles)
    }

    private func formatPace(_ seconds: TimeInterval, miles: Double) -> String {
        guard miles > 0.01 else { return "--'--\"" }
        let paceSeconds = seconds / miles
        let m = Int(paceSeconds) / 60
        let s = Int(paceSeconds) % 60
        return String(format: "%d'%02d\"", m, s)
    }

}
