import Foundation
import MapKit
import CoreLocation

@Observable
class MapPOIService: NSObject, CLLocationManagerDelegate {
    private let locationManager = CLLocationManager()
    private var poiCache: [String: (pois: [MapPOI], fetchedAt: Date)] = [:]
    private let cacheDuration: TimeInterval = 300
    private let overpassService = OverpassService()

    private static let overpassCategories: Set<MapQuestCategory> = [.trail, .bikePath]

    private(set) var userLocation: CLLocation?
    private(set) var locationAuthorized: Bool = false
    private(set) var isLoading: Bool = false
    private(set) var pois: [MapPOI] = []
    private(set) var errorMessage: String?

    var searchRadiusMeters: Double = 2000

    var fallbackCoordinate: CLLocationCoordinate2D?

    private static let defaultFallback = CLLocationCoordinate2D(latitude: 34.0900, longitude: -118.3617)

    override init() {
        super.init()
        locationManager.delegate = self
        locationManager.desiredAccuracy = kCLLocationAccuracyBest
        let status = locationManager.authorizationStatus
        locationAuthorized = status == .authorizedWhenInUse || status == .authorizedAlways
        if locationAuthorized {
            locationManager.requestLocation()
        }
    }

    func requestPermission() {
        locationManager.requestWhenInUseAuthorization()
    }

    func requestLocation() {
        locationManager.requestLocation()
    }

    func searchPOIs(for category: MapQuestCategory, near location: CLLocation? = nil) async {
        let searchLocation = location ?? userLocation
        let center = searchLocation?.coordinate ?? fallbackCoordinate ?? Self.defaultFallback

        let cacheKey = "\(category.rawValue)_\(Int(center.latitude * 100))_\(Int(center.longitude * 100))_\(Int(searchRadiusMeters))"
        if let cached = poiCache[cacheKey], Date().timeIntervalSince(cached.fetchedAt) < cacheDuration {
            pois = cached.pois
            return
        }

        if Self.overpassCategories.contains(category) {
            await searchOverpassPOIs(for: category, center: center, cacheKey: cacheKey)
            return
        }

        isLoading = true
        errorMessage = nil

        let request = MKLocalSearch.Request()
        request.naturalLanguageQuery = category.searchQuery
        request.resultTypes = .pointOfInterest
        request.region = MKCoordinateRegion(
            center: center,
            latitudinalMeters: searchRadiusMeters * 2,
            longitudinalMeters: searchRadiusMeters * 2
        )

        let search = MKLocalSearch(request: request)
        do {
            let response = try await search.start()
            let userLoc = searchLocation ?? CLLocation(latitude: center.latitude, longitude: center.longitude)
            let results: [MapPOI] = response.mapItems.compactMap { item in
                guard let name = item.name else { return nil }

                if let poiCat = item.pointOfInterestCategory, poiCat == .parking { return nil }

                if category == .park || category == .dogPark || category == .skatePark {
                    let lower = name.lowercased()
                    let excluded = ["parking", "garage", "car park", "parking lot", "valet", "park & ride", "park and ride"]
                    if excluded.contains(where: { lower.contains($0) }) { return nil }
                }
                let itemLocation = CLLocation(
                    latitude: item.placemark.coordinate.latitude,
                    longitude: item.placemark.coordinate.longitude
                )
                let dist = userLoc.distance(from: itemLocation)
                guard dist <= searchRadiusMeters else { return nil }

                let address = [
                    item.placemark.subThoroughfare,
                    item.placemark.thoroughfare,
                    item.placemark.locality
                ].compactMap { $0 }.joined(separator: " ")

                let neighborhood = item.placemark.subLocality
                let locality = item.placemark.locality

                let specificType = Self.extractSpecificType(
                    name: name,
                    category: category,
                    mapItem: item
                )

                let description = Self.generateDescription(
                    name: name,
                    category: category,
                    mapItem: item,
                    neighborhood: neighborhood,
                    locality: locality,
                    street: item.placemark.thoroughfare
                )

                return MapPOI(
                    id: "\(category.rawValue)_\(item.placemark.coordinate.latitude)_\(item.placemark.coordinate.longitude)",
                    name: name,
                    coordinate: item.placemark.coordinate,
                    category: category,
                    address: address.isEmpty ? nil : address,
                    distance: dist,
                    placeDescription: description,
                    websiteURL: item.url,
                    phoneNumber: item.phoneNumber,
                    specificType: specificType,
                    neighborhood: neighborhood,
                    locality: locality,
                    mapItemIdentifier: item.identifier
                )
            }
            .sorted { ($0.distance ?? 0) < ($1.distance ?? 0) }

            pois = results
            poiCache[cacheKey] = (pois: results, fetchedAt: Date())
        } catch {
            errorMessage = "Couldn't find places nearby"
            pois = []
        }
        isLoading = false
    }

    private func searchOverpassPOIs(for category: MapQuestCategory, center: CLLocationCoordinate2D, cacheKey: String) async {
        isLoading = true
        errorMessage = nil

        let overpassCat: OverpassCategory = category == .bikePath ? .bikePath : .hikingTrail
        let elements = await overpassService.fetchPOIs(
            category: overpassCat,
            latitude: center.latitude,
            longitude: center.longitude,
            radiusMeters: searchRadiusMeters
        )

        let userLoc = CLLocation(latitude: center.latitude, longitude: center.longitude)
        let results: [MapPOI] = elements.prefix(30).map { element in
            let elementLoc = CLLocation(latitude: element.latitude, longitude: element.longitude)
            let dist = userLoc.distance(from: elementLoc)
            let specificType = OverpassService.specificType(for: element, category: overpassCat)
            let description = OverpassService.description(for: element, category: overpassCat)

            return MapPOI(
                id: "\(category.rawValue)_osm_\(element.id)",
                name: element.name,
                coordinate: CLLocationCoordinate2D(latitude: element.latitude, longitude: element.longitude),
                category: category,
                address: element.tags["addr:street"],
                distance: dist,
                placeDescription: description,
                websiteURL: element.tags["website"].flatMap { URL(string: $0) },
                phoneNumber: element.tags["phone"],
                specificType: specificType,
                neighborhood: nil,
                locality: nil,
                mapItemIdentifier: nil
            )
        }

        pois = results
        poiCache[cacheKey] = (pois: results, fetchedAt: Date())

        if results.isEmpty {
            errorMessage = overpassService.errorMessage ?? "No trails found nearby"
        }
        isLoading = false
    }

    func distanceToPOI(_ poi: MapPOI) -> Double? {
        guard let userLoc = userLocation else { return nil }
        let poiLoc = CLLocation(latitude: poi.coordinate.latitude, longitude: poi.coordinate.longitude)
        return userLoc.distance(from: poiLoc)
    }

    func canCheckIn(at poi: MapPOI) -> Bool {
        guard let dist = distanceToPOI(poi) else { return false }
        return dist <= poi.category.checkInRadiusMeters
    }

    func startContinuousUpdates() {
        locationManager.startUpdatingLocation()
    }

    func stopContinuousUpdates() {
        locationManager.stopUpdatingLocation()
    }

    private static func extractSpecificType(name: String, category: MapQuestCategory, mapItem: MKMapItem) -> String? {
        let lower = name.lowercased()

        switch category {
        case .museum:
            if lower.contains("art") || lower.contains("moma") || lower.contains("contemporary") || lower.contains("guggenheim") || lower.contains("whitney") { return "Art Museum" }
            if lower.contains("history") || lower.contains("heritage") || lower.contains("historical") || lower.contains("smithsonian") { return "History Museum" }
            if lower.contains("science") || lower.contains("tech") || lower.contains("discovery") || lower.contains("exploratorium") { return "Science Museum" }
            if lower.contains("children") || lower.contains("kids") { return "Children's Museum" }
            if lower.contains("natural") || lower.contains("nature") || lower.contains("fossil") || lower.contains("dinosaur") { return "Natural History" }
            if lower.contains("war") || lower.contains("military") || lower.contains("veteran") || lower.contains("army") || lower.contains("navy") { return "Military Museum" }
            if lower.contains("aviation") || lower.contains("air") || lower.contains("space") || lower.contains("nasa") || lower.contains("flight") { return "Aviation & Space" }
            if lower.contains("maritime") || lower.contains("naval") || lower.contains("ship") || lower.contains("boat") { return "Maritime Museum" }
            if lower.contains("music") || lower.contains("rock") || lower.contains("jazz") || lower.contains("grammy") { return "Music Museum" }
            if lower.contains("auto") || lower.contains("car") || lower.contains("motor") || lower.contains("vehicle") { return "Auto Museum" }
            if lower.contains("rail") || lower.contains("train") || lower.contains("locomotive") { return "Railroad Museum" }
            if lower.contains("fire") || lower.contains("firefight") { return "Fire Museum" }
            if lower.contains("sport") || lower.contains("baseball") || lower.contains("football") || lower.contains("olympic") { return "Sports Museum" }
            if lower.contains("textile") || lower.contains("fashion") || lower.contains("costume") { return "Fashion & Textile" }
            if lower.contains("folk") || lower.contains("cultural") || lower.contains("ethnic") { return "Cultural Museum" }
            if lower.contains("photograph") || lower.contains("photo") || lower.contains("camera") { return "Photography Museum" }
            if lower.contains("toy") || lower.contains("miniature") || lower.contains("doll") { return "Toy & Miniature" }
            return nil
        case .park:
            if lower.contains("national") { return "National Park" }
            if lower.contains("state") { return "State Park" }
            if lower.contains("botanical") || lower.contains("garden") || lower.contains("arboretum") { return "Botanical Garden" }
            if lower.contains("memorial") || lower.contains("monument") || lower.contains("veteran") { return "Memorial" }
            if lower.contains("playground") { return "Playground" }
            if lower.contains("nature") || lower.contains("preserve") || lower.contains("reserve") || lower.contains("wildlife") || lower.contains("sanctuary") { return "Nature Preserve" }
            if lower.contains("recreation") || lower.contains("rec ") || lower.contains("sports") || lower.contains("athletic") { return "Recreation Area" }
            if lower.contains("sculpture") { return "Sculpture Park" }
            if lower.contains("waterfront") || lower.contains("pier") || lower.contains("harbor") || lower.contains("marina") { return "Waterfront Park" }
            if lower.contains("historic") || lower.contains("heritage") { return "Historic Park" }
            if lower.contains("community") || lower.contains("neighborhood") { return "Community Park" }
            if lower.contains("linear") || lower.contains("greenway") || lower.contains("trail") { return "Greenway" }
            if lower.contains("island") { return "Island Park" }
            if lower.contains("regional") || lower.contains("county") { return "Regional Park" }
            return "Public Park"
        case .cafe:
            if lower.contains("tea") || lower.contains("matcha") || lower.contains("boba") || lower.contains("bubble") { return "Tea House" }
            if lower.contains("bakery") || lower.contains("pastry") || lower.contains("patisserie") || lower.contains("croissant") { return "Bakery Café" }
            if lower.contains("roast") || lower.contains("roaster") { return "Coffee Roaster" }
            if lower.contains("espresso") { return "Espresso Bar" }
            if lower.contains("starbucks") { return "Starbucks" }
            if lower.contains("dunkin") { return "Dunkin'" }
            if lower.contains("peet") { return "Peet's Coffee" }
            if lower.contains("blue bottle") { return "Blue Bottle" }
            if lower.contains("philz") { return "Philz Coffee" }
            if lower.contains("intelligentsia") { return "Intelligentsia" }
            if lower.contains("juice") || lower.contains("smoothie") || lower.contains("acai") { return "Juice & Smoothie" }
            if lower.contains("ice cream") || lower.contains("gelato") || lower.contains("frozen") { return "Ice Cream & Gelato" }
            if lower.contains("donut") || lower.contains("doughnut") { return "Donut Shop" }
            return "Coffee Shop"
        case .gym:
            if lower.contains("crossfit") { return "CrossFit" }
            if lower.contains("yoga") || lower.contains("pilates") { return "Yoga & Pilates" }
            if lower.contains("boxing") || lower.contains("title boxing") { return "Boxing Gym" }
            if lower.contains("planet") { return "Planet Fitness" }
            if lower.contains("24") || lower.contains("anytime") { return "24-Hour Gym" }
            if lower.contains("la fitness") { return "LA Fitness" }
            if lower.contains("gold") { return "Gold's Gym" }
            if lower.contains("equinox") { return "Equinox" }
            if lower.contains("orange") || lower.contains("orangetheory") { return "Orangetheory" }
            if lower.contains("f45") { return "F45 Training" }
            if lower.contains("crunch") { return "Crunch Fitness" }
            if lower.contains("lifetime") || lower.contains("life time") { return "Life Time" }
            if lower.contains("ymca") || lower.contains("y.m.c.a") { return "YMCA" }
            if lower.contains("barre") || lower.contains("pure barre") { return "Barre Studio" }
            if lower.contains("spin") || lower.contains("cycle") || lower.contains("soulcycle") { return "Spin Studio" }
            if lower.contains("strength") || lower.contains("powerlifting") || lower.contains("barbell") { return "Strength Training" }
            if lower.contains("functional") || lower.contains("hiit") || lower.contains("boot camp") || lower.contains("bootcamp") { return "HIIT & Boot Camp" }
            if lower.contains("swim") || lower.contains("aqua") { return "Swim & Aqua Fitness" }
            if lower.contains("personal") || lower.contains("private") || lower.contains("pt ") { return "Personal Training" }
            return "Fitness Gym"
        case .restaurant:
            if lower.contains("sushi") || lower.contains("japanese") || lower.contains("ramen") || lower.contains("izakaya") || lower.contains("udon") || lower.contains("tempura") || lower.contains("teriyaki") || lower.contains("hibachi") || lower.contains("omakase") { return "Japanese" }
            if lower.contains("pizza") || lower.contains("italian") || lower.contains("trattoria") || lower.contains("ristorante") || lower.contains("osteria") { return "Italian" }
            if lower.contains("mexican") || lower.contains("taco") || lower.contains("taqueria") || lower.contains("burrito") || lower.contains("cantina") || lower.contains("enchilada") { return "Mexican" }
            if lower.contains("thai") || lower.contains("pad thai") { return "Thai" }
            if lower.contains("indian") || lower.contains("curry") || lower.contains("tandoori") || lower.contains("masala") || lower.contains("biryani") { return "Indian" }
            if lower.contains("chinese") || lower.contains("dim sum") || lower.contains("wok") || lower.contains("szechuan") || lower.contains("sichuan") || lower.contains("cantonese") || lower.contains("dumpling") || lower.contains("noodle house") { return "Chinese" }
            if lower.contains("korean") || lower.contains("bibimbap") || lower.contains("bulgogi") { return "Korean" }
            if lower.contains("vegan") || lower.contains("plant based") || lower.contains("plant-based") { return "Plant-Based" }
            if lower.contains("barbecue") || lower.contains("grill") || lower.contains("smokehouse") || lower.contains("bbq") || lower.contains("smoked") { return "BBQ & Grill" }
            if lower.contains("seafood") || lower.contains("fish") || lower.contains("oyster") || lower.contains("lobster") || lower.contains("crab") || lower.contains("clam") || lower.contains("shrimp") { return "Seafood" }
            if lower.contains("burger") || lower.contains("shake shack") || lower.contains("five guys") || lower.contains("in-n-out") { return "Burgers" }
            if lower.contains("steakhouse") || lower.contains("steak") || lower.contains("chophouse") { return "Steakhouse" }
            if lower.contains("mediterranean") || lower.contains("greek") || lower.contains("falafel") || lower.contains("hummus") || lower.contains("shawarma") || lower.contains("kebab") { return "Mediterranean" }
            if lower.contains("vietnamese") || lower.contains("pho") || lower.contains("banh") { return "Vietnamese" }
            if lower.contains("french") || lower.contains("bistro") || lower.contains("brasserie") || lower.contains("crêpe") || lower.contains("crepe") { return "French" }
            if lower.contains("breakfast") || lower.contains("brunch") || lower.contains("diner") || lower.contains("pancake") || lower.contains("waffle") { return "Breakfast & Brunch" }
            if lower.contains("ethiopian") || lower.contains("eritrean") { return "Ethiopian" }
            if lower.contains("peruvian") || lower.contains("ceviche") { return "Peruvian" }
            if lower.contains("caribbean") || lower.contains("jamaican") || lower.contains("jerk") || lower.contains("island") { return "Caribbean" }
            if lower.contains("soul") || lower.contains("southern") || lower.contains("cajun") || lower.contains("creole") { return "Southern & Soul" }
            if lower.contains("turkish") || lower.contains("doner") { return "Turkish" }
            if lower.contains("hawaiian") || lower.contains("poke") { return "Hawaiian & Poke" }
            if lower.contains("afghan") { return "Afghan" }
            if lower.contains("moroccan") { return "Moroccan" }
            if lower.contains("spanish") || lower.contains("tapas") { return "Spanish Tapas" }
            if lower.contains("wing") || lower.contains("chicken") || lower.contains("popeye") || lower.contains("chick-fil") { return "Chicken & Wings" }
            if lower.contains("sub") || lower.contains("sandwich") || lower.contains("deli") { return "Deli & Sandwich" }
            if lower.contains("bakery") || lower.contains("pastry") { return "Bakery & Café" }
            if lower.contains("buffet") { return "Buffet" }
            if lower.contains("fine dining") || lower.contains("michelin") { return "Fine Dining" }
            if lower.contains("pub") || lower.contains("gastropub") || lower.contains("tavern") || lower.contains("ale house") { return "Gastropub" }
            if lower.contains("food truck") || lower.contains("food hall") { return "Food Hall" }
            return nil
        case .library:
            if lower.contains("university") || lower.contains("college") || lower.contains("academic") { return "Academic Library" }
            if lower.contains("law") { return "Law Library" }
            if lower.contains("children") || lower.contains("kids") { return "Children's Library" }
            return "Public Library"
        case .trail:
            if lower.contains("mountain") || lower.contains("summit") || lower.contains("peak") || lower.contains("ridge") { return "Mountain Trail" }
            if lower.contains("river") || lower.contains("creek") || lower.contains("falls") || lower.contains("waterfall") { return "Waterside Trail" }
            if lower.contains("loop") { return "Loop Trail" }
            if lower.contains("coastal") || lower.contains("shore") || lower.contains("cliff") || lower.contains("bluff") { return "Coastal Trail" }
            if lower.contains("canyon") || lower.contains("gorge") { return "Canyon Trail" }
            if lower.contains("forest") || lower.contains("woods") || lower.contains("grove") { return "Forest Trail" }
            if lower.contains("lake") || lower.contains("pond") { return "Lakeside Trail" }
            if lower.contains("desert") || lower.contains("mesa") { return "Desert Trail" }
            if lower.contains("meadow") || lower.contains("prairie") || lower.contains("field") { return "Meadow Trail" }
            return "Hiking Trail"
        case .pool:
            if lower.contains("aquatic") || lower.contains("water park") { return "Aquatic Center" }
            if lower.contains("ymca") || lower.contains("community") || lower.contains("rec") { return "Community Pool" }
            if lower.contains("olympic") { return "Olympic Pool" }
            return "Swimming Pool"
        case .bookstore:
            if lower.contains("used") || lower.contains("second") || lower.contains("thrift") || lower.contains("antiquarian") || lower.contains("rare") { return "Used & Rare Books" }
            if lower.contains("comic") || lower.contains("graphic") || lower.contains("manga") { return "Comics & Manga" }
            if lower.contains("independent") || lower.contains("indie") { return "Indie Bookstore" }
            if lower.contains("barnes") { return "Barnes & Noble" }
            if lower.contains("children") || lower.contains("kids") { return "Children's Books" }
            if lower.contains("spiritual") || lower.contains("religious") || lower.contains("christian") { return "Spiritual Books" }
            return "Bookstore"
        case .beach:
            if lower.contains("state") { return "State Beach" }
            if lower.contains("surf") { return "Surf Beach" }
            if lower.contains("dog") || lower.contains("pet") { return "Dog-Friendly Beach" }
            return "Beach"
        case .yogaStudio:
            if lower.contains("hot") || lower.contains("bikram") { return "Hot Yoga" }
            if lower.contains("aerial") { return "Aerial Yoga" }
            if lower.contains("vinyasa") || lower.contains("flow") { return "Vinyasa Flow" }
            if lower.contains("yin") || lower.contains("restorative") { return "Yin & Restorative" }
            if lower.contains("power") || lower.contains("ashtanga") { return "Power Yoga" }
            if lower.contains("kundalini") { return "Kundalini" }
            return "Yoga Studio"
        case .placeOfWorship:
            if lower.contains("church") || lower.contains("cathedral") || lower.contains("chapel") || lower.contains("baptist") || lower.contains("methodist") || lower.contains("lutheran") || lower.contains("presbyterian") || lower.contains("episcopal") || lower.contains("pentecostal") || lower.contains("evangelical") || lower.contains("catholic") || lower.contains("orthodox") { return "Church" }
            if lower.contains("mosque") || lower.contains("masjid") || lower.contains("islamic") { return "Mosque" }
            if lower.contains("synagogue") || lower.contains("jewish") || lower.contains("chabad") { return "Synagogue" }
            if lower.contains("temple") || lower.contains("shrine") || lower.contains("hindu") || lower.contains("buddhist") { return "Temple" }
            if lower.contains("gurdwara") || lower.contains("sikh") { return "Gurdwara" }
            if lower.contains("quaker") || lower.contains("meeting house") { return "Meeting House" }
            return nil
        case .martialArts:
            if lower.contains("karate") { return "Karate" }
            if lower.contains("taekwondo") || lower.contains("tkd") { return "Taekwondo" }
            if lower.contains("jiu jitsu") || lower.contains("bjj") || lower.contains("jiujitsu") || lower.contains("gracie") { return "Brazilian Jiu-Jitsu" }
            if lower.contains("boxing") { return "Boxing" }
            if lower.contains("muay thai") || lower.contains("kickboxing") { return "Muay Thai" }
            if lower.contains("mma") || lower.contains("mixed martial") { return "MMA" }
            if lower.contains("kung fu") || lower.contains("wushu") || lower.contains("wing chun") { return "Kung Fu" }
            if lower.contains("krav maga") { return "Krav Maga" }
            if lower.contains("judo") { return "Judo" }
            if lower.contains("aikido") { return "Aikido" }
            if lower.contains("hapkido") { return "Hapkido" }
            if lower.contains("fencing") { return "Fencing" }
            if lower.contains("capoeira") { return "Capoeira" }
            return nil
        case .danceStudio:
            if lower.contains("ballet") { return "Ballet" }
            if lower.contains("salsa") || lower.contains("latin") || lower.contains("bachata") { return "Latin Dance" }
            if lower.contains("hip hop") || lower.contains("hiphop") || lower.contains("urban") { return "Hip Hop" }
            if lower.contains("ballroom") || lower.contains("waltz") || lower.contains("foxtrot") { return "Ballroom" }
            if lower.contains("contemporary") || lower.contains("modern") { return "Contemporary" }
            if lower.contains("swing") || lower.contains("lindy") { return "Swing" }
            if lower.contains("pole") { return "Pole Dance" }
            if lower.contains("belly") { return "Belly Dance" }
            if lower.contains("tap") { return "Tap Dance" }
            if lower.contains("flamenco") { return "Flamenco" }
            if lower.contains("zumba") { return "Zumba" }
            return nil
        case .rockClimbingGym:
            if lower.contains("boulder") { return "Bouldering" }
            if lower.contains("top rope") || lower.contains("lead") { return "Rope Climbing" }
            return "Climbing Gym"
        case .artGallery:
            if lower.contains("contemporary") || lower.contains("modern") || lower.contains("avant") { return "Contemporary Art" }
            if lower.contains("photography") || lower.contains("photo") || lower.contains("camera") { return "Photography Gallery" }
            if lower.contains("sculpture") || lower.contains("ceramic") || lower.contains("pottery") { return "Sculpture & Ceramics" }
            if lower.contains("glass") || lower.contains("blown") { return "Glass Art" }
            if lower.contains("abstract") || lower.contains("expressionist") { return "Abstract Art" }
            if lower.contains("folk") || lower.contains("craft") || lower.contains("artisan") || lower.contains("handmade") { return "Folk & Craft" }
            if lower.contains("street") || lower.contains("urban") || lower.contains("graffiti") || lower.contains("mural") { return "Street & Urban Art" }
            if lower.contains("textile") || lower.contains("fiber") || lower.contains("weaving") || lower.contains("quilt") { return "Textile Art" }
            if lower.contains("print") || lower.contains("lithograph") || lower.contains("etching") { return "Print & Works on Paper" }
            if lower.contains("native") || lower.contains("indigenous") || lower.contains("tribal") { return "Indigenous Art" }
            if lower.contains("african") { return "African Art" }
            if lower.contains("asian") || lower.contains("japanese") || lower.contains("chinese") { return "Asian Art" }
            if lower.contains("latin") || lower.contains("latino") || lower.contains("chicano") { return "Latin American Art" }
            if lower.contains("fine art") || lower.contains("classic") || lower.contains("traditional") || lower.contains("renaissance") || lower.contains("impressionist") { return "Fine Art & Classics" }
            if lower.contains("digital") || lower.contains("new media") || lower.contains("nft") { return "Digital & New Media" }
            if lower.contains("jewelry") || lower.contains("metal") || lower.contains("goldsmith") { return "Jewelry & Metalwork" }
            if lower.contains("mixed media") || lower.contains("multimedia") { return "Mixed Media" }
            if lower.contains("studio") || lower.contains("collective") || lower.contains("co-op") || lower.contains("coop") { return "Artist Studio" }
            if lower.contains("pop") { return "Pop Art" }
            if lower.contains("surreal") { return "Surrealist Art" }
            return "Art Gallery"
        case .basketballCourt: return "Basketball Court"
        case .farmersMarket:
            if lower.contains("organic") { return "Organic Market" }
            if lower.contains("flea") || lower.contains("vintage") { return "Flea & Vintage Market" }
            if lower.contains("craft") || lower.contains("artisan") { return "Artisan Market" }
            return "Farmers Market"
        case .dogPark:
            if lower.contains("off leash") || lower.contains("off-leash") { return "Off-Leash" }
            if lower.contains("small dog") { return "Small Dog Area" }
            return "Dog Park"
        case .skatePark: return "Skate Park"
        case .bowlingAlley: return "Bowling Alley"
        case .communityCenter:
            if lower.contains("senior") || lower.contains("elder") { return "Senior Center" }
            if lower.contains("youth") || lower.contains("teen") || lower.contains("boys & girls") { return "Youth Center" }
            if lower.contains("jewish") || lower.contains("jcc") { return "JCC" }
            return "Community Center"
        case .volunteerCenter:
            if lower.contains("food bank") || lower.contains("food pantry") || lower.contains("food drive") { return "Food Bank" }
            if lower.contains("shelter") || lower.contains("homeless") { return "Shelter" }
            if lower.contains("habitat") { return "Habitat for Humanity" }
            if lower.contains("animal") || lower.contains("humane") || lower.contains("spca") || lower.contains("rescue") { return "Animal Rescue" }
            if lower.contains("red cross") { return "Red Cross" }
            if lower.contains("thrift") || lower.contains("goodwill") || lower.contains("salvation") { return "Thrift & Donation" }
            return "Volunteer Center"
        case .tennisCourt: return "Tennis Court"
        case .lake:
            if lower.contains("reservoir") { return "Reservoir" }
            if lower.contains("pond") { return "Pond" }
            return "Lake"
        case .bikePath:
            if lower.contains("greenway") || lower.contains("rail trail") || lower.contains("rail-trail") { return "Rail Trail" }
            if lower.contains("mountain") || lower.contains("mtb") { return "MTB Trail" }
            if lower.contains("river") || lower.contains("creek") || lower.contains("waterfront") { return "Riverside Path" }
            return "Bike Path"
        }
    }

    private static func generateDescription(name: String, category: MapQuestCategory, mapItem: MKMapItem, neighborhood: String?, locality: String?, street: String?) -> String {
        let lower = name.lowercased()
        let locationContext = buildLocationContext(neighborhood: neighborhood, locality: locality, street: street)
        let typeDetail = extractTypeDetail(name: name, category: category)

        var parts: [String] = []

        if let detail = typeDetail {
            parts.append(detail)
        } else {
            parts.append(defaultDetail(for: category, name: lower))
        }

        if !locationContext.isEmpty {
            parts.append(locationContext)
        }

        if let url = mapItem.url {
            let host = url.host ?? ""
            if !host.isEmpty && !host.contains("apple") {
                parts.append("Visit their website for hours & details.")
            }
        }

        return parts.joined(separator: ". ") + "."
    }

    private static func buildLocationContext(neighborhood: String?, locality: String?, street: String?) -> String {
        var context: [String] = []
        if let hood = neighborhood, !hood.isEmpty {
            context.append("Located in \(hood)")
        } else if let street = street, !street.isEmpty {
            context.append("On \(street)")
        }
        if let city = locality, !city.isEmpty, city != neighborhood {
            if context.isEmpty {
                context.append("Located in \(city)")
            } else {
                context[0] += ", \(city)"
            }
        }
        return context.joined()
    }

    private static func extractTypeDetail(name: String, category: MapQuestCategory) -> String? {
        let lower = name.lowercased()

        switch category {
        case .museum:
            if lower.contains("art") || lower.contains("moma") || lower.contains("guggenheim") || lower.contains("whitney") {
                if lower.contains("contemporary") || lower.contains("modern") || lower.contains("moma") {
                    return "Modern & contemporary art museum — paintings, sculpture, installations, and rotating exhibitions from living artists"
                }
                return "Art museum featuring visual arts collections — paintings, sculpture, and curated exhibitions across eras and styles"
            }
            if lower.contains("contemporary") { return "Contemporary art museum with cutting-edge installations, multimedia works, and emerging artist showcases" }
            if lower.contains("history") || lower.contains("heritage") || lower.contains("historical") || lower.contains("smithsonian") { return "History museum with artifacts, documents, and exhibits tracing local, national, or world events" }
            if lower.contains("science") || lower.contains("tech") || lower.contains("discovery") || lower.contains("exploratorium") { return "Science & technology museum with interactive exhibits, live demonstrations, and hands-on experiments" }
            if lower.contains("children") || lower.contains("kids") { return "Children's museum with hands-on play zones, educational activities, and interactive learning exhibits" }
            if lower.contains("natural") || lower.contains("nature") || lower.contains("fossil") || lower.contains("dinosaur") { return "Natural history museum with fossils, wildlife dioramas, geology, and ecosystem exhibits" }
            if lower.contains("war") || lower.contains("military") || lower.contains("veteran") || lower.contains("army") || lower.contains("navy") { return "Military museum with weapons, uniforms, vehicles, and stories of service across conflicts" }
            if lower.contains("aviation") || lower.contains("air") || lower.contains("space") || lower.contains("nasa") || lower.contains("flight") { return "Aviation & space museum with historic aircraft, spacecraft, flight simulators, and aerospace exhibits" }
            if lower.contains("maritime") || lower.contains("naval") || lower.contains("ship") || lower.contains("boat") { return "Maritime museum with ship models, navigation instruments, and ocean exploration history" }
            if lower.contains("music") || lower.contains("rock") || lower.contains("jazz") || lower.contains("grammy") { return "Music museum with instruments, memorabilia, listening stations, and genre-specific exhibits" }
            if lower.contains("auto") || lower.contains("car") || lower.contains("motor") || lower.contains("vehicle") { return "Automobile museum with classic cars, racing history, and vintage vehicle collections" }
            if lower.contains("rail") || lower.contains("train") || lower.contains("locomotive") { return "Railroad museum with historic locomotives, restored train cars, and railway heritage" }
            if lower.contains("fire") || lower.contains("firefight") { return "Fire museum with vintage engines, firefighting equipment, and rescue history" }
            if lower.contains("sport") || lower.contains("baseball") || lower.contains("football") || lower.contains("olympic") { return "Sports museum with memorabilia, trophies, interactive exhibits, and athletic history" }
            if lower.contains("textile") || lower.contains("fashion") || lower.contains("costume") { return "Fashion & textile museum with garments, fabric art, and design history from various periods" }
            if lower.contains("folk") || lower.contains("cultural") || lower.contains("ethnic") { return "Cultural museum celebrating folk traditions, ethnic heritage, and community history" }
            if lower.contains("photograph") || lower.contains("photo") || lower.contains("camera") { return "Photography museum with curated prints, darkroom history, and photojournalism exhibits" }
            if lower.contains("toy") || lower.contains("miniature") || lower.contains("doll") { return "Toy & miniature museum with doll houses, model trains, and vintage toy collections" }
            return nil
        case .park:
            if lower.contains("national") { return "National park with protected landscapes, scenic trails, wildlife habitats, and ranger programs" }
            if lower.contains("state") { return "State park with scenic trails, picnic grounds, and natural areas for hiking and recreation" }
            if lower.contains("botanical") || lower.contains("garden") || lower.contains("arboretum") { return "Botanical garden with curated plant collections, themed gardens, and seasonal blooms" }
            if lower.contains("memorial") || lower.contains("monument") || lower.contains("veteran") { return "Memorial park with monuments, commemorative spaces, and reflective grounds" }
            if lower.contains("playground") { return "Playground with play structures, swings, and family-friendly recreation" }
            if lower.contains("nature") || lower.contains("preserve") || lower.contains("reserve") || lower.contains("wildlife") || lower.contains("sanctuary") { return "Nature preserve with protected habitats, birdwatching, and guided nature walks" }
            if lower.contains("recreation") || lower.contains("rec ") || lower.contains("sports") || lower.contains("athletic") { return "Recreation area with sports fields, courts, picnic areas, and multi-use facilities" }
            if lower.contains("sculpture") { return "Sculpture park with outdoor art installations set in landscaped grounds" }
            if lower.contains("waterfront") || lower.contains("pier") || lower.contains("harbor") || lower.contains("marina") { return "Waterfront park with scenic views, walking paths along the water, and public docks" }
            if lower.contains("historic") || lower.contains("heritage") { return "Historic park preserving significant landmarks, buildings, or archaeological sites" }
            if lower.contains("community") || lower.contains("neighborhood") { return "Community park with green space, benches, and gathering areas for the neighborhood" }
            if lower.contains("linear") || lower.contains("greenway") || lower.contains("trail") { return "Greenway or linear park with paved paths for walking, running, and cycling" }
            if lower.contains("island") { return "Island park — a waterfront or island green space with unique views and trails" }
            if lower.contains("regional") || lower.contains("county") { return "Regional park with expansive trails, open fields, and multi-use outdoor areas" }
            return nil
        case .cafe:
            if lower.contains("tea") || lower.contains("matcha") { return "Tea house specializing in loose-leaf teas, matcha, and light bites" }
            if lower.contains("boba") || lower.contains("bubble") { return "Boba tea shop with flavored milk teas, fruit teas, and customizable toppings" }
            if lower.contains("bakery") || lower.contains("pastry") || lower.contains("patisserie") || lower.contains("croissant") { return "Bakery café with fresh-baked pastries, bread, and handcrafted coffee" }
            if lower.contains("roast") || lower.contains("roaster") { return "Coffee roaster — house-roasted single-origin beans and small-batch brews" }
            if lower.contains("espresso") { return "Espresso bar focused on specialty espresso drinks and latte art" }
            if lower.contains("starbucks") { return "Starbucks — espresso drinks, Frappuccinos, and seasonal specials" }
            if lower.contains("dunkin") { return "Dunkin' — coffee, donuts, and quick breakfast options" }
            if lower.contains("peet") { return "Peet's Coffee — dark-roast specialty coffee and fresh-brewed teas" }
            if lower.contains("blue bottle") { return "Blue Bottle — pour-over, single-origin, and meticulously sourced specialty coffee" }
            if lower.contains("philz") { return "Philz Coffee — hand-crafted blended coffee with custom flavor profiles" }
            if lower.contains("intelligentsia") { return "Intelligentsia — direct-trade specialty coffee roasted for clarity and balance" }
            if lower.contains("juice") || lower.contains("smoothie") || lower.contains("acai") { return "Juice & smoothie bar with cold-pressed drinks, acai bowls, and healthy bites" }
            if lower.contains("ice cream") || lower.contains("gelato") || lower.contains("frozen") { return "Ice cream or gelato shop with handcrafted flavors and sweet treats" }
            if lower.contains("donut") || lower.contains("doughnut") { return "Donut shop with fresh-made donuts, creative glazes, and coffee" }
            return nil
        case .gym:
            if lower.contains("crossfit") { return "CrossFit box — high-intensity WODs, Olympic lifts, and coached group classes" }
            if lower.contains("yoga") || lower.contains("pilates") { return "Studio specializing in yoga, pilates, and mind-body fitness with guided classes" }
            if lower.contains("boxing") || lower.contains("title boxing") { return "Boxing gym with heavy bags, speed bags, mitt work, and cardio boxing classes" }
            if lower.contains("planet") { return "Planet Fitness — judgment-free zone with cardio machines, weights, and 24/7 access" }
            if lower.contains("24") || lower.contains("anytime") { return "24-hour fitness center — flexible access with cardio, weights, and basic amenities" }
            if lower.contains("la fitness") { return "LA Fitness — full gym floor with pool access, basketball courts, and group classes" }
            if lower.contains("gold") { return "Gold's Gym — bodybuilding-focused with heavy free weights, machines, and personal training" }
            if lower.contains("equinox") { return "Equinox — premium fitness club with luxury amenities, spa, and personal training" }
            if lower.contains("orange") || lower.contains("orangetheory") { return "Orangetheory Fitness — heart-rate monitored interval training with real-time metrics" }
            if lower.contains("f45") { return "F45 Training — 45-minute team-based functional fitness circuits with daily variety" }
            if lower.contains("crunch") { return "Crunch Fitness — no-judgment gym with diverse group classes, cardio, and weights" }
            if lower.contains("lifetime") || lower.contains("life time") { return "Life Time — resort-style athletic club with pools, courts, spa, and family programs" }
            if lower.contains("ymca") || lower.contains("y.m.c.a") { return "YMCA — community fitness with gym, pool, youth programs, and wellness classes" }
            if lower.contains("barre") || lower.contains("pure barre") { return "Barre studio — low-impact, high-intensity workouts combining ballet, pilates, and yoga" }
            if lower.contains("spin") || lower.contains("cycle") || lower.contains("soulcycle") { return "Spin studio — indoor cycling classes with music-driven cardio and performance tracking" }
            if lower.contains("strength") || lower.contains("powerlifting") || lower.contains("barbell") { return "Strength-focused gym with squat racks, platforms, and powerlifting equipment" }
            if lower.contains("functional") || lower.contains("hiit") || lower.contains("boot camp") || lower.contains("bootcamp") { return "HIIT & boot camp studio — fast-paced circuit training and functional movements" }
            if lower.contains("swim") || lower.contains("aqua") { return "Swim & aqua fitness center with lap lanes, water aerobics, and swim instruction" }
            if lower.contains("personal") || lower.contains("private") || lower.contains("pt ") { return "Personal training studio — private one-on-one or small-group coached sessions" }
            return nil
        case .restaurant:
            if lower.contains("sushi") { return "Sushi restaurant with fresh nigiri, rolls, and Japanese seafood" }
            if lower.contains("ramen") || lower.contains("udon") { return "Noodle house with ramen, udon, and rich Japanese broths" }
            if lower.contains("izakaya") { return "Izakaya — casual Japanese pub with small plates, yakitori, and drinks" }
            if lower.contains("omakase") { return "Omakase experience — chef's choice multi-course Japanese tasting menu" }
            if lower.contains("hibachi") || lower.contains("teppanyaki") { return "Hibachi & teppanyaki — tableside grilling with Japanese-style showmanship" }
            if lower.contains("japanese") || lower.contains("teriyaki") || lower.contains("tempura") { return "Japanese restaurant with teriyaki, tempura, and traditional Japanese dishes" }
            if lower.contains("pizza") { return "Pizza restaurant — pies, slices, and Italian-style toppings" }
            if lower.contains("trattoria") || lower.contains("osteria") { return "Trattoria — casual Italian dining with homestyle pasta, wine, and seasonal dishes" }
            if lower.contains("ristorante") || lower.contains("italian") { return "Italian restaurant with pasta, risotto, and classic Italian recipes" }
            if lower.contains("taqueria") || lower.contains("taco") { return "Taqueria — street-style tacos, salsas, and Mexican staples" }
            if lower.contains("cantina") { return "Cantina — Mexican grill with burritos, enchiladas, and margaritas" }
            if lower.contains("mexican") || lower.contains("burrito") || lower.contains("enchilada") { return "Mexican restaurant with tacos, burritos, mole, and authentic regional dishes" }
            if lower.contains("thai") || lower.contains("pad thai") { return "Thai restaurant with curries, pad thai, som tum, and aromatic spices" }
            if lower.contains("indian") || lower.contains("curry") || lower.contains("tandoori") || lower.contains("masala") || lower.contains("biryani") { return "Indian restaurant with curries, naan, tandoori, biryani, and regional specialties" }
            if lower.contains("dim sum") || lower.contains("dumpling") { return "Dim sum or dumpling house — steamed, fried, and soup dumplings" }
            if lower.contains("szechuan") || lower.contains("sichuan") { return "Szechuan restaurant with fiery chili, peppercorn dishes, and bold regional flavors" }
            if lower.contains("cantonese") { return "Cantonese restaurant with roast meats, congee, and Guangdong-style dishes" }
            if lower.contains("noodle house") || lower.contains("noodle") { return "Noodle house with hand-pulled or stir-fried noodles and savory broths" }
            if lower.contains("chinese") || lower.contains("wok") { return "Chinese restaurant with a range of regional dishes — stir-fry, soups, and specialties" }
            if lower.contains("korean") || lower.contains("bibimbap") || lower.contains("bulgogi") { return "Korean restaurant with BBQ, bibimbap, kimchi, and banchan side dishes" }
            if lower.contains("vegan") || lower.contains("plant based") || lower.contains("plant-based") { return "Plant-based restaurant with creative vegan dishes and whole-food ingredients" }
            if lower.contains("barbecue") || lower.contains("smokehouse") || lower.contains("bbq") || lower.contains("smoked") { return "BBQ & smokehouse with slow-smoked brisket, ribs, pulled pork, and hearty sides" }
            if lower.contains("grill") { return "Grill restaurant — chargrilled meats, seafood, and seasonal plates" }
            if lower.contains("oyster") { return "Oyster bar with fresh-shucked oysters, raw bar platters, and seafood" }
            if lower.contains("lobster") || lower.contains("crab") || lower.contains("clam") || lower.contains("shrimp") { return "Seafood restaurant specializing in shellfish, catches of the day, and coastal fare" }
            if lower.contains("seafood") || lower.contains("fish") { return "Seafood restaurant with fresh catches, fish dishes, and ocean-to-table fare" }
            if lower.contains("burger") || lower.contains("shake shack") || lower.contains("five guys") || lower.contains("in-n-out") { return "Burger joint with handcrafted patties, shakes, and classic American sides" }
            if lower.contains("steakhouse") || lower.contains("steak") || lower.contains("chophouse") { return "Steakhouse with premium aged cuts, classic sides, and a refined dining atmosphere" }
            if lower.contains("shawarma") || lower.contains("kebab") { return "Shawarma & kebab spot with spit-roasted meats, wraps, and Middle Eastern flavors" }
            if lower.contains("falafel") || lower.contains("hummus") { return "Mediterranean eatery with falafel, hummus, fresh pita, and mezze plates" }
            if lower.contains("mediterranean") || lower.contains("greek") { return "Mediterranean restaurant with grilled meats, salads, and olive oil-based dishes" }
            if lower.contains("pho") { return "Pho restaurant with slow-simmered Vietnamese beef and chicken noodle soups" }
            if lower.contains("banh") { return "Vietnamese spot with banh mi sandwiches, fresh rolls, and fragrant herbs" }
            if lower.contains("vietnamese") { return "Vietnamese restaurant with pho, banh mi, spring rolls, and herbal flavors" }
            if lower.contains("bistro") || lower.contains("brasserie") { return "French bistro with classic dishes — steak frites, coq au vin, and wine" }
            if lower.contains("french") || lower.contains("crêpe") || lower.contains("crepe") { return "French restaurant with refined dishes, pastries, and European-style cuisine" }
            if lower.contains("diner") { return "Classic diner with all-day breakfast, comfort food, and counter service" }
            if lower.contains("pancake") || lower.contains("waffle") { return "Breakfast spot with pancakes, waffles, eggs, and morning comfort food" }
            if lower.contains("breakfast") || lower.contains("brunch") { return "Breakfast & brunch restaurant with eggs, avocado toast, pastries, and brunch cocktails" }
            if lower.contains("ethiopian") || lower.contains("eritrean") { return "Ethiopian restaurant with injera flatbread, spiced stews, and communal shared plates" }
            if lower.contains("peruvian") || lower.contains("ceviche") { return "Peruvian restaurant with ceviche, lomo saltado, and Andean-inspired flavors" }
            if lower.contains("caribbean") || lower.contains("jamaican") || lower.contains("jerk") { return "Caribbean restaurant with jerk chicken, plantains, rice & peas, and island flavors" }
            if lower.contains("cajun") || lower.contains("creole") { return "Cajun & Creole restaurant with gumbo, jambalaya, and Louisiana-style cooking" }
            if lower.contains("soul") || lower.contains("southern") { return "Southern comfort food — fried chicken, mac & cheese, collard greens, and biscuits" }
            if lower.contains("turkish") || lower.contains("doner") { return "Turkish restaurant with doner, pide, meze, and charcoal-grilled dishes" }
            if lower.contains("hawaiian") || lower.contains("poke") { return "Hawaiian & poke spot with fresh raw fish bowls, rice, and island toppings" }
            if lower.contains("afghan") { return "Afghan restaurant with kabuli pulao, kebabs, and Central Asian spices" }
            if lower.contains("moroccan") { return "Moroccan restaurant with tagines, couscous, and North African spice blends" }
            if lower.contains("spanish") || lower.contains("tapas") { return "Spanish tapas bar with small plates, paella, and Iberian cured meats" }
            if lower.contains("wing") || lower.contains("chicken") || lower.contains("popeye") || lower.contains("chick-fil") { return "Chicken spot — wings, tenders, sandwiches, and crispy fried chicken" }
            if lower.contains("sub") || lower.contains("sandwich") || lower.contains("deli") { return "Deli & sandwich shop with fresh-cut meats, subs, and made-to-order sandwiches" }
            if lower.contains("bakery") || lower.contains("pastry") { return "Bakery café with artisan breads, pastries, cakes, and light lunch options" }
            if lower.contains("buffet") { return "All-you-can-eat buffet with rotating dishes across multiple cuisines" }
            if lower.contains("fine dining") || lower.contains("michelin") { return "Fine dining — multi-course tasting menus, premium ingredients, and polished service" }
            if lower.contains("pub") || lower.contains("gastropub") || lower.contains("tavern") || lower.contains("ale house") { return "Gastropub with craft beers, elevated bar food, and a casual tavern atmosphere" }
            if lower.contains("food truck") || lower.contains("food hall") { return "Food hall or truck — multi-vendor spot with diverse cuisines under one roof" }
            return nil
        case .library:
            if lower.contains("university") || lower.contains("college") || lower.contains("academic") { return "Academic library with research databases, study rooms, and scholarly collections" }
            if lower.contains("law") { return "Law library with legal reference materials, case archives, and research resources" }
            if lower.contains("children") || lower.contains("kids") { return "Children's library with story times, picture books, and youth programs" }
            return nil
        case .trail:
            if lower.contains("mountain") || lower.contains("summit") || lower.contains("peak") || lower.contains("ridge") { return "Mountain trail with elevation gain, switchbacks, and panoramic summit views" }
            if lower.contains("waterfall") || lower.contains("falls") { return "Waterfall trail leading to scenic falls — great for photos and nature" }
            if lower.contains("river") || lower.contains("creek") { return "Riverside trail running alongside water with shaded canopy and wildlife" }
            if lower.contains("loop") { return "Loop trail — a circular route through varied terrain, returning to the start" }
            if lower.contains("coastal") || lower.contains("shore") || lower.contains("cliff") || lower.contains("bluff") { return "Coastal trail with ocean bluffs, sea views, and shoreline scenery" }
            if lower.contains("canyon") || lower.contains("gorge") { return "Canyon trail with dramatic rock walls, switchbacks, and geological formations" }
            if lower.contains("forest") || lower.contains("woods") || lower.contains("grove") { return "Forest trail through wooded canopy with old-growth trees and shaded paths" }
            if lower.contains("lake") || lower.contains("pond") { return "Lakeside trail circling or leading to a scenic lake or pond" }
            if lower.contains("desert") || lower.contains("mesa") { return "Desert trail through arid landscapes with rock formations and open vistas" }
            if lower.contains("meadow") || lower.contains("prairie") || lower.contains("field") { return "Meadow trail through open grasslands with wildflowers and wildlife" }
            return nil
        case .pool:
            if lower.contains("aquatic") || lower.contains("water park") { return "Aquatic center with lap pools, water slides, splash zones, and swim lessons" }
            if lower.contains("ymca") || lower.contains("community") || lower.contains("rec") { return "Community pool with public lap swim, water aerobics, and family hours" }
            if lower.contains("olympic") { return "Olympic-size pool with competitive lanes, diving, and swim programs" }
            return nil
        case .bookstore:
            if lower.contains("used") || lower.contains("second") || lower.contains("thrift") || lower.contains("antiquarian") || lower.contains("rare") { return "Used & rare bookstore — affordable pre-owned titles, first editions, and hidden gems" }
            if lower.contains("comic") || lower.contains("graphic") || lower.contains("manga") { return "Comic & manga shop with graphic novels, collectibles, and new releases" }
            if lower.contains("independent") || lower.contains("indie") { return "Independent bookstore with staff picks, local author events, and curated shelves" }
            if lower.contains("barnes") { return "Barnes & Noble — large bookstore with in-store café, events, and wide selection" }
            if lower.contains("children") || lower.contains("kids") { return "Children's bookstore with picture books, story times, and family events" }
            if lower.contains("spiritual") || lower.contains("religious") || lower.contains("christian") { return "Spiritual bookstore with religious texts, inspirational reading, and devotionals" }
            return nil
        case .beach:
            if lower.contains("state") { return "State beach with lifeguards, maintained shoreline, restrooms, and parking" }
            if lower.contains("surf") { return "Surf beach popular with surfers — waves, board rentals, and coastal vibes" }
            if lower.contains("dog") || lower.contains("pet") { return "Dog-friendly beach where leashed or off-leash pups can play in the sand and water" }
            return nil
        case .yogaStudio:
            if lower.contains("hot") || lower.contains("bikram") { return "Hot yoga studio — heated room classes (95–105°F) for deep stretching and detox" }
            if lower.contains("aerial") { return "Aerial yoga studio with silk hammock-based practice for inversions and flexibility" }
            if lower.contains("vinyasa") || lower.contains("flow") { return "Vinyasa flow studio — breath-linked movement sequences and dynamic yoga classes" }
            if lower.contains("yin") || lower.contains("restorative") { return "Yin & restorative yoga — slow-paced, meditative holds for deep relaxation" }
            if lower.contains("power") || lower.contains("ashtanga") { return "Power / Ashtanga yoga — vigorous, athletic practice building strength and endurance" }
            if lower.contains("kundalini") { return "Kundalini yoga — breathwork, chanting, and movement for spiritual awakening" }
            return nil
        case .placeOfWorship:
            if lower.contains("cathedral") { return "Cathedral — historic seat of a bishop with grand architecture and worship services" }
            if lower.contains("baptist") { return "Baptist church with gospel worship, sermons, and community fellowship" }
            if lower.contains("methodist") { return "Methodist church with traditional worship, community outreach, and fellowship" }
            if lower.contains("lutheran") { return "Lutheran church with liturgical worship, hymns, and community programs" }
            if lower.contains("presbyterian") { return "Presbyterian church with Reformed worship, study groups, and service projects" }
            if lower.contains("episcopal") { return "Episcopal church with liturgical worship, inclusive community, and outreach" }
            if lower.contains("pentecostal") || lower.contains("evangelical") { return "Pentecostal / evangelical church with spirited worship, praise music, and Bible study" }
            if lower.contains("catholic") { return "Catholic church with Mass, sacraments, and parish community programs" }
            if lower.contains("orthodox") { return "Orthodox church with traditional liturgy, iconography, and sacramental worship" }
            if lower.contains("church") || lower.contains("chapel") { return "Church — worship services, community events, and spiritual fellowship" }
            if lower.contains("mosque") || lower.contains("masjid") || lower.contains("islamic") { return "Mosque — Islamic prayer (salah), Jumu'ah services, and community programs" }
            if lower.contains("synagogue") || lower.contains("jewish") || lower.contains("chabad") { return "Synagogue — Jewish worship, Torah study, Shabbat services, and community" }
            if lower.contains("buddhist") { return "Buddhist temple with meditation sessions, dharma talks, and mindfulness practice" }
            if lower.contains("hindu") { return "Hindu temple with puja ceremonies, festivals, and cultural celebrations" }
            if lower.contains("temple") || lower.contains("shrine") { return "Temple — sacred space for worship, meditation, ceremonies, and community" }
            if lower.contains("gurdwara") || lower.contains("sikh") { return "Gurdwara — Sikh worship, kirtan music, and free langar community meals" }
            if lower.contains("quaker") || lower.contains("meeting house") { return "Quaker meeting house — silent worship, community discernment, and peace testimony" }
            return nil
        case .martialArts:
            if lower.contains("karate") { return "Karate dojo with traditional kata, sparring, and belt progression" }
            if lower.contains("taekwondo") || lower.contains("tkd") { return "Taekwondo school with Olympic-style kicks, forms, board breaking, and sparring" }
            if lower.contains("jiu jitsu") || lower.contains("bjj") || lower.contains("jiujitsu") || lower.contains("gracie") { return "BJJ academy with gi and no-gi grappling, submissions, and open mat sessions" }
            if lower.contains("boxing") { return "Boxing gym with heavy bag work, mitt drills, footwork training, and sparring" }
            if lower.contains("muay thai") || lower.contains("kickboxing") { return "Muay Thai / kickboxing — pad work, clinch drills, and striking conditioning" }
            if lower.contains("mma") || lower.contains("mixed martial") { return "MMA gym training striking, grappling, wrestling, and cage work" }
            if lower.contains("kung fu") || lower.contains("wushu") || lower.contains("wing chun") { return "Kung Fu school with traditional Chinese forms, weapons, and conditioning" }
            if lower.contains("krav maga") { return "Krav Maga studio — real-world self-defense techniques and scenario training" }
            if lower.contains("judo") { return "Judo dojo with throws, pins, groundwork, and Olympic-style randori" }
            if lower.contains("aikido") { return "Aikido dojo — joint locks, throws, and harmonizing with an attacker's energy" }
            if lower.contains("hapkido") { return "Hapkido school with joint locks, kicks, throws, and self-defense techniques" }
            if lower.contains("fencing") { return "Fencing club with foil, épée, or sabre training and competitive bouts" }
            if lower.contains("capoeira") { return "Capoeira studio — Afro-Brazilian martial art blending acrobatics, music, and dance" }
            return nil
        case .danceStudio:
            if lower.contains("ballet") { return "Ballet studio with classical technique, pointe work, and barre classes" }
            if lower.contains("salsa") || lower.contains("bachata") { return "Salsa & bachata studio — partner dance classes and social dance nights" }
            if lower.contains("latin") { return "Latin dance studio with salsa, merengue, cumbia, and social dancing" }
            if lower.contains("hip hop") || lower.contains("hiphop") || lower.contains("urban") { return "Hip hop dance studio with urban choreography, freestyle, and battles" }
            if lower.contains("ballroom") || lower.contains("waltz") || lower.contains("foxtrot") { return "Ballroom dance studio — waltz, foxtrot, tango, and social dance events" }
            if lower.contains("contemporary") || lower.contains("modern") { return "Contemporary dance studio with expressive modern movement and improvisation" }
            if lower.contains("swing") || lower.contains("lindy") { return "Swing dance studio — lindy hop, east coast swing, and live-music socials" }
            if lower.contains("pole") { return "Pole dance studio with pole fitness, tricks, and choreography classes" }
            if lower.contains("belly") { return "Belly dance studio with technique, shimmies, and Middle Eastern dance" }
            if lower.contains("tap") { return "Tap dance studio with rhythm, footwork technique, and performance" }
            if lower.contains("flamenco") { return "Flamenco studio with Spanish guitar-driven dance, footwork, and passion" }
            if lower.contains("zumba") { return "Zumba studio — dance-fitness party with Latin beats and easy-to-follow moves" }
            return nil
        case .rockClimbingGym:
            if lower.contains("boulder") { return "Bouldering gym — rope-free climbing on short walls with crash pads below" }
            if lower.contains("top rope") || lower.contains("lead") { return "Rope climbing gym with top-rope, lead routes, and belaying stations" }
            return nil
        case .artGallery:
            if lower.contains("contemporary") || lower.contains("modern") || lower.contains("avant") { return "Contemporary art gallery featuring modern installations, mixed media, and works by living artists" }
            if lower.contains("photography") || lower.contains("photo") || lower.contains("camera") { return "Photography gallery with curated exhibitions of fine art, documentary, and portrait photography" }
            if lower.contains("sculpture") || lower.contains("ceramic") || lower.contains("pottery") { return "Sculpture & ceramics gallery showcasing three-dimensional works, pottery, and fired clay art" }
            if lower.contains("glass") || lower.contains("blown") { return "Glass art gallery with hand-blown glasswork, vessels, and luminous sculptural pieces" }
            if lower.contains("abstract") || lower.contains("expressionist") { return "Abstract art gallery with non-representational paintings, bold color fields, and gestural works" }
            if lower.contains("folk") || lower.contains("craft") || lower.contains("artisan") || lower.contains("handmade") { return "Folk & craft gallery with handmade artisan works, traditional techniques, and regional crafts" }
            if lower.contains("street") || lower.contains("urban") || lower.contains("graffiti") || lower.contains("mural") { return "Street & urban art gallery with graffiti-inspired works, murals, and pop culture pieces" }
            if lower.contains("textile") || lower.contains("fiber") || lower.contains("weaving") || lower.contains("quilt") { return "Textile art gallery with woven tapestries, fiber art, and fabric-based works" }
            if lower.contains("print") || lower.contains("lithograph") || lower.contains("etching") { return "Print gallery with lithographs, etchings, screen prints, and works on paper" }
            if lower.contains("native") || lower.contains("indigenous") || lower.contains("tribal") { return "Indigenous art gallery with Native and tribal works — paintings, carvings, and textiles" }
            if lower.contains("african") { return "African art gallery with masks, sculptures, textiles, and contemporary African works" }
            if lower.contains("asian") || lower.contains("japanese") || lower.contains("chinese") { return "Asian art gallery with calligraphy, ink painting, ceramics, and East Asian traditions" }
            if lower.contains("latin") || lower.contains("latino") || lower.contains("chicano") { return "Latin American art gallery with vibrant paintings, murals, and cultural works" }
            if lower.contains("fine art") || lower.contains("classic") || lower.contains("traditional") || lower.contains("renaissance") || lower.contains("impressionist") { return "Fine art gallery with classical paintings, impressionist works, and European masters" }
            if lower.contains("digital") || lower.contains("new media") || lower.contains("nft") { return "Digital & new media gallery with projection art, interactive installations, and generative works" }
            if lower.contains("jewelry") || lower.contains("metal") || lower.contains("goldsmith") { return "Jewelry & metalwork gallery with handcrafted pieces, precious metals, and wearable art" }
            if lower.contains("mixed media") || lower.contains("multimedia") { return "Mixed media gallery combining painting, sculpture, found objects, and experimental art" }
            if lower.contains("studio") || lower.contains("collective") || lower.contains("co-op") || lower.contains("coop") { return "Artist studio or collective — working artists' space with rotating shows and open studios" }
            if lower.contains("pop") { return "Pop art gallery with bold, colorful works inspired by popular culture and mass media" }
            if lower.contains("surreal") { return "Surrealist art gallery with dreamlike imagery, fantastical scenes, and subconscious exploration" }
            return nil
        default:
            return nil
        }
    }

    private static func defaultDetail(for category: MapQuestCategory, name: String) -> String {
        let displayName = Self.cleanDisplayName(name, category: category)
        let lower = name.lowercased()
        switch category {
        case .museum: return "\(displayName) — a museum with curated exhibits and collections worth exploring"
        case .park: return "\(displayName) — green space with paths, open areas, and spots to unwind"
        case .library: return "\(displayName) — public library with books, media, free programs, and quiet study areas"
        case .cafe: return "\(displayName) — local spot for coffee, drinks, and a change of scenery"
        case .gym: return "\(displayName) — fitness facility with equipment, training space, and workout options"
        case .trail: return "\(displayName) — a trail through natural terrain for hiking and fresh air"
        case .pool: return "\(displayName) — swimming facility with lanes for laps and water fitness"
        case .bookstore: return "\(displayName) — bookstore with shelves to browse, gifts, and reading picks"
        case .beach: return "\(displayName) — sandy shoreline for walking, swimming, and catching sunsets"
        case .basketballCourt: return "\(displayName) — outdoor basketball court for pickup games and shooting around"
        case .yogaStudio: return "\(displayName) — yoga studio with guided classes for flexibility and mindfulness"
        case .restaurant: return "\(displayName) — local restaurant. Check their website or menu for cuisine details"
        case .farmersMarket: return "\(displayName) — market with local produce, artisan goods, and food vendors"
        case .dogPark: return lower.contains("off") ? "\(displayName) — off-leash dog park where pups can run free" : "\(displayName) — fenced dog park for dogs to play and socialize"
        case .skatePark: return "\(displayName) — skate park with ramps, rails, and features for skating"
        case .rockClimbingGym: return "\(displayName) — climbing gym with walls and routes for all skill levels"
        case .bowlingAlley: return "\(displayName) — bowling lanes for groups, leagues, and casual games"
        case .artGallery: return "\(displayName) — art gallery. Visit their website or stop by to see what's currently on display"
        case .communityCenter: return "\(displayName) — community hub with programs, classes, and local events"
        case .placeOfWorship: return "\(displayName) — a place of worship for spiritual practice and community gathering"
        case .volunteerCenter:
            if lower.contains("food") { return "\(displayName) — food bank providing meals and groceries to those in need" }
            if lower.contains("shelter") { return "\(displayName) — shelter providing support and community aid" }
            return "\(displayName) — volunteer center with opportunities to give back to the community"
        case .danceStudio: return "\(displayName) — dance studio offering classes. Visit their site for styles and schedules"
        case .martialArts: return "\(displayName) — martial arts school. Check their site for disciplines and class times"
        case .tennisCourt: return "\(displayName) — tennis court for singles, doubles, and practice sessions"
        case .lake: return lower.contains("reservoir") ? "\(displayName) — reservoir with scenic paths and waterside views" : "\(displayName) — lake with waterfront views for walking and relaxation"
        case .bikePath: return "\(displayName) — bike path for cycling, commuting, and outdoor rides"
        }
    }

    private static func cleanDisplayName(_ name: String, category: MapQuestCategory) -> String {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.count > 40 {
            let words = trimmed.split(separator: " ")
            var result = ""
            for word in words {
                let candidate = result.isEmpty ? String(word) : result + " " + word
                if candidate.count > 37 {
                    return result + "..."
                }
                result = candidate
            }
            return result
        }
        return trimmed
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        Task { @MainActor in
            self.userLocation = locations.last
        }
    }

    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        let status = manager.authorizationStatus
        Task { @MainActor in
            self.locationAuthorized = status == .authorizedWhenInUse || status == .authorizedAlways
            if self.locationAuthorized {
                manager.requestLocation()
            }
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        Task { @MainActor in
            self.errorMessage = "Location error: \(error.localizedDescription)"
            self.isLoading = false
        }
    }
}
