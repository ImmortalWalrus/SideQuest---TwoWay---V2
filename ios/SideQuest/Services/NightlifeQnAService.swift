import Foundation

nonisolated enum NightlifeAIProvider: String, Sendable {
    case gemini
    case perplexity
}

nonisolated enum NightlifeAIQuestion: String, CaseIterable, Sendable {
    case womenAtDoorFree = "women_at_door_free"
    case menAtDoorFree = "men_at_door_free"

    var title: String {
        switch self {
        case .womenAtDoorFree:
            return "Women at Door / Free?"
        case .menAtDoorFree:
            return "Men at Door / Free?"
        }
    }

    var iconName: String {
        switch self {
        case .womenAtDoorFree, .menAtDoorFree:
            return "sparkles.rectangle.stack.fill"
        }
    }

    var loadingCopy: String {
        switch self {
        case .womenAtDoorFree, .menAtDoorFree:
            return "Loading answer..."
        }
    }

    var tapCopy: String {
        switch self {
        case .womenAtDoorFree, .menAtDoorFree:
            return "Tap to reveal answer."
        }
    }
}

nonisolated struct NightlifeAIAnswer: Sendable {
    let text: String
    let generatedAt: Date
}

nonisolated struct NightlifeAIConfiguration: Sendable {
    var provider: NightlifeAIProvider
    var perplexityAPIKey: String?
    var perplexityModel: String
    var perplexityBaseURL: URL
    var geminiAPIKey: String?
    var geminiModel: String
    var geminiBaseURL: URL

    static func fromEnvironment() -> NightlifeAIConfiguration {
        let env = ProcessInfo.processInfo.environment
        let runtimeSecrets = NightlifeRuntimeSecretsStore.load()
        let perplexityAPIKey = env["PERPLEXITY_API_KEY"] ?? runtimeSecrets["PERPLEXITY_API_KEY"]
        let geminiAPIKey = env["GEMINI_API_KEY"] ?? runtimeSecrets["GEMINI_API_KEY"]
        let configuredProvider = (env["NIGHTLIFE_AI_PROVIDER"] ?? runtimeSecrets["NIGHTLIFE_AI_PROVIDER"])
            .flatMap { NightlifeAIProvider(rawValue: $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()) }
        let provider = configuredProvider ?? (perplexityAPIKey?.isEmpty == false ? .perplexity : .gemini)
        return NightlifeAIConfiguration(
            provider: provider,
            perplexityAPIKey: perplexityAPIKey,
            perplexityModel: env["PERPLEXITY_MODEL"] ?? runtimeSecrets["PERPLEXITY_MODEL"] ?? "sonar",
            perplexityBaseURL: URL(string: env["PERPLEXITY_BASE_URL"] ?? runtimeSecrets["PERPLEXITY_BASE_URL"] ?? "https://api.perplexity.ai")!,
            geminiAPIKey: geminiAPIKey,
            geminiModel: env["GEMINI_MODEL"] ?? runtimeSecrets["GEMINI_MODEL"] ?? "gemini-2.5-flash",
            geminiBaseURL: URL(string: env["GEMINI_BASE_URL"] ?? runtimeSecrets["GEMINI_BASE_URL"] ?? "https://generativelanguage.googleapis.com/v1beta")!
        )
    }

    var activeAPIKey: String? {
        switch provider {
        case .gemini:
            return geminiAPIKey
        case .perplexity:
            return perplexityAPIKey
        }
    }
}

private enum NightlifeRuntimeSecretsStore {
    private static let fileName = "NightlifeAISecrets.plist"

    static func load() -> [String: String] {
        guard
            let applicationSupportURL = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first,
            let data = try? Data(contentsOf: applicationSupportURL.appendingPathComponent(fileName)),
            let payload = try? PropertyListSerialization.propertyList(from: data, options: [], format: nil) as? [String: String]
        else {
            return [:]
        }
        return payload
    }
}

enum NightlifeQnAError: LocalizedError {
    case missingAPIKey
    case invalidRequest
    case invalidResponse
    case emptyResponse
    case providerError(String)

    var errorDescription: String? {
        switch self {
        case .missingAPIKey:
            return "AI answers are unavailable in this build."
        case .invalidRequest:
            return "Could not prepare the nightlife question."
        case .invalidResponse:
            return "The AI answer came back in an unexpected format."
        case .emptyResponse:
            return "No answer was returned."
        case let .providerError(message):
            return message
        }
    }
}

actor NightlifeQnAService {
    static let shared = NightlifeQnAService(configuration: .fromEnvironment())

    private let configuration: NightlifeAIConfiguration
    private let session: URLSession
    private var cachedAnswers: [String: NightlifeAIAnswer] = [:]

    init(
        configuration: NightlifeAIConfiguration,
        session: URLSession? = nil
    ) {
        self.configuration = configuration
        if let session {
            self.session = session
        } else {
            let sessionConfiguration = URLSessionConfiguration.ephemeral
            sessionConfiguration.timeoutIntervalForRequest = 18
            sessionConfiguration.timeoutIntervalForResource = 24
            self.session = URLSession(configuration: sessionConfiguration)
        }
    }

    func answer(for event: ExternalEvent, question: NightlifeAIQuestion) async throws -> NightlifeAIAnswer {
        let cacheKey = makeCacheKey(for: event, question: question)
        if let cached = cachedAnswers[cacheKey] {
            return cached
        }

        guard let activeAPIKey = configuration.activeAPIKey, !activeAPIKey.isEmpty else {
            throw NightlifeQnAError.missingAPIKey
        }

        let prompt = makePrompt(for: event, question: question)
        guard !prompt.userPrompt.isEmpty else {
            throw NightlifeQnAError.invalidRequest
        }

        do {
            let firstPass = try await performRequest(
                apiKey: activeAPIKey,
                systemPrompt: prompt.systemPrompt,
                userPrompt: prompt.userPrompt,
                maxOutputTokens: 220
            )

            let finalText: String
            if NightlifeQnAService.isProbablyTruncated(firstPass.text, finishReason: firstPass.finishReason) {
                let secondPass = try await performRequest(
                    apiKey: activeAPIKey,
                    systemPrompt: prompt.systemPrompt,
                    userPrompt: prompt.userPrompt,
                    maxOutputTokens: 360
                )
                finalText = secondPass.text.count > firstPass.text.count ? secondPass.text : firstPass.text
            } else {
                finalText = firstPass.text
            }

            let cleanedAnswer = NightlifeQnAService.cleanedAnswer(finalText)
            guard !cleanedAnswer.isEmpty else {
                throw NightlifeQnAError.emptyResponse
            }

            let answer = NightlifeAIAnswer(text: cleanedAnswer, generatedAt: Date())
            cachedAnswers[cacheKey] = answer
            return answer
        } catch let error as NightlifeQnAError {
            throw error
        } catch {
            throw NightlifeQnAError.providerError(error.localizedDescription)
        }
    }

    private func performRequest(
        apiKey: String,
        systemPrompt: String,
        userPrompt: String,
        maxOutputTokens: Int
    ) async throws -> (text: String, finishReason: String?) {
        switch configuration.provider {
        case .gemini:
            return try await performGeminiRequest(
                apiKey: apiKey,
                systemPrompt: systemPrompt,
                userPrompt: userPrompt,
                maxOutputTokens: maxOutputTokens
            )
        case .perplexity:
            return try await performPerplexityRequest(
                apiKey: apiKey,
                systemPrompt: systemPrompt,
                userPrompt: userPrompt,
                maxOutputTokens: maxOutputTokens
            )
        }
    }

    private func performGeminiRequest(
        apiKey: String,
        systemPrompt: String,
        userPrompt: String,
        maxOutputTokens: Int
    ) async throws -> (text: String, finishReason: String?) {
        let endpoint = configuration.geminiBaseURL
            .appendingPathComponent("models")
            .appendingPathComponent("\(configuration.geminiModel):generateContent")
        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(apiKey, forHTTPHeaderField: "x-goog-api-key")

        let payload: [String: Any] = [
            "systemInstruction": [
                "parts": [
                    ["text": systemPrompt]
                ]
            ],
            "contents": [
                [
                    "role": "user",
                    "parts": [
                        ["text": userPrompt]
                    ]
                ]
            ],
            "tools": [
                ["google_search": [:]]
            ],
            "generationConfig": [
                "temperature": 0.1,
                "topP": 0.8,
                "maxOutputTokens": maxOutputTokens,
                "responseMimeType": "text/plain"
            ]
        ]
        request.httpBody = try? JSONSerialization.data(withJSONObject: payload, options: [.sortedKeys])

        let (data, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw NightlifeQnAError.invalidResponse
        }

        guard (200 ..< 300).contains(httpResponse.statusCode) else {
            let message = NightlifeQnAService.providerErrorMessage(from: data)
                ?? "AI answer request failed with status \(httpResponse.statusCode)."
            throw NightlifeQnAError.providerError(message)
        }

        guard
            let root = try JSONSerialization.jsonObject(with: data) as? [String: Any],
            let candidates = root["candidates"] as? [[String: Any]],
            let firstCandidate = candidates.first,
            let content = firstCandidate["content"] as? [String: Any],
            let parts = content["parts"] as? [[String: Any]]
        else {
            throw NightlifeQnAError.invalidResponse
        }

        let rawAnswer = parts
            .compactMap { $0["text"] as? String }
            .joined(separator: "\n")
        let finishReason = firstCandidate["finishReason"] as? String
        return (rawAnswer, finishReason)
    }

    private func performPerplexityRequest(
        apiKey: String,
        systemPrompt: String,
        userPrompt: String,
        maxOutputTokens: Int
    ) async throws -> (text: String, finishReason: String?) {
        let endpoint = configuration.perplexityBaseURL
            .appendingPathComponent("chat")
            .appendingPathComponent("completions")
        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")

        let payload: [String: Any] = [
            "model": configuration.perplexityModel,
            "messages": [
                [
                    "role": "system",
                    "content": systemPrompt
                ],
                [
                    "role": "user",
                    "content": userPrompt
                ]
            ],
            "stream": false,
            "temperature": 0.1,
            "top_p": 0.8,
            "max_tokens": maxOutputTokens,
            "web_search_options": [
                "search_context_size": "low"
            ]
        ]
        request.httpBody = try? JSONSerialization.data(withJSONObject: payload, options: [.sortedKeys])

        let (data, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw NightlifeQnAError.invalidResponse
        }

        guard (200 ..< 300).contains(httpResponse.statusCode) else {
            let message = NightlifeQnAService.providerErrorMessage(from: data)
                ?? "AI answer request failed with status \(httpResponse.statusCode)."
            throw NightlifeQnAError.providerError(message)
        }

        guard
            let root = try JSONSerialization.jsonObject(with: data) as? [String: Any],
            let choices = root["choices"] as? [[String: Any]],
            let firstChoice = choices.first,
            let message = firstChoice["message"] as? [String: Any],
            let rawAnswer = NightlifeQnAService.perplexityMessageText(from: message["content"])
        else {
            throw NightlifeQnAError.invalidResponse
        }

        let finishReason = firstChoice["finish_reason"] as? String
        return (rawAnswer, finishReason)
    }

    private func makeCacheKey(for event: ExternalEvent, question: NightlifeAIQuestion) -> String {
        [
            question.rawValue,
            event.venueName ?? event.title,
            event.city ?? "",
            event.state ?? ""
        ]
        .joined(separator: "|")
    }

    private func makePrompt(for event: ExternalEvent, question: NightlifeAIQuestion) -> (systemPrompt: String, userPrompt: String) {
        let systemPrompt = """
        Use live web search to answer nightlife access questions.
        Never invent facts.
        Give the practical answer first, then mention the main conditions that affect entry.
        Keep the answer to 3-5 short sentences, plain English, no bullets, no raw citations.
        Focus on whether the asked gender usually pays, whether guest list can make entry free or reduced, arrival timing, dress code, doorman discretion, bottle service, and hotel-guest exceptions if relevant.
        If it varies by night, say that clearly.
        """

        let questionPrompt: String
        switch question {
        case .womenAtDoorFree:
            questionPrompt = "Do women have to pay to get into \(event.venueName ?? event.title) in \([event.city, event.state].compactMap { $0 }.joined(separator: ", "))?"
        case .menAtDoorFree:
            questionPrompt = "Do men have to pay to get into \(event.venueName ?? event.title) in \([event.city, event.state].compactMap { $0 }.joined(separator: ", "))?"
        }

        let userPrompt = questionPrompt

        return (systemPrompt, userPrompt)
    }

    private static func cleanedAnswer(_ answer: String) -> String {
        let plain = ExternalEventSupport.plainText(answer) ?? answer
        let compact = plain
            .replacingOccurrences(of: "\n\n+", with: "\n", options: .regularExpression)
            .replacingOccurrences(of: #"(?<![.!?])\n"#, with: " ", options: .regularExpression)
            .replacingOccurrences(of: #"\*\*(.*?)\*\*"#, with: "$1", options: .regularExpression)
            .replacingOccurrences(of: #"\[(?:\d+(?:\s*,\s*\d+)*)\]"#, with: "", options: .regularExpression)
            .replacingOccurrences(of: #"\s+([.,!?])"#, with: "$1", options: .regularExpression)
            .replacingOccurrences(of: #" {2,}"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)

        return compact
    }

    private static func isProbablyTruncated(_ answer: String, finishReason: String?) -> Bool {
        let trimmed = answer.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return false }

        if let finishReason,
           ["MAX_TOKENS", "max_tokens", "length"].contains(finishReason) {
            return true
        }

        if let lastScalar = trimmed.unicodeScalars.last,
           CharacterSet.letters.contains(lastScalar),
           !trimmed.hasSuffix("."),
           !trimmed.hasSuffix("!"),
           !trimmed.hasSuffix("?") {
            return true
        }

        return false
    }

    private static func providerErrorMessage(from data: Data) -> String? {
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }

        if let error = object["error"] as? [String: Any],
           let message = error["message"] as? String,
           !message.isEmpty {
            return message
        }
        if let error = object["error"] as? String, !error.isEmpty {
            return error
        }
        if let message = object["message"] as? String, !message.isEmpty {
            return message
        }
        return nil
    }

    private static func perplexityMessageText(from content: Any?) -> String? {
        if let content = content as? String, !content.isEmpty {
            return content
        }
        if let contentParts = content as? [[String: Any]] {
            let text = contentParts
                .compactMap { part -> String? in
                    if let text = part["text"] as? String, !text.isEmpty {
                        return text
                    }
                    return nil
                }
                .joined(separator: "\n")
            return text.isEmpty ? nil : text
        }
        return nil
    }
}
