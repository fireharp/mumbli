import Foundation

/// Direct OpenAI API client for text polishing via GPT-4o-mini.
final class OpenAIPolishingService {
    private let endpoint = "https://api.openai.com/v1/chat/completions"
    private let model = "gpt-4o-mini"
    private let temperature = 0.3
    private let maxTokens = 2048

    private let polishingPrompt = """
        You are a text polishing assistant. Clean up this dictated text:
        - Remove filler words (um, uh, like, you know)
        - Fix grammar and punctuation
        - If the speaker corrected themselves (e.g., "at 4, actually 3"), keep only the correction
        - Keep the speaker's voice and intent — do NOT rewrite heavily
        - Output only the cleaned text, nothing else
        """

    /// Polish raw transcription text using GPT-4o-mini.
    func polish(text: String) async throws -> String {
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

        let body: [String: Any] = [
            "model": model,
            "messages": [
                [
                    "role": "system",
                    "content": polishingPrompt,
                ],
                [
                    "role": "user",
                    "content": "Dictated text: \(text)",
                ],
            ],
            "temperature": temperature,
            "max_tokens": maxTokens,
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
