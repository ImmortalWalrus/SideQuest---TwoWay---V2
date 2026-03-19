import Foundation
import MapKit
#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

protocol ExternalVenueSourceAdapter: Sendable {
    var source: ExternalEventSource { get }
    func discoverVenues(
        query: ExternalVenueQuery,
        session: URLSession,
        configuration: ExternalEventServiceConfiguration
    ) async -> ExternalVenueSourceResult
}

protocol NightlifeVenueEnrichmentAdapter: Sendable {
    var source: ExternalEventSource { get }
    func enrichVenues(
        _ venues: [ExternalVenue],
        query: ExternalVenueQuery,
        session: URLSession,
        configuration: ExternalEventServiceConfiguration
    ) async -> ExternalVenueSourceResult
}

private nonisolated func nightlifeTextQualityScore(_ value: String) -> Int {
    let normalized = ExternalEventSupport.normalizeToken(value)
    var score = 0
    if normalized.contains("highlighted in discotech s market guide") { score -= 10 }
    if normalized.contains("listed by h wood rolodex") { score -= 8 }
    if normalized.contains("recognized by h wood rolodex") { score -= 6 }
    if normalized.contains("guest list access is available") { score -= 4 }
    if normalized.contains("photos and info") || normalized.contains("best promoters here") { score -= 6 }
    if normalized.contains("ultimate guide") || normalized.contains("general info") { score -= 8 }
    if normalized.contains("all the best vip nightclubs in london") { score -= 18 }
    if normalized.contains("all the promoters") || normalized.contains("club managers owners") { score -= 14 }
    if normalized.contains("located between") || normalized.contains("located in the heart") { score -= 12 }
    if normalized.contains("between beverly hills and west hollywood") { score -= 12 }

    let narrativeTokens = [
        "music", "dj", "hip hop", "r b", "r&b", "edm", "top 40", "crowd", "dance",
        "vibe", "luxury", "upscale", "intimate", "celebrit", "a list", "cocktail",
        "rooftop", "supper club", "dark", "glamour", "atmosphere", "energy", "scene"
    ]
    if narrativeTokens.contains(where: normalized.contains) { score += 6 }
    let accessTokens = [
        "bottle service only", "hard door", "guest list", "table", "cover", "dress code"
    ]
    if accessTokens.contains(where: normalized.contains) { score += 3 }
    if looksLikeVenueHoursText(value) { score += 8 }
    score += min(value.count / 60, 5)
    return score
}

private nonisolated func hasDiscotechCoverage(_ value: String) -> Bool {
    value.contains("discotech")
}

private nonisolated func hasClubbableCoverage(_ value: String) -> Bool {
    value.contains("clubbable")
}

private nonisolated func hasHWoodCoverage(_ value: String) -> Bool {
    value.contains("hwood") || value.contains("rolodex")
}

private nonisolated func isWeakHWoodOnlyCoverage(_ value: String) -> Bool {
    hasHWoodCoverage(value) && !hasDiscotechCoverage(value) && !hasClubbableCoverage(value)
}

private nonisolated func looksLikeVenueHoursText(_ value: String?) -> Bool {
    guard let value = ExternalEventSupport.plainText(value), !value.isEmpty else { return false }
    let normalized = ExternalEventSupport.normalizeToken(value)

    let blockedTokens = [
        "located between",
        "located in the heart",
        "all the best vip nightclubs in london",
        "all the promoters",
        "club managers owners",
        "membership program",
        "bespoke membership"
    ]
    guard !blockedTokens.contains(where: normalized.contains) else {
        return false
    }

    let weekdayTokens = ["monday", "tuesday", "wednesday", "thursday", "friday", "saturday", "sunday", "mon", "tue", "wed", "thu", "fri", "sat", "sun"]
    let timeTokens = ["am", "pm", "midnight", "noon", "hours", "open", "opens", "close", "closes", "tonight", "until", "till"]
    let hasClockTime = value.range(
        of: #"(?i)\b\d{1,2}(?::\d{2})?\s*(?:am|pm)\b"#,
        options: .regularExpression
    ) != nil

    if hasClockTime { return true }
    if (normalized.contains("open tonight") || normalized.contains("opens at") || normalized.contains("open from")),
       hasClockTime {
        return true
    }
    return false
}

private nonisolated func firstRegexMatchInText(
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

private nonisolated func sanitizedVenueHoursText(_ value: String?) -> String? {
    guard let value = ExternalEventSupport.plainText(value), !value.isEmpty else { return nil }
    guard looksLikeVenueHoursText(value) else { return nil }
    if let snippet = extractedVenueHoursSnippet(from: value) {
        return snippet
    }

    let singleLine = value
        .replacingOccurrences(of: "\n", with: " ")
        .trimmingCharacters(in: .whitespacesAndNewlines)
    let hasClockTime = singleLine.range(
        of: #"(?i)\b\d{1,2}(?::\d{2})?\s*(?:am|pm)\b"#,
        options: .regularExpression
    ) != nil
    if singleLine.count <= 80,
       hasClockTime,
       !singleLine.contains("."),
       !singleLine.contains("?"),
       !singleLine.contains("!") {
        return singleLine
    }
    return nil
}

private nonisolated func extractedVenueHoursSnippet(from value: String) -> String? {
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

private nonisolated func isTrustedOfficialSiteURL(_ value: String?) -> Bool {
    guard let value,
          let url = URL(string: value),
          let host = url.host?.lowercased()
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
        "g.co",
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

private nonisolated func preferredOfficialSiteURL(primary: String?, secondary: String?) -> String? {
    [primary, secondary]
        .compactMap { candidate -> String? in
            guard isTrustedOfficialSiteURL(candidate) else { return nil }
            return candidate
        }
        .first
}

nonisolated struct AppleMapsVenueMediaAdapter: NightlifeVenueEnrichmentAdapter {
    let source: ExternalEventSource = .appleMaps

    func enrichVenues(
        _ venues: [ExternalVenue],
        query: ExternalVenueQuery,
        session: URLSession,
        configuration: ExternalEventServiceConfiguration
    ) async -> ExternalVenueSourceResult {
        let targets = Array(
            venues
                .filter { shouldEnrichAppleMapsData(for: $0) }
                .sorted { lhs, rhs in
                    appleMapsTargetScore(for: lhs) > appleMapsTargetScore(for: rhs)
                }
                .prefix(88)
        )

        guard !targets.isEmpty else {
            return ExternalVenueSourceResult(
                source: source,
                fetchedAt: Date(),
                endpoints: [],
                note: "No Apple Maps venue media enrichment targets were available.",
                venues: []
            )
        }

        var endpoints: [ExternalEventEndpointResult] = []
        var enriched: [ExternalVenue] = []
        await withTaskGroup(of: (ExternalEventEndpointResult, ExternalVenue?).self) { group in
            for venue in targets {
                group.addTask {
                    await enrichVenue(venue, query: query)
                }
            }

            for await result in group {
                endpoints.append(result.0)
                if let venue = result.1 {
                    enriched.append(venue)
                }
            }
        }

        return ExternalVenueSourceResult(
            source: source,
            fetchedAt: Date(),
            endpoints: endpoints,
            note: enriched.isEmpty ? "Apple Maps media enrichment did not yield stronger venue media." : nil,
            venues: enriched
        )
    }

    private func enrichVenue(
        _ venue: ExternalVenue,
        query: ExternalVenueQuery
    ) async -> (endpoint: ExternalEventEndpointResult, venue: ExternalVenue?) {
        do {
            let center = CLLocationCoordinate2D(
                latitude: venue.latitude ?? query.latitude,
                longitude: venue.longitude ?? query.longitude
            )
            let searchTerms = appleMapsSearchTerms(for: venue, query: query)
            let searchRadiusMeters = max(2200.0, min(query.nightlifeRadiusMiles * 1609.344, 7200.0))
            var candidates: [MKMapItem] = []
            var requestLabels: [String] = []

            for searchTerm in searchTerms.prefix(4) {
                let request = MKLocalSearch.Request()
                request.naturalLanguageQuery = searchTerm
                request.resultTypes = .pointOfInterest
                request.region = MKCoordinateRegion(
                    center: center,
                    latitudinalMeters: searchRadiusMeters,
                    longitudinalMeters: searchRadiusMeters
                )

                let response = try await MKLocalSearch(request: request).start()
                candidates.append(contentsOf: response.mapItems)
                requestLabels.append(searchTerm)
            }

            let item = bestMatch(from: candidates, venue: venue, center: center)
            guard let item else {
                return (
                    ExternalEventEndpointResult(
                        label: "Apple Maps media \(venue.name)",
                        requestURL: "mapkit://local-search/\(requestLabels.joined(separator: "|"))",
                        responseStatusCode: 200,
                        worked: true,
                        note: "No strong Apple Maps venue match for media enrichment."
                    ),
                    nil
                )
            }

            var updated = venue
            let address = appleMapsAddress(from: item)
            updated.sourceType = .venueDiscoveryAPI; if let itemName = item.name, !itemName.isEmpty { updated.aliases = Array(Set(updated.aliases + [itemName])).sorted() }
            updated.officialSiteURL = preferredOfficialSiteURL(
                primary: updated.officialSiteURL,
                secondary: item.url?.absoluteString
            )
            updated.addressLine1 = ExternalEventSupport.preferredAddressLine(
                primary: updated.addressLine1,
                primaryCity: updated.city,
                primaryState: updated.state,
                secondary: address.line1,
                secondaryCity: address.city,
                secondaryState: address.state
            )
            updated.city = updated.city ?? address.city
            updated.state = updated.state ?? address.state
            updated.postalCode = updated.postalCode ?? address.postalCode
            updated.country = updated.country ?? address.country ?? updated.country
            updated.latitude = updated.latitude ?? item.placemark.coordinate.latitude
            updated.longitude = updated.longitude ?? item.placemark.coordinate.longitude
            if let fileURL = try await lookAroundFileURL(for: item, cacheKey: venue.sourceVenueID) {
                updated.imageURL = ExternalEventSupport.preferredImageURL(
                    primary: updated.imageURL,
                    secondary: fileURL.absoluteString
                )
            }
            updated.sourceConfidence = max(updated.sourceConfidence ?? 0, 0.86)
            updated.sourceCoverageStatus = mergeCoverageStatus(updated.sourceCoverageStatus, "Apple Maps media")
            updated.rawSourcePayload = mergePayload(
                updated.rawSourcePayload,
                extra: [
                    "apple_maps_url": item.url?.absoluteString as Any,
                    "apple_maps_phone": item.phoneNumber as Any,
                    "apple_maps_place_category": item.pointOfInterestCategory?.rawValue as Any,
                    "apple_maps_name": item.name as Any,
                    "apple_maps_address_line_1": updated.addressLine1 as Any,
                    "apple_maps_city": updated.city as Any,
                    "apple_maps_state": updated.state as Any,
                    "apple_maps_postal_code": updated.postalCode as Any,
                    "apple_maps_full_address": address.fullAddress as Any,
                    "apple_maps_hours_text": updated.openingHoursText as Any,
                    "apple_maps_file_image": updated.imageURL as Any,
                    "apple_maps_image_gallery": updated.imageURL.map { [$0] } as Any
                ]
            )

            return (
                ExternalEventEndpointResult(
                    label: "Apple Maps media \(venue.name)",
                    requestURL: "mapkit://local-search/\(requestLabels.joined(separator: "|"))",
                    responseStatusCode: 200,
                    worked: true,
                    note: updated.imageURL == venue.imageURL ? "Apple Maps matched venue metadata but did not produce a stronger image." : nil
                ),
                updated
            )
        } catch {
            return (
                    ExternalEventEndpointResult(
                        label: "Apple Maps media \(venue.name)",
                        requestURL: "mapkit://local-search/\(venue.name)",
                        responseStatusCode: nil,
                        worked: false,
                        note: error.localizedDescription
                    ),
                    nil
                )
        }
    }

    private func lookAroundFileURL(for item: MKMapItem, cacheKey: String) async throws -> URL? {
        let fileManager = FileManager.default
        let directory = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent("sidequest_apple_venue_media", isDirectory: true)
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)

        let normalizedKey = ExternalEventSupport.normalizeToken(cacheKey).replacingOccurrences(of: " ", with: "-")
        let filename = normalizedKey.isEmpty ? UUID().uuidString : normalizedKey
        let targetURL = directory.appendingPathComponent("\(filename).jpg")
        if fileManager.fileExists(atPath: targetURL.path) {
            return targetURL
        }

        let sceneRequest = MKLookAroundSceneRequest(mapItem: item)
        guard let scene = try await sceneRequest.scene else {
            return nil
        }

        let options = MKLookAroundSnapshotter.Options()
        options.size = CGSize(width: 1400, height: 840)
        #if canImport(UIKit)
        options.traitCollection = UITraitCollection(displayScale: 2)
        #endif
        let snapshotter = MKLookAroundSnapshotter(scene: scene, options: options)
        let snapshot = try await snapshotter.snapshot
        let data: Data?
        #if canImport(UIKit)
        data = snapshot.image.jpegData(compressionQuality: 0.82)
        #elseif canImport(AppKit)
        if let tiffData = snapshot.image.tiffRepresentation,
           let bitmap = NSBitmapImageRep(data: tiffData) {
            data = bitmap.representation(using: .jpeg, properties: [.compressionFactor: 0.82])
        } else {
            data = nil
        }
        #else
        data = nil
        #endif
        guard let data else {
            return nil
        }
        try data.write(to: targetURL, options: Data.WritingOptions.atomic)
        return targetURL
    }

    private func bestMatch(
        from items: [MKMapItem],
        venue: ExternalVenue,
        center: CLLocationCoordinate2D
    ) -> MKMapItem? {
        let venueTokens = Set(
            appleMapsSearchTerms(
                for: venue,
                query: ExternalVenueQuery(
                    countryCode: venue.country ?? "US",
                    city: venue.city,
                    state: venue.state,
                    displayName: venue.city,
                    latitude: venue.latitude ?? center.latitude,
                    longitude: venue.longitude ?? center.longitude
                )
            )
            .map { ExternalEventSupport.normalizeToken($0) }
        )
        let targetLocation = CLLocation(latitude: center.latitude, longitude: center.longitude)

        return items.max { lhs, rhs in
            score(for: lhs, venueTokens: venueTokens, venue: venue, targetLocation: targetLocation)
                < score(for: rhs, venueTokens: venueTokens, venue: venue, targetLocation: targetLocation)
        }
    }

    private func score(
        for item: MKMapItem,
        venueTokens: Set<String>,
        venue: ExternalVenue,
        targetLocation: CLLocation
    ) -> Double {
        let itemToken = ExternalEventSupport.normalizeToken(item.name)
        var score = 0.0
        if venueTokens.contains(itemToken) {
            score += 10
        } else if venueTokens.contains(where: { token in
            !token.isEmpty && (itemToken.contains(token) || token.contains(itemToken))
        }) {
            score += 7.5
        }

        let distance = targetLocation.distance(from: CLLocation(
            latitude: item.placemark.coordinate.latitude,
            longitude: item.placemark.coordinate.longitude
        ))
        score -= min(distance / 250.0, 8.0)
        if item.url != nil { score += 1.5 }
        if item.phoneNumber != nil { score += 1.0 }
        if let venueCity = venue.city,
           ExternalEventSupport.normalizeToken(venueCity) == ExternalEventSupport.normalizeToken(item.placemark.locality) {
            score += 1.4
        }
        if let venueState = venue.state,
           ExternalEventSupport.normalizeStateToken(venueState) == ExternalEventSupport.normalizeStateToken(item.placemark.administrativeArea) {
            score += 0.8
        }
        return score
    }

    private func shouldEnrichAppleMapsData(for venue: ExternalVenue) -> Bool {
        guard venue.latitude != nil || venue.longitude != nil || venue.city != nil || venue.state != nil else {
            return false
        }
        let hasAppleMapsIdentity = ExternalEventSupport.normalizeToken(venue.rawSourcePayload).contains("apple maps")
            || ExternalEventSupport.normalizeToken(venue.rawSourcePayload).contains("apple_maps_name")
        return !hasAppleMapsIdentity
            || venue.imageURL == nil
            || venue.addressLine1 == nil
            || venue.city == nil
            || venue.state == nil
            || venue.postalCode == nil
    }

    private func appleMapsTargetScore(for venue: ExternalVenue) -> Double {
        var score = (venue.nightlifeSignalScore ?? 0) * 2.0
            + (venue.prestigeDemandScore ?? 0) * 1.6
            + (venue.venueSignalScore ?? 0) * 1.2
            + (venue.sourceConfidence ?? 0) * 6.0
        if venue.imageURL == nil { score += 3.5 }
        if venue.addressLine1 == nil { score += 4.0 }
        if venue.postalCode == nil { score += 2.5 }
        if venue.officialSiteURL != nil { score += 1.2 }
        return score
    }

    private func appleMapsSearchTerms(for venue: ExternalVenue, query: ExternalVenueQuery) -> [String] {
        let locality = [venue.city ?? query.city, venue.state ?? query.state]
            .compactMap { value -> String? in
                guard let value, !value.isEmpty else { return nil }
                return value
            }
            .joined(separator: ", ")

        var candidates = [venue.name] + venue.aliases
        candidates.append(contentsOf: venue.aliases.map { "\($0) \(locality)" })
        candidates.append(contentsOf: [
            locality.isEmpty ? nil : "\(venue.name) \(locality)",
            locality.isEmpty ? nil : "\(venue.name) nightlife \(locality)"
        ].compactMap { $0 })

        var seen = Set<String>()
        return candidates.compactMap { value -> String? in
            let cleaned = value.trimmingCharacters(in: .whitespacesAndNewlines)
            let key = ExternalEventSupport.normalizeToken(cleaned)
            guard cleaned.count >= 2, !key.isEmpty, !seen.contains(key) else { return nil }
            seen.insert(key)
            return cleaned
        }
    }

    private func appleMapsAddress(from item: MKMapItem) -> (
        line1: String?,
        city: String?,
        state: String?,
        postalCode: String?,
        country: String?,
        fullAddress: String?
    ) {
        let placemark = item.placemark
        let line1 = postalAddressLine(placemark: placemark)
        let city = placemark.locality
        let state = placemark.administrativeArea
        let postalCode = placemark.postalCode
        let country = placemark.isoCountryCode
        let fallbackFullAddress = [line1, city, state, postalCode]
            .compactMap { value -> String? in
                guard let value, !value.isEmpty else { return nil }
                return value
            }
            .joined(separator: ", ")

        if #available(iOS 26.0, *) {
            let formatted = item.addressRepresentations?.fullAddress(includingRegion: false, singleLine: true)
            let cleanedFormatted = formatted?
                .trimmingCharacters(in: .whitespacesAndNewlines)
            let normalizedFormatted = (cleanedFormatted?.isEmpty == false) ? cleanedFormatted : nil
            let normalizedFallback = fallbackFullAddress.isEmpty ? nil : fallbackFullAddress
            return (
                line1: line1,
                city: city,
                state: state,
                postalCode: postalCode,
                country: country,
                fullAddress: normalizedFormatted ?? normalizedFallback
            )
        }

        let normalizedFallback = fallbackFullAddress.isEmpty ? nil : fallbackFullAddress

        return (
            line1: line1,
            city: city,
            state: state,
            postalCode: postalCode,
            country: country,
            fullAddress: normalizedFallback
        )
    }

    private func postalAddressLine(placemark: MKPlacemark) -> String? {
        let parts = [placemark.subThoroughfare, placemark.thoroughfare].compactMap { $0 }
        let joined = parts.joined(separator: " ")
        return joined.isEmpty ? nil : joined
    }

    private func mergeCoverageStatus(_ primary: String?, _ secondary: String?) -> String? {
        let values = [primary, secondary]
            .compactMap { value -> String? in
                guard let value, !value.isEmpty else { return nil }
                return value
            }
        guard !values.isEmpty else { return nil }
        var seen = Set<String>()
        let unique = values.compactMap { value -> String? in
            let key = ExternalEventSupport.normalizeToken(value)
            guard !seen.contains(key) else { return nil }
            seen.insert(key)
            return value
        }
        return unique.joined(separator: " • ")
    }

    private func mergePayload(_ existing: String?, extra: [String: Any]) -> String {
        var payload: [String: Any] = [:]
        if let existing,
           let data = existing.data(using: .utf8),
           let decoded = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            payload = decoded
        }
        extra.forEach { payload[$0.key] = $0.value }
        return ExternalEventSupport.jsonString(payload)
    }
}

actor ExternalVenueDiscoveryService {
    static let shared = ExternalVenueDiscoveryService(configuration: .fromEnvironment())

    enum DiscoveryMode: Sendable {
        case cachedOnly
        case baseOnly
        case full
    }

    private let configuration: ExternalEventServiceConfiguration
    private let session: URLSession
    private let cacheTTL: TimeInterval
    private let venueAdapters: [any ExternalVenueSourceAdapter]
    private let nightlifeAdapters: [any NightlifeVenueEnrichmentAdapter]

    init(
        configuration: ExternalEventServiceConfiguration,
        session: URLSession? = nil,
        cacheTTL: TimeInterval = 90 * 60,
        venueAdapters: [any ExternalVenueSourceAdapter] = [
            NightlifeAggregatorVenueAdapter(),
            GooglePlacesVenueAdapter(),
            AppleMapsVenueAdapter()
        ],
        nightlifeAdapters: [any NightlifeVenueEnrichmentAdapter] = [
            AppleMapsVenueMediaAdapter(),
            NightlifeAggregatorVenueAdapter(),
            OfficialVenueWebsiteNightlifeAdapter(),
            ReservationProviderNightlifeAdapter()
        ]
    ) {
        self.configuration = configuration
        if let session {
            self.session = session
        } else {
            let urlSessionConfiguration = URLSessionConfiguration.ephemeral
            urlSessionConfiguration.timeoutIntervalForRequest = 20
            urlSessionConfiguration.timeoutIntervalForResource = 40
            self.session = URLSession(configuration: urlSessionConfiguration)
        }
        self.cacheTTL = cacheTTL
        self.venueAdapters = venueAdapters
        self.nightlifeAdapters = nightlifeAdapters
    }

    func discoverVenues(
        query: ExternalVenueQuery,
        forceRefresh: Bool = false,
        mode: DiscoveryMode = .full
    ) async -> ExternalVenueDiscoverySnapshot {
        let cacheKey = ExternalVenueCacheStore.cacheKey(query: query, mode: mode)
        if let cached = ExternalVenueCacheStore.load(forKey: cacheKey),
           (!forceRefresh || mode == .cachedOnly),
           Date().timeIntervalSince(cached.fetchedAt) < cacheTTL {
            return cached.snapshot
        }

        if mode == .cachedOnly {
            return ExternalVenueDiscoverySnapshot(
                fetchedAt: Date(),
                query: query,
                sourceResults: [],
                venues: []
            )
        }

        let activeVenueAdapters: [any ExternalVenueSourceAdapter]
        switch mode {
        case .baseOnly:
            activeVenueAdapters = venueAdapters.filter { $0.source == .nightlifeAggregator }
        case .cachedOnly, .full:
            activeVenueAdapters = venueAdapters
        }

        let baseResults = await withTaskGroup(of: ExternalVenueSourceResult.self, returning: [ExternalVenueSourceResult].self) { group in
            for adapter in activeVenueAdapters {
                group.addTask {
                    await self.discoverBaseVenues(adapter: adapter, query: query, mode: mode)
                }
            }

            var results: [ExternalVenueSourceResult] = []
            for await result in group {
                results.append(result)
            }
            return results.sorted { $0.source.rawValue < $1.source.rawValue }
        }

        var mergedVenues = Self.merge(baseResults.flatMap(\.venues))
        var allResults = baseResults

        let nightlifeTargets = prioritizedNightlifeTargets(from: mergedVenues)
        if mode == .baseOnly, !nightlifeTargets.isEmpty {
            let previewTargets = Array(nightlifeTargets.prefix(max(4, min(query.pageSize, 6))))
            let previewSources: Set<ExternalEventSource> = [.appleMaps, .venueWebsite, .reservationProvider]
            let previewAdapters = nightlifeAdapters.filter { previewSources.contains($0.source) }

            if !previewTargets.isEmpty, !previewAdapters.isEmpty {
                let previewResults = await withTaskGroup(of: ExternalVenueSourceResult.self, returning: [ExternalVenueSourceResult].self) { group in
                    for adapter in previewAdapters {
                        group.addTask {
                            await self.enrichNightlife(adapter: adapter, venues: previewTargets, query: query, mode: mode)
                        }
                    }

                    var results: [ExternalVenueSourceResult] = []
                    for await result in group {
                        results.append(result)
                    }
                    return results
                }

                allResults.append(contentsOf: previewResults)
                mergedVenues = Self.merge(mergedVenues + previewResults.flatMap(\.venues))
            }
        }

        if mode == .full, !nightlifeTargets.isEmpty {
            let firstWaveSources: Set<ExternalEventSource> = [.appleMaps, .nightlifeAggregator]
            let firstWaveAdapters = nightlifeAdapters.filter { firstWaveSources.contains($0.source) }
            let secondWaveAdapters = nightlifeAdapters.filter { !firstWaveSources.contains($0.source) }

            let firstWaveResults = await withTaskGroup(of: ExternalVenueSourceResult.self, returning: [ExternalVenueSourceResult].self) { group in
                for adapter in firstWaveAdapters {
                    group.addTask {
                        await self.enrichNightlife(adapter: adapter, venues: nightlifeTargets, query: query, mode: mode)
                    }
                }

                var results: [ExternalVenueSourceResult] = []
                for await result in group {
                    results.append(result)
                }
                return results
            }

            allResults.append(contentsOf: firstWaveResults)
            mergedVenues = Self.merge(mergedVenues + firstWaveResults.flatMap(\.venues))

            let secondWaveTargets = prioritizedNightlifeTargets(from: mergedVenues)
            if !secondWaveTargets.isEmpty, !secondWaveAdapters.isEmpty {
                let secondWaveResults = await withTaskGroup(of: ExternalVenueSourceResult.self, returning: [ExternalVenueSourceResult].self) { group in
                    for adapter in secondWaveAdapters {
                        group.addTask {
                            await self.enrichNightlife(adapter: adapter, venues: secondWaveTargets, query: query, mode: mode)
                        }
                    }

                    var results: [ExternalVenueSourceResult] = []
                    for await result in group {
                        results.append(result)
                    }
                    return results
                }

                allResults.append(contentsOf: secondWaveResults)
                mergedVenues = Self.merge(mergedVenues + secondWaveResults.flatMap(\.venues))
            }
        }

        let snapshot = ExternalVenueDiscoverySnapshot(
            fetchedAt: Date(),
            query: query,
            sourceResults: Self.mergeSourceResults(allResults),
            venues: mergedVenues
        )
        ExternalVenueCacheStore.save(snapshot: snapshot, forKey: cacheKey)
        return snapshot
    }

    private func discoverBaseVenues(
        adapter: any ExternalVenueSourceAdapter,
        query: ExternalVenueQuery,
        mode: DiscoveryMode
    ) async -> ExternalVenueSourceResult {
        let timeoutSeconds: Double
        switch (mode, adapter.source) {
        case (.baseOnly, .appleMaps):
            timeoutSeconds = 3.0
        case (.baseOnly, .nightlifeAggregator):
            timeoutSeconds = 3.5
        case (.baseOnly, _):
            timeoutSeconds = 4.0
        case (_, .appleMaps):
            timeoutSeconds = 5.0
        case (_, .nightlifeAggregator):
            timeoutSeconds = 24.0
        default:
            timeoutSeconds = 8.0
        }

        return await withTimeout(seconds: timeoutSeconds) {
            await adapter.discoverVenues(
                query: query,
                session: self.session,
                configuration: self.configuration
            )
        } fallback: {
            ExternalVenueSourceResult(
                source: adapter.source,
                fetchedAt: Date(),
                endpoints: [],
                note: "\(adapter.source.rawValue) venue discovery timed out.",
                venues: []
            )
        }
    }

    private func enrichNightlife(
        adapter: any NightlifeVenueEnrichmentAdapter,
        venues: [ExternalVenue],
        query: ExternalVenueQuery,
        mode: DiscoveryMode
    ) async -> ExternalVenueSourceResult {
        let timeoutSeconds: Double
        switch (mode, adapter.source) {
        case (.baseOnly, .nightlifeAggregator):
            timeoutSeconds = 4.5
        case (.baseOnly, .appleMaps):
            timeoutSeconds = 4.0
        case (.baseOnly, _):
            timeoutSeconds = 3.5
        case (_, .nightlifeAggregator):
            timeoutSeconds = 22.0
        case (_, .appleMaps):
            timeoutSeconds = 10.0
        case (_, .venueWebsite):
            timeoutSeconds = 16.0
        default:
            timeoutSeconds = 6.0
        }
        return await withTimeout(seconds: timeoutSeconds) {
            await adapter.enrichVenues(
                venues,
                query: query,
                session: self.session,
                configuration: self.configuration
            )
        } fallback: {
            ExternalVenueSourceResult(
                source: adapter.source,
                fetchedAt: Date(),
                endpoints: [],
                note: "\(adapter.source.rawValue) nightlife enrichment timed out.",
                venues: []
            )
        }
    }

    private func prioritizedNightlifeTargets(from venues: [ExternalVenue]) -> [ExternalVenue] {
        let nightlifeWeighted = venues.filter { venue in
            switch venue.venueType {
            case .nightlifeVenue, .lounge, .bar, .restaurant, .concertVenue, .comedyClub:
                return true
            default:
                return venue.nightlifeSignalScore != nil || venue.reservationURL != nil || venue.officialSiteURL != nil
            }
        }

        let source = nightlifeWeighted.isEmpty ? venues : nightlifeWeighted
        return Array(
            source
                .sorted { lhs, rhs in
                    let left = nightlifeTargetScore(for: lhs)
                    let right = nightlifeTargetScore(for: rhs)
                    if left == right {
                        return lhs.name < rhs.name
                    }
                    return left > right
                }
                .prefix(48)
        )
    }

    private func nightlifeTargetScore(for venue: ExternalVenue) -> Double {
        var score = (venue.nightlifeSignalScore ?? 0) * 1.8
            + (venue.prestigeDemandScore ?? 0) * 1.4
            + (venue.venueSignalScore ?? 0) * 1.1
            + (venue.sourceConfidence ?? 0) * 8

        switch venue.venueType {
        case .nightlifeVenue:
            score += 6
        case .lounge:
            score += 5
        case .bar:
            score += 3
        case .concertVenue, .comedyClub:
            score += 1
        default:
            break
        }

        if venue.officialSiteURL != nil { score += 1.5 }
        if venue.reservationURL != nil { score += 2.5 }
        let coverage = ExternalEventSupport.normalizeToken([venue.sourceCoverageStatus, venue.rawSourcePayload].compactMap { $0 }.joined(separator: " "))
        if hasDiscotechCoverage(coverage) { score += 5.5 }
        if hasClubbableCoverage(coverage) { score += 5.5 }
        if isWeakHWoodOnlyCoverage(coverage) { score -= 5.5 }
        return score
    }

    private func withTimeout<T: Sendable>(
        seconds: Double,
        operation: @escaping @Sendable () async -> T,
        fallback: @escaping @Sendable () -> T
    ) async -> T {
        await withTaskGroup(of: T.self, returning: T.self) { group in
            group.addTask { await operation() }
            group.addTask {
                let duration = UInt64(max(seconds, 0.1) * 1_000_000_000)
                try? await Task.sleep(nanoseconds: duration)
                return fallback()
            }
            let value = await group.next() ?? fallback()
            group.cancelAll()
            return value
        }
    }

    nonisolated static func merge(_ venues: [ExternalVenue]) -> [ExternalVenue] {
        let grouped = Dictionary(grouping: venues) { venue in
            canonicalVenueMergeKey(for: venue)
        }

        let initiallyMerged: [ExternalVenue] = grouped.values.compactMap { group -> ExternalVenue? in
            guard var primary = group.sorted(by: venueSort).first else { return nil }
            for secondary in group.dropFirst() {
                primary = merge(primary: primary, secondary: secondary)
            }
            return primary
        }
        let coalesced = coalesceLooselyMergedNightlifeVenues(initiallyMerged)
        return coalesced
        .sorted { lhs, rhs in
            let leftScore = (lhs.nightlifeSignalScore ?? 0) + (lhs.prestigeDemandScore ?? 0) + (lhs.venueSignalScore ?? 0)
            let rightScore = (rhs.nightlifeSignalScore ?? 0) + (rhs.prestigeDemandScore ?? 0) + (rhs.venueSignalScore ?? 0)
            if leftScore == rightScore {
                return lhs.name < rhs.name
            }
            return leftScore > rightScore
        }
    }

    private nonisolated static func coalesceLooselyMergedNightlifeVenues(_ venues: [ExternalVenue]) -> [ExternalVenue] {
        var merged: [ExternalVenue] = []

        for venue in venues.sorted(by: venueSort) {
            if let index = merged.firstIndex(where: { shouldLooselyMergeNightlife($0, venue) }) {
                let existing = merged.remove(at: index)
                merged.append(merge(primary: existing, secondary: venue))
            } else {
                merged.append(venue)
            }
        }

        return merged
    }

    private nonisolated static func shouldLooselyMergeNightlife(_ lhs: ExternalVenue, _ rhs: ExternalVenue) -> Bool {
        guard nightlifeEligibleForLooseMerge(lhs), nightlifeEligibleForLooseMerge(rhs) else {
            return false
        }

        let leftState = ExternalEventSupport.normalizeStateToken(lhs.state)
        let rightState = ExternalEventSupport.normalizeStateToken(rhs.state)
        guard !leftState.isEmpty, leftState == rightState else {
            return false
        }

        let leftAddress = ExternalEventSupport.normalizeToken(lhs.addressLine1)
        let rightAddress = ExternalEventSupport.normalizeToken(rhs.addressLine1)
        if !leftAddress.isEmpty,
           !rightAddress.isEmpty,
           leftAddress == rightAddress,
           nightlifeAliasMatch(lhs.name, rhs.name) {
            return true
        }

        let leftFingerprint = canonicalVenueNameFingerprint(
            lhs.name,
            city: lhs.city,
            state: lhs.state,
            neighborhood: lhs.neighborhood
        )
        let rightFingerprint = canonicalVenueNameFingerprint(
            rhs.name,
            city: rhs.city,
            state: rhs.state,
            neighborhood: rhs.neighborhood
        )
        guard !leftFingerprint.isEmpty, leftFingerprint == rightFingerprint else {
            return false
        }
        if !leftAddress.isEmpty, !rightAddress.isEmpty {
            return leftAddress == rightAddress
        }

        if let leftLatitude = lhs.latitude,
           let leftLongitude = lhs.longitude,
           let rightLatitude = rhs.latitude,
           let rightLongitude = rhs.longitude {
            let leftLocation = CLLocation(latitude: leftLatitude, longitude: leftLongitude)
            let rightLocation = CLLocation(latitude: rightLatitude, longitude: rightLongitude)
            if leftLocation.distance(from: rightLocation) / 1609.344 <= 1.2 {
                return true
            }
        }

        let leftCoverage = ExternalEventSupport.normalizeToken(lhs.sourceCoverageStatus)
        let rightCoverage = ExternalEventSupport.normalizeToken(rhs.sourceCoverageStatus)
        if leftAddress.isEmpty != rightAddress.isEmpty {
            return [leftCoverage, rightCoverage].contains {
                $0.contains("clubbable") || $0.contains("discotech") || $0.contains("apple maps")
            }
        }

        let leftCity = ExternalEventSupport.normalizeToken(lhs.city)
        let rightCity = ExternalEventSupport.normalizeToken(rhs.city)
        return !leftCity.isEmpty && leftCity == rightCity
    }

    private nonisolated static func nightlifeAliasMatch(_ lhs: String, _ rhs: String) -> Bool {
        let blockedTokens = Set([
            "the", "at", "and", "of", "la", "los", "angeles", "west", "hollywood", "beverly", "hills",
            "hotel", "rooftop", "bar", "club", "nightclub", "lounge", "restaurant", "venue"
        ])
        let leftTokens = Set(
            ExternalEventSupport.normalizeToken(lhs)
                .split(separator: " ")
                .map(String.init)
        ).subtracting(blockedTokens)
        let rightTokens = Set(
            ExternalEventSupport.normalizeToken(rhs)
                .split(separator: " ")
                .map(String.init)
        ).subtracting(blockedTokens)

        guard !leftTokens.isEmpty, !rightTokens.isEmpty else { return false }
        if leftTokens == rightTokens { return true }
        if leftTokens.isSubset(of: rightTokens) || rightTokens.isSubset(of: leftTokens) {
            return true
        }

        let shared = leftTokens.intersection(rightTokens)
        let denominator = Double(max(leftTokens.count, rightTokens.count))
        return denominator > 0 && (Double(shared.count) / denominator) >= 0.67
    }

    private nonisolated static func nightlifeEligibleForLooseMerge(_ venue: ExternalVenue) -> Bool {
        switch venue.venueType {
        case .nightlifeVenue, .lounge, .bar, .restaurant, .concertVenue, .comedyClub:
            return true
        default:
            break
        }

        let coverage = ExternalEventSupport.normalizeToken([venue.sourceCoverageStatus, venue.rawSourcePayload].compactMap { $0 }.joined(separator: " "))
        return venue.nightlifeSignalScore != nil
            || hasClubbableCoverage(coverage)
            || hasDiscotechCoverage(coverage)
            || coverage.contains("apple maps")
    }

    private nonisolated static func canonicalVenueMergeKey(for venue: ExternalVenue) -> String {
        let stateToken = ExternalEventSupport.normalizeStateToken(venue.state)
        let cityToken = ExternalEventSupport.normalizeToken(venue.city)
        let neighborhoodToken = ExternalEventSupport.normalizeToken(venue.neighborhood)
        let addressToken = ExternalEventSupport.normalizeToken(venue.addressLine1)
        let nameToken = canonicalVenueNameFingerprint(
            venue.name,
            city: venue.city,
            state: venue.state,
            neighborhood: venue.neighborhood
        )

        let locationToken: String
        if !addressToken.isEmpty {
            locationToken = addressToken
        } else if !cityToken.isEmpty {
            locationToken = cityToken
        } else {
            locationToken = neighborhoodToken
        }

        return [nameToken, locationToken, stateToken].joined(separator: "::")
    }

    private nonisolated static func canonicalVenueNameFingerprint(
        _ value: String,
        city: String?,
        state: String?,
        neighborhood: String?
    ) -> String {
        let blockedTokens = Set([
            "the", "la", "los", "angeles", "west", "hollywood", "hollywood", "beverly", "hills",
            "nightclub", "night", "club", "lounge", "rooftop", "bar", "hotel", "restaurant",
            "venue", "at", "of", "and", "tonight"
        ])
        let cityTokens = Set(
            [
                ExternalEventSupport.normalizeToken(city),
                ExternalEventSupport.normalizeToken(neighborhood),
                ExternalEventSupport.normalizeStateToken(state)
            ]
            .flatMap { $0.split(separator: " ").map(String.init) }
        )

        let tokens = Set(
            ExternalEventSupport.normalizeToken(value)
                .split(separator: " ")
                .map(String.init)
        )
        .subtracting(blockedTokens)
        .subtracting(cityTokens)

        let fingerprint = Array(tokens).sorted().joined(separator: " ")
        return fingerprint.isEmpty ? ExternalEventSupport.normalizeToken(value) : fingerprint
    }

    private nonisolated static func venueSort(lhs: ExternalVenue, rhs: ExternalVenue) -> Bool {
        let leftCoverage = ExternalEventSupport.normalizeToken([lhs.sourceCoverageStatus, lhs.rawSourcePayload].compactMap { $0 }.joined(separator: " "))
        let rightCoverage = ExternalEventSupport.normalizeToken([rhs.sourceCoverageStatus, rhs.rawSourcePayload].compactMap { $0 }.joined(separator: " "))

        func coverageScore(_ coverage: String) -> Double {
            var score = 0.0
            if hasDiscotechCoverage(coverage) { score += 6.0 }
            if hasClubbableCoverage(coverage) { score += 5.0 }
            if coverage.contains("apple maps") { score += 3.0 }
            if coverage.contains("official venue site") { score += 2.0 }
            if isWeakHWoodOnlyCoverage(coverage) { score -= 4.0 }
            return score
        }

        let leftScore = (lhs.sourceConfidence ?? 0) + (lhs.venueSignalScore ?? 0) + coverageScore(leftCoverage)
        let rightScore = (rhs.sourceConfidence ?? 0) + (rhs.venueSignalScore ?? 0) + coverageScore(rightCoverage)
        if leftScore == rightScore {
            return lhs.name < rhs.name
        }
        return leftScore > rightScore
    }

    private nonisolated static func merge(primary: ExternalVenue, secondary: ExternalVenue) -> ExternalVenue {
        var merged = primary
        merged.canonicalVenueID = merged.canonicalVenueID ?? secondary.canonicalVenueID
        merged.aliases = Array(Set(primary.aliases + secondary.aliases)).sorted()
        merged.venueType = merged.venueType ?? secondary.venueType
        merged.neighborhood = merged.neighborhood ?? secondary.neighborhood
        merged.addressLine1 = ExternalEventSupport.preferredAddressLine(
            primary: merged.addressLine1,
            primaryCity: merged.city,
            primaryState: merged.state,
            secondary: secondary.addressLine1,
            secondaryCity: secondary.city,
            secondaryState: secondary.state
        )
        merged.addressLine2 = merged.addressLine2 ?? secondary.addressLine2
        merged.city = merged.city ?? secondary.city
        merged.state = merged.state ?? secondary.state
        merged.postalCode = merged.postalCode ?? secondary.postalCode
        merged.country = merged.country ?? secondary.country
        merged.latitude = merged.latitude ?? secondary.latitude
        merged.longitude = merged.longitude ?? secondary.longitude
        merged.officialSiteURL = preferredOfficialSiteURL(
            primary: merged.officialSiteURL,
            secondary: secondary.officialSiteURL
        )
        merged.reservationProvider = merged.reservationProvider ?? secondary.reservationProvider
        merged.reservationURL = merged.reservationURL ?? secondary.reservationURL
        merged.imageURL = ExternalEventSupport.preferredImageURL(primary: merged.imageURL, secondary: secondary.imageURL)
        merged.openingHoursText = betterText(
            primary: sanitizedVenueHoursText(merged.openingHoursText),
            secondary: sanitizedVenueHoursText(secondary.openingHoursText)
        )
        merged.ageMinimum = merged.ageMinimum ?? secondary.ageMinimum
        merged.doorPolicyText = betterText(primary: merged.doorPolicyText, secondary: secondary.doorPolicyText)
        merged.dressCodeText = betterText(primary: merged.dressCodeText, secondary: secondary.dressCodeText)
        merged.guestListAvailable = (merged.guestListAvailable == true || secondary.guestListAvailable == true)
            ? true
            : merged.guestListAvailable ?? secondary.guestListAvailable
        merged.bottleServiceAvailable = (merged.bottleServiceAvailable == true || secondary.bottleServiceAvailable == true)
            ? true
            : merged.bottleServiceAvailable ?? secondary.bottleServiceAvailable
        merged.tableMinPrice = ExternalEventSupport.richerNightlifePrice(primary: merged.tableMinPrice, secondary: secondary.tableMinPrice)
        merged.coverPrice = ExternalEventSupport.richerNightlifePrice(primary: merged.coverPrice, secondary: secondary.coverPrice)
        merged.entryPolicySummary = betterText(primary: merged.entryPolicySummary, secondary: secondary.entryPolicySummary)
        merged.womenEntryPolicyText = betterText(primary: merged.womenEntryPolicyText, secondary: secondary.womenEntryPolicyText)
        merged.menEntryPolicyText = betterText(primary: merged.menEntryPolicyText, secondary: secondary.menEntryPolicyText)
        merged.exclusivityTierLabel = ExternalEventSupport.moreExclusiveTier(primary: merged.exclusivityTierLabel, secondary: secondary.exclusivityTierLabel)
        if let secondaryReviewCount = secondary.venuePopularityCount, secondaryReviewCount > (merged.venuePopularityCount ?? 0) {
            merged.venuePopularityCount = secondaryReviewCount
        }
        merged.venueRating = merged.venueRating ?? secondary.venueRating
        merged.venueSignalScore = max(merged.venueSignalScore ?? 0, secondary.venueSignalScore ?? 0)
        merged.nightlifeSignalScore = max(merged.nightlifeSignalScore ?? 0, secondary.nightlifeSignalScore ?? 0)
        merged.prestigeDemandScore = max(merged.prestigeDemandScore ?? 0, secondary.prestigeDemandScore ?? 0)
        merged.recurringEventPatternConfidence = max(merged.recurringEventPatternConfidence ?? 0, secondary.recurringEventPatternConfidence ?? 0)
        merged.sourceConfidence = max(merged.sourceConfidence ?? 0, secondary.sourceConfidence ?? 0)
        merged.sourceCoverageStatus = combinedCoverageStatus(primary: merged.sourceCoverageStatus, secondary: secondary.sourceCoverageStatus)
        merged.rawSourcePayload = mergedPayload(primary: merged.rawSourcePayload, secondary: secondary.rawSourcePayload)
        merged.imageURL = ExternalEventSupport.preferredNightlifeImageURL(primary: merged.imageURL, payload: merged.rawSourcePayload)
        return merged
    }

    private nonisolated static func betterText(primary: String?, secondary: String?) -> String? {
        guard let secondary, !secondary.isEmpty else { return primary }
        guard let primary, !primary.isEmpty else { return secondary }

        let normalizedPrimary = ExternalEventSupport.normalizeToken(primary)
        let normalizedSecondary = ExternalEventSupport.normalizeToken(secondary)
        let primaryIsMarketNote = normalizedPrimary.contains("highlighted in discotech s market guide")
        let secondaryIsMarketNote = normalizedSecondary.contains("highlighted in discotech s market guide")
        let primaryIsGenericGuestList = normalizedPrimary.contains("guest list access is available")
            || normalizedPrimary.contains("listed by h wood rolodex")
        let secondaryIsGenericGuestList = normalizedSecondary.contains("guest list access is available")
            || normalizedSecondary.contains("listed by h wood rolodex")
        let primaryIsExplicitDoor = normalizedPrimary.contains("bottle service only")
            || normalizedPrimary.contains("does not have general admission")
            || normalizedPrimary.contains("hard door")
        let secondaryIsExplicitDoor = normalizedSecondary.contains("bottle service only")
            || normalizedSecondary.contains("does not have general admission")
            || normalizedSecondary.contains("hard door")

        if primaryIsMarketNote && !secondaryIsMarketNote {
            return secondary
        }
        if primaryIsGenericGuestList && secondaryIsExplicitDoor {
            return secondary
        }
        if secondaryIsGenericGuestList && primaryIsExplicitDoor {
            return primary
        }
        let primaryScore = nightlifeTextQualityScore(primary)
        let secondaryScore = nightlifeTextQualityScore(secondary)
        if secondaryScore >= primaryScore + 2 {
            return secondary
        }
        if primaryScore >= secondaryScore + 2 {
            return primary
        }
        if normalizedPrimary == normalizedSecondary
            || normalizedPrimary.contains(normalizedSecondary)
            || normalizedSecondary.contains(normalizedPrimary) {
            return primary.count >= secondary.count ? primary : secondary
        }
        if secondary.count > primary.count + 24 {
            return secondary
        }
        return primary
    }

    private nonisolated static func moreExclusiveTier(primary: String?, secondary: String?) -> String? {
        ExternalEventSupport.moreExclusiveTier(primary: primary, secondary: secondary)
    }

    private nonisolated static func mergedPayload(primary: String, secondary: String) -> String {
        var payload: [String: Any] = [:]

        if let primaryData = primary.data(using: .utf8),
           let decoded = try? JSONSerialization.jsonObject(with: primaryData) as? [String: Any] {
            payload = decoded
        }

        if let secondaryData = secondary.data(using: .utf8),
           let decoded = try? JSONSerialization.jsonObject(with: secondaryData) as? [String: Any] {
            decoded.forEach { key, value in
                if payload[key] == nil {
                    payload[key] = value
                }
            }
        }

        return ExternalEventSupport.jsonString(payload)
    }

    private nonisolated static func mergeSourceResults(_ results: [ExternalVenueSourceResult]) -> [ExternalVenueSourceResult] {
        Dictionary(grouping: results, by: \.source)
            .compactMap { source, grouped -> ExternalVenueSourceResult? in
                guard let first = grouped.first else { return nil }
                let mergedVenues = merge(grouped.flatMap(\.venues))
                let note = grouped.compactMap(\.note).last
                return ExternalVenueSourceResult(
                    source: source,
                    fetchedAt: grouped.map(\.fetchedAt).max() ?? first.fetchedAt,
                    endpoints: grouped.flatMap(\.endpoints),
                    note: note,
                    venues: mergedVenues
                )
            }
            .sorted { $0.source.rawValue < $1.source.rawValue }
    }

    private nonisolated static func combinedCoverageStatus(primary: String?, secondary: String?) -> String? {
        let values = [primary, secondary]
            .compactMap { value -> String? in
                guard let value, !value.isEmpty else { return nil }
                return value
            }
        guard !values.isEmpty else { return nil }

        var seen = Set<String>()
        let unique = values.compactMap { value -> String? in
            let key = ExternalEventSupport.normalizeToken(value)
            guard !key.isEmpty, !seen.contains(key) else { return nil }
            seen.insert(key)
            return value
        }
        return unique.joined(separator: " • ")
    }
}

enum ExternalVenueCacheStore {
    private static let defaults = UserDefaults.standard
    private static let prefix = "external_venue_cache::"
    private static let encoder = JSONEncoder()
    private static let decoder = JSONDecoder()

    private struct Envelope: Codable {
        let fetchedAt: Date
        let snapshot: ExternalVenueDiscoverySnapshot
    }

    static func cacheKey(
        query: ExternalVenueQuery,
        mode: ExternalVenueDiscoveryService.DiscoveryMode
    ) -> String {
        let cacheMode: String
        switch mode {
        case .cachedOnly, .full:
            cacheMode = "full"
        case .baseOnly:
            cacheMode = "base"
        }

        let parts = [
            cacheMode,
            query.countryCode,
            query.city ?? "",
            query.state ?? "",
            query.displayName ?? "",
            String(format: "%.3f", query.latitude),
            String(format: "%.3f", query.longitude),
            String(format: "%.1f", query.hyperlocalRadiusMiles),
            String(format: "%.1f", query.nightlifeRadiusMiles),
            String(format: "%.1f", query.headlineRadiusMiles),
            String(query.pageSize)
        ]
        return prefix + parts.joined(separator: "::")
    }

    static func save(snapshot: ExternalVenueDiscoverySnapshot, forKey key: String) {
        let envelope = Envelope(fetchedAt: Date(), snapshot: snapshot)
        guard let data = try? encoder.encode(envelope) else { return }
        defaults.set(data, forKey: key)
    }

    static func load(forKey key: String) -> (fetchedAt: Date, snapshot: ExternalVenueDiscoverySnapshot)? {
        guard let data = defaults.data(forKey: key),
              let envelope = try? decoder.decode(Envelope.self, from: data) else {
            return nil
        }
        return (envelope.fetchedAt, envelope.snapshot)
    }
}

nonisolated struct OfficialVenueWebsiteNightlifeAdapter: NightlifeVenueEnrichmentAdapter {
    let source: ExternalEventSource = .venueWebsite

    private struct WebsiteMetadata {
        let description: String?
        let vibeText: String?
        let imageURL: String?
        let imageGallery: [String]
        let telephone: String?
        let openingHoursText: String?
        let priceRange: String?
        let addressLine1: String?
        let city: String?
        let state: String?
        let postalCode: String?
    }

    func enrichVenues(
        _ venues: [ExternalVenue],
        query: ExternalVenueQuery,
        session: URLSession,
        configuration: ExternalEventServiceConfiguration
    ) async -> ExternalVenueSourceResult {
        let targets = Array(
            venues
                .filter { $0.officialSiteURL != nil }
                .sorted { lhs, rhs in
                    let leftScore = (lhs.nightlifeSignalScore ?? 0) + (lhs.prestigeDemandScore ?? 0) + (lhs.sourceConfidence ?? 0)
                    let rightScore = (rhs.nightlifeSignalScore ?? 0) + (rhs.prestigeDemandScore ?? 0) + (rhs.sourceConfidence ?? 0)
                    if leftScore == rightScore {
                        return lhs.name < rhs.name
                    }
                    return leftScore > rightScore
                }
                .prefix(query.pageSize <= 6 ? 6 : (query.pageSize <= 12 ? 12 : 24))
        )
        guard !targets.isEmpty else {
            return ExternalVenueSourceResult(
                source: source,
                fetchedAt: Date(),
                endpoints: [],
                note: "No official venue websites were available for nightlife enrichment.",
                venues: []
            )
        }

        var endpoints: [ExternalEventEndpointResult] = []
        var enriched: [ExternalVenue] = []
        await withTaskGroup(of: (endpoints: [ExternalEventEndpointResult], venue: ExternalVenue?).self) { group in
            for venue in targets {
                group.addTask {
                    await enrichVenue(venue, session: session)
                }
            }

            for await result in group {
                endpoints.append(contentsOf: result.endpoints)
                if let venue = result.venue {
                    enriched.append(venue)
                }
            }
        }

        return ExternalVenueSourceResult(
            source: source,
            fetchedAt: Date(),
            endpoints: endpoints,
            note: enriched.isEmpty ? "Official venue websites did not return actionable nightlife metadata." : nil,
            venues: enriched
        )
    }

    private func enrichVenue(
        _ venue: ExternalVenue,
        session: URLSession
    ) async -> (endpoints: [ExternalEventEndpointResult], venue: ExternalVenue?) {
        guard let site = venue.officialSiteURL,
              isTrustedOfficialSiteURL(site),
              let url = URL(string: site)
        else {
            return ([], nil)
        }

        do {
            let (data, response) = try await session.data(from: url)
            let statusCode = (response as? HTTPURLResponse)?.statusCode
            let html = String(data: data, encoding: .utf8) ?? ""
            var validationHTMLFragments = [html]
            var endpoints = [
                ExternalEventEndpointResult(
                    label: "Official venue site \(venue.name)",
                    requestURL: url.absoluteString,
                    responseStatusCode: statusCode,
                    worked: statusCode.map { 200..<300 ~= $0 } ?? false,
                    note: nil
                )
            ]
            guard statusCode.map({ 200..<300 ~= $0 }) ?? false else {
                return (endpoints, nil)
            }

            var updated = venue
            var metadata = websiteMetadata(from: html, baseURL: url)

            for supplementalURL in supplementalOfficialSiteURLs(from: html, baseURL: url).prefix(3) {
                do {
                    let (supplementalData, supplementalResponse) = try await session.data(from: supplementalURL)
                    let supplementalStatusCode = (supplementalResponse as? HTTPURLResponse)?.statusCode
                    endpoints.append(
                        ExternalEventEndpointResult(
                            label: "Official venue site detail \(venue.name)",
                            requestURL: supplementalURL.absoluteString,
                            responseStatusCode: supplementalStatusCode,
                            worked: supplementalStatusCode.map { 200..<300 ~= $0 } ?? false,
                            note: nil
                        )
                    )
                    guard supplementalStatusCode.map({ 200..<300 ~= $0 }) ?? false,
                          let supplementalHTML = String(data: supplementalData, encoding: .utf8),
                          !supplementalHTML.isEmpty
                    else {
                        continue
                    }
                    validationHTMLFragments.append(supplementalHTML)
                    metadata = mergedWebsiteMetadata(
                        primary: metadata,
                        secondary: websiteMetadata(from: supplementalHTML, baseURL: supplementalURL)
                    )
                } catch {
                    endpoints.append(
                        ExternalEventEndpointResult(
                            label: "Official venue site detail \(venue.name)",
                            requestURL: supplementalURL.absoluteString,
                            responseStatusCode: nil,
                            worked: false,
                            note: error.localizedDescription
                        )
                    )
                }
            }

            guard officialSiteLooksCompatible(
                validationHTMLFragments: validationHTMLFragments,
                url: url,
                metadata: metadata,
                venue: venue
            ) else {
                return (endpoints, nil)
            }

            updated.sourceType = .officialVenueWebsite
            updated.officialSiteURL = preferredOfficialSiteURL(
                primary: updated.officialSiteURL,
                secondary: url.absoluteString
            )
            updated.imageURL = ExternalEventSupport.preferredImageURL(primary: updated.imageURL, secondary: metadata.imageURL)
            updated.addressLine1 = ExternalEventSupport.preferredAddressLine(
                primary: updated.addressLine1,
                primaryCity: updated.city,
                primaryState: updated.state,
                secondary: metadata.addressLine1,
                secondaryCity: metadata.city,
                secondaryState: metadata.state
            )
            updated.city = updated.city ?? metadata.city
            updated.state = updated.state ?? metadata.state
            updated.postalCode = updated.postalCode ?? metadata.postalCode
            updated.openingHoursText = preferText(
                primary: updated.openingHoursText,
                secondary: sanitizedVenueHoursText(
                    metadata.openingHoursText ?? capture(in: html, patterns: ["hours", "open"])
                )
            )
            updated.ageMinimum = updated.ageMinimum ?? parseAgeMinimum(in: html)
            updated.entryPolicySummary = preferText(
                primary: updated.entryPolicySummary,
                secondary: capture(
                    in: html,
                    patterns: ["guest list", "guestlist", "reservation", "reserve", "vip table", "table service", "bottle service"],
                    maxMatches: 2
                )
            )
            updated.doorPolicyText = preferText(
                primary: updated.doorPolicyText,
                secondary: capture(
                    in: html,
                    patterns: ["guest list", "door policy", "tables", "bottle service", "reservation", "vip"],
                    maxMatches: 2
                )
            )
            updated.dressCodeText = preferText(
                primary: updated.dressCodeText,
                secondary: capture(in: html, patterns: ["dress code", "upscale attire", "attire"])
            )
            updated.womenEntryPolicyText = preferText(
                primary: updated.womenEntryPolicyText,
                secondary: capture(
                    in: html,
                    patterns: ["women", "ladies", "girls", "female"],
                    maxMatches: 1
                )
            )
            updated.menEntryPolicyText = preferText(
                primary: updated.menEntryPolicyText,
                secondary: capture(
                    in: html,
                    patterns: ["men", "guys", "gentlemen", "male"],
                    maxMatches: 1
                )
            )
            updated.guestListAvailable = updated.guestListAvailable ?? containsAny(html, needles: ["guest list", "guestlist"])
            updated.bottleServiceAvailable = updated.bottleServiceAvailable ?? containsAny(html, needles: ["bottle service", "vip table", "table service"])
            updated.coverPrice = ExternalEventSupport.richerNightlifePrice(
                primary: updated.coverPrice,
                secondary: capturePrice(
                    in: html,
                    patterns: [
                        #"cover[^$]{0,24}\$([0-9][0-9,]*)"#,
                        #"\$([0-9][0-9,]*)[^.]{0,16}cover"#
                    ]
                )
            )
            updated.tableMinPrice = ExternalEventSupport.richerNightlifePrice(
                primary: updated.tableMinPrice,
                secondary: capturePrice(
                    in: html,
                    patterns: [
                        #"(?:table minimum|table minimums|tables? from|tables? start at|minimum spend)[^$]{0,28}\$([0-9][0-9,]*)"#,
                        #"\$([0-9][0-9,]*)[^.]{0,18}(?:table minimum|minimum spend|table)"#
                    ]
                )
            )
            updated.imageURL = ExternalEventSupport.preferredImageURL(
                from: [updated.imageURL, metadata.imageURL] + metadata.imageGallery.map(Optional.some)
            )
            updated.reservationURL = updated.reservationURL ?? firstReservationURL(in: html)
            updated.reservationProvider = updated.reservationProvider ?? reservationProvider(for: updated.reservationURL)
            updated.sourceConfidence = max(updated.sourceConfidence ?? 0, 0.78)
            updated.sourceCoverageStatus = mergeCoverageStatus(updated.sourceCoverageStatus, "Official venue site")
            updated.nightlifeSignalScore = max(updated.nightlifeSignalScore ?? 0, nightlifeSignalScore(for: updated))
            updated.rawSourcePayload = mergePayload(
                venue.rawSourcePayload,
                extra: [
                    "official_site_description": metadata.description as Any,
                    "official_site_vibe": metadata.vibeText as Any,
                    "official_site_price_range": metadata.priceRange as Any,
                    "official_site_phone": metadata.telephone as Any,
                    "official_site_url": updated.officialSiteURL as Any,
                    "official_site_image": metadata.imageURL as Any,
                    "official_site_image_gallery": metadata.imageGallery as Any,
                    "official_site_address": metadata.addressLine1 as Any,
                    "official_site_city": metadata.city as Any,
                    "official_site_state": metadata.state as Any,
                    "official_site_postal_code": metadata.postalCode as Any,
                    "official_site_hours": metadata.openingHoursText as Any
                ]
            )
            return (endpoints, updated)
        } catch {
            return (
                [
                    ExternalEventEndpointResult(
                        label: "Official venue site \(venue.name)",
                        requestURL: url.absoluteString,
                        responseStatusCode: nil,
                        worked: false,
                        note: error.localizedDescription
                    )
                ],
                nil
            )
        }
    }

    private func officialSiteLooksCompatible(
        validationHTMLFragments: [String],
        url: URL,
        metadata: WebsiteMetadata,
        venue: ExternalVenue
    ) -> Bool {
        let titleMatches = validationHTMLFragments.flatMap {
            allRegexMatches(
                in: $0,
                pattern: #"<title>([^<]+)</title>|<meta[^>]+(?:property|name)=["'](?:og:title|twitter:title)["'][^>]+content=["']([^"']+)["']"#,
                groupCount: 2,
                options: [.caseInsensitive]
            )
        }
        .flatMap { $0 }
        .compactMap { $0 }
        .joined(separator: " ")

        let pageText = validationHTMLFragments
            .prefix(3)
            .compactMap { ExternalEventSupport.plainText($0) }
            .map { String($0.prefix(2_500)) }
            .joined(separator: " ")

        let siteIdentityText = ExternalEventSupport.normalizeToken(
            [
                titleMatches,
                metadata.description,
                metadata.vibeText,
                url.host,
                url.path.replacingOccurrences(of: "-", with: " "),
                pageText
            ]
            .compactMap { $0 }
            .joined(separator: " ")
        )

        guard !siteIdentityText.isEmpty else { return false }

        let identityCandidates = officialSiteIdentityCandidates(for: venue)
        for candidate in identityCandidates {
            let normalizedCandidate = ExternalEventSupport.normalizeToken(candidate)
            guard normalizedCandidate.count >= 4 else { continue }
            if siteIdentityText.contains(normalizedCandidate) {
                return true
            }
        }

        let blockedTokens = Set([
            "the", "at", "and", "of", "la", "los", "angeles", "west", "hollywood",
            "beverly", "hills", "hotel", "rooftop", "bar", "club", "nightclub",
            "lounge", "restaurant", "venue"
        ])

        let venueTokens = Set(
            identityCandidates
                .flatMap { ExternalEventSupport.normalizeToken($0).split(separator: " ").map(String.init) }
        ).subtracting(blockedTokens)
        let pageTokens = Set(siteIdentityText.split(separator: " ").map(String.init)).subtracting(blockedTokens)
        let sharedTokens = venueTokens.intersection(pageTokens)

        if sharedTokens.count >= 2 {
            return true
        }
        if venueTokens.count == 1, let onlyToken = venueTokens.first, onlyToken.count >= 5 {
            return pageTokens.contains(onlyToken)
        }

        return false
    }

    private func officialSiteIdentityCandidates(for venue: ExternalVenue) -> [String] {
        let rawCandidates = [venue.name] + venue.aliases
        let suffixes = [
            " rooftop lounge",
            " rooftop bar",
            " rooftop club",
            " rooftop",
            " lounge",
            " nightclub",
            " night club",
            " club",
            " bar",
            " hotel",
            " west hollywood",
            " los angeles"
        ]

        func stripped(_ value: String) -> String {
            var output = (ExternalEventSupport.plainText(value) ?? value)
                .trimmingCharacters(in: .whitespacesAndNewlines)
            var changed = true
            while changed {
                changed = false
                let lowered = output.lowercased()
                for suffix in suffixes where lowered.hasSuffix(suffix) {
                    output = String(output.dropLast(suffix.count)).trimmingCharacters(in: .whitespacesAndNewlines)
                    changed = true
                    break
                }
            }
            if output.lowercased().hasPrefix("the ") {
                output = String(output.dropFirst(4)).trimmingCharacters(in: .whitespacesAndNewlines)
            }
            return output
        }

        var seen = Set<String>()
        return rawCandidates
            .flatMap { candidate -> [String] in
                let cleaned = (ExternalEventSupport.plainText(candidate) ?? candidate).trimmingCharacters(in: .whitespacesAndNewlines)
                let strippedCandidate = stripped(cleaned)
                return [cleaned, strippedCandidate]
            }
            .compactMap { candidate -> String? in
                let normalized = ExternalEventSupport.normalizeToken(candidate)
                guard normalized.count >= 3, !seen.contains(normalized) else { return nil }
                seen.insert(normalized)
                return candidate
            }
    }

    private func capture(in html: String, patterns: [String], maxMatches: Int = 1) -> String? {
        let lowered = html.lowercased()
        guard patterns.contains(where: lowered.contains) else { return nil }
        let text = ExternalEventSupport.plainText(html) ?? ""
        let snippets = text
            .components(separatedBy: ".")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { snippet in
                let normalized = snippet.lowercased()
                return patterns.contains(where: normalized.contains)
            }
        let unique = ExternalEventSupport.uniqueMeaningfulLines(snippets)
        guard !unique.isEmpty else { return nil }
        return unique.prefix(max(1, maxMatches)).joined(separator: ". ")
    }

    private func preferText(primary: String?, secondary: String?) -> String? {
        ExternalEventSupport.betterNightlifeText(primary: primary, secondary: secondary)
    }

    private func mergeCoverageStatus(_ primary: String?, _ secondary: String?) -> String? {
        let values = [primary, secondary]
            .compactMap { value -> String? in
                guard let value, !value.isEmpty else { return nil }
                return value
            }
        guard !values.isEmpty else { return nil }
        var seen = Set<String>()
        let unique = values.compactMap { value -> String? in
            let key = ExternalEventSupport.normalizeToken(value)
            guard !seen.contains(key) else { return nil }
            seen.insert(key)
            return value
        }
        return unique.joined(separator: " • ")
    }

    private func parseAgeMinimum(in html: String) -> Int? {
        if html.range(of: "21+", options: .caseInsensitive) != nil { return 21 }
        if html.range(of: "18+", options: .caseInsensitive) != nil { return 18 }
        return nil
    }

    private func containsAny(_ html: String, needles: [String]) -> Bool {
        let lowered = html.lowercased()
        return needles.contains(where: lowered.contains)
    }

    private func firstReservationURL(in html: String) -> String? {
        let patterns = [
            #"https?://[^"'\s>]*(?:sevenrooms|resy|opentable|tablelist|discotech|clubbable)[^"'\s<]*"#,
            #"https?://[^"'\s>]*reserve[^"'\s<]*"#
        ]
        for pattern in patterns {
            if let range = html.range(of: pattern, options: .regularExpression) {
                return String(html[range]).trimmingCharacters(in: CharacterSet(charactersIn: "\"'"))
            }
        }
        return nil
    }

    private func reservationProvider(for urlString: String?) -> String? {
        let normalized = ExternalEventSupport.normalizeToken(urlString)
        if normalized.contains("sevenrooms") { return "SevenRooms" }
        if normalized.contains("resy") { return "Resy" }
        if normalized.contains("opentable") { return "OpenTable" }
        if normalized.contains("tablelist") { return "Tablelist" }
        if normalized.contains("discotech") { return "Discotech" }
        if normalized.contains("clubbable") { return "Clubbable" }
        return nil
    }

    private func nightlifeSignalScore(for venue: ExternalVenue) -> Double {
        var score = 0.0
        if venue.guestListAvailable == true { score += 1.5 }
        if venue.bottleServiceAvailable == true { score += 2.0 }
        if venue.tableMinPrice != nil { score += 1.2 }
        if venue.ageMinimum == 21 { score += 0.8 }
        if venue.reservationURL != nil { score += 0.9 }
        return score
    }

    private func websiteMetadata(from html: String, baseURL: URL) -> WebsiteMetadata {
        let metaDescription = firstRegexMatch(
            in: html,
            pattern: #"<meta[^>]+(?:name|property)=["'](?:description|og:description|twitter:description)["'][^>]+content=["']([^"']+)["']"#,
            options: [.caseInsensitive]
        )
        let metaImage = firstRegexMatch(
            in: html,
            pattern: #"<meta[^>]+(?:property|name)=["'](?:og:image|twitter:image)["'][^>]+content=["']([^"']+)["']"#,
            options: [.caseInsensitive]
        )
        let inlineHeroImages = allRegexMatches(
            in: html,
            pattern: #"<img[^>]+(?:src|data-src)=["']([^"']+\.(?:jpe?g|png|webp)[^"']*)["'][^>]*>"#,
            groupCount: 1,
            options: [.caseInsensitive]
        )
        .compactMap(\.first)
        .compactMap { absoluteURL(path: $0, base: baseURL) }
        .filter { candidate in
            let normalized = ExternalEventSupport.normalizeToken(candidate)
            return !normalized.contains("logo")
                && !normalized.contains("icon")
                && !normalized.contains("favicon")
                && !normalized.contains("sprite")
        }

        let objects = jsonLDObjects(from: html)
        let businessObject = objects.first { object in
            let typeValue = ExternalEventSupport.normalizeToken(
                [object["@type"], object["type"]].compactMap { value in
                    if let string = value as? String { return string }
                    if let array = value as? [String] { return array.joined(separator: " ") }
                    return nil
                }.joined(separator: " ")
            )
            return typeValue.contains("nightclub")
                || typeValue.contains("bar")
                || typeValue.contains("restaurant")
                || typeValue.contains("localbusiness")
                || typeValue.contains("lodgingbusiness")
        }

        let structuredDescription = string(from: businessObject?["description"])
        let structuredImage = absoluteURL(path: string(from: businessObject?["image"]) ?? firstString(from: businessObject?["image"]), base: baseURL)
        let telephone = string(from: businessObject?["telephone"])
        let priceRange = string(from: businessObject?["priceRange"])
        let address = businessObject?["address"] as? [String: Any]
        let openingHoursText = openingHours(from: businessObject)
        let vibeText = capture(in: html, patterns: [
            "music", "vibe", "experience", "cocktail", "late night", "rooftop", "dj",
            "dance floor", "ambience", "atmosphere", "intimate", "upscale", "luxury"
        ])
        let imageGallery = ExternalEventSupport.uniqueMeaningfulLines(
            [metaImage, structuredImage] + Array(inlineHeroImages.prefix(6)).map(Optional.some)
        )

        return WebsiteMetadata(
            description: ExternalEventSupport.plainText(structuredDescription ?? metaDescription),
            vibeText: ExternalEventSupport.plainText(vibeText),
            imageURL: ExternalEventSupport.preferredImageURL(
                primary: absoluteURL(path: metaImage, base: baseURL),
                secondary: ExternalEventSupport.preferredImageURL(
                    primary: structuredImage,
                    secondary: inlineHeroImages.first
                )
            ),
            imageGallery: imageGallery,
            telephone: telephone,
            openingHoursText: openingHoursText,
            priceRange: priceRange,
            addressLine1: address.flatMap { addressLine(from: $0) },
            city: string(from: address?["addressLocality"]),
            state: string(from: address?["addressRegion"]),
            postalCode: string(from: address?["postalCode"])
        )
    }

    private func mergedWebsiteMetadata(primary: WebsiteMetadata, secondary: WebsiteMetadata) -> WebsiteMetadata {
        WebsiteMetadata(
            description: preferText(primary: primary.description, secondary: secondary.description),
            vibeText: preferText(primary: primary.vibeText, secondary: secondary.vibeText),
            imageURL: ExternalEventSupport.preferredImageURL(primary: primary.imageURL, secondary: secondary.imageURL),
            imageGallery: ExternalEventSupport.uniqueMeaningfulLines(
                primary.imageGallery.map(Optional.some) + secondary.imageGallery.map(Optional.some)
            ),
            telephone: preferText(primary: primary.telephone, secondary: secondary.telephone),
            openingHoursText: preferText(primary: primary.openingHoursText, secondary: secondary.openingHoursText),
            priceRange: preferText(primary: primary.priceRange, secondary: secondary.priceRange),
            addressLine1: preferText(primary: primary.addressLine1, secondary: secondary.addressLine1),
            city: preferText(primary: primary.city, secondary: secondary.city),
            state: preferText(primary: primary.state, secondary: secondary.state),
            postalCode: preferText(primary: primary.postalCode, secondary: secondary.postalCode)
        )
    }

    private func supplementalOfficialSiteURLs(from html: String, baseURL: URL) -> [URL] {
        let matches = allRegexMatches(
            in: html,
            pattern: #"<a[^>]+href=["']([^"'#>]+)["']"#,
            groupCount: 1,
            options: [.caseInsensitive]
        )
        .compactMap(\.first)

        let priorityTokens = [
            "hours", "location", "visit", "contact", "reservations", "reservation", "book", "private-events"
        ]

        var seen = Set<String>()
        var results: [URL] = []
        for match in matches {
            guard let absolute = absoluteURL(path: match, base: baseURL),
                  let url = URL(string: absolute),
                  url.host == baseURL.host
            else {
                continue
            }

            let normalized = ExternalEventSupport.normalizeToken(url.absoluteString)
            guard priorityTokens.contains(where: normalized.contains) else { continue }
            guard !normalized.contains("instagram"),
                  !normalized.contains("facebook"),
                  !normalized.contains("twitter"),
                  !normalized.contains("tiktok"),
                  !normalized.contains("opentable"),
                  !normalized.contains("sevenrooms"),
                  !normalized.contains("resy")
            else {
                continue
            }
            guard !seen.contains(url.absoluteString) else { continue }
            seen.insert(url.absoluteString)
            results.append(url)
        }
        return results
    }

    private func jsonLDObjects(from html: String) -> [[String: Any]] {
        let matches = allRegexMatches(
            in: html,
            pattern: #"<script[^>]+type=["']application/ld\+json["'][^>]*>(.*?)</script>"#,
            groupCount: 1,
            options: [.caseInsensitive, .dotMatchesLineSeparators]
        )

        return matches.flatMap { match -> [[String: Any]] in
            guard let raw = match.first,
                  let data = raw.data(using: .utf8),
                  let decoded = try? JSONSerialization.jsonObject(with: data) else {
                return []
            }
            return flattenJSONLD(decoded)
        }
    }

    private func flattenJSONLD(_ value: Any) -> [[String: Any]] {
        if let dictionary = value as? [String: Any] {
            let graph = (dictionary["@graph"] as? [Any] ?? []).flatMap(flattenJSONLD)
            return [dictionary] + graph
        }
        if let array = value as? [Any] {
            return array.flatMap(flattenJSONLD)
        }
        return []
    }

    private func addressLine(from address: [String: Any]) -> String? {
        let parts = [
            string(from: address["streetAddress"]),
            string(from: address["addressLine1"])
        ]
        .compactMap { $0 }
        .filter { !$0.isEmpty }
        return parts.first
    }

    private func openingHours(from object: [String: Any]?) -> String? {
        guard let object else { return nil }
        if let openingHours = object["openingHours"] as? [String], !openingHours.isEmpty {
            return openingHours.joined(separator: " | ")
        }
        if let openingHours = object["openingHours"] as? String, !openingHours.isEmpty {
            return openingHours
        }
        guard let specifications = object["openingHoursSpecification"] as? [[String: Any]], !specifications.isEmpty else {
            return nil
        }
        let lines = specifications.compactMap { specification -> String? in
            let day = string(from: specification["dayOfWeek"])?
                .replacingOccurrences(of: "https://schema.org/", with: "")
            let opens = string(from: specification["opens"])
            let closes = string(from: specification["closes"])
            let parts = [day, opens, closes].compactMap { $0 }.filter { !$0.isEmpty }
            guard !parts.isEmpty else { return nil }
            if let day, let opens, let closes {
                return "\(day): \(opens)-\(closes)"
            }
            return parts.joined(separator: " ")
        }
        return lines.isEmpty ? nil : lines.joined(separator: " | ")
    }

    private func string(from value: Any?) -> String? {
        if let string = value as? String {
            return string
        }
        return nil
    }

    private func firstString(from value: Any?) -> String? {
        if let array = value as? [String] {
            return array.first
        }
        if let array = value as? [Any] {
            return array.compactMap { $0 as? String }.first
        }
        return nil
    }

    private func firstRegexMatch(
        in text: String,
        pattern: String,
        options: NSRegularExpression.Options = []
    ) -> String? {
        allRegexMatches(in: text, pattern: pattern, groupCount: 1, options: options).first?.first
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

        let range = NSRange(text.startIndex..., in: text)
        return regex.matches(in: text, options: [], range: range).map { match in
            (1...groupCount).compactMap { index -> String? in
                guard let range = Range(match.range(at: index), in: text) else { return nil }
                return String(text[range])
            }
        }
    }

    private func absoluteURL(path: String?, base: URL) -> String? {
        guard let path, !path.isEmpty else { return nil }
        if path.hasPrefix("http://") || path.hasPrefix("https://") {
            return path
        }
        return URL(string: path, relativeTo: base)?.absoluteURL.absoluteString
    }

    private func capturePrice(in html: String, patterns: [String]) -> Double? {
        for pattern in patterns {
            guard let amount = firstRegexMatch(in: html, pattern: pattern, options: [.caseInsensitive]) else {
                continue
            }
            if let parsed = ExternalEventSupport.parseCurrencyAmount("$\(amount)") {
                return parsed
            }
        }
        return nil
    }

    private func mergePayload(_ existing: String?, extra: [String: Any]) -> String {
        var payload: [String: Any] = [:]
        if let existing,
           let data = existing.data(using: .utf8),
           let decoded = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            payload = decoded
        }
        extra.forEach { payload[$0.key] = $0.value }
        return ExternalEventSupport.jsonString(payload)
    }
}

nonisolated struct ReservationProviderNightlifeAdapter: NightlifeVenueEnrichmentAdapter {
    let source: ExternalEventSource = .reservationProvider

    func enrichVenues(
        _ venues: [ExternalVenue],
        query: ExternalVenueQuery,
        session: URLSession,
        configuration: ExternalEventServiceConfiguration
    ) async -> ExternalVenueSourceResult {
        let enriched = venues.compactMap { venue -> ExternalVenue? in
            guard let urlString = venue.reservationURL ?? venue.officialSiteURL else { return nil }
            let normalized = ExternalEventSupport.normalizeToken(urlString)
            var updated = venue
            if normalized.contains("sevenrooms") {
                updated.reservationProvider = "SevenRooms"
            } else if normalized.contains("resy") {
                updated.reservationProvider = "Resy"
            } else if normalized.contains("opentable") {
                updated.reservationProvider = "OpenTable"
            } else if normalized.contains("tablelist") {
                updated.reservationProvider = "Tablelist"
            } else if normalized.contains("discotech") {
                updated.reservationProvider = "Discotech"
            } else if normalized.contains("clubbable") {
                updated.reservationProvider = "Clubbable"
            } else {
                return nil
            }
            updated.sourceType = .reservationProvider
            updated.sourceConfidence = max(updated.sourceConfidence ?? 0, 0.7)
            return updated
        }

        return ExternalVenueSourceResult(
            source: source,
            fetchedAt: Date(),
            endpoints: [],
            note: enriched.isEmpty ? "No reservation-provider links were detected in current venue discovery results." : nil,
            venues: enriched
        )
    }
}

nonisolated struct NightlifeAggregatorVenueAdapter: ExternalVenueSourceAdapter, NightlifeVenueEnrichmentAdapter {
    let source: ExternalEventSource = .nightlifeAggregator

    func discoverVenues(
        query: ExternalVenueQuery,
        session: URLSession,
        configuration: ExternalEventServiceConfiguration
    ) async -> ExternalVenueSourceResult {
        var endpoints: [ExternalEventEndpointResult] = []
        var discoveredVenues: [ExternalVenue] = []
        let marketLimit = query.pageSize <= 6 ? 1 : (query.pageSize <= 10 ? 2 : 3)
        let earlyReturnTarget = max(4, min(query.pageSize, 6))
        let discotechMarkets = Array(discotechMarketCandidates(for: query).prefix(marketLimit))
        let clubbableMarkets = Array(clubbableMarketCandidates(for: query).prefix(marketLimit))
        let expectsDiscotechPass = !discotechMarkets.isEmpty
        let expectsClubbablePass = !clubbableMarkets.isEmpty
        var sawDiscotechPass = false
        var sawClubbablePass = false

        await withTaskGroup(of: MarketDiscoveryResult.self) { group in
            for market in discotechMarkets {
                group.addTask {
                    await discoverDiscotechVenues(market: market, query: query, session: session)
                }
            }

            for market in clubbableMarkets {
                group.addTask {
                    await discoverClubbableVenues(market: market, query: query, session: session)
                }
            }

            if shouldFetchHWood(for: query) {
                group.addTask {
                    await discoverHWoodVenues(query: query, session: session)
                }
            }

            while let result = await group.next() {
                switch result.sourceKind {
                case .discotech:
                    sawDiscotechPass = true
                case .clubbable:
                    sawClubbablePass = true
                case .hwood:
                    break
                }
                endpoints.append(contentsOf: result.endpoints)
                discoveredVenues.append(contentsOf: result.venues)
                let merged = ExternalVenueDiscoveryService.merge(discoveredVenues)
                let strongCount = merged.filter { venue in
                    (venue.nightlifeSignalScore ?? 0) >= 8
                        || venue.guestListAvailable == true
                        || venue.bottleServiceAvailable == true
                        || venue.reservationURL != nil
                }.count

                let hasSatisfiedMinimumSourceMix = (!expectsDiscotechPass || sawDiscotechPass)
                    && (!expectsClubbablePass || sawClubbablePass)

                if strongCount >= earlyReturnTarget && hasSatisfiedMinimumSourceMix {
                    discoveredVenues = merged
                    group.cancelAll()
                    break
                }
            }
        }

        let merged = ExternalVenueDiscoveryService.merge(discoveredVenues)
        return ExternalVenueSourceResult(
            source: source,
            fetchedAt: Date(),
            endpoints: endpoints.sorted { $0.label < $1.label },
            note: merged.isEmpty ? "Nightlife market discovery did not yield venue candidates for this location." : nil,
            venues: merged
        )
    }

    func enrichVenues(
        _ venues: [ExternalVenue],
        query: ExternalVenueQuery,
        session: URLSession,
        configuration: ExternalEventServiceConfiguration
    ) async -> ExternalVenueSourceResult {
        let targets = Array(venues.prefix(28))
        guard !targets.isEmpty else {
            return ExternalVenueSourceResult(
                source: source,
                fetchedAt: Date(),
                endpoints: [],
                note: "No nightlife venues were available for aggregator enrichment.",
                venues: []
            )
        }

        let shouldFetchHWood = targets.contains { ExternalEventSupport.normalizeStateToken($0.state) == "ca" }
        let hwoodSnapshot = shouldFetchHWood
            ? await fetchHWoodGuide(session: session)
            : HWoodGuideSnapshot(html: nil, endpoints: [], guestListVenues: [], tableBookingVenues: [], hotspotVenues: [])

        var endpoints = hwoodSnapshot.endpoints
        var enrichedVenues: [ExternalVenue] = []

        await withTaskGroup(of: VenueEnrichmentResult.self) { group in
            for venue in targets {
                group.addTask {
                    await enrichVenue(
                        venue,
                        query: query,
                        session: session,
                        hwoodSnapshot: hwoodSnapshot
                    )
                }
            }

            for await result in group {
                endpoints.append(contentsOf: result.endpoints)
                if let venue = result.venue {
                    enrichedVenues.append(venue)
                }
            }
        }

        let merged = ExternalVenueDiscoveryService.merge(enrichedVenues)
        return ExternalVenueSourceResult(
            source: source,
            fetchedAt: Date(),
            endpoints: endpoints.sorted { $0.label < $1.label },
            note: merged.isEmpty ? "Nightlife aggregators did not yield stronger venue metadata for the current market." : nil,
            venues: merged
        )
    }

    private struct VenueEnrichmentResult: Sendable {
        let endpoints: [ExternalEventEndpointResult]
        let venue: ExternalVenue?
    }

    private enum MarketDiscoverySourceKind: Sendable {
        case discotech
        case clubbable
        case hwood
    }

    private struct MarketDiscoveryResult: Sendable {
        let sourceKind: MarketDiscoverySourceKind
        let endpoints: [ExternalEventEndpointResult]
        let venues: [ExternalVenue]
    }

    private struct HWoodGuideSnapshot: Sendable {
        let html: String?
        let endpoints: [ExternalEventEndpointResult]
        let guestListVenues: [String]
        let tableBookingVenues: [String]
        let hotspotVenues: [String]
    }

    private struct NightlifePolicySnapshot: Sendable {
        let entryPolicySummary: String?
        let womenEntryPolicyText: String?
        let menEntryPolicyText: String?
        let doorPolicyText: String?
        let exclusivityTierLabel: String?
    }

    private func enrichVenue(
        _ venue: ExternalVenue,
        query: ExternalVenueQuery,
        session: URLSession,
        hwoodSnapshot: HWoodGuideSnapshot
    ) async -> VenueEnrichmentResult {
        var endpoints: [ExternalEventEndpointResult] = []
        var candidates: [ExternalVenue] = []

        let discotechResult = await enrichWithDiscotech(venue: venue, query: query, session: session)
        endpoints.append(contentsOf: discotechResult.endpoints)
        if let venue = discotechResult.venue {
            candidates.append(venue)
        }

        let clubbableResult = await enrichWithClubbable(venue: venue, query: query, session: session)
        endpoints.append(contentsOf: clubbableResult.endpoints)
        if let venue = clubbableResult.venue {
            candidates.append(venue)
        }

        if let hwoodVenue = enrichWithHWood(venue: venue, snapshot: hwoodSnapshot) {
            candidates.append(hwoodVenue)
        }

        guard !candidates.isEmpty else {
            return VenueEnrichmentResult(endpoints: endpoints, venue: nil)
        }

        let merged = ExternalVenueDiscoveryService.merge(candidates + [venue]).first
        return VenueEnrichmentResult(endpoints: endpoints, venue: merged)
    }

    private func enrichWithDiscotech(
        venue: ExternalVenue,
        query: ExternalVenueQuery,
        session: URLSession
    ) async -> VenueEnrichmentResult {
        var endpoints: [ExternalEventEndpointResult] = []
        let searchTerms = venueSearchTerms(for: venue)
        let preferredMarkets = discotechMarketCandidates(for: venue, query: query)

        for candidateURL in discotechGuideURLs(for: venue, query: query).prefix(8) {
            let pageFetch = await fetchHTML(
                url: candidateURL,
                label: "Discotech guide \(venue.name)",
                session: session
            )
            endpoints.append(pageFetch.endpoint)
            guard let pageHTML = pageFetch.html,
                  let enrichedVenue = parseDiscotechVenuePage(
                    html: pageHTML,
                    url: candidateURL,
                    baseVenue: venue,
                    query: query
                  ) else {
                continue
            }
            return VenueEnrichmentResult(endpoints: endpoints, venue: enrichedVenue)
        }

        for searchTerm in searchTerms.prefix(5) {
            guard let searchURL = discotechSearchURL(for: searchTerm) else { continue }

            let searchFetch = await fetchHTML(
                url: searchURL,
                label: "Discotech search \(searchTerm)",
                session: session
            )
            endpoints.append(searchFetch.endpoint)
            guard let searchHTML = searchFetch.html else {
                continue
            }

            let candidateURLs = prioritizeDiscotechURLs(
                discotechCandidateURLs(from: searchHTML, searchTerms: searchTerms),
                preferredMarkets: preferredMarkets
            )
            for candidateURL in candidateURLs.prefix(5) {
                let pageFetch = await fetchHTML(
                    url: candidateURL,
                    label: "Discotech guide \(venue.name)",
                    session: session
                )
                endpoints.append(pageFetch.endpoint)
                guard let pageHTML = pageFetch.html,
                      let enrichedVenue = parseDiscotechVenuePage(
                        html: pageHTML,
                        url: candidateURL,
                        baseVenue: venue,
                        query: query
                      ) else {
                    continue
                }
                return VenueEnrichmentResult(endpoints: endpoints, venue: enrichedVenue)
            }
        }

        return VenueEnrichmentResult(endpoints: endpoints, venue: nil)
    }

    private func enrichWithClubbable(
        venue: ExternalVenue,
        query: ExternalVenueQuery,
        session: URLSession
    ) async -> VenueEnrichmentResult {
        var endpoints: [ExternalEventEndpointResult] = []

        for url in clubbableCandidateURLs(for: venue, query: query).prefix(8) {
            let fetch = await fetchHTML(
                url: url,
                label: "Clubbable \(venue.name)",
                session: session
            )
            endpoints.append(fetch.endpoint)
            guard let html = fetch.html,
                  let enrichedVenue = parseClubbableVenuePage(
                    html: html,
                    url: url,
                    baseVenue: venue,
                    query: query
                  ) else {
                continue
            }
            return VenueEnrichmentResult(endpoints: endpoints, venue: enrichedVenue)
        }

        return VenueEnrichmentResult(endpoints: endpoints, venue: nil)
    }

    private func enrichWithHWood(
        venue: ExternalVenue,
        snapshot: HWoodGuideSnapshot
    ) -> ExternalVenue? {
        let venueKey = ExternalEventSupport.normalizeToken(venue.name)
        guard !venueKey.isEmpty else { return nil }

        let listedForGuestList = snapshot.guestListVenues.contains(venueKey)
        let listedForTables = snapshot.tableBookingVenues.contains(venueKey)
        let listedAsHotspot = snapshot.hotspotVenues.contains(venueKey)

        guard listedForGuestList || listedForTables || listedAsHotspot else { return nil }

        var updated = venue
        updated.source = source
        updated.sourceType = .nightlifeAggregator
        updated.guestListAvailable = updated.guestListAvailable ?? listedForGuestList
        updated.bottleServiceAvailable = updated.bottleServiceAvailable ?? listedForTables
        if updated.doorPolicyText == nil {
            switch (listedForGuestList, listedForTables) {
            case (true, true):
                updated.doorPolicyText = "Guest list access and table bookings are offered through h.wood Rolodex."
            case (true, false):
                updated.doorPolicyText = "Guest list access is offered through h.wood Rolodex."
            case (false, true):
                updated.doorPolicyText = "Table bookings are offered through h.wood Rolodex."
            case (false, false):
                break
            }
        }
        updated.sourceConfidence = max(updated.sourceConfidence ?? 0, 0.5)
        updated.sourceCoverageStatus = mergeCoverageStatus(updated.sourceCoverageStatus, "h.wood Rolodex mention")
        updated.nightlifeSignalScore = max(
            updated.nightlifeSignalScore ?? 0,
            (updated.nightlifeSignalScore ?? 0) + (listedForGuestList ? 1.2 : 0) + (listedForTables ? 1.6 : 0) + (listedAsHotspot ? 1.4 : 0)
        )
        updated.prestigeDemandScore = max(
            updated.prestigeDemandScore ?? 0,
            (updated.prestigeDemandScore ?? 0) + (listedAsHotspot ? 1.6 : 0) + (listedForGuestList ? 0.7 : 0)
        )
        updated.rawSourcePayload = mergePayload(
            updated.rawSourcePayload,
            extra: [
                "hwood_guest_list": listedForGuestList,
                "hwood_table_booking": listedForTables,
                "hwood_hotspot": listedAsHotspot,
                "hwood_summary": listedAsHotspot ? "Recognized in h.wood Rolodex as a nightlife hotspot." : "Listed in h.wood Rolodex."
            ]
        )
        return updated
    }

    private func fetchHWoodGuide(session: URLSession) async -> HWoodGuideSnapshot {
        guard let url = URL(string: "https://rolodex.hwoodgroup.com/") else {
            return HWoodGuideSnapshot(html: nil, endpoints: [], guestListVenues: [], tableBookingVenues: [], hotspotVenues: [])
        }

        let fetch = await fetchHTML(url: url, label: "h.wood Rolodex", session: session)
        guard let html = fetch.html else {
            return HWoodGuideSnapshot(html: nil, endpoints: [fetch.endpoint], guestListVenues: [], tableBookingVenues: [], hotspotVenues: [])
        }

        let plain = ExternalEventSupport.plainText(html) ?? ""
        let guestListVenues = extractVenueList(
            in: plain,
            prefix: "Guest list access to",
            stopTokens: ["10 off table bookings", "monthly", "access to", "apply"]
        )
        let tableBookingVenues = extractVenueList(
            in: plain,
            prefix: "10 off table bookings at",
            stopTokens: ["when you book", "monthly", "access to", "apply"]
        )
        let hotspotVenues = extractVenueList(
            in: plain,
            prefix: "Los Angeles Hotspots",
            stopTokens: ["global ouposts", "locations", "cities", "discover unmatched luxury"]
        )

        return HWoodGuideSnapshot(
            html: html,
            endpoints: [fetch.endpoint],
            guestListVenues: guestListVenues,
            tableBookingVenues: tableBookingVenues,
            hotspotVenues: hotspotVenues
        )
    }

    private func discoverDiscotechVenues(
        market: String,
        query: ExternalVenueQuery,
        session: URLSession
    ) async -> MarketDiscoveryResult {
        guard let marketURL = URL(string: "https://discotech.me/\(market)/") else {
            return MarketDiscoveryResult(sourceKind: .discotech, endpoints: [], venues: [])
        }

        let marketFetch = await fetchHTML(
            url: marketURL,
            label: "Discotech market \(market)",
            session: session
        )
        guard let marketHTML = marketFetch.html else {
            return MarketDiscoveryResult(sourceKind: .discotech, endpoints: [marketFetch.endpoint], venues: [])
        }

        var endpoints = [marketFetch.endpoint]
        var discovered: [ExternalVenue] = []
        let mentionExpansionLimit = query.pageSize <= 6 ? 3 : (query.pageSize <= 10 ? 6 : 12)
        let venuePageLimit = min(max(query.pageSize, 4), query.pageSize <= 6 ? 4 : (query.pageSize <= 10 ? 8 : 18))
        let candidateURLs = extractDiscotechVenueURLs(from: marketHTML, market: market)
        let plainMarketHTML = ExternalEventSupport.plainText(marketHTML) ?? marketHTML
        let celebrityMentions = splitVenueMentionSentence(
            firstRegexMatch(
                in: marketHTML,
                pattern: #"find celebrities at(.*?)\.</p>"#,
                options: [.caseInsensitive, .dotMatchesLineSeparators]
            )
        ) + extractVenueList(
            in: plainMarketHTML,
            prefix: "find celebrities at",
            stopTokens: ["The hottest clubs in", "You'll typically", "Discotech Newsfeed"]
        )
        let hotListMentions = splitVenueMentionSentence(
            firstRegexMatch(
                in: marketHTML,
                pattern: #"The hottest clubs in .*? are probably(.*?)\.</p>"#,
                options: [.caseInsensitive, .dotMatchesLineSeparators]
            )
        ) + extractVenueList(
            in: plainMarketHTML,
            prefix: "The hottest clubs in",
            stopTokens: ["You'll typically", "Discotech Newsfeed"]
        )

        var mentionSeeds: [ExternalVenue] = []
        for mention in uniqueStrings(celebrityMentions + hotListMentions) {
            guard let displayName = sanitizedNightlifeMentionName(from: mention) else {
                continue
            }

            var seeded = seedVenue(
                name: displayName,
                sourceVenueID: "discotech-mention:\(market):\(slugify(displayName))",
                query: query,
                discoveryURL: marketURL.absoluteString,
                coverageStatus: "Discotech market mention",
                venueType: .nightlifeVenue,
                sourceConfidence: 0.58
            )
            seeded.doorPolicyText = "Highlighted in Discotech's market guide for \(query.displayName ?? query.city ?? market)."
            seeded.nightlifeSignalScore = max(seeded.nightlifeSignalScore ?? 0, celebrityMentions.contains(mention) ? 9.2 : 8.4)
            seeded.prestigeDemandScore = max(seeded.prestigeDemandScore ?? 0, celebrityMentions.contains(mention) ? 10.0 : 9.0)
            discovered.append(seeded)
            mentionSeeds.append(seeded)
        }

        await withTaskGroup(of: (ExternalEventEndpointResult?, ExternalVenue?).self) { group in
            for seed in mentionSeeds.prefix(mentionExpansionLimit) {
                group.addTask {
                    guard let searchURL = self.discotechSearchURL(for: seed.name) else {
                        return (nil, seed)
                    }

                    let searchFetch = await self.fetchHTML(
                        url: searchURL,
                        label: "Discotech search \(seed.name)",
                        session: session
                    )
                    guard let searchHTML = searchFetch.html else {
                        return (searchFetch.endpoint, seed)
                    }

                    let candidateURLs = self.prioritizeDiscotechURLs(
                        self.discotechCandidateURLs(
                            from: searchHTML,
                            searchTerms: self.venueSearchTerms(for: seed)
                        ),
                        preferredMarkets: [market]
                    )

                    var endpointsForSeed = [searchFetch.endpoint]
                    for candidateURL in candidateURLs.prefix(4) {
                        let pageFetch = await self.fetchHTML(
                            url: candidateURL,
                            label: "Discotech venue \(seed.name)",
                            session: session
                        )
                        endpointsForSeed.append(pageFetch.endpoint)
                        guard let pageHTML = pageFetch.html,
                              let enrichedVenue = self.parseDiscotechVenuePage(
                                html: pageHTML,
                                url: candidateURL,
                                baseVenue: seed,
                                query: query
                              ) else {
                            continue
                        }
                        return (endpointsForSeed.last, enrichedVenue)
                    }

                    return (endpointsForSeed.last, seed)
                }
            }

            for await result in group {
                if let endpoint = result.0 {
                    endpoints.append(endpoint)
                }
                if let venue = result.1 {
                    discovered.append(venue)
                }
            }
        }

        await withTaskGroup(of: (ExternalEventEndpointResult, ExternalVenue?).self) { group in
            for candidateURL in candidateURLs.prefix(venuePageLimit) {
                group.addTask {
                    let pageFetch = await fetchHTML(
                        url: candidateURL,
                        label: "Discotech venue \(candidateURL.lastPathComponent)",
                        session: session
                    )
                    guard let pageHTML = pageFetch.html else {
                        return (pageFetch.endpoint, nil)
                    }

                    let seed = seedVenue(
                        name: humanizedVenueName(fromSlug: candidateURL.lastPathComponent),
                        sourceVenueID: "discotech:\(market):\(candidateURL.lastPathComponent)",
                        query: query,
                        discoveryURL: candidateURL.absoluteString,
                        coverageStatus: "Discotech",
                        venueType: .nightlifeVenue,
                        sourceConfidence: 0.62
                    )
                    let venue = parseDiscotechVenuePage(
                        html: pageHTML,
                        url: candidateURL,
                        baseVenue: seed,
                        query: query
                    ) ?? seed
                    return (pageFetch.endpoint, venue)
                }
            }

            for await result in group {
                endpoints.append(result.0)
                if let venue = result.1 {
                    discovered.append(venue)
                }
            }
        }

        return MarketDiscoveryResult(sourceKind: .discotech, endpoints: endpoints, venues: discovered)
    }

    private func discoverClubbableVenues(
        market: String,
        query: ExternalVenueQuery,
        session: URLSession
    ) async -> MarketDiscoveryResult {
        guard let marketURL = URL(string: "https://www.clubbable.com/\(market)") else {
            return MarketDiscoveryResult(sourceKind: .clubbable, endpoints: [], venues: [])
        }

        let marketFetch = await fetchHTML(
            url: marketURL,
            label: "Clubbable market \(market)",
            session: session
        )
        guard let marketHTML = marketFetch.html else {
            return MarketDiscoveryResult(sourceKind: .clubbable, endpoints: [marketFetch.endpoint], venues: [])
        }

        var endpoints = [marketFetch.endpoint]
        var discovered: [ExternalVenue] = []
        let venuePageLimit = min(max(query.pageSize, 4), query.pageSize <= 6 ? 4 : (query.pageSize <= 10 ? 8 : 16))
        let candidateURLs = extractClubbableVenueURLs(from: marketHTML, market: market)

        await withTaskGroup(of: (ExternalEventEndpointResult, ExternalVenue?).self) { group in
            for candidateURL in candidateURLs.prefix(venuePageLimit) {
                group.addTask {
                    let pageFetch = await fetchHTML(
                        url: candidateURL,
                        label: "Clubbable venue \(candidateURL.lastPathComponent)",
                        session: session
                    )
                    guard let pageHTML = pageFetch.html else {
                        return (pageFetch.endpoint, nil)
                    }

                    let seed = seedVenue(
                        name: humanizedVenueName(fromSlug: candidateURL.lastPathComponent),
                        sourceVenueID: "clubbable:\(market):\(candidateURL.lastPathComponent)",
                        query: query,
                        discoveryURL: candidateURL.absoluteString,
                        coverageStatus: "Clubbable",
                        venueType: .nightlifeVenue,
                        sourceConfidence: 0.61
                    )
                    let venue = parseClubbableVenuePage(
                        html: pageHTML,
                        url: candidateURL,
                        baseVenue: seed,
                        query: query
                    ) ?? seed
                    return (pageFetch.endpoint, venue)
                }
            }

            for await result in group {
                endpoints.append(result.0)
                if let venue = result.1 {
                    discovered.append(venue)
                }
            }
        }

        return MarketDiscoveryResult(sourceKind: .clubbable, endpoints: endpoints, venues: discovered)
    }

    private func discoverHWoodVenues(
        query: ExternalVenueQuery,
        session: URLSession
    ) async -> MarketDiscoveryResult {
        let snapshot = await fetchHWoodGuide(session: session)
        let seedURL = "https://rolodex.hwoodgroup.com/"
        let allVenueKeys = Array(
            Set(snapshot.hotspotVenues + snapshot.guestListVenues + snapshot.tableBookingVenues)
        )

        let venues = allVenueKeys.map { venueKey -> ExternalVenue in
            let displayName = humanizedVenueName(fromSlug: venueKey.replacingOccurrences(of: " ", with: "-"))
            var venue = seedVenue(
                name: displayName,
                sourceVenueID: "hwood:\(slugify(displayName))",
                query: query,
                discoveryURL: seedURL,
                coverageStatus: "h.wood Rolodex mention",
                venueType: .nightlifeVenue,
                sourceConfidence: 0.42
            )

            let listedForGuestList = snapshot.guestListVenues.contains(venueKey)
            let listedForTables = snapshot.tableBookingVenues.contains(venueKey)
            let listedAsHotspot = snapshot.hotspotVenues.contains(venueKey)

            venue.guestListAvailable = listedForGuestList
            venue.bottleServiceAvailable = listedForTables
            venue.doorPolicyText = hwoodDoorPolicyText(
                listedForGuestList: listedForGuestList,
                listedForTables: listedForTables,
                listedAsHotspot: listedAsHotspot
            )
            let hwoodPolicy = buildNightlifePolicySnapshot(
                texts: [
                    venue.doorPolicyText,
                    listedAsHotspot
                        ? "Recognized by h.wood Rolodex as a hotspot with a more curated door."
                        : "Listed by h.wood Rolodex for nightlife access."
                ],
                guestListAvailable: listedForGuestList,
                bottleServiceAvailable: listedForTables,
                tableMinPrice: nil,
                coverPrice: nil,
                sourceCoverageStatus: "h.wood Rolodex mention"
            )
            venue.entryPolicySummary = hwoodPolicy.entryPolicySummary
            venue.exclusivityTierLabel = hwoodPolicy.exclusivityTierLabel
            venue.nightlifeSignalScore = 3.5
                + (listedForGuestList ? 1.8 : 0)
                + (listedForTables ? 2.4 : 0)
                + (listedAsHotspot ? 1.4 : 0)
            venue.prestigeDemandScore = 3.8
                + (listedAsHotspot ? 2.2 : 0)
                + (listedForGuestList ? 0.8 : 0)
            venue.venueSignalScore = 3.5
            venue.rawSourcePayload = mergePayload(
                venue.rawSourcePayload,
                extra: [
                    "hwood_guest_list": listedForGuestList,
                    "hwood_table_booking": listedForTables,
                    "hwood_hotspot": listedAsHotspot,
                    "hwood_summary": listedAsHotspot
                        ? "Recognized by h.wood Rolodex as a nightlife hotspot."
                        : "Listed by h.wood Rolodex."
                ]
            )
            return venue
        }

        return MarketDiscoveryResult(sourceKind: .hwood, endpoints: snapshot.endpoints, venues: venues)
    }

    private func fetchHTML(
        url: URL,
        label: String,
        session: URLSession
    ) async -> (endpoint: ExternalEventEndpointResult, html: String?) {
        do {
            let (data, response) = try await session.data(from: url)
            let statusCode = (response as? HTTPURLResponse)?.statusCode
            let worked = statusCode.map { 200..<300 ~= $0 } ?? false
            let html = worked ? String(data: data, encoding: .utf8) : nil
            return (
                ExternalEventEndpointResult(
                    label: label,
                    requestURL: url.absoluteString,
                    responseStatusCode: statusCode,
                    worked: worked,
                    note: worked ? nil : "Non-success response."
                ),
                html
            )
        } catch {
            return (
                ExternalEventEndpointResult(
                    label: label,
                    requestURL: url.absoluteString,
                    responseStatusCode: nil,
                    worked: false,
                    note: error.localizedDescription
                ),
                nil
            )
        }
    }

    private func extractDiscotechVenueURLs(from html: String, market: String) -> [URL] {
        let escapedMarket = NSRegularExpression.escapedPattern(for: market)
        let matches = allRegexMatches(
            in: html,
            pattern: "https://discotech\\.me/\(escapedMarket)/([A-Za-z0-9%\\-]+)/?",
            groupCount: 1,
            options: [.caseInsensitive]
        )

        var seen = Set<String>()
        return matches.compactMap { match -> URL? in
            guard let slug = match.first?.trimmingCharacters(in: CharacterSet(charactersIn: "/")),
                  isLikelyNightlifeVenueSlug(slug) else {
                return nil
            }
            guard let url = URL(string: "https://discotech.me/\(market)/\(slug)/") else { return nil }
            guard !seen.contains(url.absoluteString) else { return nil }
            seen.insert(url.absoluteString)
            return url
        }
    }

    private func extractClubbableVenueURLs(from html: String, market: String) -> [URL] {
        let escapedMarket = NSRegularExpression.escapedPattern(for: market)
        let matches = allRegexMatches(
            in: html,
            pattern: "/\(escapedMarket)/([A-Za-z0-9\\-]+)",
            groupCount: 1,
            options: [.caseInsensitive]
        )

        var seen = Set<String>()
        return matches.compactMap { match -> URL? in
            guard let slug = match.first?.trimmingCharacters(in: CharacterSet(charactersIn: "/")),
                  isLikelyNightlifeVenueSlug(slug) else {
                return nil
            }
            guard let url = URL(string: "https://www.clubbable.com/\(market)/\(slug)") else { return nil }
            guard !seen.contains(url.absoluteString) else { return nil }
            seen.insert(url.absoluteString)
            return url
        }
    }

    private func discotechSearchURL(for venueName: String) -> URL? {
        var components = URLComponents(string: "https://discotech.me/")!
        components.queryItems = [URLQueryItem(name: "s", value: venueName)]
        return components.url
    }

    private func discotechGuideURLs(
        for venue: ExternalVenue,
        query: ExternalVenueQuery
    ) -> [URL] {
        let marketCandidates = discotechMarketCandidates(for: venue, query: query)
        var urls: [URL] = []
        var seen = Set<String>()

        for searchTerm in venueSearchTerms(for: venue) {
            let venueSlug = slugify(searchTerm)
            for market in marketCandidates {
                guard let url = URL(string: "https://discotech.me/\(market)/\(venueSlug)/") else { continue }
                guard !seen.contains(url.absoluteString) else { continue }
                seen.insert(url.absoluteString)
                urls.append(url)
            }
        }

        return urls
    }

    private func discotechMarketCandidates(
        for venue: ExternalVenue,
        query: ExternalVenueQuery
    ) -> [String] {
        var candidates: [String] = []
        let state = ExternalEventSupport.normalizeStateToken(venue.state ?? query.state)
        let normalizedCities = [venue.city, query.city, query.displayName]
            .compactMap { $0 }
            .map(ExternalEventSupport.normalizeToken)

        func append(_ raw: String?) {
            guard let raw, !raw.isEmpty else { return }
            let slug = slugify(raw)
            guard !slug.isEmpty, !candidates.contains(slug) else { return }
            candidates.append(slug)
        }

        normalizedCities.forEach { append($0) }

        if state == "ca", normalizedCities.contains(where: ExternalEventSupport.isLosAngelesMetroToken) {
            append("los angeles")
        } else if state == "ny", normalizedCities.contains(where: { ["new york", "new york city", "brooklyn", "manhattan", "queens"].contains($0) }) {
            append("new york")
        } else if state == "fl", normalizedCities.contains(where: { ["miami", "miami beach", "south beach"].contains($0) }) {
            append("miami")
        } else if state == "nv", normalizedCities.contains(where: { ["las vegas", "paradise"].contains($0) }) {
            append("las vegas")
        } else if state == "il", normalizedCities.contains(where: { ["chicago"].contains($0) }) {
            append("chicago")
        } else if state == "tx", let first = normalizedCities.first {
            append(first)
        }

        return candidates
    }

    private func discotechMarketCandidates(for query: ExternalVenueQuery) -> [String] {
        var candidates: [String] = []
        let state = ExternalEventSupport.normalizeStateToken(query.state)
        let normalizedCities = [query.city, query.displayName]
            .compactMap { $0 }
            .map(ExternalEventSupport.normalizeToken)

        func append(_ raw: String?) {
            guard let raw, !raw.isEmpty else { return }
            let slug = slugify(raw)
            guard !slug.isEmpty, !candidates.contains(slug) else { return }
            candidates.append(slug)
        }

        normalizedCities.forEach { append($0) }

        if state == "ca", normalizedCities.contains(where: ExternalEventSupport.isLosAngelesMetroToken) {
            append("los angeles")
        } else if state == "ny", normalizedCities.contains(where: { ["new york", "new york city", "brooklyn", "manhattan", "queens"].contains($0) }) {
            append("new york")
        } else if state == "fl", normalizedCities.contains(where: { ["miami", "miami beach", "south beach"].contains($0) }) {
            append("miami")
        } else if state == "nv", normalizedCities.contains(where: { ["las vegas", "paradise"].contains($0) }) {
            append("las vegas")
        } else if state == "il", normalizedCities.contains(where: { ["chicago"].contains($0) }) {
            append("chicago")
        } else if state == "tx", let first = normalizedCities.first {
            append(first)
        }

        return candidates
    }

    private func discotechCandidateURLs(from html: String, searchTerms: [String]) -> [URL] {
        let venueTokens = normalizedVenueTokens(forSearchTerms: searchTerms)
        let titleURLMatches = allRegexMatches(
            in: html,
            pattern: #"<a[^>]+title=['"]([^'"]+)['"][^>]+href=['"](https://discotech\.me/[^'"]+)['"]"#,
            groupCount: 2,
            options: [.caseInsensitive]
        )

        var ranked = titleURLMatches.compactMap { match -> (url: URL, score: Int)? in
            guard match.count >= 2,
                  let url = URL(string: match[1]),
                  isUsableDiscotechVenueURL(url) else { return nil }

            let titleToken = ExternalEventSupport.normalizeToken(match[0])
            let pathToken = ExternalEventSupport.normalizeToken(url.path)
            let matchedToken = venueTokens.first { token in
                titleToken.contains(token) || pathToken.contains(token)
            }
            guard let matchedToken else {
                return nil
            }

            var score = 0
            if pathToken.contains(matchedToken) { score += 16 }
            if titleToken == matchedToken { score += 12 }
            if venueTokens.contains(where: { token in url.path.hasSuffix("/\(slugify(token))/") }) { score += 18 }
            if pathToken.contains("guestlist") { score -= 5 }
            if pathToken.contains("tickets") { score -= 6 }
            if pathToken.contains("promo code") || pathToken.contains("promo-code") { score -= 8 }
            if pathToken.contains("bottle service") || pathToken.contains("bottle-service") { score -= 2 }
            return (url, score)
        }

        let urlOnlyMatches = allRegexMatches(
            in: html,
            pattern: #"(https://discotech\.me/[^"'\s<]+)"#,
            groupCount: 1,
            options: [.caseInsensitive]
        )

        ranked.append(contentsOf: urlOnlyMatches.compactMap { match -> (url: URL, score: Int)? in
            guard let raw = match.first,
                  let url = URL(string: raw),
                  isUsableDiscotechVenueURL(url) else { return nil }

            let pathToken = ExternalEventSupport.normalizeToken(url.path)
            let matchedToken = venueTokens.first { token in
                pathToken.contains(token)
            }
            guard let matchedToken else { return nil }

            var score = 0
            if pathToken.contains(matchedToken) { score += 16 }
            if venueTokens.contains(where: { token in url.path.hasSuffix("/\(slugify(token))/") }) { score += 18 }
            if pathToken.contains("guestlist") { score -= 5 }
            if pathToken.contains("tickets") { score -= 6 }
            if pathToken.contains("promo code") || pathToken.contains("promo-code") { score -= 8 }
            if pathToken.contains("bottle service") || pathToken.contains("bottle-service") { score -= 2 }
            return (url, score)
        })

        ranked.sort { lhs, rhs in
            if lhs.score == rhs.score {
                return lhs.url.absoluteString < rhs.url.absoluteString
            }
            return lhs.score > rhs.score
        }
        var seen = Set<String>()
        return ranked.compactMap { candidate in
            let key = candidate.url.absoluteString
            guard !seen.contains(key) else { return nil }
            seen.insert(key)
            return candidate.url
        }
    }

private func isUsableDiscotechVenueURL(_ url: URL) -> Bool {
    guard let host = url.host?.lowercased(),
          host.contains("discotech.me") else {
        return false
    }

    let normalizedPath = ExternalEventSupport.normalizeToken(
        url.path.replacingOccurrences(of: "-", with: " ")
    )
    let blockedTokens = [
        "search",
        "feed",
        "rss",
        "newsfeed",
        "tag",
        "category",
        "promo code",
        "promo codes"
    ]
    guard !blockedTokens.contains(where: normalizedPath.contains) else {
        return false
    }

    let pathComponents = url.pathComponents.filter { $0 != "/" }
    return pathComponents.count >= 2
}

private func prioritizeDiscotechURLs(

        _ urls: [URL],
        preferredMarkets: [String]
    ) -> [URL] {
        let normalizedMarkets = Set(preferredMarkets.map(ExternalEventSupport.normalizeToken))
        return urls.sorted { lhs, rhs in
            let leftPath = ExternalEventSupport.normalizeToken(lhs.path.replacingOccurrences(of: "-", with: " "))
            let rightPath = ExternalEventSupport.normalizeToken(rhs.path.replacingOccurrences(of: "-", with: " "))
            let leftPreferred = normalizedMarkets.contains { leftPath.contains($0) }
            let rightPreferred = normalizedMarkets.contains { rightPath.contains($0) }
            if leftPreferred == rightPreferred {
                return lhs.absoluteString < rhs.absoluteString
            }
            return leftPreferred && !rightPreferred
        }
    }

    private func parseDiscotechVenuePage(
        html: String,
        url: URL,
        baseVenue: ExternalVenue,
        query: ExternalVenueQuery
    ) -> ExternalVenue? {
        guard isUsableDiscotechVenueURL(url) else {
            return nil
        }
        let normalizedHTML = ExternalEventSupport.normalizeToken(html)
        let identityTokens = normalizedVenueTokens(for: baseVenue)
        let normalizedPath = ExternalEventSupport.normalizeToken(url.path.replacingOccurrences(of: "-", with: " "))
        guard identityTokens.contains(where: { normalizedHTML.contains($0) || normalizedPath.contains($0) }) else {
            return nil
        }

        let metaDescription = firstRegexMatch(
            in: html,
            pattern: #"<meta[^>]+name="description"[^>]+content="([^"]+)""#,
            options: [.caseInsensitive]
        )
        let headline = firstRegexMatch(
            in: html,
            pattern: #"<h1[^>]*>(.*?)</h1>"#,
            options: [.caseInsensitive, .dotMatchesLineSeparators]
        )
        if shouldRejectOutOfMarketNightlifePage(
            candidateName: headline,
            url: url,
            baseVenue: baseVenue,
            query: query
        ) {
            return nil
        }
        if let headline, !isLikelyNightlifeVenueName(headline) {
            return nil
        }
        let ogImage = firstRegexMatch(
            in: html,
            pattern: #"<meta[^>]+property="og:image"[^>]+content="([^"]+)""#,
            options: [.caseInsensitive]
        )
        let galleryImages = extractDiscotechGalleryImages(
            from: html,
            baseURL: url,
            venueTokens: identityTokens
        )
        let insiderTips = extractDiscotechListSection(html: html, title: "Insider Tips")
        let qaPairs = extractDiscotechQAPairs(from: html)

        let coverAnswer = answer(in: qaPairs, matching: "cover charge")
        let openAnswer = answer(in: qaPairs, matching: "open")
        let dressCodeAnswer = answer(in: qaPairs, matching: "dress code")
        let drinksAnswer = answer(in: qaPairs, matching: "drinks cost")
        let waitAnswer = answer(in: qaPairs, matching: "wait")
        let musicAnswer = answer(in: qaPairs, matching: "kind of music")
        let bestNightsAnswer = answer(in: qaPairs, matching: "best nights")
        let womenEntryExtract = entrySnippet(
            in: html,
            matching: ["women", "ladies", "girls", "female"],
            maxMatches: 2
        )
        let menEntryExtract = entrySnippet(
            in: html,
            matching: ["men", "guys", "gentlemen", "male"],
            maxMatches: 2
        )
        let guestListAvailable = normalizedHTML.contains("guest list")
        let bottleServiceAvailable = normalizedHTML.contains("bottle service")
        let coverPrice = parseCoverPrice(from: coverAnswer)
        let tableMinPrice = [
            parseTableMinimum(from: drinksAnswer),
            parseTableMinimum(from: coverAnswer),
            parseTableMinimum(from: metaDescription)
        ].compactMap { $0 }.max()
        let policy = buildNightlifePolicySnapshot(
            texts: [
                coverAnswer,
                waitAnswer,
                dressCodeAnswer,
                drinksAnswer,
                musicAnswer,
                bestNightsAnswer,
                womenEntryExtract,
                menEntryExtract,
                insiderTips.joined(separator: ". ")
            ],
            guestListAvailable: guestListAvailable,
            bottleServiceAvailable: bottleServiceAvailable,
            tableMinPrice: tableMinPrice,
            coverPrice: coverPrice,
            sourceCoverageStatus: "Discotech"
        )

        var doorNotes: [String] = insiderTips.filter {
            let normalized = ExternalEventSupport.normalizeToken($0)
            return normalized.contains("exclusive")
                || normalized.contains("hard door")
                || normalized.contains("bottle service")
                || normalized.contains("guest list")
        }
        if let coverAnswer, !coverAnswer.isEmpty {
            doorNotes.append(coverAnswer)
        }
        if let waitAnswer, !waitAnswer.isEmpty {
            doorNotes.append(waitAnswer)
        }
        var updated = baseVenue
        updated.source = source
        updated.sourceType = .nightlifeAggregator
        if let headline, !headline.isEmpty {
            updated.name = headline
            updated.aliases = uniqueStrings(updated.aliases + [headline])
        }
        updated.imageURL = ExternalEventSupport.preferredImageURL(
            from: [updated.imageURL, ogImage] + galleryImages.map(Optional.some)
        )
        updated.openingHoursText = preferVenueText(
            primary: updated.openingHoursText,
            secondary: sanitizedVenueHoursText(openAnswer)
        )
        updated.ageMinimum = updated.ageMinimum ?? parseAgeMinimum(in: html)
        updated.doorPolicyText = preferVenueText(
            primary: updated.doorPolicyText,
            secondary: policy.doorPolicyText
                ?? ExternalEventSupport.shortened(uniqueStrings(doorNotes).joined(separator: " "), maxLength: 220)
        )
        updated.dressCodeText = preferVenueText(primary: updated.dressCodeText, secondary: dressCodeAnswer)
        updated.guestListAvailable = updated.guestListAvailable ?? guestListAvailable
        updated.bottleServiceAvailable = updated.bottleServiceAvailable ?? bottleServiceAvailable
        updated.coverPrice = ExternalEventSupport.richerNightlifePrice(primary: updated.coverPrice, secondary: coverPrice)
        updated.tableMinPrice = ExternalEventSupport.richerNightlifePrice(primary: updated.tableMinPrice, secondary: tableMinPrice)
        updated.entryPolicySummary = preferVenueText(primary: updated.entryPolicySummary, secondary: policy.entryPolicySummary)
        updated.womenEntryPolicyText = preferVenueText(
            primary: updated.womenEntryPolicyText,
            secondary: womenEntryExtract ?? policy.womenEntryPolicyText
        )
        updated.menEntryPolicyText = preferVenueText(
            primary: updated.menEntryPolicyText,
            secondary: menEntryExtract ?? policy.menEntryPolicyText
        )
        updated.exclusivityTierLabel = updated.exclusivityTierLabel ?? policy.exclusivityTierLabel
        updated.reservationURL = updated.reservationURL ?? firstRegexMatch(
            in: html,
            pattern: #"https://discotech\.me/[^"'\s<]+/(?:guestlist|bottle-service|tickets)/"#,
            options: [.caseInsensitive]
        ) ?? firstRegexMatch(
            in: html,
            pattern: #"https://(?:app|link)\.discotech\.me/[^"'\s<]+"#,
            options: [.caseInsensitive]
        ) ?? url.absoluteString
        updated.reservationProvider = updated.reservationProvider ?? reservationProviderName(for: updated.reservationURL)
        updated.sourceConfidence = max(updated.sourceConfidence ?? 0, 0.84)
        updated.sourceCoverageStatus = mergeCoverageStatus(updated.sourceCoverageStatus, "Discotech")
        updated.nightlifeSignalScore = max(updated.nightlifeSignalScore ?? 0, nightlifeSignalScore(html: normalizedHTML, tableMinPrice: updated.tableMinPrice, coverPrice: updated.coverPrice, guestListAvailable: updated.guestListAvailable, bottleServiceAvailable: updated.bottleServiceAvailable))
        updated.prestigeDemandScore = max(updated.prestigeDemandScore ?? 0, prestigeScore(html: normalizedHTML, celebrityText: [metaDescription, insiderTips.joined(separator: " "), drinksAnswer].compactMap { $0 }.joined(separator: " ")))
        updated.rawSourcePayload = mergePayload(
            updated.rawSourcePayload,
            extra: [
                "discotech_url": url.absoluteString,
                "discotech_description": metaDescription as Any,
                "discotech_image": ogImage as Any,
                "discotech_image_gallery": galleryImages as Any,
                "discotech_insider_tips": insiderTips,
                "discotech_cover_answer": coverAnswer as Any,
                "discotech_open_answer": openAnswer as Any,
                "discotech_dress_code": dressCodeAnswer as Any,
                "discotech_drinks_answer": drinksAnswer as Any,
                "discotech_music_answer": musicAnswer as Any,
                "discotech_best_nights": bestNightsAnswer as Any,
                "discotech_wait_answer": waitAnswer as Any,
                "discotech_entry_summary": policy.entryPolicySummary as Any,
                "discotech_women_entry": (womenEntryExtract ?? policy.womenEntryPolicyText) as Any,
                "discotech_men_entry": (menEntryExtract ?? policy.menEntryPolicyText) as Any,
                "discotech_exclusivity_tier": policy.exclusivityTierLabel as Any
            ]
        )
        return updated
    }

    private func parseClubbableVenuePage(
        html: String,
        url: URL,
        baseVenue: ExternalVenue,
        query: ExternalVenueQuery
    ) -> ExternalVenue? {
        let rawTitle = firstRegexMatch(in: html, pattern: #"<title>([^<]+)</title>"#, options: [.caseInsensitive])
        let title = normalizedClubbableVenueTitle(rawTitle, url: url, baseVenue: baseVenue)
        let titleToken = ExternalEventSupport.normalizeToken(title)
        let identityTokens = normalizedVenueTokens(for: baseVenue)
        let normalizedPath = ExternalEventSupport.normalizeToken(url.path.replacingOccurrences(of: "-", with: " "))
        guard identityTokens.contains(where: { titleToken.contains($0) || normalizedPath.contains($0) }) else {
            return nil
        }
        if shouldRejectOutOfMarketNightlifePage(
            candidateName: title ?? rawTitle ?? baseVenue.name,
            url: url,
            baseVenue: baseVenue,
            query: query
        ) {
            return nil
        }
        if let title, !isLikelyNightlifeVenueName(title) {
            return nil
        }

        let metaDescription = firstRegexMatch(
            in: html,
            pattern: #"<meta[^>]+(?:name|property)="description"[^>]+content="([^"]+)""#,
            options: [.caseInsensitive]
        ) ?? firstRegexMatch(
            in: html,
            pattern: #"<meta[^>]+property="og:description"[^>]+content="([^"]+)""#,
            options: [.caseInsensitive]
        )
        let ogImage = firstRegexMatch(
            in: html,
            pattern: #"<meta[^>]+property="og:image"[^>]+content="([^"]+)""#,
            options: [.caseInsensitive]
        )
        let galleryImages = extractClubbableGalleryImages(
            from: html,
            baseURL: url,
            venueTokens: identityTokens
        )
        let longDescription = firstRegexMatch(
            in: html,
            pattern: #"<div[^>]+long-description[^>]*><span>(.*?)</span></div>"#,
            options: [.caseInsensitive, .dotMatchesLineSeparators]
        )
        let normalizedMetaDescription = ExternalEventSupport.normalizeToken(metaDescription)
        let normalizedLongDescription = ExternalEventSupport.normalizeToken(longDescription)
        let blockedGenericTokens = [
            "all the best vip nightclubs in london",
            "all the promoters",
            "club managers owners",
            "create a group in the app",
            "get many offers of everything for free"
        ]
        if blockedGenericTokens.contains(where: normalizedLongDescription.contains)
            || (normalizedLongDescription.isEmpty && blockedGenericTokens.contains(where: normalizedMetaDescription.contains)) {
            return nil
        }
        let timeRange = firstRegexMatch(
            in: html,
            pattern: #"(\d{1,2}:\d{2}\s*[AP]M\s*-\s*\d{2}:\d{2}\s*[AP]M)"#,
            options: [.caseInsensitive]
        )
        let minimumAge = firstRegexMatch(
            in: html,
            pattern: #"Minimum Age:\s*(\d+)"#,
            options: [.caseInsensitive]
        ).flatMap(Int.init)
        let tableMinPrice = firstRegexMatch(
            in: html,
            pattern: #"Table prices from\s*\$([0-9,]+)"#,
            options: [.caseInsensitive]
        ).flatMap { ExternalEventSupport.parseCurrencyAmount("$\($0)") }
        let bookTablePath = firstRegexMatch(
            in: html,
            pattern: #"<a[^>]+href="([^"]*tableBooking[^"]*)"[^>]*>Book Table</a>"#,
            options: [.caseInsensitive]
        )
        let guestListPath = firstRegexMatch(
            in: html,
            pattern: #"<a[^>]+href="([^"]*guestList[^"]*)"[^>]*>Request Guest List</a>"#,
            options: [.caseInsensitive]
        )
        let guestListAvailable = guestListPath != nil
        let bottleServiceAvailable = bookTablePath != nil
        let womenEntryExtract = entrySnippet(
            in: html,
            matching: ["women", "ladies", "girls", "female"],
            maxMatches: 2
        )
        let menEntryExtract = entrySnippet(
            in: html,
            matching: ["men", "guys", "gentlemen", "male"],
            maxMatches: 2
        )
        let eventMetadata = clubbablePrimaryEventMetadata(
            from: html,
            url: url,
            query: query,
            fallbackTimeRange: timeRange
        )
        let normalizedDescription = ExternalEventSupport.normalizeToken([
            metaDescription,
            longDescription
        ].compactMap { $0 }.joined(separator: " "))

        var doorSummary: [String] = []
        if guestListPath != nil && bookTablePath != nil {
            doorSummary.append("Guest list and table booking structure.")
        } else if bookTablePath != nil {
            doorSummary.append("Table booking strongly favored.")
        }
        if let tableMinPrice {
            doorSummary.append("Tables from \(formatCurrency(tableMinPrice)).")
        }
        let policy = buildNightlifePolicySnapshot(
            texts: [
                metaDescription,
                longDescription,
                doorSummary.joined(separator: " "),
                womenEntryExtract,
                menEntryExtract,
                timeRange
            ],
            guestListAvailable: guestListAvailable,
            bottleServiceAvailable: bottleServiceAvailable,
            tableMinPrice: tableMinPrice,
            coverPrice: nil,
            sourceCoverageStatus: "Clubbable"
        )

        var updated = baseVenue
        updated.source = source
        updated.sourceType = .nightlifeAggregator
        if let title, !title.isEmpty {
            updated.name = title
            updated.aliases = uniqueStrings(updated.aliases + [title, rawTitle].compactMap { $0 })
        }
        updated.imageURL = ExternalEventSupport.preferredImageURL(
            from: [updated.imageURL, ogImage] + galleryImages.map(Optional.some)
        )
        updated.openingHoursText = preferVenueText(
            primary: updated.openingHoursText,
            secondary: sanitizedVenueHoursText(eventMetadata.scheduleText ?? timeRange)
        )
        updated.ageMinimum = updated.ageMinimum ?? minimumAge
        updated.addressLine1 = ExternalEventSupport.preferredAddressLine(
            primary: updated.addressLine1,
            primaryCity: updated.city,
            primaryState: updated.state,
            secondary: eventMetadata.addressLine1,
            secondaryCity: eventMetadata.city,
            secondaryState: eventMetadata.state
        )
        updated.city = preferVenueText(primary: updated.city, secondary: eventMetadata.city)
        updated.state = preferVenueText(primary: updated.state, secondary: eventMetadata.state)
        updated.postalCode = preferVenueText(primary: updated.postalCode, secondary: eventMetadata.postalCode)
        updated.doorPolicyText = preferVenueText(
            primary: updated.doorPolicyText,
            secondary: policy.doorPolicyText
                ?? ExternalEventSupport.shortened(uniqueStrings(doorSummary).joined(separator: " "), maxLength: 180)
        )
        updated.dressCodeText = preferVenueText(
            primary: updated.dressCodeText,
            secondary: normalizedDescription.contains("dress code") ? "Dress code enforced." : nil
        )
        updated.guestListAvailable = updated.guestListAvailable ?? guestListAvailable
        updated.bottleServiceAvailable = updated.bottleServiceAvailable ?? bottleServiceAvailable
        updated.tableMinPrice = ExternalEventSupport.richerNightlifePrice(primary: updated.tableMinPrice, secondary: tableMinPrice)
        updated.entryPolicySummary = preferVenueText(primary: updated.entryPolicySummary, secondary: policy.entryPolicySummary)
        updated.womenEntryPolicyText = preferVenueText(
            primary: updated.womenEntryPolicyText,
            secondary: womenEntryExtract ?? policy.womenEntryPolicyText
        )
        updated.menEntryPolicyText = preferVenueText(
            primary: updated.menEntryPolicyText,
            secondary: menEntryExtract ?? policy.menEntryPolicyText
        )
        updated.exclusivityTierLabel = updated.exclusivityTierLabel ?? policy.exclusivityTierLabel
        updated.reservationURL = updated.reservationURL
            ?? absoluteURL(path: bookTablePath ?? guestListPath, base: url)
        updated.reservationProvider = updated.reservationProvider ?? "Clubbable"
        updated.sourceConfidence = max(updated.sourceConfidence ?? 0, 0.83)
        updated.sourceCoverageStatus = mergeCoverageStatus(updated.sourceCoverageStatus, "Clubbable")
        updated.nightlifeSignalScore = max(updated.nightlifeSignalScore ?? 0, nightlifeSignalScore(html: normalizedDescription, tableMinPrice: tableMinPrice, coverPrice: updated.coverPrice, guestListAvailable: updated.guestListAvailable, bottleServiceAvailable: updated.bottleServiceAvailable))
        updated.prestigeDemandScore = max(updated.prestigeDemandScore ?? 0, prestigeScore(html: normalizedDescription, celebrityText: [metaDescription, longDescription].compactMap { $0 }.joined(separator: " ")))
        updated.rawSourcePayload = mergePayload(
            updated.rawSourcePayload,
            extra: [
                "clubbable_url": url.absoluteString,
                "clubbable_description": ExternalEventSupport.plainText(longDescription ?? metaDescription) as Any,
                "clubbable_image": ogImage as Any,
                "clubbable_image_gallery": galleryImages as Any,
                "clubbable_time_range": eventMetadata.scheduleText ?? timeRange as Any,
                "clubbable_schedule_display": eventMetadata.scheduleText ?? timeRange as Any,
                "clubbable_start_local": eventMetadata.startLocal as Any,
                "clubbable_end_local": eventMetadata.endLocal as Any,
                "clubbable_address_line_1": eventMetadata.addressLine1 as Any,
                "clubbable_city": eventMetadata.city as Any,
                "clubbable_state": eventMetadata.state as Any,
                "clubbable_postal_code": eventMetadata.postalCode as Any,
                "clubbable_full_address": eventMetadata.fullAddress as Any,
                "clubbable_table_min": tableMinPrice as Any,
                "clubbable_minimum_age": minimumAge as Any,
                "clubbable_guest_list": guestListPath as Any,
                "clubbable_table_link": bookTablePath as Any,
                "clubbable_entry_summary": policy.entryPolicySummary as Any,
                "clubbable_women_entry": (womenEntryExtract ?? policy.womenEntryPolicyText) as Any,
                "clubbable_men_entry": (menEntryExtract ?? policy.menEntryPolicyText) as Any,
                "clubbable_exclusivity_tier": policy.exclusivityTierLabel as Any
            ]
        )
        return updated
    }

    private func normalizedClubbableVenueTitle(
        _ rawTitle: String?,
        url: URL,
        baseVenue: ExternalVenue
    ) -> String? {
        let cleanedRawTitle = ExternalEventSupport.plainText(rawTitle)?
            .replacingOccurrences(of: "&amp;", with: "&")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedRawTitle = ExternalEventSupport.normalizeToken(cleanedRawTitle)
        let slugTitle = humanizedVenueName(fromSlug: url.lastPathComponent)
        let normalizedSlugTitle = ExternalEventSupport.normalizeToken(slugTitle)

        if normalizedRawTitle.contains("guest list")
            || normalizedRawTitle.contains("table bookings")
            || normalizedRawTitle.contains("vip table")
        {
            if !normalizedSlugTitle.isEmpty {
                return slugTitle
            }
        }

        if let cleanedRawTitle, !cleanedRawTitle.isEmpty {
            return cleanedRawTitle
        }

        if !normalizedSlugTitle.isEmpty {
            return slugTitle
        }

        return ExternalEventSupport.plainText(baseVenue.name) ?? baseVenue.name
    }

    private func extractDiscotechGalleryImages(
        from html: String,
        baseURL: URL,
        venueTokens: [String]
    ) -> [String] {
        let matches = allRegexMatches(
            in: html,
            pattern: #"<img[^>]+src="([^"]+wp-content/uploads/[^"]+\.(?:jpe?g|png|webp)[^"]*)"[^>]*>"#,
            groupCount: 1,
            options: [.caseInsensitive]
        )
        .compactMap(\.first)
        .compactMap { absoluteURL(path: $0, base: baseURL) }

        return filteredVenueGalleryImages(
            from: matches,
            venueTokens: venueTokens,
            blockedTokens: ["logo", "structured-data-logo", "newsfeed", "resize=36", "resize=80", "resize=180"]
        )
    }

    private func extractClubbableGalleryImages(
        from html: String,
        baseURL: URL,
        venueTokens: [String]
    ) -> [String] {
        let matches = (
            allRegexMatches(
                in: html,
                pattern: #"(?:data-src|data-thumb|content)="([^"]+clubbable\.blob\.core\.windows\.net/medias/[^"]+)""#,
                groupCount: 1,
                options: [.caseInsensitive]
            )
            + allRegexMatches(
                in: html,
                pattern: #""image"\s*:\s*\[(.*?)\]"#,
                groupCount: 1,
                options: [.caseInsensitive, .dotMatchesLineSeparators]
            )
        )
        .flatMap { groups -> [String] in
            guard let first = groups.first else { return [] }
            if first.contains("clubbable.blob.core.windows.net/medias/") {
                return [first]
            }
            return allRegexMatches(
                in: first,
                pattern: #""(https://clubbable\.blob\.core\.windows\.net/medias/[^"]+)""#,
                groupCount: 1,
                options: [.caseInsensitive]
            ).compactMap(\.first)
        }
        .compactMap { absoluteURL(path: $0, base: baseURL) }

        return filteredVenueGalleryImages(
            from: matches,
            venueTokens: venueTokens,
            blockedTokens: ["placeholder", "logo", "youtube", "_200"]
        )
    }

    private func filteredVenueGalleryImages(
        from candidates: [String],
        venueTokens: [String],
        blockedTokens: [String]
    ) -> [String] {
        let normalizedVenueTokens = venueTokens
            .flatMap { token in
                let normalized = ExternalEventSupport.normalizeToken(token)
                return [normalized, normalized.replacingOccurrences(of: " ", with: "")]
            }
            .filter { !$0.isEmpty }

        var seen = Set<String>()
        var results: [String] = []
        for candidate in candidates {
            let decoded = candidate.removingPercentEncoding ?? candidate
            let normalized = ExternalEventSupport.normalizeToken(decoded)
            guard !blockedTokens.contains(where: normalized.contains) else { continue }
            guard normalizedVenueTokens.isEmpty || normalizedVenueTokens.contains(where: normalized.contains) else { continue }
            guard !seen.contains(candidate) else { continue }
            seen.insert(candidate)
            results.append(candidate)
            if results.count == 8 {
                break
            }
        }
        return results
    }

    private func clubbablePrimaryEventMetadata(
        from html: String,
        url: URL,
        query: ExternalVenueQuery,
        fallbackTimeRange: String?
    ) -> (
        startLocal: String?,
        endLocal: String?,
        scheduleText: String?,
        addressLine1: String?,
        city: String?,
        state: String?,
        postalCode: String?,
        fullAddress: String?
    ) {
        let timezoneID = ExternalEventSupport.timeZoneIdentifier(
            latitude: query.latitude,
            longitude: query.longitude
        )

        let startMatches = allRegexMatches(
            in: html,
            pattern: #""startDate"\s*:\s*"([^"]+)""#,
            groupCount: 1,
            options: [.caseInsensitive]
        )
        .compactMap(\.first)

        let endMatches = allRegexMatches(
            in: html,
            pattern: #""endDate"\s*:\s*"([^"]+)""#,
            groupCount: 1,
            options: [.caseInsensitive]
        )
        .compactMap(\.first)

        let paired = zip(startMatches, endMatches).map { (start: $0.0, end: $0.1) }
        let selected = preferredUpcomingClubbablePair(
            from: paired,
            timezoneID: timezoneID
        )

        let streetAddress = firstRegexMatch(
            in: html,
            pattern: #""streetAddress"\s*:\s*"([^"]+)""#,
            options: [.caseInsensitive, .dotMatchesLineSeparators]
        )
        let rawLocality = firstRegexMatch(
            in: html,
            pattern: #""addressLocality"\s*:\s*"([^"]+)""#,
            options: [.caseInsensitive, .dotMatchesLineSeparators]
        )
        let state = firstRegexMatch(
            in: html,
            pattern: #""addressRegion"\s*:\s*"([^"]+)""#,
            options: [.caseInsensitive]
        )
        let postalCode = firstRegexMatch(
            in: html,
            pattern: #""postalCode"\s*:\s*"([^"]+)""#,
            options: [.caseInsensitive]
        )

        let openMapAddress = firstRegexMatch(
            in: html,
            pattern: #"<a[^>]+href="https://maps\.google\.com/\?q=([^"]+)"[^>]*class="open-map-link""#,
            options: [.caseInsensitive, .dotMatchesLineSeparators]
        )
        let headingAddress = firstRegexMatch(
            in: html,
            pattern: #"<h5>(.*?)</h5>\s*<a[^>]+class="open-map-link""#,
            options: [.caseInsensitive, .dotMatchesLineSeparators]
        )

        let parsedAddress = parsedClubbableAddress(
            streetAddress: streetAddress,
            rawLocality: rawLocality,
            rawRegion: state,
            postalCode: postalCode,
            openMapAddress: openMapAddress,
            headingAddress: headingAddress
        )

        let hoursFallback = clubbableOpeningHoursFallback(
            from: html,
            timezoneID: timezoneID
        )

        let scheduleText = firstRegexMatch(
            in: html,
            pattern: #"(\d{1,2}:\d{2}\s*[AP]M\s*-\s*\d{2}:\d{2}\s*[AP]M)"#,
            options: [.caseInsensitive]
        ) ?? fallbackTimeRange ?? hoursFallback?.scheduleText

        return (
            startLocal: selected?.startLocal ?? hoursFallback?.startLocal,
            endLocal: selected?.endLocal ?? hoursFallback?.endLocal,
            scheduleText: scheduleText,
            addressLine1: parsedAddress.addressLine1,
            city: parsedAddress.city,
            state: parsedAddress.state,
            postalCode: parsedAddress.postalCode,
            fullAddress: parsedAddress.fullAddress
        )
    }

    private func parsedClubbableAddress(
        streetAddress: String?,
        rawLocality: String?,
        rawRegion: String?,
        postalCode: String?,
        openMapAddress: String?,
        headingAddress: String?
    ) -> (
        addressLine1: String?,
        city: String?,
        state: String?,
        postalCode: String?,
        fullAddress: String?
    ) {
        if let parsedInlineLocality = parseClubbableInlineAddress(
            rawLocality,
            fallbackRegion: rawRegion,
            fallbackPostalCode: postalCode
        ) {
            return parsedInlineLocality
        }

        let candidates = [openMapAddress, headingAddress, streetAddress, rawLocality]
            .compactMap { $0 }
            .map(decodeClubbableAddressCandidate(_:))
            .filter { !$0.isEmpty }

        for candidate in candidates {
            if let parsed = parseLooseVenueAddress(
                candidate,
                fallbackRegion: rawRegion,
                fallbackPostalCode: postalCode
            ) {
                return parsed
            }
        }

        let parsedCity = rawLocality?
            .components(separatedBy: ",")
            .first?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let parsedState = rawRegion
            ?? rawLocality?
                .components(separatedBy: ",")
                .dropFirst()
                .first?
                .trimmingCharacters(in: .whitespacesAndNewlines)

        let fullAddress = [
            streetAddress?.trimmingCharacters(in: .whitespacesAndNewlines),
            parsedCity,
            parsedState,
            postalCode?.trimmingCharacters(in: .whitespacesAndNewlines)
        ]
        .compactMap { value -> String? in
            guard let value, !value.isEmpty else { return nil }
            return ExternalEventSupport.plainText(value)
        }
        .joined(separator: ", ")

        return (
            addressLine1: ExternalEventSupport.plainText(streetAddress),
            city: ExternalEventSupport.plainText(parsedCity),
            state: ExternalEventSupport.plainText(parsedState),
            postalCode: ExternalEventSupport.plainText(postalCode),
            fullAddress: fullAddress.isEmpty ? nil : fullAddress
        )
    }

    private func parseClubbableInlineAddress(
        _ rawValue: String?,
        fallbackRegion: String?,
        fallbackPostalCode: String?
    ) -> (
        addressLine1: String?,
        city: String?,
        state: String?,
        postalCode: String?,
        fullAddress: String?
    )? {
        guard let rawValue = ExternalEventSupport.plainText(rawValue), !rawValue.isEmpty else {
            return nil
        }

        guard let streetRange = rawValue.range(
            of: #"\b\d{1,6}\s+[A-Za-z0-9.'#\-]+\b(?:\s+[A-Za-z0-9.'#\-]+){0,8}\s+(?:ave|avenue|blvd|boulevard|st|street|rd|road|dr|drive|ln|lane|way|pkwy|parkway|pl|place|ct|court|ter|terrace|cir|circle|hwy|highway)\b\.?"#,
            options: [.regularExpression, .caseInsensitive]
        ) else {
            return nil
        }

        let street = String(rawValue[streetRange]).trimmingCharacters(in: .whitespacesAndNewlines)
        let localitySeed = rawValue[..<streetRange.lowerBound]
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .replacingOccurrences(of: ", ,", with: ",")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        let locality = parseLocalityLine(
            localitySeed,
            fallbackRegion: fallbackRegion,
            fallbackPostalCode: fallbackPostalCode
        )

        let fullAddress = [
            street,
            locality.city,
            locality.state,
            locality.postalCode
        ]
        .compactMap { $0 }
        .filter { !$0.isEmpty }
        .joined(separator: ", ")

        return (
            addressLine1: street,
            city: locality.city,
            state: locality.state,
            postalCode: locality.postalCode,
            fullAddress: fullAddress.isEmpty ? nil : fullAddress
        )
    }

    private func decodeClubbableAddressCandidate(_ value: String) -> String {
        let decoded = value.removingPercentEncoding ?? value
        return decoded
            .replacingOccurrences(of: "&amp;", with: "&")
            .replacingOccurrences(of: "<br>", with: "\n")
            .replacingOccurrences(of: "<br/>", with: "\n")
            .replacingOccurrences(of: "<br />", with: "\n")
    }

    private func parseLooseVenueAddress(
        _ rawValue: String,
        fallbackRegion: String?,
        fallbackPostalCode: String?
    ) -> (
        addressLine1: String?,
        city: String?,
        state: String?,
        postalCode: String?,
        fullAddress: String?
    )? {
        let normalizedLines = rawValue
            .components(separatedBy: CharacterSet.newlines)
            .map { ExternalEventSupport.plainText($0) }
            .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        if normalizedLines.count >= 2 {
            let streetCandidate = normalizedLines.first(where: containsStreetNumber(_:))
            let localityCandidate = normalizedLines.first(where: { !containsStreetNumber($0) })
            if let streetCandidate, let localityCandidate {
                let localityParts = localityCandidate
                    .components(separatedBy: ",")
                    .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                    .filter { !$0.isEmpty }
                let parsedLocality = parseLocalityLine(
                    localityParts.joined(separator: ", "),
                    fallbackRegion: fallbackRegion,
                    fallbackPostalCode: fallbackPostalCode
                )
                let fullAddress = [
                    streetCandidate,
                    parsedLocality.city,
                    parsedLocality.state,
                    parsedLocality.postalCode
                ]
                .compactMap { $0 }
                .filter { !$0.isEmpty }
                .joined(separator: ", ")
                return (
                    addressLine1: streetCandidate,
                    city: parsedLocality.city,
                    state: parsedLocality.state,
                    postalCode: parsedLocality.postalCode,
                    fullAddress: fullAddress.isEmpty ? nil : fullAddress
                )
            }
        }

        let cleaned = ExternalEventSupport.plainText(rawValue)?
            .replacingOccurrences(of: "United States", with: "")
            .replacingOccurrences(of: "USA", with: "")
            .replacingOccurrences(of: "  ", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !cleaned.isEmpty else { return nil }

        let parts = cleaned
            .components(separatedBy: ",")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        guard !parts.isEmpty else { return nil }

        if containsStreetNumber(parts[0]) {
            let locality = parseLocalityLine(
                parts.dropFirst().joined(separator: ", "),
                fallbackRegion: fallbackRegion,
                fallbackPostalCode: fallbackPostalCode
            )
            let fullAddress = [
                parts[0],
                locality.city,
                locality.state,
                locality.postalCode
            ]
            .compactMap { $0 }
            .filter { !$0.isEmpty }
            .joined(separator: ", ")
            return (
                addressLine1: parts[0],
                city: locality.city,
                state: locality.state,
                postalCode: locality.postalCode,
                fullAddress: fullAddress.isEmpty ? nil : fullAddress
            )
        }

        return nil
    }

    private func containsStreetNumber(_ value: String) -> Bool {
        value.rangeOfCharacter(from: .decimalDigits) != nil
    }

    private func parseLocalityLine(
        _ rawValue: String,
        fallbackRegion: String?,
        fallbackPostalCode: String?
    ) -> (
        city: String?,
        state: String?,
        postalCode: String?
    ) {
        let cleaned = ExternalEventSupport.plainText(rawValue)?
            .replacingOccurrences(of: "United States", with: "")
            .replacingOccurrences(of: "USA", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !cleaned.isEmpty else {
            return (
                city: nil,
                state: normalizedStateLabel(fallbackRegion),
                postalCode: ExternalEventSupport.plainText(fallbackPostalCode)
            )
        }

        let parts = cleaned
            .components(separatedBy: ",")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        let city = parts.first(where: { !containsStreetNumber($0) && ExternalEventSupport.normalizeStateToken($0).count != 2 })

        let statePostalSource = parts.dropFirst().joined(separator: " ")
        let postal = firstRegexMatch(
            in: statePostalSource,
            pattern: #"(\d{5}(?:-\d{4})?)"#,
            options: [.caseInsensitive]
        ) ?? ExternalEventSupport.plainText(fallbackPostalCode)

        let stateMatch = firstRegexMatch(
            in: statePostalSource,
            pattern: #"\b([A-Z]{2})\b"#,
            options: [.caseInsensitive]
        )
        let normalizedFallbackState = normalizedStateLabel(fallbackRegion)
        let state = stateMatch?.uppercased() ?? normalizedFallbackState

        return (
            city: city ?? inferredCity(from: cleaned),
            state: state,
            postalCode: postal
        )
    }

    private func inferredCity(from value: String) -> String? {
        let parts = value
            .components(separatedBy: ",")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        guard parts.count >= 2 else { return nil }
        return parts[1]
    }

    private func normalizedStateLabel(_ value: String?) -> String? {
        guard let value = ExternalEventSupport.plainText(value), !value.isEmpty else { return nil }
        let normalized = ExternalEventSupport.normalizeStateToken(value)
        guard normalized.count == 2 else { return nil }
        return normalized.uppercased()
    }

    private func clubbableOpeningHoursFallback(
        from html: String,
        timezoneID: String
    ) -> (
        startLocal: String,
        endLocal: String,
        scheduleText: String
    )? {
        let specifications = allRegexMatches(
            in: html,
            pattern: #""dayOfWeek"\s*:\s*"([^"]+)".*?"opens"\s*:\s*"([^"]+)".*?"closes"\s*:\s*"([^"]+)""#,
            groupCount: 3,
            options: [.caseInsensitive, .dotMatchesLineSeparators]
        )
        guard !specifications.isEmpty else {
            return nil
        }

        let timezone = TimeZone(identifier: timezoneID) ?? .current
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timezone
        let now = Date()
        let currentHour = calendar.component(.hour, from: now)
        let baseDate = currentHour < 5
            ? calendar.date(byAdding: .day, value: -1, to: now) ?? now
            : now

        let weekdayFormatter = DateFormatter()
        weekdayFormatter.locale = Locale(identifier: "en_US_POSIX")
        weekdayFormatter.timeZone = timezone
        weekdayFormatter.dateFormat = "EEEE"
        let preferredDay = weekdayFormatter.string(from: baseDate)

        let matchedSpecification = specifications.first { specification in
            guard let day = specification.first else { return false }
            return ExternalEventSupport.normalizeToken(day).contains(ExternalEventSupport.normalizeToken(preferredDay))
        }
        guard let matchedSpecification,
              matchedSpecification.count >= 3,
              let opens = ExternalEventSupport.plainText(matchedSpecification[1]),
              let closes = ExternalEventSupport.plainText(matchedSpecification[2]),
              let startDate = clubbableDate(baseDate: baseDate, timeString: opens, timezone: timezone) else {
            return nil
        }

        let rawEndDate = clubbableDate(baseDate: baseDate, timeString: closes, timezone: timezone)
        let endDate: Date?
        if let rawEndDate {
            endDate = rawEndDate <= startDate
                ? calendar.date(byAdding: .day, value: 1, to: rawEndDate)
                : rawEndDate
        } else {
            endDate = nil
        }

        return (
            startLocal: normalizedClubbableLocalDateString(from: startDate, timezone: timezone),
            endLocal: endDate.map { normalizedClubbableLocalDateString(from: $0, timezone: timezone) } ?? normalizedClubbableLocalDateString(from: startDate, timezone: timezone),
            scheduleText: clubbableDisplayTimeRange(start: startDate, end: endDate, timezone: timezone)
        )
    }

    private func clubbableDate(
        baseDate: Date,
        timeString: String,
        timezone: TimeZone
    ) -> Date? {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = timezone
        formatter.dateFormat = "HH:mm"
        guard let time = formatter.date(from: timeString) else { return nil }

        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timezone
        let baseComponents = calendar.dateComponents([.year, .month, .day], from: baseDate)
        let timeComponents = calendar.dateComponents([.hour, .minute], from: time)
        var merged = DateComponents()
        merged.year = baseComponents.year
        merged.month = baseComponents.month
        merged.day = baseComponents.day
        merged.hour = timeComponents.hour
        merged.minute = timeComponents.minute
        return calendar.date(from: merged)
    }

    private func normalizedClubbableLocalDateString(from date: Date, timezone: TimeZone) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = timezone
        formatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ss"
        return formatter.string(from: date)
    }

    private func clubbableDisplayTimeRange(
        start: Date,
        end: Date?,
        timezone: TimeZone
    ) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = timezone
        formatter.dateFormat = "h:mm a"
        let startText = formatter.string(from: start).uppercased()
        let endText = end.map { formatter.string(from: $0).uppercased() } ?? startText
        return "\(startText) - \(endText)"
    }

    private func preferredUpcomingClubbablePair(
        from pairs: [(start: String, end: String)],
        timezoneID: String
    ) -> (startLocal: String, endLocal: String)? {
        let timezone = TimeZone(identifier: timezoneID) ?? .current
        let now = Date()

        let parsedPairs = pairs.compactMap { pair -> (startDate: Date, startLocal: String, endLocal: String)? in
            guard let startDate = parseClubbableLocalDate(pair.start, timezone: timezone) else { return nil }
            guard let normalizedStart = normalizedClubbableLocalDateString(pair.start, timezone: timezone) else {
                return nil
            }
            let normalizedEnd = normalizedClubbableLocalDateString(pair.end, timezone: timezone)
            return (
                startDate: startDate,
                startLocal: normalizedStart,
                endLocal: normalizedEnd ?? normalizedStart
            )
        }

        if let nearestUpcoming = parsedPairs
            .filter({ $0.startDate >= now.addingTimeInterval(-6 * 60 * 60) })
            .sorted(by: { $0.startDate < $1.startDate })
            .first {
            return (nearestUpcoming.startLocal, nearestUpcoming.endLocal)
        }

        if let earliest = parsedPairs.sorted(by: { $0.startDate < $1.startDate }).first {
            return (earliest.startLocal, earliest.endLocal)
        }

        return nil
    }

    private func parseClubbableLocalDate(_ value: String?, timezone: TimeZone) -> Date? {
        guard let value = ExternalEventSupport.plainText(value), !value.isEmpty else { return nil }
        let formats = [
            "yyyy-M-d'T'HH:mm:ss",
            "yyyy-M-d'T'HH:mm",
            "yyyy-MM-dd'T'HH:mm:ss",
            "yyyy-MM-dd'T'HH:mm"
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

    private func normalizedClubbableLocalDateString(_ value: String?, timezone: TimeZone) -> String? {
        guard let date = parseClubbableLocalDate(value, timezone: timezone) else { return nil }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = timezone
        formatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ss"
        return formatter.string(from: date)
    }

    private func shouldRejectOutOfMarketNightlifePage(
        candidateName: String?,
        url: URL,
        baseVenue: ExternalVenue,
        query: ExternalVenueQuery
    ) -> Bool {
        let allowedTokens = allowedNightlifeLocationTokens(for: query)
        let candidates: [String] = [
            candidateName,
            humanizedVenueName(fromSlug: url.lastPathComponent)
        ]
        .compactMap { value -> String? in
            guard let value, !value.isEmpty else { return nil }
            return value
        }

        for candidate in candidates {
            guard let suffixTokens = suffixTokensForVenueVariant(candidate, baseVenue: baseVenue),
                  !suffixTokens.isEmpty else {
                continue
            }
            let disallowed = suffixTokens.filter { token in
                !allowedTokens.contains(token) && !isGenericNightlifeDescriptorToken(token)
            }
            if !disallowed.isEmpty {
                return true
            }
        }

        return false
    }

    private func suffixTokensForVenueVariant(
        _ candidateName: String,
        baseVenue: ExternalVenue
    ) -> [String]? {
        let normalizedCandidate = ExternalEventSupport.normalizeToken(candidateName)
        guard !normalizedCandidate.isEmpty else { return nil }

        let aliases = uniqueStrings([baseVenue.name] + baseVenue.aliases + venueSearchTerms(for: baseVenue))
            .map(ExternalEventSupport.normalizeToken)
            .filter { !$0.isEmpty }
            .sorted { $0.count > $1.count }

        for alias in aliases {
            if normalizedCandidate == alias {
                return []
            }

            if normalizedCandidate.hasPrefix(alias + " ") {
                let remainder = String(normalizedCandidate.dropFirst(alias.count + 1))
                return trimmedVenueVariantTokens(from: remainder)
            }

            if normalizedCandidate.hasPrefix(alias + " at ") {
                let remainder = String(normalizedCandidate.dropFirst(alias.count + 4))
                return trimmedVenueVariantTokens(from: remainder)
            }

            if normalizedCandidate.hasPrefix(alias + " in ") {
                let remainder = String(normalizedCandidate.dropFirst(alias.count + 4))
                return trimmedVenueVariantTokens(from: remainder)
            }

            if normalizedCandidate.hasSuffix(" at " + alias) {
                let remainder = String(normalizedCandidate.dropLast(alias.count + 4))
                return trimmedVenueVariantTokens(from: remainder)
            }

            if normalizedCandidate.hasSuffix(" in " + alias) {
                let remainder = String(normalizedCandidate.dropLast(alias.count + 4))
                return trimmedVenueVariantTokens(from: remainder)
            }

            if normalizedCandidate.hasSuffix(" " + alias) {
                let remainder = String(normalizedCandidate.dropLast(alias.count + 1))
                return trimmedVenueVariantTokens(from: remainder)
            }
        }

        return nil
    }

    private func trimmedVenueVariantTokens(from remainder: String) -> [String] {
        let stopTokens = Set([
            "guest", "list", "guestlist", "table", "tables", "booking", "bookings",
            "vip", "promoter", "promoters", "price", "prices", "dress", "code",
            "photo", "photos", "info", "offers", "free", "amp", "and"
        ])
        let tokens = remainder
            .split(separator: " ")
            .map(String.init)
        if let stopIndex = tokens.firstIndex(where: { stopTokens.contains($0) }) {
            return Array(tokens[..<stopIndex])
        }
        return tokens
    }

    private func allowedNightlifeLocationTokens(
        for query: ExternalVenueQuery
    ) -> Set<String> {
        var tokens = Set<String>()

        let rawValues = discotechMarketCandidates(for: query)
            + [query.city, query.displayName, query.state]
                .compactMap { $0 }

        for raw in rawValues {
            let normalized = ExternalEventSupport.normalizeToken(raw)
            guard !normalized.isEmpty else { continue }
            tokens.insert(normalized)
            normalized
                .split(separator: " ")
                .map(String.init)
                .forEach { tokens.insert($0) }
            if let acronym = nightlifeLocationAcronym(for: normalized) {
                tokens.insert(acronym)
            }
        }

        let stateToken = ExternalEventSupport.normalizeStateToken(query.state)
        if !stateToken.isEmpty {
            tokens.insert(stateToken)
        }

        return tokens
    }

    private func nightlifeLocationAcronym(for normalizedValue: String) -> String? {
        let words = normalizedValue
            .split(separator: " ")
            .map(String.init)
            .filter { !$0.isEmpty }
        guard words.count >= 2 else { return nil }
        let acronym = words.map { String($0.prefix(1)) }.joined()
        return acronym.count >= 2 ? acronym : nil
    }

    private func isGenericNightlifeDescriptorToken(_ token: String) -> Bool {
        [
            "club",
            "nightclub",
            "night",
            "lounge",
            "rooftop",
            "bar",
            "restaurant",
            "saturdays",
            "saturday",
            "fridays",
            "friday",
            "sundays",
            "sunday",
            "la",
            "nyc"
        ].contains(token)
    }

    private func isLikelyNightlifeVenueName(_ candidateName: String) -> Bool {
        let normalized = ExternalEventSupport.normalizeToken(candidateName)
        guard !normalized.isEmpty else { return false }
        let blockedPhrases = [
            "promo code",
            "discount",
            "grand opening",
            "what are the best",
            "best nightclubs",
            "hottest clubs",
            "right now",
            "other festivals nearby",
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
            "ticket giveaway",
            "guest list deals",
            "this thursday",
            "this friday",
            "this saturday",
            "this sunday"
        ]
        return !blockedPhrases.contains(where: normalized.contains)
    }

    private func sanitizedNightlifeMentionName(from rawMention: String) -> String? {
        let normalized = ExternalEventSupport.normalizeToken(rawMention)
        guard !normalized.isEmpty, isLikelyNightlifeVenueName(normalized) else {
            return nil
        }

        let blockedTokens = [
            "probably",
            "right",
            "other",
            "nearby",
            "drive",
            "festival",
            "festivals",
            "lineup",
            "promo",
            "discount",
            "opening",
            "thursday",
            "friday",
            "saturday",
            "sunday"
        ]
        guard !blockedTokens.contains(where: normalized.contains) else {
            return nil
        }

        let words = normalized.split(separator: " ").map(String.init)
        guard (1...5).contains(words.count) else {
            return nil
        }

        let displayName = humanizedVenueName(fromSlug: slugify(normalized))
        return displayName.isEmpty ? nil : displayName
    }

    private func preferVenueText(primary: String?, secondary: String?) -> String? {
        guard let secondary, !secondary.isEmpty else { return primary }
        guard let primary, !primary.isEmpty else { return secondary }

        let normalizedPrimary = ExternalEventSupport.normalizeToken(primary)
        let normalizedSecondary = ExternalEventSupport.normalizeToken(secondary)
        let primaryIsMarketNote = normalizedPrimary.contains("highlighted in discotech s market guide")
        let secondaryIsMarketNote = normalizedSecondary.contains("highlighted in discotech s market guide")

        if primaryIsMarketNote && !secondaryIsMarketNote {
            return secondary
        }
        let primaryScore = nightlifeTextQualityScore(primary)
        let secondaryScore = nightlifeTextQualityScore(secondary)
        if secondaryScore >= primaryScore + 2 {
            return secondary
        }
        if primaryScore >= secondaryScore + 2 {
            return primary
        }
        if secondary.count > primary.count + 24 {
            return secondary
        }
        return primary
    }

    private func clubbableCandidateURLs(
        for venue: ExternalVenue,
        query: ExternalVenueQuery
    ) -> [URL] {
        let marketCandidates = clubbableMarketCandidates(for: venue, query: query)
        var urls: [URL] = []
        var seen = Set<String>()

        for searchTerm in venueSearchTerms(for: venue) {
            let venueSlug = titleSlug(searchTerm)
            for market in marketCandidates {
                guard let url = URL(string: "https://www.clubbable.com/\(market)/\(venueSlug)") else { continue }
                guard !seen.contains(url.absoluteString) else { continue }
                seen.insert(url.absoluteString)
                urls.append(url)
            }
        }

        return urls
    }

    private func clubbableMarketCandidates(
        for venue: ExternalVenue,
        query: ExternalVenueQuery
    ) -> [String] {
        var candidates: [String] = []
        let state = ExternalEventSupport.normalizeStateToken(venue.state ?? query.state)
        let cityTokens = [
            venue.city,
            query.city,
            query.displayName
        ]
            .compactMap { $0 }
            .map(ExternalEventSupport.normalizeToken)

        func append(_ value: String?) {
            guard let value, !value.isEmpty else { return }
            let slug = titleSlug(value)
            guard !slug.isEmpty, !candidates.contains(slug) else { return }
            candidates.append(slug)
        }

        let preferredMetro = preferredClubbableMetroMarket(state: state, cityTokens: cityTokens)
        append(preferredMetro)

        let skipLocalityVariants = preferredMetro != nil
        for token in cityTokens {
            if skipLocalityVariants && isLocalityCoveredByPreferredClubbableMetro(token, state: state) {
                continue
            }
            append(token)
        }

        return candidates
    }

    private func clubbableMarketCandidates(for query: ExternalVenueQuery) -> [String] {
        var candidates: [String] = []
        let state = ExternalEventSupport.normalizeStateToken(query.state)
        let cityTokens = [query.city, query.displayName]
            .compactMap { $0 }
            .map(ExternalEventSupport.normalizeToken)

        func append(_ value: String?) {
            guard let value, !value.isEmpty else { return }
            let slug = titleSlug(value)
            guard !slug.isEmpty, !candidates.contains(slug) else { return }
            candidates.append(slug)
        }

        let preferredMetro = preferredClubbableMetroMarket(state: state, cityTokens: cityTokens)
        append(preferredMetro)

        let skipLocalityVariants = preferredMetro != nil
        for token in cityTokens {
            if skipLocalityVariants && isLocalityCoveredByPreferredClubbableMetro(token, state: state) {
                continue
            }
            append(token)
        }

        return candidates
    }

    private func preferredClubbableMetroMarket(state: String, cityTokens: [String]) -> String? {
        if state == "ca", cityTokens.contains(where: ExternalEventSupport.isLosAngelesMetroToken) {
            return "Los Angeles"
        }
        if state == "ny",
           cityTokens.contains(where: { ["new york", "new york city", "brooklyn", "manhattan", "queens"].contains($0) }) {
            return "New York"
        }
        if state == "fl",
           cityTokens.contains(where: { ["miami", "miami beach", "south beach"].contains($0) }) {
            return "Miami"
        }
        if state == "nv",
           cityTokens.contains(where: { ["las vegas", "paradise"].contains($0) }) {
            return "Las Vegas"
        }
        if state == "il", cityTokens.contains("chicago") {
            return "Chicago"
        }
        if state == "tx",
           let metro = cityTokens.first(where: { ["dallas", "austin", "houston"].contains($0) }) {
            return metro
        }
        return nil
    }

    private func isLocalityCoveredByPreferredClubbableMetro(_ token: String, state: String) -> Bool {
        if state == "ca" {
            return ExternalEventSupport.isLosAngelesMetroToken(token)
        }
        if state == "ny" {
            return ["new york", "new york city", "brooklyn", "manhattan", "queens"].contains(token)
        }
        if state == "fl" {
            return ["miami", "miami beach", "south beach"].contains(token)
        }
        if state == "nv" {
            return ["las vegas", "paradise"].contains(token)
        }
        if state == "il" {
            return token == "chicago"
        }
        if state == "tx" {
            return ["dallas", "austin", "houston"].contains(token)
        }
        return false
    }

    private func extractDiscotechListSection(html: String, title: String) -> [String] {
        guard let block = firstRegexMatch(
            in: html,
            pattern: "\(NSRegularExpression.escapedPattern(for: title)).*?<ul>(.*?)</ul>",
            options: [.caseInsensitive, .dotMatchesLineSeparators]
        ) else {
            return []
        }

        return allRegexMatches(
            in: block,
            pattern: #"<li[^>]*>(.*?)</li>"#,
            groupCount: 1,
            options: [.caseInsensitive, .dotMatchesLineSeparators]
        )
        .compactMap { ExternalEventSupport.plainText($0.first) }
        .filter { !$0.isEmpty }
    }

    private func extractDiscotechQAPairs(from html: String) -> [(question: String, answer: String)] {
        allRegexMatches(
            in: html,
            pattern: #"<h3[^>]*>(.*?)</h3>\s*<p>(.*?)</p>"#,
            groupCount: 2,
            options: [.caseInsensitive, .dotMatchesLineSeparators]
        )
        .compactMap { match in
            guard match.count >= 2,
                  let question = ExternalEventSupport.plainText(match[0]),
                  let answer = ExternalEventSupport.plainText(match[1]),
                  !question.isEmpty,
                  !answer.isEmpty
            else {
                return nil
            }
            return (question, answer)
        }
    }

    private func answer(in qaPairs: [(question: String, answer: String)], matching token: String) -> String? {
        let normalizedToken = ExternalEventSupport.normalizeToken(token)
        return qaPairs.first {
            ExternalEventSupport.normalizeToken($0.question).contains(normalizedToken)
        }?.answer
    }

    private func entrySnippet(in html: String, matching patterns: [String], maxMatches: Int = 2) -> String? {
        let lowered = html.lowercased()
        guard patterns.contains(where: lowered.contains) else { return nil }
        let text = ExternalEventSupport.plainText(html) ?? ""
        let snippets = text
            .replacingOccurrences(of: "\n", with: ". ")
            .components(separatedBy: CharacterSet(charactersIn: ".!?"))
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .filter { snippet in
                let normalized = ExternalEventSupport.normalizeToken(snippet)
                return patterns.contains(where: normalized.contains)
            }
            .compactMap(cleanedSentence(from:))

        let unique = ExternalEventSupport.uniqueMeaningfulLines(snippets)
        guard !unique.isEmpty else { return nil }
        return unique.prefix(max(1, maxMatches)).joined(separator: ". ")
    }

    private func buildNightlifePolicySnapshot(
        texts: [String?],
        guestListAvailable: Bool?,
        bottleServiceAvailable: Bool?,
        tableMinPrice: Double?,
        coverPrice: Double?,
        sourceCoverageStatus: String?
    ) -> NightlifePolicySnapshot {
        let sentences = texts
            .compactMap { text -> [String]? in
                guard let cleaned = ExternalEventSupport.plainText(text), !cleaned.isEmpty else { return nil }
                return cleaned
                    .replacingOccurrences(of: "•", with: ". ")
                    .replacingOccurrences(of: "\n", with: ". ")
                    .components(separatedBy: CharacterSet(charactersIn: ".!?"))
                    .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                    .compactMap { cleanedSentence(from: $0) }
            }
            .flatMap { $0 }

        let womenEntry = sentences.first(where: isWomenEntrySentence)
        let menEntry = sentences.first(where: isMenEntrySentence)
        let normalizedHaystack = ExternalEventSupport.normalizeToken(sentences.joined(separator: " "))

        let doorSummary = ExternalEventSupport.uniqueMeaningfulLines(
            sentences.filter(isDoorPolicySentence)
        )

        var entryParts: [String?] = []
        if normalizedHaystack.contains("bottle service only")
            || normalizedHaystack.contains("does not have general admission") {
            entryParts.append("Bottle service only. Do not expect a normal general-admission line.")
        } else if bottleServiceAvailable == true, guestListAvailable != true {
            entryParts.append("Bottle service is the primary way in.")
        } else if bottleServiceAvailable == true, guestListAvailable == true {
            entryParts.append("Guest list is possible, but tables are clearly favored.")
        } else if guestListAvailable == true {
            entryParts.append("Guest list access is available.")
        }
        if normalizedHaystack.contains("hard door") {
            entryParts.append("Hard door; fit and timing matter at entry.")
        }
        let entrySummary = ExternalEventSupport.shortened(
            ExternalEventSupport.uniqueMeaningfulLines(entryParts).joined(separator: " "),
            maxLength: 220
        )

        return NightlifePolicySnapshot(
            entryPolicySummary: entrySummary,
            womenEntryPolicyText: womenEntry,
            menEntryPolicyText: menEntry,
            doorPolicyText: ExternalEventSupport.shortened(doorSummary.joined(separator: " "), maxLength: 220),
            exclusivityTierLabel: nightlifeExclusivityTierLabel(
                sourceCoverageStatus: sourceCoverageStatus,
                sentences: sentences,
                guestListAvailable: guestListAvailable,
                bottleServiceAvailable: bottleServiceAvailable,
                tableMinPrice: tableMinPrice,
                coverPrice: coverPrice
            )
        )
    }

    private func cleanedSentence(from sentence: String) -> String? {
        let cleaned = ExternalEventSupport.plainText(sentence) ?? sentence
        let normalized = ExternalEventSupport.normalizeToken(cleaned)
        guard cleaned.count >= 10, !normalized.isEmpty else { return nil }

        let blockedTokens = [
            "get insider information",
            "avoid problems at the door",
            "buy tickets",
            "purchase tickets",
            "book now",
            "click here",
            "read more",
            "more info",
            "vip nightclub",
            "our ultimate guide",
            "photos and info",
            "find the best promoters here",
            "contact us about",
            "name e mail phone number",
            "date you re arriving",
            "other details requests",
            "submit",
            "exclusive nightlife app",
            "book tables directly",
            "upcoming events at",
            "located at",
            "where is",
            "when is",
            "how long will i have to wait",
            "what are the best nights to go",
            "where can i find a list of upcoming events",
            "how much do drinks cost",
            "the place where all celebrities party",
            "celebrity heavy room",
            "exclusive nightlife room"
        ]
        guard !blockedTokens.contains(where: normalized.contains) else {
            return nil
        }

        return ExternalEventSupport.shortened(cleaned, maxLength: 170)
    }

    private func isDoorPolicySentence(_ sentence: String) -> Bool {
        let normalized = ExternalEventSupport.normalizeToken(sentence)
        let pricingOnly = normalized.contains("table prices from")
            || normalized.contains("tables from")
            || normalized.contains("table minimum")
            || normalized.contains("minimum spend")
            || normalized.contains("drinks cost")
            || normalized.contains("cover charge")
        guard !pricingOnly else { return false }
        return normalized.contains("door")
            || normalized.contains("guest list")
            || normalized.contains("bottle service")
            || normalized.contains("table booking")
            || normalized.contains("reservation")
            || normalized.contains("selective")
            || normalized.contains("dress to impress")
            || normalized.contains("general admission")
    }

    private func isWomenEntrySentence(_ sentence: String) -> Bool {
        let normalized = ExternalEventSupport.normalizeToken(sentence)
        let tokens = Set(normalized.split(separator: " ").map(String.init))
        let genderTokens = Set(["women", "woman", "ladies", "girls", "female"])
        let entryTokens = Set(["guest", "list", "table", "bottle", "entry", "free", "ratio", "cover", "door", "admission"])
        return !tokens.intersection(genderTokens).isEmpty
            && !tokens.intersection(entryTokens).isEmpty
    }

    private func isMenEntrySentence(_ sentence: String) -> Bool {
        let normalized = ExternalEventSupport.normalizeToken(sentence)
        let tokens = Set(normalized.split(separator: " ").map(String.init))
        let genderTokens = Set(["men", "man", "guys", "gentlemen", "male"])
        let entryTokens = Set(["guest", "list", "table", "bottle", "entry", "free", "ratio", "cover", "door", "admission"])
        return !tokens.intersection(genderTokens).isEmpty
            && !tokens.intersection(entryTokens).isEmpty
    }

    private func nightlifeExclusivityTierLabel(
        sourceCoverageStatus: String?,
        sentences: [String],
        guestListAvailable: Bool?,
        bottleServiceAvailable: Bool?,
        tableMinPrice: Double?,
        coverPrice: Double?
    ) -> String {
        let haystack = ExternalEventSupport.normalizeToken(
            ([sourceCoverageStatus] + sentences.map { Optional($0) }).compactMap { $0 }.joined(separator: " ")
        )

        if (bottleServiceAvailable == true && (
            guestListAvailable != true
            || haystack.contains("bottle service only")
            || haystack.contains("does not have general admission")
        )) && (
            (tableMinPrice ?? 0) >= 1000
            || (coverPrice ?? 0) >= 100
            || haystack.contains("ultra exclusive")
            || haystack.contains("invite only")
        ) {
            return "Ultra-Selective Door"
        }

        if (bottleServiceAvailable == true && (
            guestListAvailable != true
            || haystack.contains("bottle service only")
            || haystack.contains("does not have general admission")
        )) && (
            (tableMinPrice ?? 0) >= 500
            || haystack.contains("highly exclusive")
            || haystack.contains("hard door")
            || haystack.contains("celebrities party")
            || haystack.contains("a list")
            || haystack.contains("celebrit")
            || haystack.contains("hwood")
            || haystack.contains("rolodex")
            || haystack.contains("bottle service only")
        ) {
            return "Strict Door"
        }

        if (tableMinPrice ?? 0) >= 250
            || (coverPrice ?? -1) >= 40
            || bottleServiceAvailable == true
            || haystack.contains("exclusive")
            || haystack.contains("high door")
            || haystack.contains("hard door")
            || haystack.contains("table booking strongly favored")
            || haystack.contains("celebrit") {
            return "Selective Door"
        }

        if guestListAvailable == true
            || haystack.contains("guest list")
            || haystack.contains("reservation")
            || (tableMinPrice ?? -1) >= 100
            || (coverPrice ?? -1) >= 20 {
            return "Casual Door"
        }

        return "Open Door"
    }

    private func parseAgeMinimum(in html: String) -> Int? {
        if let explicit = firstRegexMatch(in: html, pattern: #"\b(21|18)\+\b"#, options: [.caseInsensitive]).flatMap(Int.init) {
            return explicit
        }
        if let explicit = firstRegexMatch(in: html, pattern: #"Minimum Age:\s*(\d+)"#, options: [.caseInsensitive]).flatMap(Int.init) {
            return explicit
        }
        return nil
    }

    private func parseCoverPrice(from text: String?) -> Double? {
        guard let text else { return nil }
        let normalized = ExternalEventSupport.normalizeToken(text)
        if normalized.contains("does not charge cover") || normalized.contains("no cover") {
            return 0
        }
        guard normalized.contains("cover") else { return nil }
        return moneyValues(
            in: text,
            patterns: [
                #"(?:cover(?: charge)?|door|general admission)[^$0-9]{0,24}\$?\s*([0-9]+(?:,[0-9]{3})*(?:\.[0-9]+)?k?)"#,
                #"\$([0-9]+(?:,[0-9]{3})*(?:\.[0-9]+)?k?)[^.]{0,18}(?:cover(?: charge)?|door|general admission)"#
            ]
        )
        .filter { (10...500).contains($0) }
        .min()
    }

    private func parseTableMinimum(from text: String?) -> Double? {
        guard let text else { return nil }
        let normalized = ExternalEventSupport.normalizeToken(text)
        guard normalized.contains("bottle") || normalized.contains("table") else { return nil }
        return moneyValues(
            in: text,
            patterns: [
                #"(?:table prices? from|tables? from|table minimums?|minimum spend|bottle service(?: only)?|table booking)[^$0-9]{0,24}\$?\s*([0-9]+(?:,[0-9]{3})*(?:\.[0-9]+)?k?)"#,
                #"\$([0-9]+(?:,[0-9]{3})*(?:\.[0-9]+)?k?)[^.]{0,22}(?:table|minimum spend|bottle service)"#
            ]
        )
        .filter { $0 >= 100 }
        .min()
    }

    private func moneyValues(in text: String, patterns: [String]) -> [Double] {
        patterns
            .flatMap { pattern in
                allRegexMatches(
                    in: text,
                    pattern: pattern,
                    groupCount: 1,
                    options: [.caseInsensitive]
                )
            }
            .compactMap(\.first)
            .compactMap(parseMoneyToken)
    }

    private func parseMoneyToken(_ token: String) -> Double? {
        let cleaned = token
            .lowercased()
            .replacingOccurrences(of: "$", with: "")
            .replacingOccurrences(of: ",", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleaned.isEmpty else { return nil }
        if cleaned.hasSuffix("k") {
            let numeric = String(cleaned.dropLast())
            guard let base = Double(numeric) else { return nil }
            return base * 1000
        }
        return Double(cleaned)
    }

    private func nightlifeSignalScore(
        html: String,
        tableMinPrice: Double?,
        coverPrice: Double?,
        guestListAvailable: Bool?,
        bottleServiceAvailable: Bool?
    ) -> Double {
        var score = 6.0
        if guestListAvailable == true { score += 3.5 }
        if bottleServiceAvailable == true { score += 4.2 }
        if let tableMinPrice {
            score += min(tableMinPrice / 600.0, 8.0)
        }
        if let coverPrice, coverPrice >= 50 {
            score += min(coverPrice / 40.0, 3.0)
        }

        let premiumTokens = [
            "exclusive", "celebrit", "hard door", "bottle service only", "reservation only",
            "vip", "guest list", "table booking", "members", "dress to impress"
        ]
        if premiumTokens.contains(where: html.contains) {
            score += 4.0
        }
        return score
    }

    private func prestigeScore(html: String, celebrityText: String) -> Double {
        let haystack = ExternalEventSupport.normalizeToken(html + " " + celebrityText)
        var score = 5.5
        let celebrityTokens = ["celebrit", "a list", "kardashian", "drake", "justin bieber", "elite", "luxury", "glamour", "hollywood royalty"]
        if celebrityTokens.contains(where: haystack.contains) {
            score += 4.5
        }
        let prestigeTokens = ["h wood", "hwood", "supper club", "vip", "exclusive", "private room", "guest list", "table booking", "luxurious", "opulent", "celebrities party"]
        if prestigeTokens.contains(where: haystack.contains) {
            score += 3.5
        }
        return score
    }

    private func extractVenueList(
        in text: String,
        prefix: String,
        stopTokens: [String]
    ) -> [String] {
        let normalizedText = text.replacingOccurrences(of: "•", with: ",")
        guard let range = normalizedText.range(of: prefix, options: .caseInsensitive) else {
            return []
        }
        let tail = String(normalizedText[range.upperBound...])
        let loweredTail = ExternalEventSupport.normalizeToken(tail)
        let stopIndex = stopTokens
            .compactMap { token in loweredTail.range(of: ExternalEventSupport.normalizeToken(token))?.lowerBound }
            .min()
        let relevantTail = stopIndex.map { String(tail[..<tail.index(tail.startIndex, offsetBy: loweredTail.distance(from: loweredTail.startIndex, to: $0))]) } ?? tail
        return relevantTail
            .components(separatedBy: CharacterSet(charactersIn: ",;•"))
            .compactMap { piece -> String? in
                let cleaned = piece.replacingOccurrences(of: "and", with: ",")
                let candidate = ExternalEventSupport.normalizeToken(cleaned)
                return candidate.isEmpty ? nil : candidate
            }
    }

    private func splitVenueMentionSentence(_ text: String?) -> [String] {
        guard let text, !text.isEmpty else { return [] }
        return text
            .replacingOccurrences(of: " and ", with: ", ")
            .replacingOccurrences(of: "•", with: ",")
            .components(separatedBy: CharacterSet(charactersIn: ",;"))
            .compactMap { piece -> String? in
                let cleaned = ExternalEventSupport.normalizeToken(piece)
                guard !cleaned.isEmpty else { return nil }
                return cleaned
            }
    }

    private func mergeCoverageStatus(_ primary: String?, _ secondary: String?) -> String? {
        let values = [primary, secondary]
            .compactMap { value -> String? in
                guard let value, !value.isEmpty else { return nil }
                return value
            }
        guard !values.isEmpty else { return nil }
        var seen = Set<String>()
        let unique = values.compactMap { value -> String? in
            let key = ExternalEventSupport.normalizeToken(value)
            guard !seen.contains(key) else { return nil }
            seen.insert(key)
            return value
        }
        return unique.joined(separator: " • ")
    }

    private func mergePayload(_ existing: String?, extra: [String: Any]) -> String {
        var payload: [String: Any] = [:]
        if let existing,
           let data = existing.data(using: .utf8),
           let decoded = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            payload = decoded
        }
        extra.forEach { payload[$0.key] = $0.value }
        return ExternalEventSupport.jsonString(payload)
    }

    private func reservationProviderName(for urlString: String?) -> String? {
        let normalized = ExternalEventSupport.normalizeToken(urlString)
        if normalized.contains("discotech") { return "Discotech" }
        if normalized.contains("clubbable") { return "Clubbable" }
        if normalized.contains("sevenrooms") { return "SevenRooms" }
        if normalized.contains("resy") { return "Resy" }
        return nil
    }

    private func absoluteURL(path: String?, base: URL) -> String? {
        guard let path, !path.isEmpty else { return nil }
        if path.hasPrefix("http://") || path.hasPrefix("https://") {
            return path
        }
        return URL(string: path, relativeTo: base)?.absoluteURL.absoluteString
    }

    private func titleSlug(_ value: String) -> String {
        value
            .replacingOccurrences(of: "'", with: "")
            .replacingOccurrences(of: "’", with: "")
            .replacingOccurrences(of: "&", with: " and ")
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty }
            .map { token in
                if token.count <= 3 {
                    return token.capitalized
                }
                return token.prefix(1).uppercased() + token.dropFirst()
            }
            .joined(separator: "-")
    }

    private func slugify(_ value: String) -> String {
        ExternalEventSupport.normalizeToken(
            value
                .replacingOccurrences(of: "'", with: "")
                .replacingOccurrences(of: "’", with: "")
                .replacingOccurrences(of: "&", with: " and ")
        )
        .replacingOccurrences(of: " ", with: "-")
    }

    private func firstRegexMatch(
        in source: String,
        pattern: String,
        options: NSRegularExpression.Options = []
    ) -> String? {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: options) else {
            return nil
        }
        let range = NSRange(source.startIndex..<source.endIndex, in: source)
        guard let match = regex.firstMatch(in: source, options: [], range: range),
              match.numberOfRanges > 1,
              let outputRange = Range(match.range(at: 1), in: source) else {
            return nil
        }
        return ExternalEventSupport.plainText(String(source[outputRange]))
    }

    private func allRegexMatches(
        in source: String,
        pattern: String,
        groupCount: Int,
        options: NSRegularExpression.Options = []
    ) -> [[String]] {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: options) else {
            return []
        }
        let range = NSRange(source.startIndex..<source.endIndex, in: source)
        return regex.matches(in: source, options: [], range: range).compactMap { match in
            var groups: [String] = []
            for index in 1...groupCount {
                guard index < match.numberOfRanges,
                      let groupRange = Range(match.range(at: index), in: source) else {
                    return nil
                }
                groups.append(String(source[groupRange]))
            }
            return groups
        }
    }

    private func formatCurrency(_ value: Double) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencyCode = "USD"
        formatter.maximumFractionDigits = value.rounded() == value ? 0 : 2
        return formatter.string(from: NSNumber(value: value)) ?? "$\(Int(value.rounded()))"
    }

    private func uniqueStrings(_ values: [String]) -> [String] {
        var seen = Set<String>()
        return values.compactMap { value -> String? in
            let cleaned = ExternalEventSupport.plainText(value) ?? value
            let key = ExternalEventSupport.normalizeToken(cleaned)
            guard !key.isEmpty, !seen.contains(key) else { return nil }
            seen.insert(key)
            return cleaned
        }
    }

    private func seedVenue(
        name: String,
        sourceVenueID: String,
        query: ExternalVenueQuery,
        discoveryURL: String,
        coverageStatus: String,
        venueType: ExternalVenueType,
        sourceConfidence: Double
    ) -> ExternalVenue {
        ExternalVenue(
            id: "\(source.rawValue):\(sourceVenueID)",
            source: source,
            sourceType: .nightlifeAggregator,
            sourceVenueID: sourceVenueID,
            canonicalVenueID: nil,
            name: name,
            aliases: [name],
            venueType: venueType,
            neighborhood: query.displayName,
            addressLine1: nil,
            addressLine2: nil,
            city: query.city,
            state: query.state,
            postalCode: nil,
            country: query.countryCode,
            latitude: nil,
            longitude: nil,
            officialSiteURL: nil,
            reservationProvider: nil,
            reservationURL: nil,
            imageURL: nil,
            openingHoursText: nil,
            ageMinimum: nil,
            doorPolicyText: nil,
            dressCodeText: nil,
            guestListAvailable: nil,
            bottleServiceAvailable: nil,
            tableMinPrice: nil,
            coverPrice: nil,
            venueSignalScore: 7.2,
            nightlifeSignalScore: 8.0,
            prestigeDemandScore: 7.0,
            recurringEventPatternConfidence: 4.5,
            sourceConfidence: sourceConfidence,
            sourceCoverageStatus: coverageStatus,
            rawSourcePayload: ExternalEventSupport.jsonString([
                "discovery_url": discoveryURL,
                "discovery_market": query.displayName ?? query.city ?? ""
            ])
        )
    }

    private func shouldFetchHWood(for query: ExternalVenueQuery) -> Bool {
        if ExternalEventSupport.isLosAngelesMetroSearchLocation(city: query.city, state: query.state) {
            return true
        }
        guard ExternalEventSupport.normalizeStateToken(query.state) == "ca" else { return false }
        let displayName = ExternalEventSupport.normalizeToken(query.displayName)
        return ["los angeles", "west hollywood", "hollywood", "beverly hills", "santa monica"]
            .contains { displayName.contains($0) }
    }

    private func isLikelyNightlifeVenueSlug(_ slug: String) -> Bool {
        let normalized = ExternalEventSupport.normalizeToken(slug.replacingOccurrences(of: "-", with: " "))
        guard !normalized.isEmpty else { return false }
        if normalized == "feed" || normalized == "guest lists" {
            return false
        }
        let blockedTokens = [
            "top", "best", "bachelorette", "bachelor", "pool parties", "club crawl",
            "rooftop bars", "nightlife spots", "asian clubs", "edm clubs", "hip hop clubs",
            "high end", "restaurants", "clubstaurants", "nightlife news", "promo code",
            "discount", "grand opening", "what are the best", "music festivals",
            "festival lineup", "virgin fest", "this thursday", "this friday",
            "this saturday", "this sunday", "lineup"
        ]
        return !blockedTokens.contains(where: normalized.contains)
    }

    private func humanizedVenueName(fromSlug slug: String) -> String {
        slug
            .replacingOccurrences(of: "%20", with: " ")
            .replacingOccurrences(of: "-", with: " ")
            .split(separator: " ")
            .map { token -> String in
                if token.uppercased() == token, token.count <= 4 {
                    return String(token)
                }
                let value = String(token)
                guard let first = value.first else { return value }
                return first.uppercased() + value.dropFirst().lowercased()
            }
            .joined(separator: " ")
    }

    private func hwoodDoorPolicyText(
        listedForGuestList: Bool,
        listedForTables: Bool,
        listedAsHotspot: Bool
    ) -> String? {
        var parts: [String] = []
        if listedAsHotspot {
            parts.append("Recognized by h.wood Rolodex as a top Los Angeles nightlife hotspot.")
        }
        if listedForGuestList && listedForTables {
            parts.append("Guest list access and table bookings are both available through h.wood Rolodex.")
        } else if listedForGuestList {
            parts.append("Guest list access is available through h.wood Rolodex.")
        } else if listedForTables {
            parts.append("Table bookings are available through h.wood Rolodex.")
        }
        return parts.isEmpty ? nil : parts.joined(separator: " ")
    }

    private func venueSearchTerms(for venue: ExternalVenue) -> [String] {
        let original = ExternalEventSupport.plainText(venue.name) ?? venue.name
        let lowercased = original.lowercased()
        var candidates = [original]

        for alias in venue.aliases {
            let cleanedAlias = ExternalEventSupport.plainText(alias) ?? alias
            if !cleanedAlias.isEmpty {
                candidates.append(cleanedAlias)
            }
        }

        func strippedDescriptors(_ value: String) -> String {
            var output = value.trimmingCharacters(in: .whitespacesAndNewlines)
            let suffixes = [
                " rooftop lounge",
                " rooftop bar",
                " rooftop club",
                " rooftop",
                " lounge",
                " nightclub",
                " night club",
                " club",
                " bar",
                " hotel",
                " west hollywood",
                " los angeles"
            ]

            var matched = true
            while matched {
                matched = false
                for suffix in suffixes where output.lowercased().hasSuffix(suffix) {
                    output = String(output.dropLast(suffix.count)).trimmingCharacters(in: .whitespacesAndNewlines)
                    matched = true
                }
            }

            if output.lowercased().hasPrefix("the ") {
                output = String(output.dropFirst(4)).trimmingCharacters(in: .whitespacesAndNewlines)
            }
            return output
        }

        if let atRange = lowercased.range(of: " at ") {
            let left = String(original[..<atRange.lowerBound]).trimmingCharacters(in: .whitespacesAndNewlines)
            let right = String(original[atRange.upperBound...]).trimmingCharacters(in: .whitespacesAndNewlines)
            let strippedLeft = strippedDescriptors(left)
            let strippedRight = strippedDescriptors(right)
            candidates.append(left)
            candidates.append(right)
            candidates.append(strippedLeft)
            candidates.append(strippedRight)
            if !strippedLeft.isEmpty, !strippedRight.isEmpty {
                candidates.append("\(strippedLeft) at \(strippedRight)")
                candidates.append("\(strippedRight) at \(strippedLeft)")
                candidates.append("\(strippedRight) \(strippedLeft)")
            }
        }

        let trims = [
            " rooftop lounge",
            " rooftop bar",
            " rooftop",
            " lounge",
            " bar",
            " club",
            " nightclub"
        ]

        for suffix in trims {
            if lowercased.hasSuffix(suffix) {
                candidates.append(String(original.dropLast(suffix.count)))
            }
        }

        let strippedOriginal = strippedDescriptors(original)
        if !strippedOriginal.isEmpty {
            candidates.append(strippedOriginal)
        }

        var seen = Set<String>()
        return candidates.compactMap { value in
            let cleaned = value.trimmingCharacters(in: .whitespacesAndNewlines)
            let key = ExternalEventSupport.normalizeToken(
                cleaned
                    .replacingOccurrences(of: "'", with: "")
                    .replacingOccurrences(of: "’", with: "")
            )
            guard !key.isEmpty, !seen.contains(key) else { return nil }
            seen.insert(key)
            return cleaned
        }
    }

    private func normalizedVenueTokens(for venue: ExternalVenue) -> [String] {
        normalizedVenueTokens(forSearchTerms: venueSearchTerms(for: venue))
    }

    private func normalizedVenueTokens(forSearchTerms searchTerms: [String]) -> [String] {
        var seen = Set<String>()
        return searchTerms.compactMap { value -> String? in
            let normalized = ExternalEventSupport.normalizeToken(
                value
                    .replacingOccurrences(of: "'", with: "")
                    .replacingOccurrences(of: "’", with: "")
            )
            guard normalized.count >= 3, !seen.contains(normalized) else { return nil }
            seen.insert(normalized)
            return normalized
        }
    }
}

nonisolated struct NightlifeEditorialVenueAdapter: NightlifeVenueEnrichmentAdapter {
    let source: ExternalEventSource = .editorialGuide

    func enrichVenues(
        _ venues: [ExternalVenue],
        query: ExternalVenueQuery,
        session: URLSession,
        configuration: ExternalEventServiceConfiguration
    ) async -> ExternalVenueSourceResult {
        ExternalVenueSourceResult(
            source: source,
            fetchedAt: Date(),
            endpoints: [],
            note: "Editorial nightlife guides are modeled as weak-signal enrichment only and are not active source-of-truth providers yet.",
            venues: []
        )
    }
}
