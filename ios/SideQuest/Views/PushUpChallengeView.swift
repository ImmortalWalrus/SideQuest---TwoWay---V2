import SwiftUI
import UIKit
import AVFoundation

struct PushUpChallengeView: View {
    let quest: Quest
    let instanceId: String
    let appState: AppState
    @Environment(\.dismiss) private var dismiss
    @State private var cameraService = ExerciseCameraService()
    @State private var phase: PushUpPhase = .setup
    @State private var repCount: Int = 0
    @State private var elapsedSeconds: TimeInterval = 0
    @State private var startTime: Date?
    @State private var timer: Timer?
    @State private var completedSession: ExerciseSession?
    @State private var pulseGoal: Bool = false
    @State private var lastRepScale: CGFloat = 1.0
    @State private var bodyLostCount: Int = 0
    @State private var readyConfirmed: Bool = false
    @State private var countdownValue: Int = 0
    @State private var showCountdown: Bool = false
    @State private var countdownTick: Int = 0
    @State private var borderGlowOpacity: Double = 0
    @State private var autoStartTriggered: Bool = false

    private var targetReps: Int { quest.targetReps ?? 100 }
    private var pathColor: Color { PathColorHelper.color(for: quest.path) }
    private var goalReached: Bool { repCount >= targetReps }
    private var progress: Double { min(1.0, Double(repCount) / Double(max(1, targetReps))) }

    private var borderColor: Color {
        let label = cameraService.pushUpPhaseLabel
        if label == "Down" { return .orange }
        if label == "Up" { return .green }
        if label == "Fix Form!" || label == "Standing" || label == "Get Down" { return .red }
        return .clear
    }

    private var hasActiveWarning: Bool {
        phase == .active && (
            cameraService.displayKneesOnGround ||
            !cameraService.displayBodyDetected ||
            !cameraService.displayHeadDetected ||
            cameraService.displayStanding
        )
    }

    var body: some View {
        NavigationStack {
            if let session = completedSession {
                ExerciseSummaryView(
                    session: session,
                    quest: quest,
                    onSubmit: {
                        appState.submitExerciseEvidence(for: instanceId, session: session)
                        dismiss()
                    },
                    onDiscard: { dismiss() }
                )
            } else {
                mainContent
            }
        }
        .interactiveDismissDisabled(phase == .active)
        .persistentSystemOverlays(.hidden)
    }

    private var mainContent: some View {
        GeometryReader { geo in
            ZStack {
                cameraLayer
                phaseContent(size: geo.size)

                if showCountdown {
                    countdownOverlay
                }
            }
        }
        .background(Color(.systemGroupedBackground))
        .onAppear {
            appState.isImmersive = true
            lockPortrait()
            cameraService.configure()
            cameraService.start()
        }
        .onDisappear {
            timer?.invalidate()
            cameraService.stop()
            appState.isImmersive = false
            unlockOrientation()
        }
        .onChange(of: cameraService.pushUpCount) { _, newCount in
            guard phase == .active else { return }
            withAnimation(.spring(response: 0.2)) {
                repCount = newCount
                lastRepScale = 1.15
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                withAnimation(.spring(response: 0.2)) {
                    lastRepScale = 1.0
                }
            }
        }
        .onChange(of: cameraService.bodyDetected) { old, new in
            if old && !new && phase == .active {
                bodyLostCount += 1
            }
        }
        .onChange(of: cameraService.positioningReady) { _, ready in
            if ready && !readyConfirmed {
                readyConfirmed = true
            }
            if ready && phase == .setup && !autoStartTriggered && !showCountdown {
                autoStartTriggered = true
                beginCountdown()
            }
        }
        .onChange(of: goalReached) { _, reached in
            if reached {
                withAnimation(.easeInOut(duration: 0.8).repeatForever(autoreverses: true)) {
                    pulseGoal = true
                }
            }
        }
        .onChange(of: cameraService.pushUpPhaseLabel) { _, newLabel in
            guard phase == .active else { return }
            if newLabel == "Up" || newLabel == "Down" {
                withAnimation(.easeOut(duration: 0.15)) {
                    borderGlowOpacity = 0.8
                }
                withAnimation(.easeIn(duration: 0.6).delay(0.15)) {
                    borderGlowOpacity = 0.25
                }
            }
        }
        .sensoryFeedback(.impact(weight: .medium), trigger: repCount)
        .sensoryFeedback(.success, trigger: goalReached)
        .sensoryFeedback(.success, trigger: readyConfirmed)
        .sensoryFeedback(.impact(weight: .light), trigger: countdownTick)
        .sensoryFeedback(.warning, trigger: cameraService.displayStanding)
        .navigationTitle(quest.title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                if phase != .active {
                    Button("Close") { dismiss() }
                }
            }
            ToolbarItem(placement: .topBarTrailing) {
                if phase == .active {
                    Button("End", role: .destructive) { endSession() }
                        .fontWeight(.semibold)
                }
            }
        }
    }

    @ViewBuilder
    private var cameraLayer: some View {
        if cameraService.cameraAvailable {
            CameraPreviewView(session: cameraService.captureSession)
                .ignoresSafeArea()

            SkeletonOverlayView(
                joints: cameraService.jointPositions,
                bodyDetected: cameraService.bodyDetected,
                accentColor: pathColor,
                videoAspectRatio: cameraService.videoAspectRatio
            )
            .ignoresSafeArea()
        }
    }

    @ViewBuilder
    private func phaseContent(size: CGSize) -> some View {
        if phase == .setup {
            setupOverlay
        } else {
            activeOverlay

            if cameraService.cameraAvailable {
                screenBorderGlow(size: size)
            }

            if cameraService.displayStanding && cameraService.cameraAvailable {
                standingWarningOverlay
            }
        }
    }

    // MARK: - Screen Border Glow

    private func screenBorderGlow(size: CGSize) -> some View {
        RoundedRectangle(cornerRadius: 0)
            .stroke(borderColor, lineWidth: 16)
            .ignoresSafeArea()
            .opacity(borderGlowOpacity)
            .allowsHitTesting(false)
            .animation(.easeInOut(duration: 0.25), value: borderColor)
    }

    // MARK: - Standing Warning Overlay

    private var standingWarningOverlay: some View {
        ZStack {
            Color.black.opacity(0.55).ignoresSafeArea()

            VStack(spacing: 20) {
                Image(systemName: "arrow.down.to.line")
                    .font(.system(size: 72, weight: .bold))
                    .foregroundStyle(.yellow)
                    .symbolEffect(.pulse, options: .repeating)

                Text("GET BACK DOWN!")
                    .font(.system(size: 36, weight: .black, design: .rounded))
                    .foregroundStyle(.white)
                    .multilineTextAlignment(.center)

                Text("Stand back in push-up position\nto continue tracking")
                    .font(.title3.weight(.medium))
                    .foregroundStyle(.white.opacity(0.8))
                    .multilineTextAlignment(.center)
            }
            .padding(32)
        }
        .allowsHitTesting(false)
        .transition(.opacity)
        .animation(.easeInOut(duration: 0.35), value: cameraService.displayStanding)
    }

    // MARK: - Setup Overlay

    private var setupOverlay: some View {
        Group {
            if cameraService.cameraAvailable {
                ZStack {
                    PushUpPositionGuideView(
                        bodyDetected: cameraService.bodyDetected,
                        armsVisible: cameraService.armsVisible,
                        goodDistance: cameraService.goodDistance,
                        accentColor: pathColor
                    )
                    .ignoresSafeArea()

                    VStack(spacing: 0) {
                        CoachingBannerView(hint: cameraService.positioningHint)
                            .padding(.top, 8)

                        Spacer()

                        setupInstructions
                            .padding(.horizontal, 16)

                        setupStartButton
                            .padding(.horizontal, 16)
                            .padding(.bottom, 16)
                            .padding(.top, 12)
                    }
                }
            } else {
                cameraUnavailablePlaceholder
            }
        }
    }

    private var setupInstructions: some View {
        VStack(spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: "iphone.gen3.radiowaves.left.and.right")
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(pathColor)
                Text("Position Your Phone")
                    .font(.headline)
                    .foregroundStyle(.white)
            }

            VStack(alignment: .leading, spacing: 8) {
                instructionRow(icon: "iphone.gen3", text: "Prop phone upright in portrait mode")
                instructionRow(icon: "figure.arms.open", text: "Make sure your full body, including feet, is visible")
                instructionRow(icon: "arrow.left.and.right", text: "Stand about 5-8 feet from the camera")
                instructionRow(icon: "eye.fill", text: "Keep your head visible to the camera")
                instructionRow(icon: "knee", text: "Keep knees off the ground for proper form")
            }
        }
        .padding(16)
        .background(.ultraThinMaterial, in: .rect(cornerRadius: 16))
    }

    private func instructionRow(icon: String, text: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .font(.subheadline)
                .foregroundStyle(.white.opacity(0.7))
                .frame(width: 24)
            Text(text)
                .font(.subheadline)
                .foregroundStyle(.white.opacity(0.85))
        }
    }

    private var setupStartButton: some View {
        VStack(spacing: 8) {
            if !cameraService.positioningReady {
                HStack(spacing: 8) {
                    ProgressView()
                        .tint(.white)
                    Text(cameraService.lowerBodyVisible ? "Get into push-up position..." : "Move back until your feet are visible...")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.white)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .background(.ultraThinMaterial, in: Capsule())
            } else if !showCountdown {
                HStack(spacing: 8) {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                    Text("Position detected — starting soon...")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.white)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .background(.ultraThinMaterial, in: Capsule())
            }
        }
    }

    private var countdownOverlay: some View {
        ZStack {
            Color.black.opacity(0.6).ignoresSafeArea()

            VStack(spacing: 16) {
                Text("Get into position!")
                    .font(.title2.weight(.bold))
                    .foregroundStyle(.white.opacity(0.8))

                Text("\(countdownValue)")
                    .font(.system(size: 120, weight: .heavy, design: .rounded))
                    .foregroundStyle(.white)
                    .contentTransition(.numericText())
                    .animation(.spring(response: 0.3), value: countdownValue)

                Text("Push-ups start when countdown ends")
                    .font(.subheadline)
                    .foregroundStyle(.white.opacity(0.5))
            }
        }
        .allowsHitTesting(false)
    }

    private func beginCountdown() {
        showCountdown = true
        countdownValue = 5
        cameraService.resetPushUpCount()
        Task { @MainActor in
            for i in stride(from: 5, through: 1, by: -1) {
                countdownValue = i
                countdownTick += 1
                try? await Task.sleep(for: .seconds(1))
            }
            showCountdown = false
            startSession()
        }
    }

    // MARK: - Active Overlay

    private var activeOverlay: some View {
        Group {
            if cameraService.cameraAvailable {
                cameraActiveHUD
            } else {
                manualFallback
            }
        }
    }

    private var cameraActiveHUD: some View {
        VStack {
            VStack(spacing: 6) {
                if hasActiveWarning {
                    activeWarningBanners
                }
                statsOverlay
            }
            .padding(.top, 8)
            .padding(.horizontal, 16)

            Spacer()

            repRing
                .scaleEffect(lastRepScale)

            Spacer()

            bottomBar
                .padding(.horizontal, 16)
                .padding(.bottom, 16)
        }
        .animation(.easeInOut(duration: 0.35), value: hasActiveWarning)
    }

    // MARK: - Warning Banners (Large)

    private var activeWarningBanners: some View {
        VStack(spacing: 8) {
            if cameraService.displayStanding {
                largeWarningBanner(
                    icon: "figure.stand",
                    text: "STAND DETECTED — GET DOWN!",
                    bgColor: .red
                )
            }

            if !cameraService.displayBodyDetected {
                largeWarningBanner(
                    icon: "person.fill.xmark",
                    text: "BODY NOT DETECTED",
                    bgColor: .red
                )
            }

            if !cameraService.displayHeadDetected && cameraService.displayBodyDetected {
                largeWarningBanner(
                    icon: "eye.slash.fill",
                    text: "HEAD NOT VISIBLE",
                    bgColor: .orange
                )
            }

            if cameraService.displayKneesOnGround && !cameraService.displayStanding {
                largeWarningBanner(
                    icon: "exclamationmark.triangle.fill",
                    text: "KNEES OFF THE GROUND!",
                    bgColor: .red
                )
            }

            if !cameraService.displayFormGood && !cameraService.displayKneesOnGround && !cameraService.displayStanding && cameraService.displayBodyDetected {
                largeWarningBanner(
                    icon: "xmark.circle.fill",
                    text: "FIX YOUR FORM",
                    bgColor: .orange
                )
            }
        }
        .transition(.move(edge: .top).combined(with: .opacity))
    }

    private func largeWarningBanner(icon: String, text: String, bgColor: Color) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.title2.weight(.bold))
                .foregroundStyle(.white)

            Text(text)
                .font(.title3.weight(.heavy))
                .foregroundStyle(.white)
                .lineLimit(1)
                .minimumScaleFactor(0.7)

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 14)
        .frame(maxWidth: .infinity)
        .background(bgColor.opacity(0.85), in: .rect(cornerRadius: 14))
        .transition(.move(edge: .top).combined(with: .opacity))
    }

    private var statsOverlay: some View {
        HStack(spacing: 8) {
            bodyDetectionBadge

            Spacer()

            Text(formatDuration(elapsedSeconds))
                .font(.subheadline.monospacedDigit().weight(.semibold))
                .foregroundStyle(.white)
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(.black.opacity(0.5), in: Capsule())

            Spacer()

            formBadge

            phaseBadge
        }
    }

    private var bodyDetectionBadge: some View {
        HStack(spacing: 5) {
            Circle()
                .fill(cameraService.displayBodyDetected ? Color.green : Color.red)
                .frame(width: 8, height: 8)
            Text(cameraService.displayBodyDetected ? "Tracking" : "No Body")
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.white)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(.black.opacity(0.5), in: Capsule())
        .animation(.easeInOut(duration: 0.3), value: cameraService.displayBodyDetected)
    }

    private var formBadge: some View {
        HStack(spacing: 4) {
            Image(systemName: cameraService.displayFormGood ? "checkmark.circle.fill" : "xmark.circle.fill")
                .font(.caption2)
            Text("Form")
                .font(.caption2.weight(.semibold))
        }
        .foregroundStyle(cameraService.displayFormGood ? .green : .red)
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .background(.black.opacity(0.5), in: Capsule())
        .animation(.easeInOut(duration: 0.3), value: cameraService.displayFormGood)
    }

    private var phaseBadge: some View {
        Text(cameraService.pushUpPhaseLabel)
            .font(.caption2.weight(.bold))
            .foregroundStyle(.white)
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(
                phaseBadgeColor.opacity(0.7),
                in: Capsule()
            )
            .animation(.easeInOut(duration: 0.2), value: cameraService.pushUpPhaseLabel)
    }

    private var phaseBadgeColor: Color {
        switch cameraService.pushUpPhaseLabel {
        case "Down": return .orange
        case "Fix Form!", "Standing", "Get Down": return .red
        default: return .green
        }
    }

    private var repRing: some View {
        ZStack {
            Circle()
                .stroke(.white.opacity(0.15), lineWidth: 10)
                .frame(width: 180, height: 180)

            Circle()
                .trim(from: 0, to: progress)
                .stroke(
                    goalReached ? Color.green.gradient : pathColor.gradient,
                    style: StrokeStyle(lineWidth: 10, lineCap: .round)
                )
                .rotationEffect(.degrees(-90))
                .frame(width: 180, height: 180)
                .animation(.spring(response: 0.3), value: progress)

            VStack(spacing: 2) {
                Text("\(repCount)")
                    .font(.system(size: 64, weight: .heavy, design: .rounded))
                    .foregroundStyle(.white)
                    .contentTransition(.numericText())
                    .animation(.spring(response: 0.3), value: repCount)

                Text("of \(targetReps)")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.white.opacity(0.7))
            }
        }
        .shadow(color: .black.opacity(0.3), radius: 12, y: 4)
    }

    private var bottomBar: some View {
        VStack(spacing: 10) {
            if goalReached {
                Button {
                    endSession()
                } label: {
                    Label("Finish", systemImage: "checkmark.circle.fill")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 6)
                }
                .buttonStyle(.borderedProminent)
                .tint(.green)
                .scaleEffect(pulseGoal ? 1.03 : 1.0)
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }

            Button {
                manualCountRep()
            } label: {
                Label("Tap to Add Rep", systemImage: "hand.tap.fill")
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    .background(.white.opacity(0.2), in: Capsule())
            }
        }
        .animation(.spring(response: 0.3), value: goalReached)
    }

    private var manualFallback: some View {
        VStack(spacing: 0) {
            VStack(spacing: 4) {
                Text(formatDuration(elapsedSeconds))
                    .font(.subheadline.monospacedDigit().weight(.medium))
                    .foregroundStyle(.secondary)

                HStack(spacing: 0) {
                    statColumn(value: "\(repCount)", label: "DONE")
                    Divider().frame(height: 32)
                    statColumn(value: "\(max(0, targetReps - repCount))", label: "LEFT")
                    Divider().frame(height: 32)
                    statColumn(value: "\(targetReps)", label: "GOAL")
                }
                .padding(.vertical, 12)
                .background(Color(.secondarySystemGroupedBackground), in: .rect(cornerRadius: 14))
                .padding(.horizontal, 16)
            }
            .padding(.top, 16)

            VStack(spacing: 12) {
                Image(systemName: "camera.fill")
                    .font(.system(size: 36))
                    .foregroundStyle(.secondary)
                Text("Camera not available")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Text("Install this app on your device\nvia the Rork App to use the camera.")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity)
            .padding(.top, 32)

            Button {
                manualCountRep()
            } label: {
                VStack(spacing: 16) {
                    Spacer()

                    ZStack {
                        Circle()
                            .stroke(Color(.systemGray5), lineWidth: 12)
                            .frame(width: 200, height: 200)

                        Circle()
                            .trim(from: 0, to: progress)
                            .stroke(
                                goalReached ? Color.green.gradient : pathColor.gradient,
                                style: StrokeStyle(lineWidth: 12, lineCap: .round)
                            )
                            .rotationEffect(.degrees(-90))
                            .frame(width: 200, height: 200)
                            .animation(.spring(response: 0.3), value: progress)

                        VStack(spacing: 4) {
                            Text("\(repCount)")
                                .font(.system(size: 72, weight: .heavy, design: .rounded))
                                .contentTransition(.numericText())
                                .animation(.spring(response: 0.3), value: repCount)

                            Image(systemName: "hand.tap.fill")
                                .font(.title3)
                                .foregroundStyle(.tertiary)
                        }
                    }
                    .scaleEffect(lastRepScale)

                    Text("Tap to count each rep")
                        .font(.subheadline)
                        .foregroundStyle(.tertiary)

                    Spacer()

                    if goalReached {
                        Button {
                            endSession()
                        } label: {
                            Label("Finish", systemImage: "checkmark.circle.fill")
                                .font(.headline)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 6)
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(.green)
                        .scaleEffect(pulseGoal ? 1.03 : 1.0)
                        .padding(.horizontal, 16)
                        .padding(.bottom, 16)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .animation(.spring(response: 0.3), value: goalReached)
        }
    }

    private var cameraUnavailablePlaceholder: some View {
        VStack(spacing: 24) {
            Spacer()

            Image(systemName: "figure.strengthtraining.traditional")
                .font(.system(size: 64))
                .foregroundStyle(pathColor.gradient)

            VStack(spacing: 8) {
                HStack(spacing: 8) {
                    PathBadgeView(path: quest.path)
                    if quest.type == .verified {
                        VerifiedBadge(isVerified: true)
                    }
                }

                Text("Push-Up Challenge")
                    .font(.title2.weight(.bold))
                Text("Target: \(targetReps) reps")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            VStack(alignment: .leading, spacing: 10) {
                Label("Camera not available in simulator", systemImage: "camera.fill")
                Label("Manual tap available as backup", systemImage: "hand.tap.fill")
                Label("Hit your goal to complete", systemImage: "checkmark.circle.fill")
            }
            .font(.subheadline)
            .foregroundStyle(.secondary)
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(.secondarySystemGroupedBackground), in: .rect(cornerRadius: 14))
            .padding(.horizontal, 16)

            Spacer()

            Button {
                startSession()
            } label: {
                Label("Start Push-Ups", systemImage: "play.fill")
                    .font(.title3.weight(.bold))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
            }
            .buttonStyle(.borderedProminent)
            .tint(pathColor)
            .padding(.horizontal, 16)
            .padding(.bottom, 16)
        }
    }

    private func statColumn(value: String, label: String) -> some View {
        VStack(spacing: 4) {
            Text(value)
                .font(.headline.monospacedDigit())
                .contentTransition(.numericText())
            Text(label)
                .font(.caption2.weight(.medium))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Actions

    private func startSession() {
        repCount = 0
        bodyLostCount = 0
        startTime = Date()
        elapsedSeconds = 0
        borderGlowOpacity = 0
        startTimer()
        phase = .active
    }

    private func manualCountRep() {
        repCount += 1
        withAnimation(.spring(response: 0.15, dampingFraction: 0.5)) {
            lastRepScale = 1.15
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
            withAnimation(.spring(response: 0.2)) {
                lastRepScale = 1.0
            }
        }
    }

    private func endSession() {
        phase = .setup
        timer?.invalidate()
        timer = nil
        cameraService.stop()

        let session = ExerciseSession(
            id: UUID().uuidString,
            exerciseType: .pushUp,
            startedAt: startTime,
            endedAt: Date(),
            repsCompleted: repCount,
            targetReps: targetReps,
            totalFramesAnalyzed: cameraService.totalFramesProcessed,
            framesWithBodyDetected: cameraService.framesWithBody,
            averageConfidence: Double(cameraService.poseConfidence),
            bodyLostCount: bodyLostCount
        )

        withAnimation(.spring(response: 0.4)) {
            completedSession = session
        }
    }

    private func startTimer() {
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { _ in
            Task { @MainActor in
                guard let start = startTime else { return }
                elapsedSeconds = Date().timeIntervalSince(start)
            }
        }
    }

    private func formatDuration(_ seconds: TimeInterval) -> String {
        let total = Int(max(0, seconds))
        let m = total / 60
        let s = total % 60
        return String(format: "%02d:%02d", m, s)
    }

    private func lockPortrait() {
        guard let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene else { return }
        windowScene.requestGeometryUpdate(.iOS(interfaceOrientations: .portrait))
    }

    private func unlockOrientation() {
        guard let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene else { return }
        windowScene.requestGeometryUpdate(.iOS(interfaceOrientations: .all))
    }
}

nonisolated enum PushUpPhase: Equatable {
    case setup
    case active
}
