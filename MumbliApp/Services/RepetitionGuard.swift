import Foundation

/// Deterministic post-processing guard that detects when the polishing LLM
/// goes off-rails: hallucinating content, repeating phrases, or leaking tags.
///
/// Primary detection: **word novelty** — the fraction of output words that do not
/// appear in the raw transcription. Polishing adds punctuation and removes fillers;
/// it does not introduce vocabulary. Every real failure mode (the model answering
/// the dictation, refusing, translating, or looping) shows up as novel words.
///
/// This replaced an earlier sentence-count rule ("polishing never ADDS sentences").
/// That premise was wrong: Whisper returns unpunctuated run-ons, so *correct*
/// polishing necessarily raises the sentence count. Calibrated against 4657 real
/// (raw, polished) pairs from mumbli.log, the sentence rule flagged 7.1% of all
/// dictations while catching 0 of the 7 genuine failures the other guards caught;
/// the rules below flag 1.2% and catch 11/11.
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

        // Guard 1: Tag leakage — output should never contain XML-like tags
        // that come from the system prompt (e.g. <dictation>, <terms>).
        // Checked BEFORE the short-input bail-out below: a 12-char raw once polished
        // to a bare "</dictation>", which the old length-gated ordering let through.
        if containsLeakedTags(polishedTrimmed) {
            let reason = "tag leakage detected in output"
            NSLog("[RepetitionGuard] %@ — falling back to raw", reason)
            return Result(text: rawTrimmed, didIntervene: true, reason: reason)
        }

        // Skip the statistical guards for very short texts (< 20 chars) — not enough
        // signal. Tag leakage (above) and URL stripping (below) still apply.
        guard rawTrimmed.count >= 20 else {
            return Result(text: polishedTrimmed, didIntervene: false, reason: nil)
        }

        // Guard 2: Invention — polishing must not introduce vocabulary the speaker
        // never used. Real polishes sit at p95 novelty 0.09; failures (the model
        // answering, refusing, or translating the dictation) run 0.56–1.00.
        let novelty = wordNovelty(polished: polishedTrimmed, raw: rawTrimmed)
        if novelty > 0.4 {
            let reason = String(format: "invention: %.0f%% of output words absent from raw", novelty * 100)
            NSLog("[RepetitionGuard] %@ — falling back to raw", reason)
            return Result(text: rawTrimmed, didIntervene: true, reason: reason)
        }

        // Guard 3: Character length — polished should not be >2x the raw length.
        // Polishing cleans up text; it should never significantly expand it.
        let lengthRatio = Double(polishedTrimmed.count) / Double(max(rawTrimmed.count, 1))
        if lengthRatio > 2.0 {
            let reason = String(format: "length explosion: %.1fx (raw=%d, polished=%d)",
                                lengthRatio, rawTrimmed.count, polishedTrimmed.count)
            NSLog("[RepetitionGuard] %@ — falling back to raw", reason)
            return Result(text: rawTrimmed, didIntervene: true, reason: reason)
        }

        // Guard 4: Truncation — the speaker's words must survive. Filler removal
        // costs a few percent; dropping >40% means the model summarised or answered
        // instead of polishing. The old guard was blind to this entirely.
        let retention = wordRetention(polished: polishedTrimmed, raw: rawTrimmed)
        if retention < 0.6 {
            let reason = String(format: "truncation: only %.0f%% of spoken words retained", retention * 100)
            NSLog("[RepetitionGuard] %@ — falling back to raw", reason)
            return Result(text: rawTrimmed, didIntervene: true, reason: reason)
        }

        // Guard 5: URL stripping — spoken dictation should never contain URLs.
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

    /// Lowercased word tokens, punctuation stripped. Apostrophes are kept so
    /// "don't" stays one token and a contraction change reads as a substitution.
    private static func tokenize(_ text: String) -> [String] {
        return text.lowercased()
            .components(separatedBy: CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyz0123456789'").inverted)
            .filter { !$0.isEmpty }
    }

    /// Multiset word counts, used by both novelty and retention.
    private static func counts(_ tokens: [String]) -> [String: Int] {
        var c: [String: Int] = [:]
        for t in tokens { c[t, default: 0] += 1 }
        return c
    }

    /// Fraction of the polished output's words that do NOT appear in the raw
    /// transcription (counting repeats, so a repetition loop scores high).
    /// 0.0 = every output word was spoken; 1.0 = entirely invented.
    private static func wordNovelty(polished: String, raw: String) -> Double {
        let outTokens = tokenize(polished)
        guard !outTokens.isEmpty else { return 0.0 }
        let rawCounts = counts(tokenize(raw))
        var novel = 0
        for (word, count) in counts(outTokens) {
            novel += max(0, count - (rawCounts[word] ?? 0))
        }
        return Double(novel) / Double(outTokens.count)
    }

    /// Fraction of the raw transcription's words that survive into the output.
    /// 1.0 = every spoken word preserved; low values mean summarised or dropped.
    private static func wordRetention(polished: String, raw: String) -> Double {
        let rawTokens = tokenize(raw)
        guard !rawTokens.isEmpty else { return 1.0 }
        let outCounts = counts(tokenize(polished))
        var kept = 0
        for (word, count) in counts(rawTokens) {
            kept += min(count, outCounts[word] ?? 0)
        }
        return Double(kept) / Double(rawTokens.count)
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
