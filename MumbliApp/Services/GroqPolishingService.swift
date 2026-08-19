import Foundation

/// Groq LLM polishing service — uses Groq's OpenAI-compatible chat completions API.
/// Extremely fast inference via Groq LPU hardware (~391ms p50 for the current model,
/// see the reasoningEffort comment below — the earlier retired Llama model was ~250ms).
final class GroqPolishingService {
    private let endpoint = "https://api.groq.com/openai/v1/chat/completions"
    /// Groq retired the entire Llama instruct lineup (`llama-3.1-8b-instant` began
    /// returning 404 model_not_found on 2026-08-17). gpt-oss-20b is the fastest
    /// remaining model that preserves the speaker's wording and resists the
    /// prompt-injection probes in the polishing prompt's CRITICAL RULES.
    static let model = "openai/gpt-oss-20b"
    /// gpt-oss is a reasoning model; "low" is the floor Groq accepts (none/off are
    /// rejected). Low keeps reasoning to ~15 chars and roughly halves p50 latency
    /// vs. the default (391ms vs 459ms) — and it never appears in `content`.
    private let reasoningEffort = "low"
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
            "model": Self.model,
            "messages": [
                ["role": "system", "content": effectivePrompt],
                ["role": "user", "content": text],
            ],
            "temperature": temperature,
            "max_tokens": maxTokens,
            "reasoning_effort": reasoningEffort,
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
              let message = firstChoice["message"] as? [String: Any] else {
            throw GroqPolishError.invalidResponse
        }

        // gpt-oss returns its chain-of-thought in a separate `reasoning` field and
        // occasionally returns null `content` on very long inputs (~1 in 5 above
        // 3k chars). Treat that as empty so the caller falls back to the raw
        // transcription rather than surfacing an error.
        return message["content"] as? String ?? ""
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
