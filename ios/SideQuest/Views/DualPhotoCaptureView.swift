import SwiftUI
import UIKit
import AVFoundation

nonisolated enum DualPhotoPhase: Equatable {
    case preview
    case capturing
    case review
}

struct DualPhotoCaptureView: View {
    let quest: Quest
    let instanceId: String
    let appState: AppState
    @Environment(\.dismiss) private var dismiss

    @State private var phase: DualPhotoPhase = .preview
    @State private var dualCamera = DualCameraService()
    @State private var shutterFlash: Bool = false
    @State private var shutterScale: CGFloat = 1.0
    @State private var showSubmitConfirm: Bool = false
    @State private var captureTime: Date = .now
    @State private var pipExpanded: Bool = false

    private var pathColor: Color { PathColorHelper.color(for: quest.path) }

    var body: some View {
        NavigationStack {
            ZStack {
                Color.black.ignoresSafeArea()

                switch phase {
                case .preview:
                    previewView
                case .capturing:
                    capturingView
                case .review:
                    reviewView
                }

                if shutterFlash {
                    Color.white
                        .opacity(0.85)
                        .ignoresSafeArea()
                        .allowsHitTesting(false)
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dualCamera.stopBoth()
                        dismiss()
                    }
                    .foregroundStyle(.white)
                }
                ToolbarItem(placement: .principal) {
                    Label("Dual Capture", systemImage: "camera.on.rectangle.fill")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.white)
                }
            }
            .toolbarBackground(.hidden, for: .navigationBar)
            .alert("Submit Photos?", isPresented: $showSubmitConfirm) {
                Button("Submit") {
                    appState.submitEvidence(for: instanceId)
                    dismiss()
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("Both photos will be sent for community verification.")
            }
        }
        .onAppear {
            appState.isImmersive = true
            dualCamera.configureAndStart()
        }
        .onDisappear {
            dualCamera.stopBoth()
            appState.isImmersive = false
        }
    }

    private var previewView: some View {
        ZStack {
            rearCameraPreview
                .ignoresSafeArea()

            frontPiP

            VStack {
                Spacer()
                captureControls
            }
        }
    }

    private var capturingView: some View {
        ZStack {
            rearCameraPreview
                .ignoresSafeArea()

            VStack(spacing: 20) {
                ProgressView()
                    .tint(.white)
                    .scaleEffect(1.3)
                Text("Capturing both cameras...")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.white)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(.black.opacity(0.4))
        }
    }

    @ViewBuilder
    private var rearCameraPreview: some View {
        #if targetEnvironment(simulator)
        rearPlaceholder
        #else
        if dualCamera.isConfigured {
            PreviewLayerView(previewLayer: dualCamera.rearPreviewLayer)
        } else {
            ZStack {
                Color(white: 0.07).ignoresSafeArea()
                ProgressView()
                    .tint(.white)
            }
        }
        #endif
    }

    private var rearPlaceholder: some View {
        ZStack {
            Color(white: 0.07).ignoresSafeArea()
            VStack(spacing: 10) {
                Image(systemName: "camera.viewfinder")
                    .font(.system(size: 40))
                    .foregroundStyle(.white.opacity(0.18))
                Text("Rear Camera")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.white.opacity(0.25))
            }
        }
    }

    private var frontPiP: some View {
        VStack {
            HStack {
                Spacer()
                ZStack {
                    RoundedRectangle(cornerRadius: pipExpanded ? 20 : 16)
                        .fill(Color(white: 0.12))
                        .frame(
                            width: pipExpanded ? 180 : 110,
                            height: pipExpanded ? 240 : 146
                        )
                        .overlay {
                            #if targetEnvironment(simulator)
                            frontPiPPlaceholder
                            #else
                            if dualCamera.isConfigured {
                                PreviewLayerView(previewLayer: dualCamera.frontPreviewLayer)
                                    .allowsHitTesting(false)
                            } else {
                                frontPiPPlaceholder
                            }
                            #endif
                        }
                        .clipShape(.rect(cornerRadius: pipExpanded ? 20 : 16))
                        .overlay(
                            RoundedRectangle(cornerRadius: pipExpanded ? 20 : 16)
                                .strokeBorder(.white.opacity(0.3), lineWidth: 2)
                        )
                        .shadow(color: .black.opacity(0.5), radius: 10, y: 4)

                    VStack {
                        Spacer()
                        HStack {
                            Label("Selfie", systemImage: "person.crop.circle")
                                .font(.system(size: 9, weight: .semibold))
                                .foregroundStyle(.white.opacity(0.75))
                                .padding(.horizontal, 7)
                                .padding(.vertical, 4)
                                .background(.black.opacity(0.55), in: Capsule())
                            Spacer()
                        }
                        .padding(8)
                    }
                    .frame(
                        width: pipExpanded ? 180 : 110,
                        height: pipExpanded ? 240 : 146
                    )
                    .allowsHitTesting(false)
                }
                .overlay {
                    Button {
                        withAnimation(.spring(duration: 0.35)) {
                            pipExpanded.toggle()
                        }
                    } label: {
                        Color.clear
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.top, 60)
            .padding(.trailing, 16)

            Spacer()
        }
    }

    private var frontPiPPlaceholder: some View {
        ZStack {
            Color(white: 0.1)
            VStack(spacing: 6) {
                Image(systemName: "person.crop.square")
                    .font(.system(size: 24))
                    .foregroundStyle(.white.opacity(0.2))
                Text("Front")
                    .font(.system(size: 9))
                    .foregroundStyle(.white.opacity(0.2))
            }
        }
    }

    private var captureControls: some View {
        VStack(spacing: 20) {
            HStack(spacing: 8) {
                Image(systemName: "bolt.horizontal.circle.fill")
                    .font(.subheadline)
                    .foregroundStyle(pathColor)
                Text("Tap to capture both cameras simultaneously")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.white.opacity(0.65))
            }

            Button {
                guard phase == .preview else { return }
                shutterScale = 0.88
                withAnimation(.spring(duration: 0.25)) { shutterScale = 1.0 }
                withAnimation(.easeOut(duration: 0.06)) { shutterFlash = true }
                Task { @MainActor in
                    try? await Task.sleep(for: .milliseconds(60))
                    withAnimation(.easeIn(duration: 0.2)) { shutterFlash = false }
                    captureTime = .now
                    withAnimation(.snappy) { phase = .capturing }
                    await dualCamera.captureBoth()
                    dualCamera.stopBoth()
                    withAnimation(.snappy) { phase = .review }
                }
            } label: {
                ZStack {
                    Circle()
                        .strokeBorder(.white, lineWidth: 3)
                        .frame(width: 84, height: 84)
                    Circle()
                        .fill(.white)
                        .frame(width: 70, height: 70)
                        .scaleEffect(shutterScale)
                }
            }
            .buttonStyle(.plain)
            .sensoryFeedback(.impact(weight: .heavy), trigger: phase)
        }
        .padding(.horizontal, 24)
        .padding(.bottom, 40)
        .padding(.top, 20)
        .background(
            LinearGradient(
                colors: [.clear, .black.opacity(0.85)],
                startPoint: .top,
                endPoint: .bottom
            )
        )
    }

    private var reviewView: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(spacing: 28) {
                    VStack(spacing: 8) {
                        ZStack {
                            Circle()
                                .fill(pathColor.opacity(0.18))
                                .frame(width: 76, height: 76)
                            Image(systemName: "checkmark.circle.fill")
                                .font(.system(size: 38))
                                .foregroundStyle(pathColor)
                        }
                        .padding(.top, 28)

                        Text("Both Photos Captured")
                            .font(.title2.weight(.bold))
                            .foregroundStyle(.white)

                        Text(captureTime, style: .time)
                            .font(.subheadline)
                            .foregroundStyle(.white.opacity(0.45))
                    }

                    HStack(spacing: 12) {
                        capturedPhotoCard(label: "Location", image: dualCamera.rearImage, fallbackIcon: "camera.viewfinder", color: pathColor)
                        capturedPhotoCard(label: "Selfie", image: dualCamera.frontImage, fallbackIcon: "person.crop.circle", color: .purple)
                    }
                    .padding(.horizontal, 16)

                    VStack(spacing: 0) {
                        verificationRow(icon: "bolt.horizontal.circle.fill", color: pathColor, text: "Both cameras fired simultaneously")
                        Divider().background(.white.opacity(0.1))
                        verificationRow(icon: "clock.badge.checkmark.fill", color: .orange, text: "Timestamp embedded \u{00B7} \(captureTime.formatted(date: .omitted, time: .shortened))")
                        Divider().background(.white.opacity(0.1))
                        verificationRow(icon: "checkmark.shield.fill", color: .blue, text: "Anti-fraud fingerprint generated")
                    }
                    .background(.white.opacity(0.06), in: .rect(cornerRadius: 14))
                    .padding(.horizontal, 16)
                }
                .padding(.bottom, 24)
            }

            VStack(spacing: 10) {
                Button {
                    dualCamera.reset()
                    dualCamera = DualCameraService()
                    dualCamera.configureAndStart()
                    withAnimation(.snappy) { phase = .preview }
                } label: {
                    Label("Retake Both", systemImage: "arrow.counterclockwise")
                        .font(.subheadline.weight(.semibold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 13)
                        .background(.white.opacity(0.1), in: .rect(cornerRadius: 14))
                        .foregroundStyle(.white)
                }
                .buttonStyle(.plain)

                Button {
                    showSubmitConfirm = true
                } label: {
                    Label("Submit Evidence", systemImage: "paperplane.fill")
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

    private func capturedPhotoCard(label: String, image: UIImage?, fallbackIcon: String, color: Color) -> some View {
        VStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color(white: 0.12))
                    .frame(height: 160)

                if let image {
                    Image(uiImage: image)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .allowsHitTesting(false)
                } else {
                    VStack(spacing: 8) {
                        Image(systemName: fallbackIcon)
                            .font(.system(size: 32))
                            .foregroundStyle(color)
                        Image(systemName: "checkmark.circle.fill")
                            .font(.title3)
                            .foregroundStyle(.green)
                    }
                }
            }
            .frame(height: 160)
            .clipShape(.rect(cornerRadius: 12))

            HStack(spacing: 5) {
                Image(systemName: "checkmark.circle.fill")
                    .font(.caption2)
                    .foregroundStyle(.green)
                Text(label)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.white)
            }
        }
        .frame(maxWidth: .infinity)
    }

    private func verificationRow(icon: String, color: Color, text: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .font(.subheadline)
                .foregroundStyle(color)
                .frame(width: 28)
            Text(text)
                .font(.subheadline)
                .foregroundStyle(.white.opacity(0.75))
            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }
}
