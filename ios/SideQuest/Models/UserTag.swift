import SwiftUI

nonisolated enum UserSkill: String, CaseIterable, Codable, Identifiable, Sendable {
    case charisma = "Charisma"
    case mindfulness = "Mindfulness"
    case discipline = "Discipline"
    case strength = "Strength"
    case endurance = "Endurance"
    case focus = "Focus"
    case intelligence = "Intelligence"
    case creativity = "Creativity"
    case resilience = "Resilience"
    case leadership = "Leadership"

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .charisma: "person.wave.2.fill"
        case .mindfulness: "leaf.fill"
        case .discipline: "shield.fill"
        case .strength: "dumbbell.fill"
        case .endurance: "figure.run"
        case .focus: "scope"
        case .intelligence: "brain.head.profile.fill"
        case .creativity: "paintpalette.fill"
        case .resilience: "bolt.shield.fill"
        case .leadership: "star.fill"
        }
    }

    var description: String {
        switch self {
        case .charisma: "Social confidence & influence"
        case .mindfulness: "Awareness & inner peace"
        case .discipline: "Consistency & willpower"
        case .strength: "Physical power & muscle"
        case .endurance: "Stamina & lasting energy"
        case .focus: "Deep work & concentration"
        case .intelligence: "Sharp thinking & problem-solving"
        case .creativity: "Expression & original ideas"
        case .resilience: "Bouncing back from adversity"
        case .leadership: "Inspiring & guiding others"
        }
    }

    var color: Color {
        switch self {
        case .charisma: .orange
        case .mindfulness: .green
        case .discipline: .red
        case .strength: .red
        case .endurance: .blue
        case .focus: .indigo
        case .intelligence: .purple
        case .creativity: .pink
        case .resilience: .orange
        case .leadership: .yellow
        }
    }
}

nonisolated enum UserInterest: String, CaseIterable, Codable, Identifiable, Sendable {
    case nature = "Nature"
    case animals = "Animals"
    case chess = "Chess"
    case cardio = "Cardio"
    case photography = "Photography"
    case writing = "Writing"
    case fitness = "Fitness"
    case meditation = "Meditation"
    case exploration = "Exploration"
    case brainTraining = "Brain Training"
    case running = "Running"
    case hiking = "Hiking"
    case reading = "Reading"
    case travel = "Travel"
    case art = "Art"
    case yoga = "Yoga"
    case cooking = "Cooking"
    case music = "Music"
    case volunteering = "Volunteering"
    case wellness = "Wellness"
    case spirituality = "Spirituality"
    case outdoors = "Outdoors"

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .nature: "leaf.circle.fill"
        case .animals: "pawprint.fill"
        case .chess: "checkerboard.rectangle"
        case .cardio: "heart.fill"
        case .photography: "camera.fill"
        case .writing: "pencil"
        case .fitness: "figure.strengthtraining.traditional"
        case .meditation: "figure.mind.and.body"
        case .exploration: "map.fill"
        case .brainTraining: "puzzlepiece.fill"
        case .running: "figure.run"
        case .hiking: "figure.hiking"
        case .reading: "book.fill"
        case .travel: "airplane"
        case .art: "paintbrush.fill"
        case .yoga: "figure.yoga"
        case .cooking: "frying.pan.fill"
        case .music: "music.note"
        case .volunteering: "hand.raised.fill"
        case .wellness: "heart.text.clipboard.fill"
        case .spirituality: "sparkles"
        case .outdoors: "sun.max.fill"
        }
    }

    var color: Color {
        switch self {
        case .nature: .green
        case .animals: .brown
        case .chess: .primary
        case .cardio: .red
        case .photography: .cyan
        case .writing: .indigo
        case .fitness: .orange
        case .meditation: .teal
        case .exploration: .blue
        case .brainTraining: .purple
        case .running: .red
        case .hiking: .green
        case .reading: .brown
        case .travel: .blue
        case .art: .pink
        case .yoga: .purple
        case .cooking: .orange
        case .music: .pink
        case .volunteering: .mint
        case .wellness: .teal
        case .spirituality: .indigo
        case .outdoors: .green
        }
    }
}
