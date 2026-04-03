import Foundation

enum VocabularyStore {
    private static let key = "customVocabulary"
    private static let maxWhisperWords = 100

    static func words() -> [String] {
        UserDefaults.standard.stringArray(forKey: key) ?? []
    }

    static func save(_ words: [String]) {
        UserDefaults.standard.set(words, forKey: key)
    }

    /// Comma-separated vocabulary for Whisper prompt parameter (224 token limit).
    static func whisperPrompt() -> String? {
        let w = words()
        guard !w.isEmpty else { return nil }
        return Array(w.prefix(maxWhisperWords)).joined(separator: ", ")
    }

    /// Vocabulary instruction snippet for polishing system prompts.
    static func polishingSnippet() -> String? {
        let w = words()
        guard !w.isEmpty else { return nil }
        return "\n<terms>\nCustom vocabulary (use these exact spellings when they appear in the text): \(w.joined(separator: ", "))\n</terms>"
    }
}
