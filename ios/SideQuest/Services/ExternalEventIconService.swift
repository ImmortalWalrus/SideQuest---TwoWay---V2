import UIKit

enum ExternalEventIconService {
    private static let imageCache = NSCache<NSString, UIImage>()

    static func iconName(for event: ExternalEvent) -> String {
        switch event.eventType {
        case .groupRun:
            return "group_run"
        case .race5k, .race10k:
            return variant(baseNames: ["race_short_v1", "race_short_v2"], seed: event)
        case .raceHalfMarathon, .raceMarathon:
            return "race_long"
        case .sportsEvent:
            return sportsCategory(for: event)
        case .concert:
            return musicGenreCategory(for: event)
        case .partyNightlife:
            return variant(baseNames: ["nightlife_party_v1", "nightlife_party_v2"], seed: event)
        case .socialCommunityEvent:
            return communityCategory(for: event)
        case .weekendActivity:
            return weekendCategory(for: event)
        case .otherLiveEvent:
            return fallbackCategory(for: event)
        }
    }

    static func image(for event: ExternalEvent) -> UIImage? {
        let name = iconName(for: event)
        let cacheKey = NSString(string: name)
        if let cached = imageCache.object(forKey: cacheKey) {
            return cached
        }
        guard let image = QuestAssetMapping.bundleImage(named: name, ext: "png", folder: "EventIcons") else {
            return nil
        }
        imageCache.setObject(image, forKey: cacheKey)
        return image
    }

    private static func communityCategory(for event: ExternalEvent) -> String {
        let haystack = normalizedHaystack(for: event)
        if haystack.contains("market") || haystack.contains("festival") {
            return "market_festival"
        }
        if haystack.contains("food") || haystack.contains("drink") {
            return "food_drink"
        }
        return "community_social"
    }

    private static func weekendCategory(for event: ExternalEvent) -> String {
        let haystack = normalizedHaystack(for: event)
        if haystack.contains("comedy") {
            return "comedy_show"
        }
        if haystack.contains("theater")
            || haystack.contains("theatre")
            || haystack.contains("play")
            || haystack.contains("broadway")
            || haystack.contains("blue man")
            || haystack.contains("show")
        {
            return "theater_live_show"
        }
        if haystack.contains("food") || haystack.contains("drink") {
            return "food_drink"
        }
        if haystack.contains("market") || haystack.contains("festival") {
            return "market_festival"
        }
        return variant(baseNames: ["outdoor_weekend_v1", "outdoor_weekend_v2"], seed: event)
    }

    private static func fallbackCategory(for event: ExternalEvent) -> String {
        let haystack = normalizedHaystack(for: event)
        if haystack.contains("food") || haystack.contains("drink") {
            return "food_drink"
        }
        if haystack.contains("festival") || haystack.contains("market") {
            return "market_festival"
        }
        if haystack.contains("community") || haystack.contains("networking") {
            return "community_social"
        }
        return "generic_live_event"
    }

    private static func sportsCategory(for event: ExternalEvent) -> String {
        let haystack = normalizedHaystack(for: event)

        if haystack.contains("basketball")
            || haystack.contains("nba")
            || haystack.contains("wnba")
            || haystack.contains("ncaab")
            || haystack.contains("ncaamb")
            || haystack.contains("ncaawb")
        {
            return "basketball"
        }

        if haystack.contains("football")
            || haystack.contains("nfl")
            || haystack.contains("ncaaf")
            || haystack.contains("college football")
            || haystack.contains("super bowl")
        {
            return "football"
        }

        if haystack.contains("baseball")
            || haystack.contains("mlb")
            || haystack.contains("minor league baseball")
            || haystack.contains("ballpark")
        {
            return "baseball"
        }

        if haystack.contains("soccer")
            || haystack.contains("mls")
            || haystack.contains("nwsl")
            || haystack.contains("usl")
            || haystack.contains("premier league")
            || haystack.contains("champions league")
            || haystack.contains("uefa")
            || haystack.contains("fifa")
            || haystack.contains("laliga")
            || haystack.contains("la liga")
            || haystack.contains("bundesliga")
            || haystack.contains("serie a")
        {
            return "soccer"
        }

        if haystack.contains("hockey")
            || haystack.contains("nhl")
            || haystack.contains("ahl")
            || haystack.contains("puck")
        {
            return "hockey"
        }

        if haystack.contains("tennis")
            || haystack.contains("atp")
            || haystack.contains("wta")
            || haystack.contains("us open")
            || haystack.contains("wimbledon")
            || haystack.contains("roland garros")
            || haystack.contains("australian open")
        {
            return "tennis"
        }

        if haystack.contains("golf")
            || haystack.contains("pga")
            || haystack.contains("lpga")
            || haystack.contains("masters")
            || haystack.contains("open championship")
        {
            return "golf"
        }

        if haystack.contains("boxing")
            || haystack.contains("ufc")
            || haystack.contains("mma")
            || haystack.contains("wrestling")
            || haystack.contains("wwe")
            || haystack.contains("aew")
            || haystack.contains("bellator")
            || haystack.contains("fight night")
            || haystack.contains("kickboxing")
            || haystack.contains("muay thai")
        {
            return "combat"
        }

        if haystack.contains("formula 1")
            || haystack.contains("formula one")
            || haystack.contains("f1 ")
            || haystack.hasPrefix("f1")
            || haystack.contains("nascar")
            || haystack.contains("indycar")
            || haystack.contains("motogp")
            || haystack.contains("motocross")
            || haystack.contains("supercross")
            || haystack.contains("grand prix")
            || haystack.contains("rally")
        {
            return "motorsports"
        }

        return "generic_live_event"
    }

    private static func musicGenreCategory(for event: ExternalEvent) -> String {
        let haystack = normalizedHaystack(for: event)

        if haystack.contains("afrobeats") || haystack.contains("amapiano") || haystack.contains("reggae") || haystack.contains("dancehall") {
            return variant(baseNames: ["afrobeats_world_reggae_01", "afrobeats_world_reggae_02"], seed: event)
        }
        if haystack.contains("gospel") || haystack.contains("worship") || haystack.contains("christian") {
            return variant(baseNames: ["gospel_christian_01", "gospel_christian_02"], seed: event)
        }
        if haystack.contains("classical") || haystack.contains("orchestra") || haystack.contains("symphony") || haystack.contains("opera") {
            return variant(baseNames: ["classical_orchestral_01", "classical_orchestral_02"], seed: event)
        }
        if haystack.contains("jazz") || haystack.contains("blues") || haystack.contains("soul") || haystack.contains("funk") {
            return variant(baseNames: ["jazz_blues_01", "jazz_blues_02"], seed: event)
        }
        if haystack.contains("country") || haystack.contains("americana") || haystack.contains("bluegrass") {
            return variant(baseNames: ["country_americana_01", "country_americana_02"], seed: event)
        }
        if haystack.contains("folk") || haystack.contains("acoustic") || haystack.contains("singer songwriter") || haystack.contains("singer-songwriter") {
            return variant(baseNames: ["folk_acoustic_01", "folk_acoustic_02", "singer_songwriter_01", "singer_songwriter_02"], seed: event)
        }
        if haystack.contains("latin") || haystack.contains("reggaeton") || haystack.contains("banda") || haystack.contains("corridos") || haystack.contains("salsa") || haystack.contains("bachata") {
            return variant(baseNames: ["latin_reggaeton_01", "latin_reggaeton_02", "latin_reggaeton_03"], seed: event)
        }
        if haystack.contains("house") || haystack.contains("techno") || haystack.contains("trance") {
            return variant(baseNames: ["house_techno_01", "house_techno_02", "house_techno_03"], seed: event)
        }
        if haystack.contains("edm") || haystack.contains("electronic") || haystack.contains("dance") || haystack.contains("dj") {
            return variant(baseNames: ["electronic_edm_01", "electronic_edm_02", "electronic_edm_03"], seed: event)
        }
        if haystack.contains("metal") || haystack.contains("hard rock") || haystack.contains("thrash") {
            return variant(baseNames: ["metal_hard_rock_01", "metal_hard_rock_02", "metal_hard_rock_03"], seed: event)
        }
        if haystack.contains("punk") || haystack.contains("emo") {
            return variant(baseNames: ["punk_emo_01", "punk_emo_02"], seed: event)
        }
        if haystack.contains("alternative") || haystack.contains("indie") || haystack.contains("shoegaze") || haystack.contains("dream pop") {
            return variant(baseNames: ["alternative_indie_01", "alternative_indie_02", "alternative_indie_03"], seed: event)
        }
        if haystack.contains("rock") {
            return variant(baseNames: ["rock_01", "rock_02", "rock_03"], seed: event)
        }
        if haystack.contains("rnb") || haystack.contains("r b") || haystack.contains("neo soul") {
            return variant(baseNames: ["rnb_soul_01", "rnb_soul_02", "rnb_soul_03"], seed: event)
        }
        if haystack.contains("hip hop") || haystack.contains("hiphop") || haystack.contains("rap") || haystack.contains("trap") {
            return variant(baseNames: ["hip_hop_rap_01", "hip_hop_rap_02", "hip_hop_rap_03"], seed: event)
        }
        if haystack.contains("pop") || haystack.contains("k pop") || haystack.contains("dance pop") {
            return variant(baseNames: ["pop_01", "pop_02", "pop_03"], seed: event)
        }
        return variant(baseNames: ["concert_generic_01", "concert_generic_02"], seed: event)
    }

    private static func normalizedHaystack(for event: ExternalEvent) -> String {
        ExternalEventSupport.normalizeToken(
            [
                event.title,
                event.category,
                event.subcategory,
                event.shortDescription,
                event.fullDescription,
                event.tags.joined(separator: " ")
            ]
            .compactMap { $0 }
            .joined(separator: " ")
        )
    }

    private static func variant(baseNames: [String], seed event: ExternalEvent) -> String {
        guard !baseNames.isEmpty else { return "generic_live_event" }
        let seed = (event.sourceEventID + event.title).unicodeScalars.reduce(0) { partialResult, scalar in
            partialResult + Int(scalar.value)
        }
        return baseNames[seed % baseNames.count]
    }
}
