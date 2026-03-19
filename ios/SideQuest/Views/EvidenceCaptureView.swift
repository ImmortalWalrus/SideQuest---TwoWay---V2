import SwiftUI
import UIKit
import AVFoundation
import AVKit

struct EvidenceCaptureView: View {
    let instanceId: String
    let appState: AppState
    @Environment(\.dismiss) private var dismiss
    @State private var captureStep: CaptureStep = .ready
    @State private var showSubmitConfirm: Bool = false
    @State private var cameraService = TimelapseCameraService()
    @State private var isRecording: Bool = false
    @State private var recordingElapsed: TimeInterval = 0
    @State private var recordingTimer: Timer?
    @State private var recPulse: Bool = false
    @State private var videoThumbnail: UIImage?

    var body: some View {
        NavigationStack {
            VStack {
                switch captureStep {
                case .ready:
                    readyView
                case .capturing:
                    capturingView
                case .review:
                    reviewView
                }
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("Submit Evidence")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        cameraService.stop()
                        dismiss()
                    }
                }
            }
            .alert("Submit Evidence?", isPresented: $showSubmitConfirm) {
                Button("Submit") {
                    appState.submitEvidence(for: instanceId)
                    dismiss()
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("Your submission will be sent for community verification.")
            }
        }
        .onAppear {
            appState.isImmersive = true
            cameraService.configure(front: false, includeAudio: true)
            cameraService.start()
        }
        .onDisappear {
            recordingTimer?.invalidate()
            cameraService.stop()
            appState.isImmersive = false
        }
    }

    private var readyView: some View {
        ZStack {
            evidenceCameraPreview

            VStack {
                Spacer()

                VStack(spacing: 16) {
                    Button {
                        startRecording()
                    } label: {
                        ZStack {
                            Circle()
                                .strokeBorder(.white, lineWidth: 4)
                                .frame(width: 80, height: 80)
                            Circle()
                                .fill(.red)
                                .frame(width: 64, height: 64)
                        }
                    }
                    .buttonStyle(.plain)

                    Text("Tap to start recording")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.white.opacity(0.6))
                }
                .padding(.bottom, 40)
                .padding(.top, 16)
                .frame(maxWidth: .infinity)
                .background(
                    LinearGradient(colors: [.clear, .black.opacity(0.7)], startPoint: .top, endPoint: .bottom)
                )
            }
        }
    }

    private func startRecording() {
        recordingElapsed = 0
        recPulse = true
        withAnimation(.snappy) { captureStep = .capturing }

        Task { @MainActor in
            await cameraService.startVideoRecording()
            isRecording = true
            recordingTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { _ in
                Task { @MainActor in
                    recordingElapsed += 1
                }
            }
        }
    }

    private var capturingView: some View {
        ZStack {
            evidenceCameraPreview

            VStack {
                HStack {
                    HStack(spacing: 6) {
                        Circle()
                            .fill(.red)
                            .frame(width: 10, height: 10)
                            .opacity(recPulse ? 0.3 : 1.0)
                            .animation(.easeInOut(duration: 0.7).repeatForever(autoreverses: true), value: recPulse)
                        Text("REC")
                            .font(.system(size: 12, weight: .bold, design: .monospaced))
                            .foregroundStyle(.white)
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(.black.opacity(0.55), in: Capsule())

                    Spacer()

                    Text(formatElapsed(recordingElapsed))
                        .font(.system(size: 14, weight: .semibold, design: .monospaced))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(.black.opacity(0.55), in: Capsule())
                }
                .padding(.horizontal, 20)
                .padding(.top, 12)

                Spacer()

                VStack(spacing: 16) {
                    Button {
                        recordingTimer?.invalidate()
                        recordingTimer = nil
                        isRecording = false
                        Task {
                            let url = await cameraService.stopVideoRecording()
                            if let url {
                                videoThumbnail = generateThumbnail(for: url)
                            }
                            withAnimation(.snappy) { captureStep = .review }
                        }
                    } label: {
                        ZStack {
                            Circle()
                                .fill(.white)
                                .frame(width: 76, height: 76)
                            RoundedRectangle(cornerRadius: 6)
                                .fill(.red)
                                .frame(width: 28, height: 28)
                        }
                    }
                    .buttonStyle(.plain)
                    .sensoryFeedback(.impact(weight: .medium), trigger: isRecording)

                    Text("Tap to stop recording")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.white.opacity(0.6))
                }
                .padding(.bottom, 40)
                .padding(.top, 16)
                .frame(maxWidth: .infinity)
                .background(
                    LinearGradient(colors: [.clear, .black.opacity(0.7)], startPoint: .top, endPoint: .bottom)
                )
            }
        }
    }

    private var reviewView: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(spacing: 20) {
                    if let thumb = videoThumbnail {
                        Color(.tertiarySystemGroupedBackground)
                            .frame(height: 240)
                            .overlay {
                                Image(uiImage: thumb)
                                    .resizable()
                                    .aspectRatio(contentMode: .fill)
                                    .allowsHitTesting(false)
                            }
                            .clipShape(.rect(cornerRadius: 16))
                            .overlay {
                                ZStack {
                                    Circle()
                                        .fill(.black.opacity(0.5))
                                        .frame(width: 56, height: 56)
                                    Image(systemName: "play.fill")
                                        .font(.title3)
                                        .foregroundStyle(.white)
                                }
                            }
                            .padding(.horizontal, 16)
                            .padding(.top, 16)
                    }

                    VStack(spacing: 10) {
                        ZStack {
                            Circle()
                                .fill(Color.green.opacity(0.15))
                                .frame(width: 76, height: 76)
                            Image(systemName: "checkmark.circle.fill")
                                .font(.system(size: 38))
                                .foregroundStyle(.green)
                        }

                        Text("Video Captured")
                            .font(.title2.weight(.bold))

                        Text(formatElapsed(recordingElapsed) + " recorded")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }

                    VStack(spacing: 0) {
                        HStack(spacing: 10) {
                            Image(systemName: "video.fill")
                                .font(.subheadline)
                                .foregroundStyle(.blue)
                                .frame(width: 28)
                            Text("Video evidence recorded in-app")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                            Spacer()
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 12)

                        Divider()

                        HStack(spacing: 10) {
                            Image(systemName: "checkmark.shield.fill")
                                .font(.subheadline)
                                .foregroundStyle(.green)
                                .frame(width: 28)
                            Text("Anti-fraud fingerprint generated")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                            Spacer()
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 12)
                    }
                    .background(Color(.secondarySystemGroupedBackground), in: .rect(cornerRadius: 14))
                    .padding(.horizontal, 16)
                }
                .padding(.bottom, 20)
            }

            VStack(spacing: 12) {
                Button {
                    captureStep = .ready
                    recordingElapsed = 0
                    videoThumbnail = nil
                    cameraService.recordedVideoURL = nil
                    if !cameraService.isRunning {
                        cameraService.start()
                    }
                } label: {
                    Label("Retake", systemImage: "arrow.counterclockwise")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)

                Button {
                    showSubmitConfirm = true
                } label: {
                    Label("Submit", systemImage: "paperplane.fill")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 16)
            .background(.bar)
        }
    }

    @ViewBuilder
    private var evidenceCameraPreview: some View {
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

    private func formatElapsed(_ t: TimeInterval) -> String {
        let m = Int(t) / 60
        let s = Int(t) % 60
        return String(format: "%02d:%02d", m, s)
    }

    private func generateThumbnail(for url: URL) -> UIImage? {
        let asset = AVAsset(url: url)
        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        generator.maximumSize = CGSize(width: 600, height: 600)
        if let cgImage = try? generator.copyCGImage(at: .zero, actualTime: nil) {
            return UIImage(cgImage: cgImage)
        }
        return nil
    }
}

nonisolated enum CaptureStep {
    case ready
    case capturing
    case review
}
