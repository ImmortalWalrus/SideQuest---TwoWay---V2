import Foundation

extension ExternalEvent {
    var sideQuestQuestID: String {
        "external_event_\(source.rawValue)_\(sourceEventID)"
    }

    private var sideQuestPath: QuestPath {
        switch eventType {
        case .groupRun, .race5k, .race10k, .raceHalfMarathon, .raceMarathon:
            return .warrior
        case .socialCommunityEvent:
            return .mind
        case .concert, .partyNightlife, .weekendActivity, .sportsEvent, .otherLiveEvent:
            return .explorer
        }
    }

    private var sideQuestDifficulty: QuestDifficulty {
        switch eventType {
        case .raceMarathon:
            return .expert
        case .raceHalfMarathon, .race10k, .sportsEvent:
            return .hard
        case .concert, .partyNightlife, .weekendActivity, .socialCommunityEvent, .groupRun, .otherLiveEvent:
            return .medium
        case .race5k:
            return .medium
        }
    }

    var sideQuestPlaceType: VerifiedPlaceType {
        switch eventType {
        case .partyNightlife:
            if let venueName, venueName.localizedCaseInsensitiveContains("bar") || venueName.localizedCaseInsensitiveContains("lounge") {
                return .barLounge
            }
            return .nightclub
        case .concert:
            return .concertVenue
        case .sportsEvent:
            if let venueName, venueName.localizedCaseInsensitiveContains("stadium") || venueName.localizedCaseInsensitiveContains("park") {
                return .stadium
            }
            return .arena
        case .socialCommunityEvent:
            return .communityCenter
        case .weekendActivity:
            return .restaurant
        case .groupRun, .race5k, .race10k, .raceHalfMarathon, .raceMarathon:
            return .park
        case .otherLiveEvent:
            return .concertVenue
        }
    }

    var mapPinAssetName: String? {
        switch sideQuestPlaceType {
        case .nightclub:
            return "15_nightclub"
        case .barLounge:
            return "16_bar_lounge"
        case .concertVenue:
            return "17_concert_venue"
        case .stadium:
            return "18_stadium"
        case .arena:
            return "12_arena"
        default:
            return nil
        }
    }

    var mapFallbackCategory: MapQuestCategory {
        switch sideQuestPlaceType {
        case .nightclub, .barLounge:
            return .restaurant
        case .concertVenue:
            return .museum
        case .arena, .stadium:
            return .basketballCourt
        case .communityCenter:
            return .communityCenter
        case .restaurant:
            return .restaurant
        case .park:
            return .park
        default:
            return .communityCenter
        }
    }

    private var sideQuestPresenceMinutes: Int? {
        switch eventType {
        case .partyNightlife:
            return 5
        case .concert, .sportsEvent, .socialCommunityEvent:
            return 10
        case .weekendActivity, .otherLiveEvent:
            return 5
        case .groupRun, .race5k, .race10k, .raceHalfMarathon, .raceMarathon:
            return 5
        }
    }

    private var sideQuestDescription: String {
        let base = [title, venueName, sideQuestScheduleLine]
            .compactMap { value in
                guard let value, !value.isEmpty else { return nil }
                return value
            }
            .joined(separator: " • ")

        let verificationNote: String
        if eventType == .partyNightlife || recordKind == .venueNight || eventType == .concert || eventType == .sportsEvent {
            verificationNote = "Start the quest in-app, then verify on-site later with location check-in. Optional stronger proof is available with dual photo."
        } else {
            verificationNote = "Start the quest in-app, then verify on-site later."
        }

        return base.isEmpty ? verificationNote : "\(base). \(verificationNote)"
    }

    private var sideQuestScheduleLine: String? {
        if let startLocal, !startLocal.isEmpty {
            if let endLocal, !endLocal.isEmpty {
                return "\(startLocal) - \(endLocal)"
            }
            return startLocal
        }
        if let startAtUTC {
            return DateFormatter.localizedString(from: startAtUTC, dateStyle: .medium, timeStyle: .short)
        }
        return nil
    }

    private var sideQuestAddressLine: String? {
        let parts: [String] = [addressLine1, city, state, postalCode]
            .compactMap { $0 }
            .filter { !$0.isEmpty }
        guard !parts.isEmpty else { return venueName }
        return parts.joined(separator: ", ")
    }

    func sideQuestQuest(rewardPolicy: ExternalEventRewardPolicy) -> Quest {
        Quest(
            id: sideQuestQuestID,
            title: title,
            description: sideQuestDescription,
            path: sideQuestPath,
            difficulty: sideQuestDifficulty,
            type: .verified,
            evidenceType: .placeVerification,
            xpReward: rewardPolicy.xp,
            goldReward: rewardPolicy.coins,
            diamondReward: rewardPolicy.diamonds,
            milestoneIds: [],
            minCompletionMinutes: 0,
            isRepeatable: true,
            requiresUniqueLocation: true,
            isFeatured: false,
            featuredExpiresAt: nil,
            completionCount: socialProofCount ?? completionCountFallback,
            requiredPlaceType: sideQuestPlaceType,
            presenceMinutes: sideQuestPresenceMinutes,
            verificationLatitude: latitude,
            verificationLongitude: longitude,
            verificationVenueName: venueName,
            verificationAddressText: sideQuestAddressLine,
            externalEventIconName: ExternalEventIconService.iconName(for: self)
        )
    }

    private var completionCountFallback: Int {
        if let venuePopularityCount {
            return venuePopularityCount
        }
        if let ticketProviderCount {
            return ticketProviderCount
        }
        return 0
    }
}

extension AppState {
    func externalEventQuestInstance(for event: ExternalEvent) -> QuestInstance? {
        let questID = event.sideQuestQuestID
        return activeInstances
            .filter { $0.quest.id == questID }
            .sorted { lhs, rhs in
                if lhs.state == rhs.state {
                    return lhs.startedAt > rhs.startedAt
                }
                return questStatePriority(lhs.state) < questStatePriority(rhs.state)
            }
            .first
    }

    @discardableResult
    func startExternalEventQuest(_ event: ExternalEvent) -> QuestInstance? {
        if let existing = externalEventQuestInstance(for: event),
           existing.state == .active || existing.state == .submitted || existing.state == .verified {
            return existing
        }

        let quest = event.sideQuestQuest(rewardPolicy: ExternalEventPolicyService.policy(for: event))
        guard activeQuestCount < 5 else { return nil }

        activeInstances.removeAll { $0.quest.id == quest.id && ($0.state == .failed || $0.state == .rejected) }

        let instance = QuestInstance(
            id: UUID().uuidString,
            quest: quest,
            state: .active,
            mode: .solo,
            startedAt: Date(),
            submittedAt: nil,
            verifiedAt: nil,
            groupId: nil
        )
        activeInstances.append(instance)
        PersistenceService.saveActiveInstances(activeInstances)
        syncQuestInstanceToBackend(instance)
        return instance
    }

    func retryExternalEventQuest(_ event: ExternalEvent) -> QuestInstance? {
        let questID = event.sideQuestQuestID
        activeInstances.removeAll { $0.quest.id == questID && ($0.state == .failed || $0.state == .rejected) }
        return startExternalEventQuest(event)
    }

    private func questStatePriority(_ state: QuestInstanceState) -> Int {
        switch state {
        case .active: return 0
        case .submitted: return 1
        case .verified: return 2
        case .rejected: return 3
        case .failed: return 4
        case .pendingInvite: return 5
        case .pendingQueue: return 6
        }
    }
}
