import Foundation

nonisolated struct GooglePlacesVenueAdapter: ExternalVenueSourceAdapter {
    let source: ExternalEventSource = .googlePlaces

    func discoverVenues(
        query: ExternalVenueQuery,
        session: URLSession,
        configuration: ExternalEventServiceConfiguration
    ) async -> ExternalVenueSourceResult {
        guard let apiKey = configuration.googlePlacesAPIKey, !apiKey.isEmpty else {
            return ExternalVenueSourceResult(
                source: source,
                fetchedAt: Date(),
                endpoints: [],
                note: ExternalEventIngestionError.missingCredential("Missing Google Places API key.").localizedDescription,
                venues: []
            )
        }

        let url = configuration.googlePlacesBaseURL.appendingPathComponent("places:searchNearby")
        guard URLComponents(url: url, resolvingAgainstBaseURL: false) != nil else {
            return ExternalVenueSourceResult(
                source: source,
                fetchedAt: Date(),
                endpoints: [],
                note: "Could not build Google Places Nearby Search URL.",
                venues: []
            )
        }

        let radiusMeters = Int(min(max(query.nightlifeRadiusMiles, 1) * 1609.34, 49_000))
        let payload: [String: Any] = [
            "includedTypes": [
                "night_club",
                "bar",
                "live_music_venue",
                "event_venue",
                "concert_hall",
                "stadium",
                "arena"
            ],
            "maxResultCount": min(max(query.pageSize, 8), 20),
            "locationRestriction": [
                "circle": [
                    "center": [
                        "latitude": query.latitude,
                        "longitude": query.longitude
                    ],
                    "radius": radiusMeters
                ]
            ]
        ]

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue(apiKey, forHTTPHeaderField: "X-Goog-Api-Key")
        request.setValue(
            "places.id,places.displayName,places.primaryType,places.primaryTypeDisplayName,places.formattedAddress,places.shortFormattedAddress,places.location,places.businessStatus,places.websiteUri,places.rating,places.userRatingCount,places.regularOpeningHours,places.priceLevel,places.googleMapsUri",
            forHTTPHeaderField: "X-Goog-FieldMask"
        )
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try? JSONSerialization.data(withJSONObject: payload, options: [.sortedKeys])

        do {
            let (data, response) = try await session.data(for: request)
            let statusCode = (response as? HTTPURLResponse)?.statusCode
            let endpoint = ExternalEventEndpointResult(
                label: "Google Places nearby venues",
                requestURL: url.absoluteString,
                responseStatusCode: statusCode,
                worked: statusCode.map { 200..<300 ~= $0 } ?? false,
                note: nil
            )

            guard statusCode.map({ 200..<300 ~= $0 }) ?? false else {
                return ExternalVenueSourceResult(
                    source: source,
                    fetchedAt: Date(),
                    endpoints: [endpoint],
                    note: String(data: data, encoding: .utf8),
                    venues: []
                )
            }

            let json = try ExternalEventSupport.decodeJSONDictionary(data)
            let venues = json.array("places").compactMap(normalize(place:))
            return ExternalVenueSourceResult(
                source: source,
                fetchedAt: Date(),
                endpoints: [endpoint],
                note: venues.isEmpty ? "Google Places returned no matching venues near the current coordinate." : nil,
                venues: venues
            )
        } catch {
            return ExternalVenueSourceResult(
                source: source,
                fetchedAt: Date(),
                endpoints: [
                    ExternalEventEndpointResult(
                        label: "Google Places nearby venues",
                        requestURL: url.absoluteString,
                        responseStatusCode: nil,
                        worked: false,
                        note: error.localizedDescription
                    )
                ],
                note: error.localizedDescription,
                venues: []
            )
        }
    }

    private func normalize(place: JSONDictionary) -> ExternalVenue? {
        let name = place.dictionary("displayName")?.string("text") ?? place.string("displayName") ?? "Unnamed Venue"
        let address = place.string("formattedAddress")
        let shortAddress = place.string("shortFormattedAddress")
        let primaryType = place.string("primaryType")
        let regularOpeningHours = place.dictionary("regularOpeningHours")
        let openHours = (regularOpeningHours?["weekdayDescriptions"] as? [String])?.joined(separator: " | ")
        let userRatingCount = ExternalEventSupport.parseInt(place["userRatingCount"])

        return ExternalVenue(
            id: "\(source.rawValue):\(place.string("id") ?? UUID().uuidString)",
            source: source,
            sourceType: .venueDiscoveryAPI,
            sourceVenueID: place.string("id") ?? UUID().uuidString,
            canonicalVenueID: nil,
            name: name,
            aliases: shortAddress.map { [$0] } ?? [],
            venueType: venueType(for: primaryType),
            neighborhood: shortAddress,
            addressLine1: address,
            addressLine2: nil,
            city: nil,
            state: nil,
            postalCode: nil,
            country: "US",
            latitude: place.dictionary("location").flatMap { ExternalEventSupport.parseDouble($0["latitude"]) },
            longitude: place.dictionary("location").flatMap { ExternalEventSupport.parseDouble($0["longitude"]) },
            officialSiteURL: place.string("websiteUri"),
            reservationProvider: nil,
            reservationURL: nil,
            imageURL: nil,
            openingHoursText: openHours?.isEmpty == false ? openHours : nil,
            ageMinimum: nil,
            doorPolicyText: nil,
            dressCodeText: nil,
            guestListAvailable: nil,
            bottleServiceAvailable: nil,
            tableMinPrice: nil,
            coverPrice: nil,
            venueSignalScore: score(rating: ExternalEventSupport.parseDouble(place["rating"]), ratingsCount: userRatingCount),
            nightlifeSignalScore: venueType(for: primaryType) == .nightlifeVenue ? score(rating: ExternalEventSupport.parseDouble(place["rating"]), ratingsCount: userRatingCount) : nil,
            prestigeDemandScore: score(rating: ExternalEventSupport.parseDouble(place["rating"]), ratingsCount: userRatingCount),
            recurringEventPatternConfidence: regularOpeningHours == nil ? nil : 0.68,
            sourceConfidence: 0.84,
            sourceCoverageStatus: place.string("businessStatus"),
            rawSourcePayload: ExternalEventSupport.jsonString(place)
        )
    }

    private func venueType(for primaryType: String?) -> ExternalVenueType {
        switch ExternalEventSupport.normalizeToken(primaryType) {
        case "stadium":
            return .stadium
        case "arena":
            return .arena
        case "night club":
            return .nightlifeVenue
        case "bar":
            return .bar
        case "live music venue", "concert hall", "event venue":
            return .concertVenue
        default:
            return .other
        }
    }

    private func score(rating: Double?, ratingsCount: Int?) -> Double? {
        guard let rating else { return nil }
        let countScore = min(Double(ratingsCount ?? 0) / 250.0, 4.0)
        return rating + countScore
    }
}
