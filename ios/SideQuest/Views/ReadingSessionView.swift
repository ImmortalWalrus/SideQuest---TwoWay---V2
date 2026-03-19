import SwiftUI
import UIKit
import AVFoundation

struct ReadingSessionView: View {
    let quest: Quest
    let instanceId: String
    let appState: AppState
    @Environment(\.dismiss) private var dismiss
    @State private var sessionActive: Bool = false
    @State private var readingSeconds: TimeInterval = 0
    @State private var startTime: Date?
    @State private var timer: Timer?
    @State private var completedSession: ReadingSession?
    @State private var countdownValue: Int = 0
    @State private var countdownTimer: Timer?
    @State private var showPhotoCapture: Bool = false
    @State private var cameraService = TimelapseCameraService()
    @State private var capturedPhoto: UIImage?
    @State private var pulseGoal: Bool = false

    private var targetDuration: TimeInterval { quest.targetHoldSeconds ?? 600 }
    private var pathColor: Color { PathColorHelper.color(for: quest.path) }
    private var goalReached: Bool { readingSeconds >= targetDuration }
    private var progress: Double { min(1.0, readingSeconds / max(1, targetDuration)) }
    private var timeRemaining: TimeInterval { max(0, targetDuration - readingSeconds) }

    private var currentXP: Int {
        let baseXP = Double(quest.xpReward)
        let progressFraction = min(1.0, readingSeconds / max(1, targetDuration))
        return Int(baseXP * progressFraction)
    }

    var body: some View {
        NavigationStack {
            if let session = completedSession {
                ReadingSummaryView(
                    session: session,
                    quest: quest,
                    capturedPhoto: capturedPhoto,
                    onSubmit: {
                        appState.submitReadingEvidence(for: instanceId, session: session)
                        dismiss()
                    },
                    onDiscard: { dismiss() }
                )
            } else if showPhotoCapture {
                photoCaptureView
            } else {
                mainContent
            }
        }
        .interactiveDismissDisabled(sessionActive)
    }

    private var mainContent: some View {
        ZStack {
            Color(.systemBackground).ignoresSafeArea()

            VStack(spacing: 0) {
                Spacer()

                if sessionActive {
                    activeTimerView
                } else {
                    setupView
                }

                Spacer()

                controlPanel
            }
        }
        .onDisappear {
            timer?.invalidate()
            countdownTimer?.invalidate()
            appState.isImmersive = false
        }
        .onAppear {
            appState.isImmersive = true
        }
        .onChange(of: goalReached) { _, reached in
            if reached {
                withAnimation(.easeInOut(duration: 0.8).repeatForever(autoreverses: true)) {
                    pulseGoal = true
                }
            }
        }
        .sensoryFeedback(.success, trigger: goalReached)
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                if !sessionActive {
                    Button("Close") { dismiss() }
                }
            }
        }
    }

    // MARK: - Setup

    private var setupView: some View {
        VStack(spacing: 24) {
            ZStack {
                Circle()
                    .fill(pathColor.opacity(0.1))
                    .frame(width: 120, height: 120)
                Image(systemName: "book.fill")
                    .font(.system(size: 48))
                    .foregroundStyle(pathColor)
            }

            VStack(spacing: 8) {
                HStack(spacing: 8) {
                    PathBadgeView(path: quest.path)
                    if quest.type == .verified {
                        VerifiedBadge(isVerified: true)
                    }
                }

                Text("Reading Session")
                    .font(.title2.weight(.bold))
                Text("Read for \(formatDuration(targetDuration))")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            if countdownValue > 0 {
                Text("\(countdownValue)")
                    .font(.system(size: 72, weight: .bold, design: .rounded))
                    .foregroundStyle(pathColor)
                    .contentTransition(.numericText())
                    .transition(.scale.combined(with: .opacity))
            }

            VStack(spacing: 6) {
                Label("Find a quiet spot and grab your book", systemImage: "book.fill")
                Label("Timer runs until you end the session", systemImage: "timer")
                Label("Take a photo of your book when done", systemImage: "camera.fill")
            }
            .font(.caption)
            .foregroundStyle(.tertiary)
        }
        .animation(.spring(response: 0.3), value: countdownValue)
    }

    // MARK: - Active Timer

    private var activeTimerView: some View {
        VStack(spacing: 32) {
            ZStack {
                Circle()
                    .stroke(Color(.systemGray5), lineWidth: 8)
                    .frame(width: 220, height: 220)

                Circle()
                    .trim(from: 0, to: progress)
                    .stroke(
                        goalReached ? Color.green.gradient : pathColor.gradient,
                        style: StrokeStyle(lineWidth: 8, lineCap: .round)
                    )
                    .frame(width: 220, height: 220)
                    .rotationEffect(.degrees(-90))
                    .animation(.linear(duration: 0.5), value: progress)

                VStack(spacing: 8) {
                    Text(formatDuration(timeRemaining))
                        .font(.system(size: 44, weight: .thin, design: .rounded))
                        .contentTransition(.numericText())

                    Text("remaining")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            if goalReached {
                Label("Goal Reached!", systemImage: "checkmark.circle.fill")
                    .font(.headline.weight(.bold))
                    .foregroundStyle(.green)
                    .padding(.horizontal, 20)
                    .padding(.vertical, 12)
                    .background(.green.opacity(0.1), in: Capsule())
                    .scaleEffect(pulseGoal ? 1.05 : 1.0)
                    .transition(.scale.combined(with: .opacity))
            }

            HStack(spacing: 4) {
                Image(systemName: "sparkles")
                    .font(.caption)
                Text("+\(currentXP) XP so far")
                    .font(.subheadline.weight(.medium))
            }
            .foregroundStyle(pathColor.opacity(0.9))
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .background(.ultraThinMaterial, in: Capsule())
        }
    }

    // MARK: - Control Panel

    private var controlPanel: some View {
        VStack(spacing: 16) {
            if sessionActive {
                HStack(spacing: 16) {
                    VStack(spacing: 4) {
                        Text(formatDuration(readingSeconds))
                            .font(.headline.monospacedDigit())
                        Text("Reading")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity)

                    Divider().frame(height: 36)

                    VStack(spacing: 4) {
                        Text(formatDuration(targetDuration))
                            .font(.headline.monospacedDigit())
                        Text("Target")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity)
                }

                Button {
                    endSession()
                } label: {
                    Label(
                        goalReached ? "Finish & Take Photo" : "End Session",
                        systemImage: goalReached ? "camera.fill" : "stop.fill"
                    )
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 6)
                }
                .buttonStyle(.borderedProminent)
                .tint(goalReached ? .green : .secondary)
                .scaleEffect(pulseGoal && goalReached ? 1.03 : 1.0)
            } else {
                Button {
                    startCountdown()
                } label: {
                    Label("Start Reading", systemImage: "play.fill")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 6)
                }
                .buttonStyle(.borderedProminent)
                .tint(pathColor)
                .disabled(countdownValue > 0)
            }
        }
        .padding(20)
        .padding(.bottom, 8)
        .background(.ultraThinMaterial)
    }

    // MARK: - Photo Capture

    private var photoCaptureView: some View {
        ZStack {
            cameraLayer

            VStack {
                Spacer()

                VStack(spacing: 16) {
                    Text("Take a photo of your book")
                        .font(.headline)
                        .foregroundStyle(.white)

                    Button {
                        Task {
                            let photo = await cameraService.capturePhoto()
                            capturedPhoto = photo
                            cameraService.stop()
                            finalizeSession()
                        }
                    } label: {
                        ZStack {
                            Circle()
                                .strokeBorder(.white, lineWidth: 4)
                                .frame(width: 80, height: 80)
                            Circle()
                                .fill(.white)
                                .frame(width: 64, height: 64)
                        }
                    }
                    .buttonStyle(.plain)

                    Button("Skip Photo") {
                        cameraService.stop()
                        finalizeSession()
                    }
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.white.opacity(0.7))
                }
                .padding(.bottom, 40)
                .padding(.top, 16)
                .frame(maxWidth: .infinity)
                .background(
                    LinearGradient(colors: [.clear, .black.opacity(0.7)], startPoint: .top, endPoint: .bottom)
                )
            }
        }
        .onAppear {
            cameraService.configure(front: false)
            cameraService.start()
        }
        .onDisappear {
            cameraService.stop()
        }
        .navigationTitle("Photo Evidence")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarColorScheme(.dark, for: .navigationBar)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button("Back") {
                    cameraService.stop()
                    showPhotoCapture = false
                    sessionActive = true
                }
                .foregroundStyle(.white)
            }
        }
    }

    @ViewBuilder
    private var cameraLayer: some View {
        Group {
            #if targetEnvironment(simulator)
            cameraPlaceholder
            #else
            if AVCaptureDevice.default(for: .video) != nil {
                CameraPreviewView(session: cameraService.captureSession)
                    .ignoresSafeArea()
                    .overlay {
                        Color.black.opacity(0.15)
                            .ignoresSafeArea()
                            .allowsHitTesting(false)
                    }
            } else {
                cameraPlaceholder
            }
            #endif
        }
    }

    private var cameraPlaceholder: some View {
        VStack(spacing: 20) {
            Image(systemName: "camera.fill")
                .font(.system(size: 56))
                .foregroundStyle(.secondary)
            Text("Camera Preview")
                .font(.title2.weight(.semibold))
            Text("Install this app on your device\nvia the Rork App to use the camera.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(.systemBackground))
    }

    // MARK: - Session Logic

    private func startCountdown() {
        countdownValue = 3
        countdownTimer?.invalidate()
        countdownTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { _ in
            Task { @MainActor in
                countdownValue -= 1
                if countdownValue <= 0 {
                    countdownTimer?.invalidate()
                    countdownTimer = nil
                    startReadingSession()
                }
            }
        }
    }

    private func startReadingSession() {
        sessionActive = true
        readingSeconds = 0
        startTime = Date()
        pulseGoal = false
        startTimer()
    }

    private func endSession() {
        sessionActive = false
        timer?.invalidate()
        timer = nil
        showPhotoCapture = true
    }

    private func finalizeSession() {
        var flags: [ReadingIntegrityFlag] = []
        if readingSeconds < 30 { flags.append(.tooShort) }
        if capturedPhoto == nil { flags.append(.noPhoto) }

        let session = ReadingSession(
            id: UUID().uuidString,
            startedAt: startTime,
            endedAt: Date(),
            readingDurationSeconds: readingSeconds,
            targetDurationSeconds: targetDuration,
            photoTaken: capturedPhoto != nil,
            integrityFlags: flags,
            wasDisqualified: false
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
                readingSeconds = Date().timeIntervalSince(start)
            }
        }
    }

    private func formatDuration(_ seconds: TimeInterval) -> String {
        let total = Int(max(0, seconds))
        let m = total / 60
        let s = total % 60
        return String(format: "%d:%02d", m, s)
    }
}
