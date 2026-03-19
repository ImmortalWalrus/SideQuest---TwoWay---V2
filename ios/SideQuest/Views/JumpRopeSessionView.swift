import SwiftUI
import AVFoundation

struct JumpRopeSessionView: View {
    let quest: Quest
    let instanceId: String
    let appState: AppState
    @Environment(\.dismiss) private var dismiss
    @State private var sessionActive: Bool = false
    @State private var detector = JumpRopeDetectionService()
    @State private var metronome = MetronomeService()
    @State private var elapsedSeconds: TimeInterval = 0
    @State private var startTime: Date?
    @State private var timer: Timer?
    @State private var completedSession: ExerciseSession?
    @State private var pulseGoal: Bool = false
    @State private var beatPulse: Bool = false
    @State private var showSetup: Bool = true
    @State private var selectedBPM: Int = 120
    @State private var metronomeEnabled: Bool = true
    @State private var lastOnBeat: Bool = false
    @State private var streakFlash: Bool = false
    @State private var previousJumpCount: Int = 0
    @State private var challengeMode: Bool = false
    @State private var hearts: Int = 3
    @State private var maxHearts: Int = 3
    @State private var heartLostTrigger: Int = 0
    @State private var gameOver: Bool = false
    @State private var heartShake: Bool = false
    @State private var showAutoStartCountdown: Bool = false
    @State private var autoStartCountdownValue: Int = 0
    @State private var bodyReadyProgress: Double = 0
    @State private var readinessTask: Task<Void, Never>?
    @State private var countdownTask: Task<Void, Never>?

    private var targetJumps: Int { quest.targetReps ?? 100 }
    private var pathColor: Color { PathColorHelper.color(for: quest.path) }
    private var goalReached: Bool { detector.jumpCount >= targetJumps }
    private var progress: Double { min(1.0, Double(detector.jumpCount) / Double(max(1, targetJumps))) }

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
            } else if showSetup {
                setupView
            } else {
                sessionView
            }
        }
        .interactiveDismissDisabled(sessionActive)
        .onAppear {
            detector.start()
        }
        .onDisappear {
            timer?.invalidate()
            timer = nil
            readinessTask?.cancel()
            readinessTask = nil
            countdownTask?.cancel()
            countdownTask = nil
            metronome.stop()
            detector.stop()
            appState.isImmersive = false
        }
    }

    private var setupView: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(spacing: 28) {
                    Image(systemName: "figure.jumprope")
                        .font(.system(size: 64))
                        .foregroundStyle(pathColor.gradient)
                        .symbolEffect(.bounce, options: .repeating.speed(0.5))
                        .padding(.top, 24)

                    VStack(spacing: 8) {
                        HStack(spacing: 8) {
                            PathBadgeView(path: quest.path)
                            if quest.type == .verified {
                                VerifiedBadge(isVerified: true)
                            }
                        }
                        Text("Jump Rope Challenge")
                            .font(.title2.weight(.bold))
                        Text("Target: \(targetJumps) jumps")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }

                    VStack(spacing: 16) {
                        HStack {
                            Image(systemName: "metronome.fill")
                                .foregroundStyle(pathColor)
                            Text("Beat Pacer")
                                .font(.subheadline.weight(.semibold))
                            Spacer()
                            Toggle("", isOn: $metronomeEnabled)
                                .labelsHidden()
                                .tint(pathColor)
                        }

                        if metronomeEnabled {
                            VStack(spacing: 8) {
                                Text("\(selectedBPM) BPM")
                                    .font(.title3.weight(.bold).monospacedDigit())
                                    .foregroundStyle(pathColor)

                                HStack(spacing: 16) {
                                    Button {
                                        selectedBPM = max(60, selectedBPM - 10)
                                    } label: {
                                        Image(systemName: "minus.circle.fill")
                                            .font(.title2)
                                            .foregroundStyle(.secondary)
                                    }

                                    Slider(value: Binding(
                                        get: { Double(selectedBPM) },
                                        set: { selectedBPM = Int($0) }
                                    ), in: 60...200, step: 5)
                                    .tint(pathColor)

                                    Button {
                                        selectedBPM = min(200, selectedBPM + 10)
                                    } label: {
                                        Image(systemName: "plus.circle.fill")
                                            .font(.title2)
                                            .foregroundStyle(.secondary)
                                    }
                                }

                                HStack(spacing: 16) {
                                    bpmPreset("Slow", bpm: 80)
                                    bpmPreset("Medium", bpm: 120)
                                    bpmPreset("Fast", bpm: 150)
                                    bpmPreset("Sprint", bpm: 180)
                                }
                            }
                            .transition(.opacity.combined(with: .move(edge: .top)))
                        }
                    }
                    .padding(16)
                    .background(Color(.secondarySystemGroupedBackground), in: .rect(cornerRadius: 14))
                    .padding(.horizontal, 16)

                    VStack(spacing: 16) {
                        HStack {
                            Image(systemName: "heart.fill")
                                .foregroundStyle(.red)
                            Text("Challenge Mode")
                                .font(.subheadline.weight(.semibold))
                            Spacer()
                            Toggle("", isOn: $challengeMode)
                                .labelsHidden()
                                .tint(.red)
                        }

                        if challengeMode {
                            VStack(alignment: .leading, spacing: 8) {
                                HStack(spacing: 4) {
                                    ForEach(0..<3, id: \.self) { _ in
                                        Image(systemName: "heart.fill")
                                            .foregroundStyle(.red)
                                    }
                                    Text("3 Lives")
                                        .font(.subheadline.weight(.bold))
                                        .foregroundStyle(.red)
                                }
                                Text("Miss the beat and lose a heart. Lose all 3 and the session ends!")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            .transition(.opacity.combined(with: .move(edge: .top)))
                        }
                    }
                    .padding(16)
                    .background(Color(.secondarySystemGroupedBackground), in: .rect(cornerRadius: 14))
                    .padding(.horizontal, 16)

                    VStack(alignment: .leading, spacing: 10) {
                        Label("Camera detects your jumps via pose tracking", systemImage: "figure.jumprope")
                        Label("Jump on the beat for bonus streak points", systemImage: "waveform.path")
                        Label("Prop phone up to see your full body", systemImage: "iphone.gen3")
                    }
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .padding(16)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color(.secondarySystemGroupedBackground), in: .rect(cornerRadius: 14))
                    .padding(.horizontal, 16)
                    .padding(.bottom, 16)
                }
            }

            VStack(spacing: 8) {
                if challengeMode && !metronomeEnabled {
                    Text("Challenge mode requires the beat pacer")
                        .font(.caption)
                        .foregroundStyle(.orange)
                }

                Button {
                    if challengeMode { metronomeEnabled = true }
                    withAnimation(.spring(response: 0.4)) {
                        showSetup = false
                    }
                    prepareSession()
                } label: {
                    Label(challengeMode ? "Start Challenge" : "Start Jumping", systemImage: challengeMode ? "heart.fill" : "play.fill")
                        .font(.title3.weight(.bold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                }
                .buttonStyle(.borderedProminent)
                .tint(challengeMode ? .red : pathColor)
                .disabled(challengeMode && !metronomeEnabled)
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 16)
            .padding(.top, 8)
            .background(Color(.systemGroupedBackground))
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle(quest.title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button("Close") { dismiss() }
            }
        }
        .onChange(of: challengeMode) { _, on in
            if on { metronomeEnabled = true }
        }
    }

    private func bpmPreset(_ label: String, bpm: Int) -> some View {
        Button {
            withAnimation(.spring(response: 0.2)) {
                selectedBPM = bpm
            }
        } label: {
            Text(label)
                .font(.caption.weight(.semibold))
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(selectedBPM == bpm ? pathColor : Color(.tertiarySystemGroupedBackground), in: Capsule())
                .foregroundStyle(selectedBPM == bpm ? .white : .secondary)
        }
        .buttonStyle(.plain)
    }

    private var sessionView: some View {
        VStack(spacing: 0) {
            cameraArea
            controlsArea
        }
        .background(Color.black)
        .onAppear {
            appState.isImmersive = true
            detector.start()
            if detector.positioningReady {
                beginReadinessHoldIfNeeded()
            }
        }
        .onChange(of: goalReached) { _, reached in
            if reached && sessionActive {
                withAnimation(.easeInOut(duration: 0.8).repeatForever(autoreverses: true)) {
                    pulseGoal = true
                }
            }
        }
        .onChange(of: detector.positioningReady) { _, ready in
            handleDetectorPresenceChanged(ready)
        }
        .onChange(of: detector.jumpCount) { oldVal, newVal in
            guard sessionActive, newVal > oldVal else { return }
            if metronomeEnabled {
                lastOnBeat = metronome.checkJumpOnBeat()
            }
        }
        .onChange(of: metronome.missedBeatCount) { oldVal, newVal in
            guard challengeMode, newVal > oldVal, sessionActive, !gameOver, elapsedSeconds >= 3 else { return }
            withAnimation(.spring(response: 0.3, dampingFraction: 0.4)) {
                hearts = max(0, hearts - 1)
                heartLostTrigger += 1
                heartShake = true
            }
            detector.recordMissedBeat()
            if hearts <= 0 {
                gameOver = true
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                    endSession()
                }
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
                heartShake = false
            }
        }
        .sensoryFeedback(.impact(weight: .light), trigger: detector.jumpCount)
        .sensoryFeedback(.success, trigger: goalReached)
        .sensoryFeedback(.impact(weight: .heavy, intensity: 1.0), trigger: heartLostTrigger)
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                if !sessionActive {
                    Button("Close") { dismiss() }
                        .fontWeight(.semibold)
                        .foregroundStyle(.white)
                }
            }
            ToolbarItem(placement: .topBarTrailing) {
                if sessionActive {
                    Button("End", role: .destructive) { endSession() }
                        .fontWeight(.semibold)
                        .foregroundStyle(.white)
                }
            }
        }
    }

    private var cameraArea: some View {
        ZStack {
            #if targetEnvironment(simulator)
            simulatorPlaceholder
            #else
            if AVCaptureDevice.default(for: .video) != nil {
                CameraPreviewView(session: detector.captureSession)
                    .ignoresSafeArea()

                SkeletonOverlayView(
                    joints: detector.jointPositions,
                    bodyDetected: detector.displayBodyDetected,
                    accentColor: challengeMode ? .red : pathColor
                )
                .ignoresSafeArea()
            } else {
                simulatorPlaceholder
            }
            #endif

            if !detector.cameraAvailable {
                VStack(spacing: 10) {
                    ProgressView()
                        .tint(.white)
                    Text("Starting camera…")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.white)
                }
                .padding(.horizontal, 18)
                .padding(.vertical, 14)
                .background(.ultraThinMaterial, in: .rect(cornerRadius: 16))
            }

            VStack(spacing: 12) {
                if detector.cameraAvailable {
                    CoachingBannerView(hint: detector.positioningHint)
                        .padding(.top, 12)
                }

                if challengeMode {
                    heartsDisplay
                }
                Spacer()
                if metronomeEnabled {
                    beatIndicator
                        .padding(.bottom, 16)
                }
            }

            if gameOver {
                gameOverOverlay
            }

            if showAutoStartCountdown {
                autoStartCountdownOverlay
            } else if !sessionActive && !gameOver {
                autoStartStatusOverlay
            }

            if !detector.displayBodyDetected && sessionActive && !gameOver {
                VStack(spacing: 8) {
                    Image(systemName: "person.fill.questionmark")
                        .font(.title)
                    Text("Position yourself in frame")
                        .font(.subheadline.weight(.medium))
                }
                .foregroundStyle(.white)
                .padding(16)
                .background(.ultraThinMaterial, in: .rect(cornerRadius: 14))
            }
        }
        .frame(maxHeight: .infinity)
    }

    private var gameOverOverlay: some View {
        VStack(spacing: 16) {
            Image(systemName: "heart.slash.fill")
                .font(.system(size: 48))
                .foregroundStyle(.red)
                .symbolEffect(.bounce)

            Text("GAME OVER")
                .font(.title.weight(.black))
                .foregroundStyle(.white)

            Text("\(detector.jumpCount) jumps completed")
                .font(.subheadline)
                .foregroundStyle(.white.opacity(0.8))
        }
        .padding(32)
        .background(.ultraThinMaterial, in: .rect(cornerRadius: 20))
        .transition(.scale.combined(with: .opacity))
    }

    private var simulatorPlaceholder: some View {
        VStack(spacing: 20) {
            Image(systemName: "figure.jumprope")
                .font(.system(size: 48))
                .foregroundStyle(.secondary)
            Text("Camera Preview")
                .font(.title2.weight(.semibold))
                .foregroundStyle(.white)
            Text("Install this app on your device\nvia the Rork App to use the camera.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(.systemGray6))
    }

    private var autoStartStatusOverlay: some View {
        VStack(spacing: 12) {
            Image(systemName: detector.positioningReady ? "checkmark.circle.fill" : detector.positioningHint == .none ? "figure.jumprope" : detector.positioningHint.icon)
                .font(.system(size: 34, weight: .bold))
                .foregroundStyle(detector.positioningReady ? pathColor : .white)

            Text(detector.positioningReady ? "Hold position to begin" : detector.positioningHint == .none ? "Position yourself in frame" : detector.positioningHint.message)
                .font(.headline.weight(.bold))
                .foregroundStyle(.white)
                .multilineTextAlignment(.center)

            Text(detector.positioningReady ? "Keep your full body visible for 2 seconds" : "We’ll auto-start once your full body is detected")
                .font(.subheadline)
                .foregroundStyle(.white.opacity(0.72))
                .multilineTextAlignment(.center)

            ProgressView(value: bodyReadyProgress)
                .progressViewStyle(.linear)
                .tint(pathColor)
                .frame(width: 180)
                .opacity(detector.positioningReady ? 1 : 0.35)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 18)
        .background(.ultraThinMaterial, in: .rect(cornerRadius: 18))
        .allowsHitTesting(false)
    }

    private var autoStartCountdownOverlay: some View {
        VStack(spacing: 14) {
            Text(challengeMode ? "Challenge starts in" : "Session starts in")
                .font(.headline.weight(.bold))
                .foregroundStyle(.white.opacity(0.8))

            Text("\(autoStartCountdownValue)")
                .font(.system(size: 96, weight: .heavy, design: .rounded))
                .foregroundStyle(.white)
                .contentTransition(.numericText())

            Text("Stay centered and be ready to jump")
                .font(.subheadline)
                .foregroundStyle(.white.opacity(0.65))
        }
        .padding(.horizontal, 28)
        .padding(.vertical, 24)
        .background(.ultraThinMaterial, in: .rect(cornerRadius: 20))
        .allowsHitTesting(false)
    }

    private var beatIndicator: some View {
        HStack(spacing: 6) {
            ForEach(0..<4, id: \.self) { i in
                let isActive = metronome.currentBeat % 4 == i
                Circle()
                    .fill(isActive ? (challengeMode && !metronome.lastBeatHadJump ? Color.red : pathColor) : Color.white.opacity(0.3))
                    .frame(width: isActive ? 16 : 10, height: isActive ? 16 : 10)
                    .animation(.spring(response: 0.15, dampingFraction: 0.6), value: metronome.currentBeat)
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 10)
        .background(.ultraThinMaterial, in: Capsule())
    }

    private var heartsDisplay: some View {
        HStack(spacing: 8) {
            ForEach(0..<maxHearts, id: \.self) { i in
                Image(systemName: i < hearts ? "heart.fill" : "heart")
                    .font(.title2)
                    .foregroundStyle(i < hearts ? .red : .white.opacity(0.3))
                    .scaleEffect(heartShake && i == hearts ? 1.5 : 1.0)
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 10)
        .background(.ultraThinMaterial, in: Capsule())
        .animation(.spring(response: 0.25, dampingFraction: 0.3), value: hearts)
    }

    private var controlsArea: some View {
        VStack(spacing: 12) {
            HStack(spacing: 0) {
                Text(formatDuration(elapsedSeconds))
                    .font(.caption.monospacedDigit().weight(.medium))
                    .foregroundStyle(.secondary)
                Spacer()
                if !challengeMode && metronomeEnabled {
                    HStack(spacing: 4) {
                        Image(systemName: "metronome.fill")
                            .font(.caption2)
                        Text("\(selectedBPM) BPM")
                            .font(.caption.monospacedDigit().weight(.medium))
                    }
                    .foregroundStyle(pathColor)
                } else if challengeMode {
                    HStack(spacing: 4) {
                        Image(systemName: "metronome.fill")
                            .font(.caption2)
                        Text("\(selectedBPM) BPM")
                            .font(.caption.monospacedDigit().weight(.medium))
                    }
                    .foregroundStyle(.red)
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 12)

            HStack(spacing: 0) {
                statColumn(value: "\(detector.jumpCount)", label: "JUMPS")
                Divider().frame(height: 36)
                statColumn(value: "\(max(0, targetJumps - detector.jumpCount))", label: "LEFT")
                Divider().frame(height: 36)
                statColumn(value: "\(detector.bestStreak)", label: "STREAK")
                if challengeMode {
                    Divider().frame(height: 36)
                    statColumn(value: "\(metronome.missedBeatCount)", label: "MISSES", highlight: true)
                } else if metronomeEnabled {
                    Divider().frame(height: 36)
                    statColumn(value: "\(metronome.onBeatJumps)", label: "ON BEAT")
                }
            }
            .padding(.vertical, 10)
            .background(Color(.secondarySystemGroupedBackground), in: .rect(cornerRadius: 14))
            .padding(.horizontal, 16)

            ZStack {
                Circle()
                    .stroke(Color(.systemGray5), lineWidth: 10)
                    .frame(width: 120, height: 120)

                Circle()
                    .trim(from: 0, to: progress)
                    .stroke(
                        goalReached ? Color.green.gradient : (challengeMode ? Color.red.gradient : pathColor.gradient),
                        style: StrokeStyle(lineWidth: 10, lineCap: .round)
                    )
                    .rotationEffect(.degrees(-90))
                    .frame(width: 120, height: 120)
                    .animation(.spring(response: 0.3), value: progress)

                VStack(spacing: 2) {
                    Text("\(detector.jumpCount)")
                        .font(.system(size: 36, weight: .heavy, design: .rounded))
                        .contentTransition(.numericText())
                        .animation(.spring(response: 0.3), value: detector.jumpCount)
                    Image(systemName: "figure.jumprope")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
            }
            .padding(.vertical, 4)

            if goalReached && !gameOver {
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
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }

            if metronomeEnabled && !challengeMode {
                HStack(spacing: 20) {
                    Button {
                        metronome.updateBPM(selectedBPM - 5)
                        selectedBPM = metronome.bpm
                    } label: {
                        Image(systemName: "tortoise.fill")
                            .font(.body)
                            .foregroundStyle(.secondary)
                            .frame(width: 44, height: 44)
                            .background(Color(.tertiarySystemGroupedBackground), in: Circle())
                    }

                    Button {
                        metronome.updateBPM(selectedBPM + 5)
                        selectedBPM = metronome.bpm
                    } label: {
                        Image(systemName: "hare.fill")
                            .font(.body)
                            .foregroundStyle(.secondary)
                            .frame(width: 44, height: 44)
                            .background(Color(.tertiarySystemGroupedBackground), in: Circle())
                    }
                }
                .padding(.bottom, 4)
            }
        }
        .padding(.bottom, 16)
        .background(Color(.systemGroupedBackground))
        .animation(.spring(response: 0.3), value: goalReached)
    }

    private func statColumn(value: String, label: String, highlight: Bool = false) -> some View {
        VStack(spacing: 4) {
            Text(value)
                .font(.headline.monospacedDigit())
                .foregroundStyle(highlight ? .red : .primary)
                .contentTransition(.numericText())
            Text(label)
                .font(.caption2.weight(.medium))
                .foregroundStyle(highlight ? .red.opacity(0.7) : .secondary)
        }
        .frame(maxWidth: .infinity)
    }

    private func prepareSession() {
        sessionActive = false
        pulseGoal = false
        elapsedSeconds = 0
        previousJumpCount = 0
        hearts = maxHearts
        gameOver = false
        heartShake = false
        heartLostTrigger = 0
        bodyReadyProgress = 0
        showAutoStartCountdown = false
        autoStartCountdownValue = 0
        readinessTask?.cancel()
        readinessTask = nil
        countdownTask?.cancel()
        countdownTask = nil
        timer?.invalidate()
        timer = nil
        metronome.stop()
        startTime = nil
        detector.reset()
        detector.setCountingEnabled(false)
        detector.start()
    }

    private func startSession() {
        sessionActive = true
        pulseGoal = false
        detector.reset()
        startTime = Date()
        elapsedSeconds = 0
        previousJumpCount = 0
        hearts = maxHearts
        gameOver = false
        heartShake = false
        heartLostTrigger = 0
        bodyReadyProgress = 0
        showAutoStartCountdown = false
        autoStartCountdownValue = 0

        detector.start()

        Task { @MainActor in
            let startupDeadline = Date().addingTimeInterval(2.5)
            while !detector.cameraAvailable && Date() < startupDeadline {
                try? await Task.sleep(for: .milliseconds(100))
            }
            guard sessionActive else { return }
            detector.setCountingEnabled(true)
            if metronomeEnabled || challengeMode {
                metronome.bpm = selectedBPM
                metronome.start()
            }
            startTimer()
        }
    }

    private func endSession() {
        sessionActive = false
        readinessTask?.cancel()
        readinessTask = nil
        countdownTask?.cancel()
        countdownTask = nil
        timer?.invalidate()
        timer = nil
        metronome.stop()
        detector.setCountingEnabled(false)
        detector.stop()

        let session = ExerciseSession(
            id: UUID().uuidString,
            exerciseType: .jumpRope,
            startedAt: startTime,
            endedAt: Date(),
            totalFramesAnalyzed: detector.totalFramesAnalyzed,
            framesWithBodyDetected: detector.framesWithBody,
            averageConfidence: detector.currentConfidence,
            bodyLostCount: detector.bodyLostCount,
            jumpCount: detector.jumpCount,
            targetJumps: targetJumps,
            bestStreakJumps: detector.bestStreak,
            bpmUsed: metronomeEnabled ? selectedBPM : 0,
            onBeatJumps: metronome.onBeatJumps
        )

        withAnimation(.spring(response: 0.4)) {
            completedSession = session
        }
    }

    private func handleDetectorPresenceChanged(_ ready: Bool) {
        guard !sessionActive, !gameOver else { return }
        if ready {
            beginReadinessHoldIfNeeded()
        } else {
            cancelAutoStartSequence(resetProgress: true)
        }
    }

    private func beginReadinessHoldIfNeeded() {
        guard !sessionActive, !showAutoStartCountdown, readinessTask == nil else { return }
        readinessTask = Task { @MainActor in
            bodyReadyProgress = 0
            for step in 1...20 {
                try? await Task.sleep(for: .milliseconds(100))
                guard !Task.isCancelled else { return }
                guard detector.positioningReady, !sessionActive else {
                    bodyReadyProgress = 0
                    readinessTask = nil
                    return
                }
                bodyReadyProgress = Double(step) / 20.0
            }
            readinessTask = nil
            beginAutoStartCountdown()
        }
    }

    private func beginAutoStartCountdown() {
        guard !sessionActive, !showAutoStartCountdown else { return }
        showAutoStartCountdown = true
        autoStartCountdownValue = 5
        countdownTask = Task { @MainActor in
            for value in stride(from: 5, through: 1, by: -1) {
                guard !Task.isCancelled else { return }
                guard detector.positioningReady else {
                    cancelAutoStartSequence(resetProgress: true)
                    return
                }
                autoStartCountdownValue = value
                try? await Task.sleep(for: .seconds(1))
            }
            countdownTask = nil
            showAutoStartCountdown = false
            bodyReadyProgress = 0
            startSession()
        }
    }

    private func cancelAutoStartSequence(resetProgress: Bool) {
        readinessTask?.cancel()
        readinessTask = nil
        countdownTask?.cancel()
        countdownTask = nil
        showAutoStartCountdown = false
        autoStartCountdownValue = 0
        if resetProgress {
            bodyReadyProgress = 0
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
}

