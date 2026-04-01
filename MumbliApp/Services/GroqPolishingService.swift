import Foundation

/// Groq LLM polishing service — uses Groq's OpenAI-compatible chat completions API.
/// Extremely fast inference (~250ms) via Groq LPU hardware.
final class GroqPolishingService {
    private let endpoint = "https://api.groq.com/openai/v1/chat/completions"
    private let model = "llama-3.1-8b-instant"
    private let temperature = 0.3
    private let maxTokens = 2048

    func polish(text: String, prompt: String? = nil) async throws -> String {
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return ""
        }

        guard let apiKey = KeychainManager.shared.get(key: KeychainManager.groqAPIKeyKey) else {
            throw GroqPolishError.missingAPIKey
        }

        let effectivePrompt = prompt ?? OpenAIPolishingService.resolvedPrompt()

        var request = URLRequest(url: URL(string: endpoint)!)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")

        let body: [String: Any] = [
            "model": model,
            "messages": [
                ["role": "system", "content": effectivePrompt],
                ["role": "user", "content": text],
            ],
            "temperature": temperature,
            "max_tokens": maxTokens,
        ]

        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw GroqPolishError.invalidResponse
        }

        guard httpResponse.statusCode == 200 else {
            let errorBody = String(data: data, encoding: .utf8) ?? "Unknown error"
            throw GroqPolishError.apiError(statusCode: httpResponse.statusCode, message: errorBody)
        }

        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let choices = json["choices"] as? [[String: Any]],
              let firstChoice = choices.first,
              let message = firstChoice["message"] as? [String: Any],
              let content = message["content"] as? String else {
            throw GroqPolishError.invalidResponse
        }

        return content
    }
}

enum GroqPolishError: Error, LocalizedError {
    case missingAPIKey
    case invalidResponse
    case apiError(statusCode: Int, message: String)

    var errorDescription: String? {
        switch self {
        case .missingAPIKey:
            return "Groq API key not configured. Add it in Settings."
        case .invalidResponse:
            return "Invalid response from Groq API"
        case .apiError(let statusCode, let message):
            return "Groq API error (\(statusCode)): \(message)"
        }
    }
}
