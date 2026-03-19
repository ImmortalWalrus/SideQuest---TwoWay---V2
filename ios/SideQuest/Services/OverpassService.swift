import Foundation
import CoreLocation

nonisolated struct OverpassElement: Sendable {
    let id: Int64
    let type: String
    let name: String
    let latitude: Double
    let longitude: Double
    let tags: [String: String]
}

nonisolated struct OverpassResponse: Sendable {
    let elements: [OverpassElement]
}

nonisolated enum OverpassCategory: Sendable {
    case hikingTrail
    case bikePath

    var overpassQuery: String {
        switch self {
        case .hikingTrail:
            return """
            (
              way["highway"="path"](around:{{RADIUS}},{{LAT}},{{LON}});
              way["highway"="footway"]["footway"!="crossing"]["footway"!="sidewalk"](around:{{RADIUS}},{{LAT}},{{LON}});
              way["highway"="track"]["tracktype"~"grade[1-3]"](around:{{RADIUS}},{{LAT}},{{LON}});
              relation["route"="hiking"](around:{{RADIUS}},{{LAT}},{{LON}});
              relation["route"="foot"](around:{{RADIUS}},{{LAT}},{{LON}});
            );
            """
        case .bikePath:
            return """
            (
              way["highway"="cycleway"](around:{{RADIUS}},{{LAT}},{{LON}});
              way["highway"="path"]["bicycle"="designated"](around:{{RADIUS}},{{LAT}},{{LON}});
              way["highway"="path"]["bicycle"="yes"](around:{{RADIUS}},{{LAT}},{{LON}});
              relation["route"="bicycle"](around:{{RADIUS}},{{LAT}},{{LON}});
            );
            """
        }
    }
}

@Observable
class OverpassService {
    private let endpoint = "https://overpass-api.de/api/interpreter"
    private var cache: [String: (elements: [OverpassElement], fetchedAt: Date)] = [:]
    private let cacheDuration: TimeInterval = 600

    private(set) var isLoading: Bool = false
    private(set) var errorMessage: String?

    func fetchPOIs(category: OverpassCategory, latitude: Double, longitude: Double, radiusMeters: Double) async -> [OverpassElement] {
        let cacheKey = "\(category)_\(Int(latitude * 100))_\(Int(longitude * 100))_\(Int(radiusMeters))"
        if let cached = cache[cacheKey], Date().timeIntervalSince(cached.fetchedAt) < cacheDuration {
            return cached.elements
        }

        isLoading = true
        errorMessage = nil

        let queryBody = category.overpassQuery
            .replacingOccurrences(of: "{{RADIUS}}", with: String(format: "%.0f", radiusMeters))
            .replacingOccurrences(of: "{{LAT}}", with: String(format: "%.6f", latitude))
            .replacingOccurrences(of: "{{LON}}", with: String(format: "%.6f", longitude))

        let fullQuery = "[out:json][timeout:15];\(queryBody)out center tags;"

        guard let url = URL(string: endpoint) else {
            isLoading = false
            errorMessage = "Invalid endpoint"
            return []
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.httpBody = "data=\(fullQuery)".addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed).flatMap { $0.data(using: .utf8) }
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 20

        do {
            let (data, response) = try await URLSession.shared.data(for: request)

            guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
                isLoading = false
                errorMessage = "Overpass API unavailable"
                return []
            }

            let elements = parseResponse(data: data, userLat: latitude, userLon: longitude, radius: radiusMeters)
            cache[cacheKey] = (elements: elements, fetchedAt: Date())
            isLoading = false
            return elements
        } catch {
            isLoading = false
            errorMessage = "Network error"
            return []
        }
    }

    private func parseResponse(data: Data, userLat: Double, userLon: Double, radius: Double) -> [OverpassElement] {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let rawElements = json["elements"] as? [[String: Any]] else {
            return []
        }

        let userLocation = CLLocation(latitude: userLat, longitude: userLon)
        var seen = Set<String>()
        var results: [OverpassElement] = []

        for element in rawElements {
            guard let tags = element["tags"] as? [String: String] else { continue }

            let name = tags["name"] ?? tags["description"] ?? tags["ref"] ?? ""
            guard !name.isEmpty else { continue }

            var lat: Double?
            var lon: Double?

            if let center = element["center"] as? [String: Any] {
                lat = center["lat"] as? Double
                lon = center["lon"] as? Double
            } else {
                lat = element["lat"] as? Double
                lon = element["lon"] as? Double
            }

            guard let finalLat = lat, let finalLon = lon else { continue }

            let elementLoc = CLLocation(latitude: finalLat, longitude: finalLon)
            let dist = userLocation.distance(from: elementLoc)
            guard dist <= radius else { continue }

            let dedupKey = name.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
            guard !seen.contains(dedupKey) else { continue }
            seen.insert(dedupKey)

            let id = element["id"] as? Int64 ?? Int64(results.count)
            let type = element["type"] as? String ?? "way"

            results.append(OverpassElement(
                id: id,
                type: type,
                name: name,
                latitude: finalLat,
                longitude: finalLon,
                tags: tags
            ))
        }

        return results.sorted { a, b in
            let distA = userLocation.distance(from: CLLocation(latitude: a.latitude, longitude: a.longitude))
            let distB = userLocation.distance(from: CLLocation(latitude: b.latitude, longitude: b.longitude))
            return distA < distB
        }
    }

    static func specificType(for element: OverpassElement, category: OverpassCategory) -> String {
        let tags = element.tags
        let name = element.name.lowercased()

        switch category {
        case .hikingTrail:
            if let sac = tags["sac_scale"] {
                switch sac {
                case "hiking": return "Easy Trail"
                case "mountain_hiking": return "Mountain Trail"
                case "demanding_mountain_hiking": return "Challenging Mountain"
                case "alpine_hiking": return "Alpine Trail"
                case "demanding_alpine_hiking": return "Expert Alpine"
                default: break
                }
            }
            if tags["route"] == "hiking" { return "Hiking Route" }
            if name.contains("mountain") || name.contains("summit") || name.contains("peak") || name.contains("ridge") { return "Mountain Trail" }
            if name.contains("waterfall") || name.contains("falls") { return "Waterfall Trail" }
            if name.contains("river") || name.contains("creek") || name.contains("stream") { return "Riverside Trail" }
            if name.contains("loop") { return "Loop Trail" }
            if name.contains("coastal") || name.contains("shore") || name.contains("cliff") || name.contains("bluff") { return "Coastal Trail" }
            if name.contains("canyon") || name.contains("gorge") { return "Canyon Trail" }
            if name.contains("forest") || name.contains("woods") || name.contains("grove") { return "Forest Trail" }
            if name.contains("lake") || name.contains("pond") { return "Lakeside Trail" }
            if name.contains("meadow") || name.contains("prairie") { return "Meadow Trail" }
            if name.contains("nature") || name.contains("preserve") || name.contains("reserve") { return "Nature Trail" }
            if tags["highway"] == "footway" { return "Footpath" }
            if tags["highway"] == "track" { return "Dirt Track" }
            return "Hiking Trail"

        case .bikePath:
            if tags["route"] == "bicycle" { return "Bike Route" }
            if name.contains("mountain") || name.contains("mtb") { return "MTB Trail" }
            if name.contains("greenway") || name.contains("rail trail") || name.contains("rail-trail") { return "Rail Trail" }
            if name.contains("river") || name.contains("creek") || name.contains("waterfront") { return "Riverside Path" }
            if name.contains("loop") { return "Loop Route" }
            if name.contains("commuter") || name.contains("protected") { return "Protected Lane" }
            if tags["bicycle"] == "designated" { return "Dedicated Bikeway" }
            if tags["highway"] == "cycleway" {
                if tags["segregated"] == "yes" { return "Segregated Cycleway" }
                return "Cycleway"
            }
            if tags["surface"] == "unpaved" || tags["surface"] == "gravel" || tags["surface"] == "dirt" { return "Gravel Path" }
            return "Bike Path"
        }
    }

    static func description(for element: OverpassElement, category: OverpassCategory) -> String {
        let tags = element.tags
        let name = element.name
        var parts: [String] = []

        switch category {
        case .hikingTrail:
            let type = specificType(for: element, category: category)
            parts.append("\(name) — \(type.lowercased())")

            if let surface = tags["surface"] {
                let surfaceDesc = surfaceDescription(surface)
                parts.append(surfaceDesc)
            }

            if let sac = tags["sac_scale"] {
                parts.append("Difficulty: \(sacScaleDescription(sac))")
            }

            if let distance = tags["distance"] {
                parts.append("\(distance) km")
            } else if let length = tags["length"] {
                parts.append("\(length) long")
            }

            if let ele = tags["ele"] {
                parts.append("Elevation: \(ele)m")
            }

            if tags["dog"] == "yes" || tags["dog"] == "leashed" {
                parts.append("Dogs allowed")
            }

            if let access = tags["access"], access == "private" {
                parts.append("Private access — check before visiting")
            }

        case .bikePath:
            let type = specificType(for: element, category: category)
            parts.append("\(name) — \(type.lowercased())")

            if let surface = tags["surface"] {
                let surfaceDesc = surfaceDescription(surface)
                parts.append(surfaceDesc)
            }

            if let width = tags["width"] {
                parts.append("\(width)m wide")
            }

            if let lit = tags["lit"], lit == "yes" {
                parts.append("Lit at night")
            }

            if let distance = tags["distance"] {
                parts.append("\(distance) km")
            }

            if tags["oneway"] == "yes" {
                parts.append("One-way")
            }
        }

        return parts.joined(separator: ". ") + "."
    }

    private static func surfaceDescription(_ surface: String) -> String {
        switch surface {
        case "asphalt", "paved": return "Paved surface"
        case "gravel", "fine_gravel": return "Gravel surface"
        case "dirt", "earth", "ground": return "Dirt surface"
        case "grass": return "Grass surface"
        case "sand": return "Sandy surface"
        case "concrete": return "Concrete surface"
        case "compacted": return "Compacted surface"
        case "wood": return "Wooden boardwalk"
        case "cobblestone", "sett": return "Cobblestone surface"
        default: return "\(surface.replacingOccurrences(of: "_", with: " ").capitalized) surface"
        }
    }

    private static func sacScaleDescription(_ sac: String) -> String {
        switch sac {
        case "hiking": return "Easy hiking, well-marked paths"
        case "mountain_hiking": return "Mountain hiking, some steep sections"
        case "demanding_mountain_hiking": return "Demanding, exposed terrain possible"
        case "alpine_hiking": return "Alpine, scrambling required"
        case "demanding_alpine_hiking": return "Expert alpine, climbing sections"
        case "difficult_alpine_hiking": return "Extreme alpine, technical climbing"
        default: return sac.replacingOccurrences(of: "_", with: " ").capitalized
        }
    }
}
