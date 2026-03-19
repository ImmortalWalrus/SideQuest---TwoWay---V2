import Foundation
import MapKit

nonisolated struct SidequestCoordinate: Sendable {
    let longitude: Double
    let latitude: Double
}

nonisolated struct SidequestOffset: Sendable {
    let xMeters: Double
    let yMeters: Double
}

nonisolated struct SidequestScenePlace: Sendable {
    let id: String
    let title: String
    let category: String
    let mapLabel: String
    let coordinates: SidequestCoordinate
    let neighborhood: String
    let destinationType: String
    let rewardFlavor: String
    let questHook: String
    let modelKey: String?
}

nonisolated struct SidequestSceneQuest: Sendable {
    let id: String
    let title: String
    let linkedPlaceId: String
    let categoryTag: String
    let rewardLabel: String
    let summary: String
    let offsetMeters: SidequestOffset
}

nonisolated struct SidequestSceneData: Sendable {
    let places: [SidequestScenePlace]
    let quests: [SidequestSceneQuest]
    let playerCoordinates: SidequestCoordinate?
    let initialSelectedPlaceId: String?
}

struct SceneDataBridge {

    private static let modelKeyMap: [MapQuestCategory: String] = [
        .cafe: "cozy-corner-cafe",
    ]

    static func buildSceneData(
        encounters: [ExploreEncounter],
        userCoordinate: CLLocationCoordinate2D?,
        selectedEncounterID: String?
    ) -> SidequestSceneData {
        var places: [SidequestScenePlace] = []
        var quests: [SidequestSceneQuest] = []

        for encounter in encounters {
            let poi = encounter.poi
            let category = poi.category

            let place = SidequestScenePlace(
                id: poi.id,
                title: poi.name,
                category: category.rawValue.lowercased(),
                mapLabel: category.rawValue,
                coordinates: SidequestCoordinate(
                    longitude: poi.coordinate.longitude,
                    latitude: poi.coordinate.latitude
                ),
                neighborhood: poi.neighborhood ?? poi.locality ?? "",
                destinationType: category.questPath.rawValue,
                rewardFlavor: "\(encounter.xp) XP · \(encounter.gold) Gold",
                questHook: encounter.flavorText,
                modelKey: nil
            )
            places.append(place)

            if let quest = encounter.quest {
                let sceneQuest = SidequestSceneQuest(
                    id: quest.id,
                    title: quest.title,
                    linkedPlaceId: poi.id,
                    categoryTag: "\(category.rawValue) Quest",
                    rewardLabel: "\(quest.xpReward) XP",
                    summary: quest.description,
                    offsetMeters: SidequestOffset(xMeters: 0, yMeters: 0)
                )
                quests.append(sceneQuest)
            }
        }

        let playerCoords: SidequestCoordinate? = userCoordinate.map {
            SidequestCoordinate(longitude: $0.longitude, latitude: $0.latitude)
        }

        let selectedPlaceId: String? = {
            guard let selectedEncounterID else { return nil }
            return encounters.first { $0.id == selectedEncounterID }?.poi.id
        }()

        return SidequestSceneData(
            places: places,
            quests: quests,
            playerCoordinates: playerCoords,
            initialSelectedPlaceId: selectedPlaceId
        )
    }
}
