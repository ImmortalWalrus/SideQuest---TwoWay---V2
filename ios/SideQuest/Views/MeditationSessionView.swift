import SwiftUI
import AVFoundation

struct MeditationSessionView: View {
    let quest: Quest
    let instanceId: String
    let appState: AppState
    @Environment(\.dismiss) private var dismiss
    @State private var cameraService = MeditationCameraService()
    @State private var sessionActive: Bool = false
    @State private var meditationSeconds: TimeInterval = 0
    @State private var elapsedSeconds: TimeInterval = 0
    @State private var startTime: Date?
    @State private var timer: Timer?
    @State private var faceLostCount: Int = 0
    @State private var faceLostStart: Date?
    @State private var validFrames: Int = 0
    @State private var totalActiveFrames: Int = 0
    @State private var confidenceSum: Double = 0
    @State private var confidenceCount: Int = 0
    @State private var lastMeditationTick: Date?
    @State private var completedSession: MeditationSession?
    @State private var showDQAlert: Bool = false
    @State private var dqReason: String = ""
    @State private var pulseGoal: Bool = false
    @State private var breathPhase: Double = 0
    @State private var breathTimer: Timer?
    @State private var readyHoldStart: Date?
    @State private var readyCountdown: Int = 0
    @State private var countdownTimer: Timer?

    private var targetDuration: TimeInterval { quest.targetHoldSeconds ?? 300 }
    private var pathColor: Color { PathColorHelper.color(for: quest.path) }
    private var goalReached: Bool { meditationSeconds >= targetDuration }
    private var progress: Double { min(1.0, meditationSeconds / max(1, targetDuration)) }

    private var isInValidState: Bool {
        cameraService.faceDetected && cameraService.eyesClosed && cameraService.headStill
    }

    var body: some View {
        NavigationStack {
            if let session = completedSession {
                MeditationSummaryView(
                    session: session,
                    quest: quest,
                    onSubmit: {
                        appState.submitMeditationEvidence(for: instanceId, session: session)
                        dismiss()
                    },
                    onDiscard: { dismiss() }
                )
            } else {
                mainContent
            }
        }
        .interactiveDismissDisabled(sessionActive)
    }

    private var mainContent: some View {
        ZStack {
            cameraLayer

            if sessionActive {
                meditationActiveOverlay
            }

            uiOverlay
        }
        .onAppear {
            cameraService.configure()
            cameraService.start()
            appState.isImmersive = true
        }
        .onDisappear {
            cameraService.stop()
            timer?.invalidate()
            breathTimer?.invalidate()
            countdownTimer?.invalidate()
            appState.isImmersive = false
        }
        .onChange(of: cameraService.updateCounter) { _, _ in
            if sessionActive {
                processUpdate()
            } else {
                checkAutoStart()
            }
        }
        .onChange(of: goalReached) { _, reached in
            if reached {
                withAnimation(.easeInOut(duration: 0.8).repeatForever(autoreverses: true)) {
                    pulseGoal = true
                }
            }
        }
        .sensoryFeedback(.success, trigger: goalReached)
        .alert("Session Disqualified", isPresented: $showDQAlert) {
            Button("View Summary") { endSession() }
            Button("Dismiss", role: .cancel) { dismiss() }
        } message: { Text(dqReason) }
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                if !sessionActive {
                    Button("Close") { dismiss() }
                }
            }
            ToolbarItem(placement: .topBarTrailing) {
                if sessionActive {
                    Text(formatDuration(elapsedSeconds))
                        .font(.subheadline.monospacedDigit().weight(.semibold))
                        .foregroundStyle(.white.opacity(0.6))
                }
            }
        }
        .toolbarColorScheme(.dark, for: .navigationBar)
    }

    private var meditationActiveOverlay: some View {
        ZStack {
            Color.black.opacity(0.3).ignoresSafeArea()
                .allowsHitTesting(false)

            Circle()
                .fill(
                    RadialGradient(
                        colors: [
                            (isInValidState ? Color.indigo : Color.orange).opacity(0.35),
                            Color.clear
                        ],
                        center: .center,
                        startRadius: 20,
                        endRadius: 200
                    )
                )
                .frame(width: 400, height: 400)
                .scaleEffect(0.8 + breathPhase * 0.4)
                .animation(.easeInOut(duration: 4), value: breathPhase)

            Circle()
                .stroke(
                    (isInValidState ? Color.indigo : Color.orange).opacity(0.15),
                    lineWidth: 1
                )
                .frame(width: 300, height: 300)
                .scaleEffect(0.9 + breathPhase * 0.2)
                .animation(.easeInOut(duration: 4).delay(0.5), value: breathPhase)
        }
        .allowsHitTesting(false)
    }

    @ViewBuilder
    private var cameraLayer: some View {
        Group {
            #if targetEnvironment(simulator)
            meditationPlaceholder
            #else
            if AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .front) != nil {
                CameraPreviewView(session: cameraService.captureSession)
                    .ignoresSafeArea()
                    .overlay {
                        Color.black.opacity(sessionActive ? 0.35 : 0.2)
                            .ignoresSafeArea()
                            .allowsHitTesting(false)
                    }
            } else {
                meditationPlaceholder
            }
            #endif
        }
    }

    private var meditationPlaceholder: some View {
        VStack(spacing: 20) {
            Image(systemName: "brain.head.profile.fill")
                .font(.system(size: 56))
                .foregroundStyle(.secondary)
            Text("Meditation Tracker")
                .font(.title2.weight(.semibold))
            Text("Install this app on your device\nvia the Rork App to use the camera.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(.systemBackground))
    }

    private var uiOverlay: some View {
        VStack {
            if sessionActive {
                activeHUD
            }
            Spacer()
            controlPanel
        }
    }

    private var activeHUD: some View {
        VStack(spacing: 12) {
            Text(formatDuration(meditationSeconds))
                .font(.system(size: 72, weight: .thin, design: .rounded))
                .foregroundStyle(goalReached ? .green : isInValidState ? .white : .orange)
                .contentTransition(.numericText())
                .animation(.linear(duration: 0.3), value: meditationSeconds)

            Text("of \(formatDuration(targetDuration))")
                .font(.subheadline)
                .foregroundStyle(.white.opacity(0.5))

            statusIndicator

            if goalReached {
                Label("Goal Reached!", systemImage: "checkmark.circle.fill")
                    .font(.headline.weight(.bold))
                    .foregroundStyle(.green)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    .background(.ultraThinMaterial, in: Capsule())
                    .scaleEffect(pulseGoal ? 1.05 : 1.0)
                    .transition(.scale.combined(with: .opacity))
            }
        }
        .padding(.top, 80)
        .animation(.spring(response: 0.4), value: isInValidState)
        .animation(.spring(response: 0.4), value: goalReached)
    }

    @ViewBuilder
    private var statusIndicator: some View {
        if !cameraService.faceDetected && sessionActive {
            Label("Position your face in frame", systemImage: "faceid")
                .font(.caption.weight(.bold))
                .foregroundStyle(.yellow)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(.black.opacity(0.6), in: Capsule())
        } else if !cameraService.eyesClosed && cameraService.faceDetected {
            Label("Close your eyes", systemImage: "eye.slash.fill")
                .font(.caption.weight(.bold))
                .foregroundStyle(.orange)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(.black.opacity(0.6), in: Capsule())
        } else if !cameraService.headStill && cameraService.faceDetected && cameraService.eyesClosed {
            Label("Stay still...", systemImage: "hand.raised.fill")
                .font(.caption.weight(.bold))
                .foregroundStyle(.orange)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(.black.opacity(0.6), in: Capsule())
        } else if isInValidState && !goalReached {
            Label("Meditating...", systemImage: "sparkles")
                .font(.caption.weight(.bold))
                .foregroundStyle(.indigo)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(.black.opacity(0.6), in: Capsule())
        }
    }

    private var controlPanel: some View {
        VStack(spacing: 16) {
            if sessionActive {
                VStack(spacing: 6) {
                    HStack {
                        Text(formatDuration(meditationSeconds))
                            .font(.subheadline.monospacedDigit().weight(.semibold))
                        Spacer()
                        Text(formatDuration(targetDuration))
                            .font(.subheadline.monospacedDigit().weight(.semibold))
                            .foregroundStyle(.secondary)
                    }
                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            RoundedRectangle(cornerRadius: 4)
                                .fill(Color(.systemGray5))
                            RoundedRectangle(cornerRadius: 4)
                                .fill(goalReached ? Color.green.gradient : Color.indigo.gradient)
                                .frame(width: geo.size.width * progress)
                                .animation(.linear(duration: 0.5), value: progress)
                        }
                    }
                    .frame(height: 8)
                }

                HStack(spacing: 0) {
                    VStack(spacing: 4) {
                        Image(systemName: cameraService.faceDetected ? "faceid" : "face.dashed")
                            .font(.title3)
                            .foregroundStyle(cameraService.faceDetected ? .green : .red)
                        Text("FACE")
                            .font(.caption2.weight(.medium))
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity)
                    Divider().frame(height: 36)
                    VStack(spacing: 4) {
                        Image(systemName: cameraService.eyesClosed ? "eye.slash.fill" : "eye.fill")
                            .font(.title3)
                            .foregroundStyle(cameraService.eyesClosed ? .green : .orange)
                        Text("EYES")
                            .font(.caption2.weight(.medium))
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity)
                    Divider().frame(height: 36)
                    VStack(spacing: 4) {
                        Image(systemName: cameraService.headStill ? "checkmark.circle.fill" : "arrow.triangle.2.circlepath")
                            .font(.title3)
                            .foregroundStyle(cameraService.headStill ? .green : .orange)
                        Text("STILL")
                            .font(.caption2.weight(.medium))
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity)
                }

                Button {
                    endSession()
                } label: {
                    Label(
                        goalReached ? "Finish" : "End Session",
                        systemImage: goalReached ? "checkmark.circle.fill" : "stop.fill"
                    )
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 6)
                }
                .buttonStyle(.borderedProminent)
                .tint(goalReached ? .green : .secondary)
                .scaleEffect(pulseGoal && goalReached ? 1.03 : 1.0)
            } else {
                readyState
            }
        }
        .padding(20)
        .padding(.bottom, 8)
        .background(.ultraThinMaterial)
    }

    private var readyState: some View {
        VStack(spacing: 12) {
            HStack(spacing: 8) {
                PathBadgeView(path: quest.path)
                if quest.type == .verified {
                    VerifiedBadge(isVerified: true)
                }
            }

            Text("Meditation Session")
                .font(.title3.weight(.semibold))
            Text("Meditate for \(formatDuration(targetDuration))")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            HStack(spacing: 0) {
                VStack(spacing: 4) {
                    Image(systemName: cameraService.faceDetected ? "faceid" : "face.dashed")
                        .font(.title3)
                        .foregroundStyle(cameraService.faceDetected ? .green : .red)
                    Text("FACE")
                        .font(.caption2.weight(.medium))
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity)
                Divider().frame(height: 36)
                VStack(spacing: 4) {
                    Image(systemName: cameraService.eyesClosed ? "eye.slash.fill" : "eye.fill")
                        .font(.title3)
                        .foregroundStyle(cameraService.eyesClosed ? .green : .orange)
                    Text("EYES")
                        .font(.caption2.weight(.medium))
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity)
                Divider().frame(height: 36)
                VStack(spacing: 4) {
                    Image(systemName: cameraService.headStill ? "checkmark.circle.fill" : "arrow.triangle.2.circlepath")
                        .font(.title3)
                        .foregroundStyle(cameraService.headStill ? .green : .orange)
                    Text("STILL")
                        .font(.caption2.weight(.medium))
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity)
            }

            if readyCountdown > 0 {
                Text("Starting in \(readyCountdown)...")
                    .font(.title2.weight(.bold))
                    .foregroundStyle(.indigo)
                    .transition(.scale.combined(with: .opacity))
            } else if isInValidState {
                Text("Hold position...")
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.indigo)
                    .transition(.opacity)
            } else {
                VStack(spacing: 4) {
                    Label("Prop your phone facing you", systemImage: "iphone.gen3.radiowaves.left.and.right")
                    Label("Close your eyes & stay still", systemImage: "eye.slash.fill")
                    Label("Session auto-starts when ready", systemImage: "timer")
                }
                .font(.caption)
                .foregroundStyle(.tertiary)
            }
        }
        .animation(.spring(response: 0.3), value: readyCountdown)
        .animation(.spring(response: 0.3), value: isInValidState)
    }

    private func checkAutoStart() {
        guard !sessionActive else { return }

        if isInValidState {
            if readyHoldStart == nil {
                readyHoldStart = Date()
                startCountdownTimer()
            }
        } else {
            readyHoldStart = nil
            readyCountdown = 0
            countdownTimer?.invalidate()
            countdownTimer = nil
        }
    }

    private func startCountdownTimer() {
        countdownTimer?.invalidate()
        countdownTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { _ in
            Task { @MainActor in
                guard let holdStart = readyHoldStart, isInValidState else {
                    readyHoldStart = nil
                    readyCountdown = 0
                    countdownTimer?.invalidate()
                    countdownTimer = nil
                    return
                }

                let elapsed = Date().timeIntervalSince(holdStart)
                let remaining = max(0, Int(ceil(3.0 - elapsed)))
                readyCountdown = remaining

                if elapsed >= 3.0 {
                    countdownTimer?.invalidate()
                    countdownTimer = nil
                    startSession()
                }
            }
        }
    }

    private func startSession() {
        sessionActive = true
        meditationSeconds = 0
        elapsedSeconds = 0
        startTime = Date()
        faceLostCount = 0
        faceLostStart = nil
        validFrames = 0
        totalActiveFrames = 0
        confidenceSum = 0
        confidenceCount = 0
        lastMeditationTick = nil
        dqReason = ""
        readyCountdown = 0
        cameraService.resetCounters()
        startTimer()
        startBreathCycle()
    }

    private func endSession() {
        sessionActive = false
        cameraService.stop()
        timer?.invalidate()
        timer = nil
        breathTimer?.invalidate()
        breathTimer = nil

        var flags: [MeditationIntegrityFlag] = []

        let faceRatio = cameraService.totalFramesProcessed > 0
            ? Double(cameraService.framesWithFace) / Double(cameraService.totalFramesProcessed)
            : 0
        if faceRatio < 0.5 { flags.append(.faceNotDetected) }

        let eyesRatio = cameraService.framesWithFace > 0
            ? Double(cameraService.framesWithEyesClosed) / Double(cameraService.framesWithFace)
            : 0
        if eyesRatio < 0.6 && cameraService.framesWithFace > 10 { flags.append(.eyesOpenTooMuch) }

        let stillRatio = cameraService.framesWithFace > 0
            ? Double(cameraService.framesHeadStill) / Double(cameraService.framesWithFace)
            : 0
        if stillRatio < 0.5 && cameraService.framesWithFace > 10 { flags.append(.excessiveMovement) }

        let avgConf = confidenceCount > 0 ? confidenceSum / Double(confidenceCount) : 0
        if avgConf < 0.35 && confidenceCount > 10 { flags.append(.lowConfidence) }

        if meditationSeconds < 30 { flags.append(.tooShort) }

        let session = MeditationSession(
            id: UUID().uuidString,
            startedAt: startTime,
            endedAt: Date(),
            meditationDurationSeconds: meditationSeconds,
            targetDurationSeconds: targetDuration,
            totalFramesAnalyzed: cameraService.totalFramesProcessed,
            framesWithFaceDetected: cameraService.framesWithFace,
            framesWithEyesClosed: cameraService.framesWithEyesClosed,
            framesHeadStill: cameraService.framesHeadStill,
            averageConfidence: avgConf,
            faceLostCount: faceLostCount,
            integrityFlags: flags,
            wasDisqualified: !dqReason.isEmpty
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

                if isInValidState {
                    let now = Date()
                    if let last = lastMeditationTick {
                        meditationSeconds += now.timeIntervalSince(last)
                    }
                    lastMeditationTick = now
                } else {
                    lastMeditationTick = nil
                }
            }
        }
    }

    private func startBreathCycle() {
        breathTimer?.invalidate()
        breathTimer = Timer.scheduledTimer(withTimeInterval: 4.0, repeats: true) { _ in
            Task { @MainActor in
                withAnimation(.easeInOut(duration: 4.0)) {
                    breathPhase = breathPhase == 0 ? 1 : 0
                }
            }
        }
    }

    private func processUpdate() {
        confidenceSum += Double(cameraService.faceConfidence)
        confidenceCount += 1
        totalActiveFrames += 1

        if !cameraService.faceDetected {
            if faceLostStart == nil {
                faceLostStart = Date()
                faceLostCount += 1
            }
            if let lostStart = faceLostStart, Date().timeIntervalSince(lostStart) > 30 {
                dqReason = "Face not detected for too long. Make sure your face is visible to the camera."
                showDQAlert = true
            }
            return
        } else {
            faceLostStart = nil
        }

        if isInValidState {
            validFrames += 1
        }
    }

    private func formatDuration(_ seconds: TimeInterval) -> String {
        let total = Int(max(0, seconds))
        let m = total / 60
        let s = total % 60
        return String(format: "%d:%02d", m, s)
    }
}
