//
//  SideQuestTests.swift
//  SideQuestTests
//
//  Created by Rork on March 19, 2026.
//

import Foundation
import Testing
@testable import SideQuest

@Suite(.serialized)
struct SideQuestTests {

    @Test func parseDoubleRejectsBooleanGoogleRatings() {
        #expect(ExternalEventSupport.parseDouble(true) == nil)
        #expect(ExternalEventSupport.parseDouble(NSNumber(booleanLiteral: true)) == nil)
        #expect(ExternalEventSupport.parseDouble(NSNumber(value: 4.4)) == 4.4)
    }

    @Test func sanitizedGoogleReviewIdentityRemovesBooleanPoisonedRating() throws {
        let rawPayload = ExternalEventSupport.jsonString([
            "google_places_rating": true,
            "google_places_url": "https://www.google.com/search?tbm=map&q=Whisky%20A%20Go%20Go"
        ])

        let event = ExternalEvent(
            id: "event-1",
            source: .ticketmaster,
            sourceEventID: "tm-1",
            sourceParentID: nil,
            sourceURL: nil,
            mergedSources: [.ticketmaster],
            title: "Test Show",
            shortDescription: nil,
            fullDescription: nil,
            category: nil,
            subcategory: nil,
            eventType: .concert,
            startAtUTC: nil,
            endAtUTC: nil,
            startLocal: nil,
            endLocal: nil,
            timezone: nil,
            salesStartAtUTC: nil,
            salesEndAtUTC: nil,
            venueName: "Whisky A Go Go",
            venueID: nil,
            addressLine1: "8901 W Sunset Boulevard",
            addressLine2: nil,
            city: "West Hollywood",
            state: "CA",
            postalCode: "90069",
            country: "US",
            latitude: nil,
            longitude: nil,
            imageURL: nil,
            fallbackThumbnailAsset: "generic_live_event",
            status: .scheduled,
            availabilityStatus: .available,
            urgencyBadge: nil,
            socialProofCount: nil,
            socialProofLabel: nil,
            venuePopularityCount: nil,
            venueRating: 1.0,
            ticketProviderCount: nil,
            priceMin: nil,
            priceMax: nil,
            currency: nil,
            organizerName: nil,
            organizerEventCount: nil,
            organizerVerified: nil,
            tags: [],
            distanceValue: nil,
            distanceUnit: nil,
            raceType: nil,
            registrationURL: nil,
            ticketURL: nil,
            rawSourcePayload: rawPayload
        )

        let sanitized = ExternalEventSupport.sanitizedGoogleReviewIdentity(event)
        #expect(sanitized.venueRating == nil)

        let payloadData = try #require(sanitized.rawSourcePayload.data(using: .utf8))
        let payloadObject = try #require(JSONSerialization.jsonObject(with: payloadData) as? [String: Any])
        #expect(payloadObject["google_places_rating"] == nil)
        #expect(payloadObject["google_places_url"] as? String == "https://www.google.com/search?tbm=map&q=Whisky%20A%20Go%20Go")
    }

    @Test func supabaseCacheLoadRepairsFreshPoisonedRowsFromHealthierExactCandidates() async throws {
        let searchLocation = ExternalEventSearchLocation(
            city: "West Hollywood",
            state: "CA",
            postalCode: "90069",
            countryCode: "US",
            latitude: 34.0901,
            longitude: -118.3852,
            displayName: "West Hollywood, CA"
        )

        let poisonedCrypto = Self.makeEvent(
            id: "crypto-poisoned",
            title: "Los Angeles Kings vs. Philadelphia Flyers",
            venueName: "Crypto.com Arena",
            addressLine1: "1111 S. Figueroa St.",
            city: "Los Angeles",
            state: "CA",
            postalCode: "90017",
            venueRating: 1.0,
            rawSourcePayload: ExternalEventSupport.jsonString([
                "google_places_rating": true,
                "google_places_url": "https://www.google.com/search?tbm=map&q=Crypto.com%20Arena"
            ])
        )

        let healthyCrypto = Self.makeEvent(
            id: "crypto-healthy",
            title: "Los Angeles Kings vs. Philadelphia Flyers",
            venueName: "Crypto.com Arena",
            addressLine1: "1111 S. Figueroa St.",
            city: "Los Angeles",
            state: "CA",
            postalCode: "90017",
            venueRating: 4.7,
            venuePopularityCount: 54,
            rawSourcePayload: ExternalEventSupport.jsonString([
                "google_places_rating": 4.7,
                "google_places_user_rating_count": 54,
                "google_places_url": "https://www.google.com/maps/search/Crypto.com%20Arena"
            ])
        )

        let exactRows = try [
            Self.makeSnapshotRow(
                snapshot: Self.makeSnapshot(
                    fetchedAt: Self.isoDate("2026-03-19T02:38:49Z"),
                    searchLocation: searchLocation,
                    events: [poisonedCrypto]
                ),
                fetchedAt: Self.isoDate("2026-03-19T02:38:49Z"),
                quality: .full
            ),
            Self.makeSnapshotRow(
                snapshot: Self.makeSnapshot(
                    fetchedAt: Self.isoDate("2026-03-17T23:09:39Z"),
                    searchLocation: searchLocation,
                    events: [healthyCrypto]
                ),
                fetchedAt: Self.isoDate("2026-03-17T23:09:39Z"),
                quality: .full
            )
        ]

        let service = Self.makeService { request in
            let query = request.url?.query ?? ""
            if query.contains("cache_key=") {
                return try Self.jsonResponse(exactRows, url: request.url!)
            }
            return try Self.jsonResponse([], url: request.url!)
        }

        let loaded = try #require(await service.load(searchLocation: searchLocation, intent: ExternalDiscoveryIntent.nearbyWorthIt))
        let crypto = try #require(loaded.mergedEvents.first)
        #expect(crypto.venueRating == 4.7)
        #expect(crypto.venuePopularityCount == 54)
    }

    @Test func supabaseCacheLoadRepairsBlankVenueReviewsFromNearbyMetroDonorRows() async throws {
        let losAngeles = ExternalEventSearchLocation(
            city: "Los Angeles",
            state: "CA",
            postalCode: "90012",
            countryCode: "US",
            latitude: 34.0522,
            longitude: -118.2437,
            displayName: "Los Angeles, CA"
        )
        let westHollywood = ExternalEventSearchLocation(
            city: "West Hollywood",
            state: "CA",
            postalCode: "90069",
            countryCode: "US",
            latitude: 34.0901,
            longitude: -118.3852,
            displayName: "West Hollywood, CA"
        )

        let blankPauley = Self.makeEvent(
            id: "pauley-blank",
            title: "NCAA Womens Tournament: 1st Round",
            venueName: "Pauley Pavilion-UCLA",
            addressLine1: "UCLA Campus",
            city: "Los Angeles",
            state: "CA",
            postalCode: "90024",
            venueRating: nil,
            rawSourcePayload: ExternalEventSupport.jsonString([
                "venue": [
                    "name": "Pauley Pavilion-UCLA"
                ]
            ])
        )

        let donorPauley = Self.makeEvent(
            id: "pauley-donor",
            title: "NCAA Womens Tournament: 1st Round",
            venueName: "Pauley Pavilion-UCLA",
            addressLine1: "301 Westwood Plaza",
            city: "Los Angeles",
            state: "CA",
            postalCode: "90024",
            venueRating: 4.8,
            venuePopularityCount: 2,
            rawSourcePayload: ExternalEventSupport.jsonString([
                "google_places_rating": 4.8,
                "google_places_user_rating_count": 2,
                "google_places_url": "https://www.google.com/maps/search/Pauley%20Pavilion-UCLA"
            ])
        )

        let exactRows = try [
            Self.makeSnapshotRow(
                snapshot: Self.makeSnapshot(
                    fetchedAt: Self.isoDate("2026-03-18T19:51:10Z"),
                    searchLocation: losAngeles,
                    events: [blankPauley]
                ),
                fetchedAt: Self.isoDate("2026-03-18T19:51:10Z"),
                quality: .full
            )
        ]

        let donorRows = try [
            Self.makeSnapshotRow(
                snapshot: Self.makeSnapshot(
                    fetchedAt: Self.isoDate("2026-03-17T23:09:39Z"),
                    searchLocation: westHollywood,
                    events: [donorPauley]
                ),
                fetchedAt: Self.isoDate("2026-03-17T23:09:39Z"),
                quality: .full
            )
        ]

        let service = Self.makeService { request in
            let query = request.url?.query ?? ""
            if query.contains("cache_key=") {
                return try Self.jsonResponse(exactRows, url: request.url!)
            }
            return try Self.jsonResponse(donorRows, url: request.url!)
        }

        let loaded = try #require(await service.load(searchLocation: losAngeles, intent: ExternalDiscoveryIntent.nearbyWorthIt))
        let pauley = try #require(loaded.mergedEvents.first)
        #expect(pauley.venueRating == 4.8)
        #expect(pauley.venuePopularityCount == 2)
    }

    private static func makeService(
        handler: @escaping (URLRequest) throws -> (HTTPURLResponse, Data)
    ) -> SupabaseEventFeedCacheService {
        MockURLProtocol.requestHandler = handler
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [MockURLProtocol.self]
        let session = URLSession(configuration: configuration)
        return SupabaseEventFeedCacheService(
            configuration: SupabaseEventFeedCacheConfiguration(
                projectURL: URL(string: "https://example.supabase.co"),
                anonKey: "test-anon-key"
            ),
            session: session
        )
    }

    private static func makeSnapshot(
        fetchedAt: Date,
        searchLocation: ExternalEventSearchLocation,
        events: [ExternalEvent]
    ) -> ExternalLocationDiscoverySnapshot {
        let query = ExternalEventQuery(
            countryCode: searchLocation.countryCode,
            city: searchLocation.city,
            state: searchLocation.state,
            postalCode: searchLocation.postalCode,
            latitude: searchLocation.latitude,
            longitude: searchLocation.longitude,
            radiusMiles: 12,
            keyword: nil,
            pageSize: 12,
            page: 0,
            sourcePageDepth: 1,
            includePast: false,
            hyperlocalRadiusMiles: 2,
            nightlifeRadiusMiles: 6,
            headlineRadiusMiles: 12,
            adaptiveRadiusExpansion: true,
            discoveryIntent: .nearbyWorthIt
        )
        let sourceResult = ExternalEventSourceResult(
            source: .ticketmaster,
            usedCache: false,
            fetchedAt: fetchedAt,
            endpoints: [],
            note: nil,
            nextCursor: nil,
            events: events
        )
        let eventSnapshot = ExternalEventIngestionSnapshot(
            fetchedAt: fetchedAt,
            query: query,
            sourceResults: [sourceResult],
            mergedEvents: events,
            dedupeGroups: []
        )
        return ExternalLocationDiscoverySnapshot(
            fetchedAt: fetchedAt,
            searchLocation: searchLocation,
            appliedProfiles: [],
            venueSnapshot: nil,
            eventSnapshot: eventSnapshot,
            mergedEvents: events,
            notes: []
        )
    }

    private static func makeSnapshotRow(
        snapshot: ExternalLocationDiscoverySnapshot,
        fetchedAt: Date,
        quality: ExternalDiscoveryCacheQuality
    ) throws -> [String: Any] {
        let data = try JSONEncoder().encode(snapshot)
        let object = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
        var row: [String: Any] = [
            "snapshot": object,
            "fetched_at": ExternalEventSupport.iso8601NoFractionalSeconds.string(from: fetchedAt),
            "quality": quality.rawValue,
            "display_name": snapshot.searchLocation.displayName
        ]
        if let city = snapshot.searchLocation.city {
            row["city"] = city
        }
        if let state = snapshot.searchLocation.state {
            row["state"] = state
        }
        if let latitude = snapshot.searchLocation.latitude {
            row["latitude"] = latitude
        }
        if let longitude = snapshot.searchLocation.longitude {
            row["longitude"] = longitude
        }
        return row
    }

    private static func makeEvent(
        id: String,
        title: String,
        venueName: String,
        addressLine1: String?,
        city: String?,
        state: String?,
        postalCode: String?,
        venueRating: Double?,
        venuePopularityCount: Int? = nil,
        rawSourcePayload: String
    ) -> ExternalEvent {
        ExternalEvent(
            id: id,
            source: .ticketmaster,
            sourceEventID: id,
            sourceParentID: nil,
            sourceURL: nil,
            mergedSources: [.ticketmaster],
            title: title,
            shortDescription: nil,
            fullDescription: nil,
            category: nil,
            subcategory: nil,
            eventType: .sportsEvent,
            startAtUTC: nil,
            endAtUTC: nil,
            startLocal: nil,
            endLocal: nil,
            timezone: nil,
            salesStartAtUTC: nil,
            salesEndAtUTC: nil,
            venueName: venueName,
            venueID: nil,
            addressLine1: addressLine1,
            addressLine2: nil,
            city: city,
            state: state,
            postalCode: postalCode,
            country: "US",
            latitude: nil,
            longitude: nil,
            imageURL: nil,
            fallbackThumbnailAsset: "generic_live_event",
            status: .scheduled,
            availabilityStatus: .available,
            urgencyBadge: nil,
            socialProofCount: nil,
            socialProofLabel: nil,
            venuePopularityCount: venuePopularityCount,
            venueRating: venueRating,
            ticketProviderCount: nil,
            priceMin: nil,
            priceMax: nil,
            currency: nil,
            organizerName: nil,
            organizerEventCount: nil,
            organizerVerified: nil,
            tags: [],
            distanceValue: nil,
            distanceUnit: nil,
            raceType: nil,
            registrationURL: nil,
            ticketURL: nil,
            rawSourcePayload: rawSourcePayload
        )
    }

    private static func isoDate(_ value: String) -> Date {
        ExternalEventSupport.iso8601NoFractionalSeconds.date(from: value)!
    }

    private static func jsonResponse(
        _ object: Any,
        url: URL
    ) throws -> (HTTPURLResponse, Data) {
        let data = try JSONSerialization.data(withJSONObject: object)
        let response = HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil)!
        return (response, data)
    }

}

private final class MockURLProtocol: URLProtocol, @unchecked Sendable {
    static var requestHandler: ((URLRequest) throws -> (HTTPURLResponse, Data))?

    override class func canInit(with request: URLRequest) -> Bool {
        true
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        request
    }

    override func startLoading() {
        guard let handler = Self.requestHandler else {
            client?.urlProtocol(self, didFailWithError: URLError(.badServerResponse))
            return
        }

        do {
            let (response, data) = try handler(request)
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }

    override func stopLoading() {}
}
