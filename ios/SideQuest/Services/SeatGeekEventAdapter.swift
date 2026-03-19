import Foundation

nonisolated struct SeatGeekEventAdapter: ExternalEventSourceAdapter {
    let source: ExternalEventSource = .seatGeek

    func fetchPage(
        query: ExternalEventQuery,
        cursor: ExternalEventSourceCursor?,
        session: URLSession,
        configuration: ExternalEventServiceConfiguration
    ) async -> ExternalEventSourceResult {
        guard let clientID = configuration.seatGeekClientID, !clientID.isEmpty else {
            return ExternalEventSourceResult(
                source: source,
                usedCache: false,
                fetchedAt: Date(),
                endpoints: [],
                note: ExternalEventIngestionError.missingCredential("Missing SeatGeek client ID.").localizedDescription,
                nextCursor: nil,
                events: []
            )
        }

        let page = max(cursor?.page ?? (query.page + 1), 1)
        var components = URLComponents(
            url: configuration.seatGeekBaseURL.appendingPathComponent("events"),
            resolvingAgainstBaseURL: false
        )
        components?.queryItems = [
            URLQueryItem(name: "client_id", value: clientID),
            URLQueryItem(name: "page", value: String(page)),
            URLQueryItem(name: "per_page", value: String(max(12, min(query.pageSize, 48)))),
            URLQueryItem(name: "sort", value: "datetime_utc.asc"),
            URLQueryItem(name: "datetime_utc.gte", value: seatGeekDateString(Date()))
        ]

        if let latitude = query.latitude, let longitude = query.longitude {
            components?.queryItems?.append(URLQueryItem(name: "lat", value: String(latitude)))
            components?.queryItems?.append(URLQueryItem(name: "lon", value: String(longitude)))
            let rangeMiles = Int(query.headlineRadiusMiles > 0 ? query.headlineRadiusMiles : (query.radiusMiles ?? 12))
            components?.queryItems?.append(URLQueryItem(name: "range", value: "\(max(2, rangeMiles))mi"))
        } else if let city = query.city, !city.isEmpty {
            components?.queryItems?.append(URLQueryItem(name: "venue.city", value: city))
        }

        if let state = query.state, !state.isEmpty {
            components?.queryItems?.append(URLQueryItem(name: "venue.state", value: state))
        }

        if let keyword = query.keyword, !keyword.isEmpty {
            components?.queryItems?.append(URLQueryItem(name: "q", value: keyword))
        }

        guard let url = components?.url else {
            return ExternalEventSourceResult(
                source: source,
                usedCache: false,
                fetchedAt: Date(),
                endpoints: [],
                note: "Could not build SeatGeek request URL.",
                nextCursor: nil,
                events: []
            )
        }

        do {
            let (data, response) = try await session.data(from: url)
            let statusCode = (response as? HTTPURLResponse)?.statusCode
            let endpoint = ExternalEventEndpointResult(
                label: "SeatGeek events",
                requestURL: url.absoluteString,
                responseStatusCode: statusCode,
                worked: statusCode.map { 200..<300 ~= $0 } ?? false,
                note: nil
            )

            guard statusCode.map({ 200..<300 ~= $0 }) ?? false else {
                return ExternalEventSourceResult(
                    source: source,
                    usedCache: false,
                    fetchedAt: Date(),
                    endpoints: [endpoint],
                    note: String(data: data, encoding: .utf8),
                    nextCursor: nil,
                    events: []
                )
            }

            let json = try ExternalEventSupport.decodeJSONDictionary(data)
            let events = json.array("events").compactMap(normalize(event:))
                .filter { query.includePast || $0.isUpcoming }
            let meta = json.dictionary("meta")
            let hasMore = (ExternalEventSupport.parseInt(meta?["page"]) ?? page) * (ExternalEventSupport.parseInt(meta?["per_page"]) ?? query.pageSize) < (ExternalEventSupport.parseInt(meta?["total"]) ?? 0)

            return ExternalEventSourceResult(
                source: source,
                usedCache: false,
                fetchedAt: Date(),
                endpoints: [endpoint],
                note: events.isEmpty ? "SeatGeek returned no local events for the current query." : nil,
                nextCursor: hasMore ? ExternalEventSourceCursor(source: source, page: page + 1, pageSize: query.pageSize, nextToken: nil) : nil,
                events: ExternalEventIngestionService.dedupe(events: events).events
            )
        } catch {
            return ExternalEventSourceResult(
                source: source,
                usedCache: false,
                fetchedAt: Date(),
                endpoints: [
                    ExternalEventEndpointResult(
                        label: "SeatGeek events",
                        requestURL: url.absoluteString,
                        responseStatusCode: nil,
                        worked: false,
                        note: error.localizedDescription
                    )
                ],
                note: error.localizedDescription,
                nextCursor: nil,
                events: []
            )
        }
    }

    private func normalize(event: JSONDictionary) -> ExternalEvent? {
        let title = event.string("title") ?? "Untitled SeatGeek Event"
        let performers = event.array("performers")
        let performerNames = performers.compactMap { $0.string("name") }
        let taxonomies = event.array("taxonomies")
        let venue = event.dictionary("venue")
        let venueLocation = (venue?["location"] as? [String: Any]) ?? [:]
        let score = ExternalEventSupport.parseDouble(event["score"])
        let type = normalizeType(taxonomies: taxonomies, title: title, performers: performerNames)
        let localDateTime = event.string("datetime_local")
        let utcDateTime = seatGeekUTCDate(event.string("datetime_utc"))
        let venueName = venue?.string("name")
        let locationBits = [
            venue?.string("city"),
            venue?.string("state"),
            venue?.string("extended_address")
        ].compactMap { $0 }.joined(separator: " ")

        return ExternalEvent(
            id: "\(source.rawValue):\(event.string("id") ?? UUID().uuidString)",
            source: source,
            sourceEventID: event.string("id") ?? UUID().uuidString,
            sourceParentID: nil,
            sourceURL: event.string("url"),
            mergedSources: [source],
            title: title,
            shortDescription: ExternalEventSupport.shortened(locationBits.isEmpty ? nil : locationBits),
            fullDescription: nil,
            category: taxonomies.first?.string("name"),
            subcategory: performers.first?.string("type"),
            eventType: type,
            startAtUTC: utcDateTime,
            endAtUTC: nil,
            startLocal: localDateTime,
            endLocal: nil,
            timezone: venue?.string("timezone"),
            salesStartAtUTC: nil,
            salesEndAtUTC: nil,
            venueName: venueName,
            venueID: venue?.string("id"),
            addressLine1: venue?.string("address"),
            addressLine2: nil,
            city: venue?.string("city"),
            state: venue?.string("state"),
            postalCode: venue?.string("postal_code"),
            country: venue?.string("country"),
            latitude: ExternalEventSupport.parseDouble(venue?["lat"]) ?? ExternalEventSupport.parseDouble(venueLocation["lat"]) ?? ExternalEventSupport.parseDouble(venueLocation["latitude"]),
            longitude: ExternalEventSupport.parseDouble(venue?["lon"]) ?? ExternalEventSupport.parseDouble(venueLocation["lon"]) ?? ExternalEventSupport.parseDouble(venueLocation["longitude"]),
            imageURL: preferredImageURL(performers: performers),
            fallbackThumbnailAsset: ExternalEventSupport.fallbackThumbnailAsset(for: type),
            status: status(for: event, startAtUTC: utcDateTime).0,
            availabilityStatus: status(for: event, startAtUTC: utcDateTime).1,
            urgencyBadge: nil,
            socialProofCount: nil,
            socialProofLabel: nil,
            venuePopularityCount: nil,
            venueRating: nil,
            ticketProviderCount: nil,
            priceMin: ExternalEventSupport.parseDouble(event.dictionary("stats")?["lowest_price"]),
            priceMax: ExternalEventSupport.parseDouble(event.dictionary("stats")?["highest_price"]),
            currency: "USD",
            organizerName: nil,
            organizerEventCount: nil,
            organizerVerified: nil,
            tags: ExternalEventSupport.tags(from: [
                taxonomies.first?.string("name"),
                venueName,
                performerNames.joined(separator: ", "),
                type.rawValue
            ]),
            distanceValue: nil,
            distanceUnit: nil,
            raceType: nil,
            registrationURL: nil,
            ticketURL: event.string("url"),
            rawSourcePayload: ExternalEventSupport.jsonString(event),
            sourceType: .ticketingAPI,
            recordKind: .event,
            neighborhood: venue?.string("display_location"),
            reservationURL: nil,
            artistsOrTeams: performerNames,
            ageMinimum: nil,
            doorPolicyText: nil,
            dressCodeText: nil,
            guestListAvailable: nil,
            bottleServiceAvailable: nil,
            tableMinPrice: nil,
            coverPrice: nil,
            openingHoursText: nil,
            sourceConfidence: 0.86,
            popularityScoreRaw: score,
            venueSignalScore: score,
            exclusivityScore: type == .partyNightlife ? score : nil,
            trendingScore: score,
            crossSourceConfirmationScore: nil,
            distanceFromUser: nil
        )
    }

    private func normalizeType(taxonomies: [[String: Any]], title: String, performers: [String]) -> ExternalEventType {
        let haystack = ExternalEventSupport.normalizeToken(([title] + performers + taxonomies.compactMap { $0.string("name") }).joined(separator: " "))
        if haystack.contains("sport") || haystack.contains("nba") || haystack.contains("mlb") || haystack.contains("nfl") || haystack.contains("nhl") || haystack.contains("soccer") || haystack.contains("fc ") {
            return .sportsEvent
        }
        if haystack.contains("concert") || haystack.contains("music") || haystack.contains("tour") || haystack.contains("band") {
            return .concert
        }
        if haystack.contains("club") || haystack.contains("nightlife") || haystack.contains("party") || haystack.contains("dj") {
            return .partyNightlife
        }
        if haystack.contains("comedy") || haystack.contains("theater") || haystack.contains("theatre") {
            return .weekendActivity
        }
        return .otherLiveEvent
    }

    private func preferredImageURL(performers: [[String: Any]]) -> String? {
        performers
            .sorted { (ExternalEventSupport.parseInt($0["score"]) ?? 0) > (ExternalEventSupport.parseInt($1["score"]) ?? 0) }
            .compactMap { $0.string("image") }
            .first
    }

    private func status(for event: JSONDictionary, startAtUTC: Date?) -> (ExternalEventStatus, ExternalEventAvailabilityStatus) {
        let stats = event.dictionary("stats")
        if let listingCount = ExternalEventSupport.parseInt(stats?["listing_count"]), listingCount == 0 {
            if let startAtUTC, startAtUTC < Date() {
                return (.ended, .ended)
            }
            return (.soldOut, .soldOut)
        }
        if let startAtUTC, startAtUTC < Date() {
            return (.ended, .ended)
        }
        return (.onsale, .onsale)
    }

    private func seatGeekDateString(_ date: Date) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        return formatter.string(from: date)
    }

    private func seatGeekUTCDate(_ value: String?) -> Date? {
        guard let value, !value.isEmpty else { return nil }
        return ExternalEventSupport.iso8601Formatter.date(from: value)
            ?? ExternalEventSupport.iso8601NoFractionalSeconds.date(from: value)
            ?? {
                let formatter = DateFormatter()
                formatter.locale = Locale(identifier: "en_US_POSIX")
                formatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ss"
                formatter.timeZone = TimeZone(secondsFromGMT: 0)
                return formatter.date(from: value)
            }()
    }
}
