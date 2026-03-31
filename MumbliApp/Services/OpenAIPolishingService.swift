import Foundation

/// Polishing preset identifiers, stored in UserDefaults as raw values.
enum PolishingPreset: String, CaseIterable, Identifiable {
    case light = "light"
    case formal = "formal"
    case casual = "casual"
    case verbatim = "verbatim"
    case custom = "custom"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .light: return "Light cleanup"
        case .formal: return "Formal"
        case .casual: return "Casual"
        case .verbatim: return "Verbatim"
        case .custom: return "Custom"
        }
    }

    var prompt: String {
        switch self {
        case .light:
            return """
                You are a text polishing assistant. Clean up this dictated text:
                - Remove filler words (um, uh, like, you know)
                - Fix grammar and punctuation
                - If the speaker corrected themselves (e.g., "at 4, actually 3"), keep only the correction
                - Keep the speaker's voice and intent — do NOT rewrite heavily
                - Output only the cleaned text, nothing else
                """
        case .formal:
            return "Rewrite this dictated text in a formal, professional tone. Fix grammar, remove filler words, use proper punctuation."
        case .casual:
            return "Clean up this dictated text. Keep it casual and conversational. Just fix obvious errors and filler words."
        case .verbatim:
            return "Clean up this dictated text minimally: remove filler words (um, uh, like, you know), fix typos, and add punctuation. Keep the content and wording exactly as spoken otherwise. Output only the cleaned text, nothing else."
        case .custom:
            return "" // Provided by UserDefaults
        }
    }
}

/// Model options for polishing, stored in UserDefaults as raw values.
enum PolishingModel: String, CaseIterable, Identifiable {
    case gpt5_4_nano = "gpt-5.4-nano"
    case gpt5_4_mini = "gpt-5.4-mini"
    case other = "other"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .gpt5_4_nano: return "GPT-5.4 Nano"
        case .gpt5_4_mini: return "GPT-5.4 Mini"
        case .other: return "Other"
        }
    }
}

/// Direct OpenAI API client for text polishing.
final class OpenAIPolishingService {
    private let endpoint = "https://api.openai.com/v1/chat/completions"
    private let temperature = 0.3
    private let maxTokens = 2048

    /// Resolve the model string from UserDefaults.
    static func resolvedModel() -> String {
        let raw = UserDefaults.standard.string(forKey: "polishingModel") ?? PolishingModel.gpt5_4_nano.rawValue
        if raw == PolishingModel.other.rawValue {
            let custom = UserDefaults.standard.string(forKey: "customPolishingModel") ?? ""
            return custom.isEmpty ? PolishingModel.gpt5_4_nano.rawValue : custom
        }
        return raw
    }

    /// Resolve the prompt string from UserDefaults.
    static func resolvedPrompt() -> String {
        let raw = UserDefaults.standard.string(forKey: "polishingPreset") ?? PolishingPreset.light.rawValue
        let preset = PolishingPreset(rawValue: raw) ?? .light
        if preset == .custom {
            let custom = UserDefaults.standard.string(forKey: "customPolishingPrompt") ?? ""
            return custom.isEmpty ? PolishingPreset.light.prompt : custom
        }
        return preset.prompt
    }

    /// Polish raw transcription text using the configured model and prompt.
    func polish(text: String, model: String? = nil, prompt: String? = nil) async throws -> String {
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return ""
        }

        guard let apiKey = KeychainManager.shared.get(key: KeychainManager.openAIAPIKeyKey) else {
            throw OpenAIError.missingAPIKey
        }

        var request = URLRequest(url: URL(string: endpoint)!)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")

        let effectiveModel = model ?? Self.resolvedModel()
        let effectivePrompt = prompt ?? Self.resolvedPrompt()

        let body: [String: Any] = [
            "model": effectiveModel,
            "messages": [
                [
                    "role": "system",
                    "content": effectivePrompt,
                ],
                [
                    "role": "user",
                    "content": text,
                ],
            ],
            "temperature": temperature,
            "max_completion_tokens": maxTokens,
        ]

        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw OpenAIError.invalidResponse
        }

        guard httpResponse.statusCode == 200 else {
            let errorBody = String(data: data, encoding: .utf8) ?? "Unknown error"
            throw OpenAIError.apiError(statusCode: httpResponse.statusCode, message: errorBody)
        }

        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let choices = json["choices"] as? [[String: Any]],
              let firstChoice = choices.first,
              let message = firstChoice["message"] as? [String: Any],
              let content = message["content"] as? String else {
            throw OpenAIError.invalidResponse
        }

        return content
    }
}

enum OpenAIError: Error, LocalizedError {
    case missingAPIKey
    case invalidResponse
    case apiError(statusCode: Int, message: String)

    var errorDescription: String? {
        switch self {
        case .missingAPIKey:
            return "OpenAI API key not configured. Add it in Settings."
        case .invalidResponse:
            return "Invalid response from OpenAI API"
        case .apiError(let statusCode, let message):
            return "OpenAI API error (\(statusCode)): \(message)"
        }
    }
}
