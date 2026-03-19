import Foundation

nonisolated enum ExternalDiscoveryCacheQuality: String, Codable, Sendable {
    case fast
    case full
}

nonisolated struct SupabaseEventFeedCacheConfiguration: Sendable {
    var projectURL: URL?
    var anonKey: String?
    var schema: String = "public"
    var snapshotTable: String = "external_event_snapshots"
    var upsertRPC: String = "upsert_external_event_snapshot"

    static func fromEnvironment() -> SupabaseEventFeedCacheConfiguration {
        let env = ProcessInfo.processInfo.environment
        let runtimeSecrets = SupabaseRuntimeSecretsStore.load()
        return SupabaseEventFeedCacheConfiguration(
            projectURL: (env["SUPABASE_URL"] ?? runtimeSecrets["SUPABASE_URL"]).flatMap(URL.init(string:)),
            anonKey: env["SUPABASE_ANON_KEY"] ?? runtimeSecrets["SUPABASE_ANON_KEY"],
            schema: env["SUPABASE_SCHEMA"] ?? runtimeSecrets["SUPABASE_SCHEMA"] ?? "public",
            snapshotTable: env["SUPABASE_EXTERNAL_EVENT_SNAPSHOT_TABLE"] ?? runtimeSecrets["SUPABASE_EXTERNAL_EVENT_SNAPSHOT_TABLE"] ?? "external_event_snapshots",
            upsertRPC: env["SUPABASE_EXTERNAL_EVENT_UPSERT_RPC"] ?? runtimeSecrets["SUPABASE_EXTERNAL_EVENT_UPSERT_RPC"] ?? "upsert_external_event_snapshot"
        )
    }

    var isConfigured: Bool {
        guard projectURL != nil else { return false }
        guard let anonKey, !anonKey.isEmpty else { return false }
        return true
    }
}

private enum SupabaseRuntimeSecretsStore {
    private static let fileName = "SupabaseRuntimeSecrets.plist"

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

actor SupabaseEventFeedCacheService {
    static let shared = SupabaseEventFeedCacheService(configuration: .fromEnvironment())

    private struct SnapshotLoadCandidate {
        let snapshot: ExternalLocationDiscoverySnapshot
        let quality: ExternalDiscoveryCacheQuality
        let fetchedAt: Date?
        let city: String
        let state: String
        let displayName: String
        let latitude: Double?
        let longitude: Double?
        let bucketLatitude: Double?
        let bucketLongitude: Double?
    }

    private let configuration: SupabaseEventFeedCacheConfiguration
    private let session: URLSession
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    init(
        configuration: SupabaseEventFeedCacheConfiguration,
        session: URLSession? = nil
    ) {
        self.configuration = configuration
        if let session {
            self.session = session
        } else {
            let config = URLSessionConfiguration.ephemeral
            config.timeoutIntervalForRequest = 8
            config.timeoutIntervalForResource = 15
            self.session = URLSession(configuration: config)
        }
    }

    nonisolated var isConfigured: Bool {
        configuration.isConfigured
    }

    func load(
        searchLocation: ExternalEventSearchLocation,
        intent: ExternalDiscoveryIntent
    ) async -> ExternalLocationDiscoverySnapshot? {
        guard configuration.isConfigured else {
            return nil
        }

        if let request = makeLoadRequest(searchLocation: searchLocation, intent: intent),
           let rows = await fetchRows(for: request),
           let candidate = decodeCandidates(from: rows).first {
            return Self.sanitizedSnapshot(candidate.snapshot, intent: intent)
        }

        if let request = makeFallbackLoadRequest(searchLocation: searchLocation, intent: intent),
           let rows = await fetchRows(for: request),
           let candidate = Self.bestFallbackCandidate(from: decodeCandidates(from: rows), for: searchLocation) {
            return Self.sanitizedSnapshot(candidate.snapshot, intent: intent)
        }

        return nil
    }

    func save(
        snapshot: ExternalLocationDiscoverySnapshot,
        intent: ExternalDiscoveryIntent,
        quality: ExternalDiscoveryCacheQuality
    ) async {
        let sanitizedSnapshot = Self.sanitizedSnapshot(snapshot, intent: intent)
        guard configuration.isConfigured,
              let request = makeUpsertRequest(snapshot: sanitizedSnapshot, intent: intent, quality: quality)
        else {
            return
        }

        do {
            let (_, response) = try await session.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse,
                  200 ..< 300 ~= httpResponse.statusCode
            else {
                return
            }
        } catch {
            return
        }
    }

    private func makeLoadRequest(
        searchLocation: ExternalEventSearchLocation,
        intent: ExternalDiscoveryIntent
    ) -> URLRequest? {
        guard let projectURL = configuration.projectURL else { return nil }
        let cacheKey = Self.cacheKey(for: searchLocation, intent: intent)
        let retentionCutoff = Self.postgrestTimestamp(from: Date())

        var components = URLComponents(
            url: projectURL.appendingPathComponent("rest/v1/\(configuration.snapshotTable)"),
            resolvingAgainstBaseURL: false
        )
        components?.queryItems = [
            URLQueryItem(name: "select", value: "snapshot,fetched_at,expires_at,quality"),
            URLQueryItem(name: "cache_key", value: "eq.\(cacheKey)"),
            URLQueryItem(name: "intent", value: "eq.\(intent.rawValue)"),
            URLQueryItem(name: "expires_at", value: "gte.\(retentionCutoff)"),
            URLQueryItem(name: "order", value: "quality.desc,fetched_at.desc"),
            URLQueryItem(name: "limit", value: "1")
        ]

        guard let url = components?.url else { return nil }
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        applyHeaders(to: &request)
        request.setValue(configuration.schema, forHTTPHeaderField: "Accept-Profile")
        return request
    }

    private func makeFallbackLoadRequest(
        searchLocation: ExternalEventSearchLocation,
        intent: ExternalDiscoveryIntent
    ) -> URLRequest? {
        guard let projectURL = configuration.projectURL else { return nil }
        let retentionCutoff = Self.postgrestTimestamp(from: Date())

        var components = URLComponents(
            url: projectURL.appendingPathComponent("rest/v1/\(configuration.snapshotTable)"),
            resolvingAgainstBaseURL: false
        )

        var queryItems: [URLQueryItem] = [
            URLQueryItem(
                name: "select",
                value: "snapshot,fetched_at,expires_at,quality,city,state,display_name,latitude,longitude,bucket_latitude,bucket_longitude"
            ),
            URLQueryItem(name: "intent", value: "eq.\(intent.rawValue)"),
            URLQueryItem(name: "country_code", value: "eq.\(searchLocation.countryCode)"),
            URLQueryItem(name: "expires_at", value: "gte.\(retentionCutoff)"),
            URLQueryItem(name: "order", value: "quality.desc,fetched_at.desc"),
            URLQueryItem(name: "limit", value: "24")
        ]

        if let state = searchLocation.state?.trimmingCharacters(in: .whitespacesAndNewlines),
           !state.isEmpty {
            queryItems.append(URLQueryItem(name: "state", value: "eq.\(state)"))
        }

        components?.queryItems = queryItems

        guard let url = components?.url else { return nil }
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        applyHeaders(to: &request)
        request.setValue(configuration.schema, forHTTPHeaderField: "Accept-Profile")
        return request
    }

    private func makeUpsertRequest(
        snapshot: ExternalLocationDiscoverySnapshot,
        intent: ExternalDiscoveryIntent,
        quality: ExternalDiscoveryCacheQuality
    ) -> URLRequest? {
        guard let projectURL = configuration.projectURL else { return nil }
        let cacheKey = Self.cacheKey(for: snapshot.searchLocation, intent: intent)
        let coordinates = Self.coordinateBucket(for: snapshot.searchLocation)
        let snapshotPayload = Self.snapshotJSONObject(snapshot, encoder: encoder)
        let fetchedAt = snapshot.fetchedAt
        let expiresAt = fetchedAt.addingTimeInterval(Self.ttl(for: intent))

        var body: [String: Any] = [
            "p_cache_key": cacheKey,
            "p_intent": intent.rawValue,
            "p_quality": quality.rawValue,
            "p_country_code": snapshot.searchLocation.countryCode,
            "p_display_name": snapshot.searchLocation.displayName,
            "p_bucket_latitude": coordinates.latitude as Any,
            "p_bucket_longitude": coordinates.longitude as Any,
            "p_event_count": snapshot.mergedEvents.count,
            "p_exclusive_count": snapshot.mergedEvents.filter(ExternalEventSupport.isExclusiveEvent).count,
            "p_nightlife_count": snapshot.mergedEvents.filter { $0.eventType == .partyNightlife }.count,
            "p_snapshot": snapshotPayload,
            "p_fetched_at": Self.iso8601Timestamp(from: fetchedAt),
            "p_expires_at": Self.iso8601Timestamp(from: expiresAt)
        ]

        if let city = snapshot.searchLocation.city {
            body["p_city"] = city
        }
        if let state = snapshot.searchLocation.state {
            body["p_state"] = state
        }
        if let postalCode = snapshot.searchLocation.postalCode {
            body["p_postal_code"] = postalCode
        }
        if let latitude = snapshot.searchLocation.latitude {
            body["p_latitude"] = latitude
        }
        if let longitude = snapshot.searchLocation.longitude {
            body["p_longitude"] = longitude
        }

        guard let data = try? JSONSerialization.data(withJSONObject: body, options: []) else {
            return nil
        }

        let url = projectURL.appendingPathComponent("rest/v1/rpc/\(configuration.upsertRPC)")
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.httpBody = data
        applyHeaders(to: &request)
        request.setValue(configuration.schema, forHTTPHeaderField: "Content-Profile")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        return request
    }

    private func applyHeaders(to request: inout URLRequest) {
        guard let anonKey = configuration.anonKey else { return }
        request.setValue(anonKey, forHTTPHeaderField: "apikey")
        request.setValue("Bearer \(anonKey)", forHTTPHeaderField: "Authorization")
    }

    private func fetchRows(for request: URLRequest) async -> [[String: Any]]? {
        do {
            let (data, response) = try await session.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse,
                  200 ..< 300 ~= httpResponse.statusCode
            else {
                return nil
            }

            return try JSONSerialization.jsonObject(with: data) as? [[String: Any]]
        } catch {
            return nil
        }
    }

    private func decodeCandidates(from rows: [[String: Any]]) -> [SnapshotLoadCandidate] {
        rows.compactMap { row in
            guard let snapshotObject = row["snapshot"],
                  let snapshotData = try? JSONSerialization.data(withJSONObject: snapshotObject, options: []),
                  let snapshot = try? decoder.decode(ExternalLocationDiscoverySnapshot.self, from: snapshotData)
            else {
                return nil
            }

            let quality = (row["quality"] as? String).flatMap(ExternalDiscoveryCacheQuality.init(rawValue:)) ?? .fast
            let fetchedAt = Self.dateValue(from: row["fetched_at"])
            let city = (row["city"] as? String) ?? snapshot.searchLocation.city ?? ""
            let state = (row["state"] as? String) ?? snapshot.searchLocation.state ?? ""
            let displayName = (row["display_name"] as? String) ?? snapshot.searchLocation.displayName

            return SnapshotLoadCandidate(
                snapshot: snapshot,
                quality: quality,
                fetchedAt: fetchedAt,
                city: city,
                state: state,
                displayName: displayName,
                latitude: Self.doubleValue(from: row["latitude"]) ?? snapshot.searchLocation.latitude,
                longitude: Self.doubleValue(from: row["longitude"]) ?? snapshot.searchLocation.longitude,
                bucketLatitude: Self.doubleValue(from: row["bucket_latitude"]),
                bucketLongitude: Self.doubleValue(from: row["bucket_longitude"])
            )
        }
    }

    nonisolated private static func cacheKey(
        for searchLocation: ExternalEventSearchLocation,
        intent: ExternalDiscoveryIntent
    ) -> String {
        if let latitude = searchLocation.latitude,
           let longitude = searchLocation.longitude {
            let bucket = coordinateBucket(for: searchLocation)
            let bucketLatitude = bucket.latitude ?? latitude
            let bucketLongitude = bucket.longitude ?? longitude
            return [
                intent.rawValue,
                searchLocation.countryCode,
                String(format: "%.2f", bucketLatitude),
                String(format: "%.2f", bucketLongitude)
            ].joined(separator: "::")
        }

        return [
            intent.rawValue,
            searchLocation.countryCode,
            ExternalEventSupport.normalizeToken(searchLocation.city),
            ExternalEventSupport.normalizeStateToken(searchLocation.state),
            searchLocation.postalCode ?? ""
        ].joined(separator: "::")
    }

    nonisolated private static func coordinateBucket(
        for searchLocation: ExternalEventSearchLocation
    ) -> (latitude: Double?, longitude: Double?) {
        guard let latitude = searchLocation.latitude,
              let longitude = searchLocation.longitude
        else {
            return (nil, nil)
        }

        func bucket(_ value: Double, step: Double) -> Double {
            (value / step).rounded() * step
        }

        let step = isHighDensityMetro(searchLocation) ? 0.12 : 0.08
        return (bucket(latitude, step: step), bucket(longitude, step: step))
    }

    nonisolated private static func ttl(for intent: ExternalDiscoveryIntent) -> TimeInterval {
        switch intent {
        case .biggestTonight:
            return 2 * 24 * 60 * 60
        case .lastMinutePlans:
            return 24 * 60 * 60
        case .exclusiveHot:
            return 3 * 24 * 60 * 60
        case .nearbyWorthIt:
            return 4 * 24 * 60 * 60
        }
    }

    nonisolated static func freshnessWindow(
        for intent: ExternalDiscoveryIntent,
        searchLocation: ExternalEventSearchLocation
    ) -> TimeInterval {
        let isMajorMetro = isHighDensityMetro(searchLocation)

        switch intent {
        case .exclusiveHot:
            return isMajorMetro ? 60 * 60 : 3 * 60 * 60
        case .biggestTonight:
            return isMajorMetro ? 90 * 60 : 4 * 60 * 60
        case .lastMinutePlans:
            return isMajorMetro ? 60 * 60 : 3 * 60 * 60
        case .nearbyWorthIt:
            return isMajorMetro ? 6 * 60 * 60 : 24 * 60 * 60
        }
    }

    nonisolated static func isFresh(
        snapshot: ExternalLocationDiscoverySnapshot,
        intent: ExternalDiscoveryIntent
    ) -> Bool {
        let age = Date().timeIntervalSince(snapshot.fetchedAt)
        return age <= freshnessWindow(for: intent, searchLocation: snapshot.searchLocation)
    }

    nonisolated private static func isHighDensityMetro(_ searchLocation: ExternalEventSearchLocation) -> Bool {
        let metroTokens = Set([
            "los angeles", "west hollywood", "hollywood", "new york", "manhattan", "miami beach",
            "miami", "chicago", "austin", "dallas", "nashville", "las vegas", "atlanta",
            "houston", "seattle", "phoenix", "denver", "boston", "philadelphia", "san francisco",
            "san diego", "san jose", "oakland", "portland", "sacramento", "washington",
            "washington dc", "district of columbia", "baltimore", "orlando", "tampa",
            "charlotte", "raleigh", "detroit", "minneapolis", "st louis", "new orleans",
            "columbus", "cleveland", "cincinnati", "pittsburgh", "indianapolis", "milwaukee",
            "salt lake city", "kansas city"
        ])

        let haystack = [
            searchLocation.displayName,
            searchLocation.city,
            searchLocation.state
        ]
        .compactMap { $0 }
        .map(ExternalEventSupport.normalizeToken)
        .joined(separator: " ")

        return metroTokens.contains(where: haystack.contains)
    }

    nonisolated private static func bestFallbackCandidate(
        from candidates: [SnapshotLoadCandidate],
        for searchLocation: ExternalEventSearchLocation
    ) -> SnapshotLoadCandidate? {
        guard !candidates.isEmpty else { return nil }

        return candidates.max { lhs, rhs in
            let lhsScore = fallbackMatchScore(candidate: lhs, searchLocation: searchLocation)
            let rhsScore = fallbackMatchScore(candidate: rhs, searchLocation: searchLocation)
            if lhsScore != rhsScore {
                return lhsScore < rhsScore
            }

            if lhs.quality != rhs.quality {
                return lhs.quality == .fast
            }

            let lhsDistance = approximateDistanceMiles(candidate: lhs, searchLocation: searchLocation) ?? .greatestFiniteMagnitude
            let rhsDistance = approximateDistanceMiles(candidate: rhs, searchLocation: searchLocation) ?? .greatestFiniteMagnitude
            if lhsDistance != rhsDistance {
                return lhsDistance > rhsDistance
            }

            let lhsDate = lhs.fetchedAt ?? .distantPast
            let rhsDate = rhs.fetchedAt ?? .distantPast
            return lhsDate < rhsDate
        }
    }

    nonisolated private static func fallbackMatchScore(
        candidate: SnapshotLoadCandidate,
        searchLocation: ExternalEventSearchLocation
    ) -> Int {
        let normalizedSearchCity = ExternalEventSupport.normalizeToken(searchLocation.city)
        let normalizedSearchState = ExternalEventSupport.normalizeStateToken(searchLocation.state)
        let normalizedCandidateCity = ExternalEventSupport.normalizeToken(candidate.city)
        let normalizedCandidateDisplay = ExternalEventSupport.normalizeToken(candidate.displayName)
        let normalizedCandidateState = ExternalEventSupport.normalizeStateToken(candidate.state)

        var score = 0

        if !normalizedSearchCity.isEmpty {
            if normalizedCandidateCity == normalizedSearchCity {
                score += 220
            } else if normalizedCandidateDisplay.contains(normalizedSearchCity)
                        || normalizedSearchCity.contains(normalizedCandidateCity) {
                score += 140
            }
        }

        if !normalizedSearchState.isEmpty, normalizedSearchState == normalizedCandidateState {
            score += 50
        }

        if let distanceMiles = approximateDistanceMiles(candidate: candidate, searchLocation: searchLocation) {
            switch distanceMiles {
            case ..<5:
                score += 90
            case ..<12:
                score += 70
            case ..<25:
                score += 45
            case ..<40:
                score += 20
            default:
                break
            }
        }

        return score
    }

    nonisolated private static func approximateDistanceMiles(
        candidate: SnapshotLoadCandidate,
        searchLocation: ExternalEventSearchLocation
    ) -> Double? {
        guard let searchLatitude = searchLocation.latitude,
              let searchLongitude = searchLocation.longitude
        else {
            return nil
        }

        let candidateLatitude = candidate.latitude ?? candidate.bucketLatitude
        let candidateLongitude = candidate.longitude ?? candidate.bucketLongitude
        guard let candidateLatitude, let candidateLongitude else {
            return nil
        }

        let latitudeMiles = (candidateLatitude - searchLatitude) * 69.0
        let longitudeMiles = (candidateLongitude - searchLongitude) * max(cos(searchLatitude * .pi / 180.0), 0.1) * 69.0
        return sqrt(latitudeMiles * latitudeMiles + longitudeMiles * longitudeMiles)
    }

    nonisolated private static func dateValue(from rawValue: Any?) -> Date? {
        guard let string = rawValue as? String else { return nil }
        return ExternalEventSupport.iso8601Formatter.date(from: string)
            ?? ExternalEventSupport.iso8601NoFractionalSeconds.date(from: string)
    }

    nonisolated private static func doubleValue(from rawValue: Any?) -> Double? {
        if let value = rawValue as? Double {
            return value
        }
        if let value = rawValue as? NSNumber {
            return value.doubleValue
        }
        if let value = rawValue as? String {
            return Double(value)
        }
        return nil
    }

    nonisolated private static func snapshotJSONObject(
        _ snapshot: ExternalLocationDiscoverySnapshot,
        encoder: JSONEncoder
    ) -> Any {
        guard let data = try? encoder.encode(snapshot),
              let object = try? JSONSerialization.jsonObject(with: data, options: [])
        else {
            return [:]
        }
        return object
    }

    nonisolated private static func iso8601Timestamp(from date: Date) -> String {
        if let string = ExternalEventSupport.iso8601Formatter.string(from: date) as String? {
            return string
        }
        return ExternalEventSupport.iso8601NoFractionalSeconds.string(from: date)
    }

    nonisolated private static func postgrestTimestamp(from date: Date) -> String {
        ExternalEventSupport.iso8601NoFractionalSeconds.string(from: date)
    }

    nonisolated private static func sanitizedSnapshot(
        _ snapshot: ExternalLocationDiscoverySnapshot,
        intent: ExternalDiscoveryIntent
    ) -> ExternalLocationDiscoverySnapshot {
        let sanitizedMergedEvents = sanitizedEvents(snapshot.mergedEvents, intent: intent)
        let sanitizedSourceResults = snapshot.eventSnapshot.sourceResults.map { result in
            ExternalEventSourceResult(
                source: result.source,
                usedCache: result.usedCache,
                fetchedAt: result.fetchedAt,
                endpoints: result.endpoints,
                note: result.note,
                nextCursor: result.nextCursor,
                events: sanitizedEvents(result.events, intent: intent)
            )
        }
        let sanitizedEventSnapshot = ExternalEventIngestionSnapshot(
            fetchedAt: snapshot.eventSnapshot.fetchedAt,
            query: snapshot.eventSnapshot.query,
            sourceResults: sanitizedSourceResults,
            mergedEvents: sanitizedMergedEvents,
            dedupeGroups: snapshot.eventSnapshot.dedupeGroups
        )

        return ExternalLocationDiscoverySnapshot(
            fetchedAt: snapshot.fetchedAt,
            searchLocation: snapshot.searchLocation,
            appliedProfiles: snapshot.appliedProfiles,
            venueSnapshot: snapshot.venueSnapshot,
            eventSnapshot: sanitizedEventSnapshot,
            mergedEvents: sanitizedMergedEvents,
            notes: snapshot.notes
        )
    }

    nonisolated private static func sanitizedEvents(
        _ events: [ExternalEvent],
        intent: ExternalDiscoveryIntent
    ) -> [ExternalEvent] {
        events.compactMap { event in
            let sanitized = ExternalEventSupport.sanitizedGoogleReviewIdentity(
                repairedNightlifeEvent(event)
            )
            guard shouldKeepInCachedSnapshot(sanitized, intent: intent) else {
                return nil
            }
            return sanitized
        }
    }

    nonisolated private static func repairedNightlifeEvent(_ event: ExternalEvent) -> ExternalEvent {
        guard event.eventType == .partyNightlife || event.recordKind == .venueNight else {
            return event
        }

        var repaired = event
        let payload = decodedPayload(from: repaired.rawSourcePayload)
        repaired.imageURL = ExternalEventSupport.preferredNightlifeImageURL(
            primary: repaired.imageURL,
            payload: repaired.rawSourcePayload
        )
        if repaired.venueRating == nil {
            let ratingCandidates: [Any?] = [
                payload["google_places_rating"],
                payload["google_rating"],
                payload["yelp_rating"],
                payload["venue_rating"],
                payload["rating"],
                (payload["venue"] as? [String: Any])?["rating"],
                (payload["place"] as? [String: Any])?["rating"]
            ]
            repaired.venueRating = ratingCandidates
                .lazy
                .compactMap(ExternalEventSupport.parseDouble)
                .first(where: { $0 >= 1.0 && $0 <= 5.0 })
        }
        if repaired.venuePopularityCount == nil {
            let reviewCountCandidates: [Any?] = [
                payload["google_places_user_rating_count"],
                payload["google_places_userRatingCount"],
                payload["userRatingCount"],
                payload["ratingCount"],
                payload["yelp_review_count"],
                payload["review_count"],
                payload["reviewCount"],
                payload["venue_reviews"],
                payload["reviews"],
                (payload["venue"] as? [String: Any])?["reviews"],
                (payload["place"] as? [String: Any])?["reviews"]
            ]
            repaired.venuePopularityCount = reviewCountCandidates
                .lazy
                .compactMap(ExternalEventSupport.parseInt)
                .first(where: { $0 > 0 })
        }
        if repaired.startLocal == nil {
            repaired.startLocal = firstPayloadString(payload, keys: [
                "clubbable_start_local",
                "official_site_start_local"
            ])
        }
        if repaired.endLocal == nil {
            repaired.endLocal = firstPayloadString(payload, keys: [
                "clubbable_end_local",
                "official_site_end_local"
            ])
        }
        if repaired.openingHoursText == nil {
            repaired.openingHoursText = firstPayloadScheduleText(payload, keys: [
                "apple_maps_hours_text",
                "apple_maps_schedule_text",
                "official_site_hours",
                "clubbable_schedule_display",
                "clubbable_time_range",
                "discotech_open_answer"
            ])
        }
        if repaired.addressLine1 == nil || ExternalEventSupport.isWeakAddressLine(
            repaired.addressLine1,
            city: repaired.city,
            state: repaired.state
        ) {
            let payloadAddress = firstPayloadAddress(payload, keys: [
                "apple_maps_address_line_1",
                "clubbable_address_line_1",
                "official_site_address",
                "google_places_address",
                "yelp_address_line_1",
                "clubbable_full_address",
                "apple_maps_full_address"
            ])
            repaired.addressLine1 = ExternalEventSupport.preferredAddressLine(
                primary: repaired.addressLine1,
                primaryCity: repaired.city,
                primaryState: repaired.state,
                secondary: payloadAddress?.addressLine1,
                secondaryCity: payloadAddress?.city,
                secondaryState: payloadAddress?.state
            )
            repaired.city = repaired.city ?? payloadAddress?.city
            repaired.state = repaired.state ?? payloadAddress?.state
            repaired.postalCode = repaired.postalCode ?? payloadAddress?.postalCode
        }
        if repaired.city == nil {
            repaired.city = firstPayloadString(payload, keys: [
                "apple_maps_city",
                "clubbable_city",
                "official_site_city",
                "google_places_city",
                "yelp_city"
            ])
        }
        if repaired.state == nil {
            repaired.state = firstPayloadString(payload, keys: [
                "apple_maps_state",
                "clubbable_state",
                "official_site_state",
                "google_places_state",
                "yelp_state"
            ])
        }
        if repaired.postalCode == nil {
            repaired.postalCode = firstPayloadString(payload, keys: [
                "apple_maps_postal_code",
                "clubbable_postal_code",
                "official_site_postal_code",
                "google_places_postal_code",
                "yelp_postal_code"
            ])
        }
        return repaired
    }

    nonisolated private static func decodedPayload(from rawSourcePayload: String) -> [String: Any] {
        guard let data = rawSourcePayload.data(using: .utf8),
              let payload = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else {
            return [:]
        }
        return payload
    }

    nonisolated private static func firstPayloadString(
        _ payload: [String: Any],
        keys: [String]
    ) -> String? {
        for key in keys {
            guard let value = payload[key] as? String,
                  let cleaned = ExternalEventSupport.plainText(value)?
                    .trimmingCharacters(in: .whitespacesAndNewlines),
                  !cleaned.isEmpty
            else {
                continue
            }
            return cleaned
        }
        return nil
    }

    nonisolated private static func firstPayloadScheduleText(
        _ payload: [String: Any],
        keys: [String]
    ) -> String? {
        for key in keys {
            guard let value = firstPayloadString(payload, keys: [key]) else { continue }
            let normalized = ExternalEventSupport.normalizeToken(value)
            if value.range(of: #"(?i)\b\d{1,2}(?::\d{2})?\s*(?:am|pm)\b"#, options: .regularExpression) != nil {
                return value
            }
            let weekdaySignals = ["monday", "tuesday", "wednesday", "thursday", "friday", "saturday", "sunday", "tonight", "today"]
            let timingSignals = ["open", "opens", "close", "closes", "hours", "until", "pm", "am"]
            if weekdaySignals.contains(where: normalized.contains),
               timingSignals.contains(where: normalized.contains) {
                return value
            }
        }
        return nil
    }

    nonisolated private static func firstPayloadAddressLine(
        _ payload: [String: Any],
        keys: [String]
    ) -> String? {
        firstPayloadAddress(payload, keys: keys)?.addressLine1
    }

    nonisolated private static func firstPayloadAddress(
        _ payload: [String: Any],
        keys: [String]
    ) -> (
        addressLine1: String?,
        city: String?,
        state: String?,
        postalCode: String?
    )? {
        for key in keys {
            guard let value = firstPayloadString(payload, keys: [key]) else { continue }
            if let parsed = parseAddressComponents(from: value) {
                return parsed
            }
            let primaryLine = value
                .components(separatedBy: ",")
                .first?
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if let primaryLine, !primaryLine.isEmpty {
                return (
                    addressLine1: primaryLine,
                    city: nil,
                    state: nil,
                    postalCode: nil
                )
            }
        }
        return nil
    }

    nonisolated private static func parseAddressComponents(
        from rawValue: String
    ) -> (
        addressLine1: String?,
        city: String?,
        state: String?,
        postalCode: String?
    )? {
        guard let cleaned = ExternalEventSupport.plainText(rawValue), !cleaned.isEmpty else {
            return nil
        }

        let streetPattern = #"\b\d{1,6}\s+[A-Za-z0-9.'#\-]+\b(?:\s+[A-Za-z0-9.'#\-]+){0,8}\s+(?:ave|avenue|blvd|boulevard|st|street|rd|road|dr|drive|ln|lane|way|pkwy|parkway|pl|place|ct|court|ter|terrace|cir|circle|hwy|highway)\b\.?"#
        guard let streetRange = cleaned.range(of: streetPattern, options: [.regularExpression, .caseInsensitive]) else {
            return nil
        }

        let street = String(cleaned[streetRange]).trimmingCharacters(in: .whitespacesAndNewlines)
        let prefix = cleaned[..<streetRange.lowerBound]
            .replacingOccurrences(of: ",", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let suffix = cleaned[streetRange.upperBound...]
            .replacingOccurrences(of: ",", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let localitySeed = [String(prefix), String(suffix)]
            .joined(separator: " ")
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)

        let postalCode = firstRegexMatch(in: localitySeed, pattern: #"\b\d{5}(?:-\d{4})?\b"#)
        let state = firstRegexMatch(in: localitySeed, pattern: #"\b([A-Z]{2})\b"#)?.uppercased()
        let city = parseAddressCity(from: localitySeed, excludingState: state, postalCode: postalCode)

        return (
            addressLine1: street,
            city: city,
            state: state,
            postalCode: postalCode
        )
    }

    nonisolated private static func parseAddressCity(
        from value: String,
        excludingState state: String?,
        postalCode: String?
    ) -> String? {
        var cleaned = value
        if let postalCode {
            cleaned = cleaned.replacingOccurrences(of: postalCode, with: " ")
        }
        if let state {
            cleaned = cleaned.replacingOccurrences(
                of: #"\b\#(state)\b"#,
                with: " ",
                options: [.regularExpression, .caseInsensitive]
            )
        }
        cleaned = cleaned
            .replacingOccurrences(of: "USA", with: " ")
            .replacingOccurrences(of: "United States", with: " ")
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)

        let parts = cleaned
            .components(separatedBy: ",")
            .flatMap { $0.components(separatedBy: "  ") }
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        if let direct = parts.first(where: { !$0.contains(where: \.isNumber) && ExternalEventSupport.normalizeStateToken($0).count != 2 }) {
            return direct.capitalized
        }

        guard !cleaned.isEmpty, !cleaned.contains(where: \.isNumber) else {
            return nil
        }
        return cleaned.capitalized
    }

    nonisolated private static func firstRegexMatch(
        in value: String,
        pattern: String
    ) -> String? {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: []) else {
            return nil
        }
        let range = NSRange(value.startIndex..<value.endIndex, in: value)
        guard let match = regex.firstMatch(in: value, options: [], range: range),
              let matchRange = Range(match.range(at: match.numberOfRanges > 1 ? 1 : 0), in: value)
        else {
            return nil
        }
        return String(value[matchRange])
    }

    nonisolated private static func shouldKeepInCachedSnapshot(
        _ event: ExternalEvent,
        intent: ExternalDiscoveryIntent
    ) -> Bool {
        if ExternalEventSupport.shouldSuppressLowSignalEvent(event) {
            return false
        }

        if event.eventType == .partyNightlife || event.recordKind == .venueNight {
            if !ExternalEventSupport.hasUsableNightlifeImage(for: event) {
                return false
            }
        }

        switch intent {
        case .exclusiveHot:
            return event.isUpcoming || event.recordKind == .venueNight
        case .biggestTonight, .nearbyWorthIt, .lastMinutePlans:
            return true
        }
    }
}
