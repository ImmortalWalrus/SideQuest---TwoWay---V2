import Foundation

nonisolated enum ExternalEventSource: String, Codable, CaseIterable, Sendable {
    case ticketmaster
    case stubHub
    case runsignup
    case eventbrite
    case googleEvents
    case seatGeek
    case sportsSchedule
    case appleMaps
    case googlePlaces
    case yelpFusion
    case venueWebsite
    case venueCalendar
    case reservationProvider
    case nightlifeAggregator
    case editorialGuide
}

nonisolated enum ExternalEventSourceType: String, Codable, CaseIterable, Sendable {
    case ticketingAPI = "ticketing_api"
    case sportsScheduleAPI = "sports_schedule_api"
    case venueDiscoveryAPI = "venue_discovery_api"
    case officialVenueWebsite = "official_venue_website"
    case venueCalendar = "venue_calendar"
    case reservationProvider = "reservation_provider"
    case nightlifeAggregator = "nightlife_aggregator"
    case editorialEnrichment = "editorial_enrichment"
    case scraped = "scraped"
}

nonisolated enum ExternalEventRecordKind: String, Codable, CaseIterable, Sendable {
    case event
    case venueNight = "venue_night"
    case venue
}

nonisolated enum ExternalVenueType: String, Codable, CaseIterable, Sendable {
    case stadium
    case arena
    case concertVenue = "concert_venue"
    case nightlifeVenue = "nightlife_venue"
    case lounge
    case bar
    case restaurant
    case comedyClub = "comedy_club"
    case artsVenue = "arts_venue"
    case park
    case festivalGround = "festival_ground"
    case raceVenue = "race_venue"
    case other
}

nonisolated enum ExternalDiscoveryIntent: String, Codable, CaseIterable, Sendable {
    case biggestTonight = "biggest_tonight"
    case exclusiveHot = "exclusive_hot"
    case nearbyWorthIt = "nearby_and_worth_it"
    case lastMinutePlans = "last_minute_plans"
}

nonisolated enum ExternalEventType: String, Codable, CaseIterable, Sendable {
    case concert = "concert"
    case partyNightlife = "party / nightlife"
    case weekendActivity = "weekend activity"
    case socialCommunityEvent = "social / community event"
    case groupRun = "group run"
    case race5k = "race_5k"
    case race10k = "race_10k"
    case raceHalfMarathon = "race_half_marathon"
    case raceMarathon = "race_marathon"
    case sportsEvent = "sports event"
    case otherLiveEvent = "other live event"
}

nonisolated enum ExternalEventStatus: String, Codable, CaseIterable, Sendable {
    case scheduled
    case onsale
    case openRegistration
    case soldOut
    case cancelled
    case postponed
    case rescheduled
    case ended
    case unknown
}

nonisolated enum ExternalEventAvailabilityStatus: String, Codable, CaseIterable, Sendable {
    case available
    case onsale
    case openRegistration
    case registrationClosed
    case soldOut
    case cancelled
    case postponed
    case rescheduled
    case ended
    case unknown
}

nonisolated enum ExternalEventUrgencyBadge: String, Codable, CaseIterable, Sendable {
    case almostSoldOut = "almost sold out"
    case sellingFast = "selling fast"
    case registrationClosingSoon = "registration closing soon"
}

nonisolated enum ExternalEventSortOption: String, Codable, CaseIterable, Identifiable, Sendable {
    case recommended = "Recommended"
    case hottest = "Hottest"
    case soonest = "Soonest"
    case closest = "Closest"
    case weekend = "This Weekend"

    var id: String { rawValue }
}

nonisolated enum ExternalEventFilterOption: String, Codable, CaseIterable, Identifiable, Sendable {
    case all = "All"
    case today = "Today"
    case tonight = "Tonight"
    case tomorrow = "Tomorrow"
    case sports = "Sports"
    case concerts = "Concerts"
    case nightlife = "Nightlife"
    case exclusive = "Exclusive"
    case races = "Races"
    case community = "Community"
    case weekend = "Weekend"
    case free = "Free"

    var id: String { rawValue }
}

nonisolated struct ExternalEventQuery: Codable, Hashable, Sendable {
    var countryCode: String = "US"
    var city: String?
    var state: String?
    var postalCode: String?
    var latitude: Double?
    var longitude: Double?
    var radiusMiles: Double?
    var keyword: String?
    var pageSize: Int = 8
    var page: Int = 0
    var sourcePageDepth: Int = 1
    var includePast: Bool = false
    var hyperlocalRadiusMiles: Double = 2
    var nightlifeRadiusMiles: Double = 6
    var headlineRadiusMiles: Double = 12
    var adaptiveRadiusExpansion: Bool = true
    var discoveryIntent: ExternalDiscoveryIntent = .nearbyWorthIt
}

nonisolated struct ExternalEventSourceCursor: Codable, Hashable, Sendable {
    let source: ExternalEventSource
    let page: Int
    let pageSize: Int
    let nextToken: String?
}

nonisolated struct ExternalEventEndpointResult: Codable, Hashable, Sendable {
    let label: String
    let requestURL: String
    let responseStatusCode: Int?
    let worked: Bool
    let note: String?
}

nonisolated struct ExternalEventDedupeGroup: Codable, Hashable, Sendable {
    let dedupeKey: String
    let canonicalEventID: String
    let mergedEventIDs: [String]
    let mergedSources: [ExternalEventSource]
    let reason: String
}

nonisolated struct ExternalEventSourceResult: Codable, Hashable, Sendable {
    let source: ExternalEventSource
    var usedCache: Bool
    let fetchedAt: Date
    let endpoints: [ExternalEventEndpointResult]
    let note: String?
    let nextCursor: ExternalEventSourceCursor?
    let events: [ExternalEvent]
}

nonisolated struct ExternalEventIngestionSnapshot: Codable, Hashable, Sendable {
    let fetchedAt: Date
    let query: ExternalEventQuery
    let sourceResults: [ExternalEventSourceResult]
    let mergedEvents: [ExternalEvent]
    let dedupeGroups: [ExternalEventDedupeGroup]
}

nonisolated struct ExternalVenueQuery: Codable, Hashable, Sendable {
    var countryCode: String = "US"
    var city: String?
    var state: String?
    var displayName: String?
    var latitude: Double
    var longitude: Double
    var hyperlocalRadiusMiles: Double = 2
    var nightlifeRadiusMiles: Double = 6
    var headlineRadiusMiles: Double = 12
    var adaptiveRadiusExpansion: Bool = true
    var pageSize: Int = 24
}

nonisolated struct ExternalVenueSourceResult: Codable, Hashable, Sendable {
    let source: ExternalEventSource
    let fetchedAt: Date
    let endpoints: [ExternalEventEndpointResult]
    let note: String?
    let venues: [ExternalVenue]
}

nonisolated struct ExternalVenueDiscoverySnapshot: Codable, Hashable, Sendable {
    let fetchedAt: Date
    let query: ExternalVenueQuery
    let sourceResults: [ExternalVenueSourceResult]
    let venues: [ExternalVenue]
}

nonisolated struct ExternalRadiusExpansionProfile: Codable, Hashable, Sendable {
    let step: Int
    let hyperlocalRadiusMiles: Double
    let nightlifeRadiusMiles: Double
    let headlineRadiusMiles: Double
}

nonisolated struct ExternalLocationDiscoverySnapshot: Codable, Hashable, Sendable {
    let fetchedAt: Date
    let searchLocation: ExternalEventSearchLocation
    let appliedProfiles: [ExternalRadiusExpansionProfile]
    let venueSnapshot: ExternalVenueDiscoverySnapshot?
    let eventSnapshot: ExternalEventIngestionSnapshot
    let mergedEvents: [ExternalEvent]
    let notes: [String]
}

nonisolated struct ExternalVenue: Identifiable, Codable, Hashable, Sendable {
    var id: String
    var source: ExternalEventSource
    var sourceType: ExternalEventSourceType
    var sourceVenueID: String
    var canonicalVenueID: String?
    var name: String
    var aliases: [String]
    var venueType: ExternalVenueType?
    var neighborhood: String?
    var addressLine1: String?
    var addressLine2: String?
    var city: String?
    var state: String?
    var postalCode: String?
    var country: String?
    var latitude: Double?
    var longitude: Double?
    var officialSiteURL: String?
    var reservationProvider: String?
    var reservationURL: String?
    var imageURL: String?
    var openingHoursText: String?
    var ageMinimum: Int?
    var doorPolicyText: String?
    var dressCodeText: String?
    var guestListAvailable: Bool?
    var bottleServiceAvailable: Bool?
    var tableMinPrice: Double?
    var coverPrice: Double?
    var venueSignalScore: Double?
    var nightlifeSignalScore: Double?
    var prestigeDemandScore: Double?
    var recurringEventPatternConfidence: Double?
    var sourceConfidence: Double?
    var sourceCoverageStatus: String?
    var rawSourcePayload: String
    var venuePopularityCount: Int? = nil
    var venueRating: Double? = nil
    var entryPolicySummary: String? = nil
    var womenEntryPolicyText: String? = nil
    var menEntryPolicyText: String? = nil
    var exclusivityTierLabel: String? = nil
}

nonisolated struct ExternalEvent: Identifiable, Codable, Hashable, Sendable {
    var id: String
    var source: ExternalEventSource
    var sourceEventID: String
    var sourceParentID: String?
    var sourceURL: String?
    var mergedSources: [ExternalEventSource]

    var title: String
    var shortDescription: String?
    var fullDescription: String?
    var category: String?
    var subcategory: String?
    var eventType: ExternalEventType

    var startAtUTC: Date?
    var endAtUTC: Date?
    var startLocal: String?
    var endLocal: String?
    var timezone: String?
    var salesStartAtUTC: Date?
    var salesEndAtUTC: Date?

    var venueName: String?
    var venueID: String?
    var addressLine1: String?
    var addressLine2: String?
    var city: String?
    var state: String?
    var postalCode: String?
    var country: String?
    var latitude: Double?
    var longitude: Double?

    var imageURL: String?
    var fallbackThumbnailAsset: String

    var status: ExternalEventStatus
    var availabilityStatus: ExternalEventAvailabilityStatus
    var urgencyBadge: ExternalEventUrgencyBadge?
    var socialProofCount: Int?
    var socialProofLabel: String?
    var venuePopularityCount: Int?
    var venueRating: Double?
    var ticketProviderCount: Int?

    var priceMin: Double?
    var priceMax: Double?
    var currency: String?

    var organizerName: String?
    var organizerEventCount: Int?
    var organizerVerified: Bool?
    var tags: [String]
    var distanceValue: Double?
    var distanceUnit: String?
    var raceType: String?
    var registrationURL: String?
    var ticketURL: String?
    var rawSourcePayload: String
    var sourceType: ExternalEventSourceType = .ticketingAPI
    var recordKind: ExternalEventRecordKind = .event
    var neighborhood: String? = nil
    var reservationURL: String? = nil
    var artistsOrTeams: [String] = []
    var ageMinimum: Int? = nil
    var doorPolicyText: String? = nil
    var dressCodeText: String? = nil
    var guestListAvailable: Bool? = nil
    var bottleServiceAvailable: Bool? = nil
    var tableMinPrice: Double? = nil
    var coverPrice: Double? = nil
    var openingHoursText: String? = nil
    var sourceConfidence: Double? = nil
    var popularityScoreRaw: Double? = nil
    var venueSignalScore: Double? = nil
    var exclusivityScore: Double? = nil
    var trendingScore: Double? = nil
    var crossSourceConfirmationScore: Double? = nil
    var distanceFromUser: Double? = nil
    var entryPolicySummary: String? = nil
    var womenEntryPolicyText: String? = nil
    var menEntryPolicyText: String? = nil
    var exclusivityTierLabel: String? = nil
}

extension ExternalEvent {
    var normalizedDedupKey: String {
        ExternalEventSupport.normalizedDedupKey(
            title: title,
            eventType: eventType,
            startLocal: startLocal,
            startAtUTC: startAtUTC,
            timezone: timezone,
            venueName: venueName,
            city: city,
            state: state,
            latitude: latitude,
            longitude: longitude
        )
    }

    var isUpcoming: Bool {
        guard let startAtUTC else { return true }
        return startAtUTC >= Date()
    }
}
