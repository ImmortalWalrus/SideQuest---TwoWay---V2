import SwiftUI
import AVFoundation

struct AffirmationsLogView: View {
    let quest: Quest
    let instanceId: String
    let appState: AppState
    @Environment(\.dismiss) private var dismiss
    @State private var step: AffirmationStep = .write
    @State private var showSubmitConfirm: Bool = false
    @State private var cameraService = TimelapseCameraService()

    private var pathColor: Color {
        PathColorHelper.color(for: quest.path)
    }

    private var dailyPrompt: String {
        let prompts = [
            "I show up and put in the work, every single day.",
            "I handle what's in front of me and keep moving.",
            "I'm building something real, one day at a time.",
            "I don't need permission to go after what I want.",
            "I'm done waiting — I'm doing.",
            "I earned today. Tomorrow I'll earn it again.",
            "Every rep, every page, every step counts.",
            "I trust the work I'm putting in.",
            "I stay focused on what matters.",
            "Clear head, steady hands, no excuses.",
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
                Text("Your handwritten affirmations will be analyzed and sent for verification.")
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
                            .fill(.purple.opacity(0.12))
                            .frame(width: 80, height: 80)
                        Image(systemName: "sparkles")
                            .font(.system(size: 34))
                            .foregroundStyle(.purple)
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
                    Label("Today's Inspiration", systemImage: "sparkles")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.purple)

                    Text("\"\(dailyPrompt)\"")
                        .font(.title3.weight(.medium))
                        .italic()
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(16)
                .background(
                    RoundedRectangle(cornerRadius: 14)
                        .fill(.purple.opacity(0.06))
                        .overlay(
                            RoundedRectangle(cornerRadius: 14)
                                .strokeBorder(.purple.opacity(0.15), lineWidth: 1)
                        )
                )

                VStack(alignment: .leading, spacing: 16) {
                    Text("How It Works")
                        .font(.headline)

                    AffirmationInstructionRow(number: 1, icon: "pencil.line", text: "Write your affirmations by hand — at least 5 statements", color: .purple)
                    AffirmationInstructionRow(number: 2, icon: "heart.fill", text: "Write in present tense as if already true", color: .purple)
                    AffirmationInstructionRow(number: 3, icon: "camera.fill", text: "Take a clear photo of your handwritten entry", color: .purple)
                    AffirmationInstructionRow(number: 4, icon: "checkmark.seal.fill", text: "Submit for verification to earn rewards", color: .purple)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                VStack(alignment: .leading, spacing: 8) {
                    Label("Why Affirmations?", systemImage: "brain.head.profile.fill")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.secondary)

                    Text("Writing things down by hand helps them stick. Doing it daily keeps your priorities front and center instead of buried under distractions.")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(14)
                .background(Color(.secondarySystemGroupedBackground), in: .rect(cornerRadius: 12))

                Button {
                    withAnimation(.snappy) { step = .capture }
                } label: {
                    Label("I've Written My Affirmations", systemImage: "camera.fill")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(.purple)
                .padding(.top, 4)
            }
            .padding(16)
        }
    }

    private var captureView: some View {
        VStack(spacing: 0) {
            ZStack {
                affirmationCameraPreview

                RoundedRectangle(cornerRadius: 12)
                    .strokeBorder(style: StrokeStyle(lineWidth: 2, dash: [8, 6]))
                    .foregroundStyle(.purple.opacity(0.4))
                    .padding(24)
                    .allowsHitTesting(false)

                VStack {
                    Spacer()
                    Text("Position your handwritten affirmations in frame")
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
                            .fill(.purple)
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
    private var affirmationCameraPreview: some View {
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
                                        Image(systemName: "sparkles")
                                            .font(.system(size: 44))
                                            .foregroundStyle(.purple.opacity(0.5))
                                        Text("Affirmations Captured")
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
                            .foregroundStyle(.purple)
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
                    Label("Submit Affirmations", systemImage: "paperplane.fill")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(.purple)
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 16)
            .background(.bar)
        }
    }
}

private struct AffirmationInstructionRow: View {
    let number: Int
    let icon: String
    let text: String
    let color: Color

    var body: some View {
        HStack(spacing: 12) {
            Text("\(number)")
                .font(.caption.weight(.bold))
                .foregroundStyle(.white)
                .frame(width: 24, height: 24)
                .background(color, in: Circle())

            Image(systemName: icon)
                .font(.subheadline)
                .foregroundStyle(color)
                .frame(width: 24)

            Text(text)
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
    }
}

nonisolated enum AffirmationStep: Sendable {
    case write
    case capture
    case review
}
