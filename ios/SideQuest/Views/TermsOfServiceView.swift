import SwiftUI

struct TermsOfServiceView: View {
    private let lastUpdated = "January 15, 2025"

    private let sections: [(icon: String, title: String, content: String)] = [
        ("checkmark.shield.fill", "Fair Play", "All quest evidence must be genuine and completed by you. Faking evidence, using bots, or manipulating GPS/clock data will result in quest rejection and potential account suspension."),
        ("person.fill.checkmark", "Community Standards", "Treat fellow players with respect during moderation and social interactions. Harassment, hate speech, or targeted abuse will result in permanent bans."),
        ("eye.fill", "Moderation Rules", "When moderating, review evidence honestly and thoroughly. Do not screenshot or record other players' evidence. Repeated false reports or malicious moderation will lead to Karma penalties and mod suspensions."),
        ("cart.fill", "Purchases & Currency", "Gold and Diamonds are in-app currencies with no real-world value. Cosmetic purchases are non-refundable. We reserve the right to modify pricing and item availability."),
        ("arrow.clockwise", "Account & Progress", "You are responsible for your account. Progress is stored locally with optional cloud sync. We are not responsible for data loss due to device changes without backup. Resetting progress is irreversible."),
        ("bell.fill", "Notifications", "We may send push notifications for quest reminders, verification results, and social updates. You can disable these at any time in Settings."),
        ("doc.text.fill", "Changes to Terms", "We may update these terms periodically. Continued use of the app after changes constitutes acceptance. Material changes will be communicated via in-app notification."),
    ]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Terms of Service")
                        .font(.title2.weight(.bold))
                    Text("Last updated \(lastUpdated)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding(.horizontal, 20)
                .padding(.top, 16)

                VStack(spacing: 12) {
                    ForEach(Array(sections.enumerated()), id: \.offset) { index, section in
                        HStack(alignment: .top, spacing: 14) {
                            ZStack {
                                Circle()
                                    .fill(.blue.opacity(0.12))
                                    .frame(width: 36, height: 36)
                                Image(systemName: section.icon)
                                    .font(.system(size: 14))
                                    .foregroundStyle(.blue)
                            }

                            VStack(alignment: .leading, spacing: 4) {
                                Text("\(index + 1). \(section.title)")
                                    .font(.subheadline.weight(.semibold))
                                Text(section.content)
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                                    .lineSpacing(2)
                            }
                        }
                        .padding(14)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color(.secondarySystemGroupedBackground), in: .rect(cornerRadius: 14))
                    }
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 20)
            }
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle("Terms of Service")
        .navigationBarTitleDisplayMode(.inline)
    }
}
