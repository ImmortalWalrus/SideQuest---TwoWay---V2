import SwiftUI

struct HelpFAQView: View {
    @State private var expandedId: String?

    private let faqs: [(id: String, q: String, a: String)] = [
        ("1", "How do I complete a quest?", "Accept a quest from the Quests tab, then follow the evidence requirements. For verified quests, you'll need to provide proof like GPS tracking, camera evidence, or in-app video depending on the quest type."),
        ("2", "What are the three paths?", "Warrior focuses on physical challenges like running and push-ups. Explorer is about getting outside and visiting new places. Mind covers meditation, reading, and brain training games."),
        ("3", "How does verification work?", "After you submit evidence, the community moderators review it. Auto-verification may also apply for GPS-tracked quests that meet all requirements. Most quests verify within a few minutes."),
        ("4", "What are Diamonds for?", "Diamonds are a premium currency earned from hard and expert quests, Master Contracts, and special events. They can be spent in the Shop on exclusive cosmetics."),
        ("5", "How do streaks work?", "Complete at least one quest per day to maintain your streak. Missing a day resets it to zero. Streaks above 3 days unlock bonus rewards on verified quests."),
        ("6", "What is a Master Contract?", "Master Contracts are 30-day challenges that require daily discipline across multiple quest types. They offer massive XP, gold, and diamond rewards but can be failed if you miss too many days."),
        ("7", "How does moderation work?", "Players review each other's quest evidence. Accurate moderation earns Karma. Repeated screenshots of evidence or false reports lead to suspensions."),
        ("8", "Can I play with friends?", "Yes! You can start group quests, compare stats on the leaderboard, and do NFC handshake verification for bonus multipliers."),
        ("9", "How is GPS tracking verified?", "GPS quests check your route for distance, speed limits, pause durations, and path continuity. Abnormal patterns (teleportation, impossible speeds) will flag the submission."),
        ("10", "What happens if my quest is rejected?", "You'll receive a notification explaining why. Common reasons include clock manipulation, insufficient evidence, or failing to meet quest-specific requirements. You can retry the quest."),
    ]

    var body: some View {
        List {
            Section {
                ForEach(faqs, id: \.id) { faq in
                    VStack(alignment: .leading, spacing: 0) {
                        Button {
                            withAnimation(.snappy(duration: 0.25)) {
                                expandedId = expandedId == faq.id ? nil : faq.id
                            }
                        } label: {
                            HStack(spacing: 12) {
                                Image(systemName: "questionmark.circle.fill")
                                    .foregroundStyle(.blue)
                                    .font(.body)
                                Text(faq.q)
                                    .font(.subheadline.weight(.medium))
                                    .foregroundStyle(.primary)
                                    .multilineTextAlignment(.leading)
                                Spacer()
                                Image(systemName: "chevron.down")
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(.tertiary)
                                    .rotationEffect(.degrees(expandedId == faq.id ? 180 : 0))
                            }
                            .padding(.vertical, 4)
                        }
                        .buttonStyle(.plain)

                        if expandedId == faq.id {
                            Text(faq.a)
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                                .padding(.leading, 36)
                                .padding(.top, 6)
                                .padding(.bottom, 4)
                                .transition(.opacity.combined(with: .move(edge: .top)))
                        }
                    }
                }
            } header: {
                Text("Frequently Asked Questions")
            }

            Section {
                HStack(spacing: 12) {
                    Image(systemName: "envelope.fill")
                        .foregroundStyle(.blue)
                        .frame(width: 28)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Contact Support")
                            .font(.subheadline.weight(.medium))
                        Text("support@sidequestapp.com")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            } header: {
                Text("Still need help?")
            }
        }
        .navigationTitle("Help & FAQ")
        .navigationBarTitleDisplayMode(.inline)
    }
}
