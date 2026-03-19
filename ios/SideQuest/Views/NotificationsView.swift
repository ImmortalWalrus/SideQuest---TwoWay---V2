import SwiftUI

struct NotificationsView: View {
    let appState: AppState
    let onDeepLink: (AppNotification) -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                ForEach(appState.notifications) { notification in
                    Button {
                        onDeepLink(notification)
                        dismiss()
                    } label: {
                        HStack(spacing: 12) {
                            Image(systemName: iconForType(notification.type))
                                .font(.body)
                                .foregroundStyle(.white)
                                .frame(width: 36, height: 36)
                                .background(colorForType(notification.type).gradient, in: .rect(cornerRadius: 8))

                            VStack(alignment: .leading, spacing: 3) {
                                HStack {
                                    Text(notification.title)
                                        .font(.subheadline.weight(notification.isRead ? .regular : .semibold))
                                    Spacer()
                                    if !notification.isRead {
                                        Circle()
                                            .fill(.blue)
                                            .frame(width: 8, height: 8)
                                    }
                                }
                                Text(notification.message)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(2)
                                Text(notification.createdAt, style: .relative)
                                    .font(.caption2)
                                    .foregroundStyle(.tertiary)
                            }
                        }
                    }
                    .buttonStyle(.plain)
                }
            }
            .navigationTitle("Notifications")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    if appState.notifications.contains(where: { !$0.isRead }) {
                        Button("Read All") {
                            for i in appState.notifications.indices {
                                appState.notifications[i].isRead = true
                            }
                            appState.updateBadgeCount()
                        }
                        .font(.subheadline)
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }

    private func iconForType(_ type: NotificationType) -> String {
        switch type {
        case .questVerified: "checkmark.seal.fill"
        case .questRejected: "xmark.circle.fill"
        case .groupInvite: "person.2.fill"
        case .modTask: "shield.checkered"
        case .featuredQuest: "star.fill"
        case .voteAlignment: "exclamationmark.triangle.fill"
        case .weeklyReport: "chart.bar.fill"
        case .nudge: "hand.point.right.fill"
        }
    }

    private func colorForType(_ type: NotificationType) -> Color {
        switch type {
        case .questVerified: .green
        case .questRejected: .red
        case .groupInvite: .blue
        case .modTask: .orange
        case .featuredQuest: .yellow
        case .voteAlignment: .red
        case .weeklyReport: .indigo
        case .nudge: .teal
        }
    }
}
