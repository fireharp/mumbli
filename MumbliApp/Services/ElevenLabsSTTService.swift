import Foundation

/// Direct ElevenLabs Speech-to-Text API client.
/// Sends accumulated PCM audio as WAV via multipart/form-data POST.
final class ElevenLabsSTTService {
    private let endpoint = "https://api.elevenlabs.io/v1/speech-to-text"
    private let model = "scribe_v1"

    /// Transcribe PCM 16-bit 16kHz mono audio data.
    /// Wraps the raw PCM in a WAV header before uploading.
    func transcribe(audioData: Data) async throws -> String {
        guard let apiKey = KeychainManager.shared.get(key: KeychainManager.elevenLabsAPIKeyKey) else {
            throw ElevenLabsError.missingAPIKey
        }

        NSLog("[ElevenLabsSTT] PCM data: %d bytes (%.1fs at 16kHz/16-bit/mono)", audioData.count, Double(audioData.count) / (16000.0 * 2.0))

        // Analyze PCM content: check for silence / all zeros
        let sampleCount = audioData.count / 2  // 16-bit = 2 bytes per sample
        var zeroSamples = 0
        var maxAmplitude: Int16 = 0
        var sumSquares: Float = 0
        audioData.withUnsafeBytes { rawBuffer in
            let samples = rawBuffer.bindMemory(to: Int16.self)
            for i in 0..<min(sampleCount, samples.count) {
                let sample = samples[i]
                if sample == 0 { zeroSamples += 1 }
                let abs = sample < 0 ? -sample : sample
                if abs > maxAmplitude { maxAmplitude = abs }
                sumSquares += Float(sample) * Float(sample)
            }
        }
        let rms = sampleCount > 0 ? sqrtf(sumSquares / Float(sampleCount)) : 0
        let zeroPercent = sampleCount > 0 ? (Double(zeroSamples) / Double(sampleCount)) * 100.0 : 100.0
        NSLog("[ElevenLabsSTT] PCM analysis: %d samples, %d zero (%.1f%%), maxAmplitude=%d, RMS=%.1f",
              sampleCount, zeroSamples, zeroPercent, maxAmplitude, rms)

        if zeroPercent > 99.0 {
            NSLog("[ElevenLabsSTT] WARNING: Audio is effectively silence (%.1f%% zero samples)", zeroPercent)
        }

        let wavData = addWAVHeader(pcmData: audioData, sampleRate: 16000, channels: 1, bitsPerSample: 16)
        NSLog("[ElevenLabsSTT] WAV data: %d bytes (44-byte header + %d PCM)", wavData.count, audioData.count)

        // Validate WAV header bytes
        let headerHex = wavData.prefix(44).map { String(format: "%02X", $0) }.joined(separator: " ")
        NSLog("[ElevenLabsSTT] WAV header (44 bytes): %@", headerHex)

        let boundary = UUID().uuidString
        var request = URLRequest(url: URL(string: endpoint)!)
        request.httpMethod = "POST"
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        request.setValue(apiKey, forHTTPHeaderField: "xi-api-key")

        var body = Data()

        // model field
        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"model_id\"\r\n\r\n".data(using: .utf8)!)
        body.append("\(model)\r\n".data(using: .utf8)!)

        // audio file field
        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"file\"; filename=\"audio.wav\"\r\n".data(using: .utf8)!)
        body.append("Content-Type: audio/wav\r\n\r\n".data(using: .utf8)!)
        body.append(wavData)
        body.append("\r\n".data(using: .utf8)!)

        // closing boundary
        body.append("--\(boundary)--\r\n".data(using: .utf8)!)

        request.httpBody = body

        NSLog("[ElevenLabsSTT] Sending request (%d bytes body)", body.count)
        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw ElevenLabsError.invalidResponse
        }

        let responseBody = String(data: data, encoding: .utf8) ?? "<non-UTF8 data, \(data.count) bytes>"
        NSLog("[ElevenLabsSTT] Response status: %d, body: %@", httpResponse.statusCode, responseBody)

        guard httpResponse.statusCode == 200 else {
            throw ElevenLabsError.apiError(statusCode: httpResponse.statusCode, message: responseBody)
        }

        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let text = json["text"] as? String else {
            NSLog("[ElevenLabsSTT] Failed to parse JSON or missing 'text' field")
            throw ElevenLabsError.invalidResponse
        }

        NSLog("[ElevenLabsSTT] Transcription result: '%@' (%d chars)", text, text.count)
        return text
    }

    /// Create a WAV file header and prepend it to raw PCM data.
    private func addWAVHeader(pcmData: Data, sampleRate: Int, channels: Int, bitsPerSample: Int) -> Data {
        let byteRate = sampleRate * channels * (bitsPerSample / 8)
        let blockAlign = channels * (bitsPerSample / 8)
        let dataSize = pcmData.count
        let fileSize = 36 + dataSize

        var header = Data()

        // RIFF header
        header.append("RIFF".data(using: .ascii)!)
        header.append(withUnsafeBytes(of: UInt32(fileSize).littleEndian) { Data($0) })
        header.append("WAVE".data(using: .ascii)!)

        // fmt sub-chunk
        header.append("fmt ".data(using: .ascii)!)
        header.append(withUnsafeBytes(of: UInt32(16).littleEndian) { Data($0) })       // sub-chunk size
        header.append(withUnsafeBytes(of: UInt16(1).littleEndian) { Data($0) })        // PCM format
        header.append(withUnsafeBytes(of: UInt16(channels).littleEndian) { Data($0) }) // channels
        header.append(withUnsafeBytes(of: UInt32(sampleRate).littleEndian) { Data($0) })
        header.append(withUnsafeBytes(of: UInt32(byteRate).littleEndian) { Data($0) })
        header.append(withUnsafeBytes(of: UInt16(blockAlign).littleEndian) { Data($0) })
        header.append(withUnsafeBytes(of: UInt16(bitsPerSample).littleEndian) { Data($0) })

        // data sub-chunk
        header.append("data".data(using: .ascii)!)
        header.append(withUnsafeBytes(of: UInt32(dataSize).littleEndian) { Data($0) })

        return header + pcmData
    }
}

enum ElevenLabsError: Error, LocalizedError {
    case missingAPIKey
    case invalidResponse
    case apiError(statusCode: Int, message: String)

    var errorDescription: String? {
        switch self {
        case .missingAPIKey:
            return "ElevenLabs API key not configured. Add it in Settings."
        case .invalidResponse:
            return "Invalid response from ElevenLabs API"
        case .apiError(let statusCode, let message):
            return "ElevenLabs API error (\(statusCode)): \(message)"
        }
    }
}
