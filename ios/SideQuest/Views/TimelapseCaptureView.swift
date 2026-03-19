import SwiftUI
import AVFoundation

nonisolated enum TimelapsePhase: Equatable {
    case ready
    case recording
    case review
    case memoryRecall
}

struct TimelapseCaptureView: View {
    let quest: Quest
    let instanceId: String
    let appState: AppState
    @Environment(\.dismiss) private var dismiss

    @State private var phase: TimelapsePhase = .ready
    @State private var cameraService = TimelapseCameraService()
    @State private var elapsed: TimeInterval = 0
    @State private var frameCount: Int = 0
    @State private var sessionTimer: Timer?
    @State private var frameTimer: Timer?
    @State private var showSubmitConfirm: Bool = false
    @State private var recPulse: Bool = false
    @State private var shutterFlash: Bool = false
    @State private var recallText: String = ""
    @State private var recallSubmitted: Bool = false
    @State private var startCheckpoint: TimeCheckpoint?
    @State private var uptimeAtStart: TimeInterval = 0
    @State private var clockTampered: Bool = false

    private var minDuration: TimeInterval { TimeInterval(quest.minCompletionMinutes * 60) }
    private var canStop: Bool { minDuration == 0 || elapsed >= minDuration }
    private var pathColor: Color { PathColorHelper.color(for: quest.path) }

    private var captureInterval: TimeInterval {
        let m = quest.minCompletionMinutes
        switch m {
        case 0..<15:  return 8
        case 15..<25: return 10
        case 25..<45: return 15
        default:      return 20
        }
    }

    private var estimatedFrames: Int {
        guard minDuration > 0 else { return 0 }
        return Int(minDuration / captureInterval)
    }

    private var isReadingQuest: Bool {
        quest.title.lowercased().contains("read")
    }

    private var shouldPlugIn: Bool {
        quest.minCompletionMinutes >= 20
    }

    private var elapsedFormatted: String {
        let m = Int(elapsed) / 60
        let s = Int(elapsed) % 60
        return String(format: "%02d:%02d", m, s)
    }

    private var remainingFormatted: String {
        let r = max(0, minDuration - elapsed)
        let m = Int(r) / 60
        let s = Int(r) % 60
        return String(format: "%02d:%02d", m, s)
    }

    private var intervalLabel: String {
        let i = Int(captureInterval)
        return "1 frame every \(i)s"
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Color.black.ignoresSafeArea()

                switch phase {
                case .ready:
                    readyView
                case .recording:
                    recordingView
                case .review:
                    reviewView
                case .memoryRecall:
                    memoryRecallView
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    if phase != .memoryRecall {
                        Button("Cancel") {
                            stopTimers()
                            cameraService.stop()
                            dismiss()
                        }
                        .foregroundStyle(.white)
                    }
                }
                ToolbarItem(placement: .principal) {
                    Label(quest.title, systemImage: "timelapse")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.white)
                        .lineLimit(1)
                }
            }
            .toolbarBackground(.hidden, for: .navigationBar)
            .alert("Submit Timelapse?", isPresented: $showSubmitConfirm) {
                Button("Submit") {
                    appState.submitEvidence(for: instanceId)
                    dismiss()
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("\(frameCount) frames captured across \(elapsedFormatted). Submitting for community verification.")
            }
        }
        .onAppear {
            cameraService.configure(front: true)
            cameraService.start()
            appState.isImmersive = true
        }
        .onDisappear {
            stopTimers()
            cameraService.stop()
            appState.isImmersive = false
        }
        .interactiveDismissDisabled(phase == .recording)
    }

    // MARK: - Ready / Setup

    private var readyView: some View {
        ScrollView {
            VStack(spacing: 0) {
                cameraSetupPreview
                    .frame(height: 220)

                VStack(spacing: 24) {
                    VStack(spacing: 6) {
                        Text(quest.title)
                            .font(.title2.weight(.bold))
                            .foregroundStyle(.white)
                        Text("Timelapse Session")
                            .font(.subheadline)
                            .foregroundStyle(.white.opacity(0.45))
                    }
                    .padding(.top, 24)

                    sessionInfoRow

                    if shouldPlugIn {
                        plugInBanner
                    }

                    phonePlacementCard

                    Button {
                        beginRecording()
                    } label: {
                        HStack(spacing: 10) {
                            Circle()
                                .fill(.red)
                                .frame(width: 11, height: 11)
                            Text("Start Recording")
                                .font(.headline)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                        .background(pathColor, in: .rect(cornerRadius: 16))
                        .foregroundStyle(.white)
                    }
                    .buttonStyle(.plain)
                    .padding(.bottom, 32)
                }
                .padding(.horizontal, 20)
            }
        }
        .scrollBounceBehavior(.basedOnSize)
    }

    private var cameraSetupPreview: some View {
        ZStack {
            #if targetEnvironment(simulator)
            Color(white: 0.08).ignoresSafeArea(edges: .top)
            VStack(spacing: 10) {
                Image(systemName: "timelapse")
                    .font(.system(size: 36))
                    .foregroundStyle(.white.opacity(0.2))
                Text("Camera Preview")
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.2))
            }
            #else
            if AVCaptureDevice.default(for: .video) != nil {
                CameraPreviewView(session: cameraService.captureSession)
            } else {
                Color(white: 0.08)
                VStack(spacing: 10) {
                    Image(systemName: "timelapse")
                        .font(.system(size: 36))
                        .foregroundStyle(.white.opacity(0.2))
                    Text("Camera unavailable")
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.2))
                }
            }
            #endif

            LinearGradient(
                colors: [.clear, .black],
                startPoint: .top,
                endPoint: .bottom
            )
        }
        .clipped()
    }

    private var sessionInfoRow: some View {
        HStack(spacing: 0) {
            infoCell(
                icon: "clock.fill",
                value: quest.minCompletionMinutes > 0 ? "\(quest.minCompletionMinutes) min" : "Open",
                label: "Duration",
                color: pathColor
            )
            Rectangle()
                .fill(.white.opacity(0.1))
                .frame(width: 1, height: 44)
            infoCell(
                icon: "camera.shutter.button.fill",
                value: intervalLabel,
                label: "Capture Rate",
                color: .white
            )
            if estimatedFrames > 0 {
                Rectangle()
                    .fill(.white.opacity(0.1))
                    .frame(width: 1, height: 44)
                infoCell(
                    icon: "photo.stack.fill",
                    value: "~\(estimatedFrames)",
                    label: "Est. Frames",
                    color: .white
                )
            }
        }
        .padding(.vertical, 14)
        .background(.white.opacity(0.07), in: .rect(cornerRadius: 16))
    }

    private func infoCell(icon: String, value: String, label: String, color: Color) -> some View {
        VStack(spacing: 5) {
            Image(systemName: icon)
                .font(.system(size: 13))
                .foregroundStyle(color.opacity(0.8))
            Text(value)
                .font(.system(size: 13, weight: .semibold, design: .monospaced))
                .foregroundStyle(.white)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            Text(label)
                .font(.system(size: 10))
                .foregroundStyle(.white.opacity(0.4))
        }
        .frame(maxWidth: .infinity)
    }

    private var plugInBanner: some View {
        HStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 10)
                    .fill(Color.yellow.opacity(0.15))
                    .frame(width: 40, height: 40)
                Image(systemName: "bolt.fill")
                    .font(.system(size: 16))
                    .foregroundStyle(.yellow)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text("Plug In Recommended")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.white)
                Text("This session lasts \(quest.minCompletionMinutes) minutes. Keeping your phone charged ensures no interruptions.")
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.5))
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer()
        }
        .padding(14)
        .background(.yellow.opacity(0.08), in: .rect(cornerRadius: 14))
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .stroke(Color.yellow.opacity(0.2), lineWidth: 1)
        )
    }

    private var phonePlacementCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 10) {
                Image(systemName: "iphone.gen3")
                    .font(.system(size: 15))
                    .foregroundStyle(pathColor)
                Text("Before You Start")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.white)
            }

            VStack(spacing: 10) {
                placementRow(
                    icon: "table.furniture.fill",
                    text: "Set your phone on a flat, stable surface facing you"
                )
                placementRow(
                    icon: "eye.fill",
                    text: "Make sure your face and workspace are visible"
                )
                placementRow(
                    icon: "bell.slash.fill",
                    text: "Enable Do Not Disturb to avoid interruptions"
                )
                if isReadingQuest {
                    placementRow(
                        icon: "text.quote",
                        text: "You'll be asked to log a few sentences about what you read afterward"
                    )
                }
            }
        }
        .padding(16)
        .background(.white.opacity(0.05), in: .rect(cornerRadius: 16))
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(Color.white.opacity(0.08), lineWidth: 1)
        )
    }

    private func placementRow(icon: String, text: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 12))
                .foregroundStyle(pathColor.opacity(0.7))
                .frame(width: 18)
                .padding(.top, 1)
            Text(text)
                .font(.caption)
                .foregroundStyle(.white.opacity(0.6))
                .fixedSize(horizontal: false, vertical: true)
            Spacer()
        }
    }

    // MARK: - Recording

    private var recordingView: some View {
        ZStack {
            cameraPreview

            if shutterFlash {
                Color.white.opacity(0.55)
                    .ignoresSafeArea()
                    .transition(.opacity)
            }

            VStack {
                HStack {
                    HStack(spacing: 6) {
                        Circle()
                            .fill(.red)
                            .frame(width: 10, height: 10)
                            .opacity(recPulse ? 0.2 : 1.0)
                            .animation(.easeInOut(duration: 0.7).repeatForever(autoreverses: true), value: recPulse)
                        Text("REC")
                            .font(.system(size: 12, weight: .bold, design: .monospaced))
                            .foregroundStyle(.white)
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(.black.opacity(0.55), in: Capsule())

                    Spacer()

                    HStack(spacing: 5) {
                        Image(systemName: "photo.stack.fill")
                            .font(.system(size: 11))
                        Text("\(frameCount)")
                            .font(.system(size: 12, weight: .semibold, design: .monospaced))
                        Text("·")
                            .foregroundStyle(.white.opacity(0.3))
                        Text(intervalLabel)
                            .font(.system(size: 10, design: .monospaced))
                            .foregroundStyle(.white.opacity(0.6))
                    }
                    .foregroundStyle(.white)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(.black.opacity(0.55), in: Capsule())
                }
                .padding(.horizontal, 20)
                .padding(.top, 8)

                Spacer()
            }

            VStack {
                Spacer()

                VStack(spacing: 18) {
                    Text(elapsedFormatted)
                        .font(.system(size: 72, weight: .bold, design: .monospaced))
                        .foregroundStyle(.white)
                        .shadow(color: .black.opacity(0.6), radius: 8)

                    if minDuration > 0 {
                        VStack(spacing: 6) {
                            GeometryReader { geo in
                                ZStack(alignment: .leading) {
                                    Capsule()
                                        .fill(.white.opacity(0.18))
                                        .frame(height: 5)
                                    Capsule()
                                        .fill(canStop ? Color.green : pathColor)
                                        .frame(width: geo.size.width * min(elapsed / minDuration, 1.0), height: 5)
                                        .animation(.linear(duration: 1), value: elapsed)
                                }
                            }
                            .frame(height: 5)

                            HStack {
                                Text(canStop ? "✓ Minimum reached" : "Keep going...")
                                    .font(.caption2.weight(.semibold))
                                    .foregroundStyle(canStop ? .green : .white.opacity(0.5))
                                Spacer()
                                if !canStop {
                                    Text(remainingFormatted + " left")
                                        .font(.caption2.monospacedDigit())
                                        .foregroundStyle(.white.opacity(0.4))
                                }
                            }
                        }
                    }

                    Button {
                        guard canStop else { return }
                        stopTimers()
                        withAnimation(.snappy) { phase = .review }
                    } label: {
                        ZStack {
                            Circle()
                                .fill(canStop ? .white : .white.opacity(0.25))
                                .frame(width: 76, height: 76)
                            RoundedRectangle(cornerRadius: 6)
                                .fill(canStop ? .red : Color(white: 0.4))
                                .frame(width: 30, height: 30)
                        }
                    }
                    .buttonStyle(.plain)
                    .sensoryFeedback(.success, trigger: canStop)
                    .disabled(!canStop)
                }
                .padding(.horizontal, 28)
                .padding(.bottom, 32)
                .padding(.top, 20)
                .background(
                    LinearGradient(
                        colors: [.clear, .black.opacity(0.88)],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
            }
        }
        .onAppear { recPulse = true }
    }

    // MARK: - Review

    private var reviewView: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(spacing: 24) {
                    VStack(spacing: 10) {
                        ZStack {
                            Circle()
                                .fill(pathColor.opacity(0.18))
                                .frame(width: 80, height: 80)
                            Image(systemName: "checkmark.circle.fill")
                                .font(.system(size: 40))
                                .foregroundStyle(pathColor)
                        }
                        .padding(.top, 24)

                        Text("Timelapse Captured")
                            .font(.title2.weight(.bold))
                            .foregroundStyle(.white)

                        Text("\(frameCount) frames · \(elapsedFormatted)")
                            .font(.subheadline)
                            .foregroundStyle(.white.opacity(0.55))
                    }

                    filmstripGrid

                    statsRow
                        .padding(.horizontal, 16)

                    if isReadingQuest {
                        HStack(spacing: 10) {
                            Image(systemName: "text.quote")
                                .font(.system(size: 13))
                                .foregroundStyle(pathColor)
                            Text("One more step — log what you read to complete the quest.")
                                .font(.caption)
                                .foregroundStyle(.white.opacity(0.55))
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        .padding(14)
                        .background(.white.opacity(0.05), in: .rect(cornerRadius: 14))
                        .padding(.horizontal, 16)
                    }
                }
                .padding(.bottom, 24)
            }

            VStack(spacing: 10) {
                Button {
                    elapsed = 0
                    frameCount = 0
                    beginRecording()
                } label: {
                    Label("Retake", systemImage: "arrow.counterclockwise")
                        .font(.subheadline.weight(.semibold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 13)
                        .background(.white.opacity(0.1), in: .rect(cornerRadius: 14))
                        .foregroundStyle(.white)
                }
                .buttonStyle(.plain)

                Button {
                    if clockTampered || TimeIntegrityService.shared.hasTimeManipulation {
                        appState.submitEvidence(for: instanceId)
                        dismiss()
                        return
                    }
                    if isReadingQuest {
                        withAnimation(.snappy) { phase = .memoryRecall }
                    } else {
                        showSubmitConfirm = true
                    }
                } label: {
                    Label(
                        isReadingQuest ? "Continue to Reading Log" : "Submit Timelapse",
                        systemImage: isReadingQuest ? "text.quote" : "paperplane.fill"
                    )
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 15)
                    .background(pathColor, in: .rect(cornerRadius: 14))
                    .foregroundStyle(.white)
                }
                .buttonStyle(.plain)
                .sensoryFeedback(.impact(weight: .heavy), trigger: showSubmitConfirm)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 16)
            .background(.ultraThinMaterial.opacity(0.6))
        }
    }

    // MARK: - Memory Recall

    private var memoryRecallView: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(spacing: 24) {
                    VStack(spacing: 12) {
                        ZStack {
                            Circle()
                                .fill(pathColor.opacity(0.15))
                                .frame(width: 72, height: 72)
                            Image(systemName: "brain.head.profile.fill")
                                .font(.system(size: 32))
                                .foregroundStyle(pathColor)
                        }
                        .padding(.top, 28)

                        Text("Memory Recall")
                            .font(.title2.weight(.bold))
                            .foregroundStyle(.white)

                        Text("What did you read? Summarize the key ideas in a few sentences. This reinforces retention and verifies your session.")
                            .font(.subheadline)
                            .foregroundStyle(.white.opacity(0.5))
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 8)
                    }

                    VStack(alignment: .leading, spacing: 10) {
                        HStack {
                            Text("Your Notes")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.white.opacity(0.4))
                                .textCase(.uppercase)
                                .tracking(1)
                            Spacer()
                            Text("\(recallText.count) chars")
                                .font(.caption2.monospacedDigit())
                                .foregroundStyle(recallText.count >= 60 ? pathColor : .white.opacity(0.25))
                        }

                        ZStack(alignment: .topLeading) {
                            TextEditor(text: $recallText)
                                .font(.body)
                                .foregroundStyle(.white)
                                .scrollContentBackground(.hidden)
                                .frame(minHeight: 160)
                                .padding(14)
                                .background(.white.opacity(0.07), in: .rect(cornerRadius: 14))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 14)
                                        .stroke(recallText.isEmpty ? Color.white.opacity(0.08) : pathColor.opacity(0.4), lineWidth: 1)
                                )

                            if recallText.isEmpty {
                                Text("E.g. \"I read about habit formation in Atomic Habits. The main takeaway was the 1% improvement concept — small daily gains compound into massive results over time...\"")
                                    .font(.body)
                                    .foregroundStyle(.white.opacity(0.2))
                                    .padding(14 + 4)
                                    .allowsHitTesting(false)
                            }
                        }

                        HStack(spacing: 6) {
                            Image(systemName: "lock.fill")
                                .font(.system(size: 10))
                                .foregroundStyle(.white.opacity(0.2))
                            Text("Shared only with moderators for verification")
                                .font(.caption2)
                                .foregroundStyle(.white.opacity(0.25))
                        }
                        .padding(.top, 2)
                    }
                    .padding(.horizontal, 20)

                    recallPromptCards
                        .padding(.horizontal, 20)
                        .padding(.bottom, 24)
                }
            }

            VStack(spacing: 10) {
                if recallText.count < 40 {
                    Text("Write at least a sentence or two to submit")
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.35))
                }

                Button {
                    guard recallText.count >= 40 else { return }
                    withAnimation(.snappy) { recallSubmitted = true }
                    appState.submitEvidence(for: instanceId)
                    dismiss()
                } label: {
                    Label("Submit Quest", systemImage: "paperplane.fill")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 15)
                        .background(
                            recallText.count >= 40 ? pathColor : Color.white.opacity(0.12),
                            in: .rect(cornerRadius: 14)
                        )
                        .foregroundStyle(recallText.count >= 40 ? .white : .white.opacity(0.3))
                }
                .buttonStyle(.plain)
                .disabled(recallText.count < 40)
                .animation(.easeOut(duration: 0.2), value: recallText.count >= 40)

                Button("Skip for now") {
                    showSubmitConfirm = true
                }
                .font(.caption)
                .foregroundStyle(.white.opacity(0.3))
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 16)
            .background(.ultraThinMaterial.opacity(0.6))
        }
        .alert("Submit without notes?", isPresented: $showSubmitConfirm) {
            Button("Submit Anyway") {
                appState.submitEvidence(for: instanceId)
                dismiss()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Memory recall notes improve your verification score and help solidify what you learned.")
        }
    }

    private var recallPromptCards: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Prompts")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.white.opacity(0.4))
                .textCase(.uppercase)
                .tracking(1)

            VStack(spacing: 8) {
                promptRow("💡", "What was the main idea or argument?")
                promptRow("🔁", "What's one thing you'll apply or remember?")
                promptRow("❓", "What question did this raise for you?")
            }
        }
    }

    private func promptRow(_ emoji: String, _ text: String) -> some View {
        HStack(spacing: 10) {
            Text(emoji)
                .font(.system(size: 13))
            Text(text)
                .font(.caption)
                .foregroundStyle(.white.opacity(0.45))
            Spacer()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
        .background(.white.opacity(0.04), in: .rect(cornerRadius: 10))
    }

    // MARK: - Shared subviews

    private var filmstripGrid: some View {
        let cols = [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())]
        let displayCount = min(frameCount, 32)
        let hasOverflow = frameCount > 32

        return LazyVGrid(columns: cols, spacing: 3) {
            ForEach(0..<displayCount, id: \.self) { i in
                let pct = Double(i) / Double(max(frameCount - 1, 1))
                RoundedRectangle(cornerRadius: 4)
                    .fill(Color(
                        hue: 0.58 + pct * 0.12,
                        saturation: 0.35 + pct * 0.25,
                        brightness: 0.25 + pct * 0.35
                    ))
                    .frame(height: 56)
                    .overlay(alignment: .bottomLeading) {
                        Text("\(i + 1)")
                            .font(.system(size: 8, weight: .medium, design: .monospaced))
                            .foregroundStyle(.white.opacity(0.45))
                            .padding(3)
                    }
            }

            if hasOverflow {
                RoundedRectangle(cornerRadius: 4)
                    .fill(.white.opacity(0.07))
                    .frame(height: 56)
                    .overlay {
                        Text("+\(frameCount - 32)")
                            .font(.caption.weight(.bold))
                            .foregroundStyle(.white.opacity(0.4))
                    }
            }
        }
        .padding(.horizontal, 16)
    }

    private var statsRow: some View {
        HStack(spacing: 0) {
            statCell(value: elapsedFormatted, label: "Duration")
            Divider().frame(height: 36).background(.white.opacity(0.2))
            statCell(value: "\(frameCount)", label: "Frames")
            Divider().frame(height: 36).background(.white.opacity(0.2))
            statCell(value: "\(Int(captureInterval))s", label: "Interval")
            if quest.minCompletionMinutes > 0 {
                Divider().frame(height: 36).background(.white.opacity(0.2))
                statCell(value: canStop ? "✓" : "✗", label: "Min Met", color: canStop ? .green : .red)
            }
        }
        .padding(.vertical, 14)
        .background(.white.opacity(0.07), in: .rect(cornerRadius: 14))
    }

    private func statCell(value: String, label: String, color: Color = .white) -> some View {
        VStack(spacing: 4) {
            Text(value)
                .font(.system(size: 15, weight: .bold, design: .monospaced))
                .foregroundStyle(color)
            Text(label)
                .font(.system(size: 10))
                .foregroundStyle(.white.opacity(0.45))
        }
        .frame(maxWidth: .infinity)
    }

    @ViewBuilder
    private var cameraPreview: some View {
        #if targetEnvironment(simulator)
        cameraPlaceholder
        #else
        if AVCaptureDevice.default(for: .video) != nil {
            CameraPreviewView(session: cameraService.captureSession)
                .ignoresSafeArea()
        } else {
            cameraPlaceholder
        }
        #endif
    }

    private var cameraPlaceholder: some View {
        ZStack {
            Color(white: 0.07).ignoresSafeArea()
            VStack(spacing: 14) {
                Image(systemName: "timelapse")
                    .font(.system(size: 44))
                    .foregroundStyle(.white.opacity(0.25))
                Text("Camera Preview")
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.white.opacity(0.35))
                Text("Install on your device via the Rork App\nto use the camera.")
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.2))
                    .multilineTextAlignment(.center)
            }
        }
    }

    private func beginRecording() {
        if !cameraService.isRunning {
            cameraService.start()
        }

        withAnimation(.snappy) { phase = .recording }
        startCheckpoint = TimeIntegrityService.shared.recordCheckpoint()
        uptimeAtStart = ProcessInfo.processInfo.systemUptime
        clockTampered = false

        sessionTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { _ in
            Task { @MainActor in
                let monotonicElapsed = ProcessInfo.processInfo.systemUptime - self.uptimeAtStart
                let drift = abs(self.elapsed + 1 - monotonicElapsed)
                if drift > 5 {
                    self.clockTampered = true
                }
                self.elapsed = monotonicElapsed
            }
        }
        frameTimer = Timer.scheduledTimer(withTimeInterval: captureInterval, repeats: true) { _ in
            Task { @MainActor in
                self.frameCount += 1
            }
        }
    }

    private func stopTimers() {
        sessionTimer?.invalidate()
        frameTimer?.invalidate()
        sessionTimer = nil
        frameTimer = nil
    }
}
