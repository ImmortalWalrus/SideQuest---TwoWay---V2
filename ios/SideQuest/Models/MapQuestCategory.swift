import Foundation
import MapKit
import SwiftUI

nonisolated enum MapQuestCategory: String, CaseIterable, Identifiable, Sendable {
    case cafe = "Café"
    case gym = "Gym"
    case park = "Park"
    case library = "Library"
    case trail = "Trail"
    case pool = "Pool"
    case bookstore = "Bookstore"
    case museum = "Museum"
    case beach = "Beach"
    case basketballCourt = "Basketball"
    case yogaStudio = "Yoga"
    case restaurant = "Restaurant"
    case farmersMarket = "Market"
    case dogPark = "Dog Park"
    case skatePark = "Skate Park"
    case rockClimbingGym = "Climbing"
    case bowlingAlley = "Bowling"
    case artGallery = "Gallery"
    case communityCenter = "Community"
    case placeOfWorship = "Worship"
    case volunteerCenter = "Volunteer"
    case danceStudio = "Dance"
    case martialArts = "Martial Arts"
    case tennisCourt = "Tennis"
    case lake = "Lake"
    case bikePath = "Bike Path"

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .cafe: "cup.and.saucer.fill"
        case .gym: "dumbbell.fill"
        case .park: "tree.fill"
        case .library: "books.vertical.fill"
        case .trail: "figure.hiking"
        case .pool: "figure.pool.swim"
        case .bookstore: "book.fill"
        case .museum: "building.columns.fill"
        case .beach: "beach.umbrella.fill"
        case .basketballCourt: "basketball.fill"
        case .yogaStudio: "figure.yoga"
        case .restaurant: "fork.knife"
        case .farmersMarket: "carrot.fill"
        case .dogPark: "dog.fill"
        case .skatePark: "figure.skating"
        case .rockClimbingGym: "figure.climbing"
        case .bowlingAlley: "figure.bowling"
        case .artGallery: "paintpalette.fill"
        case .communityCenter: "person.3.fill"
        case .placeOfWorship: "building.fill"
        case .volunteerCenter: "heart.circle.fill"
        case .danceStudio: "figure.dance"
        case .martialArts: "figure.martial.arts"
        case .tennisCourt: "tennisball.fill"
        case .lake: "water.waves"
        case .bikePath: "bicycle"
        }
    }

    var searchQuery: String {
        switch self {
        case .cafe: "coffee shop cafe"
        case .gym: "gym fitness"
        case .park: "park"
        case .library: "library"
        case .trail: "hiking trail"
        case .pool: "swimming pool"
        case .bookstore: "bookstore book shop"
        case .museum: "museum"
        case .beach: "beach"
        case .basketballCourt: "basketball court"
        case .yogaStudio: "yoga studio"
        case .restaurant: "restaurant"
        case .farmersMarket: "farmers market"
        case .dogPark: "dog park"
        case .skatePark: "skate park"
        case .rockClimbingGym: "rock climbing gym"
        case .bowlingAlley: "bowling alley"
        case .artGallery: "art gallery"
        case .communityCenter: "community center"
        case .placeOfWorship: "church temple mosque synagogue"
        case .volunteerCenter: "food bank shelter volunteer"
        case .danceStudio: "dance studio"
        case .martialArts: "martial arts dojo"
        case .tennisCourt: "tennis court"
        case .lake: "lake"
        case .bikePath: "bike path cycleway"
        }
    }

    var tintColor: String {
        switch self {
        case .cafe: "brown"
        case .gym: "orange"
        case .park: "green"
        case .library: "indigo"
        case .trail: "mint"
        case .pool: "cyan"
        case .bookstore: "purple"
        case .museum: "teal"
        case .beach: "yellow"
        case .basketballCourt: "orange"
        case .yogaStudio: "pink"
        case .restaurant: "red"
        case .farmersMarket: "green"
        case .dogPark: "brown"
        case .skatePark: "gray"
        case .rockClimbingGym: "orange"
        case .bowlingAlley: "blue"
        case .artGallery: "purple"
        case .communityCenter: "teal"
        case .placeOfWorship: "indigo"
        case .volunteerCenter: "pink"
        case .danceStudio: "purple"
        case .martialArts: "red"
        case .tennisCourt: "green"
        case .lake: "blue"
        case .bikePath: "green"
        }
    }

    var checkInRadiusMeters: Double {
        switch self {
        case .cafe: 100
        case .gym: 100
        case .park: 500
        case .library: 100
        case .trail: 500
        case .pool: 100
        case .bookstore: 100
        case .museum: 250
        case .beach: 500
        case .basketballCourt: 150
        case .yogaStudio: 100
        case .restaurant: 100
        case .farmersMarket: 250
        case .dogPark: 300
        case .skatePark: 200
        case .rockClimbingGym: 100
        case .bowlingAlley: 100
        case .artGallery: 150
        case .communityCenter: 150
        case .placeOfWorship: 150
        case .volunteerCenter: 150
        case .danceStudio: 100
        case .martialArts: 100
        case .tennisCourt: 150
        case .lake: 500
        case .bikePath: 300
        }
    }

    var relatedQuestIds: [String] {
        switch self {
        case .cafe: ["pv_cafe1", "ei2"]
        case .gym: ["pv_gym1", "pv_gym2", "wi_m1"]
        case .park: ["pv_park1", "ei8"]
        case .library: ["pv_lib1", "pv_lib2", "pv_lib3", "mi_i1", "mi_im1"]
        case .trail: ["t3", "tr_e1", "tr_m1", "tr_h1", "tr_loop1", "tr_multi1"]
        case .pool: ["pv_pool1", "wi_m3"]
        case .bookstore: ["pv_book1", "pv_book2"]
        case .museum: ["pv_museum1", "pv_museum2"]
        case .beach: ["pv_beach1"]
        case .basketballCourt: ["pv_bball1"]
        case .yogaStudio: ["pv_yoga1"]
        case .restaurant: ["pv_rest1"]
        case .farmersMarket: ["pv_farm1"]
        case .dogPark: ["pv_dog1"]
        case .skatePark: ["pv_skate1"]
        case .rockClimbingGym: ["pv_climb1"]
        case .bowlingAlley: ["pv_bowl1"]
        case .artGallery: ["pv_art1", "pv_art2"]
        case .communityCenter: ["pv_comm1"]
        case .placeOfWorship: ["pv_worship1"]
        case .volunteerCenter: ["pv_vol1", "pv_vol2"]
        case .danceStudio: ["pv_dance1"]
        case .martialArts: ["pv_martial1"]
        case .tennisCourt: ["pv_tennis1"]
        case .lake: ["pv_lake1"]
        case .bikePath: ["bk_e1", "bk_m1", "bk_h1", "bk_commute1"]
        }
    }

    var questXPReward: Int {
        switch self {
        case .cafe: 80
        case .gym: 120
        case .park: 100
        case .library: 90
        case .trail: 150
        case .pool: 110
        case .bookstore: 90
        case .museum: 120
        case .beach: 110
        case .basketballCourt: 120
        case .yogaStudio: 110
        case .restaurant: 80
        case .farmersMarket: 90
        case .dogPark: 80
        case .skatePark: 100
        case .rockClimbingGym: 130
        case .bowlingAlley: 90
        case .artGallery: 100
        case .communityCenter: 90
        case .placeOfWorship: 80
        case .volunteerCenter: 140
        case .danceStudio: 110
        case .martialArts: 120
        case .tennisCourt: 110
        case .lake: 100
        case .bikePath: 120
        }
    }

    var questGoldReward: Int {
        questXPReward / 2
    }

    var questDifficulty: QuestDifficulty {
        switch self {
        case .cafe, .park, .library, .dogPark, .restaurant, .placeOfWorship: .easy
        case .gym, .pool, .bookstore, .museum, .beach, .yogaStudio, .farmersMarket,
             .bowlingAlley, .artGallery, .communityCenter, .danceStudio, .tennisCourt, .lake: .medium
        case .trail, .basketballCourt, .skatePark, .rockClimbingGym, .volunteerCenter, .martialArts, .bikePath: .hard
        }
    }

    var questPath: QuestPath {
        switch self {
        case .cafe, .park, .trail, .library, .bookstore, .museum, .beach,
             .restaurant, .farmersMarket, .dogPark, .artGallery, .communityCenter,
             .placeOfWorship, .volunteerCenter, .lake: .explorer
        case .gym, .pool, .basketballCourt, .skatePark, .rockClimbingGym,
             .bowlingAlley, .tennisCourt, .martialArts, .bikePath: .warrior
        case .yogaStudio, .danceStudio: .mind
        }
    }

    var presenceTimerMinutes: Int {
        switch self {
        case .cafe, .restaurant, .dogPark, .skatePark: 5
        case .bookstore, .museum, .library, .artGallery, .communityCenter,
             .placeOfWorship, .volunteerCenter, .farmersMarket: 5
        case .gym, .pool, .yogaStudio, .basketballCourt, .rockClimbingGym,
             .bowlingAlley, .danceStudio, .martialArts, .tennisCourt: 10
        case .park, .beach, .lake: 5
        case .trail, .bikePath: 30
        }
    }

    var cooldownDays: Int {
        switch self {
        case .restaurant: 60
        default: 30
        }
    }

    var hasNewPlaceQuests: Bool {
        switch self {
        case .restaurant, .park, .bookstore, .museum, .artGallery, .volunteerCenter: true
        default: false
        }
    }

    var mapColor: Color {
        switch self {
        case .cafe: Color(red: 0.6, green: 0.4, blue: 0.2)
        case .gym: .orange
        case .park: .green
        case .library: .indigo
        case .trail: .mint
        case .pool: .cyan
        case .bookstore: .purple
        case .museum: .teal
        case .beach: Color(red: 0.95, green: 0.75, blue: 0.2)
        case .basketballCourt: .orange
        case .yogaStudio: .pink
        case .restaurant: .red
        case .farmersMarket: Color(red: 0.3, green: 0.7, blue: 0.3)
        case .dogPark: Color(red: 0.6, green: 0.4, blue: 0.2)
        case .skatePark: .gray
        case .rockClimbingGym: Color(red: 0.85, green: 0.5, blue: 0.2)
        case .bowlingAlley: .blue
        case .artGallery: .purple
        case .communityCenter: .teal
        case .placeOfWorship: .indigo
        case .volunteerCenter: .pink
        case .danceStudio: Color(red: 0.7, green: 0.3, blue: 0.7)
        case .martialArts: .red
        case .tennisCourt: Color(red: 0.4, green: 0.7, blue: 0.2)
        case .lake: .blue
        case .bikePath: Color(red: 0.2, green: 0.7, blue: 0.4)
        }
    }

    var requiresEvidence: Bool {
        switch self {
        case .rockClimbingGym, .yogaStudio, .farmersMarket, .artGallery,
             .communityCenter, .danceStudio, .martialArts, .bikePath: true
        default: false
        }
    }
}

nonisolated struct MapPOI: Identifiable, Hashable, Sendable {
    let id: String
    let name: String
    let coordinate: CLLocationCoordinate2D
    let category: MapQuestCategory
    let address: String?
    let distance: Double?
    let placeDescription: String?
    let websiteURL: URL?
    let phoneNumber: String?
    let specificType: String?
    let neighborhood: String?
    let locality: String?
    let mapItemIdentifier: MKMapItem.Identifier?

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }

    static func == (lhs: MapPOI, rhs: MapPOI) -> Bool {
        lhs.id == rhs.id
    }
}

nonisolated struct MapQuestInstance: Identifiable, Sendable {
    let id: String
    let poi: MapPOI
    let category: MapQuestCategory
    let startedAt: Date
    var isCheckedIn: Bool
    var checkedInAt: Date?
    var isCompleted: Bool
}
