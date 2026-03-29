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

        let wavData = addWAVHeader(pcmData: audioData, sampleRate: 16000, channels: 1, bitsPerSample: 16)

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

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw ElevenLabsError.invalidResponse
        }

        guard httpResponse.statusCode == 200 else {
            let errorBody = String(data: data, encoding: .utf8) ?? "Unknown error"
            throw ElevenLabsError.apiError(statusCode: httpResponse.statusCode, message: errorBody)
        }

        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let text = json["text"] as? String else {
            throw ElevenLabsError.invalidResponse
        }

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
