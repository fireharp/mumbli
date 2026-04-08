import Foundation

/// Deterministic post-processing guard that detects when the polishing LLM
/// goes off-rails: hallucinating content, repeating phrases, or leaking tags.
///
/// Primary detection: sentence count — polishing REMOVES, it never ADDS sentences.
/// If the output has more sentences than the input, something went wrong.
enum RepetitionGuard {

    struct Result {
        let text: String
        /// True if the guard intervened (fell back to raw transcription).
        let didIntervene: Bool
        let reason: String?
    }

    /// Check polished text against the raw transcription.
    /// Falls back to raw transcription if the polished output looks wrong.
    static func check(polished: String, raw: String) -> Result {
        let polishedTrimmed = polished.trimmingCharacters(in: .whitespacesAndNewlines)
        let rawTrimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)

        // Skip guard for very short texts (< 20 chars) — not enough signal
        guard rawTrimmed.count >= 20 else {
            return Result(text: polishedTrimmed, didIntervene: false, reason: nil)
        }

        // Guard 1: Sentence count — polished should not have MORE sentences than raw.
        // Allow +1 tolerance (LLM might split a run-on sentence).
        let rawSentences = countSentences(rawTrimmed)
        let polishedSentences = countSentences(polishedTrimmed)
        if polishedSentences > rawSentences + 1 {
            let reason = "sentence explosion: raw=\(rawSentences), polished=\(polishedSentences)"
            NSLog("[RepetitionGuard] %@ — falling back to raw", reason)
            return Result(text: rawTrimmed, didIntervene: true, reason: reason)
        }

        // Guard 2: Character length — polished should not be >2x the raw length.
        // Polishing cleans up text; it should never significantly expand it.
        let lengthRatio = Double(polishedTrimmed.count) / Double(max(rawTrimmed.count, 1))
        if lengthRatio > 2.0 {
            let reason = String(format: "length explosion: %.1fx (raw=%d, polished=%d)",
                                lengthRatio, rawTrimmed.count, polishedTrimmed.count)
            NSLog("[RepetitionGuard] %@ — falling back to raw", reason)
            return Result(text: rawTrimmed, didIntervene: true, reason: reason)
        }

        // Guard 3: Tag leakage — output should never contain XML-like tags
        // that come from the system prompt (e.g. <dictation>, <terms>).
        if containsLeakedTags(polishedTrimmed) {
            let reason = "tag leakage detected in output"
            NSLog("[RepetitionGuard] %@ — falling back to raw", reason)
            return Result(text: rawTrimmed, didIntervene: true, reason: reason)
        }

        // Guard 4: URL stripping — spoken dictation should never contain URLs.
        // STT models (especially Whisper) hallucinate URLs like "www.labs.org.au"
        // during low-confidence segments. Strip them from the output.
        let cleaned = stripURLs(polishedTrimmed)
        if cleaned != polishedTrimmed {
            NSLog("[RepetitionGuard] stripped hallucinated URL(s) from output")
            return Result(text: cleaned, didIntervene: true, reason: "stripped hallucinated URL(s)")
        }

        return Result(text: polishedTrimmed, didIntervene: false, reason: nil)
    }

    /// Strip raw transcription of hallucinated URLs before polishing.
    /// Call this on the raw STT output before sending to the polishing LLM.
    static func stripURLs(fromRaw text: String) -> String {
        let cleaned = stripURLs(text)
        if cleaned != text {
            NSLog("[RepetitionGuard] stripped hallucinated URL(s) from raw transcription")
        }
        return cleaned
    }

    // MARK: - Private helpers

    /// Count sentences by splitting on sentence-ending punctuation.
    /// Handles abbreviations and decimals reasonably well.
    private static func countSentences(_ text: String) -> Int {
        // Split on . ! ? followed by space or end-of-string
        let pattern = #"[.!?]+(?:\s|$)"#
        let matches = (try? NSRegularExpression(pattern: pattern))?.numberOfMatches(
            in: text, range: NSRange(text.startIndex..., in: text)
        ) ?? 0
        // At least 1 sentence if there's any text
        return max(matches, text.isEmpty ? 0 : 1)
    }

    /// Check for XML-like tags that shouldn't appear in natural speech output.
    private static func containsLeakedTags(_ text: String) -> Bool {
        // Check for common system prompt tags
        let tagPatterns = ["<dictation>", "</dictation>", "<terms>", "</terms>", "<vocab"]
        return tagPatterns.contains { text.contains($0) }
    }

    /// Strip URLs from text. Matches common URL patterns that STT models hallucinate.
    /// Handles: http(s)://..., www.something.tld, and bare domain.tld patterns.
    private static func stripURLs(_ text: String) -> String {
        // Match http(s) URLs and www. prefixed domains
        let urlPattern = #"https?://\S+|www\.\S+"#
        guard let regex = try? NSRegularExpression(pattern: urlPattern, options: .caseInsensitive) else {
            return text
        }
        let result = regex.stringByReplacingMatches(
            in: text,
            range: NSRange(text.startIndex..., in: text),
            withTemplate: ""
        )
        // Collapse multiple spaces left by removal and trim
        return result.replacingOccurrences(
            of: #"\s{2,}"#, with: " ",
            options: .regularExpression
        ).trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
