import SwiftUI

struct PrivacyPolicyView: View {
    private let lastUpdated = "January 15, 2025"

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Privacy Policy")
                        .font(.title2.weight(.bold))
                    Text("Last updated \(lastUpdated)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                policySection(
                    icon: "location.fill",
                    title: "Location Data",
                    body: "GPS data is collected only during active tracking quests and is used solely to verify quest completion. Location data is processed on-device and route paths are not shared with other users. You can revoke location access at any time in Settings."
                )

                policySection(
                    icon: "camera.fill",
                    title: "Camera & Photos",
                    body: "Camera access is used for quest evidence capture (dual photos, videos, push-up tracking). Photos and videos are stored locally and uploaded only when you submit quest evidence. Moderation reviewers see evidence temporarily and cannot download it."
                )

                policySection(
                    icon: "figure.walk",
                    title: "Motion & Fitness Data",
                    body: "Step count data is accessed through Motion & Fitness only when you enable Step Tracking. This data stays on your device and is never sent to our servers. It is used to display your daily and weekly step counts within the app."
                )

                policySection(
                    icon: "person.2.fill",
                    title: "Social Features",
                    body: "Your username, avatar, level, and quest stats are visible to friends and on leaderboards. You control friend requests and can block users at any time. NFC handshake data is processed locally and only confirms proximity — no personal data is exchanged."
                )

                policySection(
                    icon: "lock.shield.fill",
                    title: "Data Security",
                    body: "All data is encrypted in transit and at rest. We use industry-standard security practices to protect your information. Your progress, scores, and achievements are stored locally with cloud backup available."
                )

                policySection(
                    icon: "trash.fill",
                    title: "Data Deletion",
                    body: "You can reset all progress from Settings at any time. To request complete account deletion, contact support@sidequestapp.com. We will delete all associated data within 30 days."
                )
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 16)
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle("Privacy")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func policySection(icon: String, title: String, body: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: icon)
                    .foregroundStyle(.blue)
                    .frame(width: 22)
                Text(title)
                    .font(.headline)
            }
            Text(body)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .lineSpacing(3)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.secondarySystemGroupedBackground), in: .rect(cornerRadius: 14))
    }
}
