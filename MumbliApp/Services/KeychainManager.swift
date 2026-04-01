import Foundation

/// Stores API keys in UserDefaults for zero-prompt access.
/// Not as secure as Keychain but avoids constant permission dialogs.
/// Acceptable for a personal-use tool where the user is the sole operator.
final class KeychainManager {
    static let shared = KeychainManager()

    static let elevenLabsAPIKeyKey = "com.mumbli.elevenlabs-api-key"
    static let openAIAPIKeyKey = "com.mumbli.openai-api-key"
    static let groqAPIKeyKey = "com.mumbli.groq-api-key"

    private let defaults = UserDefaults.standard

    private init() {}

    func save(key: String, value: String) throws {
        defaults.set(value, forKey: key)
    }

    func get(key: String) -> String? {
        return defaults.string(forKey: key)
    }

    func delete(key: String) {
        defaults.removeObject(forKey: key)
    }
}

enum KeychainError: Error, LocalizedError {
    case encodingFailed
    case saveFailed(OSStatus)

    var errorDescription: String? {
        switch self {
        case .encodingFailed:
            return "Failed to encode value"
        case .saveFailed(let status):
            return "Save failed with status \(status)"
        }
    }
}
