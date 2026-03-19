import SwiftUI

nonisolated enum QuestCategory: String, CaseIterable, Identifiable, Sendable {
    case running = "Running"
    case walking = "Walking"
    case hiking = "Hiking & Trails"
    case cycling = "Cycling"
    case pushUps = "Push-Ups"
    case planks = "Planks"
    case wallSits = "Wall Sits"
    case jumpRope = "Jump Rope"
    case steps = "Steps"
    case gymAndPlaces = "Gym & Check-Ins"
    case coldAndDiscipline = "Cold & Discipline"
    case focus = "Focus Blocks"
    case meditation = "Meditation"
    case reading = "Reading"
    case journaling = "Journaling & Gratitude"
    case affirmations = "Affirmations & Vision"
    case brainTraining = "Brain Training"
    case placesExplore = "Places & Discovery"
    case photography = "Photography"
    case socialExperiences = "Social & Experiences"
    case lifestyle = "Lifestyle"
    case digitalDetox = "Digital Detox"
    case creative = "Creative"
    case other = "Other"

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .running: "figure.run"
        case .walking: "figure.walk"
        case .hiking: "mountain.2.fill"
        case .cycling: "bicycle"
        case .pushUps: "figure.strengthtraining.traditional"
        case .planks: "figure.core.training"
        case .wallSits: "figure.seated.side"
        case .jumpRope: "figure.jumprope"
        case .steps: "shoeprints.fill"
        case .gymAndPlaces: "dumbbell.fill"
        case .coldAndDiscipline: "snowflake"
        case .focus: "timer"
        case .meditation: "brain.head.profile.fill"
        case .reading: "book.fill"
        case .journaling: "square.and.pencil"
        case .affirmations: "sparkles"
        case .brainTraining: "puzzlepiece.fill"
        case .placesExplore: "mappin.and.ellipse"
        case .photography: "camera.fill"
        case .socialExperiences: "person.2.fill"
        case .lifestyle: "leaf.fill"
        case .digitalDetox: "iphone.slash"
        case .creative: "paintbrush.fill"
        case .other: "star.fill"
        }
    }

    static func categorize(_ quest: Quest) -> QuestCategory {
        if let evidence = quest.evidenceType {
            switch evidence {
            case .gpsTracking:
                if quest.isBikeQuest { return .cycling }
                if quest.isTrailQuest { return .hiking }
                if quest.maxSpeedMph <= 8.0 && quest.targetDistanceMiles ?? 0 <= 2.0 { return .walking }
                if quest.maxSpeedMph <= 8.0 { return .hiking }
                return .running
            case .pushUpTracking: return .pushUps
            case .plankTracking: return .planks
            case .wallSitTracking: return .wallSits
            case .jumpRopeTracking: return .jumpRope
            case .stepTracking: return .steps
            case .meditationTracking: return .meditation
            case .focusTracking: return .focus
            case .readingTracking: return .reading
            case .gratitudePhoto: return .journaling
            case .affirmationPhoto: return .affirmations
            case .placeVerification:
                if quest.path == .warrior { return .gymAndPlaces }
                if quest.path == .mind { return .gymAndPlaces }
                return .placesExplore
            case .video:
                let lower = quest.title.lowercased()
                if lower.contains("cold") || lower.contains("shower") { return .coldAndDiscipline }
                return .other
            case .dualPhoto:
                let lower = quest.title.lowercased()
                if lower.contains("gym") { return .gymAndPlaces }
                if lower.contains("photo") { return .photography }
                return .other
            }
        }

        let lower = quest.title.lowercased()
        let desc = quest.description.lowercased()

        if lower.contains("chess") || lower.contains("memory") || lower.contains("math") || lower.contains("word") || lower.contains("brain") || quest.id.hasPrefix("mp_") || quest.id.hasPrefix("mi1") || quest.id.hasPrefix("mi2") || quest.id.hasPrefix("mi3") {
            return .brainTraining
        }
        if lower.contains("run") || lower.contains("sprint") { return .running }
        if lower.contains("walk") { return .walking }
        if lower.contains("hike") || lower.contains("trail") { return .hiking }
        if lower.contains("bike") || lower.contains("cycling") { return .cycling }
        if lower.contains("push-up") || lower.contains("pushup") { return .pushUps }
        if lower.contains("plank") { return .planks }
        if lower.contains("wall sit") { return .wallSits }
        if lower.contains("jump rope") { return .jumpRope }
        if lower.contains("step") { return .steps }
        if lower.contains("gym") || lower.contains("workout") || lower.contains("swim") || lower.contains("martial") || lower.contains("sport") || lower.contains("boxing") { return .gymAndPlaces }
        if lower.contains("cold") || lower.contains("ice bath") || lower.contains("shower") { return .coldAndDiscipline }
        if lower.contains("meditat") || lower.contains("breathing") || lower.contains("silence") { return .meditation }
        if lower.contains("focus") || lower.contains("study") { return .focus }
        if lower.contains("read") || lower.contains("book") || lower.contains("podcast") { return .reading }
        if lower.contains("journal") || lower.contains("gratitude") || lower.contains("letter") { return .journaling }
        if lower.contains("affirm") || lower.contains("vision") { return .affirmations }
        if lower.contains("photo") || lower.contains("texture") { return .photography }
        if lower.contains("detox") || lower.contains("no phone") || lower.contains("offline") || lower.contains("screen") { return .digitalDetox }
        if lower.contains("sketch") || lower.contains("calligraphy") || lower.contains("paint") || lower.contains("playlist") || lower.contains("herb") || lower.contains("press leaves") { return .creative }
        if lower.contains("museum") || lower.contains("park") || lower.contains("visit") || lower.contains("explore") || lower.contains("travel") || lower.contains("day trip") { return .placesExplore }
        if lower.contains("stranger") || lower.contains("compliment") || lower.contains("volunteer") || lower.contains("host") || lower.contains("speak") || lower.contains("reconnect") || lower.contains("conversation") || lower.contains("teach") || lower.contains("open mic") { return .socialExperiences }
        if lower.contains("cook") || lower.contains("recipe") || lower.contains("food") || lower.contains("bread") || lower.contains("pasta") || lower.contains("sauce") || lower.contains("dish") { return .lifestyle }
        if lower.contains("yoga") || lower.contains("stretch") || lower.contains("foam") || lower.contains("core") || lower.contains("stair") || lower.contains("hydrat") || desc.contains("wake") || lower.contains("5am") || lower.contains("discipline") || lower.contains("no junk") || lower.contains("clean eat") || lower.contains("sugar") || lower.contains("competition") || lower.contains("double session") { return .lifestyle }

        return .other
    }

    static func group(_ quests: [Quest]) -> [(category: QuestCategory, quests: [Quest])] {
        var grouped: [QuestCategory: [Quest]] = [:]
        for quest in quests {
            let cat = categorize(quest)
            grouped[cat, default: []].append(quest)
        }
        return grouped
            .sorted { lhs, rhs in
                lhs.value.count > rhs.value.count
            }
            .map { (category: $0.key, quests: $0.value) }
    }
}
