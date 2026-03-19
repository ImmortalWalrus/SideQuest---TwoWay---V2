import Foundation

nonisolated struct YelpFusionVenueAdapter: ExternalVenueSourceAdapter {
    let source: ExternalEventSource = .yelpFusion

    func discoverVenues(
        query: ExternalVenueQuery,
        session: URLSession,
        configuration: ExternalEventServiceConfiguration
    ) async -> ExternalVenueSourceResult {
        if let apiKey = configuration.yelpAPIKey, !apiKey.isEmpty {
            return await discoverViaYelpAPI(
                query: query,
                session: session,
                configuration: configuration,
                apiKey: apiKey
            )
        }

        if let token = configuration.apifyAPIToken, !token.isEmpty {
            return await discoverViaApifyActor(
                query: query,
                session: session,
                configuration: configuration,
                token: token
            )
        }

        return ExternalVenueSourceResult(
            source: source,
            fetchedAt: Date(),
            endpoints: [],
            note: ExternalEventIngestionError.missingCredential("Missing Yelp API key or Apify token for Yelp venue discovery.").localizedDescription,
            venues: []
        )
    }

    private func discoverViaYelpAPI(
        query: ExternalVenueQuery,
        session: URLSession,
        configuration: ExternalEventServiceConfiguration,
        apiKey: String
    ) async -> ExternalVenueSourceResult {
        var components = URLComponents(
            url: configuration.yelpBaseURL.appendingPathComponent("businesses/search"),
            resolvingAgainstBaseURL: false
        )
        components?.queryItems = [
            URLQueryItem(name: "latitude", value: String(query.latitude)),
            URLQueryItem(name: "longitude", value: String(query.longitude)),
            URLQueryItem(name: "radius", value: String(Int(min(query.nightlifeRadiusMiles * 1609.34, 40_000)))),
            URLQueryItem(name: "limit", value: String(min(max(query.pageSize, 8), 50))),
            URLQueryItem(name: "term", value: "nightlife live music event venue"),
            URLQueryItem(name: "sort_by", value: "best_match")
        ]
        guard let url = components?.url else {
            return ExternalVenueSourceResult(
                source: source,
                fetchedAt: Date(),
                endpoints: [],
                note: "Could not build Yelp venue discovery request.",
                venues: []
            )
        }

        var request = URLRequest(url: url)
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")

        do {
            let (data, response) = try await session.data(for: request)
            let statusCode = (response as? HTTPURLResponse)?.statusCode
            let endpoint = ExternalEventEndpointResult(
                label: "Yelp venue discovery",
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
            let venues = json.array("businesses").compactMap(normalizeYelpBusiness(business:))
            return ExternalVenueSourceResult(
                source: source,
                fetchedAt: Date(),
                endpoints: [endpoint],
                note: venues.isEmpty ? "Yelp returned no nightlife-oriented venues for the current coordinate." : nil,
                venues: venues
            )
        } catch {
            return ExternalVenueSourceResult(
                source: source,
                fetchedAt: Date(),
                endpoints: [
                    ExternalEventEndpointResult(
                        label: "Yelp venue discovery",
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

    private func discoverViaApifyActor(
        query: ExternalVenueQuery,
        session: URLSession,
        configuration: ExternalEventServiceConfiguration,
        token: String
    ) async -> ExternalVenueSourceResult {
        guard let runURL = buildApifyRunURL(configuration: configuration, token: token) else {
            return ExternalVenueSourceResult(
                source: source,
                fetchedAt: Date(),
                endpoints: [],
                note: "Could not build Yelp Apify actor URL.",
                venues: []
            )
        }

        let locationText = query.displayName ?? [query.city, query.state]
            .compactMap { value in
                guard let value, !value.isEmpty else { return nil }
                return value
            }
            .joined(separator: ", ")
        guard !locationText.isEmpty else {
            return ExternalVenueSourceResult(
                source: source,
                fetchedAt: Date(),
                endpoints: [],
                note: "Yelp Apify discovery needs a reverse-geocoded city/state label for the current coordinate.",
                venues: []
            )
        }

        let payload: [String: Any] = [
            "keywords": [
                "night club",
                "cocktail bar",
                "live music venue",
                "music venue",
                "event venue"
            ],
            "locations": [locationText],
            "sort": "Highest Rated",
            "price": ["$$$", "$$$$"],
            "maxCrawlPages": 1,
            "unique_only": true
        ]

        var request = URLRequest(url: runURL)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try? JSONSerialization.data(withJSONObject: payload, options: [.sortedKeys])

        do {
            let (data, response) = try await session.data(for: request)
            let statusCode = (response as? HTTPURLResponse)?.statusCode
            let endpoint = ExternalEventEndpointResult(
                label: "Yelp Apify venue discovery",
                requestURL: runURL.absoluteString,
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

            let parsed = try JSONSerialization.jsonObject(with: data)
            let items = parsed as? [JSONDictionary] ?? []
            let venues = items.compactMap(normalizeApifyBusiness(item:))
            return ExternalVenueSourceResult(
                source: source,
                fetchedAt: Date(),
                endpoints: [endpoint],
                note: venues.isEmpty ? "Yelp Apify actor did not return venue records for the current geography." : nil,
                venues: venues
            )
        } catch {
            return ExternalVenueSourceResult(
                source: source,
                fetchedAt: Date(),
                endpoints: [
                    ExternalEventEndpointResult(
                        label: "Yelp Apify venue discovery",
                        requestURL: runURL.absoluteString,
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

    private func buildApifyRunURL(configuration: ExternalEventServiceConfiguration, token: String) -> URL? {
        var components = URLComponents(
            url: configuration.apifyBaseURL.appendingPathComponent("v2/acts/\(configuration.yelpBusinessActorID)/run-sync-get-dataset-items"),
            resolvingAgainstBaseURL: false
        )
        components?.queryItems = [
            URLQueryItem(name: "token", value: token),
            URLQueryItem(name: "memory", value: "1024"),
            URLQueryItem(name: "timeout", value: "120"),
            URLQueryItem(name: "clean", value: "true")
        ]
        return components?.url
    }

    private func normalizeYelpBusiness(business: JSONDictionary) -> ExternalVenue? {
        let categories = business.array("categories").compactMap { $0.dictionary("title")?.string("en_US") ?? $0.string("title") ?? $0.string("alias") }
        let location = business.dictionary("location")
        let coordinate = business.dictionary("coordinates")
        let transactions = business["transactions"] as? [String] ?? []
        let displayAddress = location?["display_address"] as? [String]
        let isNightlife = categories.contains { category in
            let token = ExternalEventSupport.normalizeToken(category)
            return token.contains("nightlife") || token.contains("dance") || token.contains("club") || token.contains("music")
        }

        return ExternalVenue(
            id: "\(source.rawValue):\(business.string("id") ?? UUID().uuidString)",
            source: source,
            sourceType: .venueDiscoveryAPI,
            sourceVenueID: business.string("id") ?? UUID().uuidString,
            canonicalVenueID: nil,
            name: business.string("name") ?? "Unnamed Yelp Venue",
            aliases: [],
            venueType: isNightlife ? .nightlifeVenue : .other,
            neighborhood: displayAddress?.first,
            addressLine1: location?.string("address1"),
            addressLine2: location?.string("address2"),
            city: location?.string("city"),
            state: location?.string("state"),
            postalCode: location?.string("zip_code"),
            country: location?.string("country"),
            latitude: ExternalEventSupport.parseDouble(coordinate?["latitude"]),
            longitude: ExternalEventSupport.parseDouble(coordinate?["longitude"]),
            officialSiteURL: nil,
            reservationProvider: nil,
            reservationURL: nil,
            imageURL: business.string("image_url"),
            openingHoursText: transactions.isEmpty ? nil : transactions.joined(separator: " · "),
            ageMinimum: nil,
            doorPolicyText: nil,
            dressCodeText: nil,
            guestListAvailable: nil,
            bottleServiceAvailable: nil,
            tableMinPrice: nil,
            coverPrice: nil,
            venueSignalScore: venueScore(rating: ExternalEventSupport.parseDouble(business["rating"]), reviews: ExternalEventSupport.parseInt(business["review_count"])),
            nightlifeSignalScore: isNightlife ? venueScore(rating: ExternalEventSupport.parseDouble(business["rating"]), reviews: ExternalEventSupport.parseInt(business["review_count"])) : nil,
            prestigeDemandScore: venueScore(rating: ExternalEventSupport.parseDouble(business["rating"]), reviews: ExternalEventSupport.parseInt(business["review_count"])),
            recurringEventPatternConfidence: nil,
            sourceConfidence: 0.78,
            sourceCoverageStatus: nil,
            rawSourcePayload: ExternalEventSupport.jsonString(business)
        )
    }

    private func normalizeApifyBusiness(item: JSONDictionary) -> ExternalVenue? {
        let categories = stringArray(from: item, keys: ["categories", "categoryTitles"])
        let displayAddress = stringArray(from: item, keys: ["displayAddress", "display_address"])
        let isNightlife = categories.contains { category in
            let token = ExternalEventSupport.normalizeToken(category)
            return token.contains("nightlife") || token.contains("club") || token.contains("dance") || token.contains("music") || token.contains("cocktail")
        }

        return ExternalVenue(
            id: "\(source.rawValue):\(item.string("id") ?? item.string("businessId") ?? UUID().uuidString)",
            source: source,
            sourceType: .scraped,
            sourceVenueID: item.string("id") ?? item.string("businessId") ?? UUID().uuidString,
            canonicalVenueID: nil,
            name: item.string("name") ?? "Unnamed Yelp Venue",
            aliases: [],
            venueType: isNightlife ? .nightlifeVenue : .other,
            neighborhood: displayAddress.first,
            addressLine1: item.string("address") ?? displayAddress.first,
            addressLine2: nil,
            city: item.string("city"),
            state: item.string("state"),
            postalCode: item.string("zipCode") ?? item.string("postalCode"),
            country: item.string("country"),
            latitude: ExternalEventSupport.parseDouble(item["latitude"]),
            longitude: ExternalEventSupport.parseDouble(item["longitude"]),
            officialSiteURL: item.string("website") ?? item.string("businessWebsite"),
            reservationProvider: reservationProvider(for: item),
            reservationURL: firstURL(from: item, keys: ["reservationUrl", "bookingUrl", "reservationURL"]),
            imageURL: firstURL(from: item, keys: ["imageUrl", "imageURL", "photoUrl", "photoURL"]),
            openingHoursText: openingHours(from: item),
            ageMinimum: parseAgeMinimum(from: item),
            doorPolicyText: nil,
            dressCodeText: nil,
            guestListAvailable: nil,
            bottleServiceAvailable: nil,
            tableMinPrice: nil,
            coverPrice: nil,
            venueSignalScore: venueScore(rating: ExternalEventSupport.parseDouble(item["rating"]), reviews: ExternalEventSupport.parseInt(item["reviewCount"] ?? item["reviews"])),
            nightlifeSignalScore: isNightlife ? venueScore(rating: ExternalEventSupport.parseDouble(item["rating"]), reviews: ExternalEventSupport.parseInt(item["reviewCount"] ?? item["reviews"])) : nil,
            prestigeDemandScore: venueScore(rating: ExternalEventSupport.parseDouble(item["rating"]), reviews: ExternalEventSupport.parseInt(item["reviewCount"] ?? item["reviews"])),
            recurringEventPatternConfidence: item["hours"] == nil ? nil : 0.62,
            sourceConfidence: 0.71,
            sourceCoverageStatus: nil,
            rawSourcePayload: ExternalEventSupport.jsonString(item)
        )
    }

    private func firstURL(from item: JSONDictionary, keys: [String]) -> String? {
        for key in keys {
            if let string = item.string(key), string.hasPrefix("http") {
                return string
            }
        }
        return nil
    }

    private func stringArray(from item: JSONDictionary, keys: [String]) -> [String] {
        for key in keys {
            if let values = item[key] as? [String], !values.isEmpty {
                return values
            }
            if let values = item[key] as? [[String: Any]] {
                let strings = values.compactMap { $0["title"] as? String ?? $0["name"] as? String }
                if !strings.isEmpty {
                    return strings
                }
            }
        }
        return []
    }

    private func openingHours(from item: JSONDictionary) -> String? {
        if let hours = item["hours"] as? [String], !hours.isEmpty {
            return hours.joined(separator: " | ")
        }
        if let string = item.string("hoursText"), !string.isEmpty {
            return string
        }
        return nil
    }

    private func parseAgeMinimum(from item: JSONDictionary) -> Int? {
        let haystack = ExternalEventSupport.normalizeToken(
            [item.string("summary"), item.string("description"), item.string("attributesText")]
                .compactMap { $0 }
                .joined(separator: " ")
        )
        if haystack.contains("21") { return 21 }
        if haystack.contains("18") { return 18 }
        return nil
    }

    private func reservationProvider(for item: JSONDictionary) -> String? {
        let url = firstURL(from: item, keys: ["reservationUrl", "bookingUrl", "website", "businessWebsite"])
        let normalized = ExternalEventSupport.normalizeToken(url)
        if normalized.contains("resy") { return "Resy" }
        if normalized.contains("sevenrooms") { return "SevenRooms" }
        if normalized.contains("opentable") { return "OpenTable" }
        return nil
    }

    private func venueScore(rating: Double?, reviews: Int?) -> Double? {
        guard let rating else { return nil }
        let reviewBoost = min(Double(reviews ?? 0) / 300.0, 4.0)
        return rating + reviewBoost
    }
}
