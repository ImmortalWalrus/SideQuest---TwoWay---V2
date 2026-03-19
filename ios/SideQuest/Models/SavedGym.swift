import Foundation
import CoreLocation

nonisolated struct SavedGym: Codable, Sendable, Equatable {
    let name: String
    let latitude: Double
    let longitude: Double
    let savedAt: Date

    var coordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }
}
