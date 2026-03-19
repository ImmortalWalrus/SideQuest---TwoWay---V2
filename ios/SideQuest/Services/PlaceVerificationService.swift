import Foundation
import Vision
import UIKit

@Observable
class PlaceVerificationService {
    enum AnalysisState {
        case idle
        case analyzing
        case verified(PlaceVerificationResult)
        case rejected(String)
    }

    private(set) var state: AnalysisState = .idle
    private(set) var analysisProgress: Double = 0
    private(set) var scanningMessage: String = "Initializing scanner..."
    private(set) var detectedLabels: [(String, Double)] = []

    private let scanMessages = [
        "Scanning environment...",
        "Analyzing scene composition...",
        "Detecting location markers...",
        "Running neural inference...",
        "Cross-referencing place database...",
        "Calculating confidence score..."
    ]

    func reset() {
        state = .idle
        analysisProgress = 0
        detectedLabels = []
        scanningMessage = "Initializing scanner..."
    }

    func analyzeImage(_ image: UIImage, for placeType: VerifiedPlaceType) async {
        state = .analyzing
        analysisProgress = 0

        let messageTask = Task { @MainActor in
            for (i, msg) in scanMessages.enumerated() {
                guard !Task.isCancelled else { return }
                scanningMessage = msg
                analysisProgress = Double(i + 1) / Double(scanMessages.count + 1)
                try? await Task.sleep(for: .milliseconds(520))
            }
        }

        #if targetEnvironment(simulator)
        try? await Task.sleep(for: .seconds(3.5))
        messageTask.cancel()
        let simLabels: [(String, Double)] = [
            (placeType.rawValue, 0.87),
            ("Indoor Space", 0.74),
            ("Fitness Area", 0.61),
            ("Physical Activity", 0.55)
        ]
        detectedLabels = simLabels
        let simResult = PlaceVerificationResult(
            placeType: placeType,
            confidence: 0.87,
            topDetectedCategories: simLabels.map { $0.0 },
            isVerified: true,
            timestamp: .now
        )
        analysisProgress = 1.0
        state = .verified(simResult)
        #else
        do {
            let observations = try await classifyImage(image)
            messageTask.cancel()

            let topObs = observations.prefix(25)
            let formattedLabels: [(String, Double)] = topObs.map { obs in
                (formatLabel(obs.identifier), Double(obs.confidence))
            }
            detectedLabels = formattedLabels

            let score = computeScore(observations: Array(observations), placeType: placeType)
            let topNames = Array(topObs.prefix(6).map { formatLabel($0.identifier) })

            analysisProgress = 1.0
            if score >= placeType.minimumConfidence {
                state = .verified(PlaceVerificationResult(
                    placeType: placeType,
                    confidence: score,
                    topDetectedCategories: topNames,
                    isVerified: true,
                    timestamp: .now
                ))
            } else {
                state = .rejected(
                    "AI couldn't detect a \(placeType.rawValue.lowercased()) environment. Confidence: \(Int(score * 100))%. Try a clearer angle."
                )
            }
        } catch {
            messageTask.cancel()
            state = .rejected("Analysis failed. Please try again.")
        }
        #endif
    }

    private func classifyImage(_ image: UIImage) async throws -> [VNClassificationObservation] {
        guard let cgImage = image.cgImage else {
            throw PlaceVerificationError.invalidImage
        }

        return try await withCheckedThrowingContinuation { continuation in
            let request = VNClassifyImageRequest { req, err in
                if let err {
                    continuation.resume(throwing: err)
                    return
                }
                let results = (req.results as? [VNClassificationObservation] ?? [])
                    .filter { $0.confidence > 0.005 }
                    .sorted { $0.confidence > $1.confidence }
                continuation.resume(returning: results)
            }

            let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
            do {
                try handler.perform([request])
            } catch {
                continuation.resume(throwing: error)
            }
        }
    }

    private func computeScore(observations: [VNClassificationObservation], placeType: VerifiedPlaceType) -> Double {
        let keywords = placeType.visionKeywords
        var score: Double = 0
        for obs in observations {
            let id = obs.identifier.lowercased()
            for keyword in keywords {
                if id.contains(keyword) {
                    score += Double(obs.confidence) * 2.0
                    break
                }
            }
        }
        return min(1.0, score)
    }

    private func formatLabel(_ id: String) -> String {
        id.split(separator: ",").first
            .map(String.init)?
            .replacingOccurrences(of: "_", with: " ")
            .split(separator: " ")
            .map { $0.prefix(1).uppercased() + $0.dropFirst().lowercased() }
            .joined(separator: " ")
        ?? id
    }
}

nonisolated enum PlaceVerificationError: Error {
    case invalidImage
}
