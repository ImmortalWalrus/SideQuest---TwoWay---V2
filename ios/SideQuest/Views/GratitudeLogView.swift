import SwiftUI
import AVFoundation

struct GratitudeLogView: View {
    let quest: Quest
    let instanceId: String
    let appState: AppState
    @Environment(\.dismiss) private var dismiss
    @State private var step: GratitudeStep = .write
    @State private var showSubmitConfirm: Bool = false
    @State private var cameraService = TimelapseCameraService()

    private var pathColor: Color {
        PathColorHelper.color(for: quest.path)
    }

    private var dailyPrompt: String {
        let prompts = [
            "What made you smile today?",
            "Who are you thankful for and why?",
            "What small moment brought you joy recently?",
            "What ability or skill are you grateful to have?",
            "What challenge helped you grow?",
            "What part of your daily routine do you appreciate?",
            "What's something beautiful you noticed today?",
        ]
        let dayOfYear = Calendar.current.ordinality(of: .day, in: .year, for: Date()) ?? 0
        return prompts[dayOfYear % prompts.count]
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                switch step {
                case .write:
                    writePromptView
                case .capture:
                    captureView
                case .review:
                    reviewView
                }
            }
            .background(Color(.systemGroupedBackground))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
            .alert("Submit Entry?", isPresented: $showSubmitConfirm) {
                Button("Submit") {
                    appState.submitEvidence(for: instanceId)
                    dismiss()
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("Your handwritten entry will be analyzed and sent for verification.")
            }
        }
        .presentationDragIndicator(.visible)
    }

    private var writePromptView: some View {
        ScrollView {
            VStack(spacing: 24) {
                VStack(spacing: 16) {
                    ZStack {
                        Circle()
                            .fill(.orange.opacity(0.12))
                            .frame(width: 80, height: 80)
                        Image(systemName: "square.and.pencil")
                            .font(.system(size: 34))
                            .foregroundStyle(.orange)
                    }
                    .padding(.top, 8)

                    Text(quest.title)
                        .font(.title2.weight(.bold))

                    Text(quest.description)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }

                VStack(alignment: .leading, spacing: 12) {
                    Label("Today's Prompt", systemImage: "sparkles")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.orange)

                    Text(dailyPrompt)
                        .font(.title3.weight(.medium))
                        .italic()
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(16)
                .background(
                    RoundedRectangle(cornerRadius: 14)
                        .fill(.orange.opacity(0.06))
                        .overlay(
                            RoundedRectangle(cornerRadius: 14)
                                .strokeBorder(.orange.opacity(0.15), lineWidth: 1)
                        )
                )

                VStack(alignment: .leading, spacing: 16) {
                    Text("How It Works")
                        .font(.headline)

                    GratitudeInstructionRow(number: 1, icon: "pencil.line", text: "Write your entry by hand on paper or in a journal")
                    GratitudeInstructionRow(number: 2, icon: "camera.fill", text: "Take a clear photo of your handwritten entry")
                    GratitudeInstructionRow(number: 3, icon: "checkmark.seal.fill", text: "Submit for verification to earn rewards")
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                VStack(alignment: .leading, spacing: 8) {
                    Label("Why Handwriting?", systemImage: "hand.draw")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.secondary)

                    Text("Writing by hand engages your brain differently than typing. It slows you down, helps you reflect deeper, and creates a physical record of your growth.")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(14)
                .background(Color(.secondarySystemGroupedBackground), in: .rect(cornerRadius: 12))

                Button {
                    withAnimation(.snappy) { step = .capture }
                } label: {
                    Label("I've Written My Entry", systemImage: "camera.fill")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(.orange)
                .padding(.top, 4)
            }
            .padding(16)
        }
    }

    private var captureView: some View {
        VStack(spacing: 0) {
            ZStack {
                gratitudeCameraPreview

                RoundedRectangle(cornerRadius: 12)
                    .strokeBorder(style: StrokeStyle(lineWidth: 2, dash: [8, 6]))
                    .foregroundStyle(.orange.opacity(0.4))
                    .padding(24)
                    .allowsHitTesting(false)

                VStack {
                    Spacer()
                    Text("Position your handwritten entry in frame")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.white.opacity(0.7))
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(.black.opacity(0.5), in: Capsule())
                        .padding(.bottom, 12)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            VStack(spacing: 16) {
                Button {
                    Task {
                        let _ = await cameraService.capturePhoto()
                        cameraService.stop()
                        withAnimation(.snappy) { step = .review }
                    }
                } label: {
                    ZStack {
                        Circle()
                            .fill(.orange)
                            .frame(width: 72, height: 72)
                        Circle()
                            .strokeBorder(.white, lineWidth: 3)
                            .frame(width: 64, height: 64)
                        Image(systemName: "camera.fill")
                            .font(.title2)
                            .foregroundStyle(.white)
                    }
                }
                .buttonStyle(.plain)
                .sensoryFeedback(.impact(weight: .medium), trigger: step)

                Button {
                    cameraService.stop()
                    withAnimation(.snappy) { step = .write }
                } label: {
                    Text("Back to Prompt")
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.vertical, 20)
            .background(Color(.systemGroupedBackground))
        }
        .onAppear {
            cameraService.configure(front: false)
            cameraService.start()
        }
        .onDisappear {
            cameraService.stop()
        }
    }

    @ViewBuilder
    private var gratitudeCameraPreview: some View {
        #if targetEnvironment(simulator)
        ZStack {
            Color(.secondarySystemGroupedBackground)
            VStack(spacing: 16) {
                Image(systemName: "camera.fill")
                    .font(.system(size: 48))
                    .foregroundStyle(.secondary)
                Text("Camera Preview")
                    .font(.title2.weight(.semibold))
                Text("Install this app on your device\nvia the Rork App to use the camera.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
        }
        #else
        if AVCaptureDevice.default(for: .video) != nil {
            CameraPreviewView(session: cameraService.captureSession)
        } else {
            ZStack {
                Color(.secondarySystemGroupedBackground)
                VStack(spacing: 16) {
                    Image(systemName: "camera.fill")
                        .font(.system(size: 48))
                        .foregroundStyle(.secondary)
                    Text("Camera Preview")
                        .font(.title2.weight(.semibold))
                    Text("Install this app on your device\nvia the Rork App to use the camera.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
            }
        }
        #endif
    }

    private var reviewView: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(spacing: 20) {
                    Group {
                        if let img = cameraService.capturedImage {
                            Color(.tertiarySystemGroupedBackground)
                                .frame(height: 300)
                                .overlay {
                                    Image(uiImage: img)
                                        .resizable()
                                        .aspectRatio(contentMode: .fill)
                                        .allowsHitTesting(false)
                                }
                                .clipShape(.rect(cornerRadius: 16))
                        } else {
                            RoundedRectangle(cornerRadius: 16)
                                .fill(Color(.tertiarySystemGroupedBackground))
                                .frame(height: 300)
                                .overlay {
                                    VStack(spacing: 12) {
                                        Image(systemName: "doc.text.fill")
                                            .font(.system(size: 44))
                                            .foregroundStyle(.orange.opacity(0.5))
                                        Text("Entry Captured")
                                            .font(.headline)
                                        Text("Your handwritten entry is ready")
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                }
                        }
                    }
                    .padding(.horizontal, 16)

                    HStack(spacing: 12) {
                        Image(systemName: "checkmark.shield.fill")
                            .font(.title3)
                            .foregroundStyle(.green)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Anti-Fraud Verification")
                                .font(.subheadline.weight(.semibold))
                            Text("Photo will be analyzed for genuine handwritten content")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                    }
                    .padding(14)
                    .background(Color(.secondarySystemGroupedBackground), in: .rect(cornerRadius: 12))
                    .padding(.horizontal, 16)

                    HStack(spacing: 12) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.title3)
                            .foregroundStyle(.orange)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("No Digital Text")
                                .font(.subheadline.weight(.semibold))
                            Text("Typed, printed, or AI-generated text will be rejected")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                    }
                    .padding(14)
                    .background(Color(.secondarySystemGroupedBackground), in: .rect(cornerRadius: 12))
                    .padding(.horizontal, 16)
                }
                .padding(.top, 16)
            }

            VStack(spacing: 12) {
                Button {
                    withAnimation(.snappy) { step = .capture }
                } label: {
                    Label("Retake Photo", systemImage: "arrow.counterclockwise")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)

                Button {
                    showSubmitConfirm = true
                } label: {
                    Label("Submit Entry", systemImage: "paperplane.fill")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(.orange)
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 16)
            .background(.bar)
        }
    }
}

struct GratitudeInstructionRow: View {
    let number: Int
    let icon: String
    let text: String

    var body: some View {
        HStack(spacing: 12) {
            Text("\(number)")
                .font(.caption.weight(.bold))
                .foregroundStyle(.white)
                .frame(width: 24, height: 24)
                .background(.orange, in: Circle())

            Image(systemName: icon)
                .font(.subheadline)
                .foregroundStyle(.orange)
                .frame(width: 24)

            Text(text)
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
    }
}

nonisolated enum GratitudeStep: Sendable {
    case write
    case capture
    case review
}
