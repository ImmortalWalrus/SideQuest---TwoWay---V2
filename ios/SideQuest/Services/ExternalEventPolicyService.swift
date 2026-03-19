import Foundation

nonisolated enum ExternalEventVerificationMethod: String, Codable, CaseIterable, Sendable {
    case placeCheckIn = "Place Check-In"
    case placeAndPhoto = "Place + Photo"
    case gpsAndPlace = "GPS + Place"
    case gpsOrHealth = "GPS or Health"
}

nonisolated struct ExternalEventRewardPolicy: Hashable, Sendable {
    let xp: Int
    let coins: Int
    let diamonds: Int
    let verificationMethod: ExternalEventVerificationMethod
    let verificationRadiusMeters: Int
    let verificationOpensMinutesBefore: Int
    let verificationClosesMinutesAfter: Int

    var verificationSummary: String {
        "\(verificationMethod.rawValue) • \(verificationRadiusMeters)m radius"
    }
}

enum ExternalEventPolicyService {
    static func policy(for event: ExternalEvent) -> ExternalEventRewardPolicy {
        switch event.eventType {
        case .groupRun:
            return ExternalEventRewardPolicy(
                xp: 180,
                coins: 55,
                diamonds: 1,
                verificationMethod: .gpsOrHealth,
                verificationRadiusMeters: 250,
                verificationOpensMinutesBefore: 45,
                verificationClosesMinutesAfter: 180
            )
        case .race5k:
            return ExternalEventRewardPolicy(
                xp: 320,
                coins: 90,
                diamonds: 1,
                verificationMethod: .gpsAndPlace,
                verificationRadiusMeters: 300,
                verificationOpensMinutesBefore: 60,
                verificationClosesMinutesAfter: 240
            )
        case .race10k:
            return ExternalEventRewardPolicy(
                xp: 520,
                coins: 140,
                diamonds: 2,
                verificationMethod: .gpsAndPlace,
                verificationRadiusMeters: 350,
                verificationOpensMinutesBefore: 75,
                verificationClosesMinutesAfter: 300
            )
        case .raceHalfMarathon:
            return ExternalEventRewardPolicy(
                xp: 980,
                coins: 260,
                diamonds: 4,
                verificationMethod: .gpsAndPlace,
                verificationRadiusMeters: 400,
                verificationOpensMinutesBefore: 90,
                verificationClosesMinutesAfter: 360
            )
        case .raceMarathon:
            return ExternalEventRewardPolicy(
                xp: 1900,
                coins: 520,
                diamonds: 8,
                verificationMethod: .gpsAndPlace,
                verificationRadiusMeters: 500,
                verificationOpensMinutesBefore: 120,
                verificationClosesMinutesAfter: 480
            )
        case .concert:
            return ExternalEventRewardPolicy(
                xp: 150,
                coins: 45,
                diamonds: 1,
                verificationMethod: .placeCheckIn,
                verificationRadiusMeters: 250,
                verificationOpensMinutesBefore: 60,
                verificationClosesMinutesAfter: 180
            )
        case .sportsEvent:
            return ExternalEventRewardPolicy(
                xp: 190,
                coins: 60,
                diamonds: 1,
                verificationMethod: .placeCheckIn,
                verificationRadiusMeters: 300,
                verificationOpensMinutesBefore: 90,
                verificationClosesMinutesAfter: 210
            )
        case .partyNightlife:
            return ExternalEventRewardPolicy(
                xp: 125,
                coins: 35,
                diamonds: 1,
                verificationMethod: .placeCheckIn,
                verificationRadiusMeters: 200,
                verificationOpensMinutesBefore: 45,
                verificationClosesMinutesAfter: 180
            )
        case .weekendActivity:
            return ExternalEventRewardPolicy(
                xp: 170,
                coins: 50,
                diamonds: 1,
                verificationMethod: .placeCheckIn,
                verificationRadiusMeters: 250,
                verificationOpensMinutesBefore: 60,
                verificationClosesMinutesAfter: 240
            )
        case .socialCommunityEvent:
            return ExternalEventRewardPolicy(
                xp: 210,
                coins: 70,
                diamonds: 2,
                verificationMethod: .placeAndPhoto,
                verificationRadiusMeters: 250,
                verificationOpensMinutesBefore: 60,
                verificationClosesMinutesAfter: 240
            )
        case .otherLiveEvent:
            return ExternalEventRewardPolicy(
                xp: 135,
                coins: 40,
                diamonds: 1,
                verificationMethod: .placeCheckIn,
                verificationRadiusMeters: 250,
                verificationOpensMinutesBefore: 60,
                verificationClosesMinutesAfter: 240
            )
        }
    }
}
