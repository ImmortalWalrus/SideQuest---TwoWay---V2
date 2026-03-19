import SwiftUI
import AVFoundation
import CoreLocation

struct PermissionsView: View {
    let appState: AppState
    let onComplete: () -> Void
    @State private var notificationsGranted: Bool = false
    @State private var cameraGranted: Bool = false
    @State private var micGranted: Bool = false
    @State private var locationGranted: Bool = false
    @State private var healthGranted: Bool = false
    @State private var currentStep: Int = 0
    @State private var animateIn: Bool = false

    private let permissions: [(icon: String, title: String, description: String, color: Color)] = [
        ("bell.badge.fill", "Notifications", "Stay on track with quest reminders, streak alerts, and focus block warnings.", .blue),
        ("camera.fill", "Camera", "Verify push-ups and planks with real-time pose tracking.", .red),
        ("mic.fill", "Microphone", "Record audio for video evidence capture and meditation sessions.", .purple),
        ("location.fill", "Location", "Track walking & running quests and unlock time-of-day challenges.", .green),
        ("figure.walk", "Motion & Fitness", "Read live step counts for activity quests and step-based challenges.", .pink),
    ]

    var body: some View {
        VStack(spacing: 0) {
            Spacer()

            VStack(spacing: 24) {
                Image(systemName: "shield.checkered")
                    .font(.system(size: 52))
                    .foregroundStyle(.linearGradient(colors: [.red, .blue], startPoint: .topLeading, endPoint: .bottomTrailing))
                    .scaleEffect(animateIn ? 1 : 0.5)
                    .opacity(animateIn ? 1 : 0)

                VStack(spacing: 8) {
                    Text("Power Up Your Quests")
                        .font(.title.weight(.bold))
                        .foregroundStyle(.white)
                    Text("SideQuest works best with these permissions.")
                        .font(.subheadline)
                        .foregroundStyle(.white.opacity(0.6))
                        .multilineTextAlignment(.center)
                }
            }
            .padding(.bottom, 40)

            VStack(spacing: 16) {
                ForEach(Array(permissions.enumerated()), id: \.offset) { index, perm in
                    permissionRow(
                        icon: perm.icon,
                        title: perm.title,
                        description: perm.description,
                        color: perm.color,
                        granted: isGranted(index),
                        index: index
                    )
                    .opacity(animateIn ? 1 : 0)
                    .offset(y: animateIn ? 0 : 20)
                    .animation(.spring(response: 0.5).delay(Double(index) * 0.1), value: animateIn)
                }
            }
            .padding(.horizontal, 24)

            Spacer()

            VStack(spacing: 12) {
                Button {
                    Task { await requestAllPermissions() }
                } label: {
                    Text("Allow All")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)

                Button {
                    appState.finalizeOnboarding()
                    onComplete()
                } label: {
                    Text("Skip for Now")
                        .font(.subheadline)
                        .foregroundStyle(.white.opacity(0.5))
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 20)
        }
        .background {
            MeshGradient(
                width: 3, height: 3,
                points: [
                    [0.0, 0.0], [0.5, 0.0], [1.0, 0.0],
                    [0.0, 0.5], [0.5, 0.5], [1.0, 0.5],
                    [0.0, 1.0], [0.5, 1.0], [1.0, 1.0]
                ],
                colors: [
                    .black, .indigo.opacity(0.3), .black,
                    .red.opacity(0.2), .black, .green.opacity(0.2),
                    .black, .blue.opacity(0.2), .black
                ]
            )
            .ignoresSafeArea()
        }
        .onAppear {
            withAnimation(.spring(response: 0.6)) {
                animateIn = true
            }
        }
    }

    private func permissionRow(icon: String, title: String, description: String, color: Color, granted: Bool, index: Int) -> some View {
        HStack(spacing: 14) {
            ZStack {
                RoundedRectangle(cornerRadius: 10)
                    .fill(color.opacity(0.2))
                    .frame(width: 44, height: 44)
                Image(systemName: icon)
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(color)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.white)
                Text(description)
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.5))
                    .lineLimit(2)
            }

            Spacer()

            if granted {
                Image(systemName: "checkmark.circle.fill")
                    .font(.title3)
                    .foregroundStyle(.green)
                    .transition(.scale.combined(with: .opacity))
            }
        }
        .padding(12)
        .background(.white.opacity(0.06), in: .rect(cornerRadius: 14))
    }

    private func isGranted(_ index: Int) -> Bool {
        switch index {
        case 0: return notificationsGranted
        case 1: return cameraGranted
        case 2: return micGranted
        case 3: return locationGranted
        case 4: return healthGranted
        default: return false
        }
    }

    private func requestAllPermissions() async {
        let notifResult = await NotificationService.shared.requestAuthorization()
        withAnimation(.spring(response: 0.3)) {
            notificationsGranted = notifResult
        }
        if notifResult {
            NotificationService.shared.scheduleRecurring()
            appState.notificationsEnabled = true
            UserDefaults.standard.set(true, forKey: "notificationsEnabled")
        }

        let camStatus = AVCaptureDevice.authorizationStatus(for: .video)
        if camStatus == .notDetermined {
            let granted = await AVCaptureDevice.requestAccess(for: .video)
            withAnimation(.spring(response: 0.3)) {
                cameraGranted = granted
            }
        } else {
            withAnimation(.spring(response: 0.3)) {
                cameraGranted = camStatus == .authorized
            }
        }

        let micStatus = AVCaptureDevice.authorizationStatus(for: .audio)
        if micStatus == .notDetermined {
            let granted = await AVCaptureDevice.requestAccess(for: .audio)
            withAnimation(.spring(response: 0.3)) {
                micGranted = granted
            }
        } else {
            withAnimation(.spring(response: 0.3)) {
                micGranted = micStatus == .authorized
            }
        }

        appState.solarService.requestLocationOnce()
        try? await Task.sleep(for: .milliseconds(500))
        let locStatus = CLLocationManager().authorizationStatus
        withAnimation(.spring(response: 0.3)) {
            locationGranted = locStatus == .authorizedWhenInUse || locStatus == .authorizedAlways
        }

        if appState.stepCountService.isAvailable {
            let healthResult = await appState.stepCountService.requestAuthorization()
            withAnimation(.spring(response: 0.3)) {
                healthGranted = healthResult
            }
            if healthResult {
                appState.stepsEnabled = true
                UserDefaults.standard.set(true, forKey: "stepsEnabled")
            }
        }

        try? await Task.sleep(for: .seconds(1))
        appState.finalizeOnboarding()
        onComplete()
    }
}
