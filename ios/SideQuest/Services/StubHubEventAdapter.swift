import CoreLocation
import Foundation

nonisolated struct StubHubEventAdapter: ExternalEventSourceAdapter {
    let source: ExternalEventSource = .stubHub

    private struct SearchChannel: Sendable {
        let label: String
        let searchQuery: String
        let category: String
        let location: String
        let maxItems: Int
    }

    func fetchPage(
        query: ExternalEventQuery,
        cursor: ExternalEventSourceCursor?,
        session: URLSession,
        configuration: ExternalEventServiceConfiguration
    ) async -> ExternalEventSourceResult {
        guard let token = configuration.apifyAPIToken, !token.isEmpty else {
            return ExternalEventSourceResult(
                source: source,
                usedCache: false,
                fetchedAt: Date(),
                endpoints: [],
                note: ExternalEventIngestionError.missingCredential("Missing Apify API token for StubHub.").localizedDescription,
                nextCursor: nil,
                events: []
            )
        }

        guard let runURL = buildRunURL(configuration: configuration, token: token) else {
            return ExternalEventSourceResult(
                source: source,
                usedCache: false,
                fetchedAt: Date(),
                endpoints: [],
                note: "Could not build StubHub actor URL.",
                nextCursor: nil,
                events: []
            )
        }

        let channels = buildChannels(for: query)
        guard !channels.isEmpty else {
            return ExternalEventSourceResult(
                source: source,
                usedCache: false,
                fetchedAt: Date(),
                endpoints: [],
                note: "StubHub could not derive a usable geography query from the current location.",
                nextCursor: nil,
                events: []
            )
        }

        var endpoints: [ExternalEventEndpointResult] = []
        var normalizedEvents: [ExternalEvent] = []

        await withTaskGroup(of: (ExternalEventEndpointResult, [ExternalEvent]).self) { group in
            for channel in channels {
                group.addTask {
                    await fetchChannel(
                        channel,
                        query: query,
                        session: session,
                        configuration: configuration,
                        runURL: runURL
                    )
                }
            }

            for await result in group {
                endpoints.append(result.0)
                normalizedEvents.append(contentsOf: result.1.filter { query.includePast || $0.isUpcoming })
            }
        }

        let deduped = ExternalEventIngestionService.dedupe(events: normalizedEvents).events
        let note: String?
        if deduped.isEmpty {
            note = endpoints.contains(where: { !$0.worked })
                ? "StubHub actor calls were made but did not produce normalized local results."
                : "StubHub returned no events for the current geography query."
        } else {
            note = nil
        }

        return ExternalEventSourceResult(
            source: source,
            usedCache: false,
            fetchedAt: Date(),
            endpoints: endpoints.sorted { $0.label < $1.label },
            note: note,
            nextCursor: nil,
            events: deduped
        )
    }

    private func fetchChannel(
        _ channel: SearchChannel,
        query: ExternalEventQuery,
        session: URLSession,
        configuration: ExternalEventServiceConfiguration,
        runURL: URL
    ) async -> (ExternalEventEndpointResult, [ExternalEvent]) {
        var payload: [String: Any] = [
            "searchQuery": channel.searchQuery,
            "category": channel.category,
            "location": channel.location,
            "maxItems": channel.maxItems
        ]

        var request = URLRequest(url: runURL)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try? JSONSerialization.data(withJSONObject: payload, options: [.sortedKeys])

        do {
            let (data, response) = try await session.data(for: request)
            let statusCode = (response as? HTTPURLResponse)?.statusCode
            guard statusCode.map({ 200..<300 ~= $0 }) ?? false else {
                return (
                    ExternalEventEndpointResult(
                        label: "StubHub \(channel.label)",
                        requestURL: runURL.absoluteString,
                        responseStatusCode: statusCode,
                        worked: false,
                        note: String(data: data, encoding: .utf8)
                    ),
                    []
                )
            }

            let parsed = try JSONSerialization.jsonObject(with: data)
            let items = parsed as? [JSONDictionary] ?? []
            let events = items
                .compactMap { normalize(item: $0, categoryPath: channel.category, query: query) }
                .filter { isReasonablyLocal($0, query: query) }
            return (
                ExternalEventEndpointResult(
                    label: "StubHub \(channel.label)",
                    requestURL: runURL.absoluteString,
                    responseStatusCode: statusCode,
                    worked: true,
                    note: items.isEmpty ? "No StubHub items were returned for this geography channel." : nil
                ),
                events
            )
        } catch {
            return (
                ExternalEventEndpointResult(
                    label: "StubHub \(channel.label)",
                    requestURL: runURL.absoluteString,
                    responseStatusCode: nil,
                    worked: false,
                    note: error.localizedDescription
                ),
                []
            )
        }
    }

    private func buildChannels(for query: ExternalEventQuery) -> [SearchChannel] {
        let locationPhrase = [query.city, query.state]
            .compactMap { value in
                guard let value, !value.isEmpty else { return nil }
                return value
            }
            .joined(separator: ", ")
        guard !locationPhrase.isEmpty else { return [] }

        let baseItems = max(4, min(query.pageSize, 6))

        return [
            SearchChannel(
                label: "nba",
                searchQuery: "nba",
                category: "nba",
                location: locationPhrase,
                maxItems: baseItems
            ),
            SearchChannel(
                label: "concerts",
                searchQuery: "concerts",
                category: "concerts",
                location: locationPhrase,
                maxItems: baseItems
            ),
            SearchChannel(
                label: "theater",
                searchQuery: "theater",
                category: "theater",
                location: locationPhrase,
                maxItems: max(3, baseItems / 2)
            ),
            SearchChannel(
                label: "comedy",
                searchQuery: "comedy",
                category: "comedy",
                location: locationPhrase,
                maxItems: max(3, baseItems / 2)
            ),
            SearchChannel(
                label: "soccer",
                searchQuery: "soccer",
                category: "soccer",
                location: locationPhrase,
                maxItems: max(3, baseItems / 2)
            )
        ]
    }

    private func buildRunURL(configuration: ExternalEventServiceConfiguration, token: String) -> URL? {
        var components = URLComponents(
            url: configuration.apifyBaseURL.appendingPathComponent("v2/acts/\(configuration.stubHubActorID)/run-sync-get-dataset-items"),
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

    private func normalize(item: JSONDictionary, categoryPath: String, query: ExternalEventQuery) -> ExternalEvent? {
        if let error = item.string("error"), !error.isEmpty {
            return nil
        }

        let title = firstString(
            from: item,
            keys: ["event_name", "eventName", "title", "name", "event_title", "listingTitle"]
        ) ?? "Untitled StubHub Event"
        let ticketURL = firstString(from: item, keys: ["url", "eventUrl", "listingUrl", "link"])
        let venue = item.dictionary("venue")
        let location = item.dictionary("location")
        let coordinates = item.dictionary("coordinates")
        let venueName = firstString(from: venue ?? [:], keys: ["name", "venueName", "title"])
            ?? firstString(from: item, keys: ["venueName", "venue"])
            ?? venueNameFromURL(ticketURL)
        let city = firstString(from: location ?? [:], keys: ["city"])
            ?? firstString(from: item, keys: ["city"])
            ?? query.city
        let state = firstString(from: location ?? [:], keys: ["state", "stateCode"])
            ?? firstString(from: item, keys: ["state", "stateCode"])
            ?? query.state
        let stubDate = item.dictionary("date")
        let startISO = firstString(
            from: item,
            keys: ["dateTimeIso", "eventDateIso", "startDateTime", "startDate", "eventDate"]
        ) ?? isoFromStubHubDate(stubDate)
        let startAtUTC = ExternalEventSupport.ticketmasterDate(startISO)
        let localStart = firstString(
            from: item,
            keys: ["localDateTime", "dateTimeLocal", "displayDateTime", "dateTimeText"]
        ) ?? localDateText(stubDate) ?? startISO
        let status = availability(for: item, startAtUTC: startAtUTC)
        let category = firstString(from: item, keys: ["category", "categoryName"]) ?? categoryPath.capitalized
        let subcategory = firstString(from: item, keys: ["subcategory", "genre", "eventType"])
        let performers = stringArray(from: item, keys: ["performers", "teams", "artists"])
        let imageURL = firstString(from: item, keys: ["imageUrl", "image", "imageURL", "heroImageUrl"])
        let description = ExternalEventSupport.plainText(firstString(from: item, keys: ["description", "summary", "subtitle"]))
        let popularity = ExternalEventSupport.parseDouble(item["popularityScore"])
            ?? ExternalEventSupport.parseDouble(item["score"])
            ?? ExternalEventSupport.parseDouble(item["listingCount"])
            ?? ExternalEventSupport.parseDouble(item["rank"])
        let urgency = urgencyBadge(for: item)
        let pointCoordinates = coordinatesFromURL(ticketURL)

        return ExternalEvent(
            id: "\(source.rawValue):\(firstString(from: item, keys: ["id", "eventId", "event_id"]) ?? stableIdentifier(title: title, venueName: venueName, start: startISO))",
            source: source,
            sourceEventID: firstString(from: item, keys: ["id", "eventId", "event_id"]) ?? stableIdentifier(title: title, venueName: venueName, start: startISO),
            sourceParentID: firstString(from: item, keys: ["venueId", "venue_id"]),
            sourceURL: ticketURL,
            mergedSources: [source],
            title: title,
            shortDescription: ExternalEventSupport.shortened(description),
            fullDescription: description,
            category: category,
            subcategory: subcategory,
            eventType: normalizedType(category: category, subcategory: subcategory, title: title),
            startAtUTC: startAtUTC,
            endAtUTC: ExternalEventSupport.ticketmasterDate(firstString(from: item, keys: ["endDateTime", "endDateIso"])),
            startLocal: localStart,
            endLocal: firstString(from: item, keys: ["endLocalDateTime", "endDateTimeLocal"]),
            timezone: nil,
            salesStartAtUTC: nil,
            salesEndAtUTC: nil,
            venueName: venueName,
            venueID: firstString(from: venue ?? [:], keys: ["id", "venueId"]) ?? firstString(from: item, keys: ["venueId", "venue_id"]),
            addressLine1: firstString(from: location ?? [:], keys: ["address1", "address", "line1"]) ?? firstString(from: item, keys: ["address"]),
            addressLine2: firstString(from: location ?? [:], keys: ["address2", "line2"]),
            city: city,
            state: state,
            postalCode: firstString(from: location ?? [:], keys: ["postalCode", "zip", "zipCode"]),
            country: firstString(from: location ?? [:], keys: ["country"]) ?? firstString(from: item, keys: ["country"]),
            latitude: ExternalEventSupport.parseDouble(coordinates?["latitude"])
                ?? ExternalEventSupport.parseDouble(location?["latitude"])
                ?? ExternalEventSupport.parseDouble(item["latitude"])
                ?? pointCoordinates?.0,
            longitude: ExternalEventSupport.parseDouble(coordinates?["longitude"])
                ?? ExternalEventSupport.parseDouble(location?["longitude"])
                ?? ExternalEventSupport.parseDouble(item["longitude"])
                ?? pointCoordinates?.1,
            imageURL: imageURL,
            fallbackThumbnailAsset: ExternalEventSupport.fallbackThumbnailAsset(for: normalizedType(category: category, subcategory: subcategory, title: title)),
            status: status.0,
            availabilityStatus: status.1,
            urgencyBadge: urgency,
            socialProofCount: ExternalEventSupport.parseInt(item["listingCount"]),
            socialProofLabel: socialProofLabel(from: item),
            venuePopularityCount: nil,
            venueRating: nil,
            ticketProviderCount: 1,
            priceMin: ExternalEventSupport.parseDouble(item["minPrice"]) ?? ExternalEventSupport.parseDouble(item["lowestPrice"]),
            priceMax: ExternalEventSupport.parseDouble(item["maxPrice"]) ?? ExternalEventSupport.parseDouble(item["highestPrice"]),
            currency: firstString(from: item, keys: ["currency", "currencyCode"]),
            organizerName: "StubHub",
            organizerEventCount: nil,
            organizerVerified: true,
            tags: ExternalEventSupport.tags(from: [category, subcategory, city, state] + performers),
            distanceValue: nil,
            distanceUnit: nil,
            raceType: nil,
            registrationURL: nil,
            ticketURL: ticketURL,
            rawSourcePayload: ExternalEventSupport.jsonString(item),
            sourceType: .scraped,
            recordKind: .event,
            neighborhood: firstString(from: location ?? [:], keys: ["neighborhood"]),
            reservationURL: nil,
            artistsOrTeams: performers,
            ageMinimum: nil,
            doorPolicyText: nil,
            dressCodeText: nil,
            guestListAvailable: nil,
            bottleServiceAvailable: nil,
            tableMinPrice: nil,
            coverPrice: nil,
            openingHoursText: nil,
            sourceConfidence: 0.52,
            popularityScoreRaw: popularity,
            venueSignalScore: popularity,
            exclusivityScore: nil,
            trendingScore: popularity,
            crossSourceConfirmationScore: nil,
            distanceFromUser: nil
        )
    }

    private func normalizedType(category: String?, subcategory: String?, title: String) -> ExternalEventType {
        let haystack = ExternalEventSupport.normalizeToken(
            [category, subcategory, title].compactMap { $0 }.joined(separator: " ")
        )
        if haystack.contains("sport")
            || haystack.contains("nba")
            || haystack.contains("mlb")
            || haystack.contains("nfl")
            || haystack.contains("nhl")
            || haystack.contains("soccer")
            || haystack.contains("wwe")
            || haystack.contains("ufc")
            || haystack.contains("aew")
        {
            return .sportsEvent
        }
        if haystack.contains("concert")
            || haystack.contains("music")
            || haystack.contains("band")
            || haystack.contains("tour")
        {
            return .concert
        }
        if haystack.contains("club")
            || haystack.contains("party")
            || haystack.contains("nightlife")
            || haystack.contains("dj")
        {
            return .partyNightlife
        }
        if haystack.contains("theater") || haystack.contains("theatre") || haystack.contains("comedy") {
            return .weekendActivity
        }
        return .otherLiveEvent
    }

    private func availability(for item: JSONDictionary, startAtUTC: Date?) -> (ExternalEventStatus, ExternalEventAvailabilityStatus) {
        let haystack = ExternalEventSupport.normalizeToken(
            [
                firstString(from: item, keys: ["status", "availabilityStatus"]),
                firstString(from: item, keys: ["urgencyText", "countdownText", "availabilityMessage"])
            ]
            .compactMap { $0 }
            .joined(separator: " ")
        )
        if haystack.contains("sold out") {
            return (.soldOut, .soldOut)
        }
        if let startAtUTC, startAtUTC < Date() {
            return (.ended, .ended)
        }
        return (.onsale, .onsale)
    }

    private func urgencyBadge(for item: JSONDictionary) -> ExternalEventUrgencyBadge? {
        let haystack = ExternalEventSupport.normalizeToken(
            [
                firstString(from: item, keys: ["urgencyText", "countdownText", "availabilityMessage"]),
                firstString(from: item, keys: ["status"])
            ]
            .compactMap { $0 }
            .joined(separator: " ")
        )
        if haystack.contains("few left") || haystack.contains("selling fast") {
            return .sellingFast
        }
        if haystack.contains("almost sold out") {
            return .almostSoldOut
        }
        return nil
    }

    private func socialProofLabel(from item: JSONDictionary) -> String? {
        if let listingCount = ExternalEventSupport.parseInt(item["listingCount"]), listingCount > 0 {
            return "\(listingCount)+ listings"
        }
        return firstString(from: item, keys: ["availabilityMessage", "countdownText"])
    }

    private func stableIdentifier(title: String, venueName: String?, start: String?) -> String {
        let seed = "\(title)|\(venueName ?? "")|\(start ?? "")"
        return ExternalEventSupport.normalizeToken(seed).replacingOccurrences(of: " ", with: "-")
    }

    private func isReasonablyLocal(_ event: ExternalEvent, query: ExternalEventQuery) -> Bool {
        if let queryLatitude = query.latitude,
           let queryLongitude = query.longitude,
           let latitude = event.latitude,
           let longitude = event.longitude {
            let eventLocation = CLLocation(latitude: latitude, longitude: longitude)
            let queryLocation = CLLocation(latitude: queryLatitude, longitude: queryLongitude)
            let miles = queryLocation.distance(from: eventLocation) / 1609.344
            return miles <= max(query.headlineRadiusMiles * 1.5, 30)
        }

        let queryCity = ExternalEventSupport.normalizeToken(query.city)
        let queryState = ExternalEventSupport.normalizeStateToken(query.state)
        let eventCity = ExternalEventSupport.normalizeToken(event.city)
        let eventState = ExternalEventSupport.normalizeStateToken(event.state)

        if !eventCity.isEmpty, !queryCity.isEmpty, eventCity == queryCity {
            return true
        }
        if !eventState.isEmpty, !queryState.isEmpty, eventState != queryState {
            return false
        }
        return true
    }

    private func isoFromStubHubDate(_ date: JSONDictionary?) -> String? {
        guard
            let date,
            let month = ExternalEventSupport.parseInt(date["month"]),
            let day = ExternalEventSupport.parseInt(date["day"]),
            let year = ExternalEventSupport.parseInt(date["year"])
        else {
            return nil
        }

        let timeText = date.string("time") ?? "8:00 PM"
        let parsedTime = parseTime(timeText) ?? (hour: 20, minute: 0)
        return String(
            format: "%04d-%02d-%02dT%02d:%02d:00",
            year,
            month,
            day,
            parsedTime.hour,
            parsedTime.minute
        )
    }

    private func localDateText(_ date: JSONDictionary?) -> String? {
        guard
            let date,
            let text = date.string("text"),
            let time = date.string("time")
        else {
            return nil
        }
        return "\(text) \(time)"
    }

    private func parseTime(_ value: String) -> (hour: Int, minute: Int)? {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        let parts = trimmed.split(separator: " ")
        guard parts.count == 2 else { return nil }
        let hm = parts[0].split(separator: ":")
        guard hm.count == 2, let hourValue = Int(hm[0]), let minuteValue = Int(hm[1]) else { return nil }
        let meridiem = String(parts[1])
        var hour = hourValue % 12
        if meridiem == "PM" {
            hour += 12
        }
        return (hour, minuteValue)
    }

    private func coordinatesFromURL(_ value: String?) -> (Double, Double)? {
        guard
            let value,
            let components = URLComponents(string: value),
            let lat = components.queryItems?.first(where: { $0.name == "lt" })?.value,
            let lng = components.queryItems?.first(where: { $0.name == "lg" })?.value,
            let latitude = Double(lat),
            let longitude = Double(lng)
        else {
            return nil
        }
        return (latitude, longitude)
    }

    private func venueNameFromURL(_ value: String?) -> String? {
        guard
            let value,
            let components = URLComponents(string: value),
            let path = components.path.removingPercentEncoding
        else {
            return nil
        }
        let trimmed = path
            .trimmingCharacters(in: CharacterSet(charactersIn: "/"))
            .split(separator: "/")
            .first
        guard let trimmed else { return nil }
        let slug = String(trimmed)
        guard slug != "event" else { return nil }
        return slug
            .replacingOccurrences(of: "-", with: " ")
            .split(separator: " ")
            .map { $0.capitalized }
            .joined(separator: " ")
    }

    private func firstString(from dictionary: JSONDictionary, keys: [String]) -> String? {
        for key in keys {
            if let value = dictionary.string(key), !value.isEmpty {
                return value
            }
        }
        return nil
    }

    private func stringArray(from dictionary: JSONDictionary, keys: [String]) -> [String] {
        for key in keys {
            if let values = dictionary[key] as? [String], !values.isEmpty {
                return values
            }
            if let values = dictionary[key] as? [JSONDictionary] {
                let names = values.compactMap {
                    $0.string("name") ?? $0.string("title") ?? $0.string("team") ?? $0.string("artist")
                }
                if !names.isEmpty {
                    return names
                }
            }
        }
        return []
    }
}
