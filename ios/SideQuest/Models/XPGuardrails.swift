import Foundation

nonisolated enum XPGuardrails: Sendable {
    static let softDailyCap: Int = 800
    static let hardDailyCap: Int = 1000
    static let softCapReductionFactor: Double = 0.25

    static func applyDailyCap(rawXP: Int, alreadyEarnedToday: Int) -> Int {
        guard rawXP > 0 else { return 0 }
        let remaining = hardDailyCap - alreadyEarnedToday
        guard remaining > 0 else { return 0 }

        if alreadyEarnedToday >= softDailyCap {
            let reduced = Int(Double(rawXP) * softCapReductionFactor)
            return min(max(reduced, 1), remaining)
        }

        let xpToSoftCap = softDailyCap - alreadyEarnedToday
        if rawXP <= xpToSoftCap {
            return rawXP
        }

        let fullPortion = xpToSoftCap
        let overflowRaw = rawXP - xpToSoftCap
        let reducedPortion = Int(Double(overflowRaw) * softCapReductionFactor)
        let total = fullPortion + reducedPortion
        return min(total, remaining)
    }

    static func campaignCompletionBonus(difficulty: QuestDifficulty, baseXP: Int) -> Int {
        let percent: Double = switch difficulty {
        case .easy: 0.20
        case .medium: 0.30
        case .hard: 0.40
        case .expert: 0.50
        }
        return Int(Double(baseXP) * percent)
    }

    static func campaignEarlyCompletionBonus(difficulty: QuestDifficulty, baseXP: Int) -> Int {
        let percent: Double = switch difficulty {
        case .easy: 0.05
        case .medium: 0.08
        case .hard: 0.10
        case .expert: 0.0
        }
        return Int(Double(baseXP) * percent)
    }

    static func questXPRange(for difficulty: QuestDifficulty) -> ClosedRange<Int> {
        switch difficulty {
        case .easy: 90...140
        case .medium: 200...280
        case .hard: 380...500
        case .expert: 680...900
        }
    }
}
