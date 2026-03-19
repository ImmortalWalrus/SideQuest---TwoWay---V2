import CryptoKit
import Foundation

typealias JSONDictionary = [String: Any]

enum ExternalEventSupport {
    static let iso8601Formatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    static let iso8601NoFractionalSeconds: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter
    }()

    static func decodeJSONDictionary(_ data: Data) throws -> JSONDictionary {
        guard let json = try JSONSerialization.jsonObject(with: data) as? JSONDictionary else {
            throw ExternalEventIngestionError.invalidJSON
        }
        return json
    }

    static func jsonString(_ value: Any) -> String {
        guard let sanitizedValue = sanitizedJSONValue(value) else {
            return "{}"
        }

        let rootObject: Any
        if JSONSerialization.isValidJSONObject(sanitizedValue) {
            rootObject = sanitizedValue
        } else {
            rootObject = ["value": sanitizedValue]
        }

        guard let data = try? JSONSerialization.data(withJSONObject: rootObject, options: [.sortedKeys]),
              let string = String(data: data, encoding: .utf8)
        else {
            return "{}"
        }
        return string
    }

    private static func sanitizedJSONValue(_ value: Any) -> Any? {
        let mirror = Mirror(reflecting: value)
        if mirror.displayStyle == .optional {
            guard let child = mirror.children.first else { return nil }
            return sanitizedJSONValue(child.value)
        }

        switch value {
        case let dictionary as [String: Any]:
            var sanitized: [String: Any] = [:]
            for (key, nestedValue) in dictionary {
                if let cleaned = sanitizedJSONValue(nestedValue) {
                    sanitized[key] = cleaned
                }
            }
            return sanitized
        case let dictionary as NSDictionary:
            var sanitized: [String: Any] = [:]
            for (key, nestedValue) in dictionary {
                guard let key = key as? String,
                      let cleaned = sanitizedJSONValue(nestedValue) else {
                    continue
                }
                sanitized[key] = cleaned
            }
            return sanitized
        case let array as [Any]:
            return array.compactMap { sanitizedJSONValue($0) }
        case let array as NSArray:
            return array.compactMap { sanitizedJSONValue($0) }
        case let date as Date:
            return iso8601Formatter.string(from: date)
        case let url as URL:
            return url.absoluteString
        case is NSNull:
            return NSNull()
        case let string as String:
            return string
        case let bool as Bool:
            return bool
        case let int as Int:
            return int
        case let int8 as Int8:
            return Int(int8)
        case let int16 as Int16:
            return Int(int16)
        case let int32 as Int32:
            return Int(int32)
        case let int64 as Int64:
            return int64
        case let uint as UInt:
            return uint
        case let uint8 as UInt8:
            return UInt(uint8)
        case let uint16 as UInt16:
            return UInt(uint16)
        case let uint32 as UInt32:
            return uint32
        case let uint64 as UInt64:
            return uint64
        case let double as Double:
            return double.isFinite ? double : nil
        case let float as Float:
            return float.isFinite ? Double(float) : nil
        case let number as NSNumber:
            return number
        default:
            let fallback = String(describing: value).trimmingCharacters(in: .whitespacesAndNewlines)
            return fallback.isEmpty ? nil : fallback
        }
    }

    static func normalizedDedupKey(
        title: String,
        eventType: ExternalEventType,
        startLocal: String?,
        startAtUTC: Date?,
        timezone: String?,
        venueName: String?,
        city: String?,
        state: String?,
        latitude: Double?,
        longitude: Double?
    ) -> String {
        let dayToken = localDayToken(startLocal: startLocal, startAtUTC: startAtUTC, timezone: timezone)
        let titleToken = dedupeTitleFingerprint(title, eventType: eventType, venueName: venueName)
        let locationBits = [
            eventType == .sportsEvent ? "" : normalizeToken(venueName),
            normalizeToken(city),
            normalizeStateToken(state),
            latitude.map { String(format: "%.0f", $0) } ?? "",
            longitude.map { String(format: "%.0f", $0) } ?? ""
        ]
        return [
            titleToken,
            dayToken,
            locationBits.joined(separator: "|")
        ].joined(separator: "::")
    }

    static func dedupeBucketKey(for event: ExternalEvent) -> String {
        let dayToken = localDayToken(
            startLocal: event.startLocal,
            startAtUTC: event.startAtUTC,
            timezone: event.timezone
        )
        let titleTokens = dedupeTitleFingerprint(
            event.title,
            eventType: event.eventType,
            venueName: event.venueName
        )
        .split(separator: " ")
        .map(String.init)
        let titleSeed = titleTokens.prefix(3).joined(separator: " ")
        let locationSeed = [
            event.eventType == .sportsEvent ? "" : normalizeToken(event.venueName ?? event.addressLine1),
            normalizeToken(event.city),
            normalizeStateToken(event.state)
        ]
            .filter { !$0.isEmpty }
            .joined(separator: "|")
        return [dayToken, titleSeed, locationSeed].joined(separator: "::")
    }

    static func normalizeToken(_ value: String?) -> String {
        guard let value else { return "" }
        let lowered = value.lowercased()
        let allowed = lowered.unicodeScalars.map { scalar -> Character in
            CharacterSet.alphanumerics.contains(scalar) ? Character(String(scalar)) : " "
        }
        return String(allowed)
            .split(separator: " ")
            .joined(separator: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static func normalizeStateToken(_ value: String?) -> String {
        let normalized = normalizeToken(value)
        guard !normalized.isEmpty else { return "" }

        let stateMap: [String: String] = [
            "california": "ca",
            "ca": "ca",
            "new york": "ny",
            "ny": "ny",
            "nevada": "nv",
            "nv": "nv",
            "illinois": "il",
            "il": "il",
            "texas": "tx",
            "tx": "tx",
            "florida": "fl",
            "fl": "fl",
            "colorado": "co",
            "co": "co",
            "arizona": "az",
            "az": "az",
            "washington": "wa",
            "wa": "wa",
            "oregon": "or",
            "or": "or",
            "south carolina": "sc",
            "sc": "sc"
        ]

        if let mapped = stateMap[normalized] {
            return mapped
        }

        if let firstToken = normalized.split(separator: " ").first {
            let first = String(firstToken)
            return stateMap[first] ?? first
        }

        return normalized
    }

    static func isLikelyStreetAddress(_ value: String?) -> Bool {
        guard let value else { return false }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return false }

        if trimmed.rangeOfCharacter(from: .decimalDigits) != nil {
            return true
        }

        let streetTokens: Set<String> = [
            "alley", "aly",
            "avenue", "ave",
            "boulevard", "blvd",
            "circle", "cir",
            "court", "ct",
            "drive", "dr",
            "highway", "hwy",
            "lane", "ln",
            "parkway", "pkwy",
            "place", "pl",
            "road", "rd",
            "square", "sq",
            "street", "st",
            "suite", "ste",
            "terrace", "ter",
            "trail", "trl",
            "way"
        ]

        return normalizeToken(trimmed)
            .split(separator: " ")
            .contains(where: { streetTokens.contains(String($0)) })
    }

    static func isWeakAddressLine(_ value: String?, city: String?, state: String?) -> Bool {
        let normalizedValue = normalizeToken(value)
        guard !normalizedValue.isEmpty else { return true }

        let normalizedCity = normalizeToken(city)
        let normalizedState = normalizeStateToken(state)
        let localityCandidates = Set([
            normalizedCity,
            normalizedState,
            [normalizedCity, normalizedState].filter { !$0.isEmpty }.joined(separator: " "),
            [normalizedState, normalizedCity].filter { !$0.isEmpty }.joined(separator: " ")
        ].filter { !$0.isEmpty })

        if localityCandidates.contains(normalizedValue) {
            return true
        }

        if isLikelyStreetAddress(value) {
            return false
        }

        let localityTokens = Set(([normalizedCity, normalizedState].filter { !$0.isEmpty })
            .flatMap { $0.split(separator: " ").map(String.init) })
        let valueTokens = Set(normalizedValue.split(separator: " ").map(String.init))

        if !valueTokens.isEmpty, !localityTokens.isEmpty, valueTokens.isSubset(of: localityTokens) {
            return true
        }

        return false
    }

    static func preferredAddressLine(
        primary: String?,
        primaryCity: String?,
        primaryState: String?,
        secondary: String?,
        secondaryCity: String?,
        secondaryState: String?
    ) -> String? {
        guard let secondary, !secondary.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return primary
        }
        guard let primary, !primary.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return secondary
        }

        let normalizedPrimary = normalizeToken(primary)
        let normalizedSecondary = normalizeToken(secondary)
        if normalizedPrimary == normalizedSecondary {
            return primary
        }

        let primaryWeak = isWeakAddressLine(primary, city: primaryCity, state: primaryState)
        let secondaryWeak = isWeakAddressLine(secondary, city: secondaryCity, state: secondaryState)
        let primaryStreet = isLikelyStreetAddress(primary)
        let secondaryStreet = isLikelyStreetAddress(secondary)

        if primaryWeak && !secondaryWeak {
            return secondary
        }
        if secondaryWeak && !primaryWeak {
            return primary
        }
        if secondaryStreet && !primaryStreet {
            return secondary
        }
        if primaryStreet && !secondaryStreet {
            return primary
        }
        if secondary.count > primary.count + 8 {
            return secondary
        }
        return primary
    }

    static func googleReviewURLNeedsIdentityValidation(_ reviewURL: String) -> Bool {
        let normalized = reviewURL.lowercased()
        return normalized.contains("/maps/search/")
            || normalized.contains("/maps/place/")
            || normalized.contains("query=")
    }

    static func googleReviewIdentityScore(
        venueNames: [String?],
        addressLine1: String?,
        city: String?,
        state: String?,
        postalCode: String?,
        candidateTitle: String? = nil,
        reviewURL: String?
    ) -> Int {
        let normalizedAddress = normalizeToken(addressLine1)
        let normalizedCity = normalizeToken(city)
        let normalizedState = normalizeStateToken(state)
        let normalizedPostalCode = normalizedPostalCode(postalCode)
        let urlContext = googleReviewURLContext(reviewURL)
        let candidateContext = normalizeToken(
            [candidateTitle, urlContext.context]
                .compactMap { $0 }
                .joined(separator: " ")
        )
        let addressMatch = !normalizedAddress.isEmpty && candidateContext.contains(normalizedAddress)
        let localityMatch =
            (!normalizedPostalCode.isEmpty && candidateContext.contains(normalizedPostalCode))
            || (
                !normalizedCity.isEmpty
                && candidateContext.contains(normalizedCity)
                && (normalizedState.isEmpty || candidateContext.contains(normalizedState))
            )
        let hasCandidateAddressDigits = candidateContext.split(separator: " ").contains {
            $0.rangeOfCharacter(from: .decimalDigits) != nil
        }
        let candidateNames = Set([
            normalizeToken(candidateTitle),
            urlContext.primaryName
        ].filter { !$0.isEmpty })

        guard !candidateNames.isEmpty else { return 0 }

        var bestScore = 0
        for venueName in venueNames {
            let normalizedVenueName = normalizeToken(venueName)
            guard !normalizedVenueName.isEmpty else { continue }

            for candidateName in candidateNames {
                let score = googleReviewVenueIdentityScore(
                    expectedVenueName: normalizedVenueName,
                    candidateName: candidateName,
                    addressMatch: addressMatch,
                    localityMatch: localityMatch,
                    hasCandidateAddressDigits: hasCandidateAddressDigits,
                    hasExpectedAddress: !normalizedAddress.isEmpty
                )
                bestScore = max(bestScore, score)
            }
        }

        return bestScore
    }

    static func googleReviewURLMatchesIdentity(
        _ reviewURL: String,
        venueNames: [String?],
        addressLine1: String?,
        city: String?,
        state: String?,
        postalCode: String?
    ) -> Bool {
        googleReviewIdentityScore(
            venueNames: venueNames,
            addressLine1: addressLine1,
            city: city,
            state: state,
            postalCode: postalCode,
            reviewURL: reviewURL
        ) > 0
    }

    static func sanitizedGoogleReviewIdentity(_ event: ExternalEvent) -> ExternalEvent {
        guard var payload = payloadDictionary(from: event.rawSourcePayload) else {
            return event
        }

        var sanitized = event
        let invalidRatingKeys = googleReviewRatingKeys.filter { isJSONBoolean(payload[$0]) }
        let invalidReviewCountKeys = googleReviewReviewCountKeys.filter { isJSONBoolean(payload[$0]) }

        if !invalidRatingKeys.isEmpty || !invalidReviewCountKeys.isEmpty {
            invalidRatingKeys.forEach { payload.removeValue(forKey: $0) }
            invalidReviewCountKeys.forEach { payload.removeValue(forKey: $0) }

            if !invalidRatingKeys.isEmpty,
               let currentRating = sanitized.venueRating,
               abs(currentRating - 1.0) < 0.05 {
                sanitized.venueRating = nil
            }

            if !invalidReviewCountKeys.isEmpty,
               let currentReviewCount = sanitized.venuePopularityCount,
               currentReviewCount == 1 {
                sanitized.venuePopularityCount = nil
            }

            if let data = try? JSONSerialization.data(withJSONObject: payload, options: [.sortedKeys]),
               let rawPayload = String(data: data, encoding: .utf8) {
                sanitized.rawSourcePayload = rawPayload
            }
        }

        guard let reviewURL = firstPayloadString(
            payload,
            keys: ["google_places_url", "google_maps_uri", "google_places_google_maps_uri"]
        ),
        googleReviewURLNeedsIdentityValidation(reviewURL),
        !googleReviewURLMatchesIdentity(
            reviewURL,
            venueNames: [sanitized.venueName, sanitized.title],
            addressLine1: sanitized.addressLine1,
            city: sanitized.city,
            state: sanitized.state,
            postalCode: sanitized.postalCode
        ) else {
            return sanitized
        }

        let removedRating = firstPayloadDouble(
            payload,
            keys: googleReviewRatingKeys
        )
        let removedReviewCount = firstPayloadInt(
            payload,
            keys: googleReviewReviewCountKeys
        )

        [
            "google_places_rating",
            "google_places_user_rating_count",
            "google_places_userRatingCount",
            "google_places_url",
            "google_maps_uri",
            "google_places_google_maps_uri",
            "google_review_signal_source"
        ].forEach { payload.removeValue(forKey: $0) }

        if let removedRating,
           let currentRating = sanitized.venueRating,
           abs(currentRating - removedRating) < 0.05 {
            sanitized.venueRating = nil
        }

        if let removedReviewCount,
           let currentReviewCount = sanitized.venuePopularityCount,
           currentReviewCount == removedReviewCount {
            sanitized.venuePopularityCount = nil
        }

        if let data = try? JSONSerialization.data(withJSONObject: payload, options: [.sortedKeys]),
           let rawPayload = String(data: data, encoding: .utf8) {
            sanitized.rawSourcePayload = rawPayload
        }

        return sanitized
    }

    private static let googleReviewRatingKeys = [
        "google_places_rating",
        "google_rating",
        "venue_rating",
        "rating"
    ]

    private static let googleReviewReviewCountKeys = [
        "google_places_user_rating_count",
        "google_places_userRatingCount",
        "userRatingCount",
        "ratingCount",
        "review_count",
        "reviewCount",
        "reviews"
    ]

    private static func isJSONBoolean(_ value: Any?) -> Bool {
        if value is Bool {
            return true
        }
        guard let number = value as? NSNumber else {
            return false
        }
        return CFGetTypeID(number) == CFBooleanGetTypeID()
    }

    private static let googleReviewArticleTokens: Set<String> = [
        "a", "an", "the", "la", "le", "l", "el", "los", "las", "de", "del", "da", "di", "du"
    ]

    private static let googleReviewVenueDescriptorTokens: Set<String> = [
        "bar", "bistro", "cafe", "club", "cocktail", "grill", "hall", "hotel", "kitchen",
        "lounge", "music", "night", "nightclub", "pub", "restaurant", "room", "rooftop",
        "saloon", "supperclub", "theater", "theatre", "venue"
    ]

    private static func normalizedPostalCode(_ value: String?) -> String {
        guard let value else { return "" }
        let digits = value.filter(\.isNumber)
        if digits.count >= 5 {
            return String(digits.prefix(5))
        }
        return digits
    }

    private static func googleReviewVenueIdentityScore(
        expectedVenueName: String,
        candidateName: String,
        addressMatch: Bool,
        localityMatch: Bool,
        hasCandidateAddressDigits: Bool,
        hasExpectedAddress: Bool
    ) -> Int {
        guard !expectedVenueName.isEmpty, !candidateName.isEmpty else { return 0 }

        if expectedVenueName == candidateName {
            if hasExpectedAddress && hasCandidateAddressDigits && !addressMatch {
                return 0
            }
            if addressMatch { return 14 }
            if localityMatch { return 11 }
            return 8
        }

        let expectedTokens = googleReviewIdentityTokens(from: expectedVenueName)
        let candidateTokens = googleReviewIdentityTokens(from: candidateName)
        guard !expectedTokens.isEmpty, !candidateTokens.isEmpty else { return 0 }

        let sharedTokens = expectedTokens.intersection(candidateTokens)
        guard !sharedTokens.isEmpty else { return 0 }

        if hasExpectedAddress && hasCandidateAddressDigits && !addressMatch && expectedTokens.count <= 2 {
            return 0
        }

        if expectedTokens.count == 1 {
            guard let token = expectedTokens.first, candidateTokens.contains(token) else {
                return 0
            }
            let extras = candidateTokens.subtracting([token])
            if extras.isEmpty {
                if addressMatch { return 13 }
                if localityMatch { return 9 }
                return 5
            }
            guard addressMatch, extras.isSubset(of: googleReviewVenueDescriptorTokens) else {
                return 0
            }
            return 11
        }

        guard expectedTokens.isSubset(of: candidateTokens) else {
            if addressMatch && expectedTokens.count >= 3 && sharedTokens.count == expectedTokens.count - 1 {
                return 7
            }
            return 0
        }

        let extras = candidateTokens.subtracting(expectedTokens)
        if extras.isEmpty {
            if addressMatch { return 13 }
            if localityMatch { return 10 }
            return 6
        }
        if extras.isSubset(of: googleReviewVenueDescriptorTokens) {
            if addressMatch { return 10 }
            if localityMatch { return 7 }
            return 5
        }
        if addressMatch && extras.count == 1 {
            return 8
        }
        return 0
    }

    private static func googleReviewIdentityTokens(from normalizedValue: String) -> Set<String> {
        Set(normalizedValue.split(separator: " ").map(String.init))
            .subtracting(googleReviewArticleTokens)
    }

    private static func googleReviewURLContext(_ reviewURL: String?) -> (primaryName: String, context: String) {
        guard let reviewURL = reviewURL?.trimmingCharacters(in: .whitespacesAndNewlines),
              !reviewURL.isEmpty else {
            return ("", "")
        }

        var fragments: [String] = []
        if let url = URL(string: reviewURL),
           let components = URLComponents(url: url, resolvingAgainstBaseURL: false) {
            let interestingQueryItems = Set(["query", "q", "destination", "daddr", "place"])
            for item in components.queryItems ?? [] {
                guard interestingQueryItems.contains(item.name.lowercased()),
                      let value = item.value,
                      !value.isEmpty else {
                    continue
                }
                fragments.append(decodedGoogleReviewURLFragment(value))
            }

            let pathComponents = components.path
                .split(separator: "/")
                .map { decodedGoogleReviewURLFragment(String($0)) }

            for marker in ["search", "place"] {
                guard let index = pathComponents.firstIndex(where: { normalizeToken($0) == marker }) else {
                    continue
                }
                let tail = pathComponents[(index + 1)...]
                    .prefix { component in
                        let normalized = normalizeToken(component)
                        return !normalized.isEmpty
                            && normalized != "data"
                            && normalized.hasPrefix("@") == false
                    }
                    .joined(separator: " ")
                if !tail.isEmpty {
                    fragments.append(tail)
                }
            }
        }

        if fragments.isEmpty {
            fragments.append(reviewURL.removingPercentEncoding ?? reviewURL)
        }

        let normalizedFragments = fragments
            .map(normalizeToken)
            .filter { !$0.isEmpty }
        let primaryName = normalizedFragments.lazy
            .map(googleReviewPrimaryNameFragment)
            .first(where: { !$0.isEmpty }) ?? ""
        return (primaryName, normalizeToken(normalizedFragments.joined(separator: " ")))
    }

    private static func decodedGoogleReviewURLFragment(_ value: String) -> String {
        let plusDecoded = value.replacingOccurrences(of: "+", with: " ")
        return plusDecoded.removingPercentEncoding ?? plusDecoded
    }

    private static func googleReviewPrimaryNameFragment(_ value: String) -> String {
        let tokens = value.split(separator: " ").map(String.init)
        guard !tokens.isEmpty else { return "" }
        let cutoffIndex = tokens.firstIndex(where: { token in
            token.rangeOfCharacter(from: .decimalDigits) != nil
        }) ?? tokens.count
        return tokens.prefix(cutoffIndex).joined(separator: " ")
    }

    private static func payloadDictionary(from rawPayload: String) -> [String: Any]? {
        guard let data = rawPayload.data(using: .utf8),
              let payload = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }
        return payload
    }

    private static func firstPayloadString(
        _ payload: [String: Any],
        keys: [String]
    ) -> String? {
        for key in keys {
            guard let value = payload[key] as? String else { continue }
            let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty {
                return trimmed
            }
        }
        return nil
    }

    private static func firstPayloadDouble(
        _ payload: [String: Any],
        keys: [String]
    ) -> Double? {
        for key in keys {
            if let value = parseDouble(payload[key]) {
                return value
            }
        }
        return nil
    }

    private static func firstPayloadInt(
        _ payload: [String: Any],
        keys: [String]
    ) -> Int? {
        for key in keys {
            if let value = parseInt(payload[key]) {
                return value
            }
        }
        return nil
    }

    static func localDayToken(startLocal: String?, startAtUTC: Date?, timezone: String?) -> String {
        if let startLocal {
            let localDate = String(startLocal.split(separator: "T").first ?? "")
            if !localDate.isEmpty {
                return localDate
            }
        }
        if let startAtUTC {
            let formatter = DateFormatter()
            formatter.locale = Locale(identifier: "en_US_POSIX")
            formatter.dateFormat = "yyyy-MM-dd"
            formatter.timeZone = timezone.flatMap(TimeZone.init(identifier:)) ?? .current
            return formatter.string(from: startAtUTC)
        }
        return "unknown-day"
    }

    static func dedupeTitleFingerprint(_ title: String, eventType: ExternalEventType, venueName: String?) -> String {
        if eventType == .sportsEvent,
           let sportsFingerprint = sportsMatchupFingerprint(title) {
            return sportsFingerprint
        }

        var normalized = normalizeToken(title)
        if let venueName, !venueName.isEmpty {
            let venueToken = normalizeToken(venueName)
            if !venueToken.isEmpty {
                normalized = normalized.replacingOccurrences(of: " at \(venueToken)", with: " ")
                normalized = normalized.replacingOccurrences(of: " live at \(venueToken)", with: " ")
            }
        }

        let stopwords = Set([
            "the", "and", "with", "live", "presented", "official", "event", "tickets",
            "show", "night", "club", "featuring", "feat", "tour", "experience", "saturday",
            "friday", "sunday", "monday", "tuesday", "wednesday", "thursday"
        ])
        let tokens = normalized
            .split(separator: " ")
            .map(String.init)
            .filter { token in
                token.count > 1 && !stopwords.contains(token)
            }
        let fingerprint = Array(Set(tokens)).sorted().joined(separator: " ")
        return fingerprint.isEmpty ? normalized : fingerprint
    }

    static func titleTokenSet(for event: ExternalEvent) -> Set<String> {
        Set(
            dedupeTitleFingerprint(event.title, eventType: event.eventType, venueName: event.venueName)
                .split(separator: " ")
                .map(String.init)
        )
    }

    static func isLosAngelesMetroSearchLocation(city: String?, state: String?) -> Bool {
        let normalizedCity = normalizeToken(city)
        let normalizedState = normalizeStateToken(state)
        guard normalizedState == "ca" else { return false }
        return losAngelesMetroTokens.contains(normalizedCity)
    }

    static func isLosAngelesMetroToken(_ token: String) -> Bool {
        losAngelesMetroTokens.contains(normalizeToken(token))
    }

    static func isLosAngelesMetroEvent(_ event: ExternalEvent) -> Bool {
        guard normalizeStateToken(event.state) == "ca" else { return false }
        if losAngelesMetroTokens.contains(normalizeToken(event.city)) {
            return true
        }

        let haystack = searchableHaystack(for: event)
        if losAngelesMetroTokens.contains(where: haystack.contains) {
            return true
        }

        return trustedVenueScore(for: event) >= 12
    }

    static func sharesMetroArea(
        event: ExternalEvent,
        preferredCity: String?,
        preferredState: String?
    ) -> Bool {
        let normalizedPreferredCity = normalizeToken(preferredCity)
        let normalizedPreferredState = normalizeStateToken(preferredState)
        guard !normalizedPreferredCity.isEmpty || !normalizedPreferredState.isEmpty else { return false }

        let eventCity = normalizeToken(event.city)
        let eventState = normalizeStateToken(event.state)
        if !normalizedPreferredCity.isEmpty,
           !eventCity.isEmpty,
           normalizedPreferredCity == eventCity,
           (normalizedPreferredState.isEmpty || normalizedPreferredState == eventState)
        {
            return true
        }

        let haystack = searchableHaystack(for: event)
        if !normalizedPreferredCity.isEmpty, haystack.contains(normalizedPreferredCity),
           normalizedPreferredState.isEmpty || haystack.contains(normalizedPreferredState)
        {
            return true
        }

        return false
    }

    static func timeZoneIdentifier(latitude: Double, longitude: Double) -> String {
        if longitude <= -125 {
            return "Pacific/Honolulu"
        }
        if longitude <= -114 {
            if latitude > 42, longitude > -118 {
                return "America/Boise"
            }
            return "America/Los_Angeles"
        }
        if longitude <= -101 {
            return "America/Denver"
        }
        if longitude <= -84 {
            return "America/Chicago"
        }
        return "America/New_York"
    }

    static func marqueeEventBoost(for event: ExternalEvent) -> Int {
        let haystack = searchableHaystack(for: event)
        var score = 0

        let majorLeagueTokens = [
            "nba", "nfl", "mlb", "nhl", "mls", "wnba", "ncaa", "college basketball",
            "college football", "ufc", "mma", "boxing", "wrestling", "formula 1", "nascar"
        ]
        let headlineVenueTokens = [
            "stadium", "arena", "dome", "garden", "forum", "ballpark", "field",
            "speedway", "pavilion", "amphitheater", "auditorium", "music hall", "ballroom"
        ]
        let headlineConcertTokens = [
            "festival", "headline", "world tour", "arena tour", "live nation", "aeg",
            "orchestra", "symphony"
        ]
        let premiumNightlifeTokens = [
            "bottle service", "vip table", "guest list", "table minimum", "reservation required",
            "members only", "private club", "dress code", "hard door", "supper club", "rooftop lounge"
        ]

        if event.eventType == .sportsEvent, majorLeagueTokens.contains(where: haystack.contains) {
            score += 16
        }
        if headlineVenueTokens.contains(where: haystack.contains) {
            score += 10
        }
        if event.eventType == .concert, headlineConcertTokens.contains(where: haystack.contains) {
            score += 8
        }
        if premiumNightlifeTokens.contains(where: haystack.contains) {
            score += 10
        }
        if event.ticketProviderCount ?? 0 >= 2 {
            score += 6
        }
        if event.mergedSources.count > 1 {
            score += 5
        }
        if trustedVenueScore(for: event) >= 16 {
            score += 8
        }
        if event.eventType == .sportsEvent {
            score += 8
        }
        if isMainstreamHeadlineEvent(event) {
            score += 10
        }
        if looksAncillaryInventory(event) {
            score -= 14
        }

        return score
    }

    static func isMainstreamHeadlineEvent(_ event: ExternalEvent) -> Bool {
        let haystack = searchableHaystack(for: event)
        if event.eventType == .sportsEvent {
            let teamSignals = [
                "lakers", "clippers", "dodgers", "kings", "galaxy", "lafc", "angel city",
                "yankees", "knicks", "mets", "rangers", "heat", "mavericks", "cowboys",
                "bulls", "cubs", "white sox", "golden state", "warriors", "49ers"
            ]
            return teamSignals.contains(where: haystack.contains) || sportsMatchupFingerprint(event.title) != nil
        }
        if event.eventType == .concert {
            return haystack.contains("tour")
                || haystack.contains("headline")
                || haystack.contains("live nation")
                || haystack.contains("aeg")
                || (event.venuePopularityCount ?? 0) >= 40
        }
        return false
    }

    static func looksAncillaryInventory(_ event: ExternalEvent) -> Bool {
        let haystack = searchableHaystack(for: event)
        let ancillaryTokens = [
            "parking",
            "trackside",
            "hospitality",
            "vip package",
            "premium seating",
            "food package",
            "burger",
            "club access",
            "suite",
            "tailgate package"
        ]
        guard ancillaryTokens.contains(where: haystack.contains) else { return false }
        return event.source == .ticketmaster || event.source == .seatGeek || event.source == .stubHub
    }

    static func sportsMatchupFingerprint(_ title: String) -> String? {
        let normalized = normalizeToken(title)
        let separators = [" at ", " vs ", " versus ", " v "]
        for separator in separators {
            let pieces = normalized.components(separatedBy: separator)
            guard pieces.count >= 2 else { continue }
            let left = pieces[0].trimmingCharacters(in: .whitespacesAndNewlines)
            let right = pieces[1].trimmingCharacters(in: .whitespacesAndNewlines)
            guard !left.isEmpty, !right.isEmpty else { continue }
            return [left, right].sorted().joined(separator: " vs ")
        }
        return nil
    }

    static func plainText(_ htmlOrText: String?) -> String? {
        guard let htmlOrText, !htmlOrText.isEmpty else { return nil }
        var sanitized = htmlOrText
        let replacements: [(String, String)] = [
            (#"\\u003c"#, "<"),
            (#"\\u003e"#, ">"),
            (#"\\u0026"#, "&"),
            (#"\\/"#, "/"),
            (#"\r"#, " "),
            (#"\n"#, " "),
            (#"\t"#, " "),
            ("<br>", " "),
            ("<br/>", " "),
            ("<br />", " "),
            ("&nbsp;", " "),
            ("&amp;", "&"),
            ("&#39;", "'"),
            ("&quot;", "\""),
            ("&apos;", "'"),
            ("&ldquo;", "\""),
            ("&rdquo;", "\""),
            ("&lsquo;", "'"),
            ("&rsquo;", "'"),
            ("&ndash;", "-"),
            ("&mdash;", "-"),
            ("&hellip;", "...")
        ]
        replacements.forEach { sanitized = sanitized.replacingOccurrences(of: $0.0, with: $0.1) }
        sanitized = sanitized.replacingOccurrences(
            of: #"(?is)<script\b[^>]*>[\s\S]*?</script>"#,
            with: " ",
            options: .regularExpression
        )
        sanitized = sanitized.replacingOccurrences(
            of: #"(?is)<style\b[^>]*>[\s\S]*?</style>"#,
            with: " ",
            options: .regularExpression
        )
        sanitized = sanitized.replacingOccurrences(
            of: #"(?is)<!--[\s\S]*?-->"#,
            with: " ",
            options: .regularExpression
        )
        sanitized = decodeEscapedUnicodeScalars(in: sanitized)
        sanitized = decodeNumericHTMLEntities(in: sanitized)
        sanitized = decodeNamedHTMLEntities(in: sanitized)

        sanitized = sanitized.replacingOccurrences(
            of: "<[^>]+>",
            with: " ",
            options: .regularExpression
        )
        sanitized = sanitized.replacingOccurrences(
            of: "&[^;\\s]{2,12};",
            with: " ",
            options: .regularExpression
        )
        sanitized = sanitized.replacingOccurrences(
            of: "\\s+",
            with: " ",
            options: .regularExpression
        )
        let trimmed = sanitized.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private static func decodeNamedHTMLEntities(in text: String) -> String {
        let entities: [String: String] = [
            "&nbsp;": " ",
            "&amp;": "&",
            "&quot;": "\"",
            "&apos;": "'",
            "&rsquo;": "'",
            "&lsquo;": "'",
            "&rdquo;": "\"",
            "&ldquo;": "\"",
            "&mdash;": "-",
            "&ndash;": "-",
            "&hellip;": "...",
            "&middot;": "·",
            "&bull;": "•",
            "&copy;": "©",
            "&reg;": "®",
            "&trade;": "™"
        ]
        var result = text
        for (entity, replacement) in entities {
            result = result.replacingOccurrences(of: entity, with: replacement, options: .caseInsensitive)
        }
        return result
    }

    private static func decodeNumericHTMLEntities(in text: String) -> String {
        guard let regex = try? NSRegularExpression(pattern: #"&#(?:x([0-9a-fA-F]+)|([0-9]+));"#) else {
            return text
        }
        let matches = regex.matches(in: text, range: NSRange(text.startIndex..<text.endIndex, in: text))
        guard !matches.isEmpty else { return text }

        var result = text
        for match in matches.reversed() {
            let replacement: String
            if let hexRange = Range(match.range(at: 1), in: result), !hexRange.isEmpty {
                replacement = scalarString(from: String(result[hexRange]), radix: 16)
            } else if let decimalRange = Range(match.range(at: 2), in: result), !decimalRange.isEmpty {
                replacement = scalarString(from: String(result[decimalRange]), radix: 10)
            } else {
                continue
            }

            guard let fullRange = Range(match.range(at: 0), in: result) else { continue }
            result.replaceSubrange(fullRange, with: replacement)
        }
        return result
    }

    private static func decodeEscapedUnicodeScalars(in text: String) -> String {
        guard let regex = try? NSRegularExpression(pattern: #"\\u([0-9a-fA-F]{4})"#) else {
            return text
        }
        let matches = regex.matches(in: text, range: NSRange(text.startIndex..<text.endIndex, in: text))
        guard !matches.isEmpty else { return text }

        var result = text
        for match in matches.reversed() {
            guard let scalarRange = Range(match.range(at: 1), in: result),
                  let fullRange = Range(match.range(at: 0), in: result) else {
                continue
            }
            let replacement = scalarString(from: String(result[scalarRange]), radix: 16)
            result.replaceSubrange(fullRange, with: replacement)
        }
        return result
    }

    private static func scalarString(from value: String, radix: Int) -> String {
        guard let scalarValue = UInt32(value, radix: radix),
              let scalar = UnicodeScalar(scalarValue) else {
            return " "
        }
        return String(scalar)
    }

    static func shortened(_ text: String?, maxLength: Int = 180) -> String? {
        guard let text else { return nil }
        guard text.count > maxLength else { return text }
        return String(text.prefix(maxLength)).trimmingCharacters(in: .whitespacesAndNewlines) + "..."
    }

    static func uniqueMeaningfulLines(_ values: [String?]) -> [String] {
        var output: [String] = []
        for value in values {
            guard let cleaned = plainText(value), !cleaned.isEmpty else { continue }
            guard hasSubstantiveNovelty(cleaned, comparedTo: output.map(Optional.some)) else { continue }
            output.append(cleaned)
        }
        return output
    }

    static func hasSubstantiveNovelty(_ candidate: String?, comparedTo existing: [String?]) -> Bool {
        guard let cleaned = plainText(candidate), !cleaned.isEmpty else { return false }
        let normalizedCandidate = normalizeToken(cleaned)
        let candidateTokens = Set(normalizedCandidate.split(separator: " ").map(String.init))
        guard !candidateTokens.isEmpty else { return false }

        for existingValue in existing {
            guard let existingText = plainText(existingValue), !existingText.isEmpty else { continue }
            let normalizedExisting = normalizeToken(existingText)
            if normalizedExisting == normalizedCandidate {
                return false
            }
            if normalizedExisting.contains(normalizedCandidate) || normalizedCandidate.contains(normalizedExisting) {
                return false
            }

            let existingTokens = Set(normalizedExisting.split(separator: " ").map(String.init))
            guard !existingTokens.isEmpty else { continue }
            let overlap = candidateTokens.intersection(existingTokens)
            let overlapRatio = Double(overlap.count) / Double(min(candidateTokens.count, existingTokens.count))
            if overlapRatio >= 0.6 || (overlap.count >= 4 && overlapRatio >= 0.5) {
                return false
            }
        }

        return true
    }

    static func betterNightlifeText(primary: String?, secondary: String?) -> String? {
        guard let secondary = plainText(secondary), !secondary.isEmpty else { return plainText(primary) }
        guard let primary = plainText(primary), !primary.isEmpty else { return secondary }

        let normalizedPrimary = normalizeToken(primary)
        let normalizedSecondary = normalizeToken(secondary)
        let primaryIsMarketNote = normalizedPrimary.contains("highlighted in discotech s market guide")
        let secondaryIsMarketNote = normalizedSecondary.contains("highlighted in discotech s market guide")
        let primaryIsGeneric = normalizedPrimary.contains("guest list access is available")
            || normalizedPrimary.contains("listed by h wood rolodex")
            || normalizedPrimary.contains("recognized by h wood rolodex")
            || normalizedPrimary.contains("h wood rolodex")
            || normalizedPrimary.contains("bespoke membership")
            || normalizedPrimary.contains("membership program")
            || normalizedPrimary.contains("member benefits")
            || normalizedPrimary.contains("priority reservations")
            || normalizedPrimary.contains("priority access")
            || normalizedPrimary.contains("yourservice")
            || normalizedPrimary.contains("apply make it a night")
            || normalizedPrimary.contains("all the best vip nightclubs in london")
            || normalizedPrimary.contains("all the promoters")
            || normalizedPrimary.contains("club managers owners")
            || normalizedPrimary.contains("vip table bookings online")
            || normalizedPrimary.contains("request guest list")
            || normalizedPrimary.contains("app store")
            || normalizedPrimary.contains("reservation required")
        let secondaryIsGeneric = normalizedSecondary.contains("guest list access is available")
            || normalizedSecondary.contains("listed by h wood rolodex")
            || normalizedSecondary.contains("recognized by h wood rolodex")
            || normalizedSecondary.contains("h wood rolodex")
            || normalizedSecondary.contains("bespoke membership")
            || normalizedSecondary.contains("membership program")
            || normalizedSecondary.contains("member benefits")
            || normalizedSecondary.contains("priority reservations")
            || normalizedSecondary.contains("priority access")
            || normalizedSecondary.contains("yourservice")
            || normalizedSecondary.contains("apply make it a night")
            || normalizedSecondary.contains("all the best vip nightclubs in london")
            || normalizedSecondary.contains("all the promoters")
            || normalizedSecondary.contains("club managers owners")
            || normalizedSecondary.contains("vip table bookings online")
            || normalizedSecondary.contains("request guest list")
            || normalizedSecondary.contains("app store")
            || normalizedSecondary.contains("reservation required")
        let primaryIsExplicit = normalizedPrimary.contains("bottle service only")
            || normalizedPrimary.contains("does not have general admission")
            || normalizedPrimary.contains("hard door")
            || normalizedPrimary.contains("women:")
            || normalizedPrimary.contains("men:")
        let secondaryIsExplicit = normalizedSecondary.contains("bottle service only")
            || normalizedSecondary.contains("does not have general admission")
            || normalizedSecondary.contains("hard door")
            || normalizedSecondary.contains("women:")
            || normalizedSecondary.contains("men:")

        if primaryIsMarketNote && !secondaryIsMarketNote {
            return secondary
        }
        if primaryIsGeneric && secondaryIsExplicit {
            return secondary
        }
        if secondaryIsGeneric && primaryIsExplicit {
            return primary
        }

        let primaryScore = nightlifeDisplayQualityScore(primary)
        let secondaryScore = nightlifeDisplayQualityScore(secondary)
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

    static func richerNightlifePrice(primary: Double?, secondary: Double?) -> Double? {
        guard let secondary else { return primary }
        guard let primary else { return secondary }
        if primary <= 0, secondary > 0 {
            return secondary
        }
        if primary < 100, secondary >= 100 {
            return secondary
        }
        return max(primary, secondary)
    }

    private static func nightlifeDisplayQualityScore(_ value: String) -> Int {
        let normalized = normalizeToken(value)
        var score = 0

        let blockedTokens = [
            "highlighted in discotech s market guide",
            "listed by h wood rolodex",
            "recognized by h wood rolodex",
            "h wood rolodex",
            "bespoke membership",
            "membership program",
            "member benefits",
            "priority reservations",
            "priority access",
            "yourservice",
            "apply make it a night",
            "all the best vip nightclubs in london",
            "all the promoters",
            "club managers owners",
            "vip table bookings online",
            "guest list vip table bookings online",
            "photos and info",
            "best promoters here",
            "request guest list",
            "download the app",
            "app store",
            "reservation required"
        ]
        if blockedTokens.contains(where: normalized.contains) { score -= 12 }

        let descriptiveTokens = [
            "music", "dj", "top 40", "hip hop", "r b", "r&b", "house", "crowd", "dance",
            "vibe", "upscale", "luxury", "intimate", "rooftop", "cocktail", "dark",
            "atmosphere", "scene", "celebrit", "a list", "exclusive", "supper club"
        ]
        if descriptiveTokens.contains(where: normalized.contains) { score += 8 }

        let accessTokens = [
            "bottle service only", "hard door", "does not have general admission",
            "guest list", "table", "cover", "dress code"
        ]
        if accessTokens.contains(where: normalized.contains) { score += 4 }

        score += min(value.count / 55, 5)
        return score
    }

    static func moreExclusiveTier(primary: String?, secondary: String?) -> String? {
        func rank(_ value: String?) -> Int {
            let normalized = normalizeToken(value)
            if normalized.contains("ultra selective door") || normalized.contains("ultra exclusive") { return 5 }
            if normalized.contains("strict door") || normalized.contains("tier 4") || normalized.contains("celebrity door") { return 4 }
            if normalized.contains("selective door") || normalized.contains("tier 3") || normalized.contains("premium door") { return 3 }
            if normalized.contains("casual door") || normalized.contains("tier 2") || normalized.contains("selective") { return 2 }
            if normalized.contains("open door") || normalized.contains("tier 1") { return 1 }
            return 0
        }

        return rank(secondary) > rank(primary) ? secondary : primary ?? secondary
    }

    static func mergedPayload(primary: String, secondary: String) -> String {
        var payload: [String: Any] = [:]

        if let primaryData = primary.data(using: .utf8),
           let decoded = try? JSONSerialization.jsonObject(with: primaryData) as? [String: Any] {
            payload = decoded
        }

        if let secondaryData = secondary.data(using: .utf8),
           let decoded = try? JSONSerialization.jsonObject(with: secondaryData) as? [String: Any] {
            decoded.forEach { key, value in
                if payload[key] == nil || isEffectivelyEmptyJSONValue(payload[key]) {
                    payload[key] = value
                }
            }
        }

        return jsonString(payload)
    }

    private static func isEffectivelyEmptyJSONValue(_ value: Any?) -> Bool {
        guard let value else { return true }

        switch value {
        case is NSNull:
            return true
        case let string as String:
            return string.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        case let dictionary as [String: Any]:
            return dictionary.isEmpty
        case let dictionary as NSDictionary:
            return dictionary.count == 0
        case let array as [Any]:
            return array.isEmpty
        case let array as NSArray:
            return array.count == 0
        default:
            return false
        }
    }

    static func preferredImageURL(primary: String?, secondary: String?) -> String? {
        preferredImageURL(from: [primary, secondary])
    }

    static func preferredImageURL(from candidates: [String?]) -> String? {
        bestImageURL(from: candidates)
    }

    static func preferredImageURLs(for event: ExternalEvent, limit: Int = 3) -> [String] {
        if event.eventType == .partyNightlife || event.recordKind == .venueNight {
            return preferredNightlifeImageURLs(primary: event.imageURL, payload: event.rawSourcePayload, limit: limit)
        }

        let payloadImages = genericPayloadImageCandidates(from: event.rawSourcePayload)
        if !payloadImages.isEmpty {
            return bestImageURLs(from: payloadImages.map(Optional.some), limit: limit)
        }
        return bestImageURLs(from: [event.imageURL], limit: limit)
    }

    static func preferredNightlifeImageURL(primary: String?, payload: String) -> String? {
        preferredNightlifeImageURLs(primary: primary, payload: payload, limit: 1).first
    }

    static func preferredNightlifeImageURLs(primary: String?, payload: String, limit: Int = 3) -> [String] {
        let candidates = [primary]
            .compactMap(normalizedImageURLString(_:))
            .map { NightlifeImageCandidate(url: $0, sourceKey: "primary") }
            + nightlifeImageCandidatesWithSource(from: payload)

        return bestNightlifeImageURLs(from: candidates, limit: limit)
    }

    static func hasUsableNightlifeImage(for event: ExternalEvent) -> Bool {
        guard event.eventType == .partyNightlife || event.recordKind == .venueNight else {
            return event.imageURL != nil
        }

        let payload = normalizeToken(event.rawSourcePayload)
        let payloadImages = nightlifeImageCandidates(from: event.rawSourcePayload)
        let hasStrongImageSource = !payloadImages.isEmpty

        let hasHWoodOnlyCoverage = (payload.contains("hwood") || payload.contains("rolodex"))
            && !payload.contains("discotech")
            && !payload.contains("clubbable")
            && !payload.contains("apple maps")

        let bestCandidate = bestImageURL(
            from: [event.imageURL] + payloadImages.map(Optional.some)
        )

        guard let imageURL = bestCandidate, !imageURL.isEmpty else {
            return hasStrongImageSource
        }

        let normalizedURL = normalizeToken(imageURL)
        let blockedTokens = [
            "logo", "icon", "avatar", "placeholder", "thumb", "thumbnail", "preview",
            "-150x150", "-300x300", "_200", "_300"
        ]
        guard !blockedTokens.contains(where: normalizedURL.contains) else {
            return hasStrongImageSource
        }

        if hasHWoodOnlyCoverage,
           normalizedURL.contains("website files") {
            return false
        }

        return true
    }

    private struct NightlifeImageCandidate {
        let url: String
        let sourceKey: String
    }

    private static func nightlifeImageCandidates(from rawPayload: String) -> [String] {
        nightlifeImageCandidatesWithSource(from: rawPayload).map(\.url)
    }

    private static func nightlifeImageCandidatesWithSource(from rawPayload: String) -> [NightlifeImageCandidate] {
        guard let data = rawPayload.data(using: .utf8),
              let payload = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else {
            return []
        }

        let keys = [
            "apple_maps_image_gallery",
            "official_site_image_gallery",
            "discotech_image_gallery",
            "clubbable_image_gallery",
            "apple_maps_file_image",
            "official_site_image",
            "discotech_image",
            "clubbable_image"
        ]

        var seen = Set<String>()
        var results: [NightlifeImageCandidate] = []

        for key in keys {
            for url in imageStrings(from: payload[key]) {
                guard !seen.contains(url) else { continue }
                seen.insert(url)
                results.append(NightlifeImageCandidate(url: url, sourceKey: key))
            }
        }

        return results
    }

    private static func imageStrings(from value: Any?) -> [String] {
        guard let value else { return [] }

        if let string = value as? String {
            guard let cleaned = normalizedImageURLString(string), !cleaned.isEmpty else {
                return []
            }
            return [cleaned]
        }

        if let array = value as? [String] {
            return array.flatMap { imageStrings(from: $0) }
        }

        if let array = value as? [Any] {
            return array.flatMap { imageStrings(from: $0) }
        }

        if let dictionary = value as? [String: Any] {
            if let url = dictionary["url"] as? String {
                return imageStrings(from: url)
            }
            return ["image", "imageURL", "src", "croppedOriginalImageUrl"]
                .flatMap { imageStrings(from: dictionary[$0]) }
        }

        return []
    }

    private static func bestImageURL(from candidates: [String?]) -> String? {
        bestImageURLs(from: candidates, limit: 1).first
    }

    private static func bestImageURLs(from candidates: [String?], limit: Int) -> [String] {
        let cleaned = candidates
            .compactMap(normalizedImageURLString(_:))
            .filter { !$0.isEmpty }
            .filter { imageMeetsMinimumResolution($0) }

        guard !cleaned.isEmpty else { return [] }

        var bestByGroup: [String: (url: String, score: Int)] = [:]
        var firstSeenGroups: [String] = []

        for candidate in cleaned {
            let group = canonicalImageGroupKey(for: candidate)
            let score = imageQualityScore(candidate)
            if bestByGroup[group] == nil {
                firstSeenGroups.append(group)
                bestByGroup[group] = (candidate, score)
                continue
            }
            if let existing = bestByGroup[group], score > existing.score {
                bestByGroup[group] = (candidate, score)
            }
        }

        return firstSeenGroups
            .compactMap { bestByGroup[$0] }
            .sorted { lhs, rhs in
                if lhs.score == rhs.score { return lhs.url < rhs.url }
                return lhs.score > rhs.score
            }
            .map(\.url)
            .prefix(limit)
            .map { $0 }
    }

    private static func genericPayloadImageCandidates(from rawPayload: String) -> [String] {
        guard let data = rawPayload.data(using: .utf8),
              let payload = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else {
            return []
        }

        var candidates: [String] = []

        if let topLevelImages = payload["images"] as? [[String: Any]] {
            candidates.append(contentsOf: preferredImageURLs(from: topLevelImages, limit: 6))
        }
        if let listingItem = payload["listing_item"] as? [String: Any],
           let listingImages = listingItem["images"] as? [[String: Any]] {
            candidates.append(contentsOf: preferredImageURLs(from: listingImages, limit: 6))
        }
        if let socialEvent = payload["social_event"] as? [String: Any],
           let socialImages = socialEvent["images"] as? [[String: Any]] {
            candidates.append(contentsOf: preferredImageURLs(from: socialImages, limit: 6))
        }

        let topLevelKeys = [
            "apple_maps_image_gallery",
            "official_site_image_gallery",
            "discotech_image_gallery",
            "clubbable_image_gallery",
            "gallery_images",
            "image_gallery",
            "source_page_image_gallery",
            "apple_maps_file_image",
            "official_site_image",
            "discotech_image",
            "clubbable_image",
            "source_page_image",
            "image",
            "imageURL",
            "heroImage",
            "hero_image",
            "meta_image",
            "thumbnail",
            "thumb"
        ]

        candidates.append(contentsOf: topLevelKeys.flatMap { imageStrings(from: payload[$0]) })

        if let listingItem = payload["listing_item"] as? [String: Any] {
            candidates.append(contentsOf: imageStrings(from: listingItem["image"]))
            candidates.append(contentsOf: imageStrings(from: listingItem["imageURL"]))
            candidates.append(contentsOf: imageStrings(from: listingItem["image_url"]))
        }

        if let socialEvent = payload["social_event"] as? [String: Any] {
            candidates.append(contentsOf: imageStrings(from: socialEvent["image"]))
        }

        if let basicInfo = payload["basic_info"] as? [String: Any] {
            candidates.append(contentsOf: imageStrings(from: basicInfo["image"]))
            candidates.append(contentsOf: imageStrings(from: basicInfo["images"]))
            candidates.append(contentsOf: imageStrings(from: basicInfo["primaryImage"]))
            candidates.append(contentsOf: imageStrings(from: basicInfo["heroImage"]))
            candidates.append(contentsOf: imageStrings(from: basicInfo["logo"]))
        }

        return candidates
    }

    private static func bestNightlifeImageURLs(
        from candidates: [NightlifeImageCandidate],
        limit: Int
    ) -> [String] {
        let filteredCandidates = candidates.filter { imageMeetsMinimumResolution($0.url) }
        guard !filteredCandidates.isEmpty else { return [] }

        var bestByGroup: [String: (candidate: NightlifeImageCandidate, score: Int)] = [:]
        var firstSeenGroups: [String] = []

        for candidate in filteredCandidates {
            let group = canonicalImageGroupKey(for: candidate.url)
            let score = imageQualityScore(candidate.url) + nightlifeImageSourceScore(candidate.sourceKey, url: candidate.url)
            if bestByGroup[group] == nil {
                firstSeenGroups.append(group)
                bestByGroup[group] = (candidate, score)
                continue
            }
            if let existing = bestByGroup[group], score > existing.score {
                bestByGroup[group] = (candidate, score)
            }
        }

        return firstSeenGroups
            .compactMap { bestByGroup[$0] }
            .sorted { lhs, rhs in
                if lhs.score == rhs.score { return lhs.candidate.url < rhs.candidate.url }
                return lhs.score > rhs.score
            }
            .prefix(limit)
            .map(\.candidate.url)
    }

    static func imageMeetsMinimumResolution(_ rawURL: String) -> Bool {
        let rawLower = rawURL.lowercased()
        let normalized = normalizeToken(rawURL)

        let knownLowQualityTokens = [
            "_200", "_300", "-150x150", "-300x300",
            "resize=150", "resize=200", "resize=300", "resize=495",
            "fit=320", "fit=400", "fit=495", "w=120", "w=160", "w=200", "w=300"
        ]
        if knownLowQualityTokens.contains(where: rawLower.contains) {
            return false
        }

        if normalized.contains("thumbnail")
            || normalized.contains("preview")
            || normalized.contains("placeholder")
            || normalized.contains("avatar")
            || normalized.contains("icon")
            || normalized.contains("logo") {
            return false
        }

        if let dimensions = inferredImageDimensions(from: rawURL) {
            if let width = dimensions.width, width < 500 {
                return false
            }
            if let height = dimensions.height, height < 280 {
                return false
            }
        }

        return true
    }

    private static func canonicalImageGroupKey(for rawURL: String) -> String {
        guard let components = URLComponents(string: rawURL) else {
            return normalizeToken(rawURL)
        }
        let host = components.host?.lowercased() ?? ""
        let path = components.path.lowercased()
        let filename = URL(fileURLWithPath: path).lastPathComponent
            .replacingOccurrences(
                of: #"(?:_|-)(?:source|tablet_landscape(?:_large)?_16_9|tablet_landscape_3_2|retina_landscape_16_9|retina_portrait_16_9|retina_portrait_3_2|event_detail_page_16_9|recomendation_16_9|recommendation_16_9|artist_page_3_2|custom)(?=\.)"#,
                with: "",
                options: .regularExpression
            )
            .replacingOccurrences(of: #"(?:-|_)\d{2,4}x\d{2,4}(?=\.)"#, with: "", options: .regularExpression)
            .replacingOccurrences(of: #"(?:-|_)(?:thumb|thumbnail|small|preview|lowres|low|medium|hero)(?=\.)"#, with: "", options: .regularExpression)
            .replacingOccurrences(of: #"(?:-|_)scaled(?=\.)"#, with: "", options: .regularExpression)
            .replacingOccurrences(of: #"(?:-|_)(?:\d{2,4}|copy|final|main|cover|og|hd|full)(?=\.)"#, with: "", options: .regularExpression)
            .replacingOccurrences(of: #"(?:-|_)(?:\d{2,4}|thumb|thumbnail|small|preview|lowres|low|medium|hero|copy|final|main|cover|og|hd|full)$"#, with: "", options: .regularExpression)
        let stem = filename
            .replacingOccurrences(of: #"\.[a-z0-9]+$"#, with: "", options: .regularExpression)
            .trimmingCharacters(in: CharacterSet(charactersIn: "-_ "))
        let dirname = URL(fileURLWithPath: path).deletingLastPathComponent().lastPathComponent
            .replacingOccurrences(of: #"(?:thumbs?|thumbnails?|preview|small|medium|large)$"#, with: "", options: .regularExpression)
        if stem.count >= 8 {
            return stem
        }
        return "\(host)|\(dirname)|\(stem)"
    }

    private static func imageQualityScore(_ rawURL: String) -> Int {
        let normalized = normalizeToken(rawURL)
        let rawLower = rawURL.lowercased()
        var score = 0

        if rawURL.hasPrefix("/") || rawURL.hasPrefix("file://") { score += 44 }
        if normalized.contains("lookaround") || normalized.contains("apple venue media") { score += 34 }
        if normalized.contains("apple maps") { score += 28 }
        if normalized.contains("official") { score += 22 }
        if normalized.contains("discotech") { score += 18 }
        if normalized.contains("clubbable") { score += 12 }
        if rawLower.contains(".webp") || rawLower.contains(".jpg") || rawLower.contains(".jpeg") || rawLower.contains(".png") {
            score += 4
        }

        let lowQualityTokens = [
            "logo", "icon", "avatar", "favicon", "placeholder", "thumb", "thumbnail",
            "preview", "tiny", "small", "_150", "_200", "_300", "-150x150", "-300x300",
            "resize=150", "resize=200", "resize=300", "resize=495", "fit=640%2c240",
            "fit=640,240", "w=120", "w=160", "w=200", "w=300", "quality=40",
            "quality=50", "mqdefault"
        ]
        if lowQualityTokens.contains(where: rawLower.contains) { score -= 40 }

        if rawLower.contains("_800")
            || rawLower.contains("resize=1500")
            || rawLower.contains("resize=1300")
            || rawLower.contains("fit=992") {
            score += 14
        }

        if rawLower.range(of: #"(?:-|_)[1-9](?:[?./]|$)"#, options: .regularExpression) != nil {
            score += 6
        }
        if URL(string: rawURL)?.path.hasSuffix("-") == true {
            score -= 10
        }

        if let match = rawURL.range(of: #"(\d{3,4})x(\d{3,4})"#, options: .regularExpression) {
            let snippet = rawURL[match]
            let numbers = snippet.split(whereSeparator: { !$0.isNumber }).compactMap { Int($0) }
            if let width = numbers.first, let height = numbers.last {
                score += min((width * height) / 200_000, 24)
            }
        }

        return score
    }

    private static func inferredImageDimensions(from rawURL: String) -> (width: Int?, height: Int?)? {
        if let range = rawURL.range(of: #"(\d{3,4})x(\d{3,4})"#, options: .regularExpression) {
            let snippet = rawURL[range]
            let numbers = snippet.split(whereSeparator: { !$0.isNumber }).compactMap { Int($0) }
            if let width = numbers.first, let height = numbers.last {
                return (width, height)
            }
        }

        if let components = URLComponents(string: rawURL),
           let items = components.queryItems, !items.isEmpty {
            var width: Int?
            var height: Int?

            for item in items {
                let name = item.name.lowercased()
                let value = item.value?.removingPercentEncoding ?? item.value ?? ""
                if ["w", "width"].contains(name), let parsed = Int(value) {
                    width = parsed
                } else if ["h", "height"].contains(name), let parsed = Int(value) {
                    height = parsed
                } else if ["resize", "fit"].contains(name) {
                    let numbers = value.split(whereSeparator: { !$0.isNumber }).compactMap { Int($0) }
                    if numbers.count >= 2 {
                        width = width ?? numbers[0]
                        height = height ?? numbers[1]
                    } else if numbers.count == 1 {
                        width = width ?? numbers[0]
                    }
                }
            }

            if width != nil || height != nil {
                return (width, height)
            }
        }

        return nil
    }

    private static func nightlifeImageSourceScore(_ sourceKey: String, url rawURL: String) -> Int {
        let rawLower = rawURL.lowercased()
        var score = 0

        switch sourceKey {
        case "apple_maps_image_gallery":
            score += 120
        case "apple_maps_file_image":
            score += 112
        case "official_site_image_gallery":
            score += 90
        case "official_site_image":
            score += 84
        case "discotech_image_gallery":
            score += 58
        case "discotech_image":
            score += 52
        case "clubbable_image_gallery":
            score += 42
        case "clubbable_image":
            score += 36
        case "primary":
            score += 16
        default:
            break
        }

        if rawLower.contains("_200") || rawLower.contains("_300") {
            score -= 32
        }
        if rawLower.contains("clubbable.blob.core.windows.net/medias/"),
           !rawLower.contains(".jpg"),
           !rawLower.contains(".jpeg"),
           !rawLower.contains(".png"),
           !rawLower.contains(".webp") {
            score -= 10
        }
        if rawLower.contains("-scaled.") || rawLower.contains("_1200") || rawLower.contains("_1600") {
            score += 8
        }

        return score
    }

    static func normalizedImageURLString(_ value: String?) -> String? {
        guard let value else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        let normalized = trimmed
            .replacingOccurrences(of: "&#038;", with: "&")
            .replacingOccurrences(of: "&amp;", with: "&")
            .replacingOccurrences(of: "&#x26;", with: "&")
            .replacingOccurrences(of: "&#x2F;", with: "/")
            .replacingOccurrences(of: "&#47;", with: "/")

        return normalized.isEmpty ? nil : normalized
    }

    static func ticketmasterDate(_ value: String?) -> Date? {
        guard let value else { return nil }
        return iso8601Formatter.date(from: value) ?? iso8601NoFractionalSeconds.date(from: value)
    }

    static func combineLocalDateAndTime(date: String?, time: String?) -> String? {
        guard let date else { return nil }
        let safeTime = (time?.isEmpty == false ? time : "00:00:00") ?? "00:00:00"
        return "\(date)T\(safeTime)"
    }

    static func runSignupDateOnly(_ value: String?) -> String? {
        guard let value, !value.isEmpty else { return nil }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "MM/dd/yyyy"
        guard let date = formatter.date(from: value) else { return nil }
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: date)
    }

    static func runSignupLocalDateTime(_ value: String?, timezoneID: String?) -> (utc: Date?, local: String?) {
        guard let value, !value.isEmpty else { return (nil, nil) }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "M/d/yyyy HH:mm"
        formatter.timeZone = timezoneID.flatMap(TimeZone.init(identifier:)) ?? TimeZone(secondsFromGMT: 0)
        guard let date = formatter.date(from: value) else { return (nil, nil) }

        let localFormatter = DateFormatter()
        localFormatter.locale = Locale(identifier: "en_US_POSIX")
        localFormatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ss"
        localFormatter.timeZone = formatter.timeZone
        return (date, localFormatter.string(from: date))
    }

    static func extractFirstPrice(_ periods: [[String: Any]]) -> (Double?, Double?, String?) {
        let prices = periods.compactMap { period -> Double? in
            guard let priceString = period.string("race_fee") else { return nil }
            return parseCurrencyAmount(priceString)
        }
        guard !prices.isEmpty else { return (nil, nil, nil) }
        return (prices.min(), prices.max(), "USD")
    }

    static func parseCurrencyAmount(_ value: String?) -> Double? {
        guard let value else { return nil }
        let digits = value.replacingOccurrences(of: "[^0-9.]", with: "", options: .regularExpression)
        return Double(digits)
    }

    static func parseDouble(_ value: Any?) -> Double? {
        if isJSONBoolean(value) {
            return nil
        }

        if let number = value as? NSNumber {
            let doubleValue = number.doubleValue
            return doubleValue.isFinite ? doubleValue : nil
        }

        if let value = value as? String {
            let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
            return Double(trimmed)
        }

        return nil
    }

    static func parseInt(_ value: Any?) -> Int? {
        if isJSONBoolean(value) {
            return nil
        }

        if let number = value as? NSNumber {
            return number.intValue
        }

        if let value = value as? String {
            let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
            return Int(trimmed)
        }

        return nil
    }

    static func googleEventsDateRange(
        when: String?,
        timezoneID: String?
    ) -> (startUTC: Date?, endUTC: Date?, startLocal: String?, endLocal: String?) {
        guard let when, !when.isEmpty else { return (nil, nil, nil, nil) }

        let timezone = timezoneID.flatMap(TimeZone.init(identifier:)) ?? .current
        let normalized = when
            .replacingOccurrences(of: "–", with: " - ")
            .replacingOccurrences(of: "—", with: " - ")
            .replacingOccurrences(of: "  ", with: " ")

        let parts = normalized.components(separatedBy: " - ")
        guard !parts.isEmpty else { return (nil, nil, nil, nil) }

        let currentYear = Calendar.current.component(.year, from: Date())
        let startComponents = googleDateComponents(from: parts[0], fallbackMonth: nil, fallbackDay: nil, fallbackMeridiem: googleMeridiem(from: parts[safe: 1]))
        let endComponents = googleDateComponents(
            from: parts.count > 1 ? parts[1] : parts[0],
            fallbackMonth: startComponents?.month,
            fallbackDay: startComponents?.day,
            fallbackMeridiem: startComponents?.meridiem
        )

        let startDate = googleDate(
            month: startComponents?.month,
            day: startComponents?.day,
            year: currentYear,
            time: startComponents?.time,
            meridiem: startComponents?.meridiem,
            timezone: timezone
        )
        var endDate = googleDate(
            month: endComponents?.month,
            day: endComponents?.day,
            year: currentYear,
            time: endComponents?.time,
            meridiem: endComponents?.meridiem,
            timezone: timezone
        )

        if let startDate, let computedEnd = endDate, computedEnd < startDate {
            endDate = Calendar.current.date(byAdding: .day, value: 1, to: computedEnd)
        }

        return (
            startDate,
            endDate,
            googleLocalDateString(from: startDate, timezone: timezone),
            googleLocalDateString(from: endDate, timezone: timezone)
        )
    }

    static func googleEventType(
        title: String?,
        description: String?,
        ticketSources: [String],
        queryLabel: String
    ) -> ExternalEventType {
        let haystack = normalizeToken([
            title,
            description,
            queryLabel,
            ticketSources.joined(separator: " ")
        ]
        .compactMap { $0 }
        .joined(separator: " "))

        if haystack.contains("lakers")
            || haystack.contains("clippers")
            || haystack.contains("dodgers")
            || haystack.contains("lafc")
            || haystack.contains("galaxy")
            || haystack.contains("angel city")
            || haystack.contains("crypto com arena")
            || haystack.contains("intuit dome")
            || haystack.contains("bmo stadium")
            || haystack.contains("dignity health sports park")
            || haystack.contains("nba")
            || haystack.contains("nhl")
            || haystack.contains("mlb")
            || haystack.contains("ufc")
            || haystack.contains("boxing")
            || haystack.contains("wwe")
            || haystack.contains("aew")
            || haystack.contains("fc ")
            || haystack.contains("soccer")
            || haystack.contains("basketball")
            || haystack.contains("football")
            || haystack.contains("baseball")
            || haystack.contains("hockey")
            || haystack.contains("sports")
        {
            return .sportsEvent
        }

        if haystack.contains("club")
            || haystack.contains("nightlife")
            || haystack.contains("dj")
            || haystack.contains("afterparty")
            || haystack.contains("after party")
            || haystack.contains("day party")
            || haystack.contains("poppy")
            || haystack.contains("hyde")
            || haystack.contains("delilah")
            || haystack.contains("warwick")
            || haystack.contains("keys")
            || haystack.contains("offsunset")
            || haystack.contains("skybar")
        {
            return .partyNightlife
        }

        if haystack.contains("concert")
            || haystack.contains("band")
            || haystack.contains("live music")
            || haystack.contains("spotify")
            || haystack.contains("songkick")
            || haystack.contains("tour")
        {
            return .concert
        }

        if haystack.contains("comedy")
            || haystack.contains("theater")
            || haystack.contains("theatre")
            || haystack.contains("musical")
            || haystack.contains("show")
            || haystack.contains("film")
        {
            return .weekendActivity
        }

        if haystack.contains("community")
            || haystack.contains("festival")
            || haystack.contains("market")
            || haystack.contains("fair")
            || haystack.contains("volunteer")
        {
            return .socialCommunityEvent
        }

        return .otherLiveEvent
    }

    static func googlePreferredImageURL(_ value: String?) -> String? {
        guard let value, !value.isEmpty else { return nil }
        let normalized = normalizeToken(value)
        if normalized.contains("google com maps")
            || normalized.contains("maps vt data")
        {
            return nil
        }
        return value
    }

    static func isLikelyClubLikeNightlifeVenue(_ event: ExternalEvent) -> Bool {
        guard event.eventType == .partyNightlife || event.recordKind == .venueNight else {
            return false
        }

        let identityHaystack = normalizeToken(
            [
                event.venueName,
                event.title,
                event.category,
                event.subcategory,
                event.tags.joined(separator: " "),
                event.addressLine1,
                event.doorPolicyText,
                event.dressCodeText,
                event.entryPolicySummary,
                event.womenEntryPolicyText,
                event.menEntryPolicyText,
                event.exclusivityTierLabel
            ]
            .compactMap { $0 }
            .joined(separator: " ")
        )
        let signalHaystack = normalizeToken(
            [
                event.venueName,
                event.title,
                event.category,
                event.subcategory,
                event.tags.joined(separator: " "),
                event.addressLine1,
                event.doorPolicyText,
                event.dressCodeText,
                event.entryPolicySummary,
                event.womenEntryPolicyText,
                event.menEntryPolicyText,
                event.exclusivityTierLabel,
                event.rawSourcePayload
            ]
            .compactMap { $0 }
            .joined(separator: " ")
        )
        let identityTokens = Set(identityHaystack.split(separator: " ").map(String.init))
        let signalTokens = Set(signalHaystack.split(separator: " ").map(String.init))

        let barLikeTokens = [
            "bar",
            "lounge",
            "speakeasy",
            "cocktail",
            "pub",
            "tavern",
            "brewery",
            "taproom",
            "saloon"
        ]
        let safeClubPhrases = [
            "comedy club",
            "jazz club",
            "book club",
            "social club",
            "country club",
            "running club",
            "boxing club",
            "fitness club"
        ]
        let explicitNightclubSignals = [
            "nightclub",
            "night club",
            "strip club",
            "gentlemen's club",
            "gentlemens club",
            "bottle service only"
        ]
        let nightlifeClubSignals = [
            "dj",
            "dance",
            "edm",
            "house music",
            "techno",
            "vip",
            "vip table",
            "vip section",
            "afterparty",
            "after party",
            "club crawl",
            "day party",
            "table service",
            "guest list",
            "bottle service",
            "table minimum",
            "hard door",
            "after hours",
            "afterhours",
            "dance floor"
        ]
        let metadataNightclubSignals = [
            "discotech",
            "clubbable",
            "guest list",
            "bottle service",
            "vip table",
            "vip section",
            "table minimum",
            "exclusive tier",
            "hard door"
        ]

        if barLikeTokens.contains(where: identityTokens.contains)
            || identityHaystack.contains("rooftop bar")
            || identityHaystack.contains("wine bar")
            || identityHaystack.contains("beer garden") {
            return false
        }

        if safeClubPhrases.contains(where: identityHaystack.contains) {
            return false
        }

        if event.eventType == .partyNightlife || event.recordKind == .venueNight {
            let hasNightclubMetadataSignal =
                metadataNightclubSignals.contains(where: signalHaystack.contains)
                || event.guestListAvailable == true
                || event.bottleServiceAvailable == true
                || event.tableMinPrice != nil
                || event.exclusivityTierLabel != nil

            if hasNightclubMetadataSignal {
                return true
            }
        }

        if explicitNightclubSignals.contains(where: signalHaystack.contains) {
            return true
        }

        if signalTokens.contains("club") {
            return nightlifeClubSignals.contains(where: signalHaystack.contains)
        }

        return false
    }

    static func eventTypeForRun(distanceValue: Double?, distanceUnit: String?, name: String?, eventType: String?) -> (ExternalEventType, String?) {
        let normalizedUnit = normalizeToken(distanceUnit)
        let miles = distanceValue.flatMap { value -> Double? in
            if normalizedUnit.contains("km") {
                return value * 0.621371
            }
            return value
        }

        if let miles {
            if abs(miles - 26.2) <= 0.4 { return (.raceMarathon, "Marathon") }
            if abs(miles - 13.1) <= 0.3 { return (.raceHalfMarathon, "Half Marathon") }
            if abs(miles - 6.2) <= 0.2 { return (.race10k, "10K") }
            if abs(miles - 3.1) <= 0.2 { return (.race5k, "5K") }
        }

        let title = normalizeToken(name)
        if title.contains("marathon") { return (.raceMarathon, "Marathon") }
        if title.contains("half marathon") || title.contains("half") { return (.raceHalfMarathon, "Half Marathon") }
        if title.contains("10k") { return (.race10k, "10K") }
        if title.contains("5k") { return (.race5k, "5K") }
        if normalizeToken(eventType).contains("running") { return (.groupRun, "Group Run") }
        return (.otherLiveEvent, nil)
    }

    static func distanceParts(from value: String?) -> (Double?, String?) {
        guard let value else { return (nil, nil) }
        let numberPattern = #"[0-9]+(?:\.[0-9]+)?"#
        let amountString = value.range(of: numberPattern, options: .regularExpression).map { String(value[$0]) }
        let amount = amountString.flatMap(Double.init)

        let normalized = normalizeToken(value)
        if normalized.contains("mile") {
            return (amount, "miles")
        }
        if normalized.contains("km") || normalized.contains("kilometer") {
            return (amount, "km")
        }
        return (amount, nil)
    }

    static func ticketmasterEventType(from classifications: [[String: Any]], title: String) -> ExternalEventType? {
        let text = normalizeToken(title)
        let segments = classifications.compactMap { $0.dictionary("segment")?.string("name") }.map(normalizeToken)
        let genres = classifications.compactMap { $0.dictionary("genre")?.string("name") }.map(normalizeToken)
        let subgenres = classifications.compactMap { $0.dictionary("subGenre")?.string("name") }.map(normalizeToken)
        let haystack = ([text] + segments + genres + subgenres).joined(separator: " ")

        if haystack.contains("sports") {
            return .sportsEvent
        }
        if haystack.contains("dj")
            || haystack.contains("dance")
            || haystack.contains("nightlife")
            || haystack.contains("club")
            || haystack.contains("party")
        {
            return .partyNightlife
        }
        if haystack.contains("music") {
            return .concert
        }
        if haystack.contains("comedy")
            || haystack.contains("theatre")
            || haystack.contains("theater")
            || haystack.contains("arts")
        {
            return .weekendActivity
        }
        if haystack.contains("community") || haystack.contains("festival") {
            return .socialCommunityEvent
        }
        if haystack.isEmpty {
            return .otherLiveEvent
        }
        return .otherLiveEvent
    }

    static func normalizeTicketmasterStatus(
        statusCode: String?,
        eventStartUTC: Date?,
        now: Date = Date()
    ) -> (ExternalEventStatus, ExternalEventAvailabilityStatus) {
        switch normalizeToken(statusCode) {
        case "cancelled":
            return (.cancelled, .cancelled)
        case "postponed":
            return (.postponed, .postponed)
        case "rescheduled":
            return (.rescheduled, .rescheduled)
        case "onsale":
            return (.onsale, .onsale)
        case "offsale":
            if let eventStartUTC, eventStartUTC < now {
                return (.ended, .ended)
            }
            return (.scheduled, .registrationClosed)
        default:
            if let eventStartUTC, eventStartUTC < now {
                return (.ended, .ended)
            }
            return (.scheduled, .available)
        }
    }

    static func normalizeRunSignupStatus(
        isRegistrationOpen: Bool,
        startUTC: Date?,
        now: Date = Date()
    ) -> (ExternalEventStatus, ExternalEventAvailabilityStatus) {
        if let startUTC, startUTC < now {
            return (.ended, .ended)
        }
        if isRegistrationOpen {
            return (.openRegistration, .openRegistration)
        }
        return (.scheduled, .registrationClosed)
    }

    static func eventbriteEventType(
        category: String?,
        subcategory: String?,
        format: String?,
        title: String?,
        summary: String?
    ) -> ExternalEventType {
        let haystack = [
            normalizeToken(category),
            normalizeToken(subcategory),
            normalizeToken(format),
            normalizeToken(title),
            normalizeToken(summary)
        ].joined(separator: " ")

        if haystack.contains("comedy")
            || haystack.contains("stand up")
            || haystack.contains("standup")
            || haystack.contains("comic")
            || haystack.contains("improv")
            || haystack.contains("open mic")
        {
            return .otherLiveEvent
        }

        if haystack.contains("concert")
            || haystack.contains("music")
            || haystack.contains("dj")
            || haystack.contains("band")
            || haystack.contains("live music")
        {
            return .concert
        }

        if haystack.contains("party")
            || haystack.contains("nightlife")
            || haystack.contains("club")
            || haystack.contains("after party")
            || haystack.contains("vip")
        {
            return .partyNightlife
        }

        if haystack.contains("community")
            || haystack.contains("charity")
            || haystack.contains("fundraiser")
            || haystack.contains("volunteer")
            || haystack.contains("social")
            || haystack.contains("networking")
        {
            return .socialCommunityEvent
        }

        if haystack.contains("festival")
            || haystack.contains("market")
            || haystack.contains("fair")
            || haystack.contains("tour")
            || haystack.contains("food")
            || haystack.contains("drink")
            || haystack.contains("weekend")
            || haystack.contains("family")
            || haystack.contains("film")
            || haystack.contains("media")
            || haystack.contains("arts")
            || haystack.contains("theatre")
            || haystack.contains("theater")
        {
            return .weekendActivity
        }

        return .otherLiveEvent
    }

    static func normalizeEventbriteStatus(
        basicStatus: String?,
        schemaStatus: String?,
        availability: String?,
        availabilityEndsUTC: Date?,
        startUTC: Date?,
        isFree: Bool,
        now: Date = Date()
    ) -> (ExternalEventStatus, ExternalEventAvailabilityStatus) {
        let normalizedBasicStatus = normalizeToken(basicStatus)
        let normalizedSchemaStatus = normalizeToken(schemaStatus)
        let normalizedAvailability = normalizeToken(availability)

        if normalizedSchemaStatus.contains("eventcancelled") || normalizedBasicStatus.contains("cancel") {
            return (.cancelled, .cancelled)
        }
        if normalizedSchemaStatus.contains("eventpostponed") || normalizedBasicStatus.contains("postpon") {
            return (.postponed, .postponed)
        }
        if normalizedSchemaStatus.contains("eventrescheduled") || normalizedBasicStatus.contains("reschedul") {
            return (.rescheduled, .rescheduled)
        }

        if let startUTC, startUTC < now || normalizedBasicStatus.contains("complet") || normalizedBasicStatus.contains("ended") {
            return (.ended, .ended)
        }

        if normalizedAvailability.contains("soldout") || normalizedAvailability.contains("outofstock") {
            return (.soldOut, .soldOut)
        }

        if let availabilityEndsUTC, availabilityEndsUTC < now {
            return (.scheduled, .registrationClosed)
        }

        if isFree {
            return (.scheduled, .available)
        }

        if normalizedAvailability.contains("instock") || normalizedAvailability.contains("preorder") || normalizedBasicStatus.contains("live") {
            return (.onsale, .onsale)
        }

        return (.scheduled, .available)
    }

    static func urgencyBadgeForEventbriteAvailability(_ availability: String?) -> ExternalEventUrgencyBadge? {
        let normalized = normalizeToken(availability)
        if normalized.contains("limitedavailability") {
            return .almostSoldOut
        }
        return nil
    }

    static func eventbriteEventID(from url: String?) -> String? {
        guard let url else { return nil }
        guard let range = url.range(of: #"tickets-([0-9]+)"#, options: .regularExpression) else { return nil }
        let match = String(url[range])
        return match.replacingOccurrences(of: "tickets-", with: "")
    }

    static func urgencyBadgeForRegistrationClose(_ registrationClosesUTC: Date?, now: Date = Date()) -> ExternalEventUrgencyBadge? {
        guard let registrationClosesUTC else { return nil }
        let seconds = registrationClosesUTC.timeIntervalSince(now)
        guard seconds > 0, seconds <= 72 * 60 * 60 else { return nil }
        return .registrationClosingSoon
    }

    static func urgencyBadgeForSalesEndingSoon(_ salesEndUTC: Date?, now: Date = Date()) -> ExternalEventUrgencyBadge? {
        guard let salesEndUTC else { return nil }
        let seconds = salesEndUTC.timeIntervalSince(now)
        guard seconds > 0, seconds <= 36 * 60 * 60 else { return nil }
        return .sellingFast
    }

    static func qualityScore(for event: ExternalEvent) -> Int {
        var score = completenessScore(for: event)

        switch event.source {
        case .ticketmaster:
            score += 18
        case .stubHub:
            score += 8
        case .runsignup:
            score += 16
        case .eventbrite:
            score += 4
        case .googleEvents:
            score += 12
        case .seatGeek:
            score += 17
        case .sportsSchedule:
            score += 16
        case .appleMaps, .googlePlaces, .yelpFusion:
            score += 10
        case .venueWebsite:
            score += 12
        case .venueCalendar:
            score += 10
        case .reservationProvider:
            score += 11
        case .nightlifeAggregator:
            score += 8
        case .editorialGuide:
            score += 4
        }

        if event.imageURL != nil { score += 5 }
        if hasMeaningfulVenue(event) { score += 5 }
        if hasMeaningfulDescription(event) { score += 4 }
        if event.priceMin != nil || event.priceMax != nil { score += 3 }
        if event.urgencyBadge != nil { score += 5 }
        score += trustedVenueScore(for: event)
        if let venuePopularityCount = event.venuePopularityCount {
            score += min(venuePopularityCount / 10, 14)
        }
        if event.organizerVerified == true { score += 8 }
        if let organizerEventCount = event.organizerEventCount {
            score += min(organizerEventCount / 20, 12)
        }
        if let sourceConfidence = event.sourceConfidence {
            score += Int(sourceConfidence * 10)
        }
        if let venueSignalScore = event.venueSignalScore {
            score += Int(venueSignalScore)
        }
        if let exclusivityScore = event.exclusivityScore {
            score += Int(exclusivityScore)
        }
        if let trendingScore = event.trendingScore {
            score += Int(trendingScore)
        }
        if event.guestListAvailable == true { score += 8 }
        if event.bottleServiceAvailable == true { score += 10 }
        if event.tableMinPrice != nil { score += 7 }
        if event.coverPrice != nil { score += 3 }
        if event.reservationURL != nil { score += 4 }
        if event.ageMinimum == 21 { score += 2 }
        score += prominenceSignalScore(for: event)
        score -= organizerBlacklistPenalty(for: event)
        if isLikelySmallPromoterNight(event) { score -= 16 }

        if looksOnlineOrVirtual(event) { score -= 28 }
        if looksProfessionalPromoEvent(event) { score -= 24 }
        if looksNoisyTitle(event.title) { score -= 10 }
        if looksAncillaryInventory(event) { score -= 24 }
        if event.source == .eventbrite && event.eventType == .otherLiveEvent { score -= 8 }
        if event.source == .eventbrite && !hasMeaningfulVenue(event) { score -= 8 }
        if event.source == .eventbrite && !isHighSignalLocalEvent(event) && !isPromisingEventbriteEvent(event) { score -= 8 }
        score += marqueeEventBoost(for: event)

        return score
    }

    static func isPromisingEventbriteEvent(_ event: ExternalEvent) -> Bool {
        guard event.source == .eventbrite else { return false }
        if looksOnlineOrVirtual(event) || looksAncillaryInventory(event) {
            return false
        }
        if looksProfessionalPromoEvent(event) || isLikelySmallPromoterNight(event) {
            return false
        }

        let hasVenueIdentity = hasMeaningfulVenue(event) && (event.addressLine1 != nil || (event.latitude != nil && event.longitude != nil))
        let hasPresentation = event.imageURL != nil || hasMeaningfulDescription(event)
        let hasCredibility = event.organizerVerified == true
            || marqueeEventBoost(for: event) >= 12
            || prominenceSignalScore(for: event) >= 10
            || (event.venuePopularityCount ?? 0) >= 25

        return hasVenueIdentity && hasPresentation && hasCredibility
    }

    static func shouldSuppressLowSignalEvent(_ event: ExternalEvent) -> Bool {
        if looksOnlineOrVirtual(event) {
            return true
        }
        if looksAncillaryInventory(event) {
            return true
        }
        if looksStripClubOrAdultVenue(event) {
            return true
        }
        if looksCannabisOrPrivateReserveVenue(event) {
            return true
        }
        if (event.eventType == .partyNightlife || event.recordKind == .venueNight),
           isLikelyBrokenNightlifeSourceURL(event.sourceURL) {
            return true
        }

        let organizerPenalty = organizerBlacklistPenalty(for: event)

        switch event.source {
        case .eventbrite:
            if looksProfessionalPromoEvent(event) {
                return true
            }
            if isLikelySmallPromoterNight(event) {
                return true
            }
            if organizerPenalty >= 18, event.organizerVerified != true {
                return true
            }
            if isPromisingEventbriteEvent(event) {
                if organizerPenalty >= 10, qualityScore(for: event) < 26 {
                    return true
                }
                return qualityScore(for: event) < 22
            }
            if !isHighSignalLocalEvent(event), marqueeEventBoost(for: event) < 8, !hasMeaningfulVenue(event) {
                return true
            }
            if !isHighSignalLocalEvent(event), qualityScore(for: event) < 32 {
                return true
            }
            if organizerPenalty >= 10, qualityScore(for: event) < 28 {
                return true
            }
            return qualityScore(for: event) < 24
        case .ticketmaster:
            return qualityScore(for: event) < 10
        case .stubHub:
            return qualityScore(for: event) < 26
        case .runsignup:
            return false
        case .googleEvents:
            if event.eventType == .sportsEvent {
                return qualityScore(for: event) < 18
            }
            return qualityScore(for: event) < 22
        case .seatGeek:
            return qualityScore(for: event) < 16
        case .sportsSchedule:
            return event.eventType == .sportsEvent ? qualityScore(for: event) < 12 : qualityScore(for: event) < 18
        case .appleMaps, .googlePlaces, .yelpFusion, .venueWebsite, .venueCalendar, .reservationProvider:
            return qualityScore(for: event) < 20
        case .nightlifeAggregator:
            return qualityScore(for: event) < 24
        case .editorialGuide:
            return qualityScore(for: event) < 28
        }
    }

    private static func isLikelyBrokenNightlifeSourceURL(_ value: String?) -> Bool {
        let normalized = normalizeToken(value)
        guard !normalized.isEmpty else { return false }
        let blockedTokens = [
            "discotech me search",
            "feed rss",
            "newsfeed",
            "promo code",
            "tag ",
            "category "
        ]
        return blockedTokens.contains(where: normalized.contains)
    }

    static func fallbackThumbnailAsset(for eventType: ExternalEventType) -> String {
        switch eventType {
        case .groupRun, .race5k, .race10k, .raceHalfMarathon, .raceMarathon:
            return "005_road-run-and-brisk-walk_realism"
        case .sportsEvent:
            return "012_basketball-court-session_realism"
        case .partyNightlife, .weekendActivity, .socialCommunityEvent, .concert, .otherLiveEvent:
            return "043_community-event-and-open-mic_realism"
        }
    }

    static func tags(from values: [String?]) -> [String] {
        Array(Set(values.compactMap { value in
            guard let value else { return nil }
            let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? nil : trimmed
        })).sorted()
    }

    static func preferredImageURL(from imageObjects: [[String: Any]]) -> String? {
        preferredImageURLs(from: imageObjects, limit: 1).first
    }

    static func preferredImageURLs(from imageObjects: [[String: Any]], limit: Int = 3) -> [String] {
        let sorted = imageObjects.sorted { lhs, rhs in
            let lhsRatio = lhs.string("ratio") ?? ""
            let rhsRatio = rhs.string("ratio") ?? ""
            let lhsWidth = parseInt(lhs["width"]) ?? 0
            let rhsWidth = parseInt(rhs["width"]) ?? 0
            let lhsScore = (lhsRatio == "16_9" ? 10_000 : 0) + lhsWidth
            let rhsScore = (rhsRatio == "16_9" ? 10_000 : 0) + rhsWidth
            return lhsScore > rhsScore
        }
        var seen = Set<String>()
        var urls: [String] = []

        for image in sorted {
            guard let url = image.string("url")?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !url.isEmpty
            else {
                continue
            }

            let normalized = normalizeToken(url)
            guard !normalized.contains("logo"),
                  !normalized.contains("icon"),
                  !normalized.contains("avatar"),
                  !normalized.contains("placeholder")
            else {
                continue
            }

            guard !seen.contains(url) else { continue }
            seen.insert(url)
            urls.append(url)
            if urls.count == limit {
                break
            }
        }

        return urls
    }

    static func completenessScore(for event: ExternalEvent) -> Int {
        var score = 0
        let optionals: [Any?] = [
            event.shortDescription,
            event.fullDescription,
            event.category,
            event.subcategory,
            event.startAtUTC,
            event.salesEndAtUTC,
            event.venueName,
            event.addressLine1,
            event.city,
            event.state,
            event.country,
            event.latitude,
            event.longitude,
            event.imageURL,
            event.status,
            event.availabilityStatus,
            event.priceMin,
            event.organizerName,
            event.organizerEventCount,
            event.venuePopularityCount,
            event.venueRating,
            event.ticketProviderCount,
            event.distanceValue
        ]
        optionals.forEach { if $0 != nil { score += 1 } }
        return score
    }

    static func sourcePriority(for event: ExternalEvent) -> Int {
        switch event.eventType {
        case .groupRun, .race5k, .race10k, .raceHalfMarathon, .raceMarathon:
            return event.source == .runsignup ? 30 : 10
        case .sportsEvent:
            switch event.source {
            case .ticketmaster: return 34
            case .stubHub: return 14
            case .seatGeek: return 36
            case .sportsSchedule: return 32
            case .googleEvents: return isHighSignalLocalEvent(event) ? 22 : 16
            case .eventbrite: return 1
            case .runsignup: return 6
            case .appleMaps, .googlePlaces, .yelpFusion: return 12
            case .venueWebsite: return 14
            case .venueCalendar: return 16
            case .reservationProvider: return 18
            case .nightlifeAggregator: return 20
            case .editorialGuide: return 8
            }
        case .concert, .partyNightlife, .weekendActivity, .socialCommunityEvent, .otherLiveEvent:
            switch event.source {
            case .ticketmaster: return 34
            case .stubHub: return 14
            case .seatGeek: return 28
            case .eventbrite:
                if isHighSignalLocalEvent(event) {
                    return event.organizerVerified == true ? 10 : 6
                }
                return 1
            case .runsignup: return 10
            case .googleEvents:
                return isHighSignalLocalEvent(event) ? 24 : 16
            case .sportsSchedule: return 8
            case .appleMaps: return 20
            case .googlePlaces: return 18
            case .yelpFusion: return 18
            case .venueWebsite: return 22
            case .venueCalendar: return 22
            case .reservationProvider: return 24
            case .nightlifeAggregator: return 26
            case .editorialGuide: return 12
            }
        }
    }

    static func trustedVenueScore(for event: ExternalEvent) -> Int {
        let venue = normalizeToken(event.venueName)
        guard !venue.isEmpty else { return 0 }

        var dynamicScore = 0
        if let venueSignalScore = event.venueSignalScore {
            dynamicScore += Int(venueSignalScore.rounded())
        }
        if let popularityScoreRaw = event.popularityScoreRaw {
            dynamicScore += Int(popularityScoreRaw.rounded())
        }
        if event.guestListAvailable == true { dynamicScore += 4 }
        if event.bottleServiceAvailable == true { dynamicScore += 6 }
        if event.tableMinPrice != nil { dynamicScore += 5 }
        if event.reservationURL != nil { dynamicScore += 3 }
        if event.ageMinimum == 21 { dynamicScore += 1 }
        let signalHaystack = searchableHaystack(for: event)
        if signalHaystack.contains("discotech") { dynamicScore += 3 }
        if signalHaystack.contains("clubbable") { dynamicScore += 3 }
        if signalHaystack.contains("hwood") || signalHaystack.contains("h wood") || signalHaystack.contains("rolodex") {
            dynamicScore += 5
        }
        let premiumTokens = [
            "bottle service only",
            "guest list access",
            "table booking",
            "table bookings",
            "table minimum",
            "hard door",
            "celebrit",
            "supper club",
            "luxury nightlife",
            "private room",
            "reservation required"
        ]
        if premiumTokens.contains(where: signalHaystack.contains) {
            dynamicScore += 4
        }

        let strongGenericVenueTokens = [
            "theatre",
            "theater",
            "amphitheatre",
            "amphitheater",
            "auditorium",
            "arena",
            "stadium",
            "music hall",
            "ballroom",
            "dome",
            "forum",
            "garden",
            "field",
            "pavilion",
            "lounge",
            "nightclub",
            "night club",
            "club",
            "rooftop",
            "hotel",
            "resort"
        ]
        if strongGenericVenueTokens.contains(where: venue.contains) {
            return max(dynamicScore, 8)
        }
        if event.source == .appleMaps || event.source == .googlePlaces || event.source == .yelpFusion {
            return max(dynamicScore, 5)
        }
        return dynamicScore
    }

    static func isHighSignalLocalEvent(_ event: ExternalEvent) -> Bool {
        if trustedVenueScore(for: event) >= 12 {
            return true
        }
        if let venuePopularityCount = event.venuePopularityCount, venuePopularityCount >= 40 {
            return true
        }
        if let venueRating = event.venueRating,
           let venuePopularityCount = event.venuePopularityCount,
           venueRating >= 4.4,
           venuePopularityCount >= 500 {
            return true
        }
        if event.organizerVerified == true, let organizerEventCount = event.organizerEventCount, organizerEventCount >= 35 {
            return true
        }
        if let sourceConfidence = event.sourceConfidence, sourceConfidence >= 0.85,
           let venueSignalScore = event.venueSignalScore, venueSignalScore >= 6 {
            return true
        }
        if let popularityScoreRaw = event.popularityScoreRaw, popularityScoreRaw >= 7 {
            return true
        }
        if marqueeEventBoost(for: event) >= 18 {
            return true
        }
        switch event.availabilityStatus {
        case .soldOut:
            return true
        case .onsale, .openRegistration, .available, .registrationClosed, .cancelled, .postponed, .rescheduled, .ended, .unknown:
            break
        }
        if event.urgencyBadge != nil, event.eventType == .concert || event.eventType == .partyNightlife {
            return true
        }
        return false
    }

    private static func looksStripClubOrAdultVenue(_ event: ExternalEvent) -> Bool {
        let haystack = searchableHaystack(for: event)
        let blockedPhrases = [
            "strip club",
            "strip clubs",
            "gentlemen's club",
            "gentleman's club",
            "gentlemens club",
            "gentlemen club",
            "adult cabaret",
            "adult entertainment",
            "exotic dancer",
            "exotic dancers",
            "nude club",
            "topless club",
            "fully nude",
            "full nude"
        ]
        return blockedPhrases.contains(where: { haystack.contains($0) })
    }

    private static func looksCannabisOrPrivateReserveVenue(_ event: ExternalEvent) -> Bool {
        let haystack = searchableHaystack(for: event)
        let blockedPhrases = [
            "private reserve",
            "private reserve view events",
            "exclusive cannabis lounge",
            "cannabis lounge",
            "cannabis club",
            "weed lounge",
            "dispensary lounge",
            "consumption lounge"
        ]
        return blockedPhrases.contains(where: { haystack.contains($0) })
    }

    static func shouldPreferFallbackCardArt(for event: ExternalEvent) -> Bool {
        guard event.imageURL != nil else {
            return true
        }

        if event.source == .eventbrite {
            if looksPosterStyleFlyer(event) && !isHighSignalLocalEvent(event) {
                return true
            }
            return false
        }

        if event.source == .googleEvents {
            return looksPosterStyleFlyer(event) && marqueeEventBoost(for: event) < 18
        }

        return false
    }

    static func fallbackBannerAsset(for event: ExternalEvent) -> String {
        let haystack = searchableHaystack(for: event)
        let options: [String]
        switch event.eventType {
        case .groupRun, .race5k, .race10k, .raceHalfMarathon, .raceMarathon:
            options = ["005_road-run-and-brisk-walk_realism", "008_bike-ride-and-bike-commute_realism", "030_everyday-walk-and-scenic-route_realism"]
        case .sportsEvent:
            if haystack.contains("basketball") || haystack.contains("lakers") || haystack.contains("clippers") {
                options = ["012_basketball-court-session_realism", "011_track-day_realism", "009_gym-arrival_realism"]
            } else if haystack.contains("soccer") || haystack.contains("fc ") || haystack.contains("lafc") || haystack.contains("galaxy") {
                options = ["011_track-day_realism", "012_basketball-court-session_realism", "030_everyday-walk-and-scenic-route_realism"]
            } else {
                options = ["011_track-day_realism", "012_basketball-court-session_realism", "014_tennis-match_realism", "013_bowling-night_realism"]
            }
        case .concert:
            if haystack.contains("jazz") || haystack.contains("classical") || haystack.contains("symphony") || haystack.contains("theatre") || haystack.contains("theater") {
                options = ["040_museum-visit_realism", "041_gallery-visit_realism", "053_classic-film_realism"]
            } else if haystack.contains("afrobeats") || haystack.contains("latin") || haystack.contains("dance") || haystack.contains("dj") {
                options = ["063_dance-class_realism", "043_community-event-and-open-mic_realism", "038_restaurant-discovery_realism"]
            } else {
                options = ["043_community-event-and-open-mic_realism", "041_gallery-visit_realism", "040_museum-visit_realism", "063_dance-class_realism"]
            }
        case .partyNightlife:
            if isExclusiveEvent(event) {
                options = ["038_restaurant-discovery_realism", "045_coffee-spot_realism", "043_community-event-and-open-mic_realism", "063_dance-class_realism"]
            } else {
                options = ["038_restaurant-discovery_realism", "043_community-event-and-open-mic_realism", "063_dance-class_realism", "041_gallery-visit_realism"]
            }
        case .socialCommunityEvent:
            options = ["043_community-event-and-open-mic_realism", "042_farmers-market-visit_realism", "032_park-outing_realism", "044_volunteer-session_realism"]
        case .weekendActivity:
            if haystack.contains("food") || haystack.contains("drink") || haystack.contains("brunch") || haystack.contains("market") {
                options = ["042_farmers-market-visit_realism", "038_restaurant-discovery_realism", "045_coffee-spot_realism", "046_home-cooking_realism"]
            } else if haystack.contains("comedy") || haystack.contains("film") || haystack.contains("show") {
                options = ["053_classic-film_realism", "040_museum-visit_realism", "041_gallery-visit_realism"]
            } else {
                options = ["040_museum-visit_realism", "042_farmers-market-visit_realism", "032_park-outing_realism", "038_restaurant-discovery_realism", "049_day-trip-and-solo-adventure_realism"]
            }
        case .otherLiveEvent:
            options = ["043_community-event-and-open-mic_realism", "040_museum-visit_realism", "032_park-outing_realism", "049_day-trip-and-solo-adventure_realism", "045_coffee-spot_realism"]
        }

        let seed = (event.sourceEventID + event.title + (event.venueName ?? "")).unicodeScalars.reduce(0) { partialResult, scalar in
            partialResult + Int(scalar.value)
        }
        return options[seed % options.count]
    }

    static func prominenceSignalScore(for event: ExternalEvent) -> Int {
        var score = 0
        if let venuePopularityCount = event.venuePopularityCount {
            score += min(venuePopularityCount / 150, 20)
        }
        if let popularityScoreRaw = event.popularityScoreRaw {
            score += min(Int(popularityScoreRaw.rounded()), 16)
        }
        if let venueRating = event.venueRating, venueRating >= 4.5 {
            score += 8
        } else if let venueRating = event.venueRating, venueRating >= 4.2 {
            score += 4
        }
        if let ticketProviderCount = event.ticketProviderCount {
            score += min(ticketProviderCount * 2, 10)
        }
        if trustedVenueScore(for: event) >= 12 {
            score += 10
        }
        if isExclusiveEvent(event) {
            score += 14
        }
        if event.eventType == .sportsEvent {
            score += 14
        }
        if event.source == .googleEvents {
            score += 6
        }
        if event.mergedSources.count > 1 {
            score += 7
        }
        score += marqueeEventBoost(for: event)
        return score
    }

    static func isExclusiveEvent(_ event: ExternalEvent) -> Bool {
        let haystack = searchableHaystack(for: event)
        let exclusiveTokens = [
            "bottle service",
            "bottle service only",
            "hard door",
            "vip table",
            "exclusive",
            "celeb",
            "celebrity heavy",
            "celebrities party",
            "velvet rope",
            "guest list",
            "guest list access",
            "reservation required",
            "reservation only",
            "table minimum",
            "table booking",
            "members only",
            "private club",
            "dress code",
            "supper club",
            "hwood",
            "rolodex"
        ]
        guard event.eventType == .partyNightlife || event.eventType == .concert else {
            return false
        }
        if event.guestListAvailable == true || event.bottleServiceAvailable == true || event.tableMinPrice != nil {
            return true
        }
        if event.reservationURL != nil && trustedVenueScore(for: event) >= 12 {
            return true
        }
        if let exclusivityScore = event.exclusivityScore, exclusivityScore >= 6 {
            return true
        }
        return exclusiveTokens.contains(where: haystack.contains) || trustedVenueScore(for: event) >= 18
    }

    static func organizerBlacklistPenalty(for event: ExternalEvent) -> Int {
        let haystack = searchableHaystack(for: event)
        let organizer = normalizeToken(event.organizerName)
        var penalty = 0

        let hardTokens = [
            "business networking",
            "professional networking",
            "entrepreneur",
            "founders",
            "startup",
            "summit",
            "expo",
            "trade show",
            "masterclass",
            "webinar",
            "bootcamp",
            "investment",
            "investor",
            "real estate",
            "crypto",
            "job fair",
            "recruiting"
        ]
        let softTokens = [
            "conference",
            "seminar",
            "workshop",
            "academy",
            "consulting",
            "solutions",
            "marketing",
            "small business",
            "leadership",
            "wealth",
            "sales"
        ]
        let organizerShapeTokens = [
            "academy",
            "consulting",
            "solutions",
            "media group",
            "ventures",
            "enterprise",
            "coaching"
        ]

        if hardTokens.contains(where: haystack.contains) {
            penalty += 18
        }
        if softTokens.contains(where: haystack.contains) {
            penalty += 8
        }
        if organizerShapeTokens.contains(where: organizer.contains) {
            penalty += 6
        }
        if event.source == .eventbrite, event.organizerVerified != true, penalty > 0 {
            penalty += 6
        }

        return penalty
    }

    static func normalizedOrganizerKey(for event: ExternalEvent) -> String? {
        let normalized = normalizeToken(event.organizerName)
        return normalized.isEmpty ? nil : normalized
    }

    static func normalizedVenueKey(for event: ExternalEvent) -> String? {
        let normalized = normalizeToken(event.venueName ?? event.addressLine1)
        return normalized.isEmpty ? nil : normalized
    }

    static func merge(primary: ExternalEvent, secondary: ExternalEvent) -> ExternalEvent {
        var merged = primary
        merged.mergedSources = Array(Set(primary.mergedSources + secondary.mergedSources)).sorted { $0.rawValue < $1.rawValue }
        merged.sourceURL = merged.sourceURL ?? secondary.sourceURL
        merged.shortDescription = betterNightlifeText(primary: merged.shortDescription, secondary: secondary.shortDescription)
        merged.fullDescription = betterNightlifeText(primary: merged.fullDescription, secondary: secondary.fullDescription)
        merged.category = merged.category ?? secondary.category
        merged.subcategory = merged.subcategory ?? secondary.subcategory
        merged.endAtUTC = merged.endAtUTC ?? secondary.endAtUTC
        merged.startAtUTC = merged.startAtUTC ?? secondary.startAtUTC
        merged.startLocal = merged.startLocal ?? secondary.startLocal
        merged.endLocal = merged.endLocal ?? secondary.endLocal
        merged.timezone = merged.timezone ?? secondary.timezone
        merged.salesStartAtUTC = merged.salesStartAtUTC ?? secondary.salesStartAtUTC
        merged.salesEndAtUTC = merged.salesEndAtUTC ?? secondary.salesEndAtUTC
        merged.venueName = merged.venueName ?? secondary.venueName
        merged.venueID = merged.venueID ?? secondary.venueID
        merged.addressLine1 = preferredAddressLine(
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
        merged.imageURL = preferredImageURL(primary: merged.imageURL, secondary: secondary.imageURL)
        merged.status = primary.status == .unknown ? secondary.status : primary.status
        merged.availabilityStatus = primary.availabilityStatus == .unknown ? secondary.availabilityStatus : primary.availabilityStatus
        merged.urgencyBadge = merged.urgencyBadge ?? secondary.urgencyBadge
        merged.socialProofCount = merged.socialProofCount ?? secondary.socialProofCount
        merged.socialProofLabel = merged.socialProofLabel ?? secondary.socialProofLabel
        merged.venuePopularityCount = merged.venuePopularityCount ?? secondary.venuePopularityCount
        merged.venueRating = merged.venueRating ?? secondary.venueRating
        merged.ticketProviderCount = merged.ticketProviderCount ?? secondary.ticketProviderCount
        merged.priceMin = merged.priceMin ?? secondary.priceMin
        merged.priceMax = merged.priceMax ?? secondary.priceMax
        merged.currency = merged.currency ?? secondary.currency
        merged.organizerName = merged.organizerName ?? secondary.organizerName
        merged.organizerEventCount = merged.organizerEventCount ?? secondary.organizerEventCount
        merged.organizerVerified = merged.organizerVerified ?? secondary.organizerVerified
        merged.tags = Array(Set(primary.tags + secondary.tags)).sorted()
        merged.distanceValue = merged.distanceValue ?? secondary.distanceValue
        merged.distanceUnit = merged.distanceUnit ?? secondary.distanceUnit
        merged.raceType = merged.raceType ?? secondary.raceType
        merged.registrationURL = merged.registrationURL ?? secondary.registrationURL
        merged.ticketURL = merged.ticketURL ?? secondary.ticketURL
        merged.neighborhood = merged.neighborhood ?? secondary.neighborhood
        merged.reservationURL = merged.reservationURL ?? secondary.reservationURL
        merged.artistsOrTeams = Array(Set(primary.artistsOrTeams + secondary.artistsOrTeams)).sorted()
        merged.ageMinimum = merged.ageMinimum ?? secondary.ageMinimum
        merged.doorPolicyText = betterNightlifeText(primary: merged.doorPolicyText, secondary: secondary.doorPolicyText)
        merged.dressCodeText = betterNightlifeText(primary: merged.dressCodeText, secondary: secondary.dressCodeText)
        merged.guestListAvailable = (merged.guestListAvailable == true || secondary.guestListAvailable == true)
            ? true
            : merged.guestListAvailable ?? secondary.guestListAvailable
        merged.bottleServiceAvailable = (merged.bottleServiceAvailable == true || secondary.bottleServiceAvailable == true)
            ? true
            : merged.bottleServiceAvailable ?? secondary.bottleServiceAvailable
        merged.tableMinPrice = richerNightlifePrice(primary: merged.tableMinPrice, secondary: secondary.tableMinPrice)
        merged.coverPrice = richerNightlifePrice(primary: merged.coverPrice, secondary: secondary.coverPrice)
        merged.openingHoursText = betterNightlifeText(primary: merged.openingHoursText, secondary: secondary.openingHoursText)
        merged.entryPolicySummary = betterNightlifeText(primary: merged.entryPolicySummary, secondary: secondary.entryPolicySummary)
        merged.womenEntryPolicyText = betterNightlifeText(primary: merged.womenEntryPolicyText, secondary: secondary.womenEntryPolicyText)
        merged.menEntryPolicyText = betterNightlifeText(primary: merged.menEntryPolicyText, secondary: secondary.menEntryPolicyText)
        merged.exclusivityTierLabel = moreExclusiveTier(primary: merged.exclusivityTierLabel, secondary: secondary.exclusivityTierLabel)
        merged.rawSourcePayload = mergedPayload(primary: primary.rawSourcePayload, secondary: secondary.rawSourcePayload)
        if merged.eventType == .partyNightlife || merged.recordKind == .venueNight {
            merged.imageURL = preferredNightlifeImageURL(primary: merged.imageURL, payload: merged.rawSourcePayload)
        }
        merged.sourceConfidence = max(primary.sourceConfidence ?? 0, secondary.sourceConfidence ?? 0)
        merged.popularityScoreRaw = max(primary.popularityScoreRaw ?? 0, secondary.popularityScoreRaw ?? 0)
        merged.venueSignalScore = max(primary.venueSignalScore ?? 0, secondary.venueSignalScore ?? 0)
        merged.exclusivityScore = max(primary.exclusivityScore ?? 0, secondary.exclusivityScore ?? 0)
        merged.trendingScore = max(primary.trendingScore ?? 0, secondary.trendingScore ?? 0)
        merged.crossSourceConfirmationScore = max(primary.crossSourceConfirmationScore ?? 0, secondary.crossSourceConfirmationScore ?? 0)
        merged.distanceFromUser = min(primary.distanceFromUser ?? .greatestFiniteMagnitude, secondary.distanceFromUser ?? .greatestFiniteMagnitude)
        if merged.distanceFromUser == .greatestFiniteMagnitude {
            merged.distanceFromUser = nil
        }
        return merged
    }

    static func isLikelyDuplicate(_ lhs: ExternalEvent, _ rhs: ExternalEvent) -> Bool {
        if lhs.id == rhs.id || lhs.sourceEventID == rhs.sourceEventID {
            return true
        }
        if canonicalSourcePath(lhs.sourceURL) == canonicalSourcePath(rhs.sourceURL),
           canonicalSourcePath(lhs.sourceURL) != nil {
            return true
        }

        let leftDay = localDayToken(startLocal: lhs.startLocal, startAtUTC: lhs.startAtUTC, timezone: lhs.timezone)
        let rightDay = localDayToken(startLocal: rhs.startLocal, startAtUTC: rhs.startAtUTC, timezone: rhs.timezone)
        guard leftDay == rightDay else { return false }

        let leftFingerprint = dedupeTitleFingerprint(lhs.title, eventType: lhs.eventType, venueName: lhs.venueName)
        let rightFingerprint = dedupeTitleFingerprint(rhs.title, eventType: rhs.eventType, venueName: rhs.venueName)
        let leftState = normalizeStateToken(lhs.state)
        let rightState = normalizeStateToken(rhs.state)
        let leftAddress = normalizeToken(lhs.addressLine1)
        let rightAddress = normalizeToken(rhs.addressLine1)
        let leftCity = normalizeToken(lhs.city)
        let rightCity = normalizeToken(rhs.city)
        let sharedExactAddress = !leftAddress.isEmpty
            && leftAddress == rightAddress
            && !leftState.isEmpty
            && leftState == rightState
        let nightlifeAliasPair = (lhs.eventType == .partyNightlife || lhs.recordKind == .venueNight)
            && (rhs.eventType == .partyNightlife || rhs.recordKind == .venueNight)
            && sharedExactAddress
            && normalizedTitleAliasMatch(lhs.title, rhs.title)

        if nightlifeAliasPair {
            return true
        }

        if lhs.eventType == .sportsEvent || rhs.eventType == .sportsEvent {
            return leftFingerprint == rightFingerprint
                && (
                    leftCity == rightCity
                    || (leftState == rightState && marqueeEventBoost(for: lhs) >= 18 && marqueeEventBoost(for: rhs) >= 18)
                )
        }

        if leftFingerprint == rightFingerprint {
            let leftVenue = normalizeToken(lhs.venueName ?? lhs.addressLine1)
            let rightVenue = normalizeToken(rhs.venueName ?? rhs.addressLine1)
            if !leftVenue.isEmpty, leftVenue == rightVenue {
                return true
            }
            if leftCity == rightCity,
               leftState == rightState {
                return true
            }
            let weakSourcePair = Set([lhs.source, rhs.source])
            if leftState == rightState,
               weakSourcePair.intersection([.googleEvents, .eventbrite, .stubHub]).isEmpty == false {
                return true
            }
        }

        let leftVenue = normalizeToken(lhs.venueName ?? lhs.addressLine1)
        let rightVenue = normalizeToken(rhs.venueName ?? rhs.addressLine1)
        let sharedVenue = !leftVenue.isEmpty && leftVenue == rightVenue
        let sharedMetro = !leftCity.isEmpty
            && !leftState.isEmpty
            && leftCity == rightCity
            && leftState == rightState
        let sharedCoordinates = coordinatesNearlyMatch(lhs, rhs)
        let overlap = titleTokenOverlapScore(leftFingerprint, rightFingerprint)
        if overlap >= 0.52 && (sharedExactAddress || sharedVenue || sharedCoordinates) {
            return true
        }
        if overlap >= 0.72 && (sharedVenue || sharedMetro || leftVenue.isEmpty || rightVenue.isEmpty) {
            return true
        }

        let leftTitleTokens = titleTokenSet(for: lhs)
        let rightTitleTokens = titleTokenSet(for: rhs)
        let contained = !leftTitleTokens.isEmpty
            && !rightTitleTokens.isEmpty
            && (leftTitleTokens.isSubset(of: rightTitleTokens)
                || rightTitleTokens.isSubset(of: leftTitleTokens))
        if contained && (sharedVenue || sharedMetro || leftVenue.isEmpty || rightVenue.isEmpty) {
            return true
        }

        if contained && (sharedExactAddress || sharedCoordinates) {
            return true
        }

        if contained && leftState == rightState && marqueeEventBoost(for: lhs) >= 18 && marqueeEventBoost(for: rhs) >= 18 {
            return true
        }

        return false
    }

    private static func coordinatesNearlyMatch(_ lhs: ExternalEvent, _ rhs: ExternalEvent) -> Bool {
        guard let leftLatitude = lhs.latitude,
              let leftLongitude = lhs.longitude,
              let rightLatitude = rhs.latitude,
              let rightLongitude = rhs.longitude else {
            return false
        }
        return abs(leftLatitude - rightLatitude) <= 0.00035
            && abs(leftLongitude - rightLongitude) <= 0.00035
    }

    private static func normalizedTitleAliasMatch(_ lhs: String, _ rhs: String) -> Bool {
        let left = normalizeToken(lhs)
        let right = normalizeToken(rhs)
        guard !left.isEmpty, !right.isEmpty else { return false }
        if left == right { return true }

        let shorter = left.count <= right.count ? left : right
        let longer = left.count <= right.count ? right : left
        if shorter.count >= 8, longer.contains(shorter) {
            return true
        }

        let leftTokens = Set(left.split(separator: " ").map(String.init))
        let rightTokens = Set(right.split(separator: " ").map(String.init))
        guard !leftTokens.isEmpty, !rightTokens.isEmpty else { return false }
        let overlap = Double(leftTokens.intersection(rightTokens).count) / Double(min(leftTokens.count, rightTokens.count))
        return overlap >= 0.8
    }

    private static func canonicalSourcePath(_ urlString: String?) -> String? {
        guard let urlString,
              let components = URLComponents(string: urlString),
              let host = components.host else {
            return nil
        }
        let path = components.path.isEmpty ? "/" : components.path
        return normalizeToken(host + path)
    }

    private static func titleTokenOverlapScore(_ lhs: String, _ rhs: String) -> Double {
        let leftTokens = Set(lhs.split(separator: " ").map(String.init))
        let rightTokens = Set(rhs.split(separator: " ").map(String.init))
        guard !leftTokens.isEmpty, !rightTokens.isEmpty else { return 0 }
        let intersection = leftTokens.intersection(rightTokens).count
        let union = leftTokens.union(rightTokens).count
        guard union > 0 else { return 0 }
        return Double(intersection) / Double(union)
    }

    private static func hasMeaningfulVenue(_ event: ExternalEvent) -> Bool {
        let normalizedVenue = normalizeToken(event.venueName)
        if normalizedVenue.isEmpty {
            return false
        }

        let blocked = [
            "online event",
            "location tba",
            "venue tba",
            "tba",
            "tbd"
        ]
        if blocked.contains(normalizedVenue) {
            return false
        }

        if let addressLine1 = event.addressLine1,
           normalizedVenue == normalizeToken(addressLine1) {
            return true
        }

        return normalizedVenue.count >= 4
    }

    private static func hasMeaningfulDescription(_ event: ExternalEvent) -> Bool {
        let text = (event.shortDescription ?? event.fullDescription ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        return text.count >= 36
    }

    private static func looksOnlineOrVirtual(_ event: ExternalEvent) -> Bool {
        let haystack = searchableHaystack(for: event)
        let tokens = [
            "online",
            "virtual",
            "zoom",
            "livestream",
            "live stream",
            "webinar",
            "web cast"
        ]
        return tokens.contains(where: haystack.contains)
    }

    private static func looksProfessionalPromoEvent(_ event: ExternalEvent) -> Bool {
        let haystack = searchableHaystack(for: event)
        let tokens = [
            "conference",
            "summit",
            "expo",
            "trade show",
            "networking",
            "entrepreneur",
            "startup",
            "small business",
            "marketing",
            "adtech",
            "martech",
            "biomed",
            "medicine",
            "medical",
            "workshop",
            "seminar",
            "masterclass",
            "certification",
            "bootcamp",
            "crypto",
            "investing",
            "investment",
            "real estate",
            "job fair",
            "recruiting"
        ]
        return tokens.contains(where: haystack.contains)
    }

    private static func looksNoisyTitle(_ title: String) -> Bool {
        let separators = title.filter { "|/".contains($0) }.count
        return title.count > 110 || separators >= 4
    }

    private static func isLikelySmallPromoterNight(_ event: ExternalEvent) -> Bool {
        guard event.source == .eventbrite else { return false }
        guard event.eventType == .concert || event.eventType == .partyNightlife || event.eventType == .weekendActivity else {
            return false
        }
        if isHighSignalLocalEvent(event) {
            return false
        }

        let haystack = searchableHaystack(for: event)
        let lowSignalNightTokens = [
            "day party",
            "sunday funday",
            "birthday bash",
            "all white",
            "free entry",
            "guest list",
            "tables",
            "text for tables",
            "section info",
            "hookah",
            "kickback",
            "mixer",
            "after hours",
            "afterhours",
            "rooftop party",
            "pool party"
        ]
        let lowSignalVenueTokens = [
            "private residence",
            "house",
            "backyard",
            "apartment",
            "secret location",
            "address revealed later"
        ]

        if lowSignalNightTokens.contains(where: haystack.contains) {
            return true
        }
        if lowSignalVenueTokens.contains(where: haystack.contains) {
            return true
        }
        if event.organizerVerified != true, (event.organizerEventCount ?? 0) < 20, trustedVenueScore(for: event) == 0 {
            return true
        }
        return false
    }

    private static func looksPosterStyleFlyer(_ event: ExternalEvent) -> Bool {
        let haystack = searchableHaystack(for: event)
        let posterTokens = [
            "day party",
            "st patrick",
            "memorial day",
            "labor day",
            "birthday bash",
            "all white",
            "tickets at the door",
            "free with rsvp",
            "tables available"
        ]
        return posterTokens.contains(where: haystack.contains) || looksNoisyTitle(event.title)
    }

    private static func searchableHaystack(for event: ExternalEvent) -> String {
        normalizeToken([
            event.title,
            event.shortDescription,
            event.fullDescription,
            event.category,
            event.subcategory,
            event.organizerName,
            event.venueName,
            event.tags.joined(separator: " ")
        ]
        .compactMap { $0 }
        .joined(separator: " "))
    }

    private static let losAngelesMetroTokens: Set<String> = [
        "west hollywood",
        "weho",
        "los angeles",
        "hollywood",
        "beverly hills",
        "santa monica",
        "venice",
        "culver city",
        "silver lake",
        "echo park",
        "los feliz",
        "arts district",
        "dtla",
        "downtown los angeles",
        "koreatown",
        "inglewood",
        "carson",
        "glendale",
        "pasadena",
        "burbank",
        "studio city",
        "sherman oaks",
        "encino",
        "brentwood",
        "playa vista",
        "manhattan beach",
        "redondo beach",
        "long beach"
    ]

    private struct GoogleDateParts {
        let month: Int?
        let day: Int?
        let time: String?
        let meridiem: String?
    }

    private static func googleDateComponents(
        from rawValue: String,
        fallbackMonth: Int?,
        fallbackDay: Int?,
        fallbackMeridiem: String?
    ) -> GoogleDateParts? {
        let cleaned = rawValue
            .replacingOccurrences(of: #"^(Mon|Tue|Wed|Thu|Fri|Sat|Sun),?\s+"#, with: "", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleaned.isEmpty else { return nil }

        let monthLookup: [String: Int] = [
            "jan": 1, "feb": 2, "mar": 3, "apr": 4, "may": 5, "jun": 6,
            "jul": 7, "aug": 8, "sep": 9, "oct": 10, "nov": 11, "dec": 12
        ]

        let monthMatch = cleaned.range(of: #"(Jan|Feb|Mar|Apr|May|Jun|Jul|Aug|Sep|Oct|Nov|Dec)\s+([0-9]{1,2})"#, options: .regularExpression)
        let month: Int?
        let day: Int?
        let timeFragment: String

        if let monthMatch {
            let match = String(cleaned[monthMatch])
            let bits = match.split(separator: " ")
            month = bits.first.flatMap { monthLookup[String($0).prefix(3).lowercased()] }
            day = bits.dropFirst().first.flatMap { Int($0) }
            timeFragment = trim(cleaned.replacingOccurrences(of: match, with: ""), extra: CharacterSet(charactersIn: ","))
        } else {
            month = fallbackMonth
            day = fallbackDay
            timeFragment = trim(cleaned, extra: CharacterSet(charactersIn: ","))
        }

        let meridiem = googleMeridiem(from: timeFragment) ?? fallbackMeridiem
        let time = googleTimeFragment(from: timeFragment)

        return GoogleDateParts(month: month, day: day, time: time, meridiem: meridiem)
    }

    private static func googleMeridiem(from rawValue: String?) -> String? {
        let normalized = normalizeToken(rawValue)
        if normalized.contains("am") { return "AM" }
        if normalized.contains("pm") { return "PM" }
        return nil
    }

    private static func googleTimeFragment(from rawValue: String) -> String? {
        let match = rawValue.range(of: #"[0-9]{1,2}(?::[0-9]{2})?"#, options: .regularExpression)
        return match.map { String(rawValue[$0]) }
    }

    private static func googleDate(
        month: Int?,
        day: Int?,
        year: Int,
        time: String?,
        meridiem: String?,
        timezone: TimeZone
    ) -> Date? {
        guard let month, let day else { return nil }
        var components = DateComponents()
        components.year = year
        components.month = month
        components.day = day
        components.timeZone = timezone

        if let time, !time.isEmpty {
            let parts = time.split(separator: ":")
            var hour = Int(parts.first ?? "") ?? 0
            let minute = parts.count > 1 ? (Int(parts[1]) ?? 0) : 0
            if meridiem == "PM", hour < 12 {
                hour += 12
            } else if meridiem == "AM", hour == 12 {
                hour = 0
            }
            components.hour = hour
            components.minute = minute
        } else {
            components.hour = 0
            components.minute = 0
        }

        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timezone
        return calendar.date(from: components)
    }

    private static func googleLocalDateString(from date: Date?, timezone: TimeZone) -> String? {
        guard let date else { return nil }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ss"
        formatter.timeZone = timezone
        return formatter.string(from: date)
    }

    private static func trim(_ value: String, extra: CharacterSet) -> String {
        value.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines.union(extra))
    }
}

private extension Array {
    subscript(safe index: Int) -> Element? {
        guard indices.contains(index) else { return nil }
        return self[index]
    }
}

enum ExternalEventIngestionError: Error, Sendable, LocalizedError {
    case invalidJSON
    case missingCredential(String)
    case missingEndpointInstruction(String)
    case httpStatus(Int)

    var errorDescription: String? {
        switch self {
        case .invalidJSON:
            return "Response JSON was invalid."
        case .missingCredential(let message):
            return message
        case .missingEndpointInstruction(let message):
            return message
        case .httpStatus(let code):
            return "HTTP \(code)"
        }
    }
}

extension Dictionary where Key == String, Value == Any {
    func value(at path: [String]) -> Any? {
        var current: Any? = self
        for key in path {
            guard let dict = current as? JSONDictionary else { return nil }
            current = dict[key]
        }
        return current
    }

    func string(_ key: String) -> String? {
        switch self[key] {
        case let value as String:
            return value
        case let value as Int:
            return String(value)
        case let value as Double:
            return String(value)
        default:
            return nil
        }
    }

    func string(at path: [String]) -> String? {
        switch value(at: path) {
        case let value as String:
            return value
        case let value as Int:
            return String(value)
        case let value as Double:
            return String(value)
        default:
            return nil
        }
    }

    func dictionary(_ key: String) -> JSONDictionary? {
        self[key] as? JSONDictionary
    }

    func dictionary(at path: [String]) -> JSONDictionary? {
        value(at: path) as? JSONDictionary
    }

    func array(_ key: String) -> [JSONDictionary] {
        self[key] as? [JSONDictionary] ?? []
    }

    func array(at path: [String]) -> [JSONDictionary] {
        value(at: path) as? [JSONDictionary] ?? []
    }
}

enum ExternalEventImageCacheService {
    private static let fileManager = FileManager.default

    static func cachedLocalURLString(for remoteURLString: String?) -> String? {
        guard let remoteURLString = ExternalEventSupport.normalizedImageURLString(remoteURLString),
              let fileURL = cachedFileURL(for: remoteURLString),
              fileManager.fileExists(atPath: fileURL.path)
        else {
            return nil
        }
        return fileURL.path
    }

    static func prefetch(urlStrings: [String], limit: Int = 24) async {
        let targets = Array(
            Set(urlStrings.compactMap(ExternalEventSupport.normalizedImageURLString(_:)))
        )
        .prefix(limit)

        await withTaskGroup(of: Void.self) { group in
            for urlString in targets {
                group.addTask {
                    await cache(remoteURLString: urlString)
                }
            }
        }
    }

    @discardableResult
    static func cache(remoteURLString: String) async -> String? {
        guard let normalized = ExternalEventSupport.normalizedImageURLString(remoteURLString),
              let remoteURL = URL(string: normalized),
              !remoteURL.isFileURL,
              let destinationURL = cachedFileURL(for: normalized)
        else {
            return nil
        }

        if fileManager.fileExists(atPath: destinationURL.path) {
            return destinationURL.path
        }

        do {
            try fileManager.createDirectory(
                at: destinationURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            let (data, response) = try await URLSession.shared.data(from: remoteURL)
            guard let http = response as? HTTPURLResponse,
                  200..<300 ~= http.statusCode,
                  !data.isEmpty
            else {
                return nil
            }
            try data.write(to: destinationURL, options: .atomic)
            return destinationURL.path
        } catch {
            return nil
        }
    }

    private static func cachedFileURL(for remoteURLString: String) -> URL? {
        guard let cachesDirectory = fileManager.urls(for: .cachesDirectory, in: .userDomainMask).first,
              let remoteURL = URL(string: remoteURLString)
        else {
            return nil
        }

        let ext = preferredFileExtension(for: remoteURL)
        let digest = SHA256.hash(data: Data(remoteURLString.utf8)).map { String(format: "%02x", $0) }.joined()
        return cachesDirectory
            .appendingPathComponent("external_event_images", isDirectory: true)
            .appendingPathComponent("\(digest).\(ext)", isDirectory: false)
    }

    private static func preferredFileExtension(for remoteURL: URL) -> String {
        let rawPathExtension = remoteURL.pathExtension.lowercased()
        if ["jpg", "jpeg", "png", "webp", "heic"].contains(rawPathExtension) {
            return rawPathExtension == "jpeg" ? "jpg" : rawPathExtension
        }

        let normalized = remoteURL.absoluteString.lowercased()
        if normalized.contains(".png") { return "png" }
        if normalized.contains(".webp") { return "webp" }
        if normalized.contains(".heic") { return "heic" }
        return "jpg"
    }
}
