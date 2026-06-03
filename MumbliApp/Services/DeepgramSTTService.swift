import Foundation

/// Deepgram pre-recorded STT API client.
/// Sends accumulated PCM audio as WAV via POST body.
final class DeepgramSTTService {
    private let endpoint = "https://api.deepgram.com/v1/listen?model=nova-3&smart_format=true"

    /// Transcribe PCM 16-bit 16kHz mono audio data.
    func transcribe(audioData: Data) async throws -> String {
        guard let apiKey = KeychainManager.shared.get(key: KeychainManager.deepgramAPIKeyKey) else {
            throw DeepgramSTTError.missingAPIKey
        }

        let wavData = addWAVHeader(pcmData: audioData, sampleRate: 16000, channels: 1, bitsPerSample: 16)
        NSLog("[DeepgramSTT] Sending %.1fs audio (%d bytes WAV)", Double(audioData.count) / (16000.0 * 2.0), wavData.count)

        var request = URLRequest(url: URL(string: endpoint)!)
        request.httpMethod = "POST"
        request.setValue("Token \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("audio/wav", forHTTPHeaderField: "Content-Type")
        request.httpBody = wavData

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw DeepgramSTTError.invalidResponse
        }

        let responseBody = String(data: data, encoding: .utf8) ?? "<non-UTF8>"
        NSLog("[DeepgramSTT] Response status: %d", httpResponse.statusCode)

        guard httpResponse.statusCode == 200 else {
            throw DeepgramSTTError.apiError(statusCode: httpResponse.statusCode, message: responseBody)
        }

        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let results = json["results"] as? [String: Any],
              let channels = results["channels"] as? [[String: Any]],
              let firstChannel = channels.first,
              let alternatives = firstChannel["alternatives"] as? [[String: Any]],
              let firstAlternative = alternatives.first,
              let transcript = firstAlternative["transcript"] as? String else {
            throw DeepgramSTTError.invalidResponse
        }

        NSLog("[DeepgramSTT] Result: '%@' (%d chars)", transcript, transcript.count)
        return transcript
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

enum DeepgramSTTError: Error, LocalizedError {
    case missingAPIKey
    case invalidResponse
    case apiError(statusCode: Int, message: String)

    var errorDescription: String? {
        switch self {
        case .missingAPIKey:
            return "Deepgram API key not configured. Add it in Settings."
        case .invalidResponse:
            return "Invalid response from Deepgram API"
        case .apiError(let statusCode, let message):
            return "Deepgram API error (\(statusCode)): \(message)"
        }
    }
}
