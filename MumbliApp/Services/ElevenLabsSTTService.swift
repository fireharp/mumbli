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
        var maxAmplitude: Int = 0
        var sumSquares: Float = 0
        audioData.withUnsafeBytes { rawBuffer in
            let samples = rawBuffer.bindMemory(to: Int16.self)
            for i in 0..<min(sampleCount, samples.count) {
                let sample = Int(samples[i])
                if sample == 0 { zeroSamples += 1 }
                let magnitude = Swift.abs(sample)
                if magnitude > maxAmplitude { maxAmplitude = magnitude }
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

    /// Transcribe by splitting audio into overlapping 10s chunks, sending in parallel, and stitching.
    /// Falls back to single-batch for audio <= 12s.
    func transcribeChunked(audioData: Data) async throws -> String {
        let bytesPerSec = 16000 * 2
        let audioDuration = Double(audioData.count) / Double(bytesPerSec)

        guard audioDuration > 12.0 else {
            NSLog("[ElevenLabsSTT] Chunked: audio %.1fs <= 12s, falling back to single batch", audioDuration)
            return try await transcribe(audioData: audioData)
        }

        let chunks = splitPCMChunks(pcmData: audioData, chunkSec: 10.0, overlapSec: 2.0)
        NSLog("[ElevenLabsSTT] Chunked: %d chunks from %.1fs audio", chunks.count, audioDuration)

        let results = try await withThrowingTaskGroup(of: (Int, String).self) { group in
            for (index, chunkPCM) in chunks.enumerated() {
                group.addTask {
                    let text = try await self.transcribe(audioData: chunkPCM)
                    return (index, text)
                }
            }
            var ordered = [(Int, String)]()
            for try await result in group {
                ordered.append(result)
            }
            return ordered.sorted { $0.0 < $1.0 }.map { $0.1 }
        }

        let stitched = stitchTranscripts(results)
        NSLog("[ElevenLabsSTT] Chunked stitched result: '%@' (%d chars)", stitched, stitched.count)
        return stitched
    }

    private func splitPCMChunks(pcmData: Data, chunkSec: Double, overlapSec: Double) -> [Data] {
        let bytesPerSec = 16000 * 2
        let chunkBytes = Int(chunkSec * Double(bytesPerSec))
        let overlapBytes = Int(overlapSec * Double(bytesPerSec))
        let stride = chunkBytes - overlapBytes

        var chunks = [Data]()
        var offset = 0
        while offset < pcmData.count {
            let end = min(offset + chunkBytes, pcmData.count)
            let chunk = pcmData.subdata(in: offset..<end)
            chunks.append(chunk)
            offset += stride
            if end >= pcmData.count { break }
        }
        return chunks
    }

    private func stitchTranscripts(_ texts: [String]) -> String {
        guard !texts.isEmpty else { return "" }
        var result = texts[0]

        for i in 1..<texts.count {
            let prevWords = result.split(separator: " ").map(String.init)
            let nextWords = texts[i].split(separator: " ").map(String.init)

            guard !prevWords.isEmpty, !nextWords.isEmpty else {
                result = (result + " " + texts[i]).trimmingCharacters(in: .whitespaces)
                continue
            }

            let searchWindow = min(15, prevWords.count, nextWords.count)
            var bestLen = 0
            var bestPrevStart = prevWords.count
            var bestNextStart = 0

            for pStart in max(0, prevWords.count - searchWindow)..<prevWords.count {
                for nStart in 0..<searchWindow {
                    var run = 0
                    let punctuation = CharacterSet(charactersIn: ".,!?;:\"'")
                    while pStart + run < prevWords.count
                        && nStart + run < nextWords.count
                        && prevWords[pStart + run]
                            .lowercased()
                            .trimmingCharacters(in: punctuation)
                        == nextWords[nStart + run]
                            .lowercased()
                            .trimmingCharacters(in: punctuation) {
                        run += 1
                    }
                    if run >= 2 && run > bestLen {
                        bestLen = run
                        bestPrevStart = pStart
                        bestNextStart = nStart
                    }
                }
            }

            if bestLen >= 2 {
                let kept = prevWords[0..<(bestPrevStart + bestLen)].joined(separator: " ")
                let remaining = Array(nextWords[(bestNextStart + bestLen)...])
                result = kept
                if !remaining.isEmpty {
                    result += " " + remaining.joined(separator: " ")
                }
            } else {
                result = result + " " + texts[i]
            }
        }

        return result.trimmingCharacters(in: .whitespaces)
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
