import AVFoundation

/// Captures audio from the microphone and delivers PCM 16-bit 16kHz mono chunks.
final class AudioCaptureManager {
    /// Called with each audio buffer chunk (PCM 16-bit 16kHz mono).
    var onAudioChunk: ((Data) -> Void)?

    private var audioEngine: AVAudioEngine?
    private var isCapturing = false

    /// The desired output format: PCM 16-bit integer, 16kHz, mono.
    private let outputFormat = AVAudioFormat(
        commonFormat: .pcmFormatInt16,
        sampleRate: 16000,
        channels: 1,
        interleaved: true
    )!

    /// Check if the app has microphone permission.
    static func requestPermission(completion: @escaping (Bool) -> Void) {
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized:
            completion(true)
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .audio) { granted in
                DispatchQueue.main.async { completion(granted) }
            }
        default:
            completion(false)
        }
    }

    func startCapture() throws {
        guard !isCapturing else { return }

        let engine = AVAudioEngine()
        let inputNode = engine.inputNode
        let inputFormat = inputNode.outputFormat(forBus: 0)

        guard let converter = AVAudioConverter(from: inputFormat, to: outputFormat) else {
            throw AudioCaptureError.converterCreationFailed
        }

        inputNode.installTap(onBus: 0, bufferSize: 4096, format: inputFormat) { [weak self] buffer, _ in
            guard let self = self else { return }
            self.convertAndDeliver(buffer: buffer, converter: converter)
        }

        engine.prepare()
        try engine.start()

        audioEngine = engine
        isCapturing = true
    }

    func stopCapture() {
        guard isCapturing else { return }
        audioEngine?.inputNode.removeTap(onBus: 0)
        audioEngine?.stop()
        audioEngine = nil
        isCapturing = false
    }

    private func convertAndDeliver(buffer: AVAudioPCMBuffer, converter: AVAudioConverter) {
        let frameCapacity = AVAudioFrameCount(
            Double(buffer.frameLength) * (outputFormat.sampleRate / buffer.format.sampleRate)
        )
        guard frameCapacity > 0 else { return }

        guard let outputBuffer = AVAudioPCMBuffer(pcmFormat: outputFormat, frameCapacity: frameCapacity) else {
            return
        }

        var error: NSError?
        var inputConsumed = false
        converter.convert(to: outputBuffer, error: &error) { _, outStatus in
            if inputConsumed {
                outStatus.pointee = .noDataNow
                return nil
            }
            inputConsumed = true
            outStatus.pointee = .haveData
            return buffer
        }

        if let error = error {
            print("[AudioCaptureManager] Conversion error: \(error)")
            return
        }

        guard outputBuffer.frameLength > 0 else { return }

        let byteCount = Int(outputBuffer.frameLength) * Int(outputFormat.streamDescription.pointee.mBytesPerFrame)
        guard let int16Data = outputBuffer.int16ChannelData else { return }
        let data = Data(bytes: int16Data[0], count: byteCount)
        onAudioChunk?(data)
    }

    deinit {
        stopCapture()
    }
}

enum AudioCaptureError: Error, LocalizedError {
    case converterCreationFailed

    var errorDescription: String? {
        switch self {
        case .converterCreationFailed:
            return "Failed to create audio format converter"
        }
    }
}
