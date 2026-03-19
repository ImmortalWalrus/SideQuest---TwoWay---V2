//
//  SideQuestTests.swift
//  SideQuestTests
//
//  Created by Rork on March 19, 2026.
//

import Foundation
import Testing
@testable import SideQuest

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

}
