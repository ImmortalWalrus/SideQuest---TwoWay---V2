import Foundation
import MapKit

nonisolated struct AppleMapsVenueAdapter: ExternalVenueSourceAdapter {
    let source: ExternalEventSource = .appleMaps

    private struct SearchChannel: Sendable {
        let label: String
        let query: String
        let radiusMiles: Double
        let venueType: ExternalVenueType
        let nightlifeWeight: Double
    }

    func discoverVenues(
        query: ExternalVenueQuery,
        session: URLSession,
        configuration: ExternalEventServiceConfiguration
    ) async -> ExternalVenueSourceResult {
        let channels = buildChannels(for: query)
        var endpoints: [ExternalEventEndpointResult] = []
        var venues: [ExternalVenue] = []

        await withTaskGroup(of: (ExternalEventEndpointResult, [ExternalVenue]).self) { group in
            for channel in channels {
                group.addTask {
                    await search(channel: channel, query: query)
                }
            }

            for await result in group {
                endpoints.append(result.0)
                venues.append(contentsOf: result.1)
            }
        }

        let merged = ExternalVenueDiscoveryService.merge(venues)
        return ExternalVenueSourceResult(
            source: source,
            fetchedAt: Date(),
            endpoints: endpoints.sorted { $0.label < $1.label },
            note: merged.isEmpty ? "Apple Maps local search returned no venue candidates for the current coordinate." : nil,
            venues: merged
        )
    }

    private func buildChannels(for query: ExternalVenueQuery) -> [SearchChannel] {
        [
            SearchChannel(label: "nightlife", query: "night club", radiusMiles: query.nightlifeRadiusMiles, venueType: .nightlifeVenue, nightlifeWeight: 3.2),
            SearchChannel(label: "lounge", query: "lounge", radiusMiles: query.nightlifeRadiusMiles, venueType: .lounge, nightlifeWeight: 3.0),
            SearchChannel(label: "supper-club", query: "supper club", radiusMiles: query.nightlifeRadiusMiles, venueType: .lounge, nightlifeWeight: 3.1),
            SearchChannel(label: "hotel-lounge", query: "hotel lounge", radiusMiles: query.nightlifeRadiusMiles, venueType: .lounge, nightlifeWeight: 3.0),
            SearchChannel(label: "hotel-bar", query: "hotel bar", radiusMiles: query.nightlifeRadiusMiles, venueType: .lounge, nightlifeWeight: 3.0),
            SearchChannel(label: "private-club", query: "private club", radiusMiles: query.nightlifeRadiusMiles, venueType: .nightlifeVenue, nightlifeWeight: 3.3),
            SearchChannel(label: "rooftop", query: "rooftop lounge", radiusMiles: query.nightlifeRadiusMiles, venueType: .lounge, nightlifeWeight: 2.8),
            SearchChannel(label: "rooftop-bar", query: "rooftop bar", radiusMiles: query.nightlifeRadiusMiles, venueType: .lounge, nightlifeWeight: 3.1),
            SearchChannel(label: "hotel-rooftop", query: "hotel rooftop bar", radiusMiles: query.nightlifeRadiusMiles, venueType: .lounge, nightlifeWeight: 3.2),
            SearchChannel(label: "cocktail-lounge", query: "cocktail lounge", radiusMiles: query.nightlifeRadiusMiles, venueType: .bar, nightlifeWeight: 2.7),
            SearchChannel(label: "cocktail", query: "cocktail bar", radiusMiles: query.nightlifeRadiusMiles, venueType: .bar, nightlifeWeight: 2.2),
            SearchChannel(label: "restaurant-lounge", query: "restaurant lounge", radiusMiles: query.nightlifeRadiusMiles, venueType: .restaurant, nightlifeWeight: 2.5),
            SearchChannel(label: "live-music", query: "live music venue", radiusMiles: query.nightlifeRadiusMiles, venueType: .concertVenue, nightlifeWeight: 2.6),
            SearchChannel(label: "event-venue", query: "event venue", radiusMiles: query.headlineRadiusMiles, venueType: .artsVenue, nightlifeWeight: 1.4),
            SearchChannel(label: "stadium", query: "stadium", radiusMiles: query.headlineRadiusMiles, venueType: .stadium, nightlifeWeight: 0.6),
            SearchChannel(label: "arena", query: "arena", radiusMiles: query.headlineRadiusMiles, venueType: .arena, nightlifeWeight: 0.6),
            SearchChannel(label: "theater", query: "theater", radiusMiles: query.headlineRadiusMiles, venueType: .artsVenue, nightlifeWeight: 0.8),
            SearchChannel(label: "comedy", query: "comedy club", radiusMiles: query.nightlifeRadiusMiles, venueType: .comedyClub, nightlifeWeight: 1.4)
        ]
    }

    private func search(
        channel: SearchChannel,
        query: ExternalVenueQuery
    ) async -> (ExternalEventEndpointResult, [ExternalVenue]) {
        let center = CLLocationCoordinate2D(latitude: query.latitude, longitude: query.longitude)
        let request = MKLocalSearch.Request()
        request.naturalLanguageQuery = channel.query
        request.resultTypes = .pointOfInterest
        request.region = MKCoordinateRegion(
            center: center,
            latitudinalMeters: channel.radiusMiles * 1609.344 * 2,
            longitudinalMeters: channel.radiusMiles * 1609.344 * 2
        )

        do {
            let response = try await MKLocalSearch(request: request).start()
            let venues = response.mapItems.compactMap { item in
                normalize(item: item, channel: channel)
            }
            return (
                ExternalEventEndpointResult(
                    label: "Apple Maps \(channel.label)",
                    requestURL: "mapkit://local-search/\(channel.query)",
                    responseStatusCode: 200,
                    worked: true,
                    note: venues.isEmpty ? "No venues found for \(channel.query)." : nil
                ),
                venues
            )
        } catch {
            return (
                ExternalEventEndpointResult(
                    label: "Apple Maps \(channel.label)",
                    requestURL: "mapkit://local-search/\(channel.query)",
                    responseStatusCode: nil,
                    worked: false,
                    note: error.localizedDescription
                ),
                []
            )
        }
    }

    private func normalize(item: MKMapItem, channel: SearchChannel) -> ExternalVenue? {
        guard let name = item.name, !name.isEmpty else { return nil }

        let placemark = item.placemark
        let ratinglessSignal = baseSignalScore(for: item, channel: channel)
        let payload: [String: Any] = [
            "name": name,
            "category": channel.label,
            "latitude": placemark.coordinate.latitude,
            "longitude": placemark.coordinate.longitude,
            "url": item.url?.absoluteString as Any,
            "phoneNumber": item.phoneNumber as Any,
            "city": placemark.locality as Any,
            "state": placemark.administrativeArea as Any,
            "subLocality": placemark.subLocality as Any
        ]

        return ExternalVenue(
            id: "\(source.rawValue):\(placemark.coordinate.latitude):\(placemark.coordinate.longitude):\(ExternalEventSupport.normalizeToken(name))",
            source: source,
            sourceType: .venueDiscoveryAPI,
            sourceVenueID: item.identifier?.rawValue ?? ExternalEventSupport.normalizeToken(name),
            canonicalVenueID: nil,
            name: name,
            aliases: [placemark.title, placemark.subLocality, placemark.locality].compactMap { $0 },
            venueType: derivedVenueType(for: item, channel: channel),
            neighborhood: placemark.subLocality,
            addressLine1: postalAddressLine(placemark: placemark),
            addressLine2: nil,
            city: placemark.locality,
            state: placemark.administrativeArea,
            postalCode: placemark.postalCode,
            country: placemark.isoCountryCode ?? "US",
            latitude: placemark.coordinate.latitude,
            longitude: placemark.coordinate.longitude,
            officialSiteURL: item.url?.absoluteString,
            reservationProvider: nil,
            reservationURL: nil,
            imageURL: nil,
            openingHoursText: nil,
            ageMinimum: nil,
            doorPolicyText: nil,
            dressCodeText: nil,
            guestListAvailable: nil,
            bottleServiceAvailable: nil,
            tableMinPrice: nil,
            coverPrice: nil,
            venueSignalScore: ratinglessSignal,
            nightlifeSignalScore: channel.nightlifeWeight > 1 ? ratinglessSignal : nil,
            prestigeDemandScore: ratinglessSignal,
            recurringEventPatternConfidence: channel.venueType == .nightlifeVenue || channel.venueType == .bar ? 0.45 : 0.3,
            sourceConfidence: 0.82,
            sourceCoverageStatus: channel.label,
            rawSourcePayload: ExternalEventSupport.jsonString(payload)
        )
    }

    private func derivedVenueType(for item: MKMapItem, channel: SearchChannel) -> ExternalVenueType {
        let haystack = ExternalEventSupport.normalizeToken([
            item.name,
            item.placemark.title,
            item.placemark.subLocality,
            item.placemark.locality
        ]
        .compactMap { $0 }
        .joined(separator: " "))

        if haystack.contains("stadium") || haystack.contains("ballpark") || haystack.contains("field") {
            return .stadium
        }
        if haystack.contains("arena") || haystack.contains("dome") || haystack.contains("forum") || haystack.contains("garden") {
            return .arena
        }
        if haystack.contains("theater") || haystack.contains("theatre") || haystack.contains("playhouse") {
            return channel.query == "comedy club" ? .comedyClub : .artsVenue
        }
        if haystack.contains("club") {
            return .nightlifeVenue
        }
        if haystack.contains("lounge") {
            return .lounge
        }
        if haystack.contains("bar") || haystack.contains("cocktail") {
            return .bar
        }
        if haystack.contains("music") || haystack.contains("hall") || haystack.contains("pavilion") {
            return .concertVenue
        }
        return channel.venueType
    }

    private func baseSignalScore(for item: MKMapItem, channel: SearchChannel) -> Double {
        var score = 2.8 + channel.nightlifeWeight
        if item.url != nil { score += 1.8 }
        if item.phoneNumber != nil { score += 0.8 }

        let haystack = ExternalEventSupport.normalizeToken([
            item.name,
            item.placemark.title,
            item.placemark.subLocality
        ]
        .compactMap { $0 }
        .joined(separator: " "))

        let prestigeTokens = ["hotel", "rooftop", "supper club", "lounge", "members", "private", "vip", "resort"]
        if prestigeTokens.contains(where: haystack.contains) {
            score += 1.8
        }
        if derivedVenueType(for: item, channel: channel) == .nightlifeVenue {
            score += 1.0
        }
        return score
    }

    private func postalAddressLine(placemark: MKPlacemark) -> String? {
        let parts = [placemark.subThoroughfare, placemark.thoroughfare].compactMap { $0 }
        let joined = parts.joined(separator: " ")
        return joined.isEmpty ? nil : joined
    }
}
