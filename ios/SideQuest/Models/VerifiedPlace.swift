import SwiftUI

nonisolated enum VerifiedPlaceType: String, CaseIterable, Codable, Sendable {
    case gym = "Gym"
    case pool = "Swimming Pool"
    case library = "Library"
    case park = "Park"
    case track = "Track / Field"
    case coffeeShop = "Coffee Shop"
    case bookstore = "Bookstore"
    case museum = "Museum"
    case beach = "Beach"
    case basketballCourt = "Basketball Court"
    case yogaStudio = "Yoga Studio"
    case restaurant = "Restaurant"
    case farmersMarket = "Farmers Market"
    case dogPark = "Dog Park"
    case skatePark = "Skate Park"
    case rockClimbingGym = "Rock Climbing Gym"
    case bowlingAlley = "Bowling Alley"
    case artGallery = "Art Gallery"
    case communityCenter = "Community Center"
    case placeOfWorship = "Place of Worship"
    case volunteerCenter = "Volunteer Center"
    case danceStudio = "Dance Studio"
    case martialArts = "Martial Arts"
    case tennisCourt = "Tennis Court"
    case lake = "Lake"
    case nightclub = "Nightclub"
    case barLounge = "Bar / Lounge"
    case concertVenue = "Concert Venue"
    case arena = "Arena"
    case stadium = "Stadium"

    var icon: String {
        switch self {
        case .gym: "dumbbell.fill"
        case .pool: "figure.pool.swim"
        case .library: "books.vertical.fill"
        case .park: "tree.fill"
        case .track: "figure.run.circle.fill"
        case .coffeeShop: "cup.and.saucer.fill"
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
        case .nightclub: "sparkles"
        case .barLounge: "wineglass.fill"
        case .concertVenue: "music.mic"
        case .arena: "building.2.fill"
        case .stadium: "sportscourt.fill"
        }
    }

    var accentColor: Color {
        switch self {
        case .gym: .orange
        case .pool: .cyan
        case .library: .indigo
        case .park: .green
        case .track: .red
        case .coffeeShop: Color(red: 0.6, green: 0.4, blue: 0.2)
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
        case .nightclub: .pink
        case .barLounge: .orange
        case .concertVenue: .purple
        case .arena: .blue
        case .stadium: .green
        }
    }

    var visionKeywords: [String] {
        switch self {
        case .gym:
            ["gym", "exercise", "fitness", "weight", "workout", "dumbbell",
             "barbell", "treadmill", "crossfit", "athletic", "sport", "training",
             "locker", "bench_press", "physical", "muscle"]
        case .pool:
            ["swimming_pool", "pool", "aquatic", "swim", "natatorium",
             "water", "lane", "chlorine", "lap"]
        case .library:
            ["library", "bookshelf", "reading", "study",
             "archive", "shelf", "book", "academic", "university", "school"]
        case .park:
            ["park", "garden", "playground", "lawn", "nature", "outdoor",
             "field", "meadow", "tree", "grass", "recreation", "trail"]
        case .track:
            ["track", "field", "stadium", "athletic", "running", "oval",
             "arena", "sport", "race"]
        case .coffeeShop:
            ["cafe", "coffee", "coffeehouse", "restaurant", "bistro",
             "bakery", "espresso", "interior", "counter", "seating"]
        case .bookstore:
            ["bookstore", "book", "bookshelf", "shelf", "reading",
             "literature", "novel", "paperback", "retail", "store"]
        case .museum:
            ["museum", "exhibit", "gallery", "artifact", "display",
             "sculpture", "painting", "historical", "collection", "art"]
        case .beach:
            ["beach", "sand", "ocean", "shore", "coast", "wave",
             "seashore", "seaside", "surf", "waterfront"]
        case .basketballCourt:
            ["basketball", "court", "hoop", "backboard", "sport",
             "athletic", "gymnasium", "rim", "net"]
        case .yogaStudio:
            ["yoga", "studio", "mat", "meditation", "wellness",
             "stretch", "pilates", "fitness", "mindfulness"]
        case .restaurant:
            ["restaurant", "dining", "table", "menu", "food",
             "kitchen", "plate", "meal", "bistro", "eatery"]
        case .farmersMarket:
            ["market", "farmer", "produce", "vegetable", "fruit",
             "stall", "booth", "organic", "fresh", "vendor"]
        case .dogPark:
            ["dog", "park", "pet", "canine", "fence",
             "grass", "leash", "outdoor", "animal"]
        case .skatePark:
            ["skate", "ramp", "halfpipe", "skateboard", "concrete",
             "grind", "rail", "bowl", "park"]
        case .rockClimbingGym:
            ["climbing", "rock", "wall", "harness", "boulder",
             "hold", "rope", "carabiner", "belay", "gym"]
        case .bowlingAlley:
            ["bowling", "lane", "pin", "ball", "alley",
             "strike", "gutter", "score", "shoe"]
        case .artGallery:
            ["gallery", "art", "painting", "sculpture", "exhibit",
             "canvas", "frame", "artwork", "installation"]
        case .communityCenter:
            ["community", "center", "recreation", "hall", "event",
             "meeting", "social", "room", "public"]
        case .placeOfWorship:
            ["church", "temple", "mosque", "synagogue", "chapel",
             "altar", "pew", "worship", "prayer", "steeple"]
        case .volunteerCenter:
            ["volunteer", "shelter", "food_bank", "charity", "donation",
             "community", "service", "nonprofit", "aid"]
        case .danceStudio:
            ["dance", "studio", "mirror", "barre", "floor",
             "ballet", "rehearsal", "choreography", "performance"]
        case .martialArts:
            ["martial", "dojo", "mat", "training", "boxing",
             "ring", "punching_bag", "karate", "judo", "gym"]
        case .tennisCourt:
            ["tennis", "court", "net", "racket", "baseline",
             "serve", "sport", "match", "ball"]
        case .lake:
            ["lake", "water", "shore", "pier", "dock",
             "fishing", "boat", "nature", "pond", "reservoir"]
        case .nightclub:
            ["nightclub", "club", "dance", "dj", "vip", "bottle_service",
             "velvet_rope", "bar", "lounge", "nightlife", "party"]
        case .barLounge:
            ["bar", "lounge", "cocktail", "rooftop", "speakeasy",
             "nightlife", "seating", "drink", "venue"]
        case .concertVenue:
            ["concert", "music_venue", "stage", "venue", "live_music",
             "theater", "auditorium", "show", "performance"]
        case .arena:
            ["arena", "stadium", "venue", "seating", "concourse",
             "box_office", "event_space", "sports", "concert"]
        case .stadium:
            ["stadium", "field", "arena", "grandstand", "bleachers",
             "sports_venue", "concourse", "event_space"]
        }
    }

    var captureInstructions: String {
        switch self {
        case .gym:
            "GPS verifies you're at the gym. Stay for at least 30 minutes to complete the check-in. Set your default gym in Settings."
        case .pool:
            "Aim at the pool, lane lines, or the aquatic facility. Blue water and lane markers help the AI verify."
        case .library:
            "Show bookshelves, reading tables, or stacks of books. The more books visible, the better."
        case .park:
            "Capture the park surroundings — grass, trees, paths, or open green spaces."
        case .track:
            "Show the running track, field markings, or stadium surroundings."
        case .coffeeShop:
            "Capture the café interior, counter, or seating area. Good lighting helps the AI verify."
        case .bookstore:
            "Show bookshelves, displays, or the store interior. Rows of books help the AI verify."
        case .museum:
            "Capture exhibits, display cases, or artwork on the walls. Museum signage also helps."
        case .beach:
            "Show the sand, shoreline, or ocean. Wide shots of the beach environment work best."
        case .basketballCourt:
            "Aim at the basketball hoop, court lines, or backboard. The court surface helps verification."
        case .yogaStudio:
            "Show the studio space — yoga mats, mirrors, or the practice area."
        case .restaurant:
            "Capture the dining area, tables, or menu. The restaurant interior helps AI verify."
        case .farmersMarket:
            "Show produce stalls, vendor booths, or fresh goods on display."
        case .dogPark:
            "Capture the fenced area, park signage, or the open dog-friendly space."
        case .skatePark:
            "Show ramps, halfpipes, or concrete features of the skate park."
        case .rockClimbingGym:
            "Aim at the climbing wall, holds, or harness area. Colorful wall holds help verification."
        case .bowlingAlley:
            "Show the bowling lanes, pins, or the scoring area."
        case .artGallery:
            "Capture artwork on the walls, sculptures, or gallery exhibition space."
        case .communityCenter:
            "Show the interior space, event area, or community center signage."
        case .placeOfWorship:
            "Capture the interior or exterior of the building. Pews, altars, or architectural features help."
        case .volunteerCenter:
            "Show the volunteer space, supply area, or organization signage."
        case .danceStudio:
            "Capture the dance floor, mirrors, or barre. The open studio space helps verification."
        case .martialArts:
            "Show the training mats, equipment, or dojo space. Punching bags or ring help verify."
        case .tennisCourt:
            "Aim at the tennis court, net, or court markings."
        case .lake:
            "Capture the lake, shoreline, or waterfront. Wide shots of the water body work best."
        case .nightclub:
            "GPS check-in is enough by default. If you want stronger proof, you can optionally add dual-photo evidence later."
        case .barLounge:
            "GPS check-in is enough by default. If you want stronger proof, you can optionally add dual-photo evidence later."
        case .concertVenue:
            "GPS check-in is enough by default. If you want stronger proof, you can optionally add dual-photo evidence later."
        case .arena:
            "GPS check-in is enough by default. If you want stronger proof, you can optionally add dual-photo evidence later."
        case .stadium:
            "GPS check-in is enough by default. If you want stronger proof, you can optionally add dual-photo evidence later."
        }
    }

    var minimumConfidence: Double { 0.22 }

    var mapQuestCategory: MapQuestCategory? {
        switch self {
        case .gym: .gym
        case .pool: .pool
        case .library: .library
        case .park: .park
        case .track: nil
        case .coffeeShop: .cafe
        case .bookstore: .bookstore
        case .museum: .museum
        case .beach: .beach
        case .basketballCourt: .basketballCourt
        case .yogaStudio: .yogaStudio
        case .restaurant: .restaurant
        case .farmersMarket: .farmersMarket
        case .dogPark: .dogPark
        case .skatePark: .skatePark
        case .rockClimbingGym: .rockClimbingGym
        case .bowlingAlley: .bowlingAlley
        case .artGallery: .artGallery
        case .communityCenter: .communityCenter
        case .placeOfWorship: .placeOfWorship
        case .volunteerCenter: .volunteerCenter
        case .danceStudio: .danceStudio
        case .martialArts: .martialArts
        case .tennisCourt: .tennisCourt
        case .lake: .lake
        case .nightclub, .barLounge, .concertVenue, .arena, .stadium: nil
        }
    }

    var gpsRadiusMeters: Int {
        switch self {
        case .park, .beach, .lake, .dogPark: 500
        case .skatePark, .basketballCourt, .tennisCourt, .track: 150
        case .farmersMarket: 200
        case .museum, .artGallery, .communityCenter, .placeOfWorship, .bowlingAlley: 100
        case .gym, .pool, .rockClimbingGym, .yogaStudio, .danceStudio, .martialArts: 75
        case .coffeeShop, .restaurant, .bookstore, .library: 75
        case .volunteerCenter: 100
        case .nightclub, .barLounge: 125
        case .concertVenue: 175
        case .arena, .stadium: 250
        }
    }

    var presenceTimerMinutes: Int {
        switch self {
        case .gym: 30
        case .pool, .rockClimbingGym, .martialArts, .yogaStudio, .danceStudio: 10
        case .basketballCourt, .tennisCourt, .skatePark, .bowlingAlley: 10
        case .park, .beach, .dogPark, .track: 5
        case .lake: 10
        case .museum, .artGallery, .bookstore: 5
        case .library: 10
        case .coffeeShop: 10
        case .restaurant: 5
        case .communityCenter: 10
        case .placeOfWorship: 30
        case .farmersMarket: 5
        case .volunteerCenter: 10
        case .nightclub, .barLounge: 5
        case .concertVenue: 10
        case .arena, .stadium: 10
        }
    }

    var isGPSOnly: Bool {
        switch self {
        case .gym, .park, .nightclub, .barLounge, .concertVenue, .arena, .stadium: true
        default: false
        }
    }

    var verificationSummary: String {
        if isGPSOnly {
            return "GPS-only within \(gpsRadiusMeters)m · \(presenceTimerMinutes) min presence · No photo"
        }
        return "GPS check-in within \(gpsRadiusMeters)m · \(presenceTimerMinutes) min presence required"
    }
}

nonisolated struct PlaceVerificationResult: Sendable {
    let placeType: VerifiedPlaceType
    let confidence: Double
    let topDetectedCategories: [String]
    let isVerified: Bool
    let timestamp: Date
}
