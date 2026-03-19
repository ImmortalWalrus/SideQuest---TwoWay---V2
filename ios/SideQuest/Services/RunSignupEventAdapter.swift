import CoreLocation
import Foundation

nonisolated struct RunSignupEventAdapter: ExternalEventSourceAdapter {
    let source: ExternalEventSource = .runsignup

    func fetchPage(
        query: ExternalEventQuery,
        cursor: ExternalEventSourceCursor?,
        session: URLSession,
        configuration: ExternalEventServiceConfiguration
    ) async -> ExternalEventSourceResult {
        let currentPage = max(cursor?.page ?? query.page, 1)
        let pageSize = max(query.pageSize, 8)

        guard var components = URLComponents(url: configuration.runsignupBaseURL.appendingPathComponent("rest/races"), resolvingAgainstBaseURL: false)
        else {
            return ExternalEventSourceResult(
                source: source,
                usedCache: false,
                fetchedAt: Date(),
                endpoints: [],
                note: "RunSignup base URL was invalid.",
                nextCursor: nil,
                events: []
            )
        }

        components.queryItems = [
            URLQueryItem(name: "format", value: "json"),
            URLQueryItem(name: "results_per_page", value: String(pageSize)),
            URLQueryItem(name: "page", value: String(currentPage)),
            URLQueryItem(name: "start_date", value: "today"),
            URLQueryItem(name: "sort", value: "date ASC")
        ]

        if let postalCode = query.postalCode?.trimmingCharacters(in: .whitespacesAndNewlines),
           !postalCode.isEmpty {
            let radius = max(Int(ceil(max(query.radiusMiles ?? 0, query.headlineRadiusMiles, 25))), 25)
            components.queryItems?.append(URLQueryItem(name: "zipcode", value: postalCode))
            components.queryItems?.append(URLQueryItem(name: "radius", value: String(radius)))
        } else if let city = query.city?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !city.isEmpty {
            components.queryItems?.append(URLQueryItem(name: "city", value: city))
            if let state = query.state?.trimmingCharacters(in: .whitespacesAndNewlines),
               !state.isEmpty {
                components.queryItems?.append(URLQueryItem(name: "state", value: state))
            }
        }

        guard let listURL = components.url else {
            return ExternalEventSourceResult(
                source: source,
                usedCache: false,
                fetchedAt: Date(),
                endpoints: [],
                note: "RunSignup list URL could not be built.",
                nextCursor: nil,
                events: []
            )
        }

        var endpointResults: [ExternalEventEndpointResult] = []
        var normalizedEvents: [ExternalEvent] = []
        var nextCursor: ExternalEventSourceCursor?

        do {
            let (data, response) = try await session.data(from: listURL)
            let statusCode = (response as? HTTPURLResponse)?.statusCode
            let json = try ExternalEventSupport.decodeJSONDictionary(data)
            endpointResults.append(
                ExternalEventEndpointResult(
                    label: "RunSignup race list",
                    requestURL: listURL.absoluteString,
                    responseStatusCode: statusCode,
                    worked: statusCode.map { 200..<300 ~= $0 } ?? false,
                    note: nil
                )
            )

            guard statusCode.map({ 200..<300 ~= $0 }) ?? false else {
                return ExternalEventSourceResult(
                    source: source,
                    usedCache: false,
                    fetchedAt: Date(),
                    endpoints: endpointResults,
                    note: ExternalEventIngestionError.httpStatus(statusCode ?? -1).localizedDescription,
                    nextCursor: nil,
                    events: []
                )
            }

            let races = json.array("races")
            if races.count >= pageSize {
                nextCursor = ExternalEventSourceCursor(source: source, page: currentPage + 1, pageSize: pageSize, nextToken: nil)
            }

            let raceIDs = races.prefix(min(pageSize, 10)).compactMap { wrapper -> String? in
                wrapper.dictionary("race")?.string("race_id")
            }

            await withTaskGroup(of: ([ExternalEventEndpointResult], [ExternalEvent]).self) { group in
                for raceID in raceIDs {
                    group.addTask {
                        let detailURL = configuration.runsignupBaseURL.appendingPathComponent("rest/race/\(raceID)")
                        guard var detailComponents = URLComponents(url: detailURL, resolvingAgainstBaseURL: false) else {
                            return ([], [])
                        }
                        detailComponents.queryItems = [URLQueryItem(name: "format", value: "json")]
                        guard let resolvedDetailURL = detailComponents.url else {
                            return ([], [])
                        }

                        do {
                            let (detailData, detailResponse) = try await session.data(from: resolvedDetailURL)
                            let detailStatus = (detailResponse as? HTTPURLResponse)?.statusCode
                            let endpoint = ExternalEventEndpointResult(
                                label: "RunSignup race detail \(raceID)",
                                requestURL: resolvedDetailURL.absoluteString,
                                responseStatusCode: detailStatus,
                                worked: detailStatus.map { 200..<300 ~= $0 } ?? false,
                                note: nil
                            )

                            guard detailStatus.map({ 200..<300 ~= $0 }) ?? false else {
                                return ([endpoint], [])
                            }

                            let detailJSON = try ExternalEventSupport.decodeJSONDictionary(detailData)
                            return ([endpoint], normalize(detailJSON))
                        } catch {
                            return (
                                [
                                    ExternalEventEndpointResult(
                                        label: "RunSignup race detail \(raceID)",
                                        requestURL: resolvedDetailURL.absoluteString,
                                        responseStatusCode: nil,
                                        worked: false,
                                        note: error.localizedDescription
                                    )
                                ],
                                []
                            )
                        }
                    }
                }

                for await result in group {
                    endpointResults.append(contentsOf: result.0)
                    normalizedEvents.append(contentsOf: result.1)
                }
            }
        } catch {
            endpointResults.append(
                ExternalEventEndpointResult(
                    label: "RunSignup race list",
                    requestURL: listURL.absoluteString,
                    responseStatusCode: nil,
                    worked: false,
                    note: error.localizedDescription
                )
            )
        }

        let localizedEvents = normalizedEvents.filter { event in
            guard matchesLocalQuery(event, query: query) else { return false }
            guard event.isUpcoming else { return false }
            switch event.status {
            case .cancelled, .ended:
                return false
            default:
                return true
            }
        }
        let deduped = ExternalEventIngestionService.dedupe(events: localizedEvents).events
        return ExternalEventSourceResult(
            source: source,
            usedCache: false,
            fetchedAt: Date(),
            endpoints: endpointResults,
            note: deduped.isEmpty ? "No qualifying 5K / 10K / half marathon / marathon / group run records were normalized from the current RunSignup page." : nil,
            nextCursor: nextCursor,
            events: deduped
        )
    }

    private func normalize(_ response: JSONDictionary) -> [ExternalEvent] {
        guard let race = response.dictionary("race") else { return [] }
        let timezone = race.string("timezone")
        let raceID = race.string("race_id") ?? UUID().uuidString
        let raceURL = race.string("url")
        let raceDescription = ExternalEventSupport.plainText(race.string("description"))
        let address = race.dictionary("address")
        let nextDateLocal = ExternalEventSupport.runSignupDateOnly(race.string("next_date"))
        let raceName = race.string("name") ?? "Untitled Race"
        let isRegistrationOpen = race.string("is_registration_open") == "T"

        let events = race.array("events")
        return events.compactMap { event in
            let start = ExternalEventSupport.runSignupLocalDateTime(event.string("start_time"), timezoneID: timezone)
            guard let startLocal = start.local else { return nil }
            if let nextDateLocal,
               let eventDate = startLocal.split(separator: "T").first,
               String(eventDate) != nextDateLocal
            {
                return nil
            }

            let (distanceValue, distanceUnit) = ExternalEventSupport.distanceParts(from: event.string("distance"))
            let typeInfo = ExternalEventSupport.eventTypeForRun(
                distanceValue: distanceValue,
                distanceUnit: distanceUnit,
                name: event.string("name"),
                eventType: event.string("event_type")
            )

            guard typeInfo.0 != .otherLiveEvent else { return nil }

            let end = ExternalEventSupport.runSignupLocalDateTime(event.string("end_time"), timezoneID: timezone)
            let prices = ExternalEventSupport.extractFirstPrice(event.array("registration_periods"))
            let registrationClosesUTC = event.array("registration_periods")
                .compactMap { period -> Date? in
                    let close = ExternalEventSupport.runSignupLocalDateTime(period.string("registration_closes"), timezoneID: timezone)
                    return close.utc
                }
                .max()

            let normalizedStatus = ExternalEventSupport.normalizeRunSignupStatus(
                isRegistrationOpen: isRegistrationOpen,
                startUTC: start.utc
            )

            let eventName = event.string("name") ?? raceName
            let title = eventName == raceName ? raceName : "\(raceName) — \(eventName)"

            return ExternalEvent(
                id: "\(source.rawValue):\(raceID):\(event.string("event_id") ?? UUID().uuidString)",
                source: source,
                sourceEventID: event.string("event_id") ?? UUID().uuidString,
                sourceParentID: raceID,
                sourceURL: raceURL,
                mergedSources: [source],
                title: title,
                shortDescription: ExternalEventSupport.shortened(raceDescription),
                fullDescription: raceDescription,
                category: "Race",
                subcategory: event.string("event_type"),
                eventType: typeInfo.0,
                startAtUTC: start.utc,
                endAtUTC: end.utc,
                startLocal: start.local,
                endLocal: end.local ?? nextDateLocal.map { "\($0)T23:59:59" },
                timezone: timezone,
                salesStartAtUTC: nil,
                salesEndAtUTC: registrationClosesUTC,
                venueName: address?.string("street"),
                venueID: nil,
                addressLine1: address?.string("street"),
                addressLine2: address?.string("street2"),
                city: address?.string("city"),
                state: address?.string("state"),
                postalCode: address?.string("zipcode"),
                country: address?.string("country_code"),
                latitude: nil,
                longitude: nil,
                imageURL: race.string("logo_url"),
                fallbackThumbnailAsset: ExternalEventSupport.fallbackThumbnailAsset(for: typeInfo.0),
                status: normalizedStatus.0,
                availabilityStatus: normalizedStatus.1,
                urgencyBadge: ExternalEventSupport.urgencyBadgeForRegistrationClose(registrationClosesUTC),
                socialProofCount: nil,
                socialProofLabel: nil,
                venuePopularityCount: nil,
                venueRating: nil,
                ticketProviderCount: nil,
                priceMin: prices.0,
                priceMax: prices.1,
                currency: prices.2,
                organizerName: nil,
                organizerEventCount: nil,
                organizerVerified: nil,
                tags: ExternalEventSupport.tags(from: [
                    "runsignup",
                    typeInfo.1,
                    address?.string("city"),
                    address?.string("state")
                ]),
                distanceValue: distanceValue,
                distanceUnit: distanceUnit,
                raceType: typeInfo.1,
                registrationURL: raceURL,
                ticketURL: nil,
                rawSourcePayload: ExternalEventSupport.jsonString(["race": race, "event": event])
            )
        }
    }

    private func matchesLocalQuery(_ event: ExternalEvent, query: ExternalEventQuery) -> Bool {
        let normalizedQueryState = ExternalEventSupport.normalizeStateToken(query.state)
        let normalizedEventState = ExternalEventSupport.normalizeStateToken(event.state)
        if !normalizedQueryState.isEmpty, !normalizedEventState.isEmpty, normalizedQueryState != normalizedEventState {
            return false
        }

        let normalizedQueryCity = ExternalEventSupport.normalizeToken(query.city)
        let normalizedEventCity = ExternalEventSupport.normalizeToken(event.city)

        if let queryPostalCode = normalizedPostalPrefix(query.postalCode),
           let eventPostalCode = normalizedPostalPrefix(event.postalCode),
           queryPostalCode == eventPostalCode {
            return true
        }

        if query.postalCode?.isEmpty == false,
           normalizedQueryState.isEmpty || normalizedQueryState == normalizedEventState {
            // Zipcode+radius queries are already localized upstream, so don't throw away
            // nearby suburb races just because the city/postal prefix differs.
            return true
        }

        if !normalizedQueryCity.isEmpty, !normalizedEventCity.isEmpty {
            if normalizedQueryCity == normalizedEventCity {
                return true
            }
            if ExternalEventSupport.sharesMetroArea(
                event: event,
                preferredCity: query.city,
                preferredState: query.state
            ) {
                return true
            }
        }

        if let queryLatitude = query.latitude,
           let queryLongitude = query.longitude,
           let eventLatitude = event.latitude,
           let eventLongitude = event.longitude {
            let radiusMiles = max(query.radiusMiles ?? 0, query.hyperlocalRadiusMiles, query.headlineRadiusMiles)
            let eventLocation = CLLocation(latitude: eventLatitude, longitude: eventLongitude)
            let queryLocation = CLLocation(latitude: queryLatitude, longitude: queryLongitude)
            return queryLocation.distance(from: eventLocation) / 1609.344 <= max(radiusMiles, 20)
        }

        if !normalizedQueryCity.isEmpty || !normalizedQueryState.isEmpty || query.postalCode?.isEmpty == false {
            return false
        }

        return true
    }

    private func normalizedPostalPrefix(_ postalCode: String?) -> String? {
        guard let postalCode else { return nil }
        let digits = postalCode.filter(\.isNumber)
        guard digits.count >= 3 else { return nil }
        return String(digits.prefix(3))
    }
}
