import Foundation

/// Saves and loads PCM audio recordings for benchmarking.
/// Recordings are stored as WAV files in ~/Library/Application Support/Mumbli/recordings/.
final class RecordingManager {
    static let shared = RecordingManager()

    private let recordingsDir: URL

    private init() {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        recordingsDir = appSupport.appendingPathComponent("Mumbli/recordings")
        try? FileManager.default.createDirectory(at: recordingsDir, withIntermediateDirectories: true)
    }

    /// Save raw PCM data as a WAV file. Returns the file URL.
    @discardableResult
    func saveRecording(pcmData: Data, sampleRate: Int = 16000, channels: Int = 1, bitsPerSample: Int = 16) -> URL {
        let timestamp = Self.timestampFormatter.string(from: Date())
        let filename = "\(timestamp).wav"
        let fileURL = recordingsDir.appendingPathComponent(filename)

        let wavData = Self.addWAVHeader(pcmData: pcmData, sampleRate: sampleRate, channels: channels, bitsPerSample: bitsPerSample)
        try? wavData.write(to: fileURL)
        NSLog("[RecordingManager] Saved recording: %@ (%d bytes PCM, %d bytes WAV)", filename, pcmData.count, wavData.count)
        return fileURL
    }

    /// Save the ground-truth transcription alongside a recording.
    func saveTranscription(_ text: String, for wavURL: URL) {
        let txtURL = wavURL.deletingPathExtension().appendingPathExtension("txt")
        try? text.write(to: txtURL, atomically: true, encoding: .utf8)
        NSLog("[RecordingManager] Saved transcription: %@", txtURL.lastPathComponent)
    }

    /// List all saved recordings, newest first.
    func listRecordings() -> [URL] {
        let files = (try? FileManager.default.contentsOfDirectory(at: recordingsDir, includingPropertiesForKeys: [.creationDateKey], options: .skipsHiddenFiles)) ?? []
        return files
            .filter { $0.pathExtension == "wav" }
            .sorted { a, b in
                let da = (try? a.resourceValues(forKeys: [.creationDateKey]).creationDate) ?? .distantPast
                let db = (try? b.resourceValues(forKeys: [.creationDateKey]).creationDate) ?? .distantPast
                return da > db
            }
    }

    // MARK: - WAV Header

    private static func addWAVHeader(pcmData: Data, sampleRate: Int, channels: Int, bitsPerSample: Int) -> Data {
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

    private static let timestampFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd_HHmmss"
        return f
    }()
}
