import Foundation

nonisolated struct GoogleEventsEventAdapter: ExternalEventSourceAdapter {
    let source: ExternalEventSource = .googleEvents

    private let searchBaseURL = URL(string: "https://www.google.com/search")!
    private let maxRetryCount = 3
    private let interChannelDelayNanoseconds: UInt64 = 250_000_000

    private struct SearchChannel: Sendable {
        let label: String
        let queryText: String
    }

    private struct HTMLFetchResult: Sendable {
        let statusCode: Int?
        let html: String?
        let note: String?
    }

    func fetchPage(
        query: ExternalEventQuery,
        cursor: ExternalEventSourceCursor?,
        session: URLSession,
        configuration: ExternalEventServiceConfiguration
    ) async -> ExternalEventSourceResult {
        let timezoneID = timezoneIdentifier(for: query)
        let channels = buildChannels(for: query)
        guard !channels.isEmpty else {
            return ExternalEventSourceResult(
                source: source,
                usedCache: false,
                fetchedAt: Date(),
                endpoints: [],
                note: "Google Events could not build a search query for the current location.",
                nextCursor: nil,
                events: []
            )
        }

        var endpoints: [ExternalEventEndpointResult] = []
        var normalizedEvents: [ExternalEvent] = []

        for (index, channel) in channels.enumerated() {
            let result = await fetchChannel(
                channel,
                query: query,
                session: session,
                timezoneID: timezoneID
            )
            endpoints.append(result.0)
            normalizedEvents.append(contentsOf: result.1.filter { query.includePast || $0.isUpcoming })

            if index < channels.count - 1 {
                try? await Task.sleep(nanoseconds: interChannelDelayNanoseconds)
            }
        }

        let localFiltered = filterToLocalWindow(
            events: normalizedEvents,
            query: query
        )
        let deduped = ExternalEventIngestionService.dedupe(events: localFiltered).events
        return ExternalEventSourceResult(
            source: source,
            usedCache: false,
            fetchedAt: Date(),
            endpoints: endpoints.sorted { $0.label < $1.label },
            note: deduped.isEmpty ? "Google Events returned no high-signal local events for the current filters." : nil,
            nextCursor: nil,
            events: deduped
        )
    }

    private func fetchChannel(
        _ channel: SearchChannel,
        query: ExternalEventQuery,
        session: URLSession,
        timezoneID: String
    ) async -> (ExternalEventEndpointResult, [ExternalEvent]) {
        guard let requestURL = buildSearchURL(for: channel) else {
            return (
                ExternalEventEndpointResult(
                    label: "Google Events \(channel.label)",
                    requestURL: searchBaseURL.absoluteString,
                    responseStatusCode: nil,
                    worked: false,
                    note: "Could not build Google Events search URL."
                ),
                []
            )
        }

        let fetchResult = await fetchSearchHTML(
            at: requestURL,
            session: session
        )

        guard let html = fetchResult.html, !html.isEmpty else {
            return (
                ExternalEventEndpointResult(
                    label: "Google Events \(channel.label)",
                    requestURL: requestURL.absoluteString,
                    responseStatusCode: fetchResult.statusCode,
                    worked: false,
                    note: fetchResult.note
                ),
                []
            )
        }

        let parsedEvents = parseEvents(
            from: html,
            searchURL: requestURL,
            queryLabel: channel.label,
            timezoneID: timezoneID
        )
        let normalized = parsedEvents.compactMap {
            normalize(event: $0, queryLabel: channel.label, timezoneID: timezoneID)
        }
        let localFiltered = filterToLocalArea(events: normalized, query: query)

        return (
            ExternalEventEndpointResult(
                label: "Google Events \(channel.label)",
                requestURL: requestURL.absoluteString,
                responseStatusCode: fetchResult.statusCode,
                worked: !localFiltered.isEmpty,
                note: localFiltered.isEmpty ? (fetchResult.note ?? "No parsable Google Events cards matched the current location.") : nil
            ),
            Array(localFiltered.prefix(max(query.pageSize * 2, 12)))
        )
    }

    private func fetchSearchHTML(
        at url: URL,
        session: URLSession
    ) async -> HTMLFetchResult {
        var lastStatusCode: Int?
        var lastNote: String?

        for attempt in 0..<maxRetryCount {
            var request = URLRequest(url: url)
            request.httpMethod = "GET"
            request.timeoutInterval = 20
            request.setValue(desktopUserAgent, forHTTPHeaderField: "User-Agent")
            request.setValue("en-US,en;q=0.9", forHTTPHeaderField: "Accept-Language")
            request.setValue("text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8", forHTTPHeaderField: "Accept")
            request.setValue("https://www.google.com/", forHTTPHeaderField: "Referer")
            request.setValue("1", forHTTPHeaderField: "Upgrade-Insecure-Requests")

            do {
                let (data, response) = try await session.data(for: request)
                let statusCode = (response as? HTTPURLResponse)?.statusCode
                lastStatusCode = statusCode
                let html = String(data: data, encoding: .utf8) ?? ""

                if statusCode.map({ 200..<300 ~= $0 }) ?? false,
                   html.contains("PaEvOc"),
                   html.contains("gws-horizon-textlists__li-ed")
                {
                    return HTMLFetchResult(
                        statusCode: statusCode,
                        html: html,
                        note: nil
                    )
                }

                lastNote = failureNote(from: html, statusCode: statusCode)
                if shouldRetry(statusCode: statusCode, html: html), attempt < maxRetryCount - 1 {
                    try? await Task.sleep(nanoseconds: retryDelayNanoseconds(for: attempt))
                    continue
                }
                return HTMLFetchResult(
                    statusCode: statusCode,
                    html: nil,
                    note: lastNote
                )
            } catch {
                lastNote = error.localizedDescription
                if attempt < maxRetryCount - 1 {
                    try? await Task.sleep(nanoseconds: retryDelayNanoseconds(for: attempt))
                    continue
                }
            }
        }

        return HTMLFetchResult(
            statusCode: lastStatusCode,
            html: nil,
            note: lastNote ?? "Google Events request failed."
        )
    }

    private func parseEvents(
        from html: String,
        searchURL: URL,
        queryLabel: String,
        timezoneID: String
    ) -> [JSONDictionary] {
        eventBlocks(in: html).compactMap { block in
            let title = decodedText(
                firstCapture(
                    pattern: #"jsname=\"r4nke\"[^>]*>(.*?)</div>"#,
                    in: block
                )
            )
            guard let title, !title.isEmpty else { return nil }

            let day = decodedText(firstCapture(pattern: #"<div class=\"FTUoSb\">(.*?)</div>"#, in: block))
            let month = decodedText(firstCapture(pattern: #"<div class=\"omoMNe\">(.*?)</div>"#, in: block))
            let when = decodedText(firstCapture(pattern: #"<div class=\"Gkoz3\">(.*?)</div>"#, in: block))
                ?? fallbackWhenString(day: day, month: month)
            let venueName = decodedText(firstCapture(pattern: #"<span class=\"n3VjZe\">(.*?)</span>"#, in: block))
            let address = decodedText(firstCapture(pattern: #"<span class=\"U6txu\">(.*?)</span>"#, in: block))
            let docID = decodedText(firstCapture(pattern: #"data-encoded-docid=\"([^\"]+)\""#, in: block))
            let ticketInfo = externalTicketInfo(from: block)
            let venueRating = venueRating(from: block)
            let venueReviews = venueReviewCount(from: block)
            let venueReviewURL = googleReviewDestination(from: block, baseURL: searchURL)
            let imageURL = ExternalEventSupport.googlePreferredImageURL(
                decodedURL(
                    firstCapture(
                        pattern: #"href=\"(https:\/\/[^"]+\.(?:jpg|jpeg|png|webp)[^"]*)\""#,
                        in: block
                    )
                )
            )

            let payload: JSONDictionary = [
                "docid": docID as Any,
                "title": title,
                "description": nil as String?,
                "ticket_info": ticketInfo,
                "venue": [
                    "name": venueName as Any,
                    "rating": venueRating as Any,
                    "reviews": venueReviews as Any,
                    "location": [
                        "latitude": nil as Double?,
                        "longitude": nil as Double?
                    ]
                ],
                "address": [address].compactMap { $0 },
                "date": [
                    "when": when as Any
                ],
                "link": googleDetailURL(for: docID, searchURL: searchURL) as Any,
                "image": imageURL as Any,
                "google_places_rating": venueRating as Any,
                "google_places_user_rating_count": venueReviews as Any,
                "google_places_url": venueReviewURL as Any,
                "google_maps_uri": venueReviewURL as Any,
                "query_label": queryLabel,
                "timezone_id": timezoneID
            ]
            return payload
        }
    }

    private func eventBlocks(in html: String) -> [String] {
        matches(
            pattern: #"(?s)<li class=\"PaEvOc[^\"]*gws-horizon-textlists__li-ed\".*?</li>"#,
            in: html
        )
    }

    private func externalTicketInfo(from block: String) -> [JSONDictionary] {
        let matches = captures(
            pattern: #"href=\"(https:\/\/[^\"]+)\""#,
            in: block
        )

        var seen = Set<String>()
        var items: [JSONDictionary] = []

        for rawURL in matches {
            guard let urlString = decodedURL(rawURL), !urlString.isEmpty else { continue }
            guard seen.insert(urlString).inserted else { continue }
            guard !urlString.contains("google.com"), !urlString.contains("gstatic.com") else { continue }

            let sourceName = sourceName(for: urlString)
            items.append(
                [
                    "source": sourceName,
                    "link": urlString,
                    "link_type": linkType(for: urlString)
                ]
            )
        }

        return items
    }

    private func venueRating(from block: String) -> Double? {
        let candidates = [
            decodedText(
                firstCapture(
                    pattern: #"aria-label=\"Rated ([0-9.]+) out of 5,\""#,
                    in: block
                )
            ),
            decodedText(
                firstCapture(
                    pattern: #"<span class=\"UIHjI[^\"]*\"[^>]*>([0-9.]+)</span>"#,
                    in: block
                )
            )
        ]

        for candidate in candidates {
            if let rating = ExternalEventSupport.parseDouble(candidate),
               rating >= 1.0,
               rating <= 5.0 {
                return rating
            }
        }

        return nil
    }

    private func venueReviewCount(from block: String) -> Int? {
        let candidates = [
            decodedText(
                firstCapture(
                    pattern: #">([0-9][0-9,\.KkMm]*) reviews<"#,
                    in: block
                )
            ),
            decodedText(
                firstCapture(
                    pattern: #"aria-label=\"Rated [0-9.]+ out of 5, ([0-9][0-9,\.KkMm]*) reviews"#,
                    in: block
                )
            )
        ]

        for candidate in candidates {
            if let reviewCount = ExternalEventSupport.parseInt(candidate), reviewCount > 0 {
                return reviewCount
            }
            if let candidate {
                let normalized = candidate
                    .replacingOccurrences(of: ",", with: "")
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                    .uppercased()
                if normalized.hasSuffix("K"), let value = Double(normalized.dropLast()) {
                    return Int((value * 1_000).rounded())
                }
                if normalized.hasSuffix("M"), let value = Double(normalized.dropLast()) {
                    return Int((value * 1_000_000).rounded())
                }
            }
        }

        return nil
    }

    private func googleReviewDestination(from block: String, baseURL: URL) -> String? {
        let patterns = [
            #"href=\"([^\"]*ibp(?:=|%3D)gwp(?:;|%3B)0,7[^\"]*)\""#,
            #"href=\"([^\"]*ludocid=[^\"]*ibp(?:=|%3D)gwp(?:;|%3B)0,7[^\"]*)\""#
        ]

        for pattern in patterns {
            guard let rawURL = decodedURL(firstCapture(pattern: pattern, in: block)),
                  let absoluteURL = absoluteURLString(from: rawURL, baseURL: baseURL)
            else {
                continue
            }
            return absoluteURL
        }

        return nil
    }

    private func absoluteURLString(from rawValue: String, baseURL: URL) -> String? {
        if let url = URL(string: rawValue), url.scheme?.hasPrefix("http") == true {
            return url.absoluteString
        }
        guard let url = URL(string: rawValue, relativeTo: baseURL) else {
            return nil
        }
        return url.absoluteURL.absoluteString
    }

    private func buildChannels(for query: ExternalEventQuery) -> [SearchChannel] {
        let metro = metroQueryLocation(for: query)
        let nightlifeLocation = nightlifeQueryLocation(for: query)
        guard !metro.isEmpty else { return [] }

        switch query.discoveryIntent {
        case .biggestTonight:
            return [
                SearchChannel(label: "tonight discovery", queryText: "events tonight in \(metro)"),
                SearchChannel(label: "tonight concerts", queryText: "concerts tonight in \(metro)"),
                SearchChannel(label: "tonight sports", queryText: "sports tonight in \(metro)"),
                SearchChannel(label: "tonight comedy", queryText: "comedy tonight in \(metro)"),
                SearchChannel(label: "tonight nightlife", queryText: "nightlife tonight in \(nightlifeLocation)"),
                SearchChannel(label: "tomorrow discovery", queryText: "events tomorrow in \(metro)")
            ]
        case .exclusiveHot:
            return [
                SearchChannel(label: "tonight nightlife", queryText: "nightlife tonight in \(nightlifeLocation)"),
                SearchChannel(label: "tonight exclusive", queryText: "exclusive nightlife tonight in \(nightlifeLocation)"),
                SearchChannel(label: "tonight comedy", queryText: "comedy tonight in \(metro)"),
                SearchChannel(label: "tonight discovery", queryText: "events tonight in \(metro)"),
                SearchChannel(label: "tomorrow nightlife", queryText: "nightlife tomorrow in \(nightlifeLocation)")
            ]
        case .lastMinutePlans:
            return [
                SearchChannel(label: "tonight discovery", queryText: "things to do tonight in \(metro)"),
                SearchChannel(label: "tonight comedy", queryText: "comedy tonight in \(metro)"),
                SearchChannel(label: "this week community", queryText: "community events this week in \(metro)"),
                SearchChannel(label: "this week markets", queryText: "farmers markets this week in \(metro)"),
                SearchChannel(label: "tomorrow discovery", queryText: "events tomorrow in \(metro)")
            ]
        case .nearbyWorthIt:
            return [
                SearchChannel(label: "today discovery", queryText: "events today in \(metro)"),
                SearchChannel(label: "this week comedy", queryText: "comedy shows this week in \(metro)"),
                SearchChannel(label: "this week community", queryText: "things to do this week in \(metro)"),
                SearchChannel(label: "this week markets", queryText: "farmers markets this week in \(metro)"),
                SearchChannel(label: "this week festivals", queryText: "festivals this week in \(metro)"),
                SearchChannel(label: "tomorrow discovery", queryText: "events tomorrow in \(metro)")
            ]
        }
    }

    private func buildSearchURL(for channel: SearchChannel) -> URL? {
        var components = URLComponents(url: searchBaseURL, resolvingAgainstBaseURL: false)
        components?.queryItems = [
            URLQueryItem(name: "q", value: channel.queryText),
            URLQueryItem(name: "ibp", value: "htl;events"),
            URLQueryItem(name: "hl", value: "en"),
            URLQueryItem(name: "gl", value: "us")
        ]
        return components?.url
    }

    private func normalize(event: JSONDictionary, queryLabel: String, timezoneID: String) -> ExternalEvent? {
        let title = event.string("title") ?? "Untitled Google Event"
        let description = ExternalEventSupport.plainText(event.string("description"))
        let ticketInfo = event.array("ticket_info")
        let ticketSources = ticketInfo.compactMap { $0.string("source") }
        let eventType = ExternalEventSupport.googleEventType(
            title: title,
            description: description,
            ticketSources: ticketSources,
            queryLabel: queryLabel
        )

        let venue = event.dictionary("venue")
        let addressLines = (event["address"] as? [String] ?? [])
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        let venueName = venue?.string("name") ?? addressLines.first?.components(separatedBy: ",").first
        let parsedAddress = parseAddressComponents(addressLines: addressLines, venueName: venueName)

        let dateInfo = event.dictionary("date")
        let dateRange = ExternalEventSupport.googleEventsDateRange(
            when: dateInfo?.string("when"),
            timezoneID: timezoneID
        )

        let ticketURL = preferredTicketURL(from: ticketInfo)
        let sourceURL = event.string("link") ?? ticketURL
        let imageURL = ExternalEventSupport.googlePreferredImageURL(event.string("image"))
        let venueReviews = ExternalEventSupport.parseInt(venue?["reviews"])
        let venueRating = ExternalEventSupport.parseDouble(venue?["rating"])
        let sourceEventID = event.string("docid")
            ?? stableIdentifier(for: title, when: dateInfo?.string("when"), venueName: venueName, city: parsedAddress.city)
        let normalizedStatus: (ExternalEventStatus, ExternalEventAvailabilityStatus) = {
            if ticketURL != nil {
                return ExternalEventSupport.normalizeTicketmasterStatus(
                    statusCode: "onsale",
                    eventStartUTC: dateRange.startUTC
                )
            }
            if let startUTC = dateRange.startUTC, startUTC < Date() {
                return (.ended, .ended)
            }
            return (.scheduled, .available)
        }()

        return ExternalEvent(
            id: "\(source.rawValue):\(sourceEventID)",
            source: source,
            sourceEventID: sourceEventID,
            sourceParentID: nil,
            sourceURL: sourceURL,
            mergedSources: [source],
            title: title,
            shortDescription: ExternalEventSupport.shortened(description),
            fullDescription: description,
            category: queryLabel,
            subcategory: ticketSources.first,
            eventType: eventType,
            startAtUTC: dateRange.startUTC,
            endAtUTC: dateRange.endUTC,
            startLocal: dateRange.startLocal,
            endLocal: dateRange.endLocal,
            timezone: timezoneID,
            salesStartAtUTC: nil,
            salesEndAtUTC: nil,
            venueName: venueName,
            venueID: nil,
            addressLine1: parsedAddress.addressLine1,
            addressLine2: nil,
            city: parsedAddress.city,
            state: parsedAddress.state,
            postalCode: parsedAddress.postalCode,
            country: "US",
            latitude: ExternalEventSupport.parseDouble(venue?.dictionary("location")?["latitude"] ?? event["latitude"]),
            longitude: ExternalEventSupport.parseDouble(venue?.dictionary("location")?["longitude"] ?? event["longitude"]),
            imageURL: imageURL,
            fallbackThumbnailAsset: ExternalEventSupport.fallbackThumbnailAsset(for: eventType),
            status: normalizedStatus.0,
            availabilityStatus: normalizedStatus.1,
            urgencyBadge: nil,
            socialProofCount: nil,
            socialProofLabel: nil,
            venuePopularityCount: venueReviews,
            venueRating: venueRating,
            ticketProviderCount: ticketInfo.count,
            priceMin: nil,
            priceMax: nil,
            currency: nil,
            organizerName: ticketSources.first,
            organizerEventCount: nil,
            organizerVerified: nil,
            tags: ExternalEventSupport.tags(from: [queryLabel, venueName, parsedAddress.city, parsedAddress.state] + ticketSources),
            distanceValue: nil,
            distanceUnit: nil,
            raceType: nil,
            registrationURL: nil,
            ticketURL: ticketURL,
            rawSourcePayload: ExternalEventSupport.jsonString(event)
        )
    }

    private func preferredTicketURL(from ticketInfo: [JSONDictionary]) -> String? {
        let preferredSources = [
            "Ticketmaster.com",
            "Ticketmaster",
            "AXS",
            "Live Nation",
            "Dice.fm",
            "Dice",
            "SeatGeek",
            "StubHub",
            "Spotify.com",
            "Eventbrite.com",
            "Bandsintown",
            "Tixel"
        ]

        for sourceName in preferredSources {
            if let match = ticketInfo.first(where: { item in
                (item.string("source") ?? "").localizedCaseInsensitiveContains(sourceName)
                    && (item.string("link_type") ?? "").localizedCaseInsensitiveContains("ticket")
            }) {
                return match.string("link")
            }
        }

        return ticketInfo.first(where: {
            ($0.string("link_type") ?? "").localizedCaseInsensitiveContains("ticket")
        })?.string("link") ?? ticketInfo.first?.string("link")
    }

    private func filterToLocalWindow(
        events: [ExternalEvent],
        query: ExternalEventQuery
    ) -> [ExternalEvent] {
        guard !events.isEmpty else { return [] }
        let cutoff = Calendar.current.date(byAdding: .day, value: 21, to: Date())
        return events.filter { event in
            if let startAtUTC = event.startAtUTC, let cutoff, startAtUTC > cutoff {
                return false
            }
            return true
        }
    }

    private func filterToLocalArea(
        events: [ExternalEvent],
        query: ExternalEventQuery
    ) -> [ExternalEvent] {
        guard !events.isEmpty else { return [] }
        let postalPrefix = normalizedPostalPrefix(query.postalCode)
        let hasLocalConstraint = (query.city?.isEmpty == false) || (query.state?.isEmpty == false) || postalPrefix != nil
        guard hasLocalConstraint else { return events }

        let filtered = events.filter { event in
            if let postalPrefix,
               let eventPostalPrefix = normalizedPostalPrefix(event.postalCode),
               postalPrefix == eventPostalPrefix
            {
                return true
            }

            return ExternalEventSupport.sharesMetroArea(
                event: event,
                preferredCity: query.city,
                preferredState: query.state
            )
        }

        return filtered.isEmpty ? events : filtered
    }

    private func normalizedPostalPrefix(_ postalCode: String?) -> String? {
        guard let postalCode else { return nil }
        let digits = postalCode.filter(\.isNumber)
        guard digits.count >= 5 else { return nil }
        return String(digits.prefix(5))
    }

    private func decodedText(_ rawValue: String?) -> String? {
        guard let rawValue, !rawValue.isEmpty else { return nil }
        var value = rawValue
        let replacements = [
            "&amp;": "&",
            "&quot;": "\"",
            "&#39;": "'",
            "&apos;": "'",
            "&lt;": "<",
            "&gt;": ">",
            "&nbsp;": " ",
            "\\u003d": "=",
            "\\u0026": "&",
            "\\u0027": "'",
            "\\/": "/"
        ]
        for (source, target) in replacements {
            value = value.replacingOccurrences(of: source, with: target)
        }
        value = value.replacingOccurrences(
            of: #"<[^>]+>"#,
            with: " ",
            options: .regularExpression
        )
        value = value.replacingOccurrences(
            of: #"\s+"#,
            with: " ",
            options: .regularExpression
        )
        let cleaned = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return cleaned.isEmpty ? nil : cleaned
    }

    private func decodedURL(_ rawValue: String?) -> String? {
        guard let value = decodedText(rawValue), !value.isEmpty else { return nil }
        return value.replacingOccurrences(of: "&amp;", with: "&")
    }

    private func firstCapture(
        pattern: String,
        in text: String
    ) -> String? {
        captures(pattern: pattern, in: text).first
    }

    private func captures(
        pattern: String,
        in text: String
    ) -> [String] {
        guard let regex = try? NSRegularExpression(
            pattern: pattern,
            options: [.dotMatchesLineSeparators]
        ) else {
            return []
        }

        let nsrange = NSRange(text.startIndex..., in: text)
        return regex.matches(in: text, options: [], range: nsrange).compactMap { match in
            guard match.numberOfRanges > 1,
                  let range = Range(match.range(at: 1), in: text)
            else {
                return nil
            }
            return String(text[range])
        }
    }

    private func matches(
        pattern: String,
        in text: String
    ) -> [String] {
        guard let regex = try? NSRegularExpression(
            pattern: pattern,
            options: [.dotMatchesLineSeparators]
        ) else {
            return []
        }

        let nsrange = NSRange(text.startIndex..., in: text)
        return regex.matches(in: text, options: [], range: nsrange).compactMap { match in
            guard let range = Range(match.range(at: 0), in: text) else { return nil }
            return String(text[range])
        }
    }

    private func fallbackWhenString(
        day: String?,
        month: String?
    ) -> String? {
        guard let day, let month else { return nil }
        let cleanedDay = day.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanedMonth = month.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanedDay.isEmpty, !cleanedMonth.isEmpty else { return nil }
        return "\(cleanedMonth) \(cleanedDay)"
    }

    private func googleDetailURL(
        for docID: String?,
        searchURL: URL
    ) -> String? {
        guard let docID, !docID.isEmpty else { return nil }
        guard var components = URLComponents(url: searchURL, resolvingAgainstBaseURL: false) else {
            return searchURL.absoluteString
        }
        let encodedDocID = docID.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? docID
        components.fragment = "fpstate=tldetail&htivrt=events&htidocid=\(encodedDocID)"
        return components.url?.absoluteString ?? searchURL.absoluteString
    }

    private func sourceName(for urlString: String) -> String {
        guard let host = URL(string: urlString)?.host?.lowercased() else { return "Google Events" }
        if host.contains("ticketmaster") { return "Ticketmaster.com" }
        if host.contains("axs") { return "AXS" }
        if host.contains("livenation") { return "Live Nation" }
        if host.contains("dice") { return "Dice.fm" }
        if host.contains("seatgeek") { return "SeatGeek" }
        if host.contains("stubhub") { return "StubHub" }
        if host.contains("spotify") { return "Spotify.com" }
        if host.contains("eventbrite") { return "Eventbrite.com" }
        if host.contains("bandsintown") { return "Bandsintown" }
        if host.contains("tixel") { return "Tixel" }
        if host.contains("songkick") { return "Songkick" }
        if host.contains("ticketweb") { return "TicketWeb" }
        if host.contains("etix") { return "Etix" }
        return host.replacingOccurrences(of: "www.", with: "")
    }

    private func linkType(for urlString: String) -> String {
        let normalized = ExternalEventSupport.normalizeToken(urlString)
        if normalized.contains("ticketmaster")
            || normalized.contains("axs")
            || normalized.contains("livenation")
            || normalized.contains("dice")
            || normalized.contains("seatgeek")
            || normalized.contains("stubhub")
            || normalized.contains("spotify")
            || normalized.contains("eventbrite")
            || normalized.contains("bandsintown")
            || normalized.contains("ticketweb")
            || normalized.contains("etix")
            || normalized.contains("tickets")
            || normalized.contains("ticket")
        {
            return "ticket"
        }
        return "info"
    }

    private func failureNote(from html: String, statusCode: Int?) -> String {
        let cleaned = decodedText(html) ?? ""
        if cleaned.localizedCaseInsensitiveContains("not yet supported") {
            return "Google Events returned an unsupported browser response."
        }
        if cleaned.localizedCaseInsensitiveContains("internal server error") || statusCode == 500 {
            return "Google Events returned a temporary server error."
        }
        if cleaned.isEmpty {
            return "Google Events returned an empty response."
        }
        return String(cleaned.prefix(220))
    }

    private func shouldRetry(statusCode: Int?, html: String) -> Bool {
        if let statusCode, [429, 500, 502, 503, 504].contains(statusCode) {
            return true
        }
        let cleaned = decodedText(html) ?? ""
        return cleaned.localizedCaseInsensitiveContains("not yet supported")
            || cleaned.localizedCaseInsensitiveContains("internal server error")
            || cleaned.count < 5_000
    }

    private func retryDelayNanoseconds(for attempt: Int) -> UInt64 {
        switch attempt {
        case 0:
            return 500_000_000
        case 1:
            return 1_000_000_000
        default:
            return 1_500_000_000
        }
    }

    private var desktopUserAgent: String {
        "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0.0.0 Safari/537.36"
    }

    private func stableIdentifier(for title: String, when: String?, venueName: String?, city: String?) -> String {
        let seed = "\(title)|\(when ?? "")|\(venueName ?? "")|\(city ?? "")"
        return ExternalEventSupport.normalizeToken(seed).replacingOccurrences(of: " ", with: "-")
    }

    private func metroQueryLocation(for query: ExternalEventQuery) -> String {
        if let city = query.city, let state = query.state, !city.isEmpty, !state.isEmpty {
            return "\(city) \(state)"
        }
        if let city = query.city, !city.isEmpty {
            return city
        }
        if let postalCode = query.postalCode, !postalCode.isEmpty {
            return postalCode
        }
        return ""
    }

    private func nightlifeQueryLocation(for query: ExternalEventQuery) -> String {
        metroQueryLocation(for: query)
    }

    private func timezoneIdentifier(for query: ExternalEventQuery) -> String {
        if let latitude = query.latitude, let longitude = query.longitude {
            return ExternalEventSupport.timeZoneIdentifier(latitude: latitude, longitude: longitude)
        }
        let normalizedState = ExternalEventSupport.normalizeToken(query.state)
        switch normalizedState {
        case "ca", "california", "wa", "washington", "or", "oregon", "nv", "nevada":
            return "America/Los_Angeles"
        case "az", "arizona", "co", "colorado", "ut", "utah":
            return "America/Denver"
        case "tx", "texas", "il", "illinois", "mn", "minnesota", "mo", "missouri", "wi", "wisconsin", "tn", "tennessee", "al", "alabama":
            return "America/Chicago"
        case "ny", "new york", "fl", "florida", "ga", "georgia", "nc", "north carolina", "sc", "south carolina", "ma", "massachusetts", "pa", "pennsylvania", "dc", "district of columbia":
            return "America/New_York"
        default:
            return TimeZone.current.identifier
        }
    }

    private func parseAddressComponents(
        addressLines: [String],
        venueName: String?
    ) -> (addressLine1: String?, city: String?, state: String?, postalCode: String?) {
        let joined = addressLines.joined(separator: ", ")
        let normalizedVenue = ExternalEventSupport.normalizeToken(venueName)

        var addressLine1 = addressLines.first
        if let currentAddressLine1 = addressLine1,
           !normalizedVenue.isEmpty,
           ExternalEventSupport.normalizeToken(currentAddressLine1) == normalizedVenue,
           addressLines.count > 1 {
            addressLine1 = addressLines[1]
        }

        let pattern = #"([A-Za-z .'-]+),\s*([A-Z]{2})(?:\s+([0-9]{5}))?"#
        guard let range = joined.range(of: pattern, options: .regularExpression) else {
            return (addressLine1, nil, nil, nil)
        }

        let fragment = String(joined[range])
        let pieces = fragment.components(separatedBy: ",")
        let city = pieces.first?.trimmingCharacters(in: .whitespacesAndNewlines)
        let statePostal = pieces.dropFirst().first?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let stateParts = statePostal.split(separator: " ").map(String.init)
        let state = stateParts.first
        let postalCode = stateParts.dropFirst().first

        return (
            addressLine1,
            city?.isEmpty == false ? city : nil,
            state?.isEmpty == false ? state : nil,
            postalCode?.isEmpty == false ? postalCode : nil
        )
    }
}
