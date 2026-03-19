import Foundation

nonisolated struct ExternalEventServiceConfiguration: Sendable {
    var ticketmasterAPIKey: String?
    var ticketmasterAPISecret: String?
    var ticketmasterDiscoveryURL: URL = URL(string: "https://app.ticketmaster.com/discovery/v2/events.json")!

    var apifyClientID: String?
    var seatGeekClientID: String?
    var seatGeekClientSecret: String?
    var seatGeekBaseURL: URL = URL(string: "https://api.seatgeek.com/2")!

    var eventbritePrivateToken: String?
    var eventbriteBaseURL: URL = URL(string: "https://www.eventbriteapi.com")!
    var eventbriteSearchPath: String?

    var runsignupBaseURL: URL = URL(string: "https://api.runsignup.com")!
    var sportsScheduleAPIKey: String?
    var sportsScheduleBaseURL: URL = URL(string: "https://www.thesportsdb.com/api/v1/json/123")!
    var googlePlacesAPIKey: String?
    var googlePlacesBaseURL: URL = URL(string: "https://places.googleapis.com/v1")!
    var yelpAPIKey: String?
    var yelpBaseURL: URL = URL(string: "https://api.yelp.com/v3")!
    var apifyAPIToken: String?
    var apifyBaseURL: URL = URL(string: "https://api.apify.com")!
    var googleEventsActorID: String = "johnvc~google-events-api---access-google-events-data"
    var yelpBusinessActorID: String = "delicious_zebu~yelp-advanced-business-scraper-pay-per-result"
    var stubHubActorID: String = "benthepythondev~stubhub-scraper"

    static func fromEnvironment() -> ExternalEventServiceConfiguration {
        let env = ProcessInfo.processInfo.environment
        let runtimeSecrets = ExternalEventRuntimeSecretsStore.load()
        return ExternalEventServiceConfiguration(
            ticketmasterAPIKey: env["TICKETMASTER_API_KEY"] ?? runtimeSecrets["TICKETMASTER_API_KEY"],
            ticketmasterAPISecret: env["TICKETMASTER_API_SECRET"] ?? runtimeSecrets["TICKETMASTER_API_SECRET"],
            ticketmasterDiscoveryURL: URL(string: env["TICKETMASTER_DISCOVERY_URL"] ?? runtimeSecrets["TICKETMASTER_DISCOVERY_URL"] ?? "https://app.ticketmaster.com/discovery/v2/events.json")!,
            apifyClientID: env["APIFY_CLIENT_ID"] ?? runtimeSecrets["APIFY_CLIENT_ID"],
            seatGeekClientID: env["SEATGEEK_CLIENT_ID"] ?? runtimeSecrets["SEATGEEK_CLIENT_ID"],
            seatGeekClientSecret: env["SEATGEEK_CLIENT_SECRET"] ?? runtimeSecrets["SEATGEEK_CLIENT_SECRET"],
            seatGeekBaseURL: URL(string: env["SEATGEEK_BASE_URL"] ?? runtimeSecrets["SEATGEEK_BASE_URL"] ?? "https://api.seatgeek.com/2")!,
            eventbritePrivateToken: env["EVENTBRITE_PRIVATE_TOKEN"] ?? runtimeSecrets["EVENTBRITE_PRIVATE_TOKEN"],
            eventbriteBaseURL: URL(string: env["EVENTBRITE_BASE_URL"] ?? runtimeSecrets["EVENTBRITE_BASE_URL"] ?? "https://www.eventbriteapi.com")!,
            eventbriteSearchPath: env["EVENTBRITE_SEARCH_PATH"] ?? runtimeSecrets["EVENTBRITE_SEARCH_PATH"],
            runsignupBaseURL: URL(string: env["RUNSIGNUP_BASE_URL"] ?? runtimeSecrets["RUNSIGNUP_BASE_URL"] ?? "https://api.runsignup.com")!,
            sportsScheduleAPIKey: env["SPORTS_SCHEDULE_API_KEY"] ?? runtimeSecrets["SPORTS_SCHEDULE_API_KEY"] ?? env["SPORTRADAR_API_KEY"] ?? runtimeSecrets["SPORTRADAR_API_KEY"],
            sportsScheduleBaseURL: URL(string: env["SPORTS_SCHEDULE_BASE_URL"] ?? runtimeSecrets["SPORTS_SCHEDULE_BASE_URL"] ?? env["SPORTRADAR_BASE_URL"] ?? runtimeSecrets["SPORTRADAR_BASE_URL"] ?? "https://www.thesportsdb.com/api/v1/json/123")!,
            googlePlacesAPIKey: env["GOOGLE_PLACES_API_KEY"] ?? runtimeSecrets["GOOGLE_PLACES_API_KEY"],
            googlePlacesBaseURL: URL(string: env["GOOGLE_PLACES_BASE_URL"] ?? runtimeSecrets["GOOGLE_PLACES_BASE_URL"] ?? "https://places.googleapis.com/v1")!,
            yelpAPIKey: env["YELP_API_KEY"] ?? runtimeSecrets["YELP_API_KEY"],
            yelpBaseURL: URL(string: env["YELP_BASE_URL"] ?? runtimeSecrets["YELP_BASE_URL"] ?? "https://api.yelp.com/v3")!,
            apifyAPIToken: env["APIFY_API_TOKEN"] ?? runtimeSecrets["APIFY_API_TOKEN"],
            apifyBaseURL: URL(string: env["APIFY_BASE_URL"] ?? runtimeSecrets["APIFY_BASE_URL"] ?? "https://api.apify.com")!,
            googleEventsActorID: env["APIFY_GOOGLE_EVENTS_ACTOR_ID"] ?? runtimeSecrets["APIFY_GOOGLE_EVENTS_ACTOR_ID"] ?? "johnvc~google-events-api---access-google-events-data",
            yelpBusinessActorID: env["APIFY_YELP_ACTOR_ID"] ?? runtimeSecrets["APIFY_YELP_ACTOR_ID"] ?? "delicious_zebu~yelp-advanced-business-scraper-pay-per-result",
            stubHubActorID: env["APIFY_STUBHUB_ACTOR_ID"] ?? runtimeSecrets["APIFY_STUBHUB_ACTOR_ID"] ?? "benthepythondev~stubhub-scraper"
        )
    }

    static func sideQuestPrototype() -> ExternalEventServiceConfiguration {
        let environment = fromEnvironment()
        return ExternalEventServiceConfiguration(
            ticketmasterAPIKey: environment.ticketmasterAPIKey ?? "FIi3TiBxb316X1xYP2zThM5zfKYTCgKm",
            ticketmasterAPISecret: environment.ticketmasterAPISecret ?? "BwHmB1zLV698NU7V",
            ticketmasterDiscoveryURL: environment.ticketmasterDiscoveryURL,
            apifyClientID: environment.apifyClientID ?? "ewlVnFdot0MTzKGFq",
            seatGeekClientID: environment.seatGeekClientID,
            seatGeekClientSecret: environment.seatGeekClientSecret,
            seatGeekBaseURL: environment.seatGeekBaseURL,
            eventbritePrivateToken: environment.eventbritePrivateToken ?? "ODMX7LG7SIKPWKVARRPJ",
            eventbriteBaseURL: environment.eventbriteBaseURL,
            eventbriteSearchPath: environment.eventbriteSearchPath,
            runsignupBaseURL: environment.runsignupBaseURL,
            sportsScheduleAPIKey: environment.sportsScheduleAPIKey,
            sportsScheduleBaseURL: environment.sportsScheduleBaseURL,
            googlePlacesAPIKey: environment.googlePlacesAPIKey,
            googlePlacesBaseURL: environment.googlePlacesBaseURL,
            yelpAPIKey: environment.yelpAPIKey,
            yelpBaseURL: environment.yelpBaseURL,
            apifyAPIToken: environment.apifyAPIToken ?? "apify_api_yhX54E2qHYteUQxN3s8iEpsayM2A4W2sX0xF",
            apifyBaseURL: environment.apifyBaseURL,
            googleEventsActorID: environment.googleEventsActorID,
            yelpBusinessActorID: environment.yelpBusinessActorID,
            stubHubActorID: environment.stubHubActorID
        )
    }
}

private enum ExternalEventRuntimeSecretsStore {
    private static let fileName = "ExternalEventRuntimeSecrets.plist"

    static func load() -> [String: String] {
        guard
            let applicationSupportURL = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first,
            let data = try? Data(contentsOf: applicationSupportURL.appendingPathComponent(fileName)),
            let payload = try? PropertyListSerialization.propertyList(from: data, options: [], format: nil) as? [String: String]
        else {
            return [:]
        }
        return payload
    }
}

protocol ExternalEventSourceAdapter: Sendable {
    var source: ExternalEventSource { get }
    func fetchPage(
        query: ExternalEventQuery,
        cursor: ExternalEventSourceCursor?,
        session: URLSession,
        configuration: ExternalEventServiceConfiguration
    ) async -> ExternalEventSourceResult
}

actor ExternalEventIngestionService {
    static let shared = ExternalEventIngestionService(configuration: .fromEnvironment())

    private let configuration: ExternalEventServiceConfiguration
    private let session: URLSession
    private let cacheTTL: TimeInterval
    private let adapters: [any ExternalEventSourceAdapter]

    init(
        configuration: ExternalEventServiceConfiguration,
        session: URLSession? = nil,
        cacheTTL: TimeInterval = 15 * 60,
        adapters: [any ExternalEventSourceAdapter] = [
            TicketmasterEventAdapter(),
            RunSignupEventAdapter(),
            EventbriteEventAdapter(),
            GoogleEventsEventAdapter()
        ]
    ) {
        self.configuration = configuration
        if let session {
            self.session = session
        } else {
            let config = URLSessionConfiguration.ephemeral
            config.timeoutIntervalForRequest = 20
            config.timeoutIntervalForResource = 40
            self.session = URLSession(configuration: config)
        }
        self.cacheTTL = cacheTTL
        self.adapters = adapters
    }

    nonisolated static func fastPrimarySources(configuration: ExternalEventServiceConfiguration) -> Set<ExternalEventSource> {
        [
            .ticketmaster,
            .googleEvents
        ]
    }

    nonisolated static func slowEnrichmentSources(configuration: ExternalEventServiceConfiguration) -> Set<ExternalEventSource> {
        [.ticketmaster, .runsignup, .eventbrite, .googleEvents]
    }

    func fetchAll(
        query: ExternalEventQuery,
        forceRefresh: Bool = false,
        allowedSources: Set<ExternalEventSource>? = nil
    ) async -> ExternalEventIngestionSnapshot {
        let activeAdapters = adapters(for: allowedSources)
        let sourceResults = await withTaskGroup(of: ExternalEventSourceResult.self, returning: [ExternalEventSourceResult].self) { group in
            for adapter in activeAdapters {
                group.addTask {
                    await self.fetchAllPages(adapter: adapter, query: query, forceRefresh: forceRefresh)
                }
            }

            var results: [ExternalEventSourceResult] = []
            for await result in group {
                results.append(result)
            }
            return results.sorted { $0.source.rawValue < $1.source.rawValue }
        }

        return makeSnapshot(query: query, sourceResults: sourceResults)
    }

    func fetchNextPages(
        query: ExternalEventQuery,
        cursors: [ExternalEventSource: ExternalEventSourceCursor],
        forceRefresh: Bool = false,
        allowedSources: Set<ExternalEventSource>? = nil
    ) async -> [ExternalEventSourceResult] {
        let activeAdapters = adapters(for: allowedSources)
        return await withTaskGroup(of: ExternalEventSourceResult?.self, returning: [ExternalEventSourceResult].self) { group in
            for adapter in activeAdapters {
                guard let cursor = cursors[adapter.source] else { continue }
                group.addTask {
                    await self.fetch(
                        adapter: adapter,
                        query: query,
                        cursor: cursor,
                        forceRefresh: forceRefresh
                    )
                }
            }

            var results: [ExternalEventSourceResult] = []
            for await result in group {
                if let result {
                    results.append(result)
                }
            }
            return results.sorted { $0.source.rawValue < $1.source.rawValue }
        }
    }

    private func adapters(for allowedSources: Set<ExternalEventSource>?) -> [any ExternalEventSourceAdapter] {
        guard let allowedSources, !allowedSources.isEmpty else {
            return adapters
        }
        return adapters.filter { allowedSources.contains($0.source) }
    }

    private func fetchAllPages(
        adapter: any ExternalEventSourceAdapter,
        query: ExternalEventQuery,
        forceRefresh: Bool
    ) async -> ExternalEventSourceResult {
        let maxDepth = max(1, query.sourcePageDepth)
        var pagesFetched = 0
        var cursor: ExternalEventSourceCursor?
        var aggregatedEndpoints: [ExternalEventEndpointResult] = []
        var aggregatedEvents: [ExternalEvent] = []
        var notes: [String] = []

        repeat {
            let result = await fetch(
                adapter: adapter,
                query: query,
                cursor: cursor,
                forceRefresh: forceRefresh
            )

            pagesFetched += 1
            aggregatedEndpoints.append(contentsOf: result.endpoints)
            aggregatedEvents.append(contentsOf: result.events)
            if let note = result.note, !note.isEmpty {
                notes.append(note)
            }
            cursor = result.nextCursor

            if cursor == nil || pagesFetched >= maxDepth {
                return ExternalEventSourceResult(
                    source: adapter.source,
                    usedCache: false,
                    fetchedAt: Date(),
                    endpoints: aggregatedEndpoints,
                    note: aggregatedEvents.isEmpty ? notes.first : nil,
                    nextCursor: cursor,
                    events: ExternalEventIngestionService.dedupe(events: aggregatedEvents).events
                )
            }
        } while true
    }

    private func fetch(
        adapter: any ExternalEventSourceAdapter,
        query: ExternalEventQuery,
        cursor: ExternalEventSourceCursor?,
        forceRefresh: Bool
    ) async -> ExternalEventSourceResult {
        let page = cursor?.page ?? query.page
        let cacheKey = ExternalEventCacheStore.cacheKey(source: adapter.source, query: query, page: page)

        if !forceRefresh,
           let envelope = ExternalEventCacheStore.load(forKey: cacheKey),
           Date().timeIntervalSince(envelope.fetchedAt) < cacheTTL
        {
            var cached = envelope.result
            cached.usedCache = true
            return cached
        }

        let fresh = await adapter.fetchPage(
            query: query,
            cursor: cursor,
            session: session,
            configuration: configuration
        )

        if !fresh.events.isEmpty || fresh.endpoints.contains(where: \.worked) {
            ExternalEventCacheStore.save(result: fresh, forKey: cacheKey)
        }

        return fresh
    }

    private func makeSnapshot(
        query: ExternalEventQuery,
        sourceResults: [ExternalEventSourceResult]
    ) -> ExternalEventIngestionSnapshot {
        let allEvents = sourceResults.flatMap(\.events)
        let deduped = Self.dedupe(events: allEvents)

        return ExternalEventIngestionSnapshot(
            fetchedAt: Date(),
            query: query,
            sourceResults: sourceResults,
            mergedEvents: deduped.events,
            dedupeGroups: deduped.groups
        )
    }

    nonisolated static func dedupe(events: [ExternalEvent]) -> (events: [ExternalEvent], groups: [ExternalEventDedupeGroup]) {
        let grouped = Dictionary(grouping: events) { event in
            ExternalEventSupport.dedupeBucketKey(for: event)
        }
        var deduped: [ExternalEvent] = []
        var groups: [ExternalEventDedupeGroup] = []

        for (bucketKey, bucketEvents) in grouped {
            let sorted = bucketEvents.sorted { lhs, rhs in
                canonicalSort(lhs: lhs, rhs: rhs)
            }
            var clusters: [[ExternalEvent]] = []

            for event in sorted {
                if let clusterIndex = clusters.firstIndex(where: { cluster in
                    cluster.contains(where: { existing in
                        ExternalEventSupport.isLikelyDuplicate(existing, event)
                    })
                }) {
                    clusters[clusterIndex].append(event)
                } else {
                    clusters.append([event])
                }
            }

            for (clusterIndex, cluster) in clusters.enumerated() {
                let orderedCluster = cluster.sorted { lhs, rhs in
                    canonicalSort(lhs: lhs, rhs: rhs)
                }
                guard var canonical = orderedCluster.first else { continue }
                let mergedEventIDs = orderedCluster.map(\.id)
                for secondary in orderedCluster.dropFirst() {
                    canonical = ExternalEventSupport.merge(primary: canonical, secondary: secondary)
                }

                deduped.append(canonical)
                if orderedCluster.count > 1 {
                    groups.append(
                        ExternalEventDedupeGroup(
                            dedupeKey: "\(bucketKey)::\(clusterIndex)",
                            canonicalEventID: canonical.id,
                            mergedEventIDs: mergedEventIDs,
                            mergedSources: canonical.mergedSources,
                            reason: "Merged by shared day, fuzzy title match, and venue/metro overlap"
                        )
                    )
                }
            }
        }

        deduped.sort { lhs, rhs in
            switch (lhs.startAtUTC, rhs.startAtUTC) {
            case let (left?, right?):
                return left < right
            case (.some, nil):
                return true
            case (nil, .some):
                return false
            case (nil, nil):
                return lhs.title < rhs.title
            }
        }

        return (deduped, groups.sorted { $0.canonicalEventID < $1.canonicalEventID })
    }

    private nonisolated static func canonicalSort(lhs: ExternalEvent, rhs: ExternalEvent) -> Bool {
        let lhsScore = ExternalEventSupport.sourcePriority(for: lhs)
            + ExternalEventSupport.completenessScore(for: lhs)
            + ExternalEventSupport.qualityScore(for: lhs)
        let rhsScore = ExternalEventSupport.sourcePriority(for: rhs)
            + ExternalEventSupport.completenessScore(for: rhs)
            + ExternalEventSupport.qualityScore(for: rhs)
        if lhsScore == rhsScore {
            return lhs.id < rhs.id
        }
        return lhsScore > rhsScore
    }
}

enum ExternalEventCacheStore {
    private static let defaults = UserDefaults.standard
    private static let prefix = "external_event_cache::"
    private static let encoder = JSONEncoder()
    private static let decoder = JSONDecoder()

    private struct Envelope: Codable {
        let fetchedAt: Date
        let result: ExternalEventSourceResult
    }

    static func cacheKey(source: ExternalEventSource, query: ExternalEventQuery, page: Int) -> String {
        let keyParts = [
            source.rawValue,
            query.countryCode,
            query.city ?? "",
            query.state ?? "",
            query.postalCode ?? "",
            query.latitude.map { String(format: "%.3f", $0) } ?? "",
            query.longitude.map { String(format: "%.3f", $0) } ?? "",
            query.keyword ?? "",
            query.radiusMiles.map { String(format: "%.1f", $0) } ?? "",
            String(format: "%.1f", query.hyperlocalRadiusMiles),
            String(format: "%.1f", query.nightlifeRadiusMiles),
            String(format: "%.1f", query.headlineRadiusMiles),
            query.discoveryIntent.rawValue,
            String(query.pageSize),
            String(page),
            String(query.sourcePageDepth)
        ]
        return prefix + keyParts.joined(separator: "::")
    }

    static func save(result: ExternalEventSourceResult, forKey key: String) {
        let envelope = Envelope(fetchedAt: Date(), result: result)
        guard let data = try? encoder.encode(envelope) else { return }
        defaults.set(data, forKey: key)
    }

    static func load(forKey key: String) -> (fetchedAt: Date, result: ExternalEventSourceResult)? {
        guard let data = defaults.data(forKey: key),
              let envelope = try? decoder.decode(Envelope.self, from: data)
        else {
            return nil
        }
        return (envelope.fetchedAt, envelope.result)
    }
}
