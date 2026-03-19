import SwiftUI

struct ModHubView: View {
    let appState: AppState
    @Environment(\.dismiss) private var dismiss
    @State private var showModSession: Bool = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    if appState.profile.isSuspended {
                        suspendedBanner
                    }
                    verifyNowCard
                    if !appState.pendingSubmissions.isEmpty {
                        questReviewSection
                    }
                    statsSection
                    infoSection
                }
                .padding(16)
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("Mod Hub")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .fullScreenCover(isPresented: $showModSession) {
                ModSessionView(appState: appState)
            }
        }
        .onAppear { appState.isImmersive = true }
        .onDisappear { appState.isImmersive = false }
    }

    private var suspendedBanner: some View {
        HStack(spacing: 12) {
            Image(systemName: "nosign")
                .font(.title2)
                .foregroundStyle(.red)
            VStack(alignment: .leading, spacing: 2) {
                Text("Mod Access Suspended")
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(.red)
                if let until = appState.profile.modBanUntil {
                    Text("Available again \(until.formatted(.relative(presentation: .named)))")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
        }
        .padding(14)
        .background(Color.red.opacity(0.1), in: .rect(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .strokeBorder(Color.red.opacity(0.3), lineWidth: 1)
        )
    }

    private var verifyNowCard: some View {
        VStack(spacing: 14) {
            Image(systemName: "shield.checkered")
                .font(.system(size: 44))
                .foregroundStyle(.orange)

            Text("Help Verify Quests")
                .font(.title3.weight(.bold))

            Text("Review 5 quests today to maintain your priority status")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            Button {
                showModSession = true
            } label: {
                Label("Verify Now", systemImage: "checkmark.shield.fill")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .tint(.orange)
            .disabled(appState.profile.isSuspended)
        }
        .padding(20)
        .background(Color(.secondarySystemGroupedBackground), in: .rect(cornerRadius: 16))
    }

    private var statsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Your Stats")
                .font(.headline)

            HStack(spacing: 0) {
                StatPill(icon: "heart.fill", value: "\(appState.profile.karma)", label: "Karma", color: .red)
                Divider().frame(height: 40)
                StatPill(icon: "target", value: "\(Int(appState.profile.modAccuracy * 100))%", label: "Accuracy", color: .green)
                Divider().frame(height: 40)
                StatPill(icon: "checkmark.circle.fill", value: "\(appState.profile.modSessionsCompleted)", label: "Sessions", color: .blue)
                Divider().frame(height: 40)
                StatPill(
                    icon: "camera.fill",
                    value: "\(appState.profile.screenshotStrikes)/3",
                    label: "SS Strikes",
                    color: appState.profile.screenshotStrikes > 0 ? .red : .secondary
                )
            }
            .padding(.vertical, 14)
            .background(Color(.secondarySystemGroupedBackground), in: .rect(cornerRadius: 14))
        }
    }

    private var infoSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("How Verification Works")
                .font(.headline)

            VStack(alignment: .leading, spacing: 10) {
                infoRow(number: "1", text: "Review evidence submitted by other users")
                infoRow(number: "2", text: "Vote: Approve, Reject, or Can't Tell")
                infoRow(number: "3", text: "5 votes needed per quest. Unanimous = verified.")
                infoRow(number: "4", text: "Accurate voting increases your Karma")
                infoRow(number: "5", text: "Higher Karma = faster verification for your quests")
            }
            .padding(14)
            .background(Color(.secondarySystemGroupedBackground), in: .rect(cornerRadius: 14))

            HStack(spacing: 10) {
                Image(systemName: "camera.fill")
                    .foregroundStyle(.orange)
                    .font(.caption)
                Text("Screenshots or screen recordings of other users' evidence are strictly prohibited and will result in account suspension.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(12)
            .background(Color.orange.opacity(0.08), in: .rect(cornerRadius: 10))
        }
    }

    private var questReviewSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Quest Submissions")
                    .font(.headline)
                Spacer()
                Text("\(appState.pendingSubmissions.count) pending")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.orange)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(.orange.opacity(0.12), in: Capsule())
            }

            ForEach(appState.pendingSubmissions) { submission in
                QuestSubmissionReviewCard(submission: submission, appState: appState)
            }
        }
    }

    private func infoRow(number: String, text: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Text(number)
                .font(.caption.weight(.bold))
                .foregroundStyle(.white)
                .frame(width: 22, height: 22)
                .background(.orange, in: Circle())
            Text(text)
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
    }
}

struct ModSessionView: View {
    let appState: AppState
    @Environment(\.dismiss) private var dismiss
    @State private var currentIndex: Int = 0
    @State private var reviewCount: Int = 0
    @State private var showCompletion: Bool = false
    @State private var screenshotAlert: ScreenshotAlertType? = nil
    @State private var didForceDismiss: Bool = false
    @State private var evidenceItems: [APIEvidenceForReview] = []
    @State private var isLoading: Bool = true

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                if isLoading {
                    VStack(spacing: 16) {
                        ProgressView()
                        Text("Loading evidence for review...")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if evidenceItems.isEmpty {
                    noEvidenceView
                } else {
                    ProgressView(value: Double(currentIndex + 1), total: Double(evidenceItems.count))
                        .tint(.orange)

                    if !showCompletion, currentIndex < evidenceItems.count {
                        let item = evidenceItems[currentIndex]
                        ScrollView {
                            VStack(spacing: 20) {
                                Text("\(currentIndex + 1) of \(evidenceItems.count)")
                                    .font(.caption.weight(.medium))
                                    .foregroundStyle(.secondary)

                                VStack(alignment: .leading, spacing: 8) {
                                    Text(item.questTitle)
                                        .font(.title3.weight(.bold))
                                    HStack(spacing: 8) {
                                        Label(item.evidenceType, systemImage: evidenceIcon(item.evidenceType))
                                            .font(.caption.weight(.semibold))
                                            .foregroundStyle(.orange)
                                            .padding(.horizontal, 10)
                                            .padding(.vertical, 4)
                                            .background(.orange.opacity(0.12), in: Capsule())
                                        Text("Submitted \(formattedDate(item.submittedAt))")
                                            .font(.caption)
                                            .foregroundStyle(.tertiary)
                                    }
                                }
                                .frame(maxWidth: .infinity, alignment: .leading)

                                evidencePreviewCard(evidenceType: item.evidenceType)

                                HStack(spacing: 12) {
                                    Button {
                                        vote(.reject, evidenceId: item.id)
                                    } label: {
                                        Label("Reject", systemImage: "xmark.circle.fill")
                                            .font(.headline)
                                            .frame(maxWidth: .infinity)
                                    }
                                    .buttonStyle(.bordered)
                                    .tint(.red)

                                    Button {
                                        vote(.cantTell, evidenceId: item.id)
                                    } label: {
                                        Label("Can't Tell", systemImage: "questionmark.circle.fill")
                                            .font(.headline)
                                            .frame(maxWidth: .infinity)
                                    }
                                    .buttonStyle(.bordered)

                                    Button {
                                        vote(.approve, evidenceId: item.id)
                                    } label: {
                                        Label("Approve", systemImage: "checkmark.circle.fill")
                                            .font(.headline)
                                            .frame(maxWidth: .infinity)
                                    }
                                    .buttonStyle(.borderedProminent)
                                    .tint(.green)
                                }
                            }
                            .padding(16)
                        }
                    } else if !didForceDismiss {
                        completionView
                    }
                }
            }
            .navigationTitle("Mod Session")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("End Session") {
                        if reviewCount > 0 {
                            showCompletion = true
                        } else {
                            dismiss()
                        }
                    }
                }
            }
            .task {
                await loadEvidence()
            }
        }
        .screenshotGuard {
            handleScreenshotDetected()
        }
        .alert(item: $screenshotAlert) { alertType in
            switch alertType {
            case .firstWarning:
                return Alert(
                    title: Text("Screenshot Detected"),
                    message: Text("Screenshots of user evidence are strictly prohibited. This is your first warning."),
                    dismissButton: .default(Text("I Understand"))
                )
            case .secondWarning:
                return Alert(
                    title: Text("Final Warning"),
                    message: Text("Another screenshot was detected. One more violation will result in a 24-hour ban and a 50 Karma penalty."),
                    dismissButton: .destructive(Text("Understood"))
                )
            case .suspended:
                return Alert(
                    title: Text("Account Suspended"),
                    message: Text("You have been suspended from moderation for 24 hours and lost 50 Karma due to repeated evidence screenshots."),
                    dismissButton: .default(Text("OK")) {
                        didForceDismiss = true
                        dismiss()
                    }
                )
            }
        }
    }

    private var noEvidenceView: some View {
        VStack(spacing: 16) {
            Image(systemName: "checkmark.seal.fill")
                .font(.system(size: 48))
                .foregroundStyle(.green)
            Text("All Caught Up!")
                .font(.title2.weight(.bold))
            Text("No evidence submissions to review right now. Check back later.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
            Button("Done") { dismiss() }
                .buttonStyle(.borderedProminent)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func evidencePreviewCard(evidenceType: String) -> some View {
        RoundedRectangle(cornerRadius: 16)
            .fill(Color(.tertiarySystemGroupedBackground))
            .frame(height: 280)
            .overlay {
                VStack(spacing: 8) {
                    Image(systemName: evidenceIcon(evidenceType))
                        .font(.system(size: 40))
                        .foregroundStyle(.tertiary)
                    Text("Evidence Preview")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    Text("Screenshot protected")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 4)
                        .background(.quaternary, in: Capsule())
                }
            }
    }

    private var completionView: some View {
        VStack(spacing: 16) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 60))
                .foregroundStyle(.green)
            Text("Session Complete!")
                .font(.title2.weight(.bold))
            Text("You reviewed \(reviewCount) submissions")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Text("+\(reviewCount * 2) Karma earned")
                .font(.caption.weight(.bold))
                .foregroundStyle(.orange)
            Button("Done") { dismiss() }
                .buttonStyle(.borderedProminent)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func loadEvidence() async {
        isLoading = true
        evidenceItems = []
        isLoading = false
    }

    private func handleScreenshotDetected() {
        let strikes = appState.profile.screenshotStrikes
        appState.recordModScreenshotStrike()
        switch strikes + 1 {
        case 1:
            screenshotAlert = .firstWarning
        case 2:
            screenshotAlert = .secondWarning
        default:
            screenshotAlert = .suspended
        }
    }

    private func vote(_ type: ModVote, evidenceId: String) {
        let approved = type == .approve
        if type != .cantTell {
        }
        appState.modVote(type)
        reviewCount += 1
        withAnimation(.snappy) {
            if currentIndex + 1 >= evidenceItems.count {
                showCompletion = true
            } else {
                currentIndex += 1
            }
        }
    }

    private func formattedDate(_ isoString: String) -> String {
        let formatter = ISO8601DateFormatter()
        guard let date = formatter.date(from: isoString) else { return isoString }
        let relative = RelativeDateTimeFormatter()
        relative.unitsStyle = .abbreviated
        return relative.localizedString(for: date, relativeTo: Date())
    }

    private func evidenceIcon(_ type: String) -> String {
        switch type {
        case "video", "timelapse": "video.fill"
        case "dualPhoto": "camera.fill"
        case "gpsTracking": "location.fill"
        case "pushUpTracking": "figure.strengthtraining.traditional"
        case "plankTracking": "figure.core.training"
        case "wallSitTracking": "figure.seated.side"
        case "meditationTracking": "brain.head.profile.fill"
        case "gratitudePhoto": "square.and.pencil"
        case "stepTracking": "figure.walk"
        case "focusTracking": "timer"
        case "affirmationPhoto": "sparkles"
        case "placeVerification": "brain.filled.head.profile"
        case "readingTracking": "book.fill"
        case "jumpRopeTracking": "figure.jumprope"
        default: "photo"
        }
    }
}

private enum ScreenshotAlertType: Identifiable {
    case firstWarning, secondWarning, suspended
    var id: Int {
        switch self {
        case .firstWarning: 1
        case .secondWarning: 2
        case .suspended: 3
        }
    }
}

nonisolated enum ModVote: Sendable {
    case approve, reject, cantTell
}
