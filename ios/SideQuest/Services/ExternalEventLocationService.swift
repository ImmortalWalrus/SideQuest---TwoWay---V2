import CoreLocation
import Foundation

nonisolated struct ExternalEventSearchLocation: Codable, Hashable, Sendable {
    var city: String?
    var state: String?
    var postalCode: String?
    var countryCode: String
    var latitude: Double?
    var longitude: Double?
    var displayName: String

    var coordinate: CLLocationCoordinate2D? {
        guard let latitude, let longitude else { return nil }
        return CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }
}

enum ExternalEventLocationService {
    private static let previewFallbacks: [String: ExternalEventSearchLocation] = [
        "90069": ExternalEventSearchLocation(
            city: "West Hollywood",
            state: "CA",
            postalCode: "90069",
            countryCode: "US",
            latitude: 34.0901,
            longitude: -118.3852,
            displayName: "West Hollywood, CA"
        ),
        "10019": ExternalEventSearchLocation(
            city: "New York",
            state: "NY",
            postalCode: "10019",
            countryCode: "US",
            latitude: 40.7656,
            longitude: -73.9852,
            displayName: "New York, NY"
        ),
        "33139": ExternalEventSearchLocation(
            city: "Miami Beach",
            state: "FL",
            postalCode: "33139",
            countryCode: "US",
            latitude: 25.7826,
            longitude: -80.1341,
            displayName: "Miami Beach, FL"
        ),
        "60611": ExternalEventSearchLocation(
            city: "Chicago",
            state: "IL",
            postalCode: "60611",
            countryCode: "US",
            latitude: 41.8947,
            longitude: -87.6205,
            displayName: "Chicago, IL"
        ),
        "78701": ExternalEventSearchLocation(
            city: "Austin",
            state: "TX",
            postalCode: "78701",
            countryCode: "US",
            latitude: 30.2711,
            longitude: -97.7437,
            displayName: "Austin, TX"
        ),
        "75201": ExternalEventSearchLocation(
            city: "Dallas",
            state: "TX",
            postalCode: "75201",
            countryCode: "US",
            latitude: 32.7877,
            longitude: -96.7996,
            displayName: "Dallas, TX"
        ),
        "37203": ExternalEventSearchLocation(
            city: "Nashville",
            state: "TN",
            postalCode: "37203",
            countryCode: "US",
            latitude: 36.1532,
            longitude: -86.7850,
            displayName: "Nashville, TN"
        ),
        "89109": ExternalEventSearchLocation(
            city: "Las Vegas",
            state: "NV",
            postalCode: "89109",
            countryCode: "US",
            latitude: 36.1229,
            longitude: -115.1703,
            displayName: "Las Vegas, NV"
        ),
        "30308": ExternalEventSearchLocation(
            city: "Atlanta",
            state: "GA",
            postalCode: "30308",
            countryCode: "US",
            latitude: 33.7712,
            longitude: -84.3877,
            displayName: "Atlanta, GA"
        ),
        "28207": ExternalEventSearchLocation(
            city: "Charlotte",
            state: "NC",
            postalCode: "28207",
            countryCode: "US",
            latitude: 35.2013,
            longitude: -80.8249,
            displayName: "Charlotte, NC"
        ),
        "77002": ExternalEventSearchLocation(
            city: "Houston",
            state: "TX",
            postalCode: "77002",
            countryCode: "US",
            latitude: 29.7569,
            longitude: -95.3625,
            displayName: "Houston, TX"
        ),
        "98101": ExternalEventSearchLocation(
            city: "Seattle",
            state: "WA",
            postalCode: "98101",
            countryCode: "US",
            latitude: 47.6101,
            longitude: -122.3365,
            displayName: "Seattle, WA"
        ),
        "85004": ExternalEventSearchLocation(
            city: "Phoenix",
            state: "AZ",
            postalCode: "85004",
            countryCode: "US",
            latitude: 33.4518,
            longitude: -112.0682,
            displayName: "Phoenix, AZ"
        ),
        "80202": ExternalEventSearchLocation(
            city: "Denver",
            state: "CO",
            postalCode: "80202",
            countryCode: "US",
            latitude: 39.7528,
            longitude: -104.9992,
            displayName: "Denver, CO"
        ),
        "02108": ExternalEventSearchLocation(
            city: "Boston",
            state: "MA",
            postalCode: "02108",
            countryCode: "US",
            latitude: 42.3572,
            longitude: -71.0637,
            displayName: "Boston, MA"
        ),
        "19103": ExternalEventSearchLocation(
            city: "Philadelphia",
            state: "PA",
            postalCode: "19103",
            countryCode: "US",
            latitude: 39.9527,
            longitude: -75.1748,
            displayName: "Philadelphia, PA"
        ),
        "94103": ExternalEventSearchLocation(
            city: "San Francisco",
            state: "CA",
            postalCode: "94103",
            countryCode: "US",
            latitude: 37.7726,
            longitude: -122.4091,
            displayName: "San Francisco, CA"
        )
    ]
    @MainActor private static var resolvedPostalCodeCache: [String: ExternalEventSearchLocation] = [:]

    static var usesSimulatorPreviewLocation: Bool {
        #if targetEnvironment(simulator)
        true
        #else
        false
        #endif
    }

    static func fallbackSearchLocation(for postalCode: String = "90069") -> ExternalEventSearchLocation {
        if let fallback = previewFallbacks[postalCode] {
            return fallback
        }

        return ExternalEventSearchLocation(
            city: "Los Angeles",
            state: "CA",
            postalCode: postalCode,
            countryCode: "US",
            latitude: 34.0522,
            longitude: -118.2437,
            displayName: "Los Angeles, CA"
        )
    }

    @MainActor
    static func resolveSearchLocation(
        userCoordinate: CLLocationCoordinate2D?,
        savedCoordinate: CLLocationCoordinate2D?,
        fallbackPostalCode: String = "90069",
        spoofPostalCode: String? = nil
    ) async -> ExternalEventSearchLocation {
        if let spoofPostalCode = normalizedPostalCode(spoofPostalCode),
           let spoofed = await resolvedSearchLocation(for: spoofPostalCode) {
            return spoofed
        }

        if usesSimulatorPreviewLocation {
            return await resolvedSearchLocation(for: fallbackPostalCode)
                ?? fallbackSearchLocation(for: fallbackPostalCode)
        }

        if let userCoordinate,
           let resolved = await reverseGeocodedLocation(for: userCoordinate) {
            return resolved
        }

        if let savedCoordinate,
           let resolved = await reverseGeocodedLocation(for: savedCoordinate) {
            return resolved
        }

        return await resolvedSearchLocation(for: fallbackPostalCode)
            ?? fallbackSearchLocation(for: fallbackPostalCode)
    }

    @MainActor
    private static func resolvedSearchLocation(for postalCode: String) async -> ExternalEventSearchLocation? {
        let normalizedPostalCode = normalizedPostalCode(postalCode) ?? postalCode
        if let cached = resolvedPostalCodeCache[normalizedPostalCode] {
            return cached
        }
        if let preview = previewFallbacks[normalizedPostalCode] {
            resolvedPostalCodeCache[normalizedPostalCode] = preview
            return preview
        }
        guard let geocoded = await geocodedLocation(for: normalizedPostalCode) else {
            return nil
        }
        resolvedPostalCodeCache[normalizedPostalCode] = geocoded
        return geocoded
    }

    @MainActor
    private static func reverseGeocodedLocation(for coordinate: CLLocationCoordinate2D) async -> ExternalEventSearchLocation? {
        let geocoder = CLGeocoder()
        do {
            let placemarks = try await geocoder.reverseGeocodeLocation(
                CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude)
            )
            guard let placemark = placemarks.first else { return nil }

            let city = placemark.locality ?? placemark.subLocality ?? placemark.name
            let state = placemark.administrativeArea
            let postalCode = placemark.postalCode
            let countryCode = placemark.isoCountryCode ?? "US"
            let displayName = [city, state].compactMap { value in
                guard let value, !value.isEmpty else { return nil }
                return value
            }.joined(separator: ", ")

            return ExternalEventSearchLocation(
                city: city,
                state: state,
                postalCode: postalCode,
                countryCode: countryCode,
                latitude: coordinate.latitude,
                longitude: coordinate.longitude,
                displayName: displayName.isEmpty ? (postalCode ?? "Nearby") : displayName
            )
        } catch {
            return nil
        }
    }

    @MainActor
    private static func geocodedLocation(for postalCode: String) async -> ExternalEventSearchLocation? {
        let geocoder = CLGeocoder()
        do {
            let placemarks = try await geocoder.geocodeAddressString("\(postalCode), USA")
            guard let placemark = placemarks.first,
                  let location = placemark.location
            else {
                return nil
            }

            let city = placemark.locality ?? placemark.subLocality ?? placemark.name
            let state = placemark.administrativeArea
            let resolvedPostalCode = placemark.postalCode ?? postalCode
            let countryCode = placemark.isoCountryCode ?? "US"
            let displayName = [city, state].compactMap { value in
                guard let value, !value.isEmpty else { return nil }
                return value
            }.joined(separator: ", ")

            return ExternalEventSearchLocation(
                city: city,
                state: state,
                postalCode: resolvedPostalCode,
                countryCode: countryCode,
                latitude: location.coordinate.latitude,
                longitude: location.coordinate.longitude,
                displayName: displayName.isEmpty ? resolvedPostalCode : displayName
            )
        } catch {
            return nil
        }
    }

    private static func normalizedPostalCode(_ postalCode: String?) -> String? {
        guard let postalCode else { return nil }
        let digits = postalCode
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .components(separatedBy: CharacterSet.decimalDigits.inverted)
            .joined()
        guard !digits.isEmpty else { return nil }
        return String(digits.prefix(5))
    }
}
