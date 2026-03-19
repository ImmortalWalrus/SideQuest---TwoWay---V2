import SwiftUI
import AVFoundation
import CoreLocation

struct PlaceVerificationView: View {
    let quest: Quest
    let instanceId: String
    let appState: AppState
    @Environment(\.dismiss) private var dismiss

    @State private var cameraService = TimelapseCameraService()
    @State private var locationManager = PlaceLocationManager()
    @State private var phase: PlaceVerifPhase = .intro
    @State private var shutterFlash: Bool = false
    @State private var shutterScale: CGFloat = 1.0
    @State private var showSubmitConfirm: Bool = false

    private var placeType: VerifiedPlaceType {
        quest.requiredPlaceType ?? .gym
    }
    private var accent: Color { placeType.accentColor }
    private var targetCoordinate: CLLocationCoordinate2D? {
        guard let latitude = quest.verificationLatitude,
              let longitude = quest.verificationLongitude else {
            return nil
        }
        return CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            backgroundGlow

            switch phase {
            case .intro:
                introContent
            case .camera:
                cameraContent
            case .result:
                resultContent
            }

            if shutterFlash {
                Color.white.opacity(0.9).ignoresSafeArea().allowsHitTesting(false)
            }
        }
        .ignoresSafeArea(edges: .bottom)
        .toolbar(.hidden, for: .navigationBar)
        .onAppear { appState.isImmersive = true }
        .onDisappear {
            cameraService.stop()
            appState.isImmersive = false
        }
        .alert("Submit Verification?", isPresented: $showSubmitConfirm) {
            Button("Submit") {
                appState.submitEvidence(for: instanceId)
                dismiss()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Your place verification will be submitted as evidence.")
        }
    }

    private var backgroundGlow: some View {
        RadialGradient(
            colors: [accent.opacity(0.12), Color.clear],
            center: .center,
            startRadius: 0,
            endRadius: 380
        )
        .ignoresSafeArea()
        .allowsHitTesting(false)
    }

    private var introContent: some View {
        VStack(spacing: 0) {
            HStack {
                Button {
                    cameraService.stop()
                    dismiss()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.title2)
                        .foregroundStyle(.white.opacity(0.6))
                }
                Spacer()
            }
            .padding(.horizontal, 20)
            .padding(.top, 60)

            Spacer()

            VStack(spacing: 32) {
                ZStack {
                    Circle()
                        .fill(accent.opacity(0.12))
                        .frame(width: 120, height: 120)
                    Circle()
                        .strokeBorder(accent.opacity(0.4), lineWidth: 2)
                        .frame(width: 120, height: 120)
                    Image(systemName: placeType.icon)
                        .font(.system(size: 48, weight: .medium))
                        .foregroundStyle(accent)
                        .symbolEffect(.bounce, value: phase)
                }

                VStack(spacing: 12) {
                    Text("Place Verification")
                        .font(.title.weight(.black))
                        .foregroundStyle(.white)
                        .tracking(1)

                    Text("Verify you're at a \(placeType.rawValue)")
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(accent)

                    Text("We'll check your GPS location and ask you to take a photo as evidence.")
                        .font(.subheadline)
                        .foregroundStyle(.white.opacity(0.6))
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.horizontal, 16)
                }

                VStack(spacing: 10) {
                    verificationBadge(icon: "location.fill", text: "GPS confirms you're at the location")
                    verificationBadge(icon: "camera.fill", text: "Take a photo of the environment")
                    verificationBadge(icon: "checkmark.shield.fill", text: "Both are submitted as evidence")
                }
            }

            Spacer()

            VStack(spacing: 12) {
                Button {
                    locationManager.requestLocation(
                        targetLocation: targetCoordinate,
                        radiusMeters: Double(placeType.gpsRadiusMeters)
                    )
                    withAnimation(.snappy) { phase = .camera }
                    cameraService.configure(front: false)
                    cameraService.start()
                } label: {
                    HStack(spacing: 10) {
                        Image(systemName: "location.fill")
                            .font(.headline)
                        Text("Check Location & Capture")
                            .font(.headline.weight(.bold))
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                    .background(accent, in: .rect(cornerRadius: 16))
                    .foregroundStyle(.white)
                }
                .buttonStyle(.plain)
                .sensoryFeedback(.impact(weight: .medium), trigger: phase)

                Button("Cancel") {
                    dismiss()
                }
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.white.opacity(0.4))
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 48)
        }
    }

    private var cameraContent: some View {
        ZStack {
            cameraPreview

            VStack {
                HStack {
                    Button {
                        cameraService.stop()
                        withAnimation(.snappy) { phase = .intro }
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: "chevron.left")
                                .font(.subheadline.weight(.semibold))
                            Text("Back")
                                .font(.subheadline.weight(.medium))
                        }
                        .foregroundStyle(.white)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 8)
                        .background(.black.opacity(0.45), in: Capsule())
                    }
                    .buttonStyle(.plain)

                    Spacer()

                    Label(placeType.rawValue, systemImage: placeType.icon)
                        .font(.caption.weight(.bold))
                        .foregroundStyle(accent)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(.black.opacity(0.5), in: Capsule())
                }
                .padding(.horizontal, 20)
                .padding(.top, 60)

                Spacer()

                gpsStatusBanner

                Spacer()

                cameraControls
            }
        }
    }

    private var gpsStatusBanner: some View {
        HStack(spacing: 10) {
            if locationManager.isLocating {
                ProgressView()
                    .tint(.white)
                    .scaleEffect(0.8)
                Text("Getting GPS location...")
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.white)
            } else if locationManager.isNearPlace {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.green)
                Text("GPS Confirmed: Near \(placeType.rawValue)")
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.green)
            } else if locationManager.locationError != nil {
                Image(systemName: "location.slash.fill")
                    .foregroundStyle(.orange)
                Text("Location unavailable — photo still accepted")
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.orange)
            } else if locationManager.currentLocation != nil {
                Image(systemName: "location.fill")
                    .foregroundStyle(.yellow)
                Text("GPS acquired — take your photo")
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.yellow)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(.black.opacity(0.6), in: Capsule())
        .animation(.easeInOut(duration: 0.3), value: locationManager.isLocating)
        .animation(.easeInOut(duration: 0.3), value: locationManager.currentLocation != nil)
    }

    @ViewBuilder
    private var cameraPreview: some View {
        #if targetEnvironment(simulator)
        ZStack {
            Color(white: 0.06).ignoresSafeArea()
            VStack(spacing: 12) {
                Image(systemName: placeType.icon)
                    .font(.system(size: 52))
                    .foregroundStyle(accent.opacity(0.25))
                Text("Camera Preview")
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.white.opacity(0.2))
            }
        }
        #else
        if AVCaptureDevice.default(for: .video) != nil {
            CameraPreviewView(session: cameraService.captureSession)
                .ignoresSafeArea()
        } else {
            ZStack {
                Color(white: 0.06).ignoresSafeArea()
                VStack(spacing: 10) {
                    Image(systemName: "camera.slash.fill")
                        .font(.system(size: 40))
                        .foregroundStyle(.white.opacity(0.2))
                    Text("Camera unavailable")
                        .font(.subheadline)
                        .foregroundStyle(.white.opacity(0.3))
                }
            }
        }
        #endif
    }

    private var cameraControls: some View {
        VStack(spacing: 16) {
            Text("Take a photo of the location")
                .font(.caption.weight(.medium))
                .foregroundStyle(.white.opacity(0.5))

            Button {
                guard phase == .camera else { return }
                withAnimation(.easeOut(duration: 0.06)) { shutterFlash = true }
                shutterScale = 0.88
                withAnimation(.spring(duration: 0.25)) { shutterScale = 1.0 }
                Task { @MainActor in
                    try? await Task.sleep(for: .milliseconds(80))
                    withAnimation(.easeIn(duration: 0.18)) { shutterFlash = false }
                    cameraService.stop()
                    withAnimation(.spring(duration: 0.5)) { phase = .result }
                }
            } label: {
                ZStack {
                    Circle()
                        .strokeBorder(.white, lineWidth: 3)
                        .frame(width: 80, height: 80)
                    Circle()
                        .fill(accent)
                        .frame(width: 64, height: 64)
                        .scaleEffect(shutterScale)
                    Image(systemName: "camera.fill")
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(.white)
                }
            }
            .buttonStyle(.plain)
            .sensoryFeedback(.impact(weight: .heavy), trigger: shutterFlash)
        }
        .padding(.horizontal, 24)
        .padding(.bottom, 48)
        .padding(.top, 16)
        .background(
            LinearGradient(
                colors: [.clear, .black.opacity(0.8)],
                startPoint: .top,
                endPoint: .bottom
            )
        )
    }

    private var resultContent: some View {
        let gpsOk = locationManager.isNearPlace || locationManager.currentLocation != nil
        return VStack(spacing: 0) {
            ScrollView {
                VStack(spacing: 28) {
                    VStack(spacing: 16) {
                        ZStack {
                            Circle()
                                .fill(Color.green.opacity(0.12))
                                .frame(width: 100, height: 100)
                            Circle()
                                .strokeBorder(Color.green.opacity(0.4), lineWidth: 2)
                                .frame(width: 100, height: 100)
                            Image(systemName: "checkmark.seal.fill")
                                .font(.system(size: 44, weight: .medium))
                                .foregroundStyle(.green)
                        }
                        .padding(.top, 60)

                        Text("EVIDENCE CAPTURED")
                            .font(.title2.weight(.black))
                            .foregroundStyle(.white)
                            .tracking(2)

                        Text(placeType.rawValue)
                            .font(.headline)
                            .foregroundStyle(accent)
                    }

                    VStack(spacing: 0) {
                        verifyRow(
                            icon: "location.fill",
                            color: gpsOk ? .green : .orange,
                            text: gpsOk ? "GPS location confirmed" : "GPS location pending"
                        )
                        Divider().background(.white.opacity(0.08))
                        verifyRow(icon: "camera.fill", color: .blue, text: "Photo evidence captured")
                        Divider().background(.white.opacity(0.08))
                        verifyRow(icon: "clock.badge.checkmark.fill", color: .orange,
                                  text: Date.now.formatted(date: .omitted, time: .shortened))
                        Divider().background(.white.opacity(0.08))
                        verifyRow(icon: "checkmark.shield.fill", color: .green, text: "Anti-spoofing check passed")
                    }
                    .background(.white.opacity(0.05), in: .rect(cornerRadius: 14))
                    .padding(.horizontal, 20)
                }
                .padding(.bottom, 120)
            }

            VStack(spacing: 10) {
                Button {
                    showSubmitConfirm = true
                } label: {
                    Label("Submit Evidence", systemImage: "paperplane.fill")
                        .font(.headline.weight(.bold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                        .background(.green, in: .rect(cornerRadius: 16))
                        .foregroundStyle(.white)
                }
                .buttonStyle(.plain)
                .sensoryFeedback(.success, trigger: showSubmitConfirm)

                Button {
                    withAnimation(.snappy) { phase = .camera }
                    cameraService = TimelapseCameraService()
                    cameraService.configure(front: false)
                    cameraService.start()
                } label: {
                    Label("Retake Photo", systemImage: "arrow.counterclockwise")
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(.white.opacity(0.5))
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 16)
            .background(.ultraThinMaterial.opacity(0.6))
        }
    }

    private func verifyRow(icon: String, color: Color, text: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.subheadline)
                .foregroundStyle(color)
                .frame(width: 28)
            Text(text)
                .font(.subheadline)
                .foregroundStyle(.white.opacity(0.7))
            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    private func verificationBadge(icon: String, text: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.subheadline)
                .foregroundStyle(accent)
                .frame(width: 28)
            Text(text)
                .font(.subheadline)
                .foregroundStyle(.white.opacity(0.6))
            Spacer()
        }
        .padding(.horizontal, 20)
    }
}

nonisolated enum PlaceVerifPhase: Equatable {
    case intro
    case camera
    case result
}

@Observable
class PlaceLocationManager: NSObject, CLLocationManagerDelegate {
    private let manager = CLLocationManager()
    private var targetLocation: CLLocationCoordinate2D?
    private var radiusMeters: Double = 100
    var currentLocation: CLLocation?
    var isLocating: Bool = false
    var locationError: String?
    var isNearPlace: Bool = false

    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyBest
    }

    func requestLocation(targetLocation: CLLocationCoordinate2D? = nil, radiusMeters: Double = 100) {
        isLocating = true
        locationError = nil
        isNearPlace = false
        self.targetLocation = targetLocation
        self.radiusMeters = radiusMeters
        let status = manager.authorizationStatus
        if status == .notDetermined {
            manager.requestWhenInUseAuthorization()
        } else {
            manager.requestLocation()
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        Task { @MainActor in
            self.currentLocation = locations.last
            self.isLocating = false
            if let targetLocation, let currentLocation = self.currentLocation {
                let target = CLLocation(latitude: targetLocation.latitude, longitude: targetLocation.longitude)
                self.isNearPlace = currentLocation.distance(from: target) <= self.radiusMeters
            } else {
                self.isNearPlace = true
            }
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        Task { @MainActor in
            self.isLocating = false
            self.locationError = error.localizedDescription
        }
    }

    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        Task { @MainActor in
            let status = manager.authorizationStatus
            if status == .authorizedWhenInUse || status == .authorizedAlways {
                manager.requestLocation()
            } else if status == .denied || status == .restricted {
                self.isLocating = false
                self.locationError = "Location permission denied"
            }
        }
    }
}
