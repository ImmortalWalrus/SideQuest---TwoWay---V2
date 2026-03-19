import SafariServices
import SwiftUI

private let externalEventCardSurface = Color(red: 0.161, green: 0.169, blue: 0.204)
private let externalEventPageBackground = Color(red: 0.086, green: 0.094, blue: 0.110)
private let externalEventCardHeight: CGFloat = 206
private let externalEventMediaHeight: CGFloat = 104
private let externalEventContentHeight: CGFloat = externalEventCardHeight - externalEventMediaHeight
private let externalEventRewardRowHeight: CGFloat = 20
private let externalEventContextRowHeight: CGFloat = 22
private let externalEventDetailBlockHeight: CGFloat = 40
struct ExternalEventCardView: View {
    let event: ExternalEvent
    var imageRefreshNonce: Int = 0

    private var rewardPolicy: ExternalEventRewardPolicy {
        ExternalEventPolicyService.policy(for: event)
    }

    private var iconImage: UIImage? {
        ExternalEventIconService.image(for: event)
    }

    private var contextualAuxiliaryBadgeText: String? {
        guard let auxiliaryBadgeText = event.auxiliaryBadgeText else { return nil }

        let normalizedAuxiliary = ExternalEventSupport.normalizeToken(auxiliaryBadgeText)
        let normalizedStatus = ExternalEventSupport.normalizeToken(event.cardStatusText)

        if normalizedAuxiliary.isEmpty {
            return auxiliaryBadgeText
        }

        if normalizedAuxiliary == normalizedStatus
            || normalizedAuxiliary.contains(normalizedStatus)
            || normalizedStatus.contains(normalizedAuxiliary) {
            return nil
        }

        return auxiliaryBadgeText
    }

    private var compactVenueReviewText: String? {
        guard event.shouldShowVenueReviews else { return nil }

        switch (event.displayVenueRating, event.trustedVenueReviewCount) {
        case let (rating?, count?) where count > 0:
            return "\(String(format: "%.1f", rating)) • \(abbreviatedReviewCount(count))"
        case let (rating?, _):
            return String(format: "%.1f", rating)
        default:
            return nil
        }
    }

    private var hasContextualStrip: Bool {
        event.cardNightlifeSummaryLine != nil || contextualAuxiliaryBadgeText != nil
    }

    var body: some View {
        VStack(spacing: 0) {
            mediaHeader

            VStack(alignment: .leading, spacing: 0) {
                rewardRow
                    .frame(height: externalEventRewardRowHeight)

                if hasContextualStrip {
                    Spacer()
                        .frame(height: 4)

                    contextualStrip
                        .frame(height: externalEventContextRowHeight)

                    Spacer()
                        .frame(height: 4)

                    detailBlock
                        .frame(height: externalEventDetailBlockHeight, alignment: .top)

                    Spacer(minLength: 0)
                } else {
                    Spacer(minLength: 0)
                    detailBlock
                        .frame(height: externalEventDetailBlockHeight, alignment: .top)
                    Spacer(minLength: 0)
                }
            }
            .padding(.horizontal, 12)
            .padding(.top, 5)
            .padding(.bottom, 7)
            .frame(height: externalEventContentHeight)
        }
        .frame(maxWidth: .infinity)
        .frame(height: externalEventCardHeight, alignment: .top)
        .background(cardShell)
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .strokeBorder(.white.opacity(0.08), lineWidth: 1)
        )
        .contentShape(Rectangle())
    }

    @ViewBuilder
    private var contextualStrip: some View {
        if let nightlifeSummaryLine = event.cardNightlifeSummaryLine {
            infoStrip(icon: "sparkles", text: nightlifeSummaryLine, tint: .pink.opacity(0.92))
        } else if let auxiliaryBadgeText = contextualAuxiliaryBadgeText {
            infoStrip(icon: "waveform.path.ecg", text: auxiliaryBadgeText, tint: .cyan.opacity(0.88))
        }
    }

    private var detailBlock: some View {
        VStack(alignment: .leading, spacing: 6) {
            detailLine(icon: "calendar", text: event.scheduleLine, prominent: true)
            detailLine(icon: "mappin.and.ellipse", text: event.locationLine, lineLimit: 1)
        }
    }

    private var cardShell: some View {
        ZStack {
            LinearGradient(
                colors: [
                    Color(red: 0.17, green: 0.18, blue: 0.22),
                    Color(red: 0.11, green: 0.12, blue: 0.15)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            RadialGradient(
                colors: [
                    event.eventType.tint.opacity(0.18),
                    .clear
                ],
                center: .topTrailing,
                startRadius: 20,
                endRadius: 220
            )
        }
    }

    private var mediaHeader: some View {
        ZStack(alignment: .topLeading) {
            backgroundImage(height: externalEventMediaHeight)

            LinearGradient(
                stops: [
                    .init(color: .black.opacity(0.08), location: 0),
                    .init(color: .black.opacity(0.16), location: 0.22),
                    .init(color: .black.opacity(0.42), location: 0.58),
                    .init(color: .black.opacity(0.82), location: 1)
                ],
                startPoint: .top,
                endPoint: .bottom
            )

            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 6) {
                    eventPill(event.eventType.displayName, accent: event.eventType.tint)
                    eventPill(event.cardStatusText, accent: event.statusDisplayColor)
                    Spacer(minLength: 0)
                }

                Spacer(minLength: 0)

                headerRow
            }
            .padding(10)
        }
        .overlay(alignment: .topTrailing) {
            if let compactVenueReviewText {
                headerReviewCapsule(text: compactVenueReviewText)
                    .padding(10)
            }
        }
        .frame(height: externalEventMediaHeight)
        .clipShape(
            UnevenRoundedRectangle(
                topLeadingRadius: 20,
                bottomLeadingRadius: 14,
                bottomTrailingRadius: 14,
                topTrailingRadius: 20,
                style: .continuous
            )
        )
    }

    private var headerRow: some View {
        HStack(alignment: .center, spacing: 10) {
            if let iconImage {
                Image(uiImage: iconImage)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 42, height: 42)
                    .shadow(color: .black.opacity(0.22), radius: 5, y: 2)
            }

            VStack(alignment: .leading, spacing: 4) {
                Text(event.cardTitle)
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(.white)
                    .lineLimit(2)
                    .shadow(color: .black.opacity(0.35), radius: 4, y: 2)

                if let genreLine = event.genreLine {
                    Text(genreLine)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.66))
                        .lineLimit(1)
                        .shadow(color: .black.opacity(0.25), radius: 3, y: 1)
                }
            }
            .frame(maxWidth: .infinity, minHeight: 42, alignment: .leading)

            Spacer(minLength: 0)
        }
    }

    private var rewardRow: some View {
        ViewThatFits(in: .horizontal) {
            rewardRowContent(includePrice: true)
            rewardRowContent(includePrice: false)
        }
    }

    private func rewardRowContent(includePrice: Bool) -> some View {
        HStack(spacing: 8) {
            rewardCapsule(icon: "bolt.fill", text: "\(rewardPolicy.xp) XP", tint: .orange)
            rewardCapsule(icon: "dollarsign.circle.fill", text: "\(rewardPolicy.coins)", tint: .yellow)
            if rewardPolicy.diamonds > 0 {
                rewardCapsule(icon: "diamond.fill", text: "\(rewardPolicy.diamonds)", tint: .cyan)
            }

            if includePrice,
               let priceLine = event.priceLine,
               event.nightlifePricingLine == nil {
                Text(priceLine)
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.white.opacity(0.46))
                    .lineLimit(1)
            }

            Spacer(minLength: 0)
            actionCapsule
        }
    }

    private var actionCapsule: some View {
        HStack(spacing: 4) {
            Text(event.primaryActionTitle)
                .font(.system(size: 10, weight: .heavy))
            Image(systemName: "arrow.up.right")
                .font(.system(size: 8, weight: .bold))
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .background(
            LinearGradient(
                colors: [.white.opacity(0.18), .white.opacity(0.08)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            ),
            in: Capsule()
        )
        .overlay(Capsule().strokeBorder(.white.opacity(0.08), lineWidth: 1))
    }

    @ViewBuilder
    private func backgroundImage(height: CGFloat) -> some View {
        if let primaryImageURL = event.primaryDisplayImageURL,
           let localImage = localImage(from: primaryImageURL) {
            Image(uiImage: localImage)
                .resizable()
                .aspectRatio(contentMode: .fill)
                .frame(maxWidth: .infinity)
                .frame(height: height)
                .clipped()
        } else if let primaryImageURL = event.primaryDisplayImageURL,
                  let url = URL(string: primaryImageURL) {
            AsyncImage(url: url) { phase in
                switch phase {
                case let .success(image):
                    image
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(maxWidth: .infinity)
                        .frame(height: height)
                        .clipped()
                default:
                    placeholderBackground(height: height)
                }
            }
        } else {
            placeholderBackground(height: height)
        }
    }

    private func localImage(from imageURL: String?) -> UIImage? {
        guard let imageURL, !imageURL.isEmpty else { return nil }
        if imageURL.hasPrefix("/") {
            return UIImage(contentsOfFile: imageURL)
        }
        if let cachedPath = ExternalEventImageCacheService.cachedLocalURLString(for: imageURL) {
            return UIImage(contentsOfFile: cachedPath)
        }
        guard let url = URL(string: imageURL), url.isFileURL else { return nil }
        return UIImage(contentsOfFile: url.path)
    }

    @ViewBuilder
    private func placeholderBackground(height: CGFloat) -> some View {
        ZStack {
            LinearGradient(
                colors: [
                    externalEventCardSurface,
                    Color(red: 0.13, green: 0.15, blue: 0.18)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            RadialGradient(
                colors: [
                    event.eventType.tint.opacity(0.24),
                    .clear
                ],
                center: .topTrailing,
                startRadius: 12,
                endRadius: 180
            )
        }
        .frame(maxWidth: .infinity)
        .frame(height: height)
    }

    private func eventPill(_ text: String, accent: Color) -> some View {
        HStack(spacing: 5) {
            Circle()
                .fill(accent)
                .frame(width: 5, height: 5)
            Text(text)
                .lineLimit(1)
        }
        .font(.system(size: 9, weight: .bold))
        .foregroundStyle(.white)
        .padding(.horizontal, 7)
        .padding(.vertical, 4)
        .background(.black.opacity(0.62), in: Capsule())
        .overlay(Capsule().strokeBorder(.white.opacity(0.08), lineWidth: 1))
    }

    private func rewardCapsule(icon: String, text: String, tint: Color) -> some View {
        HStack(spacing: 4) {
            Image(systemName: icon)
                .font(.system(size: 9, weight: .bold))
            Text(text)
                .font(.system(size: 10, weight: .bold))
                .lineLimit(1)
        }
        .foregroundStyle(tint)
        .padding(.horizontal, 7)
        .padding(.vertical, 4)
        .background(tint.opacity(0.11), in: Capsule())
        .overlay(Capsule().strokeBorder(tint.opacity(0.18), lineWidth: 1))
    }

    private func reviewCapsule(text: String) -> some View {
        HStack(spacing: 4) {
            Image(systemName: "star.fill")
                .font(.system(size: 9, weight: .bold))
            Text(text)
                .font(.system(size: 10, weight: .bold))
                .lineLimit(1)
        }
        .foregroundStyle(.yellow.opacity(0.95))
        .padding(.horizontal, 7)
        .padding(.vertical, 4)
        .background(.yellow.opacity(0.1), in: Capsule())
        .overlay(Capsule().strokeBorder(.yellow.opacity(0.2), lineWidth: 1))
    }

    private func headerReviewCapsule(text: String) -> some View {
        reviewCapsule(text: text)
            .background(.black.opacity(0.22), in: Capsule())
            .shadow(color: .black.opacity(0.25), radius: 6, y: 2)
    }

    private func abbreviatedReviewCount(_ count: Int) -> String {
        switch count {
        case 1_000_000...:
            return String(format: "%.1fM", Double(count) / 1_000_000)
        case 1_000...:
            return String(format: "%.1fK", Double(count) / 1_000)
        default:
            return "\(count)"
        }
    }

    private func infoStrip(icon: String, text: String, tint: Color) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 9, weight: .bold))
                .foregroundStyle(tint)
                .padding(.top, 1)

            Text(text)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.white.opacity(0.82))
                .lineLimit(1)
                .truncationMode(.tail)

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 9)
        .padding(.vertical, 5)
        .frame(minHeight: externalEventContextRowHeight)
        .background(.white.opacity(0.045), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(.white.opacity(0.05), lineWidth: 1)
        )
    }

    private func detailLine(icon: String, text: String, prominent: Bool = false, lineLimit: Int = 1) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(.white.opacity(prominent ? 0.78 : 0.56))
                .frame(width: 13)
                .padding(.top, 1)

            Text(text)
                .font(prominent ? .caption.weight(.semibold) : .caption)
                .foregroundStyle(.white.opacity(prominent ? 0.9 : 0.68))
                .lineLimit(lineLimit)
                .fixedSize(horizontal: false, vertical: lineLimit > 1)

            Spacer(minLength: 0)
        }
    }
}

extension ExternalEventCardView: Equatable {
    static func == (lhs: ExternalEventCardView, rhs: ExternalEventCardView) -> Bool {
        lhs.event == rhs.event && lhs.imageRefreshNonce == rhs.imageRefreshNonce
    }
}

struct ExternalEventDetailView: View {
    let event: ExternalEvent
    let appState: AppState
    @State private var safariURL: URL?
    @State private var eventQuestInstanceID: String?
    @State private var showEventCheckIn: Bool = false
    @State private var showEventPlaceVerification: Bool = false
    @State private var showEventDualPhoto: Bool = false
    @State private var showDoorTypeExplanation = false

    private var rewardPolicy: ExternalEventRewardPolicy {
        ExternalEventPolicyService.policy(for: event)
    }

    private var relatedEvents: [ExternalEvent] {
        appState.relatedExternalEvents(for: event)
    }

    private var eventQuest: Quest {
        event.sideQuestQuest(rewardPolicy: rewardPolicy)
    }

    private var eventQuestInstance: QuestInstance? {
        appState.externalEventQuestInstance(for: event)
    }

    private var presentedQuestInstance: QuestInstance? {
        guard let eventQuestInstanceID else { return eventQuestInstance }
        return appState.activeInstances.first(where: { $0.id == eventQuestInstanceID }) ?? eventQuestInstance
    }

    private var primaryQuestCTA: String {
        guard let instance = eventQuestInstance else { return "Start Quest" }

        switch instance.state {
        case .active:
            if instance.isGPSAutoCheckInQuest {
                if instance.canSubmit {
                    return "Submit Check-In"
                }
                return instance.isAutoCheckInInRange ? "Auto Check-In Active" : "Arrive to Auto Check-In"
            }
            if instance.quest.isPlaceVerificationQuest {
                return "Start Verification"
            }
            return "Continue Quest"
        case .submitted:
            return "Pending Verification"
        case .verified:
            return "Quest Complete"
        case .rejected, .failed:
            return "Retry Quest"
        case .pendingInvite, .pendingQueue:
            return "Quest Pending"
        }
    }

    private var canTapPrimaryQuestCTA: Bool {
        if let instance = eventQuestInstance {
            if instance.isGPSAutoCheckInQuest && !instance.canSubmit {
                return false
            }
            switch instance.state {
            case .submitted, .verified, .pendingInvite, .pendingQueue:
                return false
            default:
                return true
            }
        }
        return appState.activeQuestCount < 5
    }

    var body: some View {
        GeometryReader { proxy in
            let contentWidth = max(0, min(proxy.size.width - 32, 420))

            ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                titleHeader

                heroImage

                VStack(alignment: .leading, spacing: 12) {
                    detailSection(title: "Essentials", icon: "mappin.circle.fill") {
                        if let genreLine = event.genreLine {
                            detailRow(icon: "music.note", title: "Genre", value: genreLine)
                        }
                        detailRow(icon: "calendar", title: "When", value: event.detailScheduleLine)
                        detailRow(icon: "mappin.and.ellipse", title: "Where", value: event.detailLocationLine)
                        if let crowdAgeRangeLine = event.crowdAgeRangeLine {
                            detailRow(icon: "person.3.fill", title: "Crowd", value: crowdAgeRangeLine)
                        }
                        if event.shouldShowVenueReviews {
                            venueReviewsRow
                        }
                        if event.eventType != .partyNightlife,
                           event.recordKind != .venueNight,
                           let priceLine = event.priceLine {
                            detailRow(icon: "ticket.fill", title: "Price", value: priceLine)
                        }
                    }

                    if event.eventType == .partyNightlife || event.recordKind == .venueNight {
                        detailSection(title: "Access", icon: "sparkles.rectangle.stack.fill") {
                            if let exclusivityTierDisplay = event.exclusivityTierDisplay {
                                doorTypeRow(value: exclusivityTierDisplay)
                            }
                            if let nightlifeAccessLine = event.nightlifeAccessLine {
                                detailRow(icon: "person.text.rectangle.fill", title: "Access", value: nightlifeAccessLine)
                            }
                            if let nightlifePricingLine = event.nightlifePricingLine {
                                detailRow(icon: "creditcard.fill", title: "Pricing", value: nightlifePricingLine)
                            }
                            if let dressCodeText = event.dressCodeText, !dressCodeText.isEmpty {
                                detailRow(icon: "tshirt.fill", title: "Dress Code", value: dressCodeText)
                            }
                            NightlifeAIQuestionDisclosureView(
                                event: event,
                                question: .womenAtDoorFree
                            )
                            NightlifeAIQuestionDisclosureView(
                                event: event,
                                question: .menAtDoorFree
                            )
                        }
                    }

                    detailSection(title: "Quest", icon: "bolt.fill") {
                        detailRow(
                            icon: "sparkles.rectangle.stack.fill",
                            title: "Rewards",
                            value: "\(rewardPolicy.xp) XP • \(rewardPolicy.coins) coins • \(rewardPolicy.diamonds) diamonds"
                        )
                        detailRow(
                            icon: "checkmark.shield.fill",
                            title: "Verification",
                            value: "\(rewardPolicy.verificationSummary)\nOpens \(rewardPolicy.verificationOpensMinutesBefore)m early • closes \(rewardPolicy.verificationClosesMinutesAfter)m after start"
                        )
                        if let organizer = event.organizerName, !organizer.isEmpty {
                            detailRow(icon: "person.2.fill", title: "Organizer", value: organizer)
                        }
                    }

                    if relatedEvents.count > 1 {
                        detailSection(title: "Available Formats", icon: "square.grid.2x2.fill") {
                            LazyVGrid(columns: [GridItem(.adaptive(minimum: 110), spacing: 8)], spacing: 8) {
                                ForEach(relatedEvents, id: \.id) { variant in
                                    variantPill(for: variant)
                                }
                            }
                        }
                    }

                    if let description = event.descriptionLine, !description.isEmpty {
                        VStack(alignment: .leading, spacing: 6) {
                            HStack(spacing: 8) {
                                Image(systemName: "text.alignleft")
                                    .font(.system(size: 11, weight: .bold))
                                    .foregroundStyle(.white.opacity(0.56))
                                Text("About")
                                    .font(.caption.weight(.bold))
                                    .foregroundStyle(.white.opacity(0.56))
                            }
                            Text(description)
                                .font(.subheadline)
                                .foregroundStyle(.white.opacity(0.84))
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }

                    eventActionFooter
                }
                .padding(16)
                .background(externalEventCardSurface.opacity(0.72), in: RoundedRectangle(cornerRadius: 22))
                .overlay(RoundedRectangle(cornerRadius: 22).strokeBorder(.white.opacity(0.07), lineWidth: 1))
                .padding(.bottom, 28)
            }
                .frame(width: contentWidth, alignment: .leading)
                .padding(.top, 16)
                .frame(maxWidth: .infinity)
            }
        }
        .background(externalEventPageBackground.ignoresSafeArea())
        .presentationDragIndicator(.visible)
        .fullScreenCover(isPresented: $showEventCheckIn) {
            if let instance = presentedQuestInstance {
                GymCheckInView(quest: instance.quest, instanceId: instance.id, appState: appState)
            } else {
                QuestSessionUnavailableView { showEventCheckIn = false }
            }
        }
        .fullScreenCover(isPresented: $showEventPlaceVerification) {
            if let instance = presentedQuestInstance {
                PlaceVerificationView(quest: instance.quest, instanceId: instance.id, appState: appState)
            } else {
                QuestSessionUnavailableView { showEventPlaceVerification = false }
            }
        }
        .fullScreenCover(isPresented: $showEventDualPhoto) {
            if let instance = presentedQuestInstance {
                DualPhotoCaptureView(quest: instance.quest, instanceId: instance.id, appState: appState)
            } else {
                QuestSessionUnavailableView { showEventDualPhoto = false }
            }
        }
        .sheet(isPresented: Binding(
            get: { safariURL != nil },
            set: { if !$0 { safariURL = nil } }
        )) {
            if let safariURL {
                SafariSheet(url: safariURL)
            }
        }
        .toolbar(.hidden, for: .navigationBar)
    }

    @ViewBuilder
    private var eventActionFooter: some View {
        VStack(alignment: .leading, spacing: 10) {
            if let instance = eventQuestInstance,
               instance.state == .active,
               (event.eventType == .concert || event.eventType == .partyNightlife || event.recordKind == .venueNight || event.eventType == .sportsEvent) {
                Button {
                    launchDualPhotoProof(for: instance)
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "camera.viewfinder")
                            .font(.system(size: 12, weight: .bold))
                        Text("Optional: Add Dual-Photo Proof")
                            .font(.caption.weight(.semibold))
                        Spacer(minLength: 0)
                    }
                    .foregroundStyle(.white.opacity(0.78))
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)
                    .background(.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                }
                .buttonStyle(.plain)
            }

            if let instance = eventQuestInstance,
               instance.isGPSAutoCheckInQuest,
               !instance.canSubmit {
                let remaining = instance.timeUntilSubmit
                let minutes = Int(remaining) / 60
                let seconds = Int(remaining) % 60
                Label(
                    instance.isAutoCheckInInRange
                        ? "Auto check-in is running in the background • \(minutes)m \(seconds)s left."
                        : "Once you arrive on-site, check-in starts automatically in the background.",
                    systemImage: instance.isAutoCheckInInRange ? "location.fill" : "location.slash"
                )
                .font(.caption)
                .foregroundStyle(instance.isAutoCheckInInRange ? .green.opacity(0.82) : .white.opacity(0.54))
            }

            ViewThatFits(in: .horizontal) {
                HStack(spacing: 10) {
                    primaryQuestCTAButton
                    if let destinationURL = event.trackedDestinationURL {
                        secondaryActionButton(destinationURL)
                    }
                }

                VStack(spacing: 10) {
                    primaryQuestCTAButton
                    if let destinationURL = event.trackedDestinationURL {
                        secondaryActionButton(destinationURL)
                    }
                }
            }

            if eventQuestInstance == nil && appState.activeQuestCount >= 5 {
                Text("You already have 5 active quests. Finish one before starting another.")
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.5))
            }
        }
    }

    private var primaryQuestCTAButton: some View {
        Button {
            handlePrimaryQuestCTA()
        } label: {
            HStack(spacing: 8) {
                Image(systemName: primaryQuestCTAIcon)
                    .font(.system(size: 13, weight: .bold))
                Text(primaryQuestCTA)
                    .font(.subheadline.weight(.bold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.82)
                Spacer(minLength: 0)
            }
            .foregroundStyle(.white)
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
            .background(event.eventType.tint.opacity(canTapPrimaryQuestCTA ? 0.82 : 0.42), in: RoundedRectangle(cornerRadius: 14))
        }
        .frame(maxWidth: .infinity)
        .buttonStyle(.plain)
        .disabled(!canTapPrimaryQuestCTA)
    }

    private func secondaryActionButton(_ destinationURL: URL) -> some View {
        Button {
            safariURL = destinationURL
        } label: {
            HStack(spacing: 6) {
                Text(event.primaryActionTitle)
                    .font(.caption.weight(.bold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.84)
                Image(systemName: "arrow.up.right")
                    .font(.system(size: 11, weight: .bold))
            }
            .foregroundStyle(.white.opacity(0.9))
            .padding(.horizontal, 12)
            .padding(.vertical, 13)
            .background(.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 14))
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .strokeBorder(.white.opacity(0.08), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }

    private var primaryQuestCTAIcon: String {
        guard let instance = eventQuestInstance else { return "sparkles" }
        switch instance.state {
        case .active:
            if instance.isGPSAutoCheckInQuest {
                return instance.canSubmit ? "checkmark.circle.fill" : "location.fill"
            }
            if instance.quest.isPlaceVerificationQuest {
                return "location.fill"
            }
            return "play.fill"
        case .submitted:
            return "clock.badge.checkmark.fill"
        case .verified:
            return "checkmark.seal.fill"
        case .rejected, .failed:
            return "arrow.clockwise"
        case .pendingInvite, .pendingQueue:
            return "hourglass"
        }
    }

    private func handlePrimaryQuestCTA() {
        if let instance = eventQuestInstance {
            switch instance.state {
            case .active:
                if instance.isGPSAutoCheckInQuest {
                    if instance.canSubmit {
                        appState.submitEvidence(for: instance.id)
                    }
                } else {
                    launchVerification(for: instance)
                }
            case .rejected, .failed:
                if let retried = appState.retryExternalEventQuest(event) {
                    eventQuestInstanceID = retried.id
                }
            case .submitted, .verified, .pendingInvite, .pendingQueue:
                break
            }
            return
        }

        if let started = appState.startExternalEventQuest(event) {
            eventQuestInstanceID = started.id
        }
    }

    private func launchVerification(for instance: QuestInstance) {
        eventQuestInstanceID = instance.id
        if instance.quest.requiredPlaceType?.isGPSOnly == true {
            showEventCheckIn = true
        } else {
            showEventPlaceVerification = true
        }
    }

    private func launchDualPhotoProof(for instance: QuestInstance) {
        eventQuestInstanceID = instance.id
        showEventDualPhoto = true
    }

    private var heroImage: some View {
        Group {
            if event.galleryImageURLs.count > 1 {
                TabView {
                    ForEach(event.galleryImageURLs, id: \.self) { imageURL in
                        heroImageView(for: imageURL)
                    }
                }
                .tabViewStyle(.page(indexDisplayMode: .automatic))
            } else if let primaryImageURL = event.primaryDisplayImageURL {
                heroImageView(for: primaryImageURL)
            } else {
                placeholderHero
            }
        }
        .frame(height: 232)
        .clipped()
        .clipShape(RoundedRectangle(cornerRadius: 24))
        .overlay(alignment: .topLeading) {
            HStack(spacing: 8) {
                detailPill(event.eventType.displayName, color: event.eventType.tint)
                detailPill(event.statusDisplayText, color: event.statusDisplayColor)
            }
            .padding(14)
        }
    }

    @ViewBuilder
    private var placeholderHero: some View {
        externalEventCardSurface
    }

    @ViewBuilder
    private func heroImageView(for imageURL: String) -> some View {
        if let localImage = localImage(from: imageURL) {
            Image(uiImage: localImage)
                .resizable()
                .aspectRatio(contentMode: .fill)
        } else if let url = URL(string: imageURL) {
            AsyncImage(url: url) { phase in
                switch phase {
                case let .success(image):
                    image
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                default:
                    placeholderHero
                }
            }
        } else {
            placeholderHero
        }
    }

    private func localImage(from imageURL: String?) -> UIImage? {
        guard let imageURL, !imageURL.isEmpty else { return nil }
        if imageURL.hasPrefix("/") {
            return UIImage(contentsOfFile: imageURL)
        }
        if let cachedPath = ExternalEventImageCacheService.cachedLocalURLString(for: imageURL) {
            return UIImage(contentsOfFile: cachedPath)
        }
        guard let url = URL(string: imageURL), url.isFileURL else { return nil }
        return UIImage(contentsOfFile: url.path)
    }

    private func detailPill(_ text: String, color: Color) -> some View {
        HStack(spacing: 5) {
            Circle()
                .fill(color)
                .frame(width: 5, height: 5)
            Text(text)
                .lineLimit(1)
        }
        .font(.system(size: 9, weight: .bold))
        .foregroundStyle(.white)
        .padding(.horizontal, 7)
        .padding(.vertical, 4)
        .background(.black.opacity(0.62), in: Capsule())
        .overlay(Capsule().strokeBorder(.white.opacity(0.08), lineWidth: 1))
    }

    private var titleHeader: some View {
        HStack(alignment: .center, spacing: 12) {
            if let icon = ExternalEventIconService.image(for: event) {
                Image(uiImage: icon)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 52, height: 52)
                    .shadow(color: .black.opacity(0.26), radius: 6, y: 2)
            }

            Text(event.title)
                .font(.title3.weight(.bold))
                .foregroundStyle(.white)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, minHeight: 52, alignment: .leading)

            Spacer(minLength: 0)
        }
    }

    private func detailSection<Content: View>(
        title: String,
        icon: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: icon)
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(.white.opacity(0.56))
                Text(title)
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.white.opacity(0.56))
            }

            VStack(alignment: .leading, spacing: 10) {
                content()
            }
        }
        .padding(12)
        .background(.white.opacity(0.045), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(.white.opacity(0.05), lineWidth: 1)
        )
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func detailRow(icon: String, title: String, value: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(.white.opacity(0.68))
                .frame(width: 18)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.white.opacity(0.48))
                Text(value)
                    .font(.subheadline)
                    .foregroundStyle(.white.opacity(0.88))
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private var venueReviewsRow: some View {
        let row = HStack(alignment: .top, spacing: 10) {
            Image(systemName: "star.bubble.fill")
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(.white.opacity(0.68))
                .frame(width: 18)

            VStack(alignment: .leading, spacing: 4) {
                Text("Venue Reviews")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.white.opacity(0.48))

                HStack(alignment: .center, spacing: 8) {
                    if let rating = event.displayVenueRating {
                        HStack(spacing: 5) {
                            Text(String(format: "%.1f", rating))
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(.white.opacity(0.92))
                            starRatingView(rating: rating)
                        }
                    }

                    if let count = event.trustedVenueReviewCount, count > 0 {
                        Text("\(count) venue reviews")
                            .font(.subheadline)
                            .foregroundStyle(.white.opacity(0.88))
                            .fixedSize(horizontal: false, vertical: true)
                    } else if event.displayVenueRating != nil {
                        Text("Venue rating")
                            .font(.subheadline)
                            .foregroundStyle(.white.opacity(0.88))
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    if event.venueReviewDestinationURL != nil {
                        Image(systemName: "arrow.up.right")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundStyle(.white.opacity(0.55))
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(maxWidth: .infinity, alignment: .leading)

        if let reviewURL = event.venueReviewDestinationURL {
            Button {
                safariURL = reviewURL
            } label: {
                row
            }
            .buttonStyle(.plain)
        } else {
            row
        }
    }

    private func starRatingView(rating: Double) -> some View {
        HStack(spacing: 2) {
            ForEach(0..<5, id: \.self) { index in
                let remaining = max(0, min(1.0, rating - Double(index)))
                Image(systemName: starSymbol(for: remaining))
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Color(red: 0.98, green: 0.78, blue: 0.26))
            }
        }
    }

    private func starSymbol(for remaining: Double) -> String {
        if remaining >= 0.75 {
            return "star.fill"
        }
        if remaining >= 0.25 {
            return "star.leadinghalf.filled"
        }
        return "star"
    }

    private func doorTypeRow(value: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "crown.fill")
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(.white.opacity(0.68))
                .frame(width: 18)

            VStack(alignment: .leading, spacing: 4) {
                Text("Door Type")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.white.opacity(0.48))

                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(value)
                        .font(.subheadline)
                        .foregroundStyle(.white.opacity(0.88))
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)

                    Button {
                        withAnimation(.easeInOut(duration: 0.16)) {
                            showDoorTypeExplanation.toggle()
                        }
                    } label: {
                        Image(systemName: "info.circle")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(.white.opacity(0.62))
                    }
                    .buttonStyle(.plain)

                    Spacer(minLength: 0)
                }

                if showDoorTypeExplanation {
                    Text(doorTypeExplanation(for: value))
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.64))
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func doorTypeExplanation(for value: String) -> String {
        let normalized = ExternalEventSupport.normalizeToken(value)
        if normalized.contains("ultra selective") {
            return "Top-tier hard door. Walk-ins are uncommon on busy nights, and table spend or strong promoter access usually helps most."
        }
        if normalized.contains("strict") {
            return "Tougher-than-average door. Dress code, timing, ratio, and guest list quality matter a lot, and tables can help on big nights."
        }
        if normalized.contains("selective") {
            return "Moderately selective. Guest list, timing, and presentation can help, but it is not automatically the hardest room in town."
        }
        if normalized.contains("casual") {
            return "Usually approachable, with lighter screening on busier nights for dress code, capacity, or crowd mix."
        }
        return "Most walk-ins have a realistic shot. Standard cover, timing, and dress code still matter, but the door is not especially hard."
    }

    private func variantPill(for variant: ExternalEvent) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(variant.raceType ?? variant.eventType.displayName)
                .font(.caption.weight(.bold))
                .foregroundStyle(.white)
            Text(variant.scheduleLine)
                .font(.caption2.weight(.medium))
                .foregroundStyle(.white.opacity(0.6))
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(.white.opacity(0.06), lineWidth: 1))
    }
}

private struct NightlifeAIQuestionDisclosureView: View {
    let event: ExternalEvent
    let question: NightlifeAIQuestion

    @State private var isExpanded = false
    @State private var isLoading = false
    @State private var answerText: String?
    @State private var errorText: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Button {
                handleTap()
            } label: {
                HStack(alignment: .top, spacing: 10) {
                    Image(systemName: question.iconName)
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(.white.opacity(0.68))
                        .frame(width: 18)

                    VStack(alignment: .leading, spacing: 4) {
                        HStack(spacing: 8) {
                            Text(question.title)
                                .font(.caption.weight(.bold))
                                .foregroundStyle(.white.opacity(0.48))

                            Spacer(minLength: 8)

                            if isLoading {
                                ProgressView()
                                    .tint(.white.opacity(0.76))
                                    .scaleEffect(0.78)
                            } else {
                                Image(systemName: isExpanded ? "chevron.up" : "sparkles")
                                    .font(.system(size: 11, weight: .bold))
                                    .foregroundStyle(.white.opacity(0.72))
                            }
                        }

                        if isExpanded {
                            Group {
                                if let answerText, !answerText.isEmpty {
                                    Text(answerText)
                                } else if isLoading {
                                    Text(question.loadingCopy)
                                        .foregroundStyle(.white.opacity(0.62))
                                } else if let errorText, !errorText.isEmpty {
                                    Text(errorText)
                                        .foregroundStyle(.white.opacity(0.68))
                                } else {
                                    Text(question.tapCopy)
                                        .foregroundStyle(.white.opacity(0.62))
                                }
                            }
                            .font(.subheadline)
                            .multilineTextAlignment(.leading)
                            .fixedSize(horizontal: false, vertical: true)
                        } else {
                            Text(question.tapCopy)
                                .font(.caption)
                                .foregroundStyle(.white.opacity(0.5))
                                .multilineTextAlignment(.leading)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if isExpanded, !isLoading, answerText == nil {
                HStack(spacing: 10) {
                    Spacer(minLength: 28)
                    Button {
                        loadAnswer()
                    } label: {
                        Text("Retry")
                            .font(.caption.weight(.bold))
                            .foregroundStyle(.white.opacity(0.86))
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .background(.white.opacity(0.08), in: Capsule())
                    }
                    .buttonStyle(.plain)
                    Spacer(minLength: 0)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func handleTap() {
        withAnimation(.easeInOut(duration: 0.16)) {
            isExpanded.toggle()
        }
        guard isExpanded, answerText == nil, !isLoading else { return }
        loadAnswer()
    }

    private func loadAnswer() {
        isLoading = true
        errorText = nil

        Task {
            do {
                let answer = try await NightlifeQnAService.shared.answer(for: event, question: question)
                await MainActor.run {
                    self.answerText = answer.text
                    self.isLoading = false
                }
            } catch {
                let fallback = fallbackEntryLine
                await MainActor.run {
                    self.answerText = fallback
                    self.errorText = fallback == nil ? (error.localizedDescription.isEmpty ? "No answer available right now." : error.localizedDescription) : nil
                    self.isLoading = false
                }
            }
        }
    }

    private var fallbackEntryLine: String? {
        switch question {
        case .womenAtDoorFree:
            return event.womenEntryLine
        case .menAtDoorFree:
            return event.menEntryLine
        }
    }
}

private extension ExternalEvent {
    var cardTitle: String {
        var safeTitle = ExternalEventSupport.plainText(title) ?? title
        if recordKind == .venueNight, !isScheduledTonight {
            safeTitle = safeTitle.replacingOccurrences(
                of: #"(?i)\s+tonight$"#,
                with: "",
                options: .regularExpression
            )
        }
        let separators = [" - ", " | ", " • ", " — ", " —", ":", ","]
        for separator in separators {
            let components = safeTitle.components(separatedBy: separator)
            if let first = components.first?.trimmingCharacters(in: .whitespacesAndNewlines),
               first.count >= 10,
               first.count <= 42 {
                return first
            }
        }

        if safeTitle.count > 54 {
            return String(safeTitle.prefix(54)).trimmingCharacters(in: .whitespacesAndNewlines) + "..."
        }

        return safeTitle
    }

    var genreLine: String? {
        guard eventType == .concert else { return nil }

        let blockedTokens = Set([
            "music",
            "live music",
            "concert",
            "concerts",
            "performing and visual arts",
            "performing arts",
            "arts"
        ])

        let candidates = [subcategory, category] + tags
        var labels: [String] = []

        for candidate in candidates {
            guard let candidate else { continue }
            let parts = candidate.split(whereSeparator: { $0 == "/" || $0 == "|" || $0 == "," })
            for part in parts {
                let rawValue = part.trimmingCharacters(in: .whitespacesAndNewlines)
                let normalized = ExternalEventSupport.normalizeToken(rawValue)
                guard !rawValue.isEmpty, !normalized.isEmpty, !blockedTokens.contains(normalized) else {
                    continue
                }
                if !labels.contains(where: { ExternalEventSupport.normalizeToken($0) == normalized }) {
                    labels.append(rawValue)
                }
                if labels.count == 2 {
                    return labels.joined(separator: " • ")
                }
            }
        }

        return labels.isEmpty ? nil : labels.joined(separator: " • ")
    }

    var descriptionLine: String? {
        let primaryDescription = shortDescription ?? fullDescription
        if eventType == .partyNightlife || recordKind == .venueNight {
            return preferredNightlifeAboutText
                ?? nightlifeFallbackAboutText
        }
        return ExternalEventSupport.plainText(primaryDescription)
    }

    var nightlifeSignalLine: String? {
        guard eventType == .partyNightlife || recordKind == .venueNight else { return nil }

        var parts: [String] = []
        if let exclusivityLabel {
            parts.append(exclusivityLabel)
        }
        let explicitEntry = ExternalEventSupport.normalizeToken([entryPolicySummary, doorPolicyText].compactMap { $0 }.joined(separator: " "))
        if explicitEntry.contains("bottle service only") || explicitEntry.contains("does not have general admission") {
            parts.append("Tables Only")
        } else if bottleServiceAvailable == true {
            parts.append(guestListAvailable == true ? "Guest List + Tables" : "Bottle Service")
        } else if guestListAvailable == true {
            parts.append("Guest List")
        }
        if let crowdAgeRangeBadge {
            parts.append(crowdAgeRangeBadge)
        } else if let ageMinimum {
            parts.append("\(ageMinimum)+")
        }
        if let condensedDoorPolicy {
            parts.append(condensedDoorPolicy)
        }

        let uniqueParts = uniqueOrdered(parts)
        return uniqueParts.isEmpty ? nil : uniqueParts.prefix(3).joined(separator: " • ")
    }

    var exclusivityTierDisplay: String? {
        guard eventType == .partyNightlife || recordKind == .venueNight else { return nil }
        if let exclusivityTierLabel, !exclusivityTierLabel.isEmpty {
            return exclusivityTierLabel
        }
        let score = exclusivityScore
            ?? venueSignalScore
            ?? crossSourceConfirmationScore
            ?? 0
        let entryHaystack = ExternalEventSupport.normalizeToken([entryPolicySummary, doorPolicyText].compactMap { $0 }.joined(separator: " "))
        let bottleServiceOnlySignal = bottleServiceAvailable == true && (
            guestListAvailable != true
            || entryHaystack.contains("bottle service only")
            || entryHaystack.contains("does not have general admission")
        )
        if bottleServiceOnlySignal && ((tableMinPrice ?? 0) >= 1000 || (coverPrice ?? 0) >= 100 || score >= 28) {
            return "Ultra-Selective Door"
        }
        if bottleServiceOnlySignal && ((tableMinPrice ?? 0) >= 500 || score >= 22) {
            return "Strict Door"
        }
        if score >= 20
            || (tableMinPrice ?? 0) >= 300
            || (coverPrice ?? 0) >= 50
            || (guestListAvailable == true && (tableMinPrice ?? 0) >= 150)
            || bottleServiceOnlySignal {
            return "Selective Door"
        }
        if score >= 14
            || reservationURL != nil
            || guestListAvailable == true
            || bottleServiceAvailable == true
            || (tableMinPrice ?? 0) >= 100
            || (coverPrice ?? 0) >= 20 {
            return "Casual Door"
        }
        return "Open Door"
    }

    var nightlifeEntryLine: String? {
        guard eventType == .partyNightlife || recordKind == .venueNight else { return nil }
        let cleaned = sanitizedNightlifeEntryText(entryPolicySummary)
        guard ExternalEventSupport.hasSubstantiveNovelty(
            cleaned,
            comparedTo: [womenEntryPolicyText, menEntryPolicyText]
        ) else {
            return nil
        }
        return cleaned
    }

    var womenEntryLine: String? {
        guard eventType == .partyNightlife || recordKind == .venueNight else { return nil }
        if let explicit = sanitizedNightlifeGenderText(
            nightlifeGenderSourceText(
                preferredKeys: ["discotech_women_entry", "clubbable_women_entry", "official_site_women_entry"],
                fallbackTexts: [womenEntryPolicyText, dressCodeText, entryPolicySummary, doorPolicyText]
            ),
            genderTokens: ["women", "woman", "ladies", "girls", "female"]
        ) {
            return explicit
        }

        if bottleServiceAvailable == true && guestListAvailable != true {
            return "This room is mostly table-driven. Free entry is not clearly published, and door access is usually discretionary."
        }
        if guestListAvailable == true {
            return "Guest list is usually the best shot. Free or reduced entry may happen on list, but dress code, timing, and door discretion still matter."
        }
        return "Free-entry terms are not clearly published, and door access appears discretionary."
    }

    var menEntryLine: String? {
        guard eventType == .partyNightlife || recordKind == .venueNight else { return nil }
        return sanitizedNightlifeGenderText(
            nightlifeGenderSourceText(
                preferredKeys: ["discotech_men_entry", "clubbable_men_entry", "official_site_men_entry"],
                fallbackTexts: [menEntryPolicyText, dressCodeText, entryPolicySummary, doorPolicyText]
            ),
            genderTokens: ["men", "man", "guys", "gentlemen", "male"]
        )
    }

    var nightlifePricingLine: String? {
        guard eventType == .partyNightlife || recordKind == .venueNight else { return nil }

        var parts: [String] = []
        if let coverPrice {
            parts.append("Cover \(formatCurrency(coverPrice))")
        }
        if let tableMinPrice {
            parts.append("Table from \(formatCurrency(tableMinPrice))")
        }
        if reservationURL != nil && parts.isEmpty {
            parts.append("Reservations Open")
        }
        return parts.isEmpty ? nil : parts.joined(separator: " • ")
    }

    var cardNightlifeSummaryLine: String? {
        guard eventType == .partyNightlife || recordKind == .venueNight else { return nil }

        var parts: [String] = []
        if let nightlifeSignalLine {
            parts.append(nightlifeSignalLine)
        }
        if let nightlifePricingLine {
            parts.append(nightlifePricingLine)
        }

        let joined = parts
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .joined(separator: "  •  ")

        return joined.isEmpty ? nil : joined
    }

    var nightlifeDoorLine: String? {
        guard eventType == .partyNightlife || recordKind == .venueNight else { return nil }

        var lines: [String] = []
        let entryHaystack = ExternalEventSupport.normalizeToken(
            [entryPolicySummary, doorPolicyText].compactMap { $0 }.joined(separator: " ")
        )

        if entryHaystack.contains("bottle service only")
            || entryHaystack.contains("does not have general admission") {
            lines.append("Bottle service only. No general admission.")
        } else if guestListAvailable == true && bottleServiceAvailable == true {
            lines.append("Guest list or table booking.")
        } else if guestListAvailable == true {
            lines.append("Guest list available.")
        } else if bottleServiceAvailable == true {
            lines.append("Table booking favored.")
        }

        if let cleaned = sanitizedNightlifeDoorText(doorPolicyText),
           ExternalEventSupport.hasSubstantiveNovelty(
                cleaned,
                comparedTo: lines.map(Optional.some) + [entryPolicySummary, womenEntryPolicyText, menEntryPolicyText]
           ) {
            lines.append(cleaned)
        }

        let unique = ExternalEventSupport.uniqueMeaningfulLines(lines.map(Optional.some))
        return unique.isEmpty ? nil : unique.joined(separator: "\n")
    }

    var nightlifeAccessLine: String? {
        guard eventType == .partyNightlife || recordKind == .venueNight else { return nil }

        let doorSummary = nightlifeDoorLine?
            .replacingOccurrences(of: "\n", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let unique = ExternalEventSupport.uniqueMeaningfulLines([
            nightlifeEntryLine,
            doorSummary
        ])
        guard !unique.isEmpty else { return nil }
        return unique.joined(separator: " ")
    }

    var auxiliaryBadgeText: String? {
        if let socialProofLabel, !socialProofLabel.isEmpty {
            return socialProofLabel
        }
        if let urgencyBadge {
            return urgencyBadge.rawValue.capitalized
        }
        return nil
    }

    var primaryActionTitle: String {
        if recordKind == .venueNight {
            return reservationURL != nil ? "Reserve" : "View Venue"
        }
        switch eventType {
        case .groupRun, .race5k, .race10k, .raceHalfMarathon, .raceMarathon:
            return "Join Event"
        case .concert, .sportsEvent:
            return ticketURL != nil ? "Buy Tickets" : "View Event"
        case .partyNightlife:
            return reservationURL != nil ? "Reserve" : "View Venue"
        case .weekendActivity, .socialCommunityEvent, .otherLiveEvent:
            return ticketURL != nil ? "Buy Tickets" : "View Event"
        }
    }

    var cardStatusText: String {
        if recordKind == .venueNight {
            if bottleServiceAvailable == true { return "Bottle Service" }
            if guestListAvailable == true { return "Guest List" }
            if reservationURL != nil { return "Reserve" }
            if let ageMinimum { return "\(ageMinimum)+" }
            return isScheduledTonight ? "Tonight" : "Upcoming"
        }

        if let urgencyDisplayText {
            return urgencyDisplayText
        }

        switch availabilityStatus {
        case .openRegistration: return "Open"
        case .onsale: return "On Sale"
        case .available: return "Available"
        case .registrationClosed: return "Closed"
        case .soldOut: return "Sold Out"
        case .cancelled: return "Canceled"
        case .postponed: return "Postponed"
        case .rescheduled: return "Rescheduled"
        case .ended: return "Ended"
        case .unknown:
            switch status {
            case .scheduled: return "Scheduled"
            case .onsale: return "On Sale"
            case .openRegistration: return "Open"
            case .soldOut: return "Sold Out"
            case .cancelled: return "Canceled"
            case .postponed: return "Postponed"
            case .rescheduled: return "Rescheduled"
            case .ended: return "Ended"
            case .unknown: return "Upcoming"
            }
        }
    }

    var trackedDestinationURL: URL? {
        let rawValue: String?
        if let nightlifePreferredURL, (eventType == .partyNightlife || recordKind == .venueNight) {
            rawValue = nightlifePreferredURL
        } else if let candidate = normalizedWebURL(from: registrationURL) {
            rawValue = candidate
        } else if let candidate = normalizedWebURL(from: ticketURL) {
            rawValue = candidate
        } else if let candidate = normalizedWebURL(from: sourceURL) {
            rawValue = candidate
        } else if let candidate = normalizedWebURL(from: reservationURL) {
            rawValue = candidate
        } else {
            rawValue = nil
        }
        guard let rawValue,
              var components = URLComponents(string: rawValue)
        else {
            return nil
        }

        var queryItems = components.queryItems ?? []
        let additions: [(String, String)] = [
            ("utm_source", "sidequest"),
            ("utm_medium", "app"),
            ("utm_campaign", "event_quests"),
            ("sq_ref", "sidequest"),
            ("sq_source", source.rawValue),
            ("sq_event_id", sourceEventID)
        ]
        for (name, value) in additions where !queryItems.contains(where: { $0.name == name }) {
            queryItems.append(URLQueryItem(name: name, value: value))
        }
        components.queryItems = queryItems
        return components.url
    }

    var scheduleLine: String {
        if let structured = structuredVenueNightScheduleLine(shortStyle: true) {
            return structured
        }
        if let venueNightScheduleLine {
            return venueNightScheduleLine
        }
        if let bestNightsLine = venueNightBestNightsLine(shortStyle: true) {
            return bestNightsLine
        }
        return displayDate(dateStyle: "EEE, MMM d • h:mm a")
    }

    var detailScheduleLine: String {
        if let structured = structuredVenueNightScheduleLine(shortStyle: false) {
            return structured
        }
        if let venueNightScheduleLine {
            return venueNightScheduleLine
        }
        if let bestNightsLine = venueNightBestNightsLine(shortStyle: false) {
            return bestNightsLine
        }
        let primary = displayDate(dateStyle: "EEEE, MMM d • h:mm a")
        guard primary != "Time TBA", let timezone else { return primary }
        return "\(primary) \(timezoneAbbreviation(for: timezone))"
    }

    var locationLine: String {
        let locationParts: [String] = [venueName, cityStateLine].compactMap { value in
            guard let value, !value.isEmpty else { return nil }
            return value
        }

        if locationParts.isEmpty {
            return "Location TBA"
        }

        return locationParts.joined(separator: " • ")
    }

    var detailLocationLine: String {
        if let preciseAddressLine {
            return preciseAddressLine
        }
        let fallbackBits: [String] = [venueName, cityStateLine].compactMap { value in
            guard let value, !value.isEmpty else { return nil }
            return value
        }
        return fallbackBits.isEmpty ? "Location TBA" : fallbackBits.joined(separator: " • ")
    }

    var displayVenueRating: Double? {
        guard !shouldSuppressNightclubVenueReviews else { return nil }
        return rawDisplayVenueRating
    }

    var shouldShowVenueReviews: Bool {
        venueReviewLine != nil
    }

    var venueReviewLine: String? {
        switch (displayVenueRating, trustedVenueReviewCount) {
        case let (rating?, count?) where count > 0:
            return String(format: "%.1f★ from %d reviews", rating, count)
        case let (rating?, _):
            return String(format: "%.1f★ venue rating", rating)
        default:
            return nil
        }
    }

    var trustedVenueReviewCount: Int? {
        guard !shouldSuppressNightclubVenueReviews else { return nil }
        return rawTrustedVenueReviewCount
    }

    var venueReviewDestinationURL: URL? {
        guard !shouldSuppressNightclubVenueReviews else { return nil }
        guard shouldShowVenueReviews else { return nil }

        let directCandidates: [String?] = [
            payloadString("google_places_google_maps_uri"),
            payloadString("google_maps_uri"),
            payloadString("googleMapsUri"),
            payloadString("google_places_url"),
            payloadString("apple_maps_url"),
            payloadString("yelp_url"),
            payloadString("yelp_business_url"),
            source == .appleMaps ? sourceURL : nil,
            source == .googlePlaces ? sourceURL : nil,
            source == .yelpFusion ? sourceURL : nil
        ]

        if let directURL = directCandidates
            .compactMap(normalizedWebURL(from:))
            .compactMap(URL.init(string:))
            .first
        {
            return directURL
        }

        guard venueReviewLine != nil else { return nil }

        let queryParts: [String] = [
            venueName,
            preciseAddressLine ?? addressLine1,
            city,
            state
        ]
        .compactMap { value in
            guard let value, !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
            return value
        }

        guard !queryParts.isEmpty else { return nil }

        var components = URLComponents(string: "https://www.google.com/maps/search/")
        components?.queryItems = [
            URLQueryItem(name: "api", value: "1"),
            URLQueryItem(name: "query", value: queryParts.joined(separator: ", "))
        ]
        return components?.url
    }

    private var rawTrustedVenueReviewCount: Int? {
        let payloadCountKeys = [
            "google_places_user_rating_count",
            "google_places_userRatingCount",
            "userRatingCount",
            "ratingCount",
            "yelp_review_count",
            "yelp_reviewCount",
            "review_count",
            "reviewCount",
            "venue_reviews",
            "reviews"
        ]

        for key in payloadCountKeys {
            if let count = ExternalEventSupport.parseInt(nightlifePayload[key]), count > 0 {
                return count
            }
        }

        return nil
    }

    private var rawDisplayVenueRating: Double? {
        if let venueRating, venueRating >= 1.0, venueRating <= 5.0 {
            return venueRating
        }

        let candidates: [Any?] = [
            nightlifePayload["google_places_rating"],
            nightlifePayload["google_rating"],
            nightlifePayload["yelp_rating"],
            nightlifePayload["venue_rating"],
            nightlifePayload["rating"],
            (nightlifePayload["venue"] as? JSONDictionary)?["rating"],
            (nightlifePayload["place"] as? JSONDictionary)?["rating"]
        ]

        for candidate in candidates {
            if let rating = ExternalEventSupport.parseDouble(candidate),
               rating >= 1.0,
               rating <= 5.0 {
                return rating
            }
        }

        return nil
    }

    private var shouldSuppressNightclubVenueReviews: Bool {
        guard isLikelyNightclubVenue || hasStrongNightclubReviewSuppressionSignals else { return false }
        return (rawDisplayVenueRating ?? 0) < 4.0
    }

    private var isLikelyNightclubVenue: Bool {
        guard eventType == .partyNightlife || recordKind == .venueNight else { return false }
        if sideQuestPlaceType == .barLounge {
            return false
        }
        return ExternalEventSupport.isLikelyClubLikeNightlifeVenue(self)
    }

    private var hasStrongNightclubReviewSuppressionSignals: Bool {
        guard eventType == .partyNightlife || recordKind == .venueNight else { return false }
        if sideQuestPlaceType == .barLounge {
            return false
        }

        let signalHaystack = ExternalEventSupport.normalizeToken(
            [
                venueName,
                title,
                category,
                subcategory,
                source.rawValue,
                sourceURL,
                doorPolicyText,
                entryPolicySummary,
                exclusivityTierLabel,
                rawSourcePayload
            ]
            .compactMap { $0 }
            .joined(separator: " ")
        )

        let nightclubSignals = [
            "nightclub",
            "guest list",
            "bottle service",
            "table minimum",
            "vip table",
            "vip section",
            "hard door",
            "selective door",
            "discotech",
            "clubbable"
        ]

        return nightclubSignals.contains(where: signalHaystack.contains)
    }

    private var nightlifePayload: JSONDictionary {
        guard let data = rawSourcePayload.data(using: .utf8),
              let dictionary = try? JSONSerialization.jsonObject(with: data) as? JSONDictionary
        else {
            return [:]
        }
        return dictionary
    }

    private var nightlifePreferredURL: String? {
        let payload = nightlifePayload
        let candidates = [
            payload["discotech_url"] as? String,
            payload["clubbable_url"] as? String,
            reservationURL,
            payload["official_site_url"] as? String,
            sourceURL
        ]
        return candidates
            .compactMap(normalizedWebURL(from:))
            .first(where: { !$0.isEmpty })
    }

    var crowdAgeRangeLine: String? {
        guard eventType == .partyNightlife || recordKind == .venueNight else { return nil }

        let candidates: [String?] = [
            payloadString("discotech_description"),
            payloadString("clubbable_description"),
            payloadString("official_site_vibe"),
            payloadString("official_site_description"),
            payloadStrings("discotech_insider_tips").joined(separator: ". "),
            shortDescription,
            fullDescription
        ]

        for candidate in candidates {
            guard let candidate else { continue }
            if let explicit = explicitAgeRangeLine(from: candidate) {
                return explicit
            }
            if let inferred = inferredCrowdAgeRangeLine(from: candidate) {
                return inferred
            }
        }

        return nil
    }

    private var crowdAgeRangeBadge: String? {
        guard let crowdAgeRangeLine else { return nil }
        if let match = crowdAgeRangeLine.range(
            of: #"\b(\d{2}\s*[-–]\s*\d{2})\b"#,
            options: .regularExpression
        ) {
            let snippet = crowdAgeRangeLine[match].replacingOccurrences(of: " ", with: "")
            return "\(snippet) Crowd"
        }
        return nil
    }

    private var curatedNightlifeAboutText: String? {
        guard eventType == .partyNightlife || recordKind == .venueNight else { return nil }

        var selectedSentences: [String] = []
        if let vibeLead = bestNightlifeNarrativeSentence(
            from: [
                payloadString("clubbable_description"),
                payloadString("official_site_vibe"),
                payloadString("official_site_description"),
                payloadString("discotech_description"),
                payloadStrings("discotech_insider_tips").joined(separator: ". "),
                shortDescription,
                fullDescription
            ]
        ) {
            selectedSentences.append(vibeLead)
        }

        let factualPriority: [String?] = [
            payloadString("discotech_drinks_answer"),
            payloadString("discotech_music_answer"),
            payloadString("discotech_wait_answer"),
            payloadString("discotech_cover_answer"),
            payloadString("discotech_best_nights"),
            payloadString("discotech_open_answer"),
            payloadStrings("discotech_insider_tips").joined(separator: ". "),
            fullDescription,
            shortDescription
        ]

        for fact in factualPriority {
            guard let fact else { continue }
            for sentence in nightlifeFactSentences(from: fact) {
                guard ExternalEventSupport.hasSubstantiveNovelty(
                        sentence,
                        comparedTo: selectedSentences.map(Optional.some)
                      )
                else {
                    continue
                }
                selectedSentences.append(sentence)
                if selectedSentences.count == 6 {
                    break
                }
            }
            if selectedSentences.count == 6 {
                break
            }
        }

        if selectedSentences.isEmpty {
            let fallbackSources: [String?] = [
                payloadString("discotech_drinks_answer"),
                payloadString("discotech_music_answer"),
                payloadString("discotech_wait_answer"),
                payloadString("discotech_cover_answer"),
                payloadString("discotech_best_nights"),
                payloadString("discotech_open_answer")
            ]

            for source in fallbackSources {
                guard let source else { continue }
                for sentence in nightlifeFactSentences(from: source) {
                    guard ExternalEventSupport.hasSubstantiveNovelty(
                            sentence,
                            comparedTo: selectedSentences.map(Optional.some)
                          )
                    else {
                        continue
                    }
                    selectedSentences.append(sentence)
                    if selectedSentences.count == 4 {
                        break
                    }
                }
                if selectedSentences.count == 4 {
                    break
                }
            }
        }

        guard !selectedSentences.isEmpty else { return nil }
        return ExternalEventSupport.shortened(selectedSentences.joined(separator: " "), maxLength: 560)
    }

    private var preferredNightlifeAboutText: String? {
        if let curatedNightlifeAboutText {
            return curatedNightlifeAboutText
        }
        if let fullDescription = ExternalEventSupport.plainText(fullDescription),
           nightlifeFactSentences(from: fullDescription).count >= 2 {
            return ExternalEventSupport.shortened(fullDescription, maxLength: 520)
        }
        if let fallback = sanitizedNightlifeAboutText(fullDescription) {
            return ExternalEventSupport.shortened(fallback, maxLength: 420)
        }
        if let fallback = sanitizedNightlifeAboutText(shortDescription) {
            return ExternalEventSupport.shortened(fallback, maxLength: 320)
        }
        return nil
    }

    private var nightlifeFallbackAboutText: String? {
        let fallbackSources: [String?] = [
            payloadString("discotech_drinks_answer"),
            payloadString("discotech_music_answer"),
            payloadString("discotech_wait_answer"),
            payloadString("discotech_cover_answer"),
            payloadString("discotech_best_nights"),
            payloadString("discotech_open_answer")
        ]

        for source in fallbackSources {
            let facts = nightlifeFactSentences(from: source)
            if !facts.isEmpty {
                return ExternalEventSupport.shortened(facts.prefix(4).joined(separator: " "), maxLength: 320)
            }
            if let cleaned = sanitizedNightlifeAboutText(source),
               !cleaned.isEmpty,
               isUsefulNightlifeFactSentence(cleaned) {
                return cleaned
            }
        }
        return nil
    }

    private func nightlifeFactSentences(from text: String?) -> [String] {
        nightlifeNarrativeSentences(from: text)
            .filter {
                !nightlifeNarrativeBlocked($0)
                    && !isGenericNightlifeFactSentence($0)
                    && isUsefulNightlifeFactSentence($0)
            }
            .filter { sentence in
                let normalized = ExternalEventSupport.normalizeToken(sentence)
                let blockedTokens = [
                    "get insider information",
                    "general info",
                    "guest list vip table bookings online",
                    "vip table bookings online",
                    "request guest list",
                    "book tables directly",
                    "priority reservations",
                    "member benefits",
                    "apply make it a night",
                    "in los angeles",
                    "the place where all celebrities party",
                    "celebrity-heavy room",
                    "priority access",
                    "yourservice",
                    "bespoke membership",
                    "membership program"
                ]
                return !blockedTokens.contains(where: normalized.contains)
            }
            .map(formattedNightlifeSentence)
    }

    private func nightlifeGenderSourceText(
        preferredKeys: [String],
        fallbackTexts: [String?]
    ) -> String? {
        for key in preferredKeys {
            if let value = payloadString(key), !value.isEmpty {
                return value
            }
        }

        let payload = nightlifePayload
        let fallbackPool: [String?] = fallbackTexts + [
            payloadString("discotech_dress_code"),
            payloadString("discotech_cover_answer"),
            payloadString("discotech_wait_answer"),
            payloadString("clubbable_description"),
            payloadStrings("discotech_insider_tips").joined(separator: ". ")
        ]

        return fallbackPool.compactMap { $0 }.first(where: { !$0.isEmpty })
    }

    private func payloadString(_ key: String) -> String? {
        if let value = nightlifePayload[key] as? String {
            return ExternalEventSupport.plainText(value)
        }
        return nil
    }

    private func payloadStrings(_ key: String) -> [String] {
        if let values = nightlifePayload[key] as? [String] {
            return values.compactMap { ExternalEventSupport.plainText($0) }
        }
        return []
    }

    var galleryImageURLs: [String] {
        if eventType == .partyNightlife || recordKind == .venueNight {
            let mergedImages = ExternalEventSupport.preferredNightlifeImageURLs(
                primary: imageURL,
                payload: rawSourcePayload,
                limit: 3
            )
            let fallbackImages = dedupedPreferredGalleryImages(payloadImageURLCandidates, limit: 3)
            let combined = dedupedPreferredGalleryImages(mergedImages + fallbackImages, limit: 3)
            return combined
        }

        let officialSiteImages: [String] = hasTrustedOfficialSitePayload
            ? (payloadStrings("official_site_image_gallery") + [payloadString("official_site_image")].compactMap { $0 })
            : []
        let suspiciousNightlifeBleed = hasSuspiciousNightlifeReservationBleed
        let sharedEventImages = ExternalEventSupport.preferredImageURLs(for: self, limit: 6)
            .filter { !looksLikeNightlifeAggregatorMediaURL($0) }
        let appleMapsImages = payloadStrings("apple_maps_image_gallery")
            + [payloadString("apple_maps_file_image")].compactMap { $0 }
        let prioritized = [
            sharedEventImages,
            appleMapsImages,
            suspiciousNightlifeBleed ? [] : officialSiteImages
        ]
        .flatMap { $0 }

        let fallbackImages = suspiciousNightlifeBleed
            ? sharedEventImages
            : dedupedPreferredGalleryImages(sharedEventImages + officialSiteImages + appleMapsImages, limit: 6)
        let preferredImages = dedupedPreferredGalleryImages(prioritized, limit: 3)

        if !preferredImages.isEmpty {
            return preferredImages
        }
        return dedupedPreferredGalleryImages(fallbackImages, limit: 3)
    }

    var primaryDisplayImageURL: String? {
        galleryImageURLs.first
    }

    private func looksLikeNightlifeAggregatorMediaURL(_ rawURL: String) -> Bool {
        let normalized = ExternalEventSupport.normalizeToken(rawURL)
        let blockedHosts = [
            "discotech",
            "clubbable",
            "tablelist",
            "hwood",
            "hwoodgroup",
            "guestlist",
            "vipnightlife"
        ]
        return blockedHosts.contains(where: normalized.contains)
    }

    private var hasSuspiciousNightlifeReservationBleed: Bool {
        guard eventType != .partyNightlife, recordKind != .venueNight else { return false }
        guard ticketURL != nil else { return false }
        guard let reservationURL else { return false }
        return looksLikeNightlifeAggregatorMediaURL(reservationURL)
    }

    private var nightlifeAddressLine1: String? {
        let candidates = [
            addressLine1,
            payloadString("apple_maps_address_line_1"),
            payloadString("clubbable_address_line_1"),
            payloadString("official_site_address"),
            payloadString("google_places_address"),
            payloadString("yelp_address_line_1")
        ]
        let cleaned = candidates
            .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        return cleaned.first(where: {
            !ExternalEventSupport.isWeakAddressLine($0, city: nightlifeCityValue, state: nightlifeStateValue)
        }) ?? cleaned.first
    }

    private var nightlifeAddressLine2: String? {
        let candidates = [
            addressLine2,
            payloadString("google_places_address_line_2"),
            payloadString("yelp_address_line_2")
        ]
        return candidates
            .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .first(where: { !$0.isEmpty })
    }

    private var nightlifeCityValue: String? {
        let candidates = [
            city,
            payloadString("apple_maps_city"),
            payloadString("clubbable_city"),
            payloadString("official_site_city"),
            payloadString("google_places_city"),
            payloadString("yelp_city")
        ]
        return candidates
            .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .first(where: { !$0.isEmpty })
    }

    private var nightlifeStateValue: String? {
        let candidates = [
            state,
            payloadString("apple_maps_state"),
            payloadString("clubbable_state"),
            payloadString("official_site_state"),
            payloadString("google_places_state"),
            payloadString("yelp_state")
        ]
        return candidates
            .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .first(where: { !$0.isEmpty })
            .map { ExternalEventSupport.normalizeStateToken($0).uppercased() }
    }

    private var nightlifePostalCodeValue: String? {
        let candidates = [
            postalCode,
            payloadString("apple_maps_postal_code"),
            payloadString("clubbable_postal_code"),
            payloadString("official_site_postal_code"),
            payloadString("google_places_postal_code"),
            payloadString("yelp_postal_code")
        ]
        return candidates
            .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .first(where: { !$0.isEmpty })
    }

    private var preciseAddressLine: String? {
        let explicitFullAddress = [
            payloadString("apple_maps_full_address"),
            payloadString("clubbable_full_address"),
            payloadString("google_places_address"),
            payloadString("yelp_full_address")
        ]
            .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .first(where: {
                !$0.isEmpty && !ExternalEventSupport.isWeakAddressLine($0, city: nightlifeCityValue, state: nightlifeStateValue)
            })
        let streetBits = [nightlifeAddressLine1, nightlifeAddressLine2].compactMap { value -> String? in
            guard let value, !value.isEmpty else { return nil }
            return value
        }
        let localityLine = [
            nightlifeCityValue,
            nightlifeStateValue
        ]
        .compactMap { value in
            guard let value, !value.isEmpty else { return nil }
            return value
        }
        .joined(separator: ", ")
        let localityWithPostal = [localityLine.isEmpty ? nil : localityLine, nightlifePostalCodeValue]
            .compactMap { $0 }
            .joined(separator: localityLine.isEmpty ? "" : " ")

        let parts = streetBits + [localityWithPostal].filter { !$0.isEmpty }
        let assembled = parts.joined(separator: ", ")
        if let explicitFullAddress,
           shouldPreferExplicitAddress(explicitFullAddress, over: assembled) {
            return explicitFullAddress
        }
        if parts.isEmpty {
            return explicitFullAddress
        }
        if ExternalEventSupport.isWeakAddressLine(assembled, city: nightlifeCityValue, state: nightlifeStateValue) {
            return explicitFullAddress
        }
        return assembled
    }

    private func shouldPreferExplicitAddress(_ candidate: String, over fallback: String) -> Bool {
        let normalizedCandidate = ExternalEventSupport.normalizeToken(candidate)
        let normalizedFallback = ExternalEventSupport.normalizeToken(fallback)
        let candidateHasStreetNumber = candidate.rangeOfCharacter(from: .decimalDigits) != nil
        let fallbackHasStreetNumber = fallback.rangeOfCharacter(from: .decimalDigits) != nil
        let candidateCommaCount = candidate.filter { $0 == "," }.count
        let fallbackCommaCount = fallback.filter { $0 == "," }.count

        if candidateHasStreetNumber && !fallbackHasStreetNumber {
            return true
        }
        if candidateHasStreetNumber && candidateCommaCount >= 1 {
            return true
        }
        if candidateCommaCount >= fallbackCommaCount + 1 {
            return true
        }
        if normalizedFallback.isEmpty {
            return !normalizedCandidate.isEmpty
        }
        return normalizedCandidate.count > normalizedFallback.count + 8
    }

    private var payloadImageURLCandidates: [String] {
        var urls: [String] = []
        urls.append(contentsOf: imageURLs(from: nightlifePayload["images"]))
        urls.append(contentsOf: imageURLs(from: nightlifePayload["gallery_images"]))

        if let listingItem = nightlifePayload["listing_item"] as? JSONDictionary {
            urls.append(contentsOf: imageURLs(from: listingItem["images"]))
            urls.append(contentsOf: imageURLs(from: listingItem["image"]))
            urls.append(contentsOf: imageURLs(from: listingItem["imageURL"]))
        }

        if let socialEvent = nightlifePayload["social_event"] as? JSONDictionary {
            urls.append(contentsOf: imageURLs(from: socialEvent["image"]))
        }

        return urls
    }

    private func dedupedPreferredGalleryImages(_ candidates: [String], limit: Int) -> [String] {
        let cleaned = candidates
            .compactMap { ExternalEventSupport.normalizedImageURLString($0) }
            .filter { ExternalEventSupport.imageMeetsMinimumResolution($0) }
            .filter { candidate in
                let normalized = ExternalEventSupport.normalizeToken(candidate)
                return !normalized.contains("logo")
                    && !normalized.contains("icon")
                    && !normalized.contains("avatar")
                    && !normalized.contains("placeholder")
            }

        var bestByGroup: [String: (url: String, score: Int)] = [:]
        var firstSeenOrder: [String] = []

        for candidate in cleaned {
            let group = canonicalImageGroupKey(for: candidate)
            let score = nightlifeImageQualityScore(candidate)
            if bestByGroup[group] == nil {
                firstSeenOrder.append(group)
                bestByGroup[group] = (candidate, score)
                continue
            }
            if let existing = bestByGroup[group], score > existing.score {
                bestByGroup[group] = (candidate, score)
            }
        }

        return firstSeenOrder
            .compactMap { bestByGroup[$0] }
            .sorted { lhs, rhs in
                if lhs.score == rhs.score { return lhs.url < rhs.url }
                return lhs.score > rhs.score
            }
            .map(\.url)
            .prefix(limit)
            .map { $0 }
    }

    private func canonicalImageGroupKey(for rawURL: String) -> String {
        guard let components = URLComponents(string: rawURL) else {
            return ExternalEventSupport.normalizeToken(rawURL)
        }
        let host = components.host?.lowercased() ?? ""
        let path = components.path.lowercased()
        let filename = URL(fileURLWithPath: path).lastPathComponent
            .replacingOccurrences(
                of: #"(?:_|-)(?:source|tablet_landscape(?:_large)?_16_9|tablet_landscape_3_2|retina_landscape_16_9|retina_portrait_16_9|retina_portrait_3_2|event_detail_page_16_9|recomendation_16_9|recommendation_16_9|artist_page_3_2|custom)(?=\.)"#,
                with: "",
                options: .regularExpression
            )
            .replacingOccurrences(of: #"(?:-|_)\d{2,4}x\d{2,4}(?=\.)"#, with: "", options: .regularExpression)
            .replacingOccurrences(of: #"(?:-|_)(?:thumb|thumbnail|small|preview|lowres|low|medium)(?=\.)"#, with: "", options: .regularExpression)
            .replacingOccurrences(of: #"-scaled(?=\.)"#, with: "", options: .regularExpression)
            .replacingOccurrences(of: #"(?:-|_)(?:\d{2,4}|thumb|thumbnail|small|preview|lowres|low|medium|copy|final|hero|main|cover|og|hd|full)$"#, with: "", options: .regularExpression)
        let stem = filename
            .replacingOccurrences(of: #"\.[a-z0-9]+$"#, with: "", options: .regularExpression)
            .replacingOccurrences(of: #"(?:-|_)(?:copy|final|hero|main|cover|og|hd|full)$"#, with: "", options: .regularExpression)
        let dirname = URL(fileURLWithPath: path).deletingLastPathComponent().lastPathComponent
            .replacingOccurrences(of: #"(?:thumbs?|thumbnails?|preview|small|medium|large)$"#, with: "", options: .regularExpression)
        let compactStem = stem
            .replacingOccurrences(of: #"(?:-|_)?(?:\d{2,4}|copy|final|hero|main|cover|og|hd|full)$"#, with: "", options: .regularExpression)
            .trimmingCharacters(in: CharacterSet(charactersIn: "-_ "))
        if compactStem.count >= 8 {
            return compactStem
        }
        return "\(host)|\(dirname)|\(compactStem)"
    }

    private func nightlifeImageQualityScore(_ rawURL: String) -> Int {
        let normalized = ExternalEventSupport.normalizeToken(rawURL)
        var score = 0

        if rawURL.hasPrefix("/") || normalized.contains("apple venue media") || normalized.contains("lookaround") {
            score += 40
        }
        if normalized.contains("apple maps") { score += 30 }
        if normalized.contains("official") { score += 24 }
        if normalized.contains("discotech") { score += 22 }
        if normalized.contains("clubbable") { score += 20 }
        if normalized.contains(".webp") || normalized.contains(".jpg") || normalized.contains(".jpeg") {
            score += 4
        }

        let lowQualityTokens = [
            "thumb", "thumbnail", "preview", "small", "tiny", "icon", "logo",
            "avatar", "placeholder", "resize=", "_200", "_300", "-150x150",
            "-300x300", "w=120", "w=160", "w=200", "w=300", "quality=40",
            "quality=50", "/thumb/", "/thumbnail/", "/preview/"
        ]
        if lowQualityTokens.contains(where: normalized.contains) { score -= 40 }

        if let dimensions = rawURL.range(of: #"(\d{3,4})x(\d{3,4})"#, options: .regularExpression) {
            let snippet = rawURL[dimensions]
            let numbers = snippet.split(whereSeparator: { !$0.isNumber }).compactMap { Int($0) }
            if let width = numbers.first, let height = numbers.last {
                score += min((width * height) / 200_000, 24)
            }
        }

        return score
    }

    private func imageURLs(from value: Any?) -> [String] {
        if let string = value as? String {
            let cleaned = ExternalEventSupport.normalizedImageURLString(string) ?? ""
            return cleaned.isEmpty ? [] : [cleaned]
        }

        if let dictionaries = value as? [[String: Any]] {
            return ExternalEventSupport.preferredImageURLs(from: dictionaries, limit: 3)
        }

        if let array = value as? [Any] {
            return array.flatMap { imageURLs(from: $0) }
        }

        if let dictionary = value as? JSONDictionary {
            if let directURL = dictionary["url"] as? String {
                return imageURLs(from: directURL)
            }
            let candidateKeys = ["image", "images", "croppedOriginalImageUrl"]
            return candidateKeys.flatMap { imageURLs(from: dictionary[$0]) }
        }

        return []
    }

    private var hasTrustedOfficialSitePayload: Bool {
        guard let url = payloadString("official_site_url"),
              let host = URL(string: url)?.host?.lowercased()
        else {
            return false
        }

        let blockedHosts = [
            "discotech.me",
            "www.discotech.me",
            "clubbable.com",
            "www.clubbable.com",
            "eventbrite.com",
            "www.eventbrite.com",
            "ticketmaster.com",
            "www.ticketmaster.com",
            "seatgeek.com",
            "www.seatgeek.com",
            "stubhub.com",
            "www.stubhub.com",
            "maps.apple.com",
            "google.com",
            "www.google.com",
            "yelp.com",
            "www.yelp.com",
            "sevenrooms.com",
            "www.sevenrooms.com",
            "resy.com",
            "www.resy.com",
            "opentable.com",
            "www.opentable.com",
            "tablelist.com",
            "www.tablelist.com"
        ]
        return !blockedHosts.contains(host)
    }

    private func nightlifeNarrativeSentences(from text: String?) -> [String] {
        guard let plain = ExternalEventSupport.plainText(text), !plain.isEmpty else { return [] }

        return plain
            .replacingOccurrences(of: "\n", with: " ")
            .components(separatedBy: CharacterSet(charactersIn: ".!?"))
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { sentence in
                sentence.count >= 28
                    && sentence.count <= 220
                    && !sentence.contains("  ")
            }
            .map { sentence in
                formattedNightlifeSentence(
                    ExternalEventSupport.shortened(sentence, maxLength: 180) ?? sentence
                )
            }
    }

    private func bestNightlifeNarrativeSentence(
        from sources: [String?],
        excluding existing: [String] = []
    ) -> String? {
        let candidates = sources
            .compactMap { $0 }
            .flatMap(nightlifeNarrativeSentences)
            .filter { !nightlifeNarrativeBlocked($0) && !isGenericNightlifeFactSentence($0) }
            .filter {
                ExternalEventSupport.hasSubstantiveNovelty(
                    $0,
                    comparedTo: existing.map(Optional.some)
                )
            }

        let ranked = candidates.sorted { lhs, rhs in
            nightlifeNarrativeScore(lhs) > nightlifeNarrativeScore(rhs)
        }
        return ranked.first
    }

    private func nightlifeNarrativeScore(_ sentence: String) -> Int {
        let normalized = ExternalEventSupport.normalizeToken(sentence)
        var score = 0

        let descriptiveTokens = [
            "fantasy", "surreal", "storybook", "upscale", "luxury", "intimate", "dark",
            "cocktail", "rooftop", "dance", "crowd", "music", "hip hop", "edm", "top 40",
            "hollywood", "celebrit", "supper club", "scene", "lounge", "vibe"
        ]
        if descriptiveTokens.contains(where: normalized.contains) { score += 8 }

        if normalized.contains("says") || sentence.contains("“") || sentence.contains("\"") {
            score -= 5
        }
        if normalized.contains("h wood group") { score -= 2 }
        if normalized.contains("reserve a spot via our online bookings") { score -= 6 }
        score += min(sentence.count / 40, 4)
        return score
    }

    private func formattedNightlifeSentence(_ sentence: String) -> String {
        let trimmed = sentence.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let last = trimmed.last else { return trimmed }
        if ".!?".contains(last) {
            return trimmed
        }
        return trimmed + "."
    }

    private func nightlifeNarrativeBlocked(_ sentence: String) -> Bool {
        let normalized = ExternalEventSupport.normalizeToken(sentence)
        let blockedTokens = [
            "get insider information",
            "general info",
            "h wood rolodex",
            "listed by h wood rolodex",
            "recognized by h wood rolodex",
            "bespoke membership",
            "membership program",
            "member benefits",
            "priority reservations",
            "priority access",
            "yourservice",
            "apply make it a night",
            "$2500 annually",
            "photos and info",
            "best promoters here",
            "vip table bookings online",
            "guest list vip table bookings online",
            "request guest list",
            "book table",
            "book tables directly",
            "download the app",
            "app store",
            "upcoming events at",
            "upcoming events and book tables",
            "current list of events",
            "avoid problems at the door",
            "ultimate guide",
            "contact us",
            "whatsapp",
            "login",
            "cookie",
            "javascript",
            "placeholder png",
            "text gold",
            "sprite",
            "clubbable",
            "discotech",
            "all the best vip nightclubs in london",
            "all the promoters",
            "club managers owners"
        ]
        guard !blockedTokens.contains(where: normalized.contains) else {
            return true
        }
        return false
    }

    private func isGenericNightlifeFactSentence(_ sentence: String) -> Bool {
        let normalized = ExternalEventSupport.normalizeToken(sentence)
        let blockedTokens = [
            "all nights are good",
            "for more upcoming event options",
            "you can check out",
            "you can download",
            "visit the website",
            "current list of events",
            "upcoming events and book tables",
            "upcoming events at",
            "book tables directly",
            "reserve a spot via our online bookings"
        ]
        return blockedTokens.contains(where: normalized.contains)
    }

    private func isUsefulNightlifeFactSentence(_ sentence: String) -> Bool {
        let normalized = ExternalEventSupport.normalizeToken(sentence)
        let factTokens = [
            "drink", "cocktail", "bottle", "table", "minimum", "cover", "guest list",
            "door", "entry", "general admission", "music", "hip hop", "r b", "r&b",
            "edm", "house", "latin", "reggaeton", "open", "close", "hours", "wait",
            "line", "arrive", "best night", "friday", "saturday", "thursday",
            "21", "18", "ladies", "girls", "women", "guys", "men", "free", "ratio",
            "dress code", "heels", "sneakers", "sportswear", "upscale", "rooftop"
        ]
        return factTokens.contains(where: normalized.contains)
    }

    private func explicitAgeRangeLine(from text: String) -> String? {
        let patterns = [
            #"\bages?\s*(\d{2})\s*(?:-|–|to)\s*(\d{2})\b"#,
            #"\b(\d{2})\s*(?:-|–|to)\s*(\d{2})\s*(?:years?\s*old|yo)?\b"#
        ]

        for pattern in patterns {
            let matches = allRegexMatches(in: text, pattern: pattern, groupCount: 2, options: [.caseInsensitive])
            for match in matches {
                guard match.count == 2,
                      let low = Int(match[0]),
                      let high = Int(match[1]),
                      low >= 18,
                      high > low,
                      high <= 45
                else {
                    continue
                }
                return "Popular among ages \(low)-\(high)."
            }
        }

        return nil
    }

    private func inferredCrowdAgeRangeLine(from text: String) -> String? {
        let normalized = ExternalEventSupport.normalizeToken(text)
        guard !normalized.isEmpty else { return nil }

        let mappings: [(tokens: [String], line: String)] = [
            (["college", "students", "student crowd", "usc", "ucla"], "Popular among ages 21-25."),
            (["early 20", "young crowd", "younger crowd", "twenty someth", "twentysometh"], "Popular among ages 21-28."),
            (["young professionals", "mid 20", "late 20", "twenties"], "Popular among ages 24-30."),
            (["mature crowd", "older crowd", "thirty someth", "30s crowd", "late 20s and 30s"], "Popular among ages 27-35.")
        ]

        for mapping in mappings where mapping.tokens.contains(where: normalized.contains) {
            return mapping.line
        }

        return nil
    }

    private func normalizedWebURL(from rawValue: String?) -> String? {
        guard let rawValue else { return nil }
        let trimmed = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        if let url = URL(string: trimmed), url.scheme != nil, url.host != nil {
            return url.absoluteString
        }
        if trimmed.hasPrefix("www.") || trimmed.contains(".com") || trimmed.contains(".net") || trimmed.contains(".org") {
            let candidate = "https://" + trimmed.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
            if let url = URL(string: candidate), url.host != nil {
                return url.absoluteString
            }
        }
        return nil
    }

    private func sanitizedNightlifeEntryText(_ text: String?) -> String? {
        guard let plain = ExternalEventSupport.plainText(text), !plain.isEmpty else { return nil }
        let cleaned = plain
            .replacingOccurrences(of: #"(?i)\bWomen:\s*[^.]+\.?\s*"#, with: "", options: .regularExpression)
            .replacingOccurrences(of: #"(?i)\bMen:\s*[^.]+\.?\s*"#, with: "", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let normalized = ExternalEventSupport.normalizeToken(cleaned)
        guard !normalized.contains("highlighted in discotech s market guide"),
              !normalized.contains("listed by h wood rolodex"),
              !normalized.contains("recognized by h wood rolodex"),
              !normalized.contains("guest list vip table bookings online"),
              !normalized.contains("vip table bookings online"),
              !normalized.contains("request guest list")
        else {
            return nil
        }
        return cleaned.isEmpty ? nil : cleaned
    }

    private func sanitizedNightlifeDoorText(_ text: String?) -> String? {
        guard let plain = ExternalEventSupport.plainText(text), !plain.isEmpty else { return nil }
        let blockedTokens = [
            "guest list vip table bookings online",
            "vip table bookings online",
            "guest list and vip table bookings",
            "the place where all celebrities party",
            "guest list and table booking structure",
            "table booking structure",
            "guest list friendly",
            "guest list is available",
            "celebrity heavy room",
            "exclusive nightlife room",
            "reservation required",
            "in los angeles",
            "get insider information",
            "general info",
            "all the best vip nightclubs in london",
            "all the promoters",
            "club managers owners",
            "listed by h wood rolodex",
            "recognized by h wood rolodex",
            "h wood rolodex"
        ]
        let usefulTokens = [
            "hard door", "strict", "selective", "dress code", "general admission",
            "bottle service only", "does not have general admission", "cover", "table minimum",
            "minimum spend", "dress to impress", "tables only"
        ]
        let sentences = plain
            .replacingOccurrences(of: "\n", with: " ")
            .components(separatedBy: CharacterSet(charactersIn: ".!?;"))
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        let kept = sentences.filter { sentence in
            let normalized = ExternalEventSupport.normalizeToken(sentence)
            guard !blockedTokens.contains(where: normalized.contains) else { return false }
            return usefulTokens.contains(where: normalized.contains)
        }

        guard !kept.isEmpty else { return nil }
        return ExternalEventSupport.shortened(
            kept.prefix(2).map(formattedNightlifeSentence).joined(separator: " "),
            maxLength: 180
        )
    }

    private func sanitizedNightlifeGenderText(_ text: String?, genderTokens: [String]) -> String? {
        guard let plain = ExternalEventSupport.plainText(text), !plain.isEmpty else { return nil }
        let entryTokens = Set(["guest", "list", "table", "bottle", "entry", "free", "ratio", "cover", "door", "admission", "dress", "shirt", "heels", "shoes", "sportswear", "sneakers", "attire"])
        let sentences = plain
            .replacingOccurrences(of: "\n", with: " ")
            .components(separatedBy: CharacterSet(charactersIn: ".!?;"))
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        let bestSentence = sentences.first { sentence in
            let normalized = ExternalEventSupport.normalizeToken(sentence)
            let tokens = Set(normalized.split(separator: " ").map(String.init))
            return !tokens.intersection(Set(genderTokens)).isEmpty
                && !tokens.intersection(entryTokens).isEmpty
                && !normalized.contains("h wood rolodex")
                && !normalized.contains("bespoke membership")
                && !normalized.contains("membership program")
                && !normalized.contains("app store")
                && !normalized.contains("upcoming events")
                && !normalized.contains("request guest list")
                && sentence.count <= 170
        }

        guard let bestSentence else { return nil }
        return ExternalEventSupport.shortened(bestSentence, maxLength: 160)
    }

    private func sanitizedNightlifeAboutText(_ text: String?) -> String? {
        guard let plain = ExternalEventSupport.plainText(text), !plain.isEmpty else { return nil }
        let sentences = plain
            .replacingOccurrences(of: "\n", with: " ")
            .components(separatedBy: CharacterSet(charactersIn: ".!?"))
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { $0.count >= 18 }

        let blockedTokens = [
            "h wood rolodex",
            "listed by h wood rolodex",
            "recognized by h wood rolodex",
            "bespoke membership",
            "membership program",
            "member benefits",
            "priority reservations",
            "priority access",
            "yourservice",
            "apply make it a night",
            "$2500 annually",
            "photos and info",
            "best promoters here",
            "vip table bookings online",
            "guest list vip table bookings online",
            "request guest list",
            "the place where all celebrities party",
            "celebrity heavy room",
            "download the app",
            "app store",
            "upcoming events at",
            "all the best vip nightclubs in london",
            "all the promoters",
            "club managers owners"
        ]

        let filtered = sentences.filter { sentence in
            let normalized = ExternalEventSupport.normalizeToken(sentence)
            return !blockedTokens.contains(where: normalized.contains)
                && isUsefulNightlifeFactSentence(sentence)
        }

        guard !filtered.isEmpty else { return nil }
        let joined = filtered.prefix(2).joined(separator: ". ") + "."
        return ExternalEventSupport.shortened(joined, maxLength: 260)
    }

    var cityStateLine: String? {
        switch (city, state) {
        case let (city?, state?) where !city.isEmpty && !state.isEmpty:
            return "\(city), \(state)"
        case let (city?, _) where !city.isEmpty:
            return city
        case let (_, state?) where !state.isEmpty:
            return state
        default:
            return nil
        }
    }

    var statusDisplayText: String {
        if let urgencyDisplayText {
            return urgencyDisplayText
        }

        switch availabilityStatus {
        case .openRegistration: return "Open Registration"
        case .onsale: return "On Sale"
        case .available: return "Available"
        case .registrationClosed: return "Registration Closed"
        case .soldOut: return "Sold Out"
        case .cancelled: return "Canceled"
        case .postponed: return "Postponed"
        case .rescheduled: return "Rescheduled"
        case .ended: return "Ended"
        case .unknown:
            switch status {
            case .scheduled: return "Scheduled"
            case .onsale: return "On Sale"
            case .openRegistration: return "Open Registration"
            case .soldOut: return "Sold Out"
            case .cancelled: return "Canceled"
            case .postponed: return "Postponed"
            case .rescheduled: return "Rescheduled"
            case .ended: return "Ended"
            case .unknown: return "Upcoming"
            }
        }
    }

    var statusDisplayColor: Color {
        switch availabilityStatus {
        case .openRegistration, .onsale, .available: return .green
        case .registrationClosed, .soldOut: return .orange
        case .cancelled, .ended: return .red
        case .postponed, .rescheduled: return .yellow
        case .unknown:
            switch status {
            case .onsale, .openRegistration, .scheduled: return .green
            case .soldOut: return .orange
            case .cancelled, .ended: return .red
            case .postponed, .rescheduled: return .yellow
            case .unknown: return .white.opacity(0.9)
            }
        }
    }

    private var urgencyDisplayText: String? {
        switch urgencyBadge {
        case .some(.almostSoldOut):
            return "Almost Sold Out"
        case .some(.sellingFast):
            return "Selling Fast"
        case .some(.registrationClosingSoon):
            return "Closing Soon"
        case .none:
            return nil
        }
    }

    var priceLine: String? {
        if let priceMin, let priceMax {
            if priceMin == 0, priceMax == 0 {
                return "Free"
            }
            if abs(priceMin - priceMax) < 0.01 {
                return "\(formatCurrency(priceMin))"
            }
            return "\(formatCurrency(priceMin)) - \(formatCurrency(priceMax))"
        }
        if let priceMin {
            return priceMin == 0 ? "Free" : formatCurrency(priceMin)
        }
        return nil
    }

    private func displayDate(dateStyle: String) -> String {
        if let startAtUTC {
            if isImplicitMidnightLocalTime,
               let startLocalDate = normalizedLocalDateString(from: startLocal) {
                return formattedDateOnly(from: startLocalDate, dateFormat: dateStyle)
            }
            let formatter = DateFormatter()
            formatter.locale = Locale(identifier: "en_US_POSIX")
            formatter.dateFormat = dateStyle
            formatter.timeZone = timezone.flatMap(TimeZone.init(identifier:)) ?? .current
            return formatter.string(from: startAtUTC)
        }
        if let startLocal, !startLocal.isEmpty {
            if isImplicitMidnightLocalTime,
               let startLocalDate = normalizedLocalDateString(from: startLocal) {
                return formattedDateOnly(from: startLocalDate, dateFormat: dateStyle)
            }
            if let parsedDate = parsedLocalDate(from: startLocal) {
                let formatter = DateFormatter()
                formatter.locale = Locale(identifier: "en_US_POSIX")
                formatter.dateFormat = dateStyle
                formatter.timeZone = timezone.flatMap(TimeZone.init(identifier:)) ?? .current
                return formatter.string(from: parsedDate)
            }
            return startLocal.replacingOccurrences(of: "T", with: " • ")
        }
        return "Time TBA"
    }

    private var venueNightScheduleLine: String? {
        guard recordKind == .venueNight else { return nil }
        for candidate in venueNightScheduleCandidates {
            if let nightlyLine = condensedVenueNightHours(from: candidate) {
                return nightlyLine
            }
        }
        return nil
    }

    private func structuredVenueNightScheduleLine(shortStyle: Bool) -> String? {
        guard recordKind == .venueNight,
              let startLocal,
              let startDate = parsedLocalDate(from: startLocal)
        else {
            return nil
        }

        let zone = timezone.flatMap(TimeZone.init(identifier:)) ?? .current
        let startFormatter = DateFormatter()
        startFormatter.locale = Locale(identifier: "en_US_POSIX")
        startFormatter.timeZone = zone
        startFormatter.dateFormat = shortStyle ? "EEE, MMM d • h:mm a" : "EEEE, MMM d • h:mm a"

        var line = startFormatter.string(from: startDate)

        if let endLocal,
           let endDate = parsedLocalDate(from: endLocal) {
            let endFormatter = DateFormatter()
            endFormatter.locale = Locale(identifier: "en_US_POSIX")
            endFormatter.timeZone = zone
            let sameDay = Calendar.current.isDate(startDate, inSameDayAs: endDate)
            endFormatter.dateFormat = sameDay
                ? "h:mm a"
                : (shortStyle ? "EEE h:mm a" : "EEEE h:mm a")
            line += " - \(endFormatter.string(from: endDate))"
        }

        if !shortStyle, let timezone {
            line += " \(timezoneAbbreviation(for: timezone))"
        }

        return line
    }

    private var exclusivityLabel: String? {
        guard eventType == .partyNightlife || recordKind == .venueNight else { return nil }
        let display = exclusivityTierDisplay ?? ""
        if let left = display.components(separatedBy: "•").first?.trimmingCharacters(in: .whitespacesAndNewlines),
           !left.isEmpty {
            return left
        }
        return nil
    }

    private var condensedDoorPolicy: String? {
        guard let doorPolicyText, !doorPolicyText.isEmpty else { return nil }
        let normalized = ExternalEventSupport.normalizeToken(doorPolicyText)
        if normalized.contains("bottle service only") {
            return "Tables Only"
        }
        if normalized.contains("guest list") {
            return "Guest List"
        }
        if normalized.contains("hard door") {
            return "Hard Door"
        }
        if normalized.contains("reservation") {
            return "Reservation Required"
        }
        if normalized.contains("door policy") {
            return "Door Policy"
        }
        return nil
    }

    private func uniqueOrdered(_ parts: [String]) -> [String] {
        var seen = Set<String>()
        var output: [String] = []
        for part in parts {
            let key = ExternalEventSupport.normalizeToken(part)
            guard !key.isEmpty, !seen.contains(key) else { continue }
            seen.insert(key)
            output.append(part)
        }
        return output
    }

    private func condensedVenueNightHours(from text: String) -> String? {
        guard isLikelyVenueNightScheduleText(text) else { return nil }
        if let extracted = extractedVenueNightScheduleSnippet(from: text) {
            return extracted
        }
        return nil
    }

    private func extractedVenueNightScheduleSnippet(from text: String) -> String? {
        let candidates = text
            .replacingOccurrences(of: "\n", with: " | ")
            .components(separatedBy: "|")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        let patterns = [
            #"(?i)\b(?:mon|tue|wed|thu|fri|sat|sun)[a-z]*\b[^.!?\n]{0,80}\b\d{1,2}(?::\d{2})?\s*(?:am|pm)\s*(?:[–-]|to)\s*\d{1,2}(?::\d{2})?\s*(?:am|pm)\b"#,
            #"(?i)\b(?:today|tonight|daily|nightly)\b[^.!?\n]{0,60}\b\d{1,2}(?::\d{2})?\s*(?:am|pm)\s*(?:[–-]|to)\s*\d{1,2}(?::\d{2})?\s*(?:am|pm)\b"#,
            #"(?i)\b(?:open(?:s)?|from)\s+\d{1,2}(?::\d{2})?\s*(?:am|pm)\s*(?:[–-]|to|until|till)\s*\d{1,2}(?::\d{2})?\s*(?:am|pm)\b"#,
            #"(?i)\b\d{1,2}(?::\d{2})?\s*(?:am|pm)\s*(?:[–-]|to)\s*\d{1,2}(?::\d{2})?\s*(?:am|pm)\b"#,
            #"(?i)\b(?:open(?:s)?(?:\s+at)?|until|till)\s+\d{1,2}(?::\d{2})?\s*(?:am|pm)\b"#
        ]

        for candidate in candidates {
            for pattern in patterns {
                if let range = candidate.range(of: pattern, options: .regularExpression) {
                    return candidate[range].trimmingCharacters(in: .whitespacesAndNewlines)
                }
            }
        }

        let sentences = text
            .replacingOccurrences(of: "\n", with: " ")
            .components(separatedBy: CharacterSet(charactersIn: ".!?"))
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        for sentence in sentences {
            for pattern in patterns {
                if let range = sentence.range(of: pattern, options: .regularExpression) {
                    return sentence[range].trimmingCharacters(in: .whitespacesAndNewlines)
                }
            }
        }

        return nil
    }

    private var venueNightScheduleCandidates: [String] {
        [
            payloadString("clubbable_schedule_display"),
            payloadString("clubbable_time_range"),
            payloadString("discotech_open_answer"),
            payloadString("apple_maps_hours_text"),
            payloadString("apple_maps_schedule_text"),
            payloadString("official_site_hours"),
            openingHoursText,
        ]
        .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
        .filter { !$0.isEmpty }
    }

    private func venueNightBestNightsLine(shortStyle: Bool) -> String? {
        guard recordKind == .venueNight else { return nil }
        let bestNights = [
            payloadString("discotech_best_nights"),
            payloadString("clubbable_best_nights")
        ]
        .compactMap { ExternalEventSupport.plainText($0)?.trimmingCharacters(in: .whitespacesAndNewlines) }
        .first { !$0.isEmpty }

        guard let bestNights, !bestNights.isEmpty else { return nil }
        let normalized = ExternalEventSupport.normalizeToken(bestNights)
        if normalized.contains("open every day") || normalized.contains("every day") || normalized.contains("open daily") {
            return shortStyle ? "Open daily" : "Open daily"
        }

        let days = extractedWeekdays(from: bestNights)
        guard !days.isEmpty else { return nil }
        let joined = shortStyle
            ? days.map { $0.shortLabel }.joined(separator: " / ")
            : days.map { $0.longLabel }.joined(separator: " / ")
        return shortStyle ? "Best on \(joined)" : "Best on \(joined)"
    }

    private struct VenueNightWeekday: Hashable {
        let shortLabel: String
        let longLabel: String
    }

    private func extractedWeekdays(from text: String) -> [VenueNightWeekday] {
        let mappings: [(pattern: String, short: String, long: String)] = [
            (#"(?i)\bmonday(s)?\b|\bmon\b"#, "Mon", "Mondays"),
            (#"(?i)\btuesday(s)?\b|\btue(s)?\b"#, "Tue", "Tuesdays"),
            (#"(?i)\bwednesday(s)?\b|\bwed\b"#, "Wed", "Wednesdays"),
            (#"(?i)\bthursday(s)?\b|\bthu(rs)?\b"#, "Thu", "Thursdays"),
            (#"(?i)\bfriday(s)?\b|\bfri\b"#, "Fri", "Fridays"),
            (#"(?i)\bsaturday(s)?\b|\bsat\b"#, "Sat", "Saturdays"),
            (#"(?i)\bsunday(s)?\b|\bsun\b"#, "Sun", "Sundays")
        ]

        var results: [VenueNightWeekday] = []
        for mapping in mappings {
            if text.range(of: mapping.pattern, options: .regularExpression) != nil {
                results.append(VenueNightWeekday(shortLabel: mapping.short, longLabel: mapping.long))
            }
        }
        return results
    }

    private func isLikelyVenueNightScheduleText(_ text: String?) -> Bool {
        guard let text = ExternalEventSupport.plainText(text), !text.isEmpty else { return false }
        let normalized = ExternalEventSupport.normalizeToken(text)
        let blockedTokens = [
            "located between",
            "located in the heart",
            "all the best vip nightclubs in london",
            "membership program",
            "bespoke membership",
            "all the promoters",
            "club managers owners"
        ]
        guard !blockedTokens.contains(where: normalized.contains) else {
            return false
        }

        let hasClockTime = text.range(
            of: #"(?i)\b\d{1,2}(?::\d{2})?\s*(?:am|pm)\b"#,
            options: .regularExpression
        ) != nil
        if hasClockTime {
            return true
        }
        return (normalized.contains("open tonight")
            || normalized.contains("opens at")
            || normalized.contains("open from"))
            && hasClockTime
    }

    private func formatCurrency(_ value: Double) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencyCode = currency ?? "USD"
        formatter.maximumFractionDigits = value.rounded() == value ? 0 : 2
        return formatter.string(from: value as NSNumber) ?? "\(value)"
    }

    private func timezoneAbbreviation(for identifier: String) -> String {
        let zone = TimeZone(identifier: identifier) ?? .current
        return zone.abbreviation() ?? identifier
    }

    private var isImplicitMidnightLocalTime: Bool {
        guard let startLocal else { return false }
        return startLocal.contains("T00:00:00") || startLocal.contains("T00:00")
    }

    private func normalizedLocalDateString(from value: String?) -> String? {
        guard let value, !value.isEmpty else { return nil }
        return String(value.split(separator: "T").first ?? Substring(value))
    }

    private func parsedLocalDate(from value: String) -> Date? {
        let formats = [
            "yyyy-MM-dd'T'HH:mm:ss",
            "yyyy-MM-dd'T'HH:mm",
            "yyyy-MM-dd"
        ]
        for format in formats {
            let formatter = DateFormatter()
            formatter.locale = Locale(identifier: "en_US_POSIX")
            formatter.dateFormat = format
            formatter.timeZone = timezone.flatMap(TimeZone.init(identifier:)) ?? .current
            if let date = formatter.date(from: value) {
                return date
            }
        }
        return nil
    }

    private func formattedDateOnly(from localDate: String, dateFormat: String) -> String {
        let input = DateFormatter()
        input.locale = Locale(identifier: "en_US_POSIX")
        input.dateFormat = "yyyy-MM-dd"
        input.timeZone = timezone.flatMap(TimeZone.init(identifier:)) ?? .current
        guard let date = input.date(from: localDate) else {
            return localDate
        }

        let output = DateFormatter()
        output.locale = Locale(identifier: "en_US_POSIX")
        output.timeZone = input.timeZone
        output.dateFormat = dateFormat.contains("EEEE") ? "EEEE, MMM d" : "EEE, MMM d"
        return output.string(from: date)
    }

    private var isScheduledTonight: Bool {
        let zone = timezone.flatMap(TimeZone.init(identifier:)) ?? .current
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = zone

        if let startLocal, let parsed = parsedLocalDate(from: startLocal) {
            return calendar.isDateInToday(parsed)
        }
        if let startAtUTC {
            return calendar.isDateInToday(startAtUTC)
        }
        return false
    }

    private func allRegexMatches(
        in text: String,
        pattern: String,
        groupCount: Int,
        options: NSRegularExpression.Options = []
    ) -> [[String]] {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: options) else {
            return []
        }
        let nsrange = NSRange(text.startIndex..<text.endIndex, in: text)
        return regex.matches(in: text, options: [], range: nsrange).map { match in
            (1...groupCount).compactMap { index in
                guard index < match.numberOfRanges,
                      let range = Range(match.range(at: index), in: text)
                else {
                    return nil
                }
                return String(text[range])
            }
        }
    }
}

private extension ExternalEventType {
    var displayName: String {
        switch self {
        case .concert: return "Concert"
        case .partyNightlife: return "Nightlife"
        case .weekendActivity: return "Weekend"
        case .socialCommunityEvent: return "Community"
        case .groupRun: return "Group Run"
        case .race5k: return "5K"
        case .race10k: return "10K"
        case .raceHalfMarathon: return "Half Marathon"
        case .raceMarathon: return "Marathon"
        case .sportsEvent: return "Sports"
        case .otherLiveEvent: return "Live Event"
        }
    }

    var tint: Color {
        switch self {
        case .groupRun, .race5k, .race10k, .raceHalfMarathon, .raceMarathon:
            return .orange
        case .sportsEvent:
            return .blue
        case .concert:
            return .pink
        case .partyNightlife:
            return .purple
        case .weekendActivity:
            return .teal
        case .socialCommunityEvent:
            return .green
        case .otherLiveEvent:
            return .blue
        }
    }
}

private extension ExternalEventSource {
    var displayName: String {
        switch self {
        case .ticketmaster: return "Ticketmaster"
        case .stubHub: return "StubHub"
        case .runsignup: return "RunSignup"
        case .eventbrite: return "Eventbrite"
        case .googleEvents: return "Google Events"
        case .seatGeek: return "SeatGeek"
        case .sportsSchedule: return "Sports Schedule"
        case .appleMaps: return "Apple Maps"
        case .googlePlaces: return "Google Places"
        case .yelpFusion: return "Yelp"
        case .venueWebsite: return "Venue Site"
        case .venueCalendar: return "Venue Calendar"
        case .reservationProvider: return "Reservations"
        case .nightlifeAggregator: return "Nightlife Network"
        case .editorialGuide: return "Local Guide"
        }
    }
}

private struct SafariSheet: UIViewControllerRepresentable {
    let url: URL

    func makeUIViewController(context: Context) -> SFSafariViewController {
        let controller = SFSafariViewController(url: url)
        controller.dismissButtonStyle = .close
        controller.preferredControlTintColor = UIColor.white
        controller.preferredBarTintColor = UIColor(red: 0.086, green: 0.094, blue: 0.110, alpha: 1)
        return controller
    }

    func updateUIViewController(_ uiViewController: SFSafariViewController, context: Context) {}
}
