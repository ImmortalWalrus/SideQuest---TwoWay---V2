import Foundation
import UIKit

nonisolated struct QuestAssetPair: Sendable {
    let banner: String
    let icon: String
}

nonisolated enum QuestAssetMapping {

    static func assets(for questTitle: String) -> QuestAssetPair {
        let normalized = normalizeTitle(questTitle)
        if let key = titleToKey[normalized] {
            return assetPairs[key]!
        }
        return assetPairs["054"]!
    }

    static func assets(forFallbackBannerAsset fallbackBannerAsset: String) -> QuestAssetPair {
        let normalizedBanner = fallbackBannerAsset.replacingOccurrences(of: ".jpg", with: "")
        let iconBase = normalizedBanner.replacingOccurrences(of: "_realism", with: "")
        return QuestAssetPair(
            banner: normalizedBanner,
            icon: "\(iconBase)_icon"
        )
    }

    static func bundleImage(named name: String, ext: String, folder: String) -> UIImage? {
        if let url = Bundle.main.url(forResource: name, withExtension: ext, subdirectory: "Resources/\(folder)"),
           let image = UIImage(contentsOfFile: url.path) {
            return image
        }
        if let url = Bundle.main.url(forResource: name, withExtension: ext),
           let image = UIImage(contentsOfFile: url.path) {
            return image
        }
        return UIImage(named: name)
    }

    private static func normalizeTitle(_ title: String) -> String {
        var t = title
        for suffix in [" (Easy)", " (Medium)", " (Hard)", " (Expert)"] {
            if t.hasSuffix(suffix) {
                t = String(t.dropLast(suffix.count))
                break
            }
        }
        return t
    }

    private static let assetPairs: [String: QuestAssetPair] = [
        "001": QuestAssetPair(banner: "001_push-ups_realism", icon: "001_push-ups_icon"),
        "002": QuestAssetPair(banner: "002_plank_realism", icon: "002_plank_icon"),
        "003": QuestAssetPair(banner: "003_wall-sit_realism", icon: "003_wall-sit_icon"),
        "004": QuestAssetPair(banner: "004_steps_realism", icon: "004_steps_icon"),
        "005": QuestAssetPair(banner: "005_road-run-and-brisk-walk_realism", icon: "005_road-run-and-brisk-walk_icon"),
        "006": QuestAssetPair(banner: "006_extreme-running_realism", icon: "006_extreme-running_icon"),
        "007": QuestAssetPair(banner: "007_jump-rope_realism", icon: "007_jump-rope_icon"),
        "008": QuestAssetPair(banner: "008_bike-ride-and-bike-commute_realism", icon: "008_bike-ride-and-bike-commute_icon"),
        "009": QuestAssetPair(banner: "009_gym-arrival_realism", icon: "009_gym-arrival_icon"),
        "010": QuestAssetPair(banner: "010_swim-session_realism", icon: "010_swim-session_icon"),
        "011": QuestAssetPair(banner: "011_track-day_realism", icon: "011_track-day_icon"),
        "012": QuestAssetPair(banner: "012_basketball-court-session_realism", icon: "012_basketball-court-session_icon"),
        "013": QuestAssetPair(banner: "013_bowling-night_realism", icon: "013_bowling-night_icon"),
        "014": QuestAssetPair(banner: "014_tennis-match_realism", icon: "014_tennis-match_icon"),
        "015": QuestAssetPair(banner: "015_skate-park-session_realism", icon: "015_skate-park-session_icon"),
        "016": QuestAssetPair(banner: "016_climbing-wall-session_realism", icon: "016_climbing-wall-session_icon"),
        "017": QuestAssetPair(banner: "017_martial-arts-training_realism", icon: "017_martial-arts-training_icon"),
        "018": QuestAssetPair(banner: "018_cold-exposure_realism", icon: "018_cold-exposure_icon"),
        "019": QuestAssetPair(banner: "019_squats_realism", icon: "019_squats_icon"),
        "020": QuestAssetPair(banner: "020_mobility-flow_realism", icon: "020_mobility-flow_icon"),
        "021": QuestAssetPair(banner: "021_bodyweight-circuit_realism", icon: "021_bodyweight-circuit_icon"),
        "022": QuestAssetPair(banner: "022_foam-roll-recovery_realism", icon: "022_foam-roll-recovery_icon"),
        "023": QuestAssetPair(banner: "023_stair-climb_realism", icon: "023_stair-climb_icon"),
        "024": QuestAssetPair(banner: "024_hydration-check_realism", icon: "024_hydration-check_icon"),
        "025": QuestAssetPair(banner: "025_nutrition-discipline_realism", icon: "025_nutrition-discipline_icon"),
        "026": QuestAssetPair(banner: "026_full-gym-session_realism", icon: "026_full-gym-session_icon"),
        "027": QuestAssetPair(banner: "027_early-grind-and-discipline_realism", icon: "027_early-grind-and-discipline_icon"),
        "028": QuestAssetPair(banner: "028_sunrise-walk_realism", icon: "028_sunrise-walk_icon"),
        "029": QuestAssetPair(banner: "029_sunset-walk_realism", icon: "029_sunset-walk_icon"),
        "030": QuestAssetPair(banner: "030_everyday-walk-and-scenic-route_realism", icon: "030_everyday-walk-and-scenic-route_icon"),
        "031": QuestAssetPair(banner: "031_street-photography_realism", icon: "031_street-photography_icon"),
        "032": QuestAssetPair(banner: "032_park-outing_realism", icon: "032_park-outing_icon"),
        "033": QuestAssetPair(banner: "033_trail-hike_realism", icon: "033_trail-hike_icon"),
        "034": QuestAssetPair(banner: "034_trail-run_realism", icon: "034_trail-run_icon"),
        "035": QuestAssetPair(banner: "035_beach-walk-and-cleanup_realism", icon: "035_beach-walk-and-cleanup_icon"),
        "036": QuestAssetPair(banner: "036_lakeside-visit_realism", icon: "036_lakeside-visit_icon"),
        "037": QuestAssetPair(banner: "037_attend-service_realism", icon: "037_attend-service_icon"),
        "038": QuestAssetPair(banner: "038_restaurant-discovery_realism", icon: "038_restaurant-discovery_icon"),
        "039": QuestAssetPair(banner: "039_bookstore-browse_realism", icon: "039_bookstore-browse_icon"),
        "040": QuestAssetPair(banner: "040_museum-visit_realism", icon: "040_museum-visit_icon"),
        "041": QuestAssetPair(banner: "041_gallery-visit_realism", icon: "041_gallery-visit_icon"),
        "042": QuestAssetPair(banner: "042_farmers-market-visit_realism", icon: "042_farmers-market-visit_icon"),
        "043": QuestAssetPair(banner: "043_community-event-and-open-mic_realism", icon: "043_community-event-and-open-mic_icon"),
        "044": QuestAssetPair(banner: "044_volunteer-session_realism", icon: "044_volunteer-session_icon"),
        "045": QuestAssetPair(banner: "045_coffee-spot_realism", icon: "045_coffee-spot_icon"),
        "046": QuestAssetPair(banner: "046_home-cooking_realism", icon: "046_home-cooking_icon"),
        "047": QuestAssetPair(banner: "047_screen-free-outdoor-escape_realism", icon: "047_screen-free-outdoor-escape_icon"),
        "048": QuestAssetPair(banner: "048_social-courage-and-reconnect_realism", icon: "048_social-courage-and-reconnect_icon"),
        "049": QuestAssetPair(banner: "049_day-trip-and-solo-adventure_realism", icon: "049_day-trip-and-solo-adventure_icon"),
        "050": QuestAssetPair(banner: "050_read-outside_realism", icon: "050_read-outside_icon"),
        "051": QuestAssetPair(banner: "051_skillcraft_realism", icon: "051_skillcraft_icon"),
        "052": QuestAssetPair(banner: "052_stargazer_realism", icon: "052_stargazer_icon"),
        "053": QuestAssetPair(banner: "053_classic-film_realism", icon: "053_classic-film_icon"),
        "054": QuestAssetPair(banner: "054_deep-focus-and-study-session_realism", icon: "054_deep-focus-and-study-session_icon"),
        "055": QuestAssetPair(banner: "055_meditation-and-silence_realism", icon: "055_meditation-and-silence_icon"),
        "056": QuestAssetPair(banner: "056_reading_realism", icon: "056_reading_icon"),
        "057": QuestAssetPair(banner: "057_writing-and-journaling_realism", icon: "057_writing-and-journaling_icon"),
        "058": QuestAssetPair(banner: "058_mindset-ritual_realism", icon: "058_mindset-ritual_icon"),
        "059": QuestAssetPair(banner: "059_learning-session_realism", icon: "059_learning-session_icon"),
        "060": QuestAssetPair(banner: "060_sketch-and-calligraphy_realism", icon: "060_sketch-and-calligraphy_icon"),
        "061": QuestAssetPair(banner: "061_podcast-reflection_realism", icon: "061_podcast-reflection_icon"),
        "062": QuestAssetPair(banner: "062_difficult-conversation_realism", icon: "062_difficult-conversation_icon"),
        "063": QuestAssetPair(banner: "063_dance-class_realism", icon: "063_dance-class_icon"),
        "064": QuestAssetPair(banner: "064_memory-training_realism", icon: "064_memory-training_icon"),
        "065": QuestAssetPair(banner: "065_speed-math_realism", icon: "065_speed-math_icon"),
        "066": QuestAssetPair(banner: "066_word-games_realism", icon: "066_word-games_icon"),
        "067": QuestAssetPair(banner: "067_chess_realism", icon: "067_chess_icon"),
    ]

    // swiftlint:disable function_body_length
    private static let titleToKey: [String: String] = {
        var map: [String: String] = [:]
        let groups: [(String, [String])] = [
            ("001", ["50 Push-Ups","80 Push-Ups","100 Push-Ups","150 Push-Ups","500 Push-Ups","1,000 Push-Ups","30 Push-Ups Unbroken","60 Push-Ups Unbroken","75 Push-Ups Unbroken","85 Push-Ups Unbroken","100 Push-Ups Challenge","50 Push-Ups Under 15 Min","75 Push-Ups Under 20 Min","200 Push-Ups Under 45 Min"]),
            ("002", ["1 Min Plank","90-Second Plank","2 Min Plank","2-Minute Plank","3-Minute Plank","4-Minute Plank","5 Min Plank"]),
            ("003", ["3-Minute Wall Sit","5-Minute Wall Sit","8-Minute Wall Sit","12-Minute Wall Sit"]),
            ("004", ["8,000 Steps","10,000 Steps","12,000 Steps","3,000 Steps Before 10am","3K Morning + 8K Total","4,000 Steps After 6pm","15,000 Steps","3K Morning + 12K Total","12K Steps Before 4pm","20,000 Steps","25,000 Steps"]),
            ("005", ["5K Run","2 Mile Run","5K Walk Under 75:00","1 Mile Walk Under 14:00","5K Run Under 30:00","1 Mile Under 8:30","3-Mile Walk Under 45:00","2-Mile Run Under 18:00","5K Walk Under 60:00","5K Under 25:30","3-Mile Run Under 26:30","2-Mile Under 16:30","5K Under 22:30","5-Mile Under 44:00"]),
            ("006", ["Extreme 1K","Extreme 2K","Extreme 5K","Extreme 10K"]),
            ("007", ["50 Jump Rope","100 Jump Rope","250 Jump Rope","500 Jump Rope","1,000 Jump Rope","2,000 Jump Rope","Jump Rope Session"]),
            ("008", ["3-Mile Bike Ride","5-Mile Bike Ride","10-Mile Bike Ride","25-Mile Bike Ride","Bike Commute","5-Mile Bike Commute","Bike Ride"]),
            ("009", ["Gym Check-In","Pre-Workout Arrival","Gym Before 7AM"]),
            ("010", ["Swim Session","Swim Workout"]),
            ("011", ["Track Day"]),
            ("012", ["Court Session — Basketball"]),
            ("013", ["Bowling Night"]),
            ("014", ["Tennis Match"]),
            ("015", ["Skate Park Session"]),
            ("016", ["Climbing Wall Session"]),
            ("017", ["Martial Arts Session","Martial Arts Training","Learn a Self-Defense Move"]),
            ("018", ["Cold Shower","Cold Exposure","Ice Bath"]),
            ("019", ["200 Squats"]),
            ("020", ["Stretch Routine","Yoga Flow","Yoga Class Check-In","New Stretch"]),
            ("021", ["Bodyweight Circuit","Core Blitz"]),
            ("022", ["Foam Roll Recovery"]),
            ("023", ["Stair Climb"]),
            ("024", ["Hydration Check"]),
            ("025", ["No Junk Food","Clean Eating Day","7-Day Streak: No Sugar"]),
            ("026", ["Full Gym Session","Sport Session","Double Session","Competition Day"]),
            ("027", ["5AM Wake-Up","No Phone First Hour","Full Day Discipline","Midnight to 5AM Challenge"]),
            ("028", ["Sunrise Walk","Watch the Sunrise","Pre-Dawn Walk"]),
            ("029", ["Sunset Walk"]),
            ("030", ["1 Mile Walk","Take a Walk","Different Time Walk","Take the Scenic Route"]),
            ("031", ["Street Photography","Texture Photography"]),
            ("032", ["Visit a New Park","Park Outing","Dog Park Hangout"]),
            ("033", ["Hike a Trail","1-Mile Trail Walk","3-Mile Trail Hike","Complete a Loop Trail","5-Mile Trail Hike","5-Mile Loop Trail","Trail Explorer: 3-Day Streak","10-Mile Trail Trek","Triple Trail Day","Trail Explorer: 7-Day Streak"]),
            ("034", ["5K Trail Run"]),
            ("035", ["Beach Walk","Clean a Public Space"]),
            ("036", ["Lakeside Visit"]),
            ("037", ["Attend Service"]),
            ("038", ["Try a New Restaurant","Try New Food","Foreign Dish"]),
            ("039", ["Bookstore Browse","3 Unique Bookstores"]),
            ("040", ["Museum Visit","Visit a Museum","Museum Solo","3 Unique Museums"]),
            ("041", ["Gallery Visit","3 Unique Galleries"]),
            ("042", ["Farmers Market Visit"]),
            ("043", ["Community Event","Attend a Live Event","Public Talk or Open Mic","Host a Gathering","Public Speaking"]),
            ("044", ["Volunteer Session","Volunteer Hour","Silent Volunteer","3 Volunteer Sessions"]),
            ("045", ["New Coffee Spot","Solo Coffee Date","Cafe Observer","Café Observer"]),
            ("046", ["Cook a New Recipe","Handmade Bread or Pasta","Master One Sauce"]),
            ("047", ["Screen-Free Hour Outdoors","Social Media Detox","24-Hour Social Media Detox","Full Day Offline","Weekend Without Screens"]),
            ("048", ["Talk to a Stranger","Genuine Compliment","Reconnect"]),
            ("049", ["Day Trip","Solo Adventure","Solo Overnight","Neighborhood Map"]),
            ("050", ["Read Outside"]),
            ("051", ["Learn a New Skill","Build With Your Hands","Fix Something","Start a Herb Garden"]),
            ("052", ["Stargazer"]),
            ("053", ["Classic Film"]),
            ("054", ["10-Min Focus Block","20-Min Focus Block","30-Min Focus Block","45-Min Focus Block","90-Min Focus Block","2-Hour Focus Session","3-Hour Focus Session","4-Hour Focus Session","Study Session","Library Study Session","Cafe Deep Work","Library Deep Session","Library Marathon"]),
            ("055", ["5-Min Meditation","10-Min Meditation","20-Min Meditation","30-Min Meditation","Deep Breathing","10 Minutes of Silence"]),
            ("056", ["10-Min Reading","20-Min Reading","30-Min Deep Read","1-Hour Reading Marathon","Read for 30 Minutes","Read for 1 Hour","Read for 2 Hours","Finish a Book"]),
            ("057", ["Gratitude Log","Journal Entry","Daily Affirmations","Vision Journal","Deep Vision Entry","Write 500 Words","Write 1,500 Words","Unsent Letter","No Complaints Day"]),
            ("058", ["Season Playlist"]),
            ("059", ["Learn 10 New Words","Memorize a Poem","Teach Someone Something","Finish a Course"]),
            ("060", ["Sketch Session","Press Leaves or Flowers","Calligraphy Week"]),
            ("061", ["Listen to a Podcast"]),
            ("062", ["Difficult Conversation"]),
            ("063", ["Dance Class"]),
            ("064", ["Memory Training","Memory Training: Medium","Memory Training: Hard","Memory Training: Expert","Memory Level 1 (85%+)","Memory Level 2 (85%+)","Memory Recall 15 (80%+)","Memory Level 3 (85%+)","Memory Level 4 (90%+)","Memory Recall 30 (85%+)"]),
            ("065", ["Speed Math Sprint","Speed Math: Medium","Speed Math: Hard","Speed Math: Expert","Math Sprint 20 (80%+)","Math Sprint 30 (80%+)","Math Accuracy 95% (15)","Math Sprint 40 (80%+)","Math Sprint 50 (85%+)","Math Accuracy 95% (30)"]),
            ("066", ["Word Scramble","Word Scramble: Medium","Word Scramble: Hard","Word Scramble: Expert","WordForge 60 Points","WordForge 80 Points","WordForge 100 Points","WordForge 120 Points","WordForge 140 Points","WordForge 160 Points"]),
            ("067", ["AI Chess Win (Level 3)","Ranked Chess Win (+10 ELO)","Chess Puzzle Set (10 at 85%+)","AI Chess Win (Level 5)","Ranked Chess Win (Equal+)","Grandmaster Ranked Victory"]),
        ]
        for (key, titles) in groups {
            for title in titles {
                map[title] = key
            }
        }
        return map
    }()
}
