import CoreLocation
import Foundation

nonisolated struct RankedExternalEvent: Identifiable, Hashable, Sendable {
    let event: ExternalEvent
    let score: Double
    let bucket: ExternalEventFeedService.Bucket

    var id: String { event.id }
}

enum ExternalEventFeedService {
    enum Bucket: String, Hashable, Sendable {
        case race
        case sports
        case concert
        case nightlife
        case weekend
        case social
        case other
    }

    static func rankedEvents(
        from events: [ExternalEvent],
        context: PersonalizationEngine.PlayerContext,
        sort: ExternalEventSortOption = .recommended,
        filter: ExternalEventFilterOption = .all,
        limit: Int = 48
    ) -> [ExternalEvent] {
        let filtered = events
            .filter { shouldInclude($0, context: context) }
            .filter { matches($0, filter: filter) }

        let scored = filtered
            .map { event in
                RankedExternalEvent(
                    event: event,
                    score: score(event: event, context: context),
                    bucket: bucket(for: event)
                )
            }
        switch sort {
        case .recommended:
            let recommended = scored.sorted { lhs, rhs in
                if lhs.score == rhs.score {
                    return (lhs.event.startAtUTC ?? .distantFuture) < (rhs.event.startAtUTC ?? .distantFuture)
                }
                return lhs.score > rhs.score
            }
            let uniqueRecommended = uniqueDisplayEvents(from: recommended)
            let locked = priorityLockIns(
                from: uniqueRecommended,
                limit: min(3, limit),
                filter: filter
            )
            let lockedIDs = Set(locked.map(\.id))
            let remainder = uniqueRecommended.filter { !lockedIDs.contains($0.id) }
            let diversifiedRemainder = diversified(
                remainder,
                limit: max(limit - locked.count, 0),
                filter: filter
            )
            return Array((locked + diversifiedRemainder).prefix(limit).map(\.event))
        case .hottest:
            let hottestCandidates = scored.filter { qualifiesForHottestLane($0.event) }
            let source = hottestCandidates.isEmpty ? scored : hottestCandidates
            let hottestSorted = uniqueDisplayEvents(from: source.sorted { lhs, rhs in
                let left = hottestScore(for: lhs.event, baseScore: lhs.score)
                let right = hottestScore(for: rhs.event, baseScore: rhs.score)
                if left == right {
                    return (lhs.event.startAtUTC ?? .distantFuture) < (rhs.event.startAtUTC ?? .distantFuture)
                }
                return left > right
            })
            let locked = priorityLockIns(
                from: hottestSorted,
                limit: min(4, limit),
                filter: filter
            )
            let lockedIDs = Set(locked.map(\.id))
            let remainder = hottestSorted.filter { !lockedIDs.contains($0.id) }
            return Array(
                (
                    locked
                    + diversified(
                        remainder,
                        limit: max(limit - locked.count, 0),
                        filter: filter
                    )
                )
                .prefix(limit)
                .map(\.event)
            )
        case .soonest:
            return Array(
                uniqueDisplayEvents(from: scored.sorted { lhs, rhs in
                    let left = lhs.event.startAtUTC ?? .distantFuture
                    let right = rhs.event.startAtUTC ?? .distantFuture
                    if left == right { return lhs.score > rhs.score }
                    return left < right
                })
                .prefix(limit)
                .map(\.event)
            )
        case .closest:
            return Array(
                uniqueDisplayEvents(from: scored.sorted { lhs, rhs in
                    let left = distanceMiles(for: lhs.event, coordinate: context.userCoordinate) ?? .greatestFiniteMagnitude
                    let right = distanceMiles(for: rhs.event, coordinate: context.userCoordinate) ?? .greatestFiniteMagnitude
                    if left == right {
                        return (lhs.event.startAtUTC ?? .distantFuture) < (rhs.event.startAtUTC ?? .distantFuture)
                    }
                    return left < right
                })
                .prefix(limit)
                .map(\.event)
            )
        case .weekend:
            return Array(
                uniqueDisplayEvents(from: scored.sorted { lhs, rhs in
                    let left = weekendPriority(for: lhs.event)
                    let right = weekendPriority(for: rhs.event)
                    if left == right {
                        return (lhs.event.startAtUTC ?? .distantFuture) < (rhs.event.startAtUTC ?? .distantFuture)
                    }
                    return left > right
                })
                .prefix(limit)
                .map(\.event)
            )
        }
    }

    static func bucket(for event: ExternalEvent) -> Bucket {
        switch event.eventType {
        case .groupRun, .race5k, .race10k, .raceHalfMarathon, .raceMarathon:
            return .race
        case .sportsEvent:
            return .sports
        case .concert:
            return .concert
        case .partyNightlife:
            return .nightlife
        case .weekendActivity:
            return .weekend
        case .socialCommunityEvent:
            return .social
        case .otherLiveEvent:
            return .other
        }
    }

    private static func shouldInclude(
        _ event: ExternalEvent,
        context: PersonalizationEngine.PlayerContext
    ) -> Bool {
        if !event.isUpcoming { return false }

        switch event.status {
        case .cancelled, .ended:
            return false
        case .scheduled, .onsale, .openRegistration, .soldOut, .postponed, .rescheduled, .unknown:
            break
        }

        switch event.availabilityStatus {
        case .cancelled, .ended:
            return false
        case .available, .onsale, .openRegistration, .registrationClosed, .soldOut, .postponed, .rescheduled, .unknown:
            break
        }

        if ExternalEventSupport.shouldSuppressLowSignalEvent(event) {
            return false
        }

        if (event.eventType == .partyNightlife || event.recordKind == .venueNight),
           !ExternalEventSupport.hasUsableNightlifeImage(for: event) {
            return false
        }

        return passesRaceGate(event, context: context)
    }

    private static func passesRaceGate(
        _ event: ExternalEvent,
        context: PersonalizationEngine.PlayerContext
    ) -> Bool {
        let runningAffinity = runningAffinityScore(context: context)
        switch event.eventType {
        case .raceMarathon:
            return runningAffinity >= 3
        case .raceHalfMarathon:
            return runningAffinity >= 2
        case .race10k:
            return runningAffinity >= 1 || context.onboarding.goals.contains(.getfit)
        case .groupRun, .race5k, .concert, .partyNightlife, .weekendActivity, .socialCommunityEvent, .sportsEvent, .otherLiveEvent:
            return true
        }
    }

    private static func runningAffinityScore(context: PersonalizationEngine.PlayerContext) -> Int {
        var score = 0
        if context.selectedInterests.contains(.running) { score += 2 }
        if context.selectedInterests.contains(.cardio) { score += 1 }
        if context.selectedInterests.contains(.fitness) { score += 1 }
        if context.warriorRank >= 6 { score += 1 }
        if context.playerLevel >= 10 { score += 1 }
        return score
    }

    private static func score(
        event: ExternalEvent,
        context: PersonalizationEngine.PlayerContext
    ) -> Double {
        var score = 0.0

        score += timeScore(for: event)
        score += statusScore(for: event)
        score += relevanceScore(for: event, context: context)
        score += onboardingEventPreferenceScore(for: event, context: context)
        score += historyAffinityScore(for: event, context: context)
        score += proximityScore(for: event, coordinate: context.userCoordinate)
        score += localSceneScore(for: event, context: context)
        score += qualitySignalScore(for: event)
        score += momentumScore(for: event)
        score += sameDayPriorityBoost(for: event)
        score += Double(ExternalEventSupport.prominenceSignalScore(for: event)) * 0.9
        score += Double(ExternalEventSupport.marqueeEventBoost(for: event)) * 0.95
        score += Double(ExternalEventSupport.completenessScore(for: event)) * 0.85
        score += Double(ExternalEventSupport.sourcePriority(for: event)) * 0.55

        if event.urgencyBadge != nil { score += 6 }
        if event.socialProofCount != nil || event.socialProofLabel != nil { score += 5 }
        if event.imageURL != nil { score += 2 }
        if event.venueName != nil { score += 2 }

        return score
    }

    private static func onboardingEventPreferenceScore(
        for event: ExternalEvent,
        context: PersonalizationEngine.PlayerContext
    ) -> Double {
        var score = 0.0
        let haystack = eventSearchHaystack(for: event)

        for preference in context.onboarding.preferredEventTypes {
            switch preference {
            case .concerts:
                if event.eventType == .concert { score += 20 }
            case .nightlife:
                if event.eventType == .partyNightlife { score += 20 }
            case .exclusiveNightlife:
                if event.eventType == .partyNightlife && qualifiesForExclusiveLane(event) {
                    score += 24
                }
            case .comedy:
                if haystack.contains("comedy") || haystack.contains("stand up") || haystack.contains("standup") || haystack.contains("improv") || haystack.contains("open mic") {
                    score += 16
                }
            case .community:
                if event.eventType == .socialCommunityEvent { score += 18 }
            case .markets:
                if haystack.contains("market") || haystack.contains("festival") || haystack.contains("fair") || haystack.contains("pop up") {
                    score += 16
                }
            case .raceEvents:
                switch event.eventType {
                case .groupRun, .race5k, .race10k, .raceHalfMarathon, .raceMarathon:
                    score += 22
                default:
                    break
                }
            case .sportsGames:
                if event.eventType == .sportsEvent {
                    score += 24
                }
            case .wellness:
                if haystack.contains("wellness") || haystack.contains("yoga") || haystack.contains("meditation") || haystack.contains("sound bath") || haystack.contains("breathwork") {
                    score += 16
                }
            case .foodAndDrink:
                if haystack.contains("food") || haystack.contains("drink") || haystack.contains("brunch") || haystack.contains("wine") || haystack.contains("tasting") {
                    score += 16
                }
            }
        }

        if event.eventType == .concert || event.eventType == .partyNightlife {
            for genre in context.onboarding.favoriteMusicGenres {
                if genre.matchTokens.contains(where: haystack.contains) {
                    score += 10
                }
            }
        }

        return min(score, 54)
    }

    private static func historyAffinityScore(
        for event: ExternalEvent,
        context: PersonalizationEngine.PlayerContext
    ) -> Double {
        func interestScore(_ interest: UserInterest) -> Double {
            min(Double(context.completedInterestCounts[interest, default: 0]) * 2.4, 16)
        }

        func skillScore(_ skill: UserSkill) -> Double {
            min(Double(context.completedSkillCounts[skill, default: 0]) * 1.8, 14)
        }

        switch event.eventType {
        case .groupRun:
            return interestScore(.running) + interestScore(.cardio) + skillScore(.endurance)
        case .race5k:
            return interestScore(.running) + interestScore(.fitness) + skillScore(.endurance)
        case .race10k:
            return interestScore(.running) + interestScore(.cardio) + skillScore(.endurance) + skillScore(.discipline)
        case .raceHalfMarathon, .raceMarathon:
            return interestScore(.running) + interestScore(.cardio) + skillScore(.endurance) + skillScore(.discipline) + skillScore(.resilience)
        case .concert:
            return interestScore(.music) + interestScore(.art) + skillScore(.creativity)
        case .partyNightlife:
            return interestScore(.music) + skillScore(.charisma)
        case .weekendActivity:
            return interestScore(.exploration) + interestScore(.travel) + interestScore(.outdoors)
        case .socialCommunityEvent:
            return interestScore(.volunteering) + skillScore(.charisma) + skillScore(.leadership)
        case .sportsEvent:
            return interestScore(.fitness) + interestScore(.cardio) + skillScore(.charisma)
        case .otherLiveEvent:
            return interestScore(.exploration) + skillScore(.creativity)
        }
    }

    private static func timeScore(for event: ExternalEvent) -> Double {
        guard let startAtUTC = event.startAtUTC else { return 8 }
        let hoursUntil = startAtUTC.timeIntervalSinceNow / 3600
        if hoursUntil < 0 { return -200 }
        if hoursUntil <= 6 { return 64 }
        if hoursUntil <= 12 { return 58 }
        if hoursUntil <= 24 { return 52 }
        if hoursUntil <= 48 { return 38 }
        if hoursUntil <= 72 { return 20 }
        if hoursUntil <= 7 * 24 { return 6 }
        if hoursUntil <= 14 * 24 { return -4 }
        if hoursUntil <= 30 * 24 { return -10 }
        if hoursUntil <= 60 * 24 { return 0 }
        return -6
    }

    private static func statusScore(for event: ExternalEvent) -> Double {
        switch event.availabilityStatus {
        case .openRegistration, .onsale: return 18
        case .available: return 12
        case .soldOut: return -22
        case .registrationClosed: return -16
        case .postponed: return -10
        case .rescheduled: return -4
        case .cancelled, .ended: return -100
        case .unknown: break
        }

        switch event.status {
        case .scheduled: return 8
        case .onsale, .openRegistration: return 14
        case .soldOut: return -18
        case .postponed: return -10
        case .rescheduled: return -4
        case .cancelled, .ended: return -100
        case .unknown: return 0
        }
    }

    private static func relevanceScore(
        for event: ExternalEvent,
        context: PersonalizationEngine.PlayerContext
    ) -> Double {
        var score = 0.0

        switch event.eventType {
        case .groupRun, .race5k, .race10k, .raceHalfMarathon, .raceMarathon:
            if context.selectedInterests.contains(.running) { score += 18 }
            if context.selectedInterests.contains(.cardio) { score += 14 }
            if context.selectedInterests.contains(.fitness) { score += 10 }
            if context.onboarding.goals.contains(.getfit) { score += 16 }
            if context.onboarding.goals.contains(.buildHabits) { score += 5 }
        case .concert:
            if context.selectedInterests.contains(.music) { score += 18 }
            if context.selectedInterests.contains(.art) { score += 8 }
            if context.onboarding.goals.contains(.relaxAndUnwind) { score += 8 }
            if context.onboarding.goals.contains(.socialChallenge) { score += 5 }
        case .partyNightlife:
            if context.selectedInterests.contains(.music) { score += 12 }
            if context.onboarding.goals.contains(.socialChallenge) { score += 18 }
            if context.onboarding.goals.contains(.explorePlaces) { score += 6 }
        case .weekendActivity:
            if context.selectedInterests.contains(.exploration) { score += 14 }
            if context.selectedInterests.contains(.travel) { score += 10 }
            if context.selectedInterests.contains(.outdoors) { score += 8 }
            if context.onboarding.goals.contains(.explorePlaces) { score += 16 }
            if context.onboarding.goals.contains(.relaxAndUnwind) { score += 8 }
        case .socialCommunityEvent:
            if context.selectedInterests.contains(.volunteering) { score += 16 }
            if context.onboarding.goals.contains(.socialChallenge) { score += 12 }
            if context.onboarding.goals.contains(.explorePlaces) { score += 6 }
        case .sportsEvent:
            if context.onboarding.goals.contains(.socialChallenge) { score += 12 }
            if context.onboarding.goals.contains(.explorePlaces) { score += 10 }
            if context.selectedInterests.contains(.fitness) { score += 8 }
            if context.selectedInterests.contains(.cardio) { score += 8 }
        case .otherLiveEvent:
            if context.onboarding.goals.contains(.explorePlaces) { score += 8 }
            if context.onboarding.goals.contains(.socialChallenge) { score += 6 }
        }

        return score
    }

    private static func proximityScore(
        for event: ExternalEvent,
        coordinate: CLLocationCoordinate2D?
    ) -> Double {
        guard let miles = distanceMiles(for: event, coordinate: coordinate) else {
            return 0
        }

        switch miles {
        case ..<3: return 22
        case ..<8: return 16
        case ..<20: return 10
        case ..<35: return 4
        case ..<60: return 0
        default: return -14
        }
    }

    private static func localSceneScore(
        for event: ExternalEvent,
        context: PersonalizationEngine.PlayerContext
    ) -> Double {
        let preferredCity = ExternalEventSupport.normalizeToken(context.preferredCity)
        let preferredState = ExternalEventSupport.normalizeToken(context.preferredState)
        guard !preferredCity.isEmpty || !preferredState.isEmpty else {
            return 0
        }

        let eventCity = ExternalEventSupport.normalizeToken(event.city)
        let eventState = ExternalEventSupport.normalizeToken(event.state)
        var score = 0.0

        if !preferredCity.isEmpty, eventCity == preferredCity {
            score += 14
        }

        if !preferredState.isEmpty, !eventState.isEmpty, eventState == preferredState {
            score += 2
        }

        if ExternalEventSupport.sharesMetroArea(
            event: event,
            preferredCity: context.preferredCity,
            preferredState: context.preferredState
        ) {
            score += 8
        }

        let neighborhood = ExternalEventSupport.normalizeToken(event.neighborhood)
        if !neighborhood.isEmpty {
            if neighborhood == preferredCity {
                score += 6
            } else if !preferredCity.isEmpty && neighborhood.contains(preferredCity) {
                score += 4
            }
        }

        if let venuePopularityCount = event.venuePopularityCount, venuePopularityCount >= 50 {
            score += 4
        }
        if let venueRating = event.venueRating, venueRating >= 4.4 {
            score += 3
        }

        if event.organizerVerified == true, let organizerEventCount = event.organizerEventCount, organizerEventCount >= 25 {
            score += 3
        }

        score += Double(ExternalEventSupport.trustedVenueScore(for: event)) * 0.85

        return score
    }

    private static func qualitySignalScore(for event: ExternalEvent) -> Double {
        var score = Double(ExternalEventSupport.qualityScore(for: event)) * 0.72
        if event.source == .eventbrite, !ExternalEventSupport.isHighSignalLocalEvent(event) {
            score -= ExternalEventSupport.isPromisingEventbriteEvent(event) ? 4 : 12
        }
        if event.source == .googleEvents {
            score += Double(event.ticketProviderCount ?? 0) * 0.9
        }
        return score
    }

    private static func momentumScore(for event: ExternalEvent) -> Double {
        var score = 0.0

        if let venuePopularityCount = event.venuePopularityCount {
            score += min(Double(venuePopularityCount) / 8, 12)
        }

        if event.organizerVerified == true {
            score += 7
        }

        if let organizerEventCount = event.organizerEventCount {
            score += min(Double(organizerEventCount) / 24, 10)
        }
        if let ticketProviderCount = event.ticketProviderCount {
            score += min(Double(ticketProviderCount) * 1.4, 8)
        }

        if event.source == .eventbrite {
            if ExternalEventSupport.isHighSignalLocalEvent(event) {
                score += 6
            } else if ExternalEventSupport.isPromisingEventbriteEvent(event) {
                score += 4
            }
        }
        if event.source == .googleEvents {
            score += Double(ExternalEventSupport.prominenceSignalScore(for: event)) * 0.65
        }
        score += Double(ExternalEventSupport.marqueeEventBoost(for: event)) * 0.8

        return score
    }

    private static func sameDayPriorityBoost(for event: ExternalEvent) -> Double {
        if isVenueNightActive(event) && qualifiesForExclusiveLane(event) {
            return 28
        }
        if isTonight(event) && ExternalEventSupport.isMainstreamHeadlineEvent(event) {
            return 42
        }
        if isToday(event) && (ExternalEventSupport.isMainstreamHeadlineEvent(event) || qualifiesForExclusiveLane(event)) {
            return 34
        }
        if isTomorrow(event) && ExternalEventSupport.isMainstreamHeadlineEvent(event) {
            return 18
        }
        return 0
    }

    private static func distanceMiles(
        for event: ExternalEvent,
        coordinate: CLLocationCoordinate2D?
    ) -> Double? {
        guard let coordinate,
              let latitude = event.latitude,
              let longitude = event.longitude
        else {
            return nil
        }

        let eventLocation = CLLocation(latitude: latitude, longitude: longitude)
        let userLocation = CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude)
        return userLocation.distance(from: eventLocation) / 1609.344
    }

    private static func diversified(
        _ scored: [RankedExternalEvent],
        limit: Int,
        filter: ExternalEventFilterOption
    ) -> [RankedExternalEvent] {
        guard !scored.isEmpty else { return [] }

        var pools = Dictionary(grouping: scored, by: \.bucket)
        var result: [RankedExternalEvent] = []
        var lastBucket: Bucket?
        var bucketCounts: [Bucket: Int] = [:]
        let bucketCaps = bucketCaps(for: filter, limit: limit)

        while result.count < limit {
            let candidates = pools.compactMap { bucket, items in
                items.first.map { (bucket: bucket, item: $0) }
            }
            guard !candidates.isEmpty else { break }

            let underCapCandidates = candidates.filter { candidate in
                guard let cap = bucketCaps[candidate.bucket] else { return true }
                return bucketCounts[candidate.bucket, default: 0] < cap
            }
            let availableCandidates = underCapCandidates.isEmpty ? candidates : underCapCandidates

            let preferred = availableCandidates
                .filter { $0.bucket != lastBucket }
                .max { lhs, rhs in lhs.item.score < rhs.item.score }
            let chosen = preferred ?? availableCandidates.max { lhs, rhs in lhs.item.score < rhs.item.score }

            guard let chosen else { break }
            result.append(chosen.item)
            lastBucket = chosen.bucket
            bucketCounts[chosen.bucket, default: 0] += 1
            pools[chosen.bucket]?.removeFirst()
            if pools[chosen.bucket]?.isEmpty == true {
                pools.removeValue(forKey: chosen.bucket)
            }
        }

        return result
    }

    private static func bucketCaps(
        for filter: ExternalEventFilterOption,
        limit: Int
    ) -> [Bucket: Int] {
        guard filter == .all else { return [:] }
        return [
            .nightlife: max(3, Int((Double(limit) * 0.22).rounded(.up)))
        ]
    }

    private static func uniqueDisplayEvents(from scored: [RankedExternalEvent]) -> [RankedExternalEvent] {
        var seen = Set<String>()
        var unique: [RankedExternalEvent] = []
        var dedupeBuckets: [String: [RankedExternalEvent]] = [:]
        var dayBucketCandidates: [String: [RankedExternalEvent]] = [:]
        var organizerCounts: [String: Int] = [:]
        var venueCounts: [String: Int] = [:]

        for item in scored {
            let key = displayKey(for: item.event)
            if seen.contains(key) { continue }
            let bucketKey = ExternalEventSupport.dedupeBucketKey(for: item.event)
            let dayBucketKey = candidateDayBucketKey(for: item)
            if dedupeBuckets[bucketKey, default: []].contains(where: { existing in
                ExternalEventSupport.isLikelyDuplicate(existing.event, item.event)
            }) || dayBucketCandidates[dayBucketKey, default: []].contains(where: { existing in
                ExternalEventSupport.isLikelyDuplicate(existing.event, item.event)
            }) {
                continue
            }

            if item.bucket != .race {
                if let organizerKey = ExternalEventSupport.normalizedOrganizerKey(for: item.event),
                   organizerCounts[organizerKey, default: 0] >= maxOrganizerOccurrences(for: item.event) {
                    continue
                }

                if let venueKey = ExternalEventSupport.normalizedVenueKey(for: item.event),
                   venueCounts[venueKey, default: 0] >= maxVenueOccurrences(for: item.event) {
                    continue
                }
            }

            seen.insert(key)
            unique.append(item)
            dedupeBuckets[bucketKey, default: []].append(item)
            dayBucketCandidates[dayBucketKey, default: []].append(item)

            if item.bucket != .race {
                if let organizerKey = ExternalEventSupport.normalizedOrganizerKey(for: item.event) {
                    organizerCounts[organizerKey, default: 0] += 1
                }
                if let venueKey = ExternalEventSupport.normalizedVenueKey(for: item.event) {
                    venueCounts[venueKey, default: 0] += 1
                }
            }
        }

        return unique
    }

    private static func candidateDayBucketKey(for item: RankedExternalEvent) -> String {
        let dayToken = ExternalEventSupport.localDayToken(
            startLocal: item.event.startLocal,
            startAtUTC: item.event.startAtUTC,
            timezone: item.event.timezone
        )
        return "\(item.bucket.rawValue)::\(dayToken)"
    }

    private static func maxOrganizerOccurrences(for event: ExternalEvent) -> Int {
        switch event.source {
        case .eventbrite:
            return event.organizerVerified == true ? 2 : 1
        case .ticketmaster:
            return 2
        case .stubHub:
            return 2
        case .runsignup:
            return 3
        case .googleEvents:
            return ExternalEventSupport.isExclusiveEvent(event) ? 2 : 1
        case .seatGeek:
            return 2
        case .sportsSchedule:
            return 3
        case .appleMaps, .googlePlaces, .yelpFusion:
            return 2
        case .venueWebsite, .venueCalendar, .reservationProvider, .nightlifeAggregator, .editorialGuide:
            return 1
        }
    }

    private static func maxVenueOccurrences(for event: ExternalEvent) -> Int {
        if let venuePopularityCount = event.venuePopularityCount, venuePopularityCount >= 120 {
            return 3
        }
        if ExternalEventSupport.isExclusiveEvent(event) {
            return 2
        }
        return 2
    }

    private static func displayKey(for event: ExternalEvent) -> String {
        if event.source == .runsignup,
           let sourceParentID = event.sourceParentID,
           !sourceParentID.isEmpty {
            return "runsignup-parent::\(sourceParentID)"
        }

        let dayToken = ExternalEventSupport.localDayToken(
            startLocal: event.startLocal,
            startAtUTC: event.startAtUTC,
            timezone: event.timezone
        )
        let titleToken = ExternalEventSupport.dedupeTitleFingerprint(
            event.title,
            eventType: event.eventType,
            venueName: event.venueName
        )
        let locationToken = event.eventType == .sportsEvent
            ? ExternalEventSupport.normalizeToken(event.venueName ?? event.city ?? event.state ?? "sports")
            : ExternalEventSupport.normalizeToken(event.venueName ?? event.city ?? event.addressLine1 ?? "unknown-location")
        return "\(titleToken)::\(dayToken)::\(locationToken)"
    }

    private static func weekendPriority(for event: ExternalEvent) -> Int {
        guard let startAtUTC = event.startAtUTC else { return 0 }
        let timezone = event.timezone.flatMap(TimeZone.init(identifier:)) ?? .current
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timezone
        let weekday = calendar.component(.weekday, from: startAtUTC)
        switch weekday {
        case 6, 7, 1:
            return 2
        default:
            return 1
        }
    }

    private static func matches(_ event: ExternalEvent, filter: ExternalEventFilterOption) -> Bool {
        switch filter {
        case .all:
            return true
        case .today:
            return isToday(event)
        case .tonight:
            return isTonight(event)
        case .tomorrow:
            return isTomorrow(event)
        case .sports:
            return event.eventType == .sportsEvent
        case .concerts:
            return event.eventType == .concert
        case .nightlife:
            return event.eventType == .partyNightlife
        case .exclusive:
            return qualifiesForExclusiveLane(event)
        case .races:
            switch event.eventType {
            case .groupRun, .race5k, .race10k, .raceHalfMarathon, .raceMarathon:
                return true
            default:
                return false
            }
        case .community:
            return event.eventType == .socialCommunityEvent || event.eventType == .weekendActivity
        case .weekend:
            return weekendPriority(for: event) >= 2
        case .free:
            guard let priceMin = event.priceMin ?? event.priceMax else { return false }
            let priceMax = event.priceMax ?? priceMin
            return priceMin == 0 && priceMax == 0
        }
    }

    static func exclusiveEvents(
        from events: [ExternalEvent],
        context: PersonalizationEngine.PlayerContext,
        limit: Int = 6
    ) -> [ExternalEvent] {
        rankedEvents(from: events, context: context, sort: .hottest, filter: .exclusive, limit: limit)
    }

    private static func priorityLockIns(
        from scored: [RankedExternalEvent],
        limit: Int,
        filter: ExternalEventFilterOption
    ) -> [RankedExternalEvent] {
        guard limit > 0 else { return [] }

        let nightlifeCap = filter == .all ? 1 : Int.max
        var nightlifeCount = 0
        var locked: [RankedExternalEvent] = []

        for item in scored where qualifiesForPriorityLockIn(item.event) {
            if item.bucket == .nightlife, nightlifeCount >= nightlifeCap {
                continue
            }
            locked.append(item)
            if item.bucket == .nightlife {
                nightlifeCount += 1
            }
            if locked.count >= limit {
                break
            }
        }

        return locked
    }

    private static func qualifiesForPriorityLockIn(_ event: ExternalEvent) -> Bool {
        if qualifiesForExclusiveLane(event) && (isTonight(event) || isToday(event)) {
            return true
        }
        if event.eventType == .sportsEvent || event.eventType == .concert {
            if isTonight(event) || isToday(event) {
                return ExternalEventSupport.isMainstreamHeadlineEvent(event)
                    || ExternalEventSupport.marqueeEventBoost(for: event) >= 18
            }
            if isTomorrow(event) {
                return ExternalEventSupport.isMainstreamHeadlineEvent(event)
                    && ExternalEventSupport.qualityScore(for: event) >= 24
            }
        }
        return false
    }

    private static func hottestScore(for event: ExternalEvent, baseScore: Double) -> Double {
        baseScore
            + Double(ExternalEventSupport.prominenceSignalScore(for: event)) * 1.8
            + Double(ExternalEventSupport.marqueeEventBoost(for: event)) * 1.6
            + (isToday(event) ? 14 : 0)
            + (isTonight(event) ? 18 : 0)
            + (isTomorrow(event) ? 8 : 0)
    }

    private static func qualifiesForHottestLane(_ event: ExternalEvent) -> Bool {
        if ExternalEventSupport.shouldSuppressLowSignalEvent(event) {
            return false
        }
        if event.source == .eventbrite,
           !ExternalEventSupport.isHighSignalLocalEvent(event),
           !ExternalEventSupport.isPromisingEventbriteEvent(event) {
            return false
        }
        if event.recordKind == .venueNight {
            return qualifiesForExclusiveLane(event)
        }

        let quality = ExternalEventSupport.qualityScore(for: event)
        let prominence = ExternalEventSupport.prominenceSignalScore(for: event)
        let marquee = ExternalEventSupport.marqueeEventBoost(for: event)

        if event.eventType == .sportsEvent {
            if isToday(event) || isTonight(event) || isTomorrow(event) {
                return quality >= 24 || marquee >= 16 || ExternalEventSupport.isMainstreamHeadlineEvent(event)
            }
            return false
        }

        if isToday(event) || isTonight(event) || isTomorrow(event) {
            if event.source == .eventbrite {
                return quality >= 28
                    || prominence >= 20
                    || marquee >= 14
                    || ExternalEventSupport.isPromisingEventbriteEvent(event)
            }
            return quality >= 32 || prominence >= 24 || marquee >= 18
        }

        return prominence >= 34 && quality >= 40
    }

    private static func qualifiesForExclusiveLane(_ event: ExternalEvent) -> Bool {
        guard ExternalEventSupport.isExclusiveEvent(event) else { return false }
        guard event.eventType == .partyNightlife else { return false }
        if event.source == .eventbrite,
           !ExternalEventSupport.isHighSignalLocalEvent(event),
           !(ExternalEventSupport.isPromisingEventbriteEvent(event) && ExternalEventSupport.qualityScore(for: event) >= 34) {
            return false
        }
        let liveTimingMatch = isToday(event) || isTonight(event) || isTomorrow(event) || isVenueNightActive(event)
        guard liveTimingMatch else { return false }

        let quality = ExternalEventSupport.qualityScore(for: event)
        let venueStrength = ExternalEventSupport.trustedVenueScore(for: event)
        let marquee = ExternalEventSupport.marqueeEventBoost(for: event)
        let hasPremiumMetadata = event.guestListAvailable == true
            || event.bottleServiceAvailable == true
            || event.tableMinPrice != nil
            || event.reservationURL != nil
        if hasPremiumMetadata && venueStrength >= 12 && (quality >= 30 || marquee >= 16) {
            return true
        }

        if venueStrength >= 18 && (quality >= 24 || marquee >= 12) {
            return true
        }

        if event.recordKind == .venueNight,
           venueStrength >= 16,
           (event.openingHoursText != nil || event.startLocal != nil || event.startAtUTC != nil),
           quality >= 22 {
            return true
        }

        return false
    }

    private static func isVenueNightActive(_ event: ExternalEvent) -> Bool {
        guard event.recordKind == .venueNight else { return false }
        if event.reservationURL != nil || event.guestListAvailable == true || event.bottleServiceAvailable == true {
            return true
        }
        guard let openingHoursText = event.openingHoursText else { return false }
        let normalized = ExternalEventSupport.normalizeToken(openingHoursText)
        if normalized.contains("tonight") || normalized.contains("open") {
            return true
        }

        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        let weekday = formatter.weekdaySymbols[Calendar.current.component(.weekday, from: Date()) - 1]
        let shortWeekday = String(weekday.prefix(3))
        let weekdayToken = ExternalEventSupport.normalizeToken(weekday)
        let shortWeekdayToken = ExternalEventSupport.normalizeToken(shortWeekday)
        return normalized.contains(weekdayToken) || normalized.contains(shortWeekdayToken)
    }

    private static func isToday(_ event: ExternalEvent) -> Bool {
        guard let startAtUTC = event.startAtUTC else { return false }
        let timezone = event.timezone.flatMap(TimeZone.init(identifier:)) ?? .current
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timezone
        return calendar.isDate(startAtUTC, inSameDayAs: Date())
    }

    private static func isTonight(_ event: ExternalEvent) -> Bool {
        guard let startAtUTC = event.startAtUTC else { return false }
        let timezone = event.timezone.flatMap(TimeZone.init(identifier:)) ?? .current
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timezone
        let now = Date()
        guard calendar.isDate(startAtUTC, inSameDayAs: now) else { return false }
        let hour = calendar.component(.hour, from: startAtUTC)
        return hour >= 17
    }

    private static func isTomorrow(_ event: ExternalEvent) -> Bool {
        guard let startAtUTC = event.startAtUTC else { return false }
        let timezone = event.timezone.flatMap(TimeZone.init(identifier:)) ?? .current
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timezone
        let tomorrow = calendar.date(byAdding: .day, value: 1, to: Date()) ?? Date()
        return calendar.isDate(startAtUTC, inSameDayAs: tomorrow)
    }

    private static func eventSearchHaystack(for event: ExternalEvent) -> String {
        ExternalEventSupport.normalizeToken([
            event.title,
            event.shortDescription,
            event.fullDescription,
            event.category,
            event.subcategory,
            event.organizerName,
            event.venueName,
            event.tags.joined(separator: " ")
        ]
        .compactMap { $0 }
        .joined(separator: " "))
    }

}
