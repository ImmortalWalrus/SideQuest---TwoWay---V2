import CoreLocation
import Foundation

actor ExternalLiveLocationDiscoveryService {
    static let shared = ExternalLiveLocationDiscoveryService(configuration: .fromEnvironment())

    enum DiscoveryMode: Sendable {
        case fast
        case preview
        case full
    }

    private let configuration: ExternalEventServiceConfiguration
    private let eventService: ExternalEventIngestionService
    private let venueService: ExternalVenueDiscoveryService
    private let googleReviewSession: URLSession
    private let sourcePageSession: URLSession
    private let googleReviewCacheFileURL: URL?
    private let googleReviewCacheTTL: TimeInterval
    #if os(macOS)
    private let headlessGoogleRatingsEnabled: Bool
    private let googleReviewChromeBinaryPath: String
    #endif
    private var googleReviewCache: [String: GoogleLocalReviewCacheEntry?] = [:]
    private var sourcePageImageCache: [String: String?] = [:]

    private struct GoogleLocalReviewLookup: Sendable {
        let cacheKey: String
        let venueName: String
        let addressLine1: String?
        let city: String?
        let state: String?
        let postalCode: String?
        let query: String
        let reviewURLs: [URL]
    }

    private struct GoogleLocalReviewSignal: Codable, Sendable {
        let rating: Double
        let reviewCount: Int?
        let reviewURL: String
    }

    private struct GoogleLocalReviewCacheEntry: Codable, Sendable {
        let signal: GoogleLocalReviewSignal
        let savedAt: Date
    }

    private struct SourcePageImageLookup: Sendable {
        let cacheKey: String
        let probeURL: URL
    }

    init(
        configuration: ExternalEventServiceConfiguration,
        eventService: ExternalEventIngestionService? = nil,
        venueService: ExternalVenueDiscoveryService? = nil
    ) {
        let environment = ProcessInfo.processInfo.environment
        self.configuration = configuration
        self.eventService = eventService ?? ExternalEventIngestionService(configuration: configuration)
        self.venueService = venueService ?? ExternalVenueDiscoveryService(configuration: configuration)
        let sessionConfiguration = URLSessionConfiguration.ephemeral
        sessionConfiguration.timeoutIntervalForRequest = 12
        sessionConfiguration.timeoutIntervalForResource = 20
        self.googleReviewSession = URLSession(configuration: sessionConfiguration)
        self.sourcePageSession = URLSession(configuration: sessionConfiguration)
        self.googleReviewCacheFileURL = Self.googleReviewCacheFileURL()
        self.googleReviewCacheTTL = Self.googleReviewCacheTTL(from: environment)
        #if os(macOS)
        self.headlessGoogleRatingsEnabled = Self.boolEnvironmentFlag(environment["SIDEQUEST_ENABLE_HEADLESS_GOOGLE_RATINGS"])
        self.googleReviewChromeBinaryPath = Self.googleReviewChromeBinaryPath(from: environment)
        #endif
        if let googleReviewCacheFileURL {
            self.googleReviewCache = Self.loadPersistedGoogleReviewCache(
                from: googleReviewCacheFileURL,
                maxAge: self.googleReviewCacheTTL
            )
        } else {
            self.googleReviewCache = [:]
        }
    }

    func discover(
        searchLocation: ExternalEventSearchLocation,
        forceRefresh: Bool = false,
        pageSize: Int = 12,
        sourcePageDepth: Int = 2,
        mode: DiscoveryMode = .full,
        intent: ExternalDiscoveryIntent = .nearbyWorthIt
    ) async -> ExternalLocationDiscoverySnapshot {
        let profiles = radiusProfiles(for: searchLocation, mode: mode, intent: intent)
        let allowedSources: Set<ExternalEventSource>? = switch mode {
        case .fast:
            ExternalEventIngestionService.fastPrimarySources(configuration: configuration)
        case .preview:
            ExternalEventIngestionService.fastPrimarySources(configuration: configuration)
        case .full:
            nil
        }
        guard let latitude = searchLocation.latitude, let longitude = searchLocation.longitude else {
            let query = ExternalEventQuery(
                countryCode: searchLocation.countryCode,
                city: searchLocation.city,
                state: searchLocation.state,
                postalCode: searchLocation.postalCode,
                latitude: nil,
                longitude: nil,
                radiusMiles: 12,
                keyword: nil,
                pageSize: pageSize,
                page: 0,
                sourcePageDepth: sourcePageDepth,
                includePast: false,
                hyperlocalRadiusMiles: 2,
                nightlifeRadiusMiles: 6,
                headlineRadiusMiles: 12,
                adaptiveRadiusExpansion: true,
                discoveryIntent: intent
            )
            let snapshot = await eventService.fetchAll(
                query: query,
                forceRefresh: forceRefresh,
                allowedSources: allowedSources
            )
            let venueNightEvents = Self.supplementalVenueNightEvents(from: [], around: searchLocation)
            let combinedEvents = ExternalEventIngestionService.dedupe(events: snapshot.mergedEvents + venueNightEvents)
            let enrichedEvents = Self.enrich(
                events: combinedEvents.events,
                with: [],
                around: searchLocation
            )
            let reviewEnrichedEvents = await enrichGoogleLocalReviews(in: enrichedEvents)
            let imageEnrichedEvents = await enrichMissingEventImages(in: reviewEnrichedEvents)
            let eventSnapshot = ExternalEventIngestionSnapshot(
                fetchedAt: snapshot.fetchedAt,
                query: snapshot.query,
                sourceResults: snapshot.sourceResults,
                mergedEvents: imageEnrichedEvents,
                dedupeGroups: snapshot.dedupeGroups + combinedEvents.groups
            )
            return ExternalLocationDiscoverySnapshot(
                fetchedAt: Date(),
                searchLocation: searchLocation,
                appliedProfiles: [ExternalRadiusExpansionProfile(step: 0, hyperlocalRadiusMiles: 2, nightlifeRadiusMiles: 6, headlineRadiusMiles: 12)],
                venueSnapshot: nil,
                eventSnapshot: eventSnapshot,
                mergedEvents: imageEnrichedEvents,
                notes: ["Fell back to city/state discovery because live coordinates were unavailable."]
            )
        }

        var mergedEventResults: [ExternalEventSourceResult] = []
        var mergedVenueResults: [ExternalVenueSourceResult] = []
        var appliedProfiles: [ExternalRadiusExpansionProfile] = []
        var notes: [String] = []
        var finalQuery: ExternalEventQuery?

        for profile in profiles {
            let eventQuery = ExternalEventQuery(
                countryCode: searchLocation.countryCode,
                city: searchLocation.city,
                state: searchLocation.state,
                postalCode: searchLocation.postalCode,
                latitude: latitude,
                longitude: longitude,
                radiusMiles: profile.headlineRadiusMiles,
                keyword: nil,
                pageSize: pageSize,
                page: 0,
                sourcePageDepth: sourcePageDepth,
                includePast: false,
                hyperlocalRadiusMiles: profile.hyperlocalRadiusMiles,
                nightlifeRadiusMiles: profile.nightlifeRadiusMiles,
                headlineRadiusMiles: profile.headlineRadiusMiles,
                adaptiveRadiusExpansion: true,
                discoveryIntent: intent
            )
            let venueQuery = ExternalVenueQuery(
                countryCode: searchLocation.countryCode,
                city: searchLocation.city,
                state: searchLocation.state,
                displayName: searchLocation.displayName,
                latitude: latitude,
                longitude: longitude,
                hyperlocalRadiusMiles: profile.hyperlocalRadiusMiles,
                nightlifeRadiusMiles: profile.nightlifeRadiusMiles,
                headlineRadiusMiles: profile.headlineRadiusMiles,
                adaptiveRadiusExpansion: true,
                pageSize: mode == .preview ? 6 : 24
            )

            async let eventSnapshotPass = eventService.fetchAll(
                query: eventQuery,
                forceRefresh: forceRefresh,
                allowedSources: allowedSources
            )

            let venueSnapshotResolved: ExternalVenueDiscoverySnapshot?
            switch mode {
            case .fast:
                venueSnapshotResolved = nil
            case .preview:
                venueSnapshotResolved = await venueService.discoverVenues(
                    query: venueQuery,
                    forceRefresh: forceRefresh,
                    mode: .baseOnly
                )
            case .full:
                venueSnapshotResolved = await venueService.discoverVenues(
                    query: venueQuery,
                    forceRefresh: forceRefresh,
                    mode: .full
                )
            }
            let eventSnapshotResolved = await eventSnapshotPass

            if let venueSnapshotResolved {
                mergedVenueResults = Self.mergeVenueResults(existing: mergedVenueResults, incoming: venueSnapshotResolved.sourceResults)
            }
            mergedEventResults = Self.mergeEventResults(existing: mergedEventResults, incoming: eventSnapshotResolved.sourceResults)
            appliedProfiles.append(profile)
            finalQuery = eventQuery

            let canonicalVenues = await enrichGoogleLocalReviews(
                in: ExternalVenueDiscoveryService.merge(mergedVenueResults.flatMap(\.venues))
            )
            let deduped = ExternalEventIngestionService.dedupe(events: mergedEventResults.flatMap(\.events))
            let venueNightEvents = Self.supplementalVenueNightEvents(from: canonicalVenues, around: searchLocation)
            let combinedEvents = ExternalEventIngestionService.dedupe(events: deduped.events + venueNightEvents)
            let enrichedEvents = Self.enrich(
                events: combinedEvents.events,
                with: canonicalVenues,
                around: searchLocation
            )

            if shouldStopExpanding(events: enrichedEvents, venues: canonicalVenues, profile: profile, appliedProfiles: appliedProfiles) {
                let reviewEnrichedEvents = await enrichGoogleLocalReviews(in: enrichedEvents)
                let imageEnrichedEvents = await enrichMissingEventImages(in: reviewEnrichedEvents)
                let eventSnapshot = ExternalEventIngestionSnapshot(
                    fetchedAt: Date(),
                    query: finalQuery ?? eventQuery,
                    sourceResults: mergedEventResults,
                    mergedEvents: imageEnrichedEvents,
                    dedupeGroups: deduped.groups + combinedEvents.groups
                )
                return ExternalLocationDiscoverySnapshot(
                    fetchedAt: Date(),
                    searchLocation: searchLocation,
                    appliedProfiles: appliedProfiles,
                    venueSnapshot: mode == .fast ? nil : ExternalVenueDiscoverySnapshot(
                        fetchedAt: Date(),
                        query: venueQuery,
                        sourceResults: mergedVenueResults,
                        venues: canonicalVenues
                    ),
                    eventSnapshot: eventSnapshot,
                    mergedEvents: imageEnrichedEvents,
                    notes: notes
                )
            }

            if profile != profiles.last {
                notes.append(
                    "Expanded search radii to \(Int(profile.headlineRadiusMiles)) miles headline coverage because early passes were too sparse."
                )
            }
        }

        let canonicalVenues = await enrichGoogleLocalReviews(
            in: ExternalVenueDiscoveryService.merge(mergedVenueResults.flatMap(\.venues))
        )
        let deduped = ExternalEventIngestionService.dedupe(events: mergedEventResults.flatMap(\.events))
        let venueNightEvents = Self.supplementalVenueNightEvents(from: canonicalVenues, around: searchLocation)
        let combinedEvents = ExternalEventIngestionService.dedupe(events: deduped.events + venueNightEvents)
        let enrichedEvents = Self.enrich(events: combinedEvents.events, with: canonicalVenues, around: searchLocation)
        let reviewEnrichedEvents = await enrichGoogleLocalReviews(in: enrichedEvents)
        let imageEnrichedEvents = await enrichMissingEventImages(in: reviewEnrichedEvents)
        let fallbackProfile = appliedProfiles.last ?? ExternalRadiusExpansionProfile(step: 0, hyperlocalRadiusMiles: 2, nightlifeRadiusMiles: 6, headlineRadiusMiles: 12)
        let eventSnapshot = ExternalEventIngestionSnapshot(
            fetchedAt: Date(),
            query: finalQuery ?? ExternalEventQuery(
                countryCode: searchLocation.countryCode,
                city: searchLocation.city,
                state: searchLocation.state,
                postalCode: searchLocation.postalCode,
                latitude: latitude,
                longitude: longitude,
                radiusMiles: fallbackProfile.headlineRadiusMiles,
                keyword: nil,
                pageSize: pageSize,
                page: 0,
                sourcePageDepth: sourcePageDepth,
                includePast: false,
                hyperlocalRadiusMiles: fallbackProfile.hyperlocalRadiusMiles,
                nightlifeRadiusMiles: fallbackProfile.nightlifeRadiusMiles,
                headlineRadiusMiles: fallbackProfile.headlineRadiusMiles,
                adaptiveRadiusExpansion: true,
                discoveryIntent: intent
            ),
            sourceResults: mergedEventResults,
            mergedEvents: imageEnrichedEvents,
            dedupeGroups: deduped.groups + combinedEvents.groups
        )
        return ExternalLocationDiscoverySnapshot(
            fetchedAt: Date(),
            searchLocation: searchLocation,
            appliedProfiles: appliedProfiles,
            venueSnapshot: mode == .fast ? nil : ExternalVenueDiscoverySnapshot(
                fetchedAt: Date(),
                query: ExternalVenueQuery(
                    countryCode: searchLocation.countryCode,
                    city: searchLocation.city,
                    state: searchLocation.state,
                    displayName: searchLocation.displayName,
                    latitude: latitude,
                    longitude: longitude,
                    hyperlocalRadiusMiles: fallbackProfile.hyperlocalRadiusMiles,
                    nightlifeRadiusMiles: fallbackProfile.nightlifeRadiusMiles,
                    headlineRadiusMiles: fallbackProfile.headlineRadiusMiles,
                    adaptiveRadiusExpansion: true,
                    pageSize: mode == .preview ? 6 : 24
                ),
                sourceResults: mergedVenueResults,
                venues: canonicalVenues
            ),
            eventSnapshot: eventSnapshot,
            mergedEvents: imageEnrichedEvents,
            notes: notes
        )
    }

    private func enrichGoogleLocalReviews(in events: [ExternalEvent]) async -> [ExternalEvent] {
        var lookupsByKey: [String: GoogleLocalReviewLookup] = [:]
        for event in events {
            guard let lookup = reviewLookup(for: event) else { continue }
            if lookupsByKey[lookup.cacheKey] == nil {
                lookupsByKey[lookup.cacheKey] = lookup
            }
        }
        let signalsByKey = await googleLocalReviewSignals(for: Array(lookupsByKey.values))

        return events.map { event in
            guard let lookup = reviewLookup(for: event),
                  let signal = signalsByKey[lookup.cacheKey]
            else {
                return event
            }
            return Self.applyGoogleLocalReviewSignal(signal, to: event)
        }
    }

    private func enrichGoogleLocalReviews(in venues: [ExternalVenue]) async -> [ExternalVenue] {
        var lookupsByKey: [String: GoogleLocalReviewLookup] = [:]
        for venue in venues {
            guard let lookup = reviewLookup(for: venue) else { continue }
            if lookupsByKey[lookup.cacheKey] == nil {
                lookupsByKey[lookup.cacheKey] = lookup
            }
        }
        let signalsByKey = await googleLocalReviewSignals(for: Array(lookupsByKey.values))

        return venues.map { venue in
            guard let lookup = reviewLookup(for: venue),
                  let signal = signalsByKey[lookup.cacheKey]
            else {
                return venue
            }
            return Self.applyGoogleLocalReviewSignal(signal, to: venue)
        }
    }

    private func googleLocalReviewSignals(
        for lookups: [GoogleLocalReviewLookup]
    ) async -> [String: GoogleLocalReviewSignal] {
        guard !lookups.isEmpty else { return [:] }

        var signalsByKey: [String: GoogleLocalReviewSignal] = [:]
        var unresolvedLookups: [GoogleLocalReviewLookup] = []
        var shouldPersistGoogleReviewCache = false

        for lookup in lookups {
            if let cachedEntry = googleReviewCache[lookup.cacheKey] {
                if let cachedEntry {
                    if Self.googleReviewSignalMatchesLookup(cachedEntry.signal, lookup: lookup) {
                        signalsByKey[lookup.cacheKey] = cachedEntry.signal
                    } else {
                        googleReviewCache.removeValue(forKey: lookup.cacheKey)
                        unresolvedLookups.append(lookup)
                        shouldPersistGoogleReviewCache = true
                    }
                }
            } else {
                unresolvedLookups.append(lookup)
            }
        }

        if !unresolvedLookups.isEmpty {
            for lookup in unresolvedLookups {
                let signal = await fetchGoogleLocalReviewSignal(for: lookup)
                let cacheKey = lookup.cacheKey
                if let signal {
                    let cacheEntry = GoogleLocalReviewCacheEntry(signal: signal, savedAt: Date())
                    googleReviewCache[cacheKey] = cacheEntry
                    signalsByKey[cacheKey] = signal
                    shouldPersistGoogleReviewCache = true
                } else {
                    googleReviewCache[cacheKey] = .some(nil)
                }
            }
            if shouldPersistGoogleReviewCache {
                persistGoogleReviewCache()
            }
        }

        return signalsByKey
    }

    private func enrichMissingEventImages(in events: [ExternalEvent]) async -> [ExternalEvent] {
        var lookupsByKey: [String: SourcePageImageLookup] = [:]
        for event in events {
            guard let lookup = sourcePageImageLookup(for: event) else { continue }
            if lookupsByKey[lookup.cacheKey] == nil {
                lookupsByKey[lookup.cacheKey] = lookup
            }
            if lookupsByKey.count >= 18 {
                break
            }
        }

        let lookups = Array(lookupsByKey.values)
        guard !lookups.isEmpty else { return events }

        var imageURLsByKey: [String: String] = [:]
        var unresolvedLookups: [SourcePageImageLookup] = []

        for lookup in lookups {
            if let cached = sourcePageImageCache[lookup.cacheKey] {
                if let cached, !cached.isEmpty {
                    imageURLsByKey[lookup.cacheKey] = cached
                }
            } else {
                unresolvedLookups.append(lookup)
            }
        }

        if !unresolvedLookups.isEmpty {
            let session = sourcePageSession
            for lookup in unresolvedLookups {
                let imageURL = await Self.fetchSourcePageImageURL(from: lookup.probeURL, session: session)
                sourcePageImageCache[lookup.cacheKey] = imageURL
                if let imageURL, !imageURL.isEmpty {
                    imageURLsByKey[lookup.cacheKey] = imageURL
                }
            }
        }

        return events.map { event in
            guard let lookup = sourcePageImageLookup(for: event),
                  let imageURL = imageURLsByKey[lookup.cacheKey]
            else {
                return event
            }
            return Self.applySourcePageImageURL(imageURL, to: event)
        }
    }

    nonisolated static func enrich(
        events: [ExternalEvent],
        with venues: [ExternalVenue],
        around searchLocation: ExternalEventSearchLocation
    ) -> [ExternalEvent] {
        let canonicalVenues = ExternalVenueDiscoveryService.merge(venues)
        return events
            .map { event in
                var enriched = event
                for venue in matchingVenues(for: event, venues: canonicalVenues) {
                    enriched = applyVenue(venue, to: enriched)
                }
                enriched.distanceFromUser = distanceFromUser(for: enriched, searchLocation: searchLocation)
                if let sourceConfidence = enriched.sourceConfidence, let venueSignalScore = enriched.venueSignalScore {
                    enriched.crossSourceConfirmationScore = max(enriched.crossSourceConfirmationScore ?? 0, sourceConfidence + venueSignalScore / 10.0 + Double(max(enriched.mergedSources.count - 1, 0)))
                }
                return enriched
            }
            .sorted { lhs, rhs in
                switch (lhs.distanceFromUser, rhs.distanceFromUser) {
                case let (left?, right?):
                    if left == right {
                        return (lhs.startAtUTC ?? .distantFuture) < (rhs.startAtUTC ?? .distantFuture)
                    }
                    return left < right
                case (.some, nil):
                    return true
                case (nil, .some):
                    return false
                case (nil, nil):
                    return (lhs.startAtUTC ?? .distantFuture) < (rhs.startAtUTC ?? .distantFuture)
                }
            }
    }

    private func radiusProfiles(
        for searchLocation: ExternalEventSearchLocation,
        mode: DiscoveryMode,
        intent: ExternalDiscoveryIntent
    ) -> [ExternalRadiusExpansionProfile] {
        let state = ExternalEventSupport.normalizeStateToken(searchLocation.state)
        let likelyDense = ["ca", "ny", "fl", "il", "tx", "nv"].contains(state)
        let needsHeadlineExpansion = intent == .biggestTonight

        if mode == .preview {
            return [
                ExternalRadiusExpansionProfile(
                    step: 0,
                    hyperlocalRadiusMiles: 2,
                    nightlifeRadiusMiles: 6,
                    headlineRadiusMiles: needsHeadlineExpansion ? 14 : 12
                )
            ]
        }

        if mode == .fast {
            if likelyDense && !needsHeadlineExpansion {
                return [
                    ExternalRadiusExpansionProfile(step: 0, hyperlocalRadiusMiles: 2, nightlifeRadiusMiles: 6, headlineRadiusMiles: 12)
                ]
            }
            return [
                ExternalRadiusExpansionProfile(step: 0, hyperlocalRadiusMiles: 2, nightlifeRadiusMiles: 6, headlineRadiusMiles: needsHeadlineExpansion ? 14 : 12),
                ExternalRadiusExpansionProfile(step: 1, hyperlocalRadiusMiles: 4, nightlifeRadiusMiles: 10, headlineRadiusMiles: needsHeadlineExpansion ? 24 : 20)
            ]
        }
        if likelyDense {
            return [
                ExternalRadiusExpansionProfile(step: 0, hyperlocalRadiusMiles: 2, nightlifeRadiusMiles: 6, headlineRadiusMiles: needsHeadlineExpansion ? 14 : 12),
                ExternalRadiusExpansionProfile(step: 1, hyperlocalRadiusMiles: 4, nightlifeRadiusMiles: 10, headlineRadiusMiles: needsHeadlineExpansion ? 24 : 20)
            ]
        }
        return [
            ExternalRadiusExpansionProfile(step: 0, hyperlocalRadiusMiles: 2, nightlifeRadiusMiles: 6, headlineRadiusMiles: needsHeadlineExpansion ? 14 : 12),
            ExternalRadiusExpansionProfile(step: 1, hyperlocalRadiusMiles: 4, nightlifeRadiusMiles: 10, headlineRadiusMiles: needsHeadlineExpansion ? 24 : 20),
            ExternalRadiusExpansionProfile(step: 2, hyperlocalRadiusMiles: 6, nightlifeRadiusMiles: 14, headlineRadiusMiles: needsHeadlineExpansion ? 36 : 32)
        ]
    }

    private func shouldStopExpanding(
        events: [ExternalEvent],
        venues: [ExternalVenue],
        profile: ExternalRadiusExpansionProfile,
        appliedProfiles: [ExternalRadiusExpansionProfile]
    ) -> Bool {
        let highSignal = events.filter {
            ExternalEventSupport.isHighSignalLocalEvent($0)
                || ExternalEventSupport.prominenceSignalScore(for: $0) >= 28
        }
        let mainstream = events.filter {
            switch $0.eventType {
            case .sportsEvent, .concert, .partyNightlife, .weekendActivity, .socialCommunityEvent:
                return true
            case .groupRun, .race5k, .race10k, .raceHalfMarathon, .raceMarathon, .otherLiveEvent:
                return false
            }
        }
        if highSignal.count >= 10 && mainstream.count >= 18 {
            return true
        }
        if mainstream.count >= 24 {
            return true
        }
        if venues.count >= 12 && mainstream.count >= 14 && appliedProfiles.count >= 2 {
            return true
        }
        return profile.step >= 2
    }

    private nonisolated static func supplementalVenueNightEvents(
        from venues: [ExternalVenue],
        around searchLocation: ExternalEventSearchLocation
    ) -> [ExternalEvent] {
        let preferredCity = ExternalEventSupport.normalizeToken(searchLocation.city)
        let preferredState = ExternalEventSupport.normalizeStateToken(searchLocation.state)

        return venues
            .filter { shouldCreateVenueNightEvent(from: $0) }
            .sorted { lhs, rhs in
                let left = venueNightRankScore(for: lhs, preferredCity: preferredCity, preferredState: preferredState)
                let right = venueNightRankScore(for: rhs, preferredCity: preferredCity, preferredState: preferredState)
                if left == right {
                    return lhs.name < rhs.name
                }
                    return left > right
                }
            .prefix(72)
            .map { venue in
                let eventSource = preferredEventSource(for: venue)
                let mergedSources = Array(Set([eventSource, venue.source])).sorted { $0.rawValue < $1.rawValue }
                let shortDescription = venueNightDescription(for: venue)
                let fullDescription = venueNightLongDescription(for: venue)
                let sourceURL = preferredNightlifeSourceURL(for: venue)
                let schedule = venueNightSchedule(for: venue, around: searchLocation)
                let venuePayload = payloadDictionary(from: venue.rawSourcePayload)
                var tags = [venue.reservationProvider, venue.sourceCoverageStatus, venue.neighborhood, venue.city].compactMap { value -> String? in
                    guard let value, !value.isEmpty else { return nil }
                    return value
                }
                if venue.guestListAvailable == true { tags.append("guest list") }
                if venue.bottleServiceAvailable == true { tags.append("bottle service") }
                if venue.dressCodeText != nil { tags.append("dress code") }
                if venue.ageMinimum == 21 { tags.append("21+") }

                return ExternalEvent(
                    id: "\(eventSource.rawValue):venue-night:\(venue.sourceVenueID)",
                    source: eventSource,
                    sourceEventID: "venue-night:\(venue.sourceVenueID)",
                    sourceParentID: venue.canonicalVenueID ?? venue.sourceVenueID,
                    sourceURL: sourceURL,
                    mergedSources: mergedSources,
                    title: venueTitle(for: venue),
                    shortDescription: shortDescription,
                    fullDescription: fullDescription,
                    category: "Nightlife",
                    subcategory: venue.venueType?.rawValue.replacingOccurrences(of: "_", with: " "),
                    eventType: .partyNightlife,
                    startAtUTC: schedule.startAtUTC,
                    endAtUTC: schedule.endAtUTC,
                    startLocal: schedule.startLocal,
                    endLocal: schedule.endLocal,
                    timezone: schedule.timezoneID,
                    salesStartAtUTC: nil,
                    salesEndAtUTC: nil,
                    venueName: venue.name,
                    venueID: venue.sourceVenueID,
                    addressLine1: venue.addressLine1,
                    addressLine2: venue.addressLine2,
                    city: venue.city,
                    state: venue.state,
                    postalCode: venue.postalCode,
                    country: venue.country,
                    latitude: venue.latitude,
                    longitude: venue.longitude,
                    imageURL: ExternalEventSupport.preferredNightlifeImageURL(
                        primary: venue.imageURL,
                        payload: venue.rawSourcePayload
                    ),
                    fallbackThumbnailAsset: ExternalEventSupport.fallbackThumbnailAsset(for: .partyNightlife),
                    status: .scheduled,
                    availabilityStatus: venue.reservationURL != nil ? .available : .unknown,
                    urgencyBadge: nil,
                    socialProofCount: nil,
                    socialProofLabel: nil,
                    venuePopularityCount: venue.venuePopularityCount ?? venueReviewCount(from: venuePayload),
                    venueRating: venue.venueRating ?? venueRating(from: venuePayload),
                    ticketProviderCount: nil,
                    priceMin: venue.coverPrice ?? venue.tableMinPrice,
                    priceMax: venue.tableMinPrice ?? venue.coverPrice,
                    currency: (venue.coverPrice != nil || venue.tableMinPrice != nil) ? "USD" : nil,
                    organizerName: nil,
                    organizerEventCount: nil,
                    organizerVerified: nil,
                    tags: Array(Set(tags)).sorted(),
                    distanceValue: nil,
                    distanceUnit: nil,
                    raceType: nil,
                    registrationURL: nil,
                    ticketURL: nil,
                    rawSourcePayload: venue.rawSourcePayload,
                    sourceType: eventSourceType(for: eventSource),
                    recordKind: .venueNight,
                    neighborhood: venue.neighborhood,
                    reservationURL: venue.reservationURL,
                    artistsOrTeams: [],
                    ageMinimum: venue.ageMinimum,
                    doorPolicyText: venue.doorPolicyText,
                    dressCodeText: venue.dressCodeText,
                    guestListAvailable: venue.guestListAvailable,
                    bottleServiceAvailable: venue.bottleServiceAvailable,
                    tableMinPrice: venue.tableMinPrice,
                    coverPrice: venue.coverPrice,
                    openingHoursText: schedule.scheduleText ?? venue.openingHoursText,
                    sourceConfidence: max(venue.sourceConfidence ?? 0, 0.68),
                    popularityScoreRaw: venue.prestigeDemandScore,
                    venueSignalScore: venue.venueSignalScore,
                    exclusivityScore: venue.nightlifeSignalScore,
                    trendingScore: venue.recurringEventPatternConfidence,
                    crossSourceConfirmationScore: max(venue.sourceConfidence ?? 0, 0.6),
                    distanceFromUser: nil,
                    entryPolicySummary: venue.entryPolicySummary,
                    womenEntryPolicyText: venue.womenEntryPolicyText,
                    menEntryPolicyText: venue.menEntryPolicyText,
                    exclusivityTierLabel: venue.exclusivityTierLabel
                )
            }
    }

    private nonisolated static func shouldCreateVenueNightEvent(from venue: ExternalVenue) -> Bool {
        guard isLikelyVenueNightName(venue.name),
              !isGenericVenueNightName(venue.name)
        else {
            return false
        }
        let venueStrength = (venue.nightlifeSignalScore ?? 0) + (venue.prestigeDemandScore ?? 0) + (venue.venueSignalScore ?? 0)
        let hasActionableMetadata = venue.reservationURL != nil
            || venue.guestListAvailable == true
            || venue.bottleServiceAvailable == true
            || venue.tableMinPrice != nil
            || venue.coverPrice != nil
            || venue.doorPolicyText != nil
            || venue.dressCodeText != nil
            || venue.openingHoursText != nil
        let coverageHaystack = nightlifeCoverageHaystack(for: venue)
        let hasStrongNightlifeIdentity = hasStrongNightlifeIdentity(venue, coverageHaystack: coverageHaystack)
        if isHotelLikeVenue(venue, coverageHaystack: coverageHaystack),
           !hasStrongNightlifeIdentity {
            return false
        }
        let hasPremiumAggregatorSignal = coverageHaystack.contains("discotech")
            || coverageHaystack.contains("clubbable")
        let hasConcreteVenueIdentity = venue.addressLine1 != nil
            || venue.reservationURL != nil
            || venue.officialSiteURL != nil
        let hasActionableDoorOrSchedule = venue.guestListAvailable == true
            || venue.bottleServiceAvailable == true
            || venue.tableMinPrice != nil
            || venue.coverPrice != nil
            || sanitizedVenueHoursText(venue.openingHoursText) != nil

        if !hasConcreteVenueIdentity && !hasActionableDoorOrSchedule {
            return false
        }

        switch venue.venueType {
        case .nightlifeVenue, .lounge:
            return hasActionableMetadata
                || hasPremiumAggregatorSignal
                || ((venue.officialSiteURL != nil || venue.reservationProvider != nil) && venueStrength >= 10)
        case .bar:
            return (hasActionableMetadata || hasPremiumAggregatorSignal) && venueStrength >= 9
        case .concertVenue, .comedyClub:
            return (hasActionableMetadata || hasPremiumAggregatorSignal) && venueStrength >= 10
        default:
            return false
        }
    }

    private nonisolated static func venueNightSchedule(
        for venue: ExternalVenue,
        around searchLocation: ExternalEventSearchLocation
    ) -> (
        startAtUTC: Date?,
        endAtUTC: Date?,
        startLocal: String?,
        endLocal: String?,
        timezoneID: String,
        scheduleText: String?
    ) {
        let timezoneID = venueNightTimeZoneIdentifier(
            for: venue,
            fallbackTimezoneID: nil,
            fallbackLatitude: searchLocation.latitude,
            fallbackLongitude: searchLocation.longitude
        )
        return resolvedVenueNightSchedule(
            for: venue,
            timezoneID: timezoneID,
            fallbackBaseDate: nil
        )
    }

    private nonisolated static func venueNightSchedule(
        for venue: ExternalVenue,
        fallbackEvent event: ExternalEvent
    ) -> (
        startAtUTC: Date?,
        endAtUTC: Date?,
        startLocal: String?,
        endLocal: String?,
        timezoneID: String,
        scheduleText: String?
    ) {
        let timezoneID = venueNightTimeZoneIdentifier(
            for: venue,
            fallbackTimezoneID: event.timezone,
            fallbackLatitude: event.latitude,
            fallbackLongitude: event.longitude
        )
        return resolvedVenueNightSchedule(
            for: venue,
            timezoneID: timezoneID,
            fallbackBaseDate: fallbackScheduleBaseDate(for: event, timezoneID: timezoneID)
        )
    }

    private nonisolated static func resolvedVenueNightSchedule(
        for venue: ExternalVenue,
        timezoneID: String,
        fallbackBaseDate: Date?
    ) -> (
        startAtUTC: Date?,
        endAtUTC: Date?,
        startLocal: String?,
        endLocal: String?,
        timezoneID: String,
        scheduleText: String?
    ) {
        let payload = payloadDictionary(from: venue.rawSourcePayload)
        if let structuredStart = stringValue(from: payload["clubbable_start_local"]),
           let structuredSchedule = structuredVenueNightSchedule(
                startLocal: structuredStart,
                endLocal: stringValue(from: payload["clubbable_end_local"]),
                timezoneID: timezoneID
           ) {
            return (
                startAtUTC: structuredSchedule.startAtUTC,
                endAtUTC: structuredSchedule.endAtUTC,
                startLocal: structuredSchedule.startLocal,
                endLocal: structuredSchedule.endLocal,
                timezoneID: timezoneID,
                scheduleText: stringValue(from: payload["clubbable_time_range"])
            )
        }
        let candidates = uniqueLines([
            stringValue(from: payload["clubbable_schedule_display"]),
            stringValue(from: payload["clubbable_time_range"]),
            stringValue(from: payload["discotech_open_answer"]),
            stringValue(from: payload["apple_maps_hours_text"]),
            stringValue(from: payload["apple_maps_schedule_text"]),
            stringValue(from: payload["official_site_hours"]),
            venue.openingHoursText
        ].compactMap { sanitizedVenueHoursText($0) })

        for candidate in candidates {
            if let parsed = parsedVenueNightSchedule(
                from: candidate,
                timezoneID: timezoneID,
                fallbackBaseDate: fallbackBaseDate
            ) {
                return (
                    startAtUTC: parsed.startAtUTC,
                    endAtUTC: parsed.endAtUTC,
                    startLocal: parsed.startLocal,
                    endLocal: parsed.endLocal,
                    timezoneID: timezoneID,
                    scheduleText: candidate
                )
            }
        }

        return (
            startAtUTC: nil,
            endAtUTC: nil,
            startLocal: nil,
            endLocal: nil,
            timezoneID: timezoneID,
            scheduleText: candidates.first
        )
    }

    private nonisolated static func structuredVenueNightSchedule(
        startLocal: String,
        endLocal: String?,
        timezoneID: String
    ) -> (
        startAtUTC: Date?,
        endAtUTC: Date?,
        startLocal: String,
        endLocal: String?
    )? {
        let timezone = TimeZone(identifier: timezoneID) ?? .current
        guard let startDate = parsedStructuredLocalDate(from: startLocal, timezone: timezone) else {
            return nil
        }
        let endDate = parsedStructuredLocalDate(from: endLocal, timezone: timezone)
        return (
            startAtUTC: startDate,
            endAtUTC: endDate,
            startLocal: startLocal,
            endLocal: endLocal
        )
    }

    private nonisolated static func parsedStructuredLocalDate(
        from value: String?,
        timezone: TimeZone
    ) -> Date? {
        guard let value, !value.isEmpty else { return nil }
        let formats = [
            "yyyy-MM-dd'T'HH:mm:ss",
            "yyyy-MM-dd'T'HH:mm",
            "yyyy-M-d'T'HH:mm:ss",
            "yyyy-M-d'T'HH:mm",
            "yyyy-MM-dd"
        ]
        for format in formats {
            let formatter = DateFormatter()
            formatter.locale = Locale(identifier: "en_US_POSIX")
            formatter.timeZone = timezone
            formatter.dateFormat = format
            if let date = formatter.date(from: value) {
                return date
            }
        }
        return nil
    }

    private nonisolated static func venueNightTimeZoneIdentifier(
        for venue: ExternalVenue,
        around searchLocation: ExternalEventSearchLocation
    ) -> String {
        venueNightTimeZoneIdentifier(
            for: venue,
            fallbackTimezoneID: nil,
            fallbackLatitude: searchLocation.latitude,
            fallbackLongitude: searchLocation.longitude
        )
    }

    private nonisolated static func venueNightTimeZoneIdentifier(
        for venue: ExternalVenue,
        fallbackTimezoneID: String?,
        fallbackLatitude: Double?,
        fallbackLongitude: Double?
    ) -> String {
        if let fallbackTimezoneID, !fallbackTimezoneID.isEmpty {
            return fallbackTimezoneID
        }
        if let latitude = venue.latitude, let longitude = venue.longitude {
            return ExternalEventSupport.timeZoneIdentifier(latitude: latitude, longitude: longitude)
        }
        if let latitude = fallbackLatitude, let longitude = fallbackLongitude {
            return ExternalEventSupport.timeZoneIdentifier(latitude: latitude, longitude: longitude)
        }
        return TimeZone.current.identifier
    }

    private nonisolated static func parsedVenueNightSchedule(
        from text: String,
        timezoneID: String,
        fallbackBaseDate: Date?
    ) -> (
        startAtUTC: Date?,
        endAtUTC: Date?,
        startLocal: String?,
        endLocal: String?
    )? {
        let plain = ExternalEventSupport.plainText(text) ?? text
        guard !plain.isEmpty,
              let startTime = firstTimeComponents(in: plain)
        else {
            return nil
        }

        let timezone = TimeZone(identifier: timezoneID) ?? .current
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timezone
        let now = Date()

        let baseDate = scheduleBaseDate(from: plain, now: now, calendar: calendar) ?? fallbackBaseDate ?? now
        guard var startDate = date(onSameDayAs: baseDate, hour: startTime.hour, minute: startTime.minute, calendar: calendar) else {
            return nil
        }

        let normalized = ExternalEventSupport.normalizeToken(plain)
        if normalized.contains("tonight"),
           startDate < now,
           let adjusted = calendar.date(byAdding: .day, value: 1, to: startDate) {
            startDate = adjusted
        }

        var endDate: Date?
        if let endTime = secondTimeComponents(in: plain),
           let builtEndDate = date(onSameDayAs: startDate, hour: endTime.hour, minute: endTime.minute, calendar: calendar) {
            endDate = builtEndDate <= startDate
                ? calendar.date(byAdding: .day, value: 1, to: builtEndDate)
                : builtEndDate
        }

        return (
            startAtUTC: startDate,
            endAtUTC: endDate,
            startLocal: localISODateTimeString(from: startDate, timezone: timezone),
            endLocal: endDate.map { localISODateTimeString(from: $0, timezone: timezone) }
        )
    }

    private nonisolated static func fallbackScheduleBaseDate(
        for event: ExternalEvent,
        timezoneID: String
    ) -> Date? {
        let timezone = TimeZone(identifier: timezoneID) ?? .current
        if let startLocal = event.startLocal,
           let parsed = parsedStructuredLocalDate(from: startLocal, timezone: timezone) {
            return parsed
        }
        return event.startAtUTC
    }

    private nonisolated static func preferredEventSource(for venue: ExternalVenue) -> ExternalEventSource {
        let coverageHaystack = nightlifeCoverageHaystack(for: venue)
        if venue.source == .nightlifeAggregator
            || coverageHaystack.contains("discotech")
            || coverageHaystack.contains("clubbable") {
            return .nightlifeAggregator
        }
        if venue.reservationURL != nil || venue.reservationProvider != nil {
            return .reservationProvider
        }
        if venue.doorPolicyText != nil || venue.dressCodeText != nil || venue.guestListAvailable == true || venue.bottleServiceAvailable == true {
            return .venueWebsite
        }
        return venue.source
    }

    private nonisolated static func eventSourceType(for source: ExternalEventSource) -> ExternalEventSourceType {
        switch source {
        case .nightlifeAggregator:
            return .nightlifeAggregator
        case .reservationProvider:
            return .reservationProvider
        case .venueWebsite:
            return .officialVenueWebsite
        case .appleMaps, .googlePlaces, .yelpFusion:
            return .venueDiscoveryAPI
        default:
            return .scraped
        }
    }

    private nonisolated static func venueNightRankScore(
        for venue: ExternalVenue,
        preferredCity: String,
        preferredState: String
    ) -> Double {
        var score = (venue.nightlifeSignalScore ?? 0) * 2.3
            + (venue.prestigeDemandScore ?? 0) * 1.5
            + (venue.venueSignalScore ?? 0) * 1.2
            + (venue.sourceConfidence ?? 0) * 10
        if venue.reservationURL != nil { score += 4 }
        if venue.guestListAvailable == true { score += 4 }
        if venue.bottleServiceAvailable == true { score += 5 }
        if venue.tableMinPrice != nil { score += 3 }
        let coverageHaystack = nightlifeCoverageHaystack(for: venue)
        if coverageHaystack.contains("discotech") { score += 6 }
        if coverageHaystack.contains("clubbable") { score += 6 }
        let hasWeakHWoodOnlyCoverage = (coverageHaystack.contains("hwood") || coverageHaystack.contains("rolodex"))
            && !coverageHaystack.contains("discotech")
            && !coverageHaystack.contains("clubbable")
        if hasWeakHWoodOnlyCoverage { score -= 7 }
        if isLikelyVenueNightName(venue.name) {
            if coverageHaystack.contains("clubbable") { score += 3.5 }
            if hasWeakHWoodOnlyCoverage { score -= 2.5 }
        } else {
            score -= 10
        }
        if isHyperExclusiveVenue(venue) { score += 8 }
        if ExternalEventSupport.normalizeToken(venue.city) == preferredCity { score += 4 }
        if ExternalEventSupport.normalizeStateToken(venue.state) == preferredState { score += 1.5 }
        return score
    }

    private nonisolated static func venueTitle(for venue: ExternalVenue) -> String {
        venue.name
    }

    private nonisolated static func venueNightDescription(for venue: ExternalVenue) -> String {
        var parts: [String] = []
        if let faqSummary = nightlifeFAQSummary(for: venue, maxParts: 2),
           ExternalEventSupport.hasSubstantiveNovelty(faqSummary, comparedTo: parts.map(Optional.some)) {
            parts.append(faqSummary)
        }
        if let vibeSummary = nightlifeVibeSummary(for: venue),
           ExternalEventSupport.hasSubstantiveNovelty(vibeSummary, comparedTo: parts.map(Optional.some)) {
            parts.append(vibeSummary)
        }
        if parts.isEmpty,
           let pricingLine = nightlifePricingSummary(for: venue),
           ExternalEventSupport.hasSubstantiveNovelty(pricingLine, comparedTo: parts.map(Optional.some)) {
            parts.append(pricingLine)
        }
        if parts.isEmpty,
           let accessLine = nightlifeAccessSummary(for: venue),
           ExternalEventSupport.hasSubstantiveNovelty(accessLine, comparedTo: parts.map(Optional.some)) {
            parts.append(accessLine)
        }
        return ExternalEventSupport.shortened(uniqueLines(parts).joined(separator: " "), maxLength: 200)
            ?? "Night out at \(venue.name)"
    }

    private nonisolated static func venueNightLongDescription(for venue: ExternalVenue) -> String {
        var parts: [String] = []
        if let faqSummary = nightlifeFAQSummary(for: venue, maxParts: 5),
           ExternalEventSupport.hasSubstantiveNovelty(faqSummary, comparedTo: parts.map(Optional.some)) {
            parts.append(faqSummary)
        }
        if let vibeSummary = nightlifeVibeSummary(for: venue),
           ExternalEventSupport.hasSubstantiveNovelty(vibeSummary, comparedTo: parts.map(Optional.some)) {
            parts.append(vibeSummary)
        }
        if let pricingLine = nightlifePricingSummary(for: venue),
           ExternalEventSupport.hasSubstantiveNovelty(pricingLine, comparedTo: parts.map(Optional.some)) {
            parts.append(pricingLine)
        }
        if parts.isEmpty,
           let accessLine = nightlifeAccessSummary(for: venue),
           ExternalEventSupport.hasSubstantiveNovelty(accessLine, comparedTo: parts.map(Optional.some)) {
            parts.append(accessLine)
        }
        return ExternalEventSupport.shortened(uniqueLines(parts).joined(separator: " "), maxLength: 560)
            ?? venueNightDescription(for: venue)
    }

    private nonisolated static func nightlifeVibeSummary(for venue: ExternalVenue) -> String? {
        let payload = payloadDictionary(from: venue.rawSourcePayload)
        let candidateTexts: [String] = [
            payload["clubbable_description"] as? String,
            stringValue(from: payload["discotech_insider_tips"]),
            payload["official_site_vibe"] as? String,
            payload["discotech_music_answer"] as? String,
            payload["discotech_best_nights"] as? String,
            payload["official_site_description"] as? String
        ]
        .compactMap { ExternalEventSupport.plainText($0) }

        let keywords = [
            "music", "dj", "hip hop", "r&b", "rb", "house", "edm", "latin",
            "dance floor", "crowd", "college", "student", "young", "celebrit",
            "rooftop", "cocktail", "supper club", "lounge", "dark", "upscale",
            "luxury", "intimate", "buzzy", "scene", "party"
        ]

        var selected: [String] = []
        for sentence in candidateTexts
            .flatMap(splitSentences)
            .filter(isUsefulNightlifeAboutSentence)
            .sorted(by: nightlifeSentenceSort) {
            let normalized = ExternalEventSupport.normalizeToken(sentence)
            guard keywords.contains(where: normalized.contains) else { continue }
            guard ExternalEventSupport.hasSubstantiveNovelty(
                sentence,
                comparedTo: selected.map(Optional.some)
            ) else {
                continue
            }
            selected.append(sentence)
            if selected.count == 2 {
                break
            }
        }

        guard !selected.isEmpty else { return nil }
        return ExternalEventSupport.shortened(selected.joined(separator: " "), maxLength: 240)
    }

    private nonisolated static func nightlifeAccessSummary(for venue: ExternalVenue) -> String? {
        var parts: [String] = []
        let explicitEntry = ExternalEventSupport.normalizeToken(
            [venue.entryPolicySummary, venue.doorPolicyText].compactMap { $0 }.joined(separator: " ")
        )
        if explicitEntry.contains("bottle service only")
            || explicitEntry.contains("does not have general admission") {
            parts.append("Bottle service is the real way in.")
        } else if venue.bottleServiceAvailable == true, venue.guestListAvailable == true {
            parts.append("Guest list and table booking are available.")
        } else if venue.bottleServiceAvailable == true {
            parts.append("Bottle service is available.")
        } else if venue.guestListAvailable == true {
            parts.append("Guest list is available.")
        }
        if let womenEntryPolicyText = venue.womenEntryPolicyText,
           ExternalEventSupport.hasSubstantiveNovelty(womenEntryPolicyText, comparedTo: [venue.entryPolicySummary, venue.doorPolicyText]) {
            parts.append("Women: \(womenEntryPolicyText)")
        }
        if let menEntryPolicyText = venue.menEntryPolicyText,
           ExternalEventSupport.hasSubstantiveNovelty(menEntryPolicyText, comparedTo: [venue.entryPolicySummary, venue.doorPolicyText, venue.womenEntryPolicyText]) {
            parts.append("Men: \(menEntryPolicyText)")
        }
        if let ageMinimum = venue.ageMinimum {
            parts.append("\(ageMinimum)+ venue.")
        }
        return uniqueLines(parts).isEmpty ? nil : uniqueLines(parts).joined(separator: " ")
    }

    private nonisolated static func nightlifePricingSummary(for venue: ExternalVenue) -> String? {
        let payload = payloadDictionary(from: venue.rawSourcePayload)
        var parts: [String] = []
        if let coverPrice = venue.coverPrice {
            if coverPrice == 0 {
                parts.append("No general-admission cover.")
            } else {
                parts.append("Cover \(formatCurrency(coverPrice)).")
            }
        }
        if let tableMinPrice = venue.tableMinPrice {
            parts.append("Tables from \(formatCurrency(tableMinPrice)).")
        }
        if parts.isEmpty,
           let priceRange = payload["official_site_price_range"] as? String,
           !priceRange.isEmpty {
            parts.append("Price range \(priceRange).")
        }
        return uniqueLines(parts).isEmpty ? nil : uniqueLines(parts).joined(separator: " ")
    }

    private nonisolated static func preferredNightlifeSynopsis(for venue: ExternalVenue) -> String? {
        let payload = payloadDictionary(from: venue.rawSourcePayload)
        let rawCandidates: [(source: String, text: String?)] = [
            ("discotech", stringValue(from: payload["discotech_insider_tips"])),
            ("discotech_music", payload["discotech_music_answer"] as? String),
            ("discotech_wait", payload["discotech_wait_answer"] as? String),
            ("discotech_drinks", payload["discotech_drinks_answer"] as? String),
            ("discotech_cover", payload["discotech_cover_answer"] as? String),
            ("discotech_best_nights", payload["discotech_best_nights"] as? String)
            ,("clubbable", payload["clubbable_description"] as? String),
            ("website", payload["official_site_vibe"] as? String),
            ("website", payload["official_site_description"] as? String)
        ]

        let scoredCandidates = rawCandidates.compactMap { candidate -> (text: String, score: Int)? in
            guard let cleaned = ExternalEventSupport.plainText(candidate.text), !cleaned.isEmpty else { return nil }
            guard isUsefulNightlifeAboutSentence(cleaned) else { return nil }
            let normalized = ExternalEventSupport.normalizeToken(cleaned)
            let venueToken = ExternalEventSupport.normalizeToken(venue.name)
            let cityToken = ExternalEventSupport.normalizeToken(venue.city)
            let stateToken = ExternalEventSupport.normalizeStateToken(venue.state)
            let neighborhoodToken = ExternalEventSupport.normalizeToken(venue.neighborhood)

            var score = 0
            switch candidate.source {
            case "discotech":
                score += 13
            case "discotech_music", "discotech_wait", "discotech_drinks":
                score += 11
            case "discotech_cover":
                score += 10
            case "clubbable":
                score += 9
            case "website":
                score += 6
            case "discotech_best_nights":
                score += 5
            default:
                break
            }

            if !venueToken.isEmpty, normalized.contains(venueToken) { score += 5 }
            if !cityToken.isEmpty, normalized.contains(cityToken) { score += 3 }
            if !neighborhoodToken.isEmpty, normalized.contains(neighborhoodToken) { score += 2 }
            if !stateToken.isEmpty, normalized.contains(stateToken) { score += 1 }

            let premiumTokens = [
                "exclusive", "celebrit", "luxur", "guest list", "bottle service",
                "hard door", "supper club", "vip", "hollywood", "a list", "hotspot"
            ]
            if premiumTokens.contains(where: normalized.contains) { score += 4 }
            let descriptiveTokens = [
                "music", "dj", "top 40", "hip hop", "r&b", "crowd", "dance", "vibe",
                "atmosphere", "cocktail", "rooftop", "dark", "upscale", "intimate", "scene"
            ]
            if descriptiveTokens.contains(where: normalized.contains) { score += 5 }
            if normalized.contains("highlighted in discotech s market guide")
                || normalized.contains("listed by h wood rolodex")
                || normalized.contains("recognized by h wood rolodex")
                || normalized.contains("member benefits")
                || normalized.contains("priority reservations")
                || normalized.contains("priority access")
                || normalized.contains("yourservice")
                || normalized.contains("apply make it a night") {
                score -= 10
            }
            score += min(cleaned.count / 55, 5)

            let outOfMarketTokens = [
                "london", "ibiza", "dubai", "paris", "miami beach", "new york", "las vegas", "san diego"
            ]
            if outOfMarketTokens.contains(where: normalized.contains)
                && (cityToken.isEmpty || !normalized.contains(cityToken)) {
                score -= 8
            }

            return (cleaned, score)
        }

        var selected: [String] = []
        for candidate in scoredCandidates.sorted(by: { lhs, rhs in
            lhs.score == rhs.score ? lhs.text.count > rhs.text.count : lhs.score > rhs.score
        }) {
            if let premiumSentence = premiumSynopsisSentence(from: candidate.text) {
                guard ExternalEventSupport.hasSubstantiveNovelty(
                    premiumSentence,
                    comparedTo: selected.map(Optional.some)
                ) else {
                    continue
                }
                selected.append(premiumSentence)
                if selected.count == 2 {
                    break
                }
            }
        }

        if !selected.isEmpty {
            return ExternalEventSupport.shortened(selected.joined(separator: " "), maxLength: 240)
        }

        if let coverage = venue.sourceCoverageStatus, !coverage.isEmpty {
            return nil
        }

        return nil
    }

    private nonisolated static func nightlifeFAQSummary(
        for venue: ExternalVenue,
        maxParts: Int
    ) -> String? {
        let payload = payloadDictionary(from: venue.rawSourcePayload)
        let candidates = nightlifeFAQFacts(from: payload)

        var selected: [String] = []
        for sentence in candidates {
            guard ExternalEventSupport.hasSubstantiveNovelty(
                sentence,
                comparedTo: selected.map(Optional.some)
            ) else {
                continue
            }
            selected.append(sentence.hasSuffix(".") ? sentence : sentence + ".")
            if selected.count == maxParts {
                break
            }
        }

        guard !selected.isEmpty else { return nil }
        return ExternalEventSupport.shortened(selected.joined(separator: " "), maxLength: maxParts <= 2 ? 220 : 560)
    }

    private nonisolated static func nightlifeFAQFacts(from payload: JSONDictionary) -> [String] {
        var facts: [String] = []

        func appendFact(_ rawValue: Any?, requireHoursSignal: Bool = false) {
            guard let cleaned = stringValue(from: rawValue).flatMap(ExternalEventSupport.plainText) else {
                return
            }

            for sentence in splitSentences(from: cleaned) {
                let normalized = ExternalEventSupport.normalizeToken(sentence)
                let blockedTokens = [
                    "get insider information",
                    "avoid problems at the door",
                    "our ultimate guide",
                    "general info",
                    "vip table bookings online",
                    "guest list vip table bookings online",
                    "request guest list",
                    "download the app",
                    "app store",
                    "contact us",
                    "submit",
                    "located between beverly hills and west hollywood",
                    "located in the heart",
                    "all the best vip nightclubs in london",
                    "all the promoters",
                    "club managers owners"
                ]
                guard !blockedTokens.contains(where: normalized.contains) else { continue }
                if requireHoursSignal, sanitizedVenueHoursText(sentence) == nil {
                    continue
                }
                facts.append(sentence.hasSuffix(".") ? sentence : sentence + ".")
            }
        }

        appendFact(payload["discotech_drinks_answer"])
        appendFact(payload["discotech_music_answer"])
        appendFact(payload["discotech_wait_answer"])
        appendFact(payload["discotech_cover_answer"])
        appendFact(payload["discotech_best_nights"])
        appendFact(payload["discotech_open_answer"], requireHoursSignal: true)
        appendFact(payload["clubbable_time_range"], requireHoursSignal: true)

        return uniqueLines(facts)
    }

    private nonisolated static func preferredNightlifeSourceURL(for venue: ExternalVenue) -> String? {
        let payload = payloadDictionary(from: venue.rawSourcePayload)
        let candidates = [
            payload["discotech_url"] as? String,
            payload["clubbable_url"] as? String,
            venue.reservationURL,
            payload["official_site_url"] as? String,
            venue.officialSiteURL
        ]
        return candidates
            .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .first(where: { !$0.isEmpty })
    }

    private nonisolated static func premiumSynopsisSentence(from text: String) -> String? {
        let cleaned = ExternalEventSupport.plainText(text) ?? text
        let sentences = cleaned
            .replacingOccurrences(of: "\n", with: " ")
            .components(separatedBy: CharacterSet(charactersIn: ".!?"))
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { sentence in
                let normalized = ExternalEventSupport.normalizeToken(sentence)
                guard sentence.count >= 20 else { return false }
                let blocked = [
                    "get insider information",
                    "avoid problems at the door",
                    "our ultimate guide",
                    "general info",
                    "buy tickets",
                    "photos and info",
                    "find the best promoters here",
                    "contact us",
                    "book tables directly",
                    "request guest list",
                    "download the app",
                    "app store",
                    "vip table bookings online",
                    "guest list vip table bookings online",
                    "bespoke membership",
                    "membership program",
                    "upcoming events at",
                    "where is",
                    "when is",
                    "how much do drinks cost",
                    "how much is cover charge"
                ]
                return !blocked.contains(where: normalized.contains)
                    && isUsefulNightlifeAboutSentence(sentence)
            }

        let premiumTokens = [
            "exclusive", "celebrit", "luxur", "guest list", "bottle service",
            "hard door", "supper club", "vip", "hollywood", "a-list", "hotspot"
        ]

        if let premium = sentences.first(where: { sentence in
            let normalized = ExternalEventSupport.normalizeToken(sentence)
            return premiumTokens.contains(where: normalized.contains)
        }) {
            return ExternalEventSupport.shortened(premium + ".", maxLength: 180)
        }

        guard let first = sentences.first else { return nil }
        return ExternalEventSupport.shortened(first + ".", maxLength: 160)
    }

    private nonisolated static func payloadDictionary(from rawPayload: String) -> JSONDictionary {
        guard let data = rawPayload.data(using: .utf8),
              let dictionary = try? JSONSerialization.jsonObject(with: data) as? JSONDictionary else {
            return [:]
        }
        return dictionary
    }

    private nonisolated static func splitSentences(from text: String) -> [String] {
        (ExternalEventSupport.plainText(text) ?? text)
            .replacingOccurrences(of: "\n", with: " ")
            .components(separatedBy: CharacterSet(charactersIn: ".!?"))
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .compactMap { sentence in
                guard sentence.count >= 18 else { return nil }
                return ExternalEventSupport.shortened(sentence + ".", maxLength: 180)
            }
    }

    private nonisolated static func nightlifeSentenceSort(lhs: String, rhs: String) -> Bool {
        func score(_ sentence: String) -> Int {
            let normalized = ExternalEventSupport.normalizeToken(sentence)
            var score = 0
            let premiumTokens = [
                "exclusive", "celebrit", "luxur", "upscale", "hotspot", "hard door", "guest list",
                "bottle service", "vip", "supper club", "rooftop", "cocktail", "dj", "music",
                "hip hop", "r&b", "house", "dance floor", "crowd", "college", "young"
            ]
            if premiumTokens.contains(where: normalized.contains) { score += 6 }
            score += min(sentence.count / 36, 4)
            return score
        }

        let leftScore = score(lhs)
        let rightScore = score(rhs)
        if leftScore == rightScore {
            return lhs.count > rhs.count
        }
        return leftScore > rightScore
    }

    private nonisolated static func isUsefulNightlifeAboutSentence(_ sentence: String) -> Bool {
        let normalized = ExternalEventSupport.normalizeToken(sentence)
        guard !normalized.isEmpty else { return false }

        let blockedTokens = [
            "highlighted in discotech s market guide",
            "listed by h wood rolodex",
            "recognized by h wood rolodex",
            "h wood rolodex",
            "bespoke membership",
            "membership program",
            "member benefits",
            "priority reservations",
            "priority access",
            "yourservice",
            "apply make it a night",
            "guest list access is available",
            "table bookings are available",
            "photos and info",
            "best promoters here",
            "ultimate guide",
            "general info",
            "vip table bookings online",
            "guest list vip table bookings online",
            "request guest list",
            "download the app",
            "app store",
            "contact us",
            "submit",
            "upcoming events at",
            "where is",
            "when is",
            "how much is cover charge",
            "how much do drinks cost",
            "all the best vip nightclubs in london",
            "all the promoters",
            "club managers owners"
        ]
        guard !blockedTokens.contains(where: normalized.contains) else { return false }

        let usefulTokens = [
            "music", "dj", "hip hop", "r&b", "top 40", "crowd", "dance", "vibe",
            "upscale", "luxury", "intimate", "rooftop", "cocktail", "dark", "scene",
            "celebrit", "a list", "supper club", "energy", "atmosphere"
        ]
        return usefulTokens.contains(where: normalized.contains) || sentence.count >= 90
    }

    private nonisolated static func stringValue(from value: Any?) -> String? {
        if let string = value as? String {
            return string
        }
        if let array = value as? [String] {
            let joined = array.joined(separator: ". ")
            return joined.isEmpty ? nil : joined
        }
        if let array = value as? [Any] {
            let joined = array.compactMap { $0 as? String }.joined(separator: ". ")
            return joined.isEmpty ? nil : joined
        }
        return nil
    }

    private nonisolated static func firstRegexMatchInText(
        _ text: String,
        pattern: String
    ) -> String? {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: []) else {
            return nil
        }
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        guard let match = regex.firstMatch(in: text, options: [], range: range),
              match.numberOfRanges > 0,
              let matchedRange = Range(match.range(at: 0), in: text)
        else {
            return nil
        }
        return String(text[matchedRange])
    }

    private nonisolated static func sanitizedVenueHoursText(_ value: String?) -> String? {
        guard let value = ExternalEventSupport.plainText(value), !value.isEmpty else { return nil }
        let normalized = ExternalEventSupport.normalizeToken(value)
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
            return nil
        }

        if let snippet = extractedVenueHoursSnippet(from: value) {
            return snippet
        }

        let weekdayTokens = [
            "monday", "tuesday", "wednesday", "thursday", "friday", "saturday", "sunday",
            "mon", "tue", "wed", "thu", "fri", "sat", "sun",
            "tonight", "today", "daily", "every day", "nightly"
        ]
        let timeTokens = ["open", "opens", "close", "closes", "hours", "until", "till", "pm", "am"]
        let compact = value.replacingOccurrences(of: "\n", with: " ").trimmingCharacters(in: .whitespacesAndNewlines)
        let hasClockTime = compact.range(
            of: #"(?i)\b\d{1,2}(?::\d{2})?\s*(?:am|pm)\b"#,
            options: .regularExpression
        ) != nil
        guard compact.count <= 80,
              hasClockTime,
              !compact.contains("."),
              !compact.contains("?"),
              !compact.contains("!"),
              weekdayTokens.contains(where: normalized.contains) || hasClockTime,
              timeTokens.contains(where: normalized.contains)
        else {
            return nil
        }
        return compact
    }

    private nonisolated static func extractedVenueHoursSnippet(from value: String) -> String? {
        let candidates = value
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
                if let match = firstRegexMatchInText(candidate, pattern: pattern) {
                    return match.trimmingCharacters(in: .whitespacesAndNewlines)
                }
            }
        }

        let sentenceCandidates = value
            .replacingOccurrences(of: "\n", with: " ")
            .components(separatedBy: CharacterSet(charactersIn: ".!?"))
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        for candidate in sentenceCandidates {
            for pattern in patterns {
                if let match = firstRegexMatchInText(candidate, pattern: pattern) {
                    return match.trimmingCharacters(in: .whitespacesAndNewlines)
                }
            }
        }

        return nil
    }

    private nonisolated static func firstTimeComponents(in text: String) -> (hour: Int, minute: Int)? {
        timeMatches(in: text).first
    }

    private nonisolated static func secondTimeComponents(in text: String) -> (hour: Int, minute: Int)? {
        let matches = timeMatches(in: text)
        guard matches.count > 1 else { return nil }
        return matches[1]
    }

    private nonisolated static func timeMatches(in text: String) -> [(hour: Int, minute: Int)] {
        guard let regex = try? NSRegularExpression(
            pattern: #"(?i)\b(\d{1,2})(?::(\d{2}))?\s*(am|pm)\b"#
        ) else {
            return []
        }

        let nsRange = NSRange(text.startIndex..<text.endIndex, in: text)
        return regex.matches(in: text, range: nsRange).compactMap { match in
            guard let hourRange = Range(match.range(at: 1), in: text),
                  let meridiemRange = Range(match.range(at: 3), in: text),
                  let hour = Int(text[hourRange]) else {
                return nil
            }
            let minute: Int
            if let minuteRange = Range(match.range(at: 2), in: text), !minuteRange.isEmpty {
                minute = Int(text[minuteRange]) ?? 0
            } else {
                minute = 0
            }
            let meridiem = text[meridiemRange].lowercased()
            var convertedHour = hour % 12
            if meridiem == "pm" {
                convertedHour += 12
            }
            return (convertedHour, minute)
        }
    }

    private nonisolated static func scheduleBaseDate(
        from text: String,
        now: Date,
        calendar: Calendar
    ) -> Date? {
        if let explicitDate = explicitMonthDayDate(from: text, now: now, calendar: calendar) {
            return explicitDate
        }

        let normalized = ExternalEventSupport.normalizeToken(text)
        if normalized.contains("tonight")
            || normalized.contains("today")
            || normalized.contains("daily")
            || normalized.contains("every day")
            || normalized.contains("nightly") {
            return now
        }

        if let weekdayDate = nextWeekdayDate(from: text, now: now, calendar: calendar) {
            return weekdayDate
        }

        return now
    }

    private nonisolated static func explicitMonthDayDate(
        from text: String,
        now: Date,
        calendar: Calendar
    ) -> Date? {
        guard let regex = try? NSRegularExpression(
            pattern: #"(?i)\b(jan(?:uary)?|feb(?:ruary)?|mar(?:ch)?|apr(?:il)?|may|jun(?:e)?|jul(?:y)?|aug(?:ust)?|sep(?:t(?:ember)?)?|oct(?:ober)?|nov(?:ember)?|dec(?:ember)?)\s+(\d{1,2})(?:,\s*(\d{4}))?"#
        ) else {
            return nil
        }

        guard let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..<text.endIndex, in: text)),
              let monthRange = Range(match.range(at: 1), in: text),
              let dayRange = Range(match.range(at: 2), in: text)
        else {
            return nil
        }

        let monthToken = text[monthRange].lowercased()
        let monthLookup: [String: Int] = [
            "jan": 1, "january": 1,
            "feb": 2, "february": 2,
            "mar": 3, "march": 3,
            "apr": 4, "april": 4,
            "may": 5,
            "jun": 6, "june": 6,
            "jul": 7, "july": 7,
            "aug": 8, "august": 8,
            "sep": 9, "sept": 9, "september": 9,
            "oct": 10, "october": 10,
            "nov": 11, "november": 11,
            "dec": 12, "december": 12
        ]
        guard let month = monthLookup[monthToken],
              let day = Int(text[dayRange])
        else {
            return nil
        }

        let year: Int
        if let yearRange = Range(match.range(at: 3), in: text), !yearRange.isEmpty {
            year = Int(text[yearRange]) ?? calendar.component(.year, from: now)
        } else {
            year = calendar.component(.year, from: now)
        }

        var components = calendar.dateComponents([.year, .month, .day], from: now)
        components.year = year
        components.month = month
        components.day = day
        return calendar.date(from: components)
    }

    private nonisolated static func nextWeekdayDate(
        from text: String,
        now: Date,
        calendar: Calendar
    ) -> Date? {
        let normalized = ExternalEventSupport.normalizeToken(text)
        let weekdayMap: [(tokens: [String], weekday: Int)] = [
            (["sunday", "sun"], 1),
            (["monday", "mon"], 2),
            (["tuesday", "tue"], 3),
            (["wednesday", "wed"], 4),
            (["thursday", "thu"], 5),
            (["friday", "fri"], 6),
            (["saturday", "sat"], 7)
        ]

        let presentWeekdays = weekdayMap.compactMap { entry -> Int? in
            entry.tokens.contains(where: normalized.contains) ? entry.weekday : nil
        }
        guard !presentWeekdays.isEmpty else {
            return nil
        }

        let currentWeekday = calendar.component(.weekday, from: now)
        let targetWeekday: Int
        if presentWeekdays.contains(currentWeekday) {
            targetWeekday = currentWeekday
        } else {
            targetWeekday = presentWeekdays.min(by: { lhs, rhs in
                let leftDelta = (lhs - currentWeekday + 7) % 7
                let rightDelta = (rhs - currentWeekday + 7) % 7
                return leftDelta < rightDelta
            }) ?? presentWeekdays[0]
        }

        let delta = (targetWeekday - currentWeekday + 7) % 7
        return calendar.date(byAdding: .day, value: delta, to: now)
    }

    private nonisolated static func date(
        onSameDayAs baseDate: Date,
        hour: Int,
        minute: Int,
        calendar: Calendar
    ) -> Date? {
        var components = calendar.dateComponents([.year, .month, .day], from: baseDate)
        components.hour = hour
        components.minute = minute
        components.second = 0
        return calendar.date(from: components)
    }

    private nonisolated static func localISODateTimeString(from date: Date, timezone: TimeZone) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = timezone
        formatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ss"
        return formatter.string(from: date)
    }

    private nonisolated static func nightlifeCoverageHaystack(for venue: ExternalVenue) -> String {
        let payload = payloadDictionary(from: venue.rawSourcePayload)
        let payloadText = payload
            .map { "\($0.key) \($0.value)" }
            .joined(separator: " ")
        return ExternalEventSupport.normalizeToken([
            venue.sourceCoverageStatus,
            payloadText,
            venue.doorPolicyText,
            venue.dressCodeText,
            venue.reservationProvider
        ]
        .compactMap { $0 }
        .joined(separator: " "))
    }

    private nonisolated static func isHyperExclusiveVenue(_ venue: ExternalVenue) -> Bool {
        let coverageHaystack = nightlifeCoverageHaystack(for: venue)
        if venue.bottleServiceAvailable == true, venue.guestListAvailable != true, (venue.tableMinPrice ?? 0) >= 1500 {
            return true
        }
        let premiumTokens = [
            "highly exclusive",
            "hard door",
            "bottle service only",
            "celebrities party",
            "a list",
            "hwood",
            "rolodex"
        ]
        return premiumTokens.contains(where: coverageHaystack.contains)
    }

    private nonisolated static func isHotelLikeVenue(
        _ venue: ExternalVenue,
        coverageHaystack: String
    ) -> Bool {
        let identityHaystack = ExternalEventSupport.normalizeToken([
            venue.name,
            venue.addressLine1,
            venue.officialSiteURL,
            coverageHaystack
        ]
        .compactMap { $0 }
        .joined(separator: " "))

        let hotelTokens = [
            "hotel",
            "resort",
            "inn",
            "suites",
            "guest room",
            "guestroom",
            "lobby"
        ]
        return hotelTokens.contains(where: identityHaystack.contains)
    }

    private nonisolated static func hasStrongNightlifeIdentity(
        _ venue: ExternalVenue,
        coverageHaystack: String
    ) -> Bool {
        let nightlifeTokens = [
            "nightclub",
            "night club",
            "guest list",
            "bottle service",
            "table service",
            "table minimum",
            "vip",
            "vip table",
            "hard door",
            "after hours",
            "afterhours",
            "dance floor",
            "live dj",
            "dj",
            "edm",
            "house music",
            "techno",
            "discotech",
            "clubbable"
        ]

        if nightlifeTokens.contains(where: coverageHaystack.contains) {
            return true
        }

        return venue.guestListAvailable == true
            || venue.bottleServiceAvailable == true
            || venue.tableMinPrice != nil
            || venue.doorPolicyText != nil
            || venue.dressCodeText != nil
            || venue.source == .nightlifeAggregator
    }

    private nonisolated static func isLikelyVenueNightName(_ value: String) -> Bool {
        let normalized = ExternalEventSupport.normalizeToken(value)
        guard !normalized.isEmpty else { return false }
        let blockedPhrases = [
            "promo code",
            "discount",
            "grand opening",
            "what are the best",
            "hottest clubs",
            "right now",
            "music festivals",
            "festival lineup",
            "festival",
            "guestlist",
            "guest list",
            "afterparty",
            "after party",
            "day party",
            "pool party",
            "circus",
            "weekender",
            "lineup",
            "guest list deals",
            "this thursday",
            "this friday",
            "this saturday",
            "this sunday"
        ]
        guard !blockedPhrases.contains(where: normalized.contains) else {
            return false
        }
        let words = normalized.split(separator: " ").map(String.init)
        return (1...5).contains(words.count)
    }

    private nonisolated static func isGenericVenueNightName(_ value: String) -> Bool {
        let normalized = ExternalEventSupport.normalizeToken(value)
        guard !normalized.isEmpty else { return true }

        let blockedExactNames = [
            "bar",
            "bar lounge",
            "lounge",
            "cocktail lounge",
            "hotel bar",
            "hotel lounge",
            "lobby bar",
            "lobby lounge",
            "rooftop",
            "rooftop bar",
            "rooftop lounge",
            "pool bar",
            "pool lounge",
            "restaurant",
            "restaurant lounge"
        ]
        if blockedExactNames.contains(normalized) {
            return true
        }

        let genericTokens = Set([
            "bar",
            "lounge",
            "cocktail",
            "rooftop",
            "lobby",
            "hotel",
            "restaurant",
            "pool",
            "club"
        ])
        let words = normalized.split(separator: " ").map(String.init)
        return !words.isEmpty && words.count <= 3 && Set(words).isSubset(of: genericTokens)
    }

    private nonisolated static func uniqueLines(_ values: [String]) -> [String] {
        ExternalEventSupport.uniqueMeaningfulLines(values.map(Optional.some))
    }

    private nonisolated static func formatCurrency(_ value: Double) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencyCode = "USD"
        formatter.maximumFractionDigits = value.rounded() == value ? 0 : 2
        return formatter.string(from: NSNumber(value: value)) ?? "$\(Int(value.rounded()))"
    }

    private nonisolated static func mergeEventResults(
        existing: [ExternalEventSourceResult],
        incoming: [ExternalEventSourceResult]
    ) -> [ExternalEventSourceResult] {
        let existingBySource = Dictionary(grouping: existing, by: \.source).mapValues(collapseEventSourceResults)
        let incomingBySource = Dictionary(grouping: incoming, by: \.source).mapValues(collapseEventSourceResults)

        return Set(existingBySource.keys).union(incomingBySource.keys)
            .sorted { $0.rawValue < $1.rawValue }
            .compactMap { source in
                switch (existingBySource[source], incomingBySource[source]) {
                case let (existing?, incoming?):
                    return ExternalEventSourceResult(
                        source: source,
                        usedCache: existing.usedCache && incoming.usedCache,
                        fetchedAt: max(existing.fetchedAt, incoming.fetchedAt),
                        endpoints: existing.endpoints + incoming.endpoints,
                        note: incoming.note ?? existing.note,
                        nextCursor: incoming.nextCursor ?? existing.nextCursor,
                        events: ExternalEventIngestionService.dedupe(events: existing.events + incoming.events).events
                    )
                case let (existing?, nil):
                    return existing
                case let (nil, incoming?):
                    return incoming
                case (nil, nil):
                    return nil
                }
            }
    }

    private nonisolated static func mergeVenueResults(
        existing: [ExternalVenueSourceResult],
        incoming: [ExternalVenueSourceResult]
    ) -> [ExternalVenueSourceResult] {
        let existingBySource = Dictionary(grouping: existing, by: \.source).mapValues(collapseVenueSourceResults)
        let incomingBySource = Dictionary(grouping: incoming, by: \.source).mapValues(collapseVenueSourceResults)

        return Set(existingBySource.keys).union(incomingBySource.keys)
            .sorted { $0.rawValue < $1.rawValue }
            .compactMap { source in
                switch (existingBySource[source], incomingBySource[source]) {
                case let (existing?, incoming?):
                    return ExternalVenueSourceResult(
                        source: source,
                        fetchedAt: max(existing.fetchedAt, incoming.fetchedAt),
                        endpoints: existing.endpoints + incoming.endpoints,
                        note: incoming.note ?? existing.note,
                        venues: ExternalVenueDiscoveryService.merge(existing.venues + incoming.venues)
                    )
                case let (existing?, nil):
                    return existing
                case let (nil, incoming?):
                    return incoming
                case (nil, nil):
                    return nil
                }
            }
    }

    private nonisolated static func collapseEventSourceResults(_ results: [ExternalEventSourceResult]) -> ExternalEventSourceResult {
        guard let first = results.first else {
            return ExternalEventSourceResult(
                source: .ticketmaster,
                usedCache: false,
                fetchedAt: Date(),
                endpoints: [],
                note: nil,
                nextCursor: nil,
                events: []
            )
        }

        return ExternalEventSourceResult(
            source: first.source,
            usedCache: results.allSatisfy(\.usedCache),
            fetchedAt: results.map(\.fetchedAt).max() ?? first.fetchedAt,
            endpoints: results.flatMap(\.endpoints),
            note: results.compactMap(\.note).last,
            nextCursor: results.compactMap(\.nextCursor).last,
            events: ExternalEventIngestionService.dedupe(events: results.flatMap(\.events)).events
        )
    }

    private nonisolated static func collapseVenueSourceResults(_ results: [ExternalVenueSourceResult]) -> ExternalVenueSourceResult {
        guard let first = results.first else {
            return ExternalVenueSourceResult(
                source: .appleMaps,
                fetchedAt: Date(),
                endpoints: [],
                note: nil,
                venues: []
            )
        }

        return ExternalVenueSourceResult(
            source: first.source,
            fetchedAt: results.map(\.fetchedAt).max() ?? first.fetchedAt,
            endpoints: results.flatMap(\.endpoints),
            note: results.compactMap(\.note).last,
            venues: ExternalVenueDiscoveryService.merge(results.flatMap(\.venues))
        )
    }

    private nonisolated static func matchingVenues(for event: ExternalEvent, venues: [ExternalVenue]) -> [ExternalVenue] {
        let eventVenueKey = ExternalEventSupport.normalizeToken(event.venueName ?? event.addressLine1)
        let eventAddressKey = ExternalEventSupport.normalizeToken(event.addressLine1)
        let eventCity = ExternalEventSupport.normalizeToken(event.city)
        let eventState = ExternalEventSupport.normalizeStateToken(event.state)
        let isNightlifeEvent = event.eventType == .partyNightlife || event.recordKind == .venueNight

        let candidates = venues.filter { venue in
            let venueKey = ExternalEventSupport.normalizeToken(venue.name)
            let venueAddressKey = ExternalEventSupport.normalizeToken(venue.addressLine1)
            let aliasMatch = venue.aliases.contains { alias in
                ExternalEventSupport.normalizeToken(alias) == eventVenueKey
            }
            let textualVenueMatch = !eventVenueKey.isEmpty
                && !venueKey.isEmpty
                && (venueKey == eventVenueKey || venueKey.contains(eventVenueKey) || eventVenueKey.contains(venueKey))
            let sameStreetAddress = !eventAddressKey.isEmpty
                && !venueAddressKey.isEmpty
                && eventAddressKey == venueAddressKey

            if textualVenueMatch || aliasMatch {
                return true
            }
            if let eventLatitude = event.latitude,
               let eventLongitude = event.longitude,
               let venueLatitude = venue.latitude,
               let venueLongitude = venue.longitude
            {
                let eventLocation = CLLocation(latitude: eventLatitude, longitude: eventLongitude)
                let venueLocation = CLLocation(latitude: venueLatitude, longitude: venueLongitude)
                let distanceMiles = eventLocation.distance(from: venueLocation) / 1609.344
                let coordinateThreshold = isNightlifeEvent ? 0.25 : 0.08
                let allowCoordinateOnlyMatch =
                    eventVenueKey.isEmpty
                    || textualVenueMatch
                    || aliasMatch
                    || sameStreetAddress
                if allowCoordinateOnlyMatch && distanceMiles <= coordinateThreshold {
                    return true
                }
            }
            if !eventCity.isEmpty,
               eventCity == ExternalEventSupport.normalizeToken(venue.city),
               eventState == ExternalEventSupport.normalizeStateToken(venue.state),
               !eventVenueKey.isEmpty {
                return venueKey.contains(eventVenueKey) || eventVenueKey.contains(venueKey)
            }
            return false
        }

        return candidates.sorted { lhs, rhs in
            let leftScore = (lhs.sourceConfidence ?? 0) + (lhs.nightlifeSignalScore ?? 0) + (lhs.prestigeDemandScore ?? 0)
            let rightScore = (rhs.sourceConfidence ?? 0) + (rhs.nightlifeSignalScore ?? 0) + (rhs.prestigeDemandScore ?? 0)
            if leftScore == rightScore {
                return (lhs.addressLine1 != nil ? 1 : 0) + (lhs.imageURL != nil ? 1 : 0) > (rhs.addressLine1 != nil ? 1 : 0) + (rhs.imageURL != nil ? 1 : 0)
            }
            return leftScore > rightScore
        }
    }

    private nonisolated static func applyVenue(_ venue: ExternalVenue, to event: ExternalEvent) -> ExternalEvent {
        var enriched = event
        let isNightlifeEvent = enriched.eventType == .partyNightlife || enriched.recordKind == .venueNight
        let venuePayload = payloadDictionary(from: venue.rawSourcePayload)
        enriched.mergedSources = Array(Set(event.mergedSources + [venue.source])).sorted { $0.rawValue < $1.rawValue }
        enriched.venueName = enriched.venueName ?? venue.name
        enriched.addressLine1 = ExternalEventSupport.preferredAddressLine(
            primary: enriched.addressLine1,
            primaryCity: enriched.city,
            primaryState: enriched.state,
            secondary: venue.addressLine1,
            secondaryCity: venue.city,
            secondaryState: venue.state
        )
        enriched.addressLine2 = enriched.addressLine2 ?? venue.addressLine2
        enriched.city = enriched.city ?? venue.city
        enriched.state = enriched.state ?? venue.state
        enriched.postalCode = enriched.postalCode ?? venue.postalCode
        enriched.country = enriched.country ?? venue.country
        enriched.latitude = enriched.latitude ?? venue.latitude
        enriched.longitude = enriched.longitude ?? venue.longitude
        enriched.neighborhood = enriched.neighborhood ?? venue.neighborhood
        enriched.sourceConfidence = max(enriched.sourceConfidence ?? 0, venue.sourceConfidence ?? 0)
        enriched.rawSourcePayload = ExternalEventSupport.mergedPayload(primary: enriched.rawSourcePayload, secondary: venue.rawSourcePayload)
        enriched.venueRating = enriched.venueRating ?? venue.venueRating ?? venueRating(from: venuePayload)
        enriched.venuePopularityCount = enriched.venuePopularityCount ?? venue.venuePopularityCount ?? venueReviewCount(from: venuePayload)
        if isNightlifeEvent {
            enriched.imageURL = ExternalEventSupport.preferredImageURL(primary: enriched.imageURL, secondary: venue.imageURL)
            enriched.reservationURL = enriched.reservationURL ?? venue.reservationURL
            enriched.ageMinimum = enriched.ageMinimum ?? venue.ageMinimum
            enriched.doorPolicyText = ExternalEventSupport.betterNightlifeText(primary: enriched.doorPolicyText, secondary: venue.doorPolicyText)
            enriched.dressCodeText = ExternalEventSupport.betterNightlifeText(primary: enriched.dressCodeText, secondary: venue.dressCodeText)
            enriched.guestListAvailable = enriched.guestListAvailable ?? venue.guestListAvailable
            enriched.bottleServiceAvailable = enriched.bottleServiceAvailable ?? venue.bottleServiceAvailable
            enriched.tableMinPrice = ExternalEventSupport.richerNightlifePrice(primary: enriched.tableMinPrice, secondary: venue.tableMinPrice)
            enriched.coverPrice = ExternalEventSupport.richerNightlifePrice(primary: enriched.coverPrice, secondary: venue.coverPrice)
            enriched.openingHoursText = ExternalEventSupport.betterNightlifeText(primary: enriched.openingHoursText, secondary: venue.openingHoursText)
            enriched.entryPolicySummary = ExternalEventSupport.betterNightlifeText(primary: enriched.entryPolicySummary, secondary: venue.entryPolicySummary)
            enriched.womenEntryPolicyText = ExternalEventSupport.betterNightlifeText(primary: enriched.womenEntryPolicyText, secondary: venue.womenEntryPolicyText)
            enriched.menEntryPolicyText = ExternalEventSupport.betterNightlifeText(primary: enriched.menEntryPolicyText, secondary: venue.menEntryPolicyText)
            enriched.exclusivityTierLabel = ExternalEventSupport.moreExclusiveTier(primary: enriched.exclusivityTierLabel, secondary: venue.exclusivityTierLabel)
            enriched.venueSignalScore = max(enriched.venueSignalScore ?? 0, venue.venueSignalScore ?? 0)
            enriched.popularityScoreRaw = max(enriched.popularityScoreRaw ?? 0, venue.prestigeDemandScore ?? 0)
            enriched.exclusivityScore = max(enriched.exclusivityScore ?? 0, venue.nightlifeSignalScore ?? 0)
            enriched.imageURL = ExternalEventSupport.preferredNightlifeImageURL(
                primary: enriched.imageURL,
                payload: enriched.rawSourcePayload
            )
            let venueSchedule = venueNightSchedule(for: venue, fallbackEvent: enriched)
            if shouldUpgradeNightlifeSchedule(for: enriched),
               venueSchedule.startAtUTC != nil || venueSchedule.startLocal != nil {
                enriched.startAtUTC = venueSchedule.startAtUTC ?? enriched.startAtUTC
                enriched.endAtUTC = venueSchedule.endAtUTC ?? enriched.endAtUTC
                enriched.startLocal = venueSchedule.startLocal ?? enriched.startLocal
                enriched.endLocal = venueSchedule.endLocal ?? enriched.endLocal
            } else {
                enriched.endAtUTC = enriched.endAtUTC ?? venueSchedule.endAtUTC
                enriched.endLocal = enriched.endLocal ?? venueSchedule.endLocal
            }
            if enriched.timezone == nil || enriched.timezone?.isEmpty == true {
                enriched.timezone = venueSchedule.timezoneID
            }
            if let scheduleText = venueSchedule.scheduleText {
                enriched.openingHoursText = ExternalEventSupport.betterNightlifeText(
                    primary: enriched.openingHoursText,
                    secondary: scheduleText
                )
            }
            enriched.shortDescription = ExternalEventSupport.betterNightlifeText(
                primary: enriched.shortDescription,
                secondary: venueNightDescription(for: venue)
            )
            enriched.fullDescription = ExternalEventSupport.betterNightlifeText(
                primary: enriched.fullDescription,
                secondary: venueNightLongDescription(for: venue)
            )
        }
        return enriched
    }

    private nonisolated static func venueRating(from payload: JSONDictionary) -> Double? {
        let nestedVenue = payload["venue"] as? JSONDictionary
        let nestedPlace = payload["place"] as? JSONDictionary
        let candidates: [Any?] = [
            payload["google_places_rating"],
            payload["google_rating"],
            payload["yelp_rating"],
            payload["venue_rating"],
            payload["rating"],
            nestedVenue?["rating"],
            nestedPlace?["rating"]
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

    private nonisolated static func venueReviewCount(from payload: JSONDictionary) -> Int? {
        let nestedVenue = payload["venue"] as? JSONDictionary
        let nestedPlace = payload["place"] as? JSONDictionary
        let candidates: [Any?] = [
            payload["google_places_user_rating_count"],
            payload["google_places_userRatingCount"],
            payload["userRatingCount"],
            payload["ratingCount"],
            payload["review_count"],
            payload["reviewCount"],
            payload["yelp_review_count"],
            payload["yelp_reviewCount"],
            payload["venue_reviews"],
            payload["reviews"],
            nestedVenue?["userRatingCount"],
            nestedVenue?["review_count"],
            nestedPlace?["userRatingCount"],
            nestedPlace?["review_count"]
        ]

        for candidate in candidates {
            if let count = ExternalEventSupport.parseInt(candidate), count > 0 {
                return count
            }
        }

        return nil
    }

    private func reviewLookup(for event: ExternalEvent) -> GoogleLocalReviewLookup? {
        guard Self.shouldScrapeGoogleReviews(for: event) else { return nil }
        if let venueRating = event.venueRating,
           venueRating >= 1.0,
           venueRating <= 5.0 {
            return nil
        }
        if let payloadRating = Self.venueRating(from: Self.payloadDictionary(from: event.rawSourcePayload)),
           payloadRating >= 1.0,
           payloadRating <= 5.0 {
            return nil
        }

        return reviewLookup(
            venueName: event.venueName ?? event.title,
            event.addressLine1,
            event.city,
            event.state,
            event.postalCode,
            rawPayload: event.rawSourcePayload
        )
    }

    private func reviewLookup(for venue: ExternalVenue) -> GoogleLocalReviewLookup? {
        guard Self.shouldScrapeGoogleReviews(for: venue) else { return nil }
        if let venueRating = venue.venueRating,
           venueRating >= 1.0,
           venueRating <= 5.0 {
            return nil
        }
        if let payloadRating = Self.venueRating(from: Self.payloadDictionary(from: venue.rawSourcePayload)),
           payloadRating >= 1.0,
           payloadRating <= 5.0 {
            return nil
        }

        return reviewLookup(
            venueName: venue.name,
            venue.addressLine1,
            venue.city,
            venue.state,
            venue.postalCode,
            rawPayload: venue.rawSourcePayload
        )
    }

    private nonisolated static func shouldScrapeGoogleReviews(for event: ExternalEvent) -> Bool {
        if event.status == .cancelled || event.status == .ended {
            return false
        }

        if event.eventType == .partyNightlife || event.recordKind == .venueNight {
            return !ExternalEventSupport.isLikelyClubLikeNightlifeVenue(event)
        }

        return true
    }

    private nonisolated static func shouldScrapeGoogleReviews(for venue: ExternalVenue) -> Bool {
        let haystack = ExternalEventSupport.normalizeToken(
            [venue.name, venue.sourceCoverageStatus, venue.rawSourcePayload]
                .compactMap { $0 }
                .joined(separator: " ")
        )
        let likelyClubLikeNightlifeVenue =
            venue.venueType == .nightlifeVenue
            && (
                haystack.contains("nightclub")
                || haystack.contains("night club")
                || haystack.contains("discotech")
                || haystack.contains("clubbable")
                || venue.guestListAvailable == true
                || venue.bottleServiceAvailable == true
                || venue.tableMinPrice != nil
                || venue.exclusivityTierLabel != nil
            )
        let blockedSignals = [
            "nightclub",
            "night club",
            "strip club",
            "gentlemen's club",
            "gentlemens club"
        ]
        if likelyClubLikeNightlifeVenue {
            return false
        }
        return !blockedSignals.contains(where: haystack.contains)
    }

    private func reviewLookup(
        venueName: String,
        _ addressLine1: String?,
        _ city: String?,
        _ state: String?,
        _ postalCode: String?,
        rawPayload: String
    ) -> GoogleLocalReviewLookup? {
        let payload = Self.payloadDictionary(from: rawPayload)
        let queryParts = [
            venueName,
            addressLine1,
            city,
            state,
            postalCode
        ]
        .compactMap { value -> String? in
            guard let value else { return nil }
            let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? nil : trimmed
        }

        guard !queryParts.isEmpty else { return nil }
        let query = queryParts.joined(separator: " ")
        let reviewURLs = Self.googleLocalReviewURLs(
            for: query,
            venueNames: [venueName],
            addressLine1: addressLine1,
            city: city,
            state: state,
            postalCode: postalCode,
            payload: payload
        )
        guard !reviewURLs.isEmpty else { return nil }

        return GoogleLocalReviewLookup(
            cacheKey: Self.googleReviewCacheKey(
                venueName: venueName,
                addressLine1: addressLine1,
                city: city,
                state: state,
                postalCode: postalCode
            ),
            venueName: venueName,
            addressLine1: addressLine1,
            city: city,
            state: state,
            postalCode: postalCode,
            query: query,
            reviewURLs: reviewURLs
        )
    }

    private nonisolated static func googleReviewCacheKey(
        venueName: String?,
        addressLine1: String?,
        city: String?,
        state: String?,
        postalCode: String?
    ) -> String {
        ExternalEventSupport.normalizeToken(
            [venueName, addressLine1, city, state, postalCode]
                .compactMap { $0 }
                .joined(separator: " ")
        )
    }

    private nonisolated static func googleLocalReviewURLs(
        for query: String,
        venueNames: [String?],
        addressLine1: String?,
        city: String?,
        state: String?,
        postalCode: String?,
        payload: JSONDictionary
    ) -> [URL] {
        var urls: [URL] = []
        let nestedVenue = payload["venue"] as? JSONDictionary
        let nestedPlace = payload["place"] as? JSONDictionary
        let rawCandidates: [String?] = [
            payload["google_places_google_maps_uri"] as? String,
            payload["google_maps_uri"] as? String,
            payload["googleMapsUri"] as? String,
            payload["google_places_url"] as? String,
            payload["google_places_googleMapsUri"] as? String,
            nestedVenue?["google_maps_uri"] as? String,
            nestedVenue?["googleMapsUri"] as? String,
            nestedVenue?["google_places_url"] as? String,
            nestedPlace?["google_maps_uri"] as? String,
            nestedPlace?["googleMapsUri"] as? String,
            nestedPlace?["google_places_url"] as? String
        ]

        if let mapSearchURL = googleLocalMapSearchURL(for: query), urls.contains(mapSearchURL) == false {
            urls.append(mapSearchURL)
        }

        if let searchURL = googleLocalReviewURL(for: query), urls.contains(searchURL) == false {
            urls.append(searchURL)
        }

        for candidate in rawCandidates {
            guard let normalizedURL = normalizedHTTPURL(from: candidate) else { continue }
            if ExternalEventSupport.googleReviewURLNeedsIdentityValidation(normalizedURL.absoluteString),
               ExternalEventSupport.googleReviewIdentityScore(
                venueNames: venueNames,
                addressLine1: addressLine1,
                city: city,
                state: state,
                postalCode: postalCode,
                reviewURL: normalizedURL.absoluteString
               ) == 0 {
                continue
            }
            if urls.contains(normalizedURL) == false {
                urls.append(normalizedURL)
            }
        }

        return urls
    }

    private nonisolated static func googleLocalMapSearchURL(for query: String) -> URL? {
        var components = URLComponents(string: "https://www.google.com/search")
        components?.queryItems = [
            URLQueryItem(name: "tbm", value: "map"),
            URLQueryItem(name: "authuser", value: "0"),
            URLQueryItem(name: "hl", value: "en"),
            URLQueryItem(name: "gl", value: "us"),
            URLQueryItem(name: "q", value: query)
        ]
        return components?.url
    }

    private nonisolated static func googleLocalReviewURL(for query: String) -> URL? {
        let disallowedPathCharacters = CharacterSet(charactersIn: "/?&=#")
        let allowedPathCharacters = CharacterSet.urlPathAllowed.subtracting(disallowedPathCharacters)
        guard let encodedQuery = query.addingPercentEncoding(withAllowedCharacters: allowedPathCharacters) else {
            return nil
        }

        var components = URLComponents(string: "https://www.google.com")
        components?.percentEncodedPath = "/maps/search/\(encodedQuery)"
        components?.queryItems = [
            URLQueryItem(name: "hl", value: "en"),
            URLQueryItem(name: "gl", value: "us")
        ]
        return components?.url
    }

    private func fetchGoogleLocalReviewSignal(
        for lookup: GoogleLocalReviewLookup
    ) async -> GoogleLocalReviewSignal? {
        if let directSignal = await Self.fetchGoogleLocalReviewSignal(
            for: lookup,
            session: googleReviewSession
        ) {
            return directSignal
        }

        #if os(macOS)
        if headlessGoogleRatingsEnabled,
           let headlessSignal = Self.fetchGoogleLocalReviewSignalWithHeadlessChrome(
                for: lookup,
                chromeBinaryPath: googleReviewChromeBinaryPath
           ) {
            return headlessSignal
        }
        #endif

        return nil
    }

    private nonisolated static func fetchGoogleLocalReviewSignal(
        for lookup: GoogleLocalReviewLookup,
        session: URLSession
    ) async -> GoogleLocalReviewSignal? {
        for reviewURL in lookup.reviewURLs {
            for attempt in 0..<2 {
                do {
                    var request = URLRequest(url: reviewURL)
                    request.httpMethod = "GET"
                    request.timeoutInterval = 12
                    request.setValue(desktopGoogleUserAgent, forHTTPHeaderField: "User-Agent")
                    request.setValue("en-US,en;q=0.9", forHTTPHeaderField: "Accept-Language")
                    request.setValue("text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8", forHTTPHeaderField: "Accept")
                    request.setValue("https://www.google.com/", forHTTPHeaderField: "Referer")

                    let (data, response) = try await session.data(for: request)
                    guard let statusCode = (response as? HTTPURLResponse)?.statusCode,
                          200..<300 ~= statusCode
                    else {
                        continue
                    }

                    let html = String(data: data, encoding: .utf8) ?? ""
                    if let signal = parseGoogleLocalReviewSignal(
                        from: html,
                        lookup: lookup,
                        reviewURL: reviewURL.absoluteString
                    ) {
                        return signal
                    }
                } catch {
                    if attempt == 1 {
                        continue
                    }
                }
            }
        }

        return nil
    }

    private nonisolated static func parseGoogleLocalReviewSignal(
        from html: String,
        lookup: GoogleLocalReviewLookup,
        reviewURL: String
    ) -> GoogleLocalReviewSignal? {
        if let mapSearchSignal = googleMapSearchReviewSignal(
            from: html,
            venueNames: [lookup.venueName],
            addressLine1: lookup.addressLine1,
            city: lookup.city,
            state: lookup.state,
            postalCode: lookup.postalCode,
            fallbackReviewURL: reviewURL
        ) {
            return GoogleLocalReviewSignal(
                rating: mapSearchSignal.rating,
                reviewCount: mapSearchSignal.reviewCount,
                reviewURL: mapSearchSignal.reviewURL
            )
        }

        let nsRange = NSRange(html.startIndex..<html.endIndex, in: html)
        guard let regex = try? NSRegularExpression(
            pattern: #"aria-label="Rated ([0-9.]+) out of 5,"|<span class="UIHjI[^"]*"[^>]*>([0-9.]+)</span>|aria-label="([0-9.]+) stars ?"|<span aria-hidden="true">([0-9.]+)</span>\s*<span class="ceNzKf[^"]*"[^>]*aria-label="[0-9.]+ stars ?""#,
            options: []
        ) else {
            return nil
        }

        var bestSignal: (signal: GoogleLocalReviewSignal, score: Int, reviewCount: Int)?

        for match in regex.matches(in: html, options: [], range: nsRange) {
            let ratingMatchRange = [1, 2, 3, 4]
                .lazy
                .map { match.range(at: $0) }
                .first(where: { $0.location != NSNotFound })
            guard let ratingMatchRange,
                  ratingMatchRange.location != NSNotFound,
                  let ratingRange = Range(ratingMatchRange, in: html)
            else {
                continue
            }

            let ratingText = String(html[ratingRange])
            let windowStart = max(0, match.range.location - 900)
            let windowEnd = min((html as NSString).length, match.range.location + match.range.length + 900)
            let window = (html as NSString).substring(with: NSRange(location: windowStart, length: windowEnd - windowStart))
            let countCandidates = [
                decodedHTMLText(firstCapture(pattern: #">([0-9][0-9,\.KkMm]*) reviews<"#, in: window)),
                decodedHTMLText(firstCapture(pattern: #"([0-9][0-9,\.KkMm]*) Google reviews"#, in: window)),
                decodedHTMLText(firstCapture(pattern: #"aria-label="([0-9][0-9,\.KkMm]*) reviews"#, in: window))
            ]
            guard let rating = Double(ratingText) else {
                continue
            }
            let reviewCount = countCandidates.lazy.compactMap(parseGoogleReviewCount).first

            let titlePatterns = [
                #"<h1[^>]+class="[^"]*DUwDvf[^"]*lfPIob[^"]*"[^>]*>(.*?)</h1>"#,
                #"<title>(.*?) - Google Maps</title>"#,
                #"<span class="OSrXXb">(.*?)</span>"#,
                #"<div class="dbg0pd">(.*?)</div>"#,
                #"<div class="qBF1Pd[^"]*"[^>]*>(.*?)</div>"#
            ]
            let title = titlePatterns
                .lazy
                .compactMap { decodedHTMLText(firstCapture(pattern: $0, in: window)) }
                .first
                ?? titlePatterns
                    .lazy
                    .compactMap { decodedHTMLText(firstCapture(pattern: $0, in: html)) }
                    .first
            let titleScore = ExternalEventSupport.googleReviewIdentityScore(
                venueNames: [lookup.venueName],
                addressLine1: lookup.addressLine1,
                city: lookup.city,
                state: lookup.state,
                postalCode: lookup.postalCode,
                candidateTitle: title,
                reviewURL: reviewURL
            )
            if titleScore == 0 {
                continue
            }

            let signal = GoogleLocalReviewSignal(
                rating: rating,
                reviewCount: reviewCount,
                reviewURL: reviewURL
            )

            if let currentBest = bestSignal {
                let reviewCountScore = reviewCount ?? 0
                if titleScore > currentBest.score || (titleScore == currentBest.score && reviewCountScore > currentBest.reviewCount) {
                    bestSignal = (signal, titleScore, reviewCountScore)
                }
            } else {
                bestSignal = (signal, titleScore, reviewCount ?? 0)
            }
        }

        return bestSignal?.signal
    }

    nonisolated static func googleMapSearchReviewSignal(
        from response: String,
        venueNames: [String?],
        addressLine1: String?,
        city: String?,
        state: String?,
        postalCode: String?,
        fallbackReviewURL: String
    ) -> (rating: Double, reviewCount: Int?, reviewURL: String)? {
        let trimmed = response.trimmingCharacters(in: .whitespacesAndNewlines)
        let sanitizedResponse = String(trimmed.drop { $0 != "[" && $0 != "{" })
        guard !sanitizedResponse.isEmpty,
              let data = sanitizedResponse.data(using: .utf8),
              let jsonObject = try? JSONSerialization.jsonObject(with: data)
        else {
            return nil
        }

        var bestMatch: (rating: Double, reviewCount: Int?, reviewURL: String, score: Int)?
        collectGoogleMapSearchCandidate(
            from: jsonObject,
            venueNames: venueNames,
            addressLine1: addressLine1,
            city: city,
            state: state,
            postalCode: postalCode,
            fallbackReviewURL: fallbackReviewURL,
            bestMatch: &bestMatch
        )
        guard let bestMatch else { return nil }
        return (bestMatch.rating, bestMatch.reviewCount, bestMatch.reviewURL)
    }

    private nonisolated static func collectGoogleMapSearchCandidate(
        from node: Any,
        venueNames: [String?],
        addressLine1: String?,
        city: String?,
        state: String?,
        postalCode: String?,
        fallbackReviewURL: String,
        bestMatch: inout (rating: Double, reviewCount: Int?, reviewURL: String, score: Int)?
    ) {
        if let array = node as? [Any] {
            if let candidate = googleMapSearchCandidate(
                in: array,
                venueNames: venueNames,
                addressLine1: addressLine1,
                city: city,
                state: state,
                postalCode: postalCode,
                fallbackReviewURL: fallbackReviewURL
            ) {
                if let currentBest = bestMatch {
                    let currentReviewCount = currentBest.reviewCount ?? 0
                    let candidateReviewCount = candidate.reviewCount ?? 0
                    if candidate.score > currentBest.score
                        || (candidate.score == currentBest.score && candidateReviewCount > currentReviewCount) {
                        bestMatch = candidate
                    }
                } else {
                    bestMatch = candidate
                }
            }

            for child in array {
                collectGoogleMapSearchCandidate(
                    from: child,
                    venueNames: venueNames,
                    addressLine1: addressLine1,
                    city: city,
                    state: state,
                    postalCode: postalCode,
                    fallbackReviewURL: fallbackReviewURL,
                    bestMatch: &bestMatch
                )
            }
        } else if let dictionary = node as? [String: Any] {
            for value in dictionary.values {
                collectGoogleMapSearchCandidate(
                    from: value,
                    venueNames: venueNames,
                    addressLine1: addressLine1,
                    city: city,
                    state: state,
                    postalCode: postalCode,
                    fallbackReviewURL: fallbackReviewURL,
                    bestMatch: &bestMatch
                )
            }
        }
    }

    private nonisolated static func googleMapSearchCandidate(
        in array: [Any],
        venueNames: [String?],
        addressLine1: String?,
        city: String?,
        state: String?,
        postalCode: String?,
        fallbackReviewURL: String
    ) -> (rating: Double, reviewCount: Int?, reviewURL: String, score: Int)? {
        guard let rating = googleMapSearchRating(in: array) else {
            return nil
        }

        let reviewURL = googleMapSearchReviewURL(in: array, fallbackReviewURL: fallbackReviewURL)
        let reviewCount = googleMapSearchReviewCount(in: array)
        let candidateStrings = googleMapSearchStrings(in: array, maxDepth: 2)
        let normalizedVenueNames = venueNames
            .compactMap { $0 }
            .map(ExternalEventSupport.normalizeToken)
            .filter { !$0.isEmpty }

        var bestScore = 0
        for candidateTitle in candidateStrings {
            guard candidateTitle.count <= 180 else { continue }
            let identityScore = ExternalEventSupport.googleReviewIdentityScore(
                venueNames: venueNames,
                addressLine1: addressLine1,
                city: city,
                state: state,
                postalCode: postalCode,
                candidateTitle: candidateTitle,
                reviewURL: reviewURL
            )
            guard identityScore > 0 else { continue }

            let normalizedCandidate = ExternalEventSupport.normalizeToken(candidateTitle)
            let exactBonus = normalizedVenueNames.contains(normalizedCandidate) ? 4 : 0
            let partialBonus = exactBonus == 0
                && normalizedVenueNames.contains(where: {
                    !$0.isEmpty && (normalizedCandidate.contains($0) || $0.contains(normalizedCandidate))
                })
                ? 1
                : 0
            bestScore = max(bestScore, identityScore + exactBonus + partialBonus)
        }

        guard bestScore > 0 else { return nil }
        return (rating, reviewCount, reviewURL, bestScore)
    }

    private nonisolated static func googleMapSearchRating(in array: [Any]) -> Double? {
        if array.count >= 8,
           array.prefix(7).allSatisfy({ $0 is NSNull }),
           let rating = ExternalEventSupport.parseDouble(array[7]),
           rating >= 1.0,
           rating <= 5.0 {
            return rating
        }

        if array.count >= 2,
           let rating = ExternalEventSupport.parseDouble(array[0]),
           rating >= 1.0,
           rating <= 5.0,
           (array[1] is [Any] || (array.count >= 3 && ExternalEventSupport.parseInt(array[2]) != nil)) {
            return rating
        }

        return nil
    }

    private nonisolated static func googleMapSearchReviewCount(in array: [Any]) -> Int? {
        guard array.count >= 3,
              let rating = ExternalEventSupport.parseDouble(array[0]),
              rating >= 1.0,
              rating <= 5.0,
              let reviewCount = ExternalEventSupport.parseInt(array[2]),
              reviewCount > 0
        else {
            return nil
        }

        return reviewCount
    }

    private nonisolated static func googleMapSearchReviewURL(
        in array: [Any],
        fallbackReviewURL: String
    ) -> String {
        let candidates = googleMapSearchStrings(in: array, maxDepth: 3)
        for candidate in candidates {
            if candidate.contains("/maps/preview/place/") {
                return googleMapSearchAbsoluteURL(candidate) ?? fallbackReviewURL
            }
        }
        for candidate in candidates {
            if candidate.contains("/search?"), candidate.contains("tbm=map") {
                return googleMapSearchAbsoluteURL(candidate) ?? fallbackReviewURL
            }
        }
        return fallbackReviewURL
    }

    private nonisolated static func googleMapSearchAbsoluteURL(_ rawValue: String) -> String? {
        if let normalized = normalizedHTTPURL(from: rawValue) {
            return normalized.absoluteString
        }
        guard rawValue.hasPrefix("/") else { return nil }
        return "https://www.google.com\(rawValue)"
    }

    private nonisolated static func googleMapSearchStrings(
        in node: Any,
        maxDepth: Int,
        depth: Int = 0
    ) -> [String] {
        guard depth <= maxDepth else { return [] }

        if let stringValue = node as? String {
            return [stringValue]
        }

        if let array = node as? [Any] {
            return array.flatMap {
                googleMapSearchStrings(in: $0, maxDepth: maxDepth, depth: depth + 1)
            }
        }

        if let dictionary = node as? [String: Any] {
            return dictionary.values.flatMap {
                googleMapSearchStrings(in: $0, maxDepth: maxDepth, depth: depth + 1)
            }
        }

        return []
    }

    private nonisolated static func parseGoogleReviewCount(_ raw: String) -> Int? {
        let normalized = raw
            .replacingOccurrences(of: ",", with: "")
            .replacingOccurrences(of: "(", with: "")
            .replacingOccurrences(of: ")", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .uppercased()

        guard !normalized.isEmpty else { return nil }

        if normalized.hasSuffix("K"), let value = Double(normalized.dropLast()) {
            return Int((value * 1_000).rounded())
        }
        if normalized.hasSuffix("M"), let value = Double(normalized.dropLast()) {
            return Int((value * 1_000_000).rounded())
        }
        return Int(normalized)
    }

    private nonisolated static func googleReviewSignalMatchesLookup(
        _ signal: GoogleLocalReviewSignal,
        lookup: GoogleLocalReviewLookup
    ) -> Bool {
        ExternalEventSupport.googleReviewURLMatchesIdentity(
            signal.reviewURL,
            venueNames: [lookup.venueName],
            addressLine1: lookup.addressLine1,
            city: lookup.city,
            state: lookup.state,
            postalCode: lookup.postalCode
        )
    }

    private nonisolated static func decodedHTMLText(_ value: String?) -> String {
        guard let value else { return "" }
        return value
            .replacingOccurrences(of: "&amp;", with: "&")
            .replacingOccurrences(of: "&quot;", with: "\"")
            .replacingOccurrences(of: "&#39;", with: "'")
            .replacingOccurrences(of: "&middot;", with: "·")
            .replacingOccurrences(of: "&nbsp;", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private nonisolated static func firstCapture(pattern: String, in value: String) -> String? {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else {
            return nil
        }
        let nsRange = NSRange(value.startIndex..<value.endIndex, in: value)
        guard let match = regex.firstMatch(in: value, options: [], range: nsRange),
              match.numberOfRanges > 1,
              let range = Range(match.range(at: 1), in: value)
        else {
            return nil
        }
        return String(value[range])
    }

    private nonisolated static let desktopGoogleUserAgent =
        "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/123.0.0.0 Safari/537.36"

    private nonisolated static func applyGoogleLocalReviewSignal(
        _ signal: GoogleLocalReviewSignal,
        to event: ExternalEvent
    ) -> ExternalEvent {
        var enriched = event
        enriched.venueRating = signal.rating
        if let reviewCount = signal.reviewCount {
            enriched.venuePopularityCount = reviewCount
        }
        var reviewPayload: [String: Any] = [
            "google_places_rating": signal.rating,
            "google_places_url": signal.reviewURL,
            "google_maps_uri": signal.reviewURL,
            "google_review_signal_source": "scraped_google_maps"
        ]
        if let reviewCount = signal.reviewCount {
            reviewPayload["google_places_user_rating_count"] = reviewCount
        }
        enriched.rawSourcePayload = ExternalEventSupport.mergedPayload(
            primary: enriched.rawSourcePayload,
            secondary: ExternalEventSupport.jsonString(reviewPayload)
        )
        return enriched
    }

    private nonisolated static func applyGoogleLocalReviewSignal(
        _ signal: GoogleLocalReviewSignal,
        to venue: ExternalVenue
    ) -> ExternalVenue {
        var enriched = venue
        enriched.venueRating = signal.rating
        if let reviewCount = signal.reviewCount {
            enriched.venuePopularityCount = reviewCount
        }
        var reviewPayload: [String: Any] = [
            "google_places_rating": signal.rating,
            "google_places_url": signal.reviewURL,
            "google_maps_uri": signal.reviewURL,
            "google_review_signal_source": "scraped_google_maps"
        ]
        if let reviewCount = signal.reviewCount {
            reviewPayload["google_places_user_rating_count"] = reviewCount
        }
        enriched.rawSourcePayload = ExternalEventSupport.mergedPayload(
            primary: enriched.rawSourcePayload,
            secondary: ExternalEventSupport.jsonString(reviewPayload)
        )
        return enriched
    }

    private nonisolated static func googleReviewCacheFileURL() -> URL? {
        guard let applicationSupportURL = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else {
            return nil
        }
        let directoryURL = applicationSupportURL.appendingPathComponent("sidequest_external_events", isDirectory: true)
        try? FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true, attributes: nil)
        return directoryURL.appendingPathComponent("google_local_reviews_cache.json")
    }

    private nonisolated static func googleReviewCacheTTL(from environment: [String: String]) -> TimeInterval {
        let hours = Double(environment["SIDEQUEST_GOOGLE_REVIEW_CACHE_TTL_HOURS"] ?? "") ?? 168
        return max(hours, 12) * 3600
    }

    private nonisolated static func boolEnvironmentFlag(_ value: String?) -> Bool {
        guard let value = value?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() else {
            return false
        }
        return ["1", "true", "yes", "on"].contains(value)
    }

    private nonisolated static func loadPersistedGoogleReviewCache(
        from url: URL,
        maxAge: TimeInterval
    ) -> [String: GoogleLocalReviewCacheEntry?] {
        guard let data = try? Data(contentsOf: url) else { return [:] }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        guard let payload = try? decoder.decode([String: GoogleLocalReviewCacheEntry].self, from: data) else {
            return [:]
        }

        let cutoffDate = Date().addingTimeInterval(-maxAge)
        return payload.reduce(into: [String: GoogleLocalReviewCacheEntry?]()) { partialResult, item in
            guard item.value.savedAt >= cutoffDate else { return }
            partialResult[item.key] = item.value
        }
    }

    private func persistGoogleReviewCache() {
        guard let googleReviewCacheFileURL else { return }
        let payload = googleReviewCache.compactMapValues { $0 }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        guard let data = try? encoder.encode(payload) else { return }
        try? data.write(to: googleReviewCacheFileURL, options: [.atomic])
    }

    #if os(macOS)
    private nonisolated static func googleReviewChromeBinaryPath(from environment: [String: String]) -> String {
        let candidate = environment["SIDEQUEST_GOOGLE_REVIEW_CHROME_BIN"]?.trimmingCharacters(in: .whitespacesAndNewlines)
        if let candidate, !candidate.isEmpty {
            return candidate
        }
        return "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome"
    }

    private nonisolated static func fetchGoogleLocalReviewSignalWithHeadlessChrome(
        for lookup: GoogleLocalReviewLookup,
        chromeBinaryPath: String
    ) -> GoogleLocalReviewSignal? {
        guard FileManager.default.isExecutableFile(atPath: chromeBinaryPath) else {
            return nil
        }

        for reviewURL in lookup.reviewURLs {
            guard let html = headlessGoogleReviewHTML(from: reviewURL, chromeBinaryPath: chromeBinaryPath) else {
                continue
            }
            if let signal = parseGoogleLocalReviewSignal(
                from: html,
                lookup: lookup,
                reviewURL: reviewURL.absoluteString
            ) {
                return signal
            }
        }

        return nil
    }

    private nonisolated static func headlessGoogleReviewHTML(
        from reviewURL: URL,
        chromeBinaryPath: String
    ) -> String? {
        let fileManager = FileManager.default
        let outputURL = fileManager.temporaryDirectory.appendingPathComponent("sidequest-google-review-\(UUID().uuidString).html")
        let errorURL = fileManager.temporaryDirectory.appendingPathComponent("sidequest-google-review-\(UUID().uuidString).err")
        fileManager.createFile(atPath: outputURL.path, contents: nil)
        fileManager.createFile(atPath: errorURL.path, contents: nil)

        defer {
            try? fileManager.removeItem(at: outputURL)
            try? fileManager.removeItem(at: errorURL)
        }

        guard let outputHandle = try? FileHandle(forWritingTo: outputURL),
              let errorHandle = try? FileHandle(forWritingTo: errorURL)
        else {
            return nil
        }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: chromeBinaryPath)
        process.arguments = [
            "--headless=new",
            "--disable-gpu",
            "--disable-background-networking",
            "--disable-sync",
            "--no-first-run",
            "--virtual-time-budget=8000",
            "--dump-dom",
            reviewURL.absoluteString
        ]
        process.standardOutput = outputHandle
        process.standardError = errorHandle

        do {
            try process.run()
        } catch {
            outputHandle.closeFile()
            errorHandle.closeFile()
            return nil
        }

        let deadline = Date().addingTimeInterval(16)
        while process.isRunning, Date() < deadline {
            Thread.sleep(forTimeInterval: 0.1)
        }

        if process.isRunning {
            process.terminate()
            Thread.sleep(forTimeInterval: 0.2)
        }

        outputHandle.closeFile()
        errorHandle.closeFile()

        guard let data = try? Data(contentsOf: outputURL),
              !data.isEmpty
        else {
            return nil
        }
        return String(data: data, encoding: .utf8)
    }
    #endif

    private func sourcePageImageLookup(for event: ExternalEvent) -> SourcePageImageLookup? {
        guard Self.shouldScrapeSourcePageImage(for: event) else { return nil }

        let rawCandidates = [
            event.ticketURL,
            event.registrationURL,
            event.sourceURL
        ]

        guard let probeURL = rawCandidates
            .compactMap(Self.normalizedHTTPURL(from:))
            .first(where: { url in
                let host = url.host?.lowercased() ?? ""
                return !host.contains("google.")
            })
        else {
            return nil
        }

        return SourcePageImageLookup(
            cacheKey: probeURL.absoluteString,
            probeURL: probeURL
        )
    }

    private nonisolated static func shouldScrapeSourcePageImage(for event: ExternalEvent) -> Bool {
        guard event.imageURL == nil else { return false }
        guard event.status != .cancelled, event.status != .ended else { return false }
        guard event.eventType != .partyNightlife, event.recordKind != .venueNight else { return false }
        return true
    }

    private nonisolated static func normalizedHTTPURL(from rawValue: String?) -> URL? {
        guard let rawValue,
              let url = URL(string: rawValue.trimmingCharacters(in: .whitespacesAndNewlines)),
              let scheme = url.scheme?.lowercased(),
              scheme == "http" || scheme == "https"
        else {
            return nil
        }
        return url
    }

    private nonisolated static func fetchSourcePageImageURL(
        from url: URL,
        session: URLSession
    ) async -> String? {
        do {
            var request = URLRequest(url: url)
            request.httpMethod = "GET"
            request.timeoutInterval = 12
            request.setValue(desktopGoogleUserAgent, forHTTPHeaderField: "User-Agent")
            request.setValue("en-US,en;q=0.9", forHTTPHeaderField: "Accept-Language")
            request.setValue("text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8", forHTTPHeaderField: "Accept")

            let (data, response) = try await session.data(for: request)
            guard let statusCode = (response as? HTTPURLResponse)?.statusCode,
                  200..<300 ~= statusCode
            else {
                return nil
            }

            let html = String(data: data, encoding: .utf8) ?? ""
            return parseSourcePageImageURL(from: html)
        } catch {
            return nil
        }
    }

    private nonisolated static func parseSourcePageImageURL(from html: String) -> String? {
        let patterns = [
            #"<meta[^>]+(?:property|name)=["'](?:og:image|twitter:image)["'][^>]+content=["']([^"']+)["']"#,
            #"<meta[^>]+content=["']([^"']+)["'][^>]+(?:property|name)=["'](?:og:image|twitter:image)["']"#,
            #"\"image\"\s*:\s*\"(https:[^"]+)\""#,
            #"\"image\"\s*:\s*\[\s*\"(https:[^"]+)\""#,
            #"\"thumbnailUrl\"\s*:\s*\"(https:[^"]+)\""#
        ]

        for pattern in patterns {
            let candidate = decodedHTMLText(firstCapture(pattern: pattern, in: html))
            guard !candidate.isEmpty,
                  let normalized = ExternalEventSupport.normalizedImageURLString(candidate),
                  ExternalEventSupport.imageMeetsMinimumResolution(normalized)
            else {
                continue
            }
            return normalized
        }

        return nil
    }

    private nonisolated static func applySourcePageImageURL(
        _ imageURL: String,
        to event: ExternalEvent
    ) -> ExternalEvent {
        var enriched = event
        enriched.imageURL = ExternalEventSupport.preferredImageURL(
            primary: enriched.imageURL,
            secondary: imageURL
        )
        enriched.rawSourcePayload = ExternalEventSupport.mergedPayload(
            primary: enriched.rawSourcePayload,
            secondary: ExternalEventSupport.jsonString([
                "source_page_image": imageURL,
                "source_page_image_gallery": [imageURL]
            ])
        )
        return enriched
    }

    private nonisolated static func shouldUpgradeNightlifeSchedule(for event: ExternalEvent) -> Bool {
        guard event.eventType == .partyNightlife || event.recordKind == .venueNight else {
            return false
        }
        if event.startLocal == nil && event.startAtUTC == nil {
            return true
        }
        if let startLocal = event.startLocal {
            let trimmed = startLocal.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.contains("T") || trimmed.contains("T00:00") {
                return true
            }
        }
        guard let startAtUTC = event.startAtUTC else {
            return false
        }
        let timezone = event.timezone.flatMap(TimeZone.init(identifier:)) ?? .current
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timezone
        let hour = calendar.component(.hour, from: startAtUTC)
        let minute = calendar.component(.minute, from: startAtUTC)
        return hour == 0 && minute == 0
    }

    private nonisolated static func distanceFromUser(
        for event: ExternalEvent,
        searchLocation: ExternalEventSearchLocation
    ) -> Double? {
        guard let searchCoordinate = searchLocation.coordinate,
              let latitude = event.latitude,
              let longitude = event.longitude
        else {
            return nil
        }
        let userLocation = CLLocation(latitude: searchCoordinate.latitude, longitude: searchCoordinate.longitude)
        let eventLocation = CLLocation(latitude: latitude, longitude: longitude)
        return userLocation.distance(from: eventLocation) / 1609.344
    }
}
