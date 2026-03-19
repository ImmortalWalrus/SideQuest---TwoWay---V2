import Foundation

nonisolated struct SportsScheduleEventAdapter: ExternalEventSourceAdapter {
    let source: ExternalEventSource = .sportsSchedule

    private struct Channel: Sendable {
        let label: String
        let sport: String
    }

    private let channels: [Channel] = [
        Channel(label: "basketball", sport: "Basketball"),
        Channel(label: "soccer", sport: "Soccer"),
        Channel(label: "american-football", sport: "American Football"),
        Channel(label: "baseball", sport: "Baseball"),
        Channel(label: "ice-hockey", sport: "Ice Hockey"),
        Channel(label: "combat-sports", sport: "Fighting")
    ]

    func fetchPage(
        query: ExternalEventQuery,
        cursor: ExternalEventSourceCursor?,
        session: URLSession,
        configuration: ExternalEventServiceConfiguration
    ) async -> ExternalEventSourceResult {
        let offsetDays = max(cursor?.page ?? query.page, 0)
        let targetDate = Calendar(identifier: .gregorian).date(byAdding: .day, value: offsetDays, to: Date()) ?? Date()
        let dateString = dayString(targetDate)

        var endpoints: [ExternalEventEndpointResult] = []
        var normalized: [ExternalEvent] = []

        await withTaskGroup(of: (ExternalEventEndpointResult, [ExternalEvent]).self) { group in
            for channel in channels {
                group.addTask {
                    await fetchChannel(
                        channel,
                        dateString: dateString,
                        query: query,
                        session: session,
                        configuration: configuration
                    )
                }
            }

            for await result in group {
                endpoints.append(result.0)
                normalized.append(contentsOf: result.1)
            }
        }

        let deduped = ExternalEventIngestionService.dedupe(events: normalized).events
        return ExternalEventSourceResult(
            source: source,
            usedCache: false,
            fetchedAt: Date(),
            endpoints: endpoints.sorted { $0.label < $1.label },
            note: deduped.isEmpty ? "Sports schedule provider returned no local games for the current discovery date." : nil,
            nextCursor: offsetDays < 2 ? ExternalEventSourceCursor(source: source, page: offsetDays + 1, pageSize: query.pageSize, nextToken: nil) : nil,
            events: deduped
        )
    }

    private func fetchChannel(
        _ channel: Channel,
        dateString: String,
        query: ExternalEventQuery,
        session: URLSession,
        configuration: ExternalEventServiceConfiguration
    ) async -> (ExternalEventEndpointResult, [ExternalEvent]) {
        var components = URLComponents(
            url: configuration.sportsScheduleBaseURL.appendingPathComponent("eventsday.php"),
            resolvingAgainstBaseURL: false
        )
        components?.queryItems = [
            URLQueryItem(name: "d", value: dateString),
            URLQueryItem(name: "s", value: channel.sport)
        ]
        guard let url = components?.url else {
            return (
                ExternalEventEndpointResult(
                    label: "Sports schedule \(channel.label)",
                    requestURL: configuration.sportsScheduleBaseURL.absoluteString,
                    responseStatusCode: nil,
                    worked: false,
                    note: "Could not build sports schedule request."
                ),
                []
            )
        }

        do {
            let (data, response) = try await session.data(from: url)
            let statusCode = (response as? HTTPURLResponse)?.statusCode
            let endpoint = ExternalEventEndpointResult(
                label: "Sports schedule \(channel.label)",
                requestURL: url.absoluteString,
                responseStatusCode: statusCode,
                worked: statusCode.map { 200..<300 ~= $0 } ?? false,
                note: nil
            )

            guard statusCode.map({ 200..<300 ~= $0 }) ?? false else {
                return (endpoint, [])
            }

            let json = try ExternalEventSupport.decodeJSONDictionary(data)
            let events = json.array("events")
                .compactMap { normalize(event: $0, sport: channel.sport) }
                .filter { event in
                    (query.includePast || event.isUpcoming) && matchesLocation(event, query: query)
                }
            return (endpoint, events)
        } catch {
            return (
                ExternalEventEndpointResult(
                    label: "Sports schedule \(channel.label)",
                    requestURL: url.absoluteString,
                    responseStatusCode: nil,
                    worked: false,
                    note: error.localizedDescription
                ),
                []
            )
        }
    }

    private func normalize(event: JSONDictionary, sport: String) -> ExternalEvent? {
        let title = [event.string("strHomeTeam"), event.string("strAwayTeam")]
            .compactMap { $0 }
            .joined(separator: " vs ")
        let eventTitle = title.isEmpty ? (event.string("strEvent") ?? "Untitled Sports Event") : title
        let timestamp = sportsTimestamp(event)
        let venueName = event.string("strVenue")
        let city = event.string("strCity")
        let country = event.string("strCountry")
        let league = event.string("strLeague")
        let teams = [event.string("strHomeTeam"), event.string("strAwayTeam")].compactMap { $0 }

        return ExternalEvent(
            id: "\(source.rawValue):\(event.string("idEvent") ?? UUID().uuidString)",
            source: source,
            sourceEventID: event.string("idEvent") ?? UUID().uuidString,
            sourceParentID: event.string("idLeague"),
            sourceURL: event.string("strVideo"),
            mergedSources: [source],
            title: eventTitle,
            shortDescription: ExternalEventSupport.shortened([league, venueName, city].compactMap { $0 }.joined(separator: " · ")),
            fullDescription: nil,
            category: sport,
            subcategory: league,
            eventType: .sportsEvent,
            startAtUTC: timestamp.utc,
            endAtUTC: nil,
            startLocal: timestamp.local,
            endLocal: nil,
            timezone: timestamp.timezoneID,
            salesStartAtUTC: nil,
            salesEndAtUTC: nil,
            venueName: venueName,
            venueID: event.string("idVenue"),
            addressLine1: venueName,
            addressLine2: nil,
            city: city,
            state: event.string("strState"),
            postalCode: nil,
            country: country,
            latitude: ExternalEventSupport.parseDouble(event["floatVenueLat"]),
            longitude: ExternalEventSupport.parseDouble(event["floatVenueLong"]),
            imageURL: event.string("strThumb") ?? event.string("strBanner"),
            fallbackThumbnailAsset: ExternalEventSupport.fallbackThumbnailAsset(for: .sportsEvent),
            status: timestamp.utc.map { $0 < Date() ? .ended : .scheduled } ?? .scheduled,
            availabilityStatus: timestamp.utc.map { $0 < Date() ? .ended : .available } ?? .available,
            urgencyBadge: nil,
            socialProofCount: nil,
            socialProofLabel: nil,
            venuePopularityCount: nil,
            venueRating: nil,
            ticketProviderCount: nil,
            priceMin: nil,
            priceMax: nil,
            currency: nil,
            organizerName: league,
            organizerEventCount: nil,
            organizerVerified: nil,
            tags: ExternalEventSupport.tags(from: [sport, league, teams.joined(separator: ", ")]),
            distanceValue: nil,
            distanceUnit: nil,
            raceType: nil,
            registrationURL: nil,
            ticketURL: nil,
            rawSourcePayload: ExternalEventSupport.jsonString(event),
            sourceType: .sportsScheduleAPI,
            recordKind: .event,
            neighborhood: nil,
            reservationURL: nil,
            artistsOrTeams: teams,
            ageMinimum: nil,
            doorPolicyText: nil,
            dressCodeText: nil,
            guestListAvailable: nil,
            bottleServiceAvailable: nil,
            tableMinPrice: nil,
            coverPrice: nil,
            openingHoursText: nil,
            sourceConfidence: 0.72,
            popularityScoreRaw: nil,
            venueSignalScore: nil,
            exclusivityScore: nil,
            trendingScore: nil,
            crossSourceConfirmationScore: nil,
            distanceFromUser: nil
        )
    }

    private func matchesLocation(_ event: ExternalEvent, query: ExternalEventQuery) -> Bool {
        guard query.city != nil || query.state != nil else { return true }
        if let city = query.city, !city.isEmpty,
           ExternalEventSupport.normalizeToken(city) == ExternalEventSupport.normalizeToken(event.city) {
            return true
        }
        if let state = query.state, !state.isEmpty,
           ExternalEventSupport.normalizeStateToken(state) == ExternalEventSupport.normalizeStateToken(event.state) {
            return true
        }
        return false
    }

    private func sportsTimestamp(_ event: JSONDictionary) -> (utc: Date?, local: String?, timezoneID: String?) {
        if let timestamp = event.string("strTimestamp"), let parsed = ExternalEventSupport.iso8601NoFractionalSeconds.date(from: timestamp) {
            let timezoneID = "UTC"
            return (parsed, ExternalEventSupport.combineLocalDateAndTime(date: dayString(parsed), time: timeString(parsed)), timezoneID)
        }

        if let localDate = event.string("dateEvent"),
           let localTime = event.string("strTime"),
           let timestamp = parseLocal(date: localDate, time: localTime)
        {
            return (timestamp, "\(localDate)T\(localTime)", "UTC")
        }

        return (nil, nil, nil)
    }

    private func parseLocal(date: String, time: String) -> Date? {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        return formatter.date(from: "\(date) \(time)")
    }

    private func dayString(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        return formatter.string(from: date)
    }

    private func timeString(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "HH:mm:ss"
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        return formatter.string(from: date)
    }
}
