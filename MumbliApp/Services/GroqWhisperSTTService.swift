import Foundation

/// Groq Whisper STT API client — extremely fast inference via Groq LPU.
/// Uses the OpenAI-compatible transcription endpoint.
final class GroqWhisperSTTService {
    private let endpoint = "https://api.groq.com/openai/v1/audio/transcriptions"
    private let model = "whisper-large-v3-turbo"

    /// Transcribe PCM 16-bit 16kHz mono audio data.
    func transcribe(audioData: Data) async throws -> String {
        guard let apiKey = KeychainManager.shared.get(key: KeychainManager.groqAPIKeyKey) else {
            throw GroqSTTError.missingAPIKey
        }

        let wavData = addWAVHeader(pcmData: audioData, sampleRate: 16000, channels: 1, bitsPerSample: 16)
        NSLog("[GroqWhisperSTT] Sending %.1fs audio (%d bytes WAV)", Double(audioData.count) / (16000.0 * 2.0), wavData.count)

        let boundary = UUID().uuidString
        var request = URLRequest(url: URL(string: endpoint)!)
        request.httpMethod = "POST"
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")

        var body = Data()
        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"model\"\r\n\r\n".data(using: .utf8)!)
        body.append("\(model)\r\n".data(using: .utf8)!)

        if let vocabPrompt = VocabularyStore.whisperPrompt() {
            body.append("--\(boundary)\r\n".data(using: .utf8)!)
            body.append("Content-Disposition: form-data; name=\"prompt\"\r\n\r\n".data(using: .utf8)!)
            body.append("\(vocabPrompt)\r\n".data(using: .utf8)!)
        }

        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"file\"; filename=\"audio.wav\"\r\n".data(using: .utf8)!)
        body.append("Content-Type: audio/wav\r\n\r\n".data(using: .utf8)!)
        body.append(wavData)
        body.append("\r\n".data(using: .utf8)!)
        body.append("--\(boundary)--\r\n".data(using: .utf8)!)

        request.httpBody = body

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw GroqSTTError.invalidResponse
        }

        let responseBody = String(data: data, encoding: .utf8) ?? "<non-UTF8>"
        NSLog("[GroqWhisperSTT] Response status: %d", httpResponse.statusCode)

        guard httpResponse.statusCode == 200 else {
            throw GroqSTTError.apiError(statusCode: httpResponse.statusCode, message: responseBody)
        }

        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let text = json["text"] as? String else {
            throw GroqSTTError.invalidResponse
        }

        NSLog("[GroqWhisperSTT] Result: '%@' (%d chars)", text, text.count)
        return text
    }

    private func addWAVHeader(pcmData: Data, sampleRate: Int, channels: Int, bitsPerSample: Int) -> Data {
        let byteRate = sampleRate * channels * (bitsPerSample / 8)
        let blockAlign = channels * (bitsPerSample / 8)
        let dataSize = pcmData.count
        let fileSize = 36 + dataSize

        var header = Data()
        header.append("RIFF".data(using: .ascii)!)
        header.append(withUnsafeBytes(of: UInt32(fileSize).littleEndian) { Data($0) })
        header.append("WAVE".data(using: .ascii)!)
        header.append("fmt ".data(using: .ascii)!)
        header.append(withUnsafeBytes(of: UInt32(16).littleEndian) { Data($0) })
        header.append(withUnsafeBytes(of: UInt16(1).littleEndian) { Data($0) })
        header.append(withUnsafeBytes(of: UInt16(channels).littleEndian) { Data($0) })
        header.append(withUnsafeBytes(of: UInt32(sampleRate).littleEndian) { Data($0) })
        header.append(withUnsafeBytes(of: UInt32(byteRate).littleEndian) { Data($0) })
        header.append(withUnsafeBytes(of: UInt16(blockAlign).littleEndian) { Data($0) })
        header.append(withUnsafeBytes(of: UInt16(bitsPerSample).littleEndian) { Data($0) })
        header.append("data".data(using: .ascii)!)
        header.append(withUnsafeBytes(of: UInt32(dataSize).littleEndian) { Data($0) })
        return header + pcmData
    }
}

enum GroqSTTError: Error, LocalizedError {
    case missingAPIKey
    case invalidResponse
    case apiError(statusCode: Int, message: String)

    var errorDescription: String? {
        switch self {
        case .missingAPIKey:
            return "Groq API key not configured. Add it in Settings."
        case .invalidResponse:
            return "Invalid response from Groq Whisper API"
        case .apiError(let statusCode, let message):
            return "Groq Whisper API error (\(statusCode)): \(message)"
        }
    }
}
