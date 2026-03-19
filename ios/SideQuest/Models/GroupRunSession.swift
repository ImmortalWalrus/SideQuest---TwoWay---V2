import Foundation
import CoreLocation

nonisolated struct GroupMember: Identifiable, Codable, Sendable {
    let id: String
    let username: String
    let avatarName: String
    var handshakeVerified: Bool = false
    var isReady: Bool = false
}

nonisolated struct GroupRunSession: Identifiable, Codable, Sendable {
    let id: String
    let questId: String
    let hostUserId: String
    var members: [GroupMember]
    let groupCode: String
    let createdAt: Date
    let maxMembers: Int

    var allHandshaked: Bool {
        members.allSatisfy { $0.handshakeVerified }
    }

    var handshakeBonusMultiplier: Double {
        allHandshaked && members.count > 1 ? 1.05 : 1.0
    }

    var groupBonusMultiplier: Double {
        members.count > 1 ? 1.2 : 1.0
    }

    var totalMultiplier: Double {
        groupBonusMultiplier * handshakeBonusMultiplier
    }

    static let pathSimilarityThreshold: Double = 0.7

    static func calculatePathSimilarity(routeA: [RoutePoint], routeB: [RoutePoint], thresholdMeters: Double = 50) -> Double {
        guard !routeA.isEmpty && !routeB.isEmpty else { return 0 }

        let sampledA = sampleRoute(routeA, targetCount: 50)
        let sampledB = sampleRoute(routeB, targetCount: 50)

        var matchCount = 0
        for pointA in sampledA {
            let locA = CLLocation(latitude: pointA.latitude, longitude: pointA.longitude)
            for pointB in sampledB {
                let locB = CLLocation(latitude: pointB.latitude, longitude: pointB.longitude)
                if locA.distance(from: locB) <= thresholdMeters {
                    matchCount += 1
                    break
                }
            }
        }

        return Double(matchCount) / Double(sampledA.count)
    }

    static func pathsAreSimilarEnough(routeA: [RoutePoint], routeB: [RoutePoint]) -> Bool {
        calculatePathSimilarity(routeA: routeA, routeB: routeB) >= pathSimilarityThreshold
    }

    private static func sampleRoute(_ route: [RoutePoint], targetCount: Int) -> [RoutePoint] {
        guard route.count > targetCount else { return route }
        let step = Double(route.count) / Double(targetCount)
        return (0..<targetCount).map { i in
            route[min(Int(Double(i) * step), route.count - 1)]
        }
    }
}
