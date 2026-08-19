import AVFoundation
import Foundation

/// Saves and loads audio recordings.
///
/// Every recording is written at capture time regardless of settings, because
/// a failed dictation needs its audio on disk for retry-from-history
/// (`AppDelegate.retryDictation`). Once a dictation's outcome is known, the
/// caller decides whether to keep it: `deleteRecording` removes both the file
/// and its transcript unless the user has enabled Settings > Debug > Save
/// recordings, in which case files persist for benchmarking as before.
/// Recordings are stored in ~/Library/Application Support/Mumbli/recordings/.
///
/// ## Storage format: Opus in a CAF container
///
/// New recordings are compressed to Opus (~26 kbps, ~9.6x smaller than the
/// 16 kHz mono PCM16 WAV this used to write) via plain `AVAudioFile` —
/// in-process, no subprocess, no temp files.
///
/// That plainness was not obvious going in. Every early attempt at writing
/// Opus was tested via `swift script.swift` (top-level interpreter
/// execution), and every one of those tests reported broken, undecodable, or
/// zero-length output. Retesting the exact same code as a real compiled
/// binary (`swiftc`) reversed every one of those results: `AVAudioFile`
/// writes a valid, correctly-durationed Opus file, and reads one back
/// correctly too. The interpreter simply doesn't run Swift's ARC
/// teardown/`deinit` the same way a compiled app does, and `AVAudioFile`
/// relies on that teardown to finalize the file — so every "broken" result
/// was an artifact of the test harness, not the API. Mumbli itself is a
/// compiled app, so this is the code path that matters.
///
/// The one real (non-artifact) finding: `AVEncoderBitRateKey` doesn't hit
/// Opus's target exactly — actual output runs a fairly consistent ~10 kbps
/// above the requested value (verified: 16k/24k/32k requested measured as
/// 26.6k/34.4k/42.0k actual on a real recording). Rather than reverse-engineer
/// a compensation constant tuned to one macOS build's encoder — which could
/// silently drift on a future OS update with nothing to catch it — this
/// requests a plain, documented value and accepts the real output.
///
/// A capability probe runs once per launch (see `probeEncodeCapability`) and
/// caches the result, so a Mac where the Opus encoder is unavailable falls
/// back to AAC-LC, and if that also fails, to the original uncompressed WAV
/// writer. A dictation is never lost to an encoder problem.
final class RecordingManager {
    static let shared = RecordingManager()

    /// Which format `saveRecording` currently targets. Decided once per launch
    /// by `probeEncodeCapability` and cached — every save after the first
    /// reuses the answer rather than re-probing.
    enum EncodeTier {
        case opus
        case aac
        case wav
    }

    private static let sampleRate = 16000.0
    private static let opusBitRate = 16000
    private static let aacBitRate = 32000

    private let recordingsDir: URL
    private lazy var encodeTier: EncodeTier = probeEncodeCapability()

    private init() {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        recordingsDir = appSupport.appendingPathComponent("Mumbli/recordings")
        try? FileManager.default.createDirectory(at: recordingsDir, withIntermediateDirectories: true)
    }

    /// Save raw PCM data as a compressed recording (Opus, falling back to AAC
    /// or WAV per `encodeTier`). Returns the file URL.
    @discardableResult
    func saveRecording(pcmData: Data, sampleRate: Int = 16000, channels: Int = 1, bitsPerSample: Int = 16) -> URL {
        let timestamp = Self.timestampFormatter.string(from: Date())

        switch encodeTier {
        case .opus:
            if let url = encodeCompressed(pcmData: pcmData, formatID: kAudioFormatOpus, fileExtension: "caf", bitRate: Self.opusBitRate, timestamp: timestamp) {
                return url
            }
            NSLog("[RecordingManager] Opus encode failed for %@, falling back to AAC for this save", timestamp)
            fallthrough
        case .aac:
            if let url = encodeCompressed(pcmData: pcmData, formatID: kAudioFormatMPEG4AAC, fileExtension: "m4a", bitRate: Self.aacBitRate, timestamp: timestamp) {
                return url
            }
            NSLog("[RecordingManager] AAC encode failed for %@, falling back to WAV for this save", timestamp)
            fallthrough
        case .wav:
            return saveWAV(pcmData: pcmData, sampleRate: sampleRate, channels: channels, bitsPerSample: bitsPerSample, timestamp: timestamp)
        }
    }

    /// Save the ground-truth transcription alongside a recording.
    func saveTranscription(_ text: String, for recordingURL: URL) {
        let txtURL = recordingURL.deletingPathExtension().appendingPathExtension("txt")
        try? text.write(to: txtURL, atomically: true, encoding: .utf8)
        NSLog("[RecordingManager] Saved transcription: %@", txtURL.lastPathComponent)
    }

    /// Delete a recording and its sibling transcript, if present. Safe to call
    /// on a filename that no longer exists.
    func deleteRecording(named filename: String) {
        let url = recordingsDir.appendingPathComponent(filename)
        let txtURL = url.deletingPathExtension().appendingPathExtension("txt")
        try? FileManager.default.removeItem(at: url)
        try? FileManager.default.removeItem(at: txtURL)
        NSLog("[RecordingManager] Deleted recording: %@", filename)
    }

    /// List all saved recordings, newest first. Covers every format this
    /// class has ever written, so old WAVs and migrated/new Opus or AAC files
    /// all show up.
    func listRecordings() -> [URL] {
        let files = (try? FileManager.default.contentsOfDirectory(at: recordingsDir, includingPropertiesForKeys: [.creationDateKey], options: .skipsHiddenFiles)) ?? []
        return files
            .filter { Self.recordingExtensions.contains($0.pathExtension) }
            .sorted { a, b in
                let da = (try? a.resourceValues(forKeys: [.creationDateKey]).creationDate) ?? .distantPast
                let db = (try? b.resourceValues(forKeys: [.creationDateKey]).creationDate) ?? .distantPast
                return da > db
            }
    }

    /// Full URL for a recording filename in this manager's directory.
    func url(for filename: String) -> URL {
        recordingsDir.appendingPathComponent(filename)
    }

    /// Load a recording as raw 16-bit PCM, regardless of the container it was
    /// saved in.
    func loadPCM(filename: String) -> Data? {
        let fileURL = url(for: filename)
        switch fileURL.pathExtension.lowercased() {
        case "wav":
            return Self.stripWAVHeader(try? Data(contentsOf: fileURL))
        case "caf", "m4a":
            return Self.decodePCM(from: fileURL)
        default:
            return nil
        }
    }

    /// Duration of a recording in seconds, decoding compressed formats via
    /// AVAudioFile. Returns nil if the file can't be read.
    func durationSeconds(filename: String) -> Double? {
        let fileURL = url(for: filename)
        switch fileURL.pathExtension.lowercased() {
        case "wav":
            return Self.wavDurationSeconds(url: fileURL)
        case "caf", "m4a":
            guard let file = try? AVAudioFile(forReading: fileURL), file.processingFormat.sampleRate > 0 else { return nil }
            return Double(file.length) / file.processingFormat.sampleRate
        default:
            return nil
        }
    }

    /// Re-encodes an existing WAV recording into the current encode tier's
    /// format, for RecordingMigrator's backlog pass. Returns the new file's
    /// URL on success. Resumable: if the destination already exists and
    /// verifies (a previous run encoded it but was interrupted before
    /// updating history or deleting the source WAV), that file is reused
    /// rather than re-encoded; if it exists but fails verification (a
    /// previous run was interrupted mid-write), it's discarded and redone.
    /// Returns nil — leaving the source WAV untouched — if the current tier
    /// is `.wav` (nothing to migrate to) or the encode fails.
    func migrateWAV(at wavURL: URL) -> URL? {
        guard encodeTier != .wav else { return nil }
        let fileExtension = encodeTier == .opus ? "caf" : "m4a"
        let destURL = wavURL.deletingPathExtension().appendingPathExtension(fileExtension)

        guard let wavData = try? Data(contentsOf: wavURL), let pcmData = Self.stripWAVHeader(wavData) else { return nil }
        let expectedSeconds = Double(pcmData.count) / (Self.sampleRate * 2.0)

        if FileManager.default.fileExists(atPath: destURL.path), Self.verify(url: destURL, expectedSeconds: expectedSeconds) {
            return destURL
        }

        let formatID: AudioFormatID = encodeTier == .opus ? kAudioFormatOpus : kAudioFormatMPEG4AAC
        let bitRate = encodeTier == .opus ? Self.opusBitRate : Self.aacBitRate
        guard Self.writeCompressed(pcmData: pcmData, formatID: formatID, bitRate: bitRate, to: destURL),
              Self.verify(url: destURL, expectedSeconds: expectedSeconds)
        else {
            try? FileManager.default.removeItem(at: destURL)
            return nil
        }
        return destURL
    }

    // MARK: - Encoding

    /// Runs once, lazily, on first save of the launch. Tries an Opus encode
    /// (then AAC) of a fraction of a second of silence, verifying each result
    /// is actually readable before trusting it, and caches whichever tier
    /// works so every subsequent save this launch skips straight to it.
    private func probeEncodeCapability() -> EncodeTier {
        let silence = Data(count: 3200) // 0.1s of 16kHz mono PCM16 silence
        let probeDir = FileManager.default.temporaryDirectory.appendingPathComponent("mumbli-encode-probe-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: probeDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: probeDir) }

        let opusURL = probeDir.appendingPathComponent("probe.caf")
        if Self.writeCompressed(pcmData: silence, formatID: kAudioFormatOpus, bitRate: Self.opusBitRate, to: opusURL),
           Self.verify(url: opusURL, expectedSeconds: 0.1) {
            NSLog("[RecordingManager] Encode capability: Opus")
            return .opus
        }

        let aacURL = probeDir.appendingPathComponent("probe.m4a")
        if Self.writeCompressed(pcmData: silence, formatID: kAudioFormatMPEG4AAC, bitRate: Self.aacBitRate, to: aacURL),
           Self.verify(url: aacURL, expectedSeconds: 0.1) {
            NSLog("[RecordingManager] Encode capability: Opus unavailable, falling back to AAC")
            return .aac
        }

        NSLog("[RecordingManager] Encode capability: Opus and AAC unavailable, falling back to WAV")
        return .wav
    }

    private func encodeCompressed(pcmData: Data, formatID: AudioFormatID, fileExtension: String, bitRate: Int, timestamp: String) -> URL? {
        let outURL = recordingsDir.appendingPathComponent("\(timestamp).\(fileExtension)")
        let expectedSeconds = Double(pcmData.count) / (Self.sampleRate * 2.0)
        guard Self.writeCompressed(pcmData: pcmData, formatID: formatID, bitRate: bitRate, to: outURL),
              Self.verify(url: outURL, expectedSeconds: expectedSeconds)
        else {
            try? FileManager.default.removeItem(at: outURL)
            return nil
        }
        let size = (try? FileManager.default.attributesOfItem(atPath: outURL.path)[.size] as? Int) ?? nil
        NSLog("[RecordingManager] Saved recording: %@.%@ (%d bytes PCM, %d bytes compressed)", timestamp, fileExtension, pcmData.count, size ?? -1)
        return outURL
    }

    private func saveWAV(pcmData: Data, sampleRate: Int, channels: Int, bitsPerSample: Int, timestamp: String) -> URL {
        let outURL = recordingsDir.appendingPathComponent("\(timestamp).wav")
        let wavData = Self.addWAVHeader(pcmData: pcmData, sampleRate: sampleRate, channels: channels, bitsPerSample: bitsPerSample)
        try? wavData.write(to: outURL)
        NSLog("[RecordingManager] Saved recording: %@ (%d bytes PCM, %d bytes WAV)", timestamp, pcmData.count, wavData.count)
        return outURL
    }

    /// Writes 16kHz mono Int16 PCM as a compressed file via AVAudioFile.
    /// Shared by both the Opus and AAC tiers — only the format ID and bitrate
    /// differ. Returns false on any construction/conversion/write failure
    /// rather than throwing, since every caller just wants a yes/no to decide
    /// whether to fall back a tier.
    ///
    /// For Opus/CAF specifically, AVAudioFile reserves a fixed ~236KB 'free'
    /// padding chunk in every file it writes, regardless of content size —
    /// found by comparing a 0.1s recording's WAV (3.2KB) against the Opus file
    /// it produced (241KB, i.e. 74x *larger*). Real audio payload was only 134
    /// bytes; the rest was this one padding chunk, identical byte-for-byte
    /// across every file regardless of duration. `stripCAFFreeChunk` removes
    /// it — CAF chunks are read sequentially with no absolute-offset
    /// cross-references, so dropping one is safe, verified by decoding the
    /// result both via `AVAudioFile` and independently via `afconvert`.
    private static func writeCompressed(pcmData: Data, formatID: AudioFormatID, bitRate: Int, to url: URL) -> Bool {
        try? FileManager.default.removeItem(at: url)

        let inputFormat = AVAudioFormat(commonFormat: .pcmFormatInt16, sampleRate: sampleRate, channels: 1, interleaved: true)!
        let frameCount = AVAudioFrameCount(pcmData.count / 2)
        guard let inputBuffer = AVAudioPCMBuffer(pcmFormat: inputFormat, frameCapacity: max(frameCount, 1)) else { return false }
        inputBuffer.frameLength = frameCount
        if frameCount > 0 {
            let wrote: Bool = pcmData.withUnsafeBytes { raw in
                guard let base = raw.bindMemory(to: Int16.self).baseAddress else { return false }
                inputBuffer.int16ChannelData![0].update(from: base, count: Int(frameCount))
                return true
            }
            guard wrote else { return false }
        }

        let settings: [String: Any] = [
            AVFormatIDKey: formatID,
            AVSampleRateKey: sampleRate,
            AVNumberOfChannelsKey: 1,
            AVEncoderBitRateKey: bitRate,
        ]
        // var, not let: explicitly niled below to force AVAudioFile's
        // deinit-time header finalization to run before this function reads
        // the file's raw bytes to strip padding. Relying on scope-exit alone
        // leaves the exact release point unspecified across build configs.
        // A single `var` binding, force-unwrapped at each use rather than
        // copied into a second `let` constant: a second binding would hold
        // its own strong reference, and setting *this* one to nil afterward
        // would then no longer be what triggers deinit — silently
        // reintroducing the exact race this whole dance exists to avoid.
        var outputFile: AVAudioFile?
        do {
            outputFile = try AVAudioFile(forWriting: url, settings: settings)
        } catch {
            return false
        }
        guard outputFile != nil else { return false }

        // AVAudioFile always wants Float32 for a compressed processingFormat,
        // regardless of the settings dict's format ID -- convert our Int16
        // capture buffer to whatever it actually asks for.
        guard let converter = AVAudioConverter(from: inputFormat, to: outputFile!.processingFormat),
              let convertedBuffer = AVAudioPCMBuffer(pcmFormat: outputFile!.processingFormat, frameCapacity: frameCount)
        else { return false }

        var fed = false
        var conversionError: NSError?
        converter.convert(to: convertedBuffer, error: &conversionError) { _, outStatus in
            if fed { outStatus.pointee = .endOfStream; return nil }
            fed = true
            outStatus.pointee = .haveData
            return inputBuffer
        }
        guard conversionError == nil else { return false }

        do {
            try outputFile!.write(from: convertedBuffer)
        } catch {
            return false
        }
        outputFile = nil // the only strong reference — this line is what actually finalizes the file

        if formatID == kAudioFormatOpus {
            stripCAFFreeChunk(at: url)
        }
        return true
    }

    /// Rewrites a CAF file with any top-level 'free' chunk removed. Best
    /// effort: leaves the file untouched on any unexpected structure rather
    /// than risk corrupting a file that already wrote and verified correctly
    /// — the padding is wasteful, not harmful, so silently keeping it is a
    /// safe failure mode.
    private static func stripCAFFreeChunk(at url: URL) {
        guard let data = try? Data(contentsOf: url),
              data.count >= 8, data[data.startIndex..<data.startIndex+4].elementsEqual(Data("caff".utf8))
        else { return }

        var out = Data(data[data.startIndex..<data.startIndex+8]) // magic + version + flags
        var pos = 8
        var droppedAny = false
        while pos + 12 <= data.count {
            let typeRange = (data.startIndex+pos)..<(data.startIndex+pos+4)
            let sizeRange = (data.startIndex+pos+4)..<(data.startIndex+pos+12)
            let chunkType = data[typeRange]
            let size = sizeRange.reduce(Int64(0)) { acc, i in (acc << 8) | Int64(data[i]) }

            if size < 0 {
                // "until EOF" sentinel some writers use for a trailing chunk —
                // copy the remainder verbatim and stop.
                out.append(data[(data.startIndex+pos)...])
                break
            }
            let chunkTotal = 12 + Int(size)
            guard pos + chunkTotal <= data.count else { return } // malformed; bail without writing anything

            if chunkType.elementsEqual(Data("free".utf8)) {
                droppedAny = true
            } else {
                out.append(data[(data.startIndex+pos)..<(data.startIndex+pos+chunkTotal)])
            }
            pos += chunkTotal
            if size == 0 && !chunkType.elementsEqual(Data("free".utf8)) { break }
        }

        guard droppedAny else { return }
        try? out.write(to: url)
    }

    /// Confirms a just-written compressed file is actually readable and its
    /// duration is plausible, rather than trusting a successful write() call
    /// alone. Cheap now that AVAudioFile reads are confirmed reliable.
    private static func verify(url: URL, expectedSeconds: Double) -> Bool {
        guard let file = try? AVAudioFile(forReading: url), file.processingFormat.sampleRate > 0 else { return false }
        let actualSeconds = Double(file.length) / file.processingFormat.sampleRate
        return file.length > 0 && abs(actualSeconds - expectedSeconds) < 0.1
    }

    /// Decodes a compressed recording to raw 16kHz mono Int16 PCM.
    private static func decodePCM(from url: URL) -> Data? {
        guard let file = try? AVAudioFile(forReading: url) else { return nil }
        guard let decodedBuffer = AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: AVAudioFrameCount(file.length)),
              (try? file.read(into: decodedBuffer)) != nil
        else { return nil }

        let outputFormat = AVAudioFormat(commonFormat: .pcmFormatInt16, sampleRate: sampleRate, channels: 1, interleaved: true)!
        guard let converter = AVAudioConverter(from: file.processingFormat, to: outputFormat),
              let outputBuffer = AVAudioPCMBuffer(pcmFormat: outputFormat, frameCapacity: decodedBuffer.frameLength)
        else { return nil }

        var fed = false
        var conversionError: NSError?
        converter.convert(to: outputBuffer, error: &conversionError) { _, outStatus in
            if fed { outStatus.pointee = .endOfStream; return nil }
            fed = true
            outStatus.pointee = .haveData
            return decodedBuffer
        }
        guard conversionError == nil, let channelData = outputBuffer.int16ChannelData else { return nil }
        return Data(bytes: channelData[0], count: Int(outputBuffer.frameLength) * 2)
    }

    // MARK: - WAV

    private static func stripWAVHeader(_ wavData: Data?) -> Data? {
        guard let wavData, wavData.count > 44 else { return nil }
        return wavData.dropFirst(44)
    }

    /// Reads just the RIFF/fmt/data header fields needed to compute duration,
    /// rather than decoding the file, mirroring the approach
    /// HistoryManager used before compressed formats existed.
    private static func wavDurationSeconds(url: URL) -> Double? {
        guard let handle = FileHandle(forReadingAtPath: url.path) else { return nil }
        defer { handle.closeFile() }
        let header = handle.readData(ofLength: 44)
        guard header.count == 44,
              header[0..<4].elementsEqual(Data("RIFF".utf8)),
              header[8..<12].elementsEqual(Data("WAVE".utf8))
        else { return nil }

        func u16(_ offset: Int) -> UInt16 {
            UInt16(header[header.startIndex + offset]) | (UInt16(header[header.startIndex + offset + 1]) << 8)
        }
        func u32(_ offset: Int) -> UInt32 {
            (0..<4).reduce(UInt32(0)) { acc, i in
                acc | (UInt32(header[header.startIndex + offset + i]) << (8 * i))
            }
        }

        let channels = u16(22)
        let sampleRate = u32(24)
        let bitsPerSample = u16(34)
        let dataSize = u32(40)
        let bytesPerSecond = Double(sampleRate) * Double(channels) * Double(bitsPerSample / 8)
        guard bytesPerSecond > 0 else { return nil }
        return Double(dataSize) / bytesPerSecond
    }

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

    private static let recordingExtensions: Set<String> = ["wav", "caf", "m4a"]

    private static let timestampFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd_HHmmss"
        return f
    }()
}
