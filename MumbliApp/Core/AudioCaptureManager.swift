import AVFoundation
import Combine
import CoreAudio

/// Captures audio from the microphone and delivers PCM 16-bit 16kHz mono chunks.
final class AudioCaptureManager {
    /// Called with each audio buffer chunk (PCM 16-bit 16kHz mono).
    var onAudioChunk: ((Data) -> Void)?

    /// Current normalized microphone input level (0.0-1.0), smoothed with EMA.
    @Published var audioLevel: Float = 0.0

    private var audioEngine: AVAudioEngine?
    private var isCapturing = false
    private var smoothedLevel: Float = 0.0
    private let smoothingAlpha: Float = 0.3
    private var previousDefaultInputDevice: AudioDeviceID?
    private var hasLoggedFormat = false
    private var chunkCount = 0
    private var totalBytesDelivered = 0

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

    /// Force the system default input to the built-in microphone so that
    /// Bluetooth headphones stay on A2DP (high-quality music profile)
    /// instead of switching to HFP (hands-free) when we open the mic.
    private func selectBuiltInMicrophone() {
        var propertyAddress = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDevices,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )

        var dataSize: UInt32 = 0
        var status = AudioObjectGetPropertyDataSize(
            AudioObjectID(kAudioObjectSystemObject),
            &propertyAddress,
            0, nil,
            &dataSize
        )
        guard status == noErr else { return }

        let deviceCount = Int(dataSize) / MemoryLayout<AudioDeviceID>.size
        var deviceIDs = [AudioDeviceID](repeating: 0, count: deviceCount)
        status = AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject),
            &propertyAddress,
            0, nil,
            &dataSize,
            &deviceIDs
        )
        guard status == noErr else { return }

        for deviceID in deviceIDs {
            // Check if this device has input streams
            var inputStreamAddress = AudioObjectPropertyAddress(
                mSelector: kAudioDevicePropertyStreams,
                mScope: kAudioDevicePropertyScopeInput,
                mElement: kAudioObjectPropertyElementMain
            )
            var streamSize: UInt32 = 0
            let streamStatus = AudioObjectGetPropertyDataSize(deviceID, &inputStreamAddress, 0, nil, &streamSize)
            guard streamStatus == noErr, streamSize > 0 else { continue }

            // Get the transport type to identify built-in devices
            var transportType: UInt32 = 0
            var transportSize = UInt32(MemoryLayout<UInt32>.size)
            var transportAddress = AudioObjectPropertyAddress(
                mSelector: kAudioDevicePropertyTransportType,
                mScope: kAudioObjectPropertyScopeGlobal,
                mElement: kAudioObjectPropertyElementMain
            )
            let transportStatus = AudioObjectGetPropertyData(deviceID, &transportAddress, 0, nil, &transportSize, &transportType)
            guard transportStatus == noErr else { continue }

            if transportType == kAudioDeviceTransportTypeBuiltIn {
                // Save current default input so we can restore it on stop
                var currentDefault: AudioDeviceID = 0
                var currentDefaultSize = UInt32(MemoryLayout<AudioDeviceID>.size)
                var defaultReadAddress = AudioObjectPropertyAddress(
                    mSelector: kAudioHardwarePropertyDefaultInputDevice,
                    mScope: kAudioObjectPropertyScopeGlobal,
                    mElement: kAudioObjectPropertyElementMain
                )
                if AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &defaultReadAddress, 0, nil, &currentDefaultSize, &currentDefault) == noErr {
                    previousDefaultInputDevice = currentDefault
                }

                // Set this device as the default input
                var mutableDeviceID = deviceID
                var defaultInputAddress = AudioObjectPropertyAddress(
                    mSelector: kAudioHardwarePropertyDefaultInputDevice,
                    mScope: kAudioObjectPropertyScopeGlobal,
                    mElement: kAudioObjectPropertyElementMain
                )
                let setStatus = AudioObjectSetPropertyData(
                    AudioObjectID(kAudioObjectSystemObject),
                    &defaultInputAddress,
                    0, nil,
                    UInt32(MemoryLayout<AudioDeviceID>.size),
                    &mutableDeviceID
                )
                if setStatus == noErr {
                    NSLog("[AudioCaptureManager] Forced input to built-in microphone (device %d)", deviceID)
                } else {
                    NSLog("[AudioCaptureManager] Failed to set built-in mic as default input: %d", setStatus)
                }
                return
            }
        }
        NSLog("[AudioCaptureManager] No built-in microphone found")
    }

    func startCapture() throws {
        guard !isCapturing else { return }

        // Tear down any existing engine before switching devices
        if let existingEngine = audioEngine {
            existingEngine.inputNode.removeTap(onBus: 0)
            existingEngine.stop()
            audioEngine = nil
        }

        // Force built-in mic to prevent Bluetooth A2DP → HFP switch
        selectBuiltInMicrophone()

        // Create engine after device switch so inputNode picks up the new device
        let engine = AVAudioEngine()
        engine.reset()

        let inputNode = engine.inputNode
        let nativeFormat = inputNode.outputFormat(forBus: 0)

        NSLog("[AudioCaptureManager] Input node native format: %@ (channels=%d, sampleRate=%.0f)", nativeFormat.description, nativeFormat.channelCount, nativeFormat.sampleRate)

        // Guard against invalid format (0 channels or 0 sample rate)
        guard nativeFormat.channelCount > 0, nativeFormat.sampleRate > 0 else {
            NSLog("[AudioCaptureManager] ERROR: Invalid native format — falling back to nil format tap")
            // Use nil format — AVAudioEngine will use the hardware's preferred format
            inputNode.installTap(onBus: 0, bufferSize: 4096, format: nil) { [weak self] buffer, _ in
                guard let self = self else { return }
                self.updateAudioLevel(buffer: buffer)
                // Skip conversion — deliver raw buffer data
                let data = Data(bytes: buffer.floatChannelData![0], count: Int(buffer.frameLength) * MemoryLayout<Float>.size)
                self.onAudioChunk?(data)
            }
            engine.prepare()
            try engine.start()
            audioEngine = engine
            isCapturing = true
            return
        }

        guard let converter = AVAudioConverter(from: nativeFormat, to: outputFormat) else {
            throw AudioCaptureError.converterCreationFailed
        }

        // Install tap using the input node's native format, not the target format.
        // Conversion to PCM 16-bit 16kHz mono happens inside the callback.
        inputNode.installTap(onBus: 0, bufferSize: 4096, format: nativeFormat) { [weak self] buffer, _ in
            guard let self = self else { return }
            self.updateAudioLevel(buffer: buffer)
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
        audioLevel = 0.0
        smoothedLevel = 0.0
        hasLoggedFormat = false
        NSLog("[AudioCaptureManager] Stopped: delivered %d chunks, %d bytes total", chunkCount, totalBytesDelivered)
        chunkCount = 0
        totalBytesDelivered = 0
        restorePreviousInputDevice()
    }

    /// Restore the default input device that was active before we switched to built-in mic.
    private func restorePreviousInputDevice() {
        guard var deviceID = previousDefaultInputDevice else { return }
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultInputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        let status = AudioObjectSetPropertyData(
            AudioObjectID(kAudioObjectSystemObject),
            &address,
            0, nil,
            UInt32(MemoryLayout<AudioDeviceID>.size),
            &deviceID
        )
        if status == noErr {
            NSLog("[AudioCaptureManager] Restored previous default input device (%d)", deviceID)
        }
        previousDefaultInputDevice = nil
    }

    private func updateAudioLevel(buffer: AVAudioPCMBuffer) {
        guard let channelData = buffer.floatChannelData else { return }
        let frames = Int(buffer.frameLength)
        guard frames > 0 else { return }

        // Calculate average power in dB
        var sum: Float = 0
        let data = channelData[0]
        for i in 0..<frames {
            let sample = data[i]
            sum += sample * sample
        }
        let meanSquare = sum / Float(frames)
        let rms = sqrtf(meanSquare)
        let db = 20 * log10f(max(rms, 1e-7))

        // Normalize from dB to 0.0-1.0 (noise floor at -50dB, max at 0dB)
        let normalized = max(0, min(1, (db + 50) / 50))

        // Exponential moving average smoothing
        smoothedLevel = smoothingAlpha * normalized + (1 - smoothingAlpha) * smoothedLevel

        let level = smoothedLevel
        DispatchQueue.main.async { [weak self] in
            self?.audioLevel = level
        }
    }

    private func convertAndDeliver(buffer: AVAudioPCMBuffer, converter: AVAudioConverter) {
        if !hasLoggedFormat {
            hasLoggedFormat = true
            NSLog("[AudioCaptureManager] Converting: input=%@ -> output=%@", buffer.format.description, outputFormat.description)
            NSLog("[AudioCaptureManager] Input: %.0fHz %d-ch, Output: %.0fHz %d-ch",
                  buffer.format.sampleRate, buffer.format.channelCount,
                  outputFormat.sampleRate, outputFormat.channelCount)
        }

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

        chunkCount += 1
        totalBytesDelivered += byteCount

        // Log first few chunks and then every 50th to diagnose audio content
        if chunkCount <= 3 || chunkCount % 50 == 0 {
            var maxAmp: Int16 = 0
            let samples = int16Data[0]
            for i in 0..<Int(outputBuffer.frameLength) {
                let abs = samples[i] < 0 ? -samples[i] : samples[i]
                if abs > maxAmp { maxAmp = abs }
            }
            NSLog("[AudioCaptureManager] Chunk #%d: %d bytes, %d frames, maxAmplitude=%d, totalDelivered=%d",
                  chunkCount, byteCount, outputBuffer.frameLength, maxAmp, totalBytesDelivered)
        }

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
