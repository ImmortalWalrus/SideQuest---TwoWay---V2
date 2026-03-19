import SwiftUI
import UIKit
import AVFoundation

struct WallSitChallengeView: View {
    let quest: Quest
    let instanceId: String
    let appState: AppState
    @Environment(\.dismiss) private var dismiss
    @State private var cameraService = WallSitCameraService()
    @State private var phase: WallSitPhase = .setup
    @State private var holdSeconds: TimeInterval = 0
    @State private var elapsedSeconds: TimeInterval = 0
    @State private var startTime: Date?
    @State private var lastHoldTick: Date?
    @State private var timer: Timer?
    @State private var completedSession: ExerciseSession?
    @State private var pulseGoal: Bool = false
    @State private var readyConfirmed: Bool = false
    @State private var countdownValue: Int = 0
    @State private var showCountdown: Bool = false
    @State private var countdownTick: Int = 0
    @State private var borderGlowOpacity: Double = 0
    @State private var bodyLostCount: Int = 0
    @State private var autoStartTriggered: Bool = false

    private var targetHold: TimeInterval { quest.targetHoldSeconds ?? 180 }
    private var pathColor: Color { PathColorHelper.color(for: quest.path) }
    private var goalReached: Bool { holdSeconds >= targetHold }
    private var holdProgress: Double { min(1.0, holdSeconds / max(1, targetHold)) }

    private var borderColor: Color {
        if !cameraService.displayBodyDetected { return .red }
        if cameraService.displayStanding || cameraService.displayChairSupportDetected { return .red }
        if cameraService.displayWallSitDetected { return .green }
        return .orange
    }

    private var hasActiveWarning: Bool {
        phase == .active && (
            !cameraService.displayBodyDetected ||
            cameraService.displayStanding ||
            cameraService.displayChairSupportDetected ||
            !cameraService.displayWallSitDetected
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
                if cameraService.cameraAvailable {
                    CameraPreviewView(session: cameraService.captureSession)
                        .ignoresSafeArea()

                    SkeletonOverlayView(
                        joints: cameraService.jointPositions,
                        bodyDetected: cameraService.bodyDetected,
                        accentColor: pathColor
                    )
                    .ignoresSafeArea()
                }

                if phase == .setup {
                    setupOverlay
                } else {
                    activeOverlay

                    if cameraService.cameraAvailable {
                        screenBorderGlow(size: geo.size)
                    }

                    if cameraService.displayStanding && cameraService.cameraAvailable {
                        standingWarningOverlay
                    }
                }

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
        .onChange(of: cameraService.positioningReady) { _, ready in
            if ready && !readyConfirmed {
                readyConfirmed = true
            }
            if ready && phase == .setup && !autoStartTriggered && !showCountdown {
                autoStartTriggered = true
                beginCountdown()
            }
        }
        .onChange(of: cameraService.bodyDetected) { old, new in
            if old && !new && phase == .active {
                bodyLostCount += 1
            }
        }
        .onChange(of: goalReached) { _, reached in
            if reached {
                withAnimation(.easeInOut(duration: 0.8).repeatForever(autoreverses: true)) {
                    pulseGoal = true
                }
            }
        }
        .onChange(of: cameraService.displayWallSitDetected) { _, inPosition in
            guard phase == .active, cameraService.cameraAvailable else { return }
            withAnimation(.easeOut(duration: 0.15)) {
                borderGlowOpacity = inPosition ? 0.5 : 0.8
            }
        }
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

    private func screenBorderGlow(size: CGSize) -> some View {
        RoundedRectangle(cornerRadius: 0)
            .stroke(borderColor, lineWidth: 16)
            .ignoresSafeArea()
            .opacity(borderGlowOpacity)
            .allowsHitTesting(false)
            .animation(.easeInOut(duration: 0.25), value: borderColor)
    }

    private var standingWarningOverlay: some View {
        ZStack {
            Color.black.opacity(0.55).ignoresSafeArea()

            VStack(spacing: 20) {
                Image(systemName: "arrow.down.to.line")
                    .font(.system(size: 72, weight: .bold))
                    .foregroundStyle(.yellow)
                    .symbolEffect(.pulse, options: .repeating)

                Text("SIT BACK DOWN!")
                    .font(.system(size: 36, weight: .black, design: .rounded))
                    .foregroundStyle(.white)
                    .multilineTextAlignment(.center)

                Text("Get back into wall sit position\nto continue tracking")
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

    private var setupOverlay: some View {
        Group {
            if cameraService.cameraAvailable {
                ZStack {
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
                instructionRow(icon: "iphone.gen3", text: "Prop phone upright, facing you from the side")
                instructionRow(icon: "figure.seated.side", text: "Back flat on the wall, thighs parallel to the floor")
                instructionRow(icon: "angle", text: "Keep shins vertical with knees bent around 90°")
                instructionRow(icon: "exclamationmark.triangle.fill", text: "No chair or seat support — hover against the wall")
                instructionRow(icon: "arrow.left.and.right", text: "Make sure full body is visible")
                instructionRow(icon: "timer", text: "Timer only counts while holding true wall-sit form")
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
            if cameraService.displayChairSupportDetected {
                HStack(spacing: 8) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(.red)
                    Text("No chair support — hover against the wall")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.white)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .background(.ultraThinMaterial, in: Capsule())
            } else if !cameraService.positioningReady {
                HStack(spacing: 8) {
                    ProgressView()
                        .tint(.white)
                    Text("Get into a true wall sit...")
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
                    Text("Position detected \u{2014} starting soon...")
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
                Text("Get into wall sit position!")
                    .font(.title2.weight(.bold))
                    .foregroundStyle(.white.opacity(0.8))

                Text("\(countdownValue)")
                    .font(.system(size: 120, weight: .heavy, design: .rounded))
                    .foregroundStyle(.white)
                    .contentTransition(.numericText())
                    .animation(.spring(response: 0.3), value: countdownValue)

                Text("Hold position when countdown ends")
                    .font(.subheadline)
                    .foregroundStyle(.white.opacity(0.5))
            }
        }
        .allowsHitTesting(false)
    }

    private func beginCountdown() {
        showCountdown = true
        countdownValue = 5
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

            holdRing

            Spacer()

            bottomBar
                .padding(.horizontal, 16)
                .padding(.bottom, 16)
        }
        .animation(.easeInOut(duration: 0.35), value: hasActiveWarning)
    }

    private var activeWarningBanners: some View {
        VStack(spacing: 8) {
            if cameraService.displayStanding {
                largeWarningBanner(
                    icon: "figure.stand",
                    text: "STANDING — SIT BACK DOWN!",
                    bgColor: .red
                )
            }

            if cameraService.displayChairSupportDetected {
                largeWarningBanner(
                    icon: "exclamationmark.triangle.fill",
                    text: "CHAIR DETECTED — REMOVE SUPPORT",
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

            if !cameraService.displayWallSitDetected && cameraService.displayBodyDetected && !cameraService.displayStanding {
                largeWarningBanner(
                    icon: "xmark.circle.fill",
                    text: "HOLD WALL SIT POSITION",
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
            Image(systemName: cameraService.displayWallSitDetected ? "checkmark.circle.fill" : "xmark.circle.fill")
                .font(.caption2)
            Text("Wall Sit")
                .font(.caption2.weight(.semibold))
        }
        .foregroundStyle(cameraService.displayWallSitDetected ? .green : .red)
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .background(.black.opacity(0.5), in: Capsule())
        .animation(.easeInOut(duration: 0.3), value: cameraService.displayWallSitDetected)
    }

    private var holdRing: some View {
        ZStack {
            Circle()
                .stroke(.white.opacity(0.15), lineWidth: 10)
                .frame(width: 180, height: 180)

            Circle()
                .trim(from: 0, to: holdProgress)
                .stroke(
                    goalReached ? Color.green.gradient : pathColor.gradient,
                    style: StrokeStyle(lineWidth: 10, lineCap: .round)
                )
                .rotationEffect(.degrees(-90))
                .frame(width: 180, height: 180)
                .animation(.spring(response: 0.3), value: holdProgress)

            VStack(spacing: 2) {
                Text(formatDuration(holdSeconds))
                    .font(.system(size: 56, weight: .heavy, design: .rounded))
                    .foregroundStyle(.white)
                    .contentTransition(.numericText())

                Text("of \(formatDuration(targetHold))")
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
        }
        .animation(.spring(response: 0.3), value: goalReached)
    }

    private var manualFallback: some View {
        VStack(spacing: 24) {
            Text(formatDuration(elapsedSeconds))
                .font(.subheadline.monospacedDigit().weight(.medium))
                .foregroundStyle(.secondary)
                .padding(.top, 16)

            Spacer()

            ZStack {
                Circle()
                    .stroke(Color(.systemGray5), lineWidth: 14)
                    .frame(width: 220, height: 220)

                Circle()
                    .trim(from: 0, to: holdProgress)
                    .stroke(
                        goalReached ? Color.green.gradient : pathColor.gradient,
                        style: StrokeStyle(lineWidth: 14, lineCap: .round)
                    )
                    .rotationEffect(.degrees(-90))
                    .frame(width: 220, height: 220)
                    .animation(.linear(duration: 0.5), value: holdProgress)

                VStack(spacing: 4) {
                    Text(formatDuration(holdSeconds))
                        .font(.system(size: 56, weight: .heavy, design: .rounded))
                        .contentTransition(.numericText())

                    Text("of \(formatDuration(targetHold))")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }

            VStack(spacing: 12) {
                Image(systemName: "camera.fill")
                    .font(.system(size: 36))
                    .foregroundStyle(.secondary)
                Text("Camera not available")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Text("Timer runs continuously in manual mode.\nInstall on device for camera tracking.")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .multilineTextAlignment(.center)
            }

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
        .animation(.spring(response: 0.3), value: goalReached)
    }

    private var cameraUnavailablePlaceholder: some View {
        VStack(spacing: 24) {
            Spacer()

            Image(systemName: "figure.strengthtraining.functional")
                .font(.system(size: 64))
                .foregroundStyle(pathColor.gradient)

            VStack(spacing: 8) {
                HStack(spacing: 8) {
                    PathBadgeView(path: quest.path)
                    if quest.type == .verified {
                        VerifiedBadge(isVerified: true)
                    }
                }

                Text("Wall Sit Challenge")
                    .font(.title2.weight(.bold))
                Text("Hold for \(formatDuration(targetHold))")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            VStack(alignment: .leading, spacing: 10) {
                Label("Camera not available in simulator", systemImage: "camera.fill")
                Label("Timer runs continuously as fallback", systemImage: "timer")
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
                Label("Start Wall Sit", systemImage: "play.fill")
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

    private func startSession() {
        holdSeconds = 0
        elapsedSeconds = 0
        bodyLostCount = 0
        startTime = Date()
        lastHoldTick = Date()
        borderGlowOpacity = 0
        startTimer()
        phase = .active
    }

    private func endSession() {
        phase = .setup
        timer?.invalidate()
        timer = nil
        cameraService.stop()

        let session = ExerciseSession(
            id: UUID().uuidString,
            exerciseType: .wallSit,
            startedAt: startTime,
            endedAt: Date(),
            holdDurationSeconds: holdSeconds,
            targetHoldSeconds: targetHold,
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
        timer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { _ in
            Task { @MainActor in
                guard let start = startTime else { return }
                elapsedSeconds = Date().timeIntervalSince(start)

                if cameraService.cameraAvailable {
                    if cameraService.displayWallSitDetected && !cameraService.displayStanding && !cameraService.displayChairSupportDetected && cameraService.displayBodyDetected {
                        if let tick = lastHoldTick {
                            holdSeconds += Date().timeIntervalSince(tick)
                        }
                        lastHoldTick = Date()
                    } else {
                        lastHoldTick = Date()
                    }
                } else {
                    if let tick = lastHoldTick {
                        holdSeconds += Date().timeIntervalSince(tick)
                    }
                    lastHoldTick = Date()
                }
            }
        }
    }

    private func formatDuration(_ seconds: TimeInterval) -> String {
        let total = Int(max(0, seconds))
        let m = total / 60
        let s = total % 60
        return String(format: "%d:%02d", m, s)
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

nonisolated enum WallSitPhase: Equatable {
    case setup
    case active
}
