import Foundation

nonisolated struct EventbriteEventAdapter: ExternalEventSourceAdapter {
    let source: ExternalEventSource = .eventbrite

    private struct ListingTarget: Sendable {
        let label: String
        let url: URL
    }

    private struct ListingQueryTopic: Sendable {
        let label: String
        let searchTerm: String?
    }

    private struct ListingItem: Sendable {
        let eventID: String?
        let title: String
        let url: String
        let summary: String?
        let imageURL: String?
        let startLocal: String?
        let endLocal: String?
        let venueName: String?
        let addressLine1: String?
        let city: String?
        let state: String?
        let postalCode: String?
        let country: String?
        let latitude: Double?
        let longitude: Double?

        var rawValue: JSONDictionary {
            [
                "event_id": eventID as Any,
                "title": title,
                "url": url,
                "summary": summary as Any,
                "image_url": imageURL as Any,
                "start_local": startLocal as Any,
                "end_local": endLocal as Any,
                "venue_name": venueName as Any,
                "address_line_1": addressLine1 as Any,
                "city": city as Any,
                "state": state as Any,
                "postal_code": postalCode as Any,
                "country": country as Any,
                "latitude": latitude as Any,
                "longitude": longitude as Any
            ]
        }
    }

    private let publicBaseURL = URL(string: "https://www.eventbrite.com")!

    func fetchPage(
        query: ExternalEventQuery,
        cursor: ExternalEventSourceCursor?,
        session: URLSession,
        configuration: ExternalEventServiceConfiguration
    ) async -> ExternalEventSourceResult {
        let pageNumber = max(cursor?.page ?? (query.page + 1), 1)
        var endpoints: [ExternalEventEndpointResult] = []
        var authNote: String?

        if let token = configuration.eventbritePrivateToken, !token.isEmpty {
            let authValidated = await validateAuth(token: token, session: session, configuration: configuration, endpoints: &endpoints)
            if !authValidated {
                authNote = "Eventbrite account auth failed, continuing with public discovery only."
            }
        } else {
            authNote = "Eventbrite account auth not configured, using public discovery only."
        }

        let listingTargets = buildListingTargets(query: query, pageNumber: pageNumber)
        var discoveredItems: [ListingItem] = []
        await withTaskGroup(of: (ExternalEventEndpointResult, [ListingItem]).self) { group in
            for target in listingTargets {
                group.addTask {
                    do {
                        let (data, response) = try await session.data(from: target.url)
                        let statusCode = (response as? HTTPURLResponse)?.statusCode
                        let html = String(data: data, encoding: .utf8) ?? ""
                        let endpoint = ExternalEventEndpointResult(
                            label: "Eventbrite public listing \(target.label)",
                            requestURL: target.url.absoluteString,
                            responseStatusCode: statusCode,
                            worked: statusCode.map { 200..<300 ~= $0 } ?? false,
                            note: nil
                        )

                        guard statusCode.map({ 200..<300 ~= $0 }) ?? false else {
                            return (endpoint, [])
                        }

                        return (endpoint, parseListingItems(from: html))
                    } catch {
                        return (
                            ExternalEventEndpointResult(
                                label: "Eventbrite public listing \(target.label)",
                                requestURL: target.url.absoluteString,
                                responseStatusCode: nil,
                                worked: false,
                                note: error.localizedDescription
                            ),
                            []
                        )
                    }
                }
            }

            for await result in group {
                endpoints.append(result.0)
                discoveredItems.append(contentsOf: result.1)
            }
        }

        var uniqueItems: [ListingItem] = []
        var seenURLs = Set<String>()
        for item in discoveredItems {
            guard !item.url.isEmpty, !seenURLs.contains(item.url) else { continue }
            seenURLs.insert(item.url)
            uniqueItems.append(item)
        }

        if let keyword = query.keyword, !keyword.isEmpty {
            let normalizedKeyword = ExternalEventSupport.normalizeToken(keyword)
            uniqueItems = uniqueItems.filter { item in
                let haystack = ExternalEventSupport.normalizeToken(item.title + " " + (item.summary ?? ""))
                return haystack.contains(normalizedKeyword)
            }
        }

        let detailItems = Array(uniqueItems.prefix(min(max(query.pageSize, 8), 12)))
        var normalizedEvents: [ExternalEvent] = []

        await withTaskGroup(of: (ExternalEventEndpointResult, ExternalEvent?).self) { group in
            for item in detailItems {
                group.addTask {
                    await fetchDetailEvent(for: item, session: session)
                }
            }

            for await result in group {
                endpoints.append(result.0)
                if let event = result.1, query.includePast || event.isUpcoming {
                    normalizedEvents.append(event)
                }
            }
        }

        let deduped = ExternalEventIngestionService.dedupe(events: normalizedEvents).events
        let nextCursor: ExternalEventSourceCursor? = detailItems.count >= query.pageSize
            ? ExternalEventSourceCursor(source: source, page: pageNumber + 1, pageSize: query.pageSize, nextToken: nil)
            : nil

        return ExternalEventSourceResult(
            source: source,
            usedCache: false,
            fetchedAt: Date(),
            endpoints: endpoints,
            note: deduped.isEmpty ? (authNote ?? "No Eventbrite public events were normalized from the current listing page.") : authNote,
            nextCursor: nextCursor,
            events: deduped
        )
    }

    private func validateAuth(
        token: String,
        session: URLSession,
        configuration: ExternalEventServiceConfiguration,
        endpoints: inout [ExternalEventEndpointResult]
    ) async -> Bool {
        let authPaths = ["v3/users/me/"]
        var authValidated = false

        for path in authPaths {
            let url = configuration.eventbriteBaseURL.appendingPathComponent(path)
            var request = URLRequest(url: url)
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

            do {
                let (data, response) = try await session.data(for: request)
                let statusCode = (response as? HTTPURLResponse)?.statusCode
                authValidated = authValidated || (statusCode.map { 200..<300 ~= $0 } ?? false)
                let note: String? = {
                    guard let statusCode, !(200..<300 ~= statusCode) else { return nil }
                    return String(data: data, encoding: .utf8)
                }()
                endpoints.append(
                    ExternalEventEndpointResult(
                        label: "Eventbrite \(path)",
                        requestURL: url.absoluteString,
                        responseStatusCode: statusCode,
                        worked: statusCode.map { 200..<300 ~= $0 } ?? false,
                        note: note
                    )
                )
            } catch {
                endpoints.append(
                    ExternalEventEndpointResult(
                        label: "Eventbrite \(path)",
                        requestURL: url.absoluteString,
                        responseStatusCode: nil,
                        worked: false,
                        note: error.localizedDescription
                    )
                )
            }
        }

        return authValidated
    }

    private func buildListingTargets(query: ExternalEventQuery, pageNumber: Int) -> [ListingTarget] {
        let basePath = listingBasePath(for: query)
        let fallbackPaths = [
            ("Los Angeles", "d/ca--los-angeles/all-events/"),
            ("New York", "d/ny--new-york/all-events/"),
            ("Chicago", "d/il--chicago/all-events/")
        ]

        let pathTargets: [(label: String, path: String)]
        if let basePath {
            pathTargets = [(readableLocationLabel(for: query), basePath)]
        } else {
            pathTargets = fallbackPaths
        }

        let topics = listingQueryTopics(for: query)
        var seen = Set<String>()

        return pathTargets.flatMap { target -> [ListingTarget] in
            topics.compactMap { topic in
                var components = URLComponents(url: publicBaseURL.appendingPathComponent(target.path), resolvingAgainstBaseURL: false)
                var queryItems: [URLQueryItem] = []
                if pageNumber > 1 {
                    queryItems.append(URLQueryItem(name: "page", value: String(pageNumber)))
                }
                if let searchTerm = topic.searchTerm, !searchTerm.isEmpty {
                    queryItems.append(URLQueryItem(name: "q", value: searchTerm))
                }
                if !queryItems.isEmpty {
                    components?.queryItems = queryItems
                }
                guard let url = components?.url else { return nil }
                guard seen.insert(url.absoluteString).inserted else { return nil }
                return ListingTarget(label: "\(target.label) \(topic.label)", url: url)
            }
        }
    }

    private func listingBasePath(for query: ExternalEventQuery) -> String? {
        guard let city = query.city, !city.isEmpty else { return nil }
        let citySlug = slugify(city)
        if let state = query.state, !state.isEmpty {
            let stateSlug = slugify(state)
            return "d/\(stateSlug)--\(citySlug)/all-events/"
        }
        return "d/united-states--\(citySlug)/all-events/"
    }

    private func readableLocationLabel(for query: ExternalEventQuery) -> String {
        if let city = query.city, let state = query.state, !city.isEmpty, !state.isEmpty {
            return "\(city), \(state)"
        }
        if let city = query.city, !city.isEmpty {
            return city
        }
        if let postalCode = query.postalCode, !postalCode.isEmpty {
            return postalCode
        }
        return "Metro"
    }

    private func listingQueryTopics(for query: ExternalEventQuery) -> [ListingQueryTopic] {
        var topics: [ListingQueryTopic] = [
            ListingQueryTopic(label: "all", searchTerm: nil)
        ]

        if let keyword = query.keyword, !keyword.isEmpty {
            topics.append(ListingQueryTopic(label: "search", searchTerm: keyword))
        }

        switch query.discoveryIntent {
        case .biggestTonight:
            topics.append(contentsOf: [
                ListingQueryTopic(label: "comedy", searchTerm: "comedy"),
                ListingQueryTopic(label: "festival", searchTerm: "festival"),
                ListingQueryTopic(label: "food", searchTerm: "food festival"),
                ListingQueryTopic(label: "market", searchTerm: "night market")
            ])
        case .exclusiveHot:
            topics.append(contentsOf: [
                ListingQueryTopic(label: "comedy", searchTerm: "comedy"),
                ListingQueryTopic(label: "festival", searchTerm: "festival"),
                ListingQueryTopic(label: "market", searchTerm: "market")
            ])
        case .nearbyWorthIt:
            topics.append(contentsOf: [
                ListingQueryTopic(label: "comedy", searchTerm: "comedy"),
                ListingQueryTopic(label: "farmers", searchTerm: "farmers market"),
                ListingQueryTopic(label: "market", searchTerm: "market"),
                ListingQueryTopic(label: "festival", searchTerm: "festival"),
                ListingQueryTopic(label: "community", searchTerm: "community event"),
                ListingQueryTopic(label: "expo", searchTerm: "expo")
            ])
        case .lastMinutePlans:
            topics.append(contentsOf: [
                ListingQueryTopic(label: "comedy", searchTerm: "comedy"),
                ListingQueryTopic(label: "market", searchTerm: "market"),
                ListingQueryTopic(label: "festival", searchTerm: "festival"),
                ListingQueryTopic(label: "community", searchTerm: "community event")
            ])
        }

        var seen = Set<String>()
        return topics.filter { topic in
            let key = topic.searchTerm?.lowercased() ?? "__all__"
            return seen.insert(key).inserted
        }
    }

    private func parseListingItems(from html: String) -> [ListingItem] {
        for jsonValue in extractJSONLDScripts(from: html) {
            guard let payload = jsonValue as? JSONDictionary else { continue }
            let items = payload.array("itemListElement")
            guard !items.isEmpty else { continue }

            return items.compactMap { listItem in
                guard let item = listItem.dictionary("item"),
                      let url = item.string("url")
                else {
                    return nil
                }

                let location = item.dictionary("location")
                let address = location?.dictionary("address")
                let geo = location?.dictionary("geo")
                return ListingItem(
                    eventID: ExternalEventSupport.eventbriteEventID(from: url),
                    title: item.string("name") ?? "Untitled Eventbrite Event",
                    url: url,
                    summary: ExternalEventSupport.plainText(item.string("description")),
                    imageURL: extractBestImageURL(from: item["image"]),
                    startLocal: item.string("startDate"),
                    endLocal: item.string("endDate"),
                    venueName: location?.string("name"),
                    addressLine1: address?.string("streetAddress"),
                    city: address?.string("addressLocality"),
                    state: address?.string("addressRegion"),
                    postalCode: address?.string("postalCode"),
                    country: address?.string("addressCountry"),
                    latitude: ExternalEventSupport.parseDouble(geo?["latitude"]),
                    longitude: ExternalEventSupport.parseDouble(geo?["longitude"])
                )
            }
        }

        return []
    }

    private func fetchDetailEvent(
        for listingItem: ListingItem,
        session: URLSession
    ) async -> (ExternalEventEndpointResult, ExternalEvent?) {
        guard let url = URL(string: listingItem.url) else {
            return (
                ExternalEventEndpointResult(
                    label: "Eventbrite detail invalid URL",
                    requestURL: listingItem.url,
                    responseStatusCode: nil,
                    worked: false,
                    note: "Invalid Eventbrite event URL."
                ),
                nil
            )
        }

        do {
            let (data, response) = try await session.data(from: url)
            let statusCode = (response as? HTTPURLResponse)?.statusCode
            let html = String(data: data, encoding: .utf8) ?? ""
            let endpoint = ExternalEventEndpointResult(
                label: "Eventbrite event detail \(listingItem.eventID ?? listingItem.title)",
                requestURL: listingItem.url,
                responseStatusCode: statusCode,
                worked: statusCode.map { 200..<300 ~= $0 } ?? false,
                note: nil
            )

            guard statusCode.map({ 200..<300 ~= $0 }) ?? false else {
                return (endpoint, nil)
            }

            return (endpoint, normalizeDetail(html: html, listingItem: listingItem))
        } catch {
            return (
                ExternalEventEndpointResult(
                    label: "Eventbrite event detail \(listingItem.eventID ?? listingItem.title)",
                    requestURL: listingItem.url,
                    responseStatusCode: nil,
                    worked: false,
                    note: error.localizedDescription
                ),
                nil
            )
        }
    }

    private func normalizeDetail(html: String, listingItem: ListingItem) -> ExternalEvent? {
        guard let nextData = extractNextData(from: html),
              let context = nextData.dictionary(at: ["props", "pageProps", "context"]),
              let basicInfo = context.dictionary("basicInfo")
        else {
            return nil
        }

        let socialEvent = extractSocialEventSchema(from: html)
        let taxonomies = context.dictionary("taxonomies")
        let galleryImages = context.array(at: ["gallery", "images"])
        let galleryImageURLs = galleryImages.compactMap { image in
            image.string("url")
                ?? image.string("croppedLogoUrl940")
                ?? image.string("croppedOriginalImageUrl")
                ?? image.string("src")
        }
        let metaImageURL = extractMetaImageURL(from: html)
        let allImageCandidates = uniqueImageCandidates(
            galleryImageURLs
            + imageURLCandidates(from: basicInfo["image"])
            + imageURLCandidates(from: basicInfo["images"])
            + imageURLCandidates(from: basicInfo["primaryImage"])
            + imageURLCandidates(from: basicInfo["heroImage"])
            + imageURLCandidates(from: basicInfo["logo"])
            + imageURLCandidates(from: socialEvent?["image"])
            + imageURLCandidates(from: socialEvent?["images"])
            + [listingItem.imageURL, metaImageURL].compactMap { $0 }
        )

        let basicInfoID = basicInfo.string("id") ?? listingItem.eventID ?? UUID().uuidString
        let sourceURL = basicInfo.string("url") ?? listingItem.url
        let title = basicInfo.string("name") ?? listingItem.title
        let summary = ExternalEventSupport.plainText(basicInfo.string("summary") ?? listingItem.summary)
        let fullDescription = ExternalEventSupport.plainText(
            socialEvent?.string("description")
            ?? basicInfo.string("summary")
            ?? listingItem.summary
        )

        let category = taxonomies?.string("category")
        let subcategory = taxonomies?.string("subcategory")
        let format = taxonomies?.string("format")
        let eventType = ExternalEventSupport.eventbriteEventType(
            category: category,
            subcategory: subcategory,
            format: format,
            title: title,
            summary: summary
        )

        let venue = basicInfo.dictionary("venue")
        let venueAddress = venue?.dictionary("address")
        let organizer = basicInfo.dictionary("organizer")
        let organizerSignals = extractOrganizerSignals(from: html)

        let startUTC = ExternalEventSupport.ticketmasterDate(basicInfo.string(at: ["startDate", "utc"]))
        let endUTC = ExternalEventSupport.ticketmasterDate(basicInfo.string(at: ["endDate", "utc"]))
        let startLocal = basicInfo.string(at: ["startDate", "local"]) ?? listingItem.startLocal
        let endLocal = basicInfo.string(at: ["endDate", "local"]) ?? listingItem.endLocal
        let timezone = basicInfo.string(at: ["startDate", "timezone"])

        let offerInfo = extractOfferInfo(from: socialEvent)
        let venueAddressDisplayLines = venueAddress?["localizedMultiLineAddressDisplay"] as? [String]
        let detailSubcategory = [subcategory, format].compactMap { $0 }.joined(separator: " / ")
        let normalizedStatus = ExternalEventSupport.normalizeEventbriteStatus(
            basicStatus: basicInfo.string("status"),
            schemaStatus: socialEvent?.string("eventStatus"),
            availability: offerInfo.availability,
            availabilityEndsUTC: offerInfo.availabilityEndsUTC,
            startUTC: startUTC,
            isFree: basicInfo["isFree"] as? Bool ?? false
        )

        let imageURL = ExternalEventSupport.preferredImageURL(from: allImageCandidates.map(Optional.some))

        return ExternalEvent(
            id: "\(source.rawValue):\(basicInfoID)",
            source: source,
            sourceEventID: basicInfoID,
            sourceParentID: basicInfo.string("organizationId"),
            sourceURL: sourceURL,
            mergedSources: [source],
            title: title,
            shortDescription: ExternalEventSupport.shortened(summary),
            fullDescription: fullDescription,
            category: category,
            subcategory: detailSubcategory.isEmpty ? nil : detailSubcategory,
            eventType: eventType,
            startAtUTC: startUTC,
            endAtUTC: endUTC,
            startLocal: startLocal,
            endLocal: endLocal,
            timezone: timezone,
            salesStartAtUTC: nil,
            salesEndAtUTC: offerInfo.availabilityEndsUTC,
            venueName: venue?.string("name") ?? listingItem.venueName,
            venueID: venue?.string("id"),
            addressLine1: listingItem.addressLine1 ?? venueAddressDisplayLines?.first,
            addressLine2: nil,
            city: venueAddress?.string("city") ?? listingItem.city,
            state: venueAddress?.string("region") ?? listingItem.state,
            postalCode: listingItem.postalCode,
            country: venueAddress?.string("country") ?? listingItem.country,
            latitude: ExternalEventSupport.parseDouble(venueAddress?["latitude"]) ?? listingItem.latitude,
            longitude: ExternalEventSupport.parseDouble(venueAddress?["longitude"]) ?? listingItem.longitude,
            imageURL: imageURL,
            fallbackThumbnailAsset: ExternalEventSupport.fallbackThumbnailAsset(for: eventType),
            status: normalizedStatus.0,
            availabilityStatus: normalizedStatus.1,
            urgencyBadge: ExternalEventSupport.urgencyBadgeForEventbriteAvailability(offerInfo.availability),
            socialProofCount: nil,
            socialProofLabel: nil,
            venuePopularityCount: nil,
            venueRating: nil,
            ticketProviderCount: nil,
            priceMin: offerInfo.lowPrice,
            priceMax: offerInfo.highPrice,
            currency: offerInfo.currency ?? basicInfo.string("currency"),
            organizerName: organizer?.string("name"),
            organizerEventCount: organizerSignals.eventsHostedCount,
            organizerVerified: organizerSignals.isVerified,
            tags: ExternalEventSupport.tags(from: [category, subcategory, format, listingItem.city, listingItem.state]),
            distanceValue: nil,
            distanceUnit: nil,
            raceType: nil,
            registrationURL: nil,
            ticketURL: sourceURL,
            rawSourcePayload: ExternalEventSupport.jsonString([
                "listing_item": listingItem.rawValue,
                "basic_info": basicInfo,
                "social_event": socialEvent as Any,
                "taxonomies": taxonomies as Any,
                "images": allImageCandidates.map { ["url": $0] },
                "gallery_images": galleryImages,
                "image_gallery": allImageCandidates,
                "meta_image": metaImageURL as Any,
                "image": imageURL as Any
            ])
        )
    }

    private func uniqueImageCandidates(_ candidates: [String]) -> [String] {
        var seen = Set<String>()
        var unique: [String] = []
        for candidate in candidates {
            guard let normalized = ExternalEventSupport.normalizedImageURLString(candidate) else { continue }
            guard seen.insert(normalized).inserted else { continue }
            unique.append(normalized)
        }
        return unique
    }

    private func extractBestImageURL(from value: Any?) -> String? {
        let candidates = imageURLCandidates(from: value).map(Optional.some)
        return ExternalEventSupport.preferredImageURL(from: candidates)
    }

    private func imageURLCandidates(from value: Any?) -> [String] {
        guard let value else { return [] }

        if let string = value as? String {
            return ExternalEventSupport.normalizedImageURLString(string).map { [$0] } ?? []
        }

        if let array = value as? [Any] {
            return array.flatMap(imageURLCandidates(from:))
        }

        if let dictionary = value as? [String: Any] {
            if let url = dictionary["url"] as? String {
                return imageURLCandidates(from: url)
            }
            return ["image", "image_url", "imageURL", "src", "content", "croppedLogoUrl940", "croppedOriginalImageUrl"]
                .flatMap { key in imageURLCandidates(from: dictionary[key]) }
        }

        return []
    }

    private func extractMetaImageURL(from html: String) -> String? {
        let patterns = [
            #"<meta[^>]+(?:property|name)=["'](?:og:image|twitter:image)["'][^>]+content=["']([^"']+)["']"#,
            #"<meta[^>]+content=["']([^"']+)["'][^>]+(?:property|name)=["'](?:og:image|twitter:image)["']"#
        ]

        for pattern in patterns {
            if let range = html.range(of: pattern, options: [.regularExpression, .caseInsensitive]) {
                let tag = String(html[range])
                if let contentRange = tag.range(of: #"content=["']([^"']+)["']"#, options: [.regularExpression, .caseInsensitive]) {
                    let content = String(tag[contentRange])
                        .replacingOccurrences(of: #"(?i)^content=["']"#, with: "", options: .regularExpression)
                        .replacingOccurrences(of: #"["']$"#, with: "", options: .regularExpression)
                    if let normalized = ExternalEventSupport.normalizedImageURLString(content) {
                        return normalized
                    }
                }
            }
        }

        return nil
    }

    private func extractOfferInfo(from socialEvent: JSONDictionary?) -> (
        availability: String?,
        lowPrice: Double?,
        highPrice: Double?,
        currency: String?,
        availabilityEndsUTC: Date?
    ) {
        guard let socialEvent else {
            return (nil, nil, nil, nil, nil)
        }

        let offersValue = socialEvent["offers"]
        let offerDictionaries: [JSONDictionary]
        switch offersValue {
        case let offers as [JSONDictionary]:
            offerDictionaries = offers
        case let offer as JSONDictionary:
            offerDictionaries = [offer]
        default:
            offerDictionaries = []
        }

        let lowPrice = offerDictionaries.compactMap {
            ExternalEventSupport.parseCurrencyAmount($0.string("lowPrice") ?? $0.string("price"))
        }.min()
        let highPrice = offerDictionaries.compactMap {
            ExternalEventSupport.parseCurrencyAmount($0.string("highPrice") ?? $0.string("price"))
        }.max()
        let currency = offerDictionaries.compactMap { $0.string("priceCurrency") }.first
        let availability = offerDictionaries.compactMap { $0.string("availability") }.first
        let availabilityEndsUTC = offerDictionaries.compactMap {
            ExternalEventSupport.ticketmasterDate($0.string("availabilityEnds") ?? $0.string("validThrough"))
        }.min()

        return (availability, lowPrice, highPrice, currency, availabilityEndsUTC)
    }

    private func extractOrganizerSignals(from html: String) -> (isVerified: Bool?, eventsHostedCount: Int?) {
        let isVerified: Bool? = {
            if html.contains("This organizer is verified!") { return true }
            if html.contains("\"verified\":true") { return true }
            if html.contains("\"verified\":false") { return false }
            return nil
        }()

        let pattern = #"<span class=\"OrganizerStats_label[^"]*\">([^<]+)</span><span class=\"OrganizerStats_data[^"]*\">([^<]+)</span>"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: []) else {
            return (isVerified, nil)
        }

        let nsRange = NSRange(html.startIndex..<html.endIndex, in: html)
        var eventsHostedCount: Int?
        regex.enumerateMatches(in: html, options: [], range: nsRange) { match, _, stop in
            guard let match,
                  match.numberOfRanges >= 3,
                  let labelRange = Range(match.range(at: 1), in: html),
                  let valueRange = Range(match.range(at: 2), in: html)
            else {
                return
            }

            let label = ExternalEventSupport.normalizeToken(String(html[labelRange]))
            guard label == "events" else { return }

            let rawValue = String(html[valueRange])
            let digits = rawValue.replacingOccurrences(of: "[^0-9]", with: "", options: .regularExpression)
            eventsHostedCount = Int(digits)
            stop.pointee = true
        }

        return (isVerified, eventsHostedCount)
    }

    private func extractSocialEventSchema(from html: String) -> JSONDictionary? {
        for jsonValue in extractJSONLDScripts(from: html) {
            guard let payload = jsonValue as? JSONDictionary else { continue }
            let type = payload.string("@type")
            if type == "SocialEvent" || type == "Event" {
                return payload
            }
        }
        return nil
    }

    private func extractJSONLDScripts(from html: String) -> [Any] {
        let pattern = #"<script[^>]*type=\"application/ld\+json\"[^>]*>(.*?)</script>"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive, .dotMatchesLineSeparators]) else {
            return []
        }

        let nsRange = NSRange(html.startIndex..<html.endIndex, in: html)
        return regex.matches(in: html, options: [], range: nsRange).compactMap { match in
            guard match.numberOfRanges > 1,
                  let range = Range(match.range(at: 1), in: html)
            else {
                return nil
            }

            let body = html[range].trimmingCharacters(in: .whitespacesAndNewlines)
            guard let data = body.data(using: .utf8) else { return nil }
            return try? JSONSerialization.jsonObject(with: data)
        }
    }

    private func extractNextData(from html: String) -> JSONDictionary? {
        let pattern = #"<script id=\"__NEXT_DATA__\" type=\"application/json\">(.*?)</script>"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.dotMatchesLineSeparators]) else {
            return nil
        }

        let nsRange = NSRange(html.startIndex..<html.endIndex, in: html)
        guard let match = regex.firstMatch(in: html, options: [], range: nsRange),
              match.numberOfRanges > 1,
              let range = Range(match.range(at: 1), in: html)
        else {
            return nil
        }

        let body = html[range].trimmingCharacters(in: .whitespacesAndNewlines)
        guard let data = body.data(using: .utf8) else { return nil }
        return try? ExternalEventSupport.decodeJSONDictionary(data)
    }

    private func slugify(_ value: String) -> String {
        ExternalEventSupport.normalizeToken(value).replacingOccurrences(of: " ", with: "-")
    }
}
