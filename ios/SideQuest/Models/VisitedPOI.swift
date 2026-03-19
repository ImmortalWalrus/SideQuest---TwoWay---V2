import Foundation
import CoreLocation

nonisolated struct VisitedPOI: Identifiable, Codable, Hashable, Sendable {
    let id: String
    let name: String
    let latitude: Double
    let longitude: Double
    let category: String
    let visitedAt: Date
    let questTitle: String

    var coordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }

    var mapCategory: MapQuestCategory? {
        MapQuestCategory.allCases.first { $0.rawValue == category }
    }
}
