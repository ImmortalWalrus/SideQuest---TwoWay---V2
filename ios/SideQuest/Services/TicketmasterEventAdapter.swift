import Foundation

nonisolated struct TicketmasterEventAdapter: ExternalEventSourceAdapter {
    let source: ExternalEventSource = .ticketmaster

    private struct SearchChannel {
        let label: String
        let classificationName: String
        let weight: Int
    }

    func fetchPage(
        query: ExternalEventQuery,
        cursor: ExternalEventSourceCursor?,
        session: URLSession,
        configuration: ExternalEventServiceConfiguration
    ) async -> ExternalEventSourceResult {
        guard let apiKey = configuration.ticketmasterAPIKey, !apiKey.isEmpty else {
            return ExternalEventSourceResult(
                source: source,
                usedCache: false,
                fetchedAt: Date(),
                endpoints: [],
                note: ExternalEventIngestionError.missingCredential("Missing Ticketmaster API key.").localizedDescription,
                nextCursor: nil,
                events: []
            )
        }

        let currentPage = cursor?.page ?? query.page
        let channels = channels(for: query)
        let totalWeight = max(channels.reduce(0) { $0 + $1.weight }, 1)

        var endpointResults: [ExternalEventEndpointResult] = []
        var normalizedEvents: [ExternalEvent] = []
        var hasNextPage = false

        await withTaskGroup(of: ([ExternalEventEndpointResult], [ExternalEvent], Bool).self) { group in
            for channel in channels {
                group.addTask {
                    let weightedSize = max(
                        3,
                        Int(
                            (
                                Double(max(query.pageSize, 12) + channels.count)
                                * Double(channel.weight)
                            )
                            / Double(totalWeight)
                        )
                    )
                    var components = URLComponents(url: configuration.ticketmasterDiscoveryURL, resolvingAgainstBaseURL: false)
                    components?.queryItems = [
                        URLQueryItem(name: "countryCode", value: query.countryCode),
                        URLQueryItem(name: "classificationName", value: channel.classificationName),
                        URLQueryItem(name: "size", value: String(weightedSize)),
                        URLQueryItem(name: "page", value: String(currentPage)),
                        URLQueryItem(name: "sort", value: "date,asc"),
                        URLQueryItem(name: "startDateTime", value: upcomingStartDateTimeString()),
                        URLQueryItem(name: "apikey", value: apiKey)
                    ]

                    if let keyword = query.keyword, !keyword.isEmpty {
                        components?.queryItems?.append(URLQueryItem(name: "keyword", value: keyword))
                    }
                    if let latitude = query.latitude,
                       let longitude = query.longitude {
                        components?.queryItems?.append(URLQueryItem(name: "latlong", value: "\(latitude),\(longitude)"))
                        let radius = query.headlineRadiusMiles > 0 ? query.headlineRadiusMiles : (query.radiusMiles ?? 12)
                        components?.queryItems?.append(URLQueryItem(name: "radius", value: String(Int(max(2, radius)))))
                        components?.queryItems?.append(URLQueryItem(name: "unit", value: "miles"))
                    } else if let postalCode = query.postalCode, !postalCode.isEmpty {
                        components?.queryItems?.append(URLQueryItem(name: "postalCode", value: postalCode))
                    } else if let city = query.city, !city.isEmpty {
                        components?.queryItems?.append(URLQueryItem(name: "city", value: city))
                    }
                    if let state = query.state, !state.isEmpty {
                        components?.queryItems?.append(URLQueryItem(name: "stateCode", value: state))
                    }

                    guard let url = components?.url else { return ([], [], false) }

                    do {
                        let (data, response) = try await session.data(from: url)
                        let statusCode = (response as? HTTPURLResponse)?.statusCode
                        let endpoint = ExternalEventEndpointResult(
                            label: "Ticketmaster \(channel.label) discovery",
                            requestURL: url.absoluteString,
                            responseStatusCode: statusCode,
                            worked: statusCode.map { 200..<300 ~= $0 } ?? false,
                            note: nil
                        )

                        guard statusCode.map({ 200..<300 ~= $0 }) ?? false else {
                            return ([endpoint], [], false)
                        }

                        let json = try ExternalEventSupport.decodeJSONDictionary(data)
                        let pageInfo = json.dictionary("page")
                        let pageNumber = ExternalEventSupport.parseInt(pageInfo?["number"]) ?? currentPage
                        let totalPages = ExternalEventSupport.parseInt(pageInfo?["totalPages"]) ?? pageNumber
                        let nextPage = pageNumber + 1 < totalPages
                        let events = json.array(at: ["_embedded", "events"]).compactMap { event in
                            normalize(event: event)
                        }.filter { event in
                            query.includePast || event.isUpcoming
                        }
                        return ([endpoint], events, nextPage)
                    } catch {
                        return (
                            [
                                ExternalEventEndpointResult(
                                    label: "Ticketmaster \(channel.label) discovery",
                                    requestURL: url.absoluteString,
                                    responseStatusCode: nil,
                                    worked: false,
                                    note: error.localizedDescription
                                )
                            ],
                            [],
                            false
                        )
                    }
                }
            }

            for await result in group {
                endpointResults.append(contentsOf: result.0)
                normalizedEvents.append(contentsOf: result.1)
                hasNextPage = hasNextPage || result.2
            }
        }

        let deduped = ExternalEventIngestionService.dedupe(events: normalizedEvents).events
        return ExternalEventSourceResult(
            source: source,
            usedCache: false,
            fetchedAt: Date(),
            endpoints: endpointResults,
            note: deduped.isEmpty ? "No relevant Ticketmaster entertainment events were normalized from the current page." : nil,
            nextCursor: hasNextPage ? ExternalEventSourceCursor(source: source, page: currentPage + 1, pageSize: query.pageSize, nextToken: nil) : nil,
            events: deduped
        )
    }

    private func normalize(event: JSONDictionary) -> ExternalEvent? {
        let title = event.string("name") ?? "Untitled Ticketmaster Event"
        let classifications = event.array("classifications")
        guard let eventType = ExternalEventSupport.ticketmasterEventType(from: classifications, title: title) else {
            return nil
        }

        let venue = event.array(at: ["_embedded", "venues"]).first
        let venueLocation = venue?.dictionary("location")
        let description = ExternalEventSupport.plainText(event.string("description") ?? event.string("info") ?? event.string("pleaseNote"))
        let primaryClassification = classifications.first
        let segment = primaryClassification?.dictionary("segment")?.string("name")
        let genre = primaryClassification?.dictionary("genre")?.string("name")
        let subGenre = primaryClassification?.dictionary("subGenre")?.string("name")

        let startUTC = ExternalEventSupport.ticketmasterDate(event.string(at: ["dates", "start", "dateTime"]))
        let endUTC = ExternalEventSupport.ticketmasterDate(event.string(at: ["dates", "end", "dateTime"]))
        let timezone = event.string(at: ["dates", "timezone"]) ?? venue?.string("timezone")
        let salesStartUTC = ExternalEventSupport.ticketmasterDate(event.string(at: ["sales", "public", "startDateTime"]))
        let salesEndUTC = ExternalEventSupport.ticketmasterDate(event.string(at: ["sales", "public", "endDateTime"]))
        let localStart = ExternalEventSupport.combineLocalDateAndTime(
            date: event.string(at: ["dates", "start", "localDate"]),
            time: event.string(at: ["dates", "start", "localTime"])
        )
        let localEnd = ExternalEventSupport.combineLocalDateAndTime(
            date: event.string(at: ["dates", "end", "localDate"]) ?? event.string(at: ["dates", "start", "localDate"]),
            time: event.string(at: ["dates", "end", "localTime"])
        )

        let normalizedStatus = ExternalEventSupport.normalizeTicketmasterStatus(
            statusCode: event.string(at: ["dates", "status", "code"]),
            eventStartUTC: startUTC
        )
        let subcategory = [genre, subGenre].compactMap { $0 }.joined(separator: " / ")

        return ExternalEvent(
            id: "\(source.rawValue):\(event.string("id") ?? UUID().uuidString)",
            source: source,
            sourceEventID: event.string("id") ?? UUID().uuidString,
            sourceParentID: nil,
            sourceURL: event.string("url"),
            mergedSources: [source],
            title: title,
            shortDescription: ExternalEventSupport.shortened(description),
            fullDescription: description,
            category: segment,
            subcategory: subcategory.isEmpty ? nil : subcategory,
            eventType: eventType,
            startAtUTC: startUTC,
            endAtUTC: endUTC,
            startLocal: localStart,
            endLocal: localEnd,
            timezone: timezone,
            salesStartAtUTC: salesStartUTC,
            salesEndAtUTC: salesEndUTC,
            venueName: venue?.string("name"),
            venueID: venue?.string("id"),
            addressLine1: venue?.dictionary("address")?.string("line1"),
            addressLine2: venue?.dictionary("address")?.string("line2"),
            city: venue?.dictionary("city")?.string("name"),
            state: venue?.dictionary("state")?.string("stateCode") ?? venue?.dictionary("state")?.string("name"),
            postalCode: venue?.string("postalCode"),
            country: venue?.dictionary("country")?.string("countryCode") ?? venue?.dictionary("country")?.string("name"),
            latitude: ExternalEventSupport.parseDouble(venueLocation?["latitude"]),
            longitude: ExternalEventSupport.parseDouble(venueLocation?["longitude"]),
            imageURL: ExternalEventSupport.preferredImageURL(from: event.array("images")),
            fallbackThumbnailAsset: ExternalEventSupport.fallbackThumbnailAsset(for: eventType),
            status: normalizedStatus.0,
            availabilityStatus: normalizedStatus.1,
            urgencyBadge: ExternalEventSupport.urgencyBadgeForSalesEndingSoon(salesEndUTC),
            socialProofCount: nil,
            socialProofLabel: nil,
            venuePopularityCount: nil,
            venueRating: nil,
            ticketProviderCount: nil,
            priceMin: nil,
            priceMax: nil,
            currency: nil,
            organizerName: event.dictionary("promoter")?.string("name"),
            organizerEventCount: nil,
            organizerVerified: nil,
            tags: ExternalEventSupport.tags(from: [segment, genre, subGenre, eventType.rawValue]),
            distanceValue: nil,
            distanceUnit: nil,
            raceType: nil,
            registrationURL: nil,
            ticketURL: event.string("url"),
            rawSourcePayload: ExternalEventSupport.jsonString(event)
        )
    }

    private func upcomingStartDateTimeString() -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        return formatter.string(from: Date())
    }

    private func channels(for query: ExternalEventQuery) -> [SearchChannel] {
        switch query.discoveryIntent {
        case .biggestTonight:
            return [
                SearchChannel(label: "sports", classificationName: "sports", weight: 6),
                SearchChannel(label: "music", classificationName: "music", weight: 3),
                SearchChannel(label: "arts", classificationName: "arts & theatre", weight: 2),
                SearchChannel(label: "comedy", classificationName: "comedy", weight: 1)
            ]
        case .exclusiveHot:
            return [
                SearchChannel(label: "music", classificationName: "music", weight: 4),
                SearchChannel(label: "arts", classificationName: "arts & theatre", weight: 2),
                SearchChannel(label: "comedy", classificationName: "comedy", weight: 1),
                SearchChannel(label: "sports", classificationName: "sports", weight: 2)
            ]
        case .lastMinutePlans:
            return [
                SearchChannel(label: "sports", classificationName: "sports", weight: 5),
                SearchChannel(label: "music", classificationName: "music", weight: 3),
                SearchChannel(label: "arts", classificationName: "arts & theatre", weight: 2),
                SearchChannel(label: "comedy", classificationName: "comedy", weight: 1)
            ]
        case .nearbyWorthIt:
            return [
                SearchChannel(label: "sports", classificationName: "sports", weight: 4),
                SearchChannel(label: "music", classificationName: "music", weight: 3),
                SearchChannel(label: "arts", classificationName: "arts & theatre", weight: 2),
                SearchChannel(label: "comedy", classificationName: "comedy", weight: 1)
            ]
        }
    }
}
