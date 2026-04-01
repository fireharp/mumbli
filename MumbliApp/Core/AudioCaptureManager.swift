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

    /// Select the specific microphone chosen in Settings (by UID) to prevent
    /// Bluetooth headphones from switching from A2DP to HFP profile.
    /// Falls back to the first built-in microphone if no selection or device not found.
    private func selectPreferredMicrophone() {
        let allDeviceIDs = Self.getAllAudioInputDeviceIDs()
        guard !allDeviceIDs.isEmpty else {
            NSLog("[AudioCaptureManager] No audio input devices found")
            return
        }

        // Save the current default input so we can restore it on stop
        savePreviousDefaultInput()

        // Try the user-selected device from Settings first
        let selectedUID = UserDefaults.standard.string(forKey: "selectedMicrophoneID") ?? ""
        if !selectedUID.isEmpty, let deviceID = Self.findDeviceByUID(selectedUID, among: allDeviceIDs) {
            if setDefaultInputDevice(deviceID) {
                NSLog("[AudioCaptureManager] Set input to user-selected device UID=%@ (device %d)", selectedUID, deviceID)
                return
            }
        }

        // Fallback: find the first built-in microphone
        if let builtInID = Self.findBuiltInMicrophone(among: allDeviceIDs) {
            if setDefaultInputDevice(builtInID) {
                NSLog("[AudioCaptureManager] Fallback: set input to built-in microphone (device %d)", builtInID)
                return
            }
        }

        NSLog("[AudioCaptureManager] No suitable microphone found — using system default")
    }

    /// Get all audio device IDs that have input streams.
    private static func getAllAudioInputDeviceIDs() -> [AudioDeviceID] {
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
        guard status == noErr else { return [] }

        let deviceCount = Int(dataSize) / MemoryLayout<AudioDeviceID>.size
        var deviceIDs = [AudioDeviceID](repeating: 0, count: deviceCount)
        status = AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject),
            &propertyAddress,
            0, nil,
            &dataSize,
            &deviceIDs
        )
        guard status == noErr else { return [] }

        // Filter to only devices with input streams
        return deviceIDs.filter { deviceID in
            var inputStreamAddress = AudioObjectPropertyAddress(
                mSelector: kAudioDevicePropertyStreams,
                mScope: kAudioDevicePropertyScopeInput,
                mElement: kAudioObjectPropertyElementMain
            )
            var streamSize: UInt32 = 0
            let streamStatus = AudioObjectGetPropertyDataSize(deviceID, &inputStreamAddress, 0, nil, &streamSize)
            return streamStatus == noErr && streamSize > 0
        }
    }

    /// Find a CoreAudio device ID by matching its UID string (from AVCaptureDevice.uniqueID).
    private static func findDeviceByUID(_ uid: String, among deviceIDs: [AudioDeviceID]) -> AudioDeviceID? {
        for deviceID in deviceIDs {
            var address = AudioObjectPropertyAddress(
                mSelector: kAudioDevicePropertyDeviceUID,
                mScope: kAudioObjectPropertyScopeGlobal,
                mElement: kAudioObjectPropertyElementMain
            )
            var uidCF: CFString? = nil
            var size = UInt32(MemoryLayout<CFString?>.size)
            let status = AudioObjectGetPropertyData(deviceID, &address, 0, nil, &size, &uidCF)
            if status == noErr, let deviceUID = uidCF as String?, deviceUID == uid {
                return deviceID
            }
        }
        return nil
    }

    /// Find the first built-in microphone by transport type.
    private static func findBuiltInMicrophone(among deviceIDs: [AudioDeviceID]) -> AudioDeviceID? {
        for deviceID in deviceIDs {
            var transportType: UInt32 = 0
            var transportSize = UInt32(MemoryLayout<UInt32>.size)
            var transportAddress = AudioObjectPropertyAddress(
                mSelector: kAudioDevicePropertyTransportType,
                mScope: kAudioObjectPropertyScopeGlobal,
                mElement: kAudioObjectPropertyElementMain
            )
            let status = AudioObjectGetPropertyData(deviceID, &transportAddress, 0, nil, &transportSize, &transportType)
            if status == noErr && transportType == kAudioDeviceTransportTypeBuiltIn {
                return deviceID
            }
        }
        return nil
    }

    /// Save the current system default input device for later restoration.
    private func savePreviousDefaultInput() {
        var currentDefault: AudioDeviceID = 0
        var currentDefaultSize = UInt32(MemoryLayout<AudioDeviceID>.size)
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultInputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        if AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &currentDefaultSize, &currentDefault) == noErr {
            previousDefaultInputDevice = currentDefault
        }
    }

    /// Set a specific input device directly on the AVAudioEngine's input audio unit.
    /// This does NOT change the system default input, so it won't trigger Bluetooth HFP switch.
    private func setInputDeviceOnEngine(engine: AVAudioEngine) {
        let allDeviceIDs = Self.getAllAudioInputDeviceIDs()

        // Try user's selected device first
        var targetDeviceID: AudioDeviceID?
        if let selectedUID = UserDefaults.standard.string(forKey: "selectedMicrophoneID") {
            targetDeviceID = Self.findDeviceByUID(selectedUID, among: allDeviceIDs)
            if targetDeviceID != nil {
                NSLog("[AudioCaptureManager] Setting engine input to user-selected device UID=%@", selectedUID)
            }
        }

        // Fallback: built-in mic
        if targetDeviceID == nil {
            targetDeviceID = Self.findBuiltInMicrophone(among: allDeviceIDs)
            if targetDeviceID != nil {
                NSLog("[AudioCaptureManager] Setting engine input to built-in microphone")
            }
        }

        guard var deviceID = targetDeviceID else {
            NSLog("[AudioCaptureManager] No target device found — using engine default")
            return
        }

        // Set the device on the input node's audio unit via kAudioOutputUnitProperty_CurrentDevice
        let inputNode = engine.inputNode
        let audioUnit = inputNode.audioUnit!
        let status = AudioUnitSetProperty(
            audioUnit,
            kAudioOutputUnitProperty_CurrentDevice,
            kAudioUnitScope_Global,
            0,
            &deviceID,
            UInt32(MemoryLayout<AudioDeviceID>.size)
        )
        if status == noErr {
            NSLog("[AudioCaptureManager] Successfully set engine input device to %d", deviceID)
        } else {
            NSLog("[AudioCaptureManager] Failed to set engine input device (status %d) — using default", status)
        }
    }

    /// Set a specific device as the system default input (DEPRECATED — triggers Bluetooth HFP).
    private func setDefaultInputDevice(_ deviceID: AudioDeviceID) -> Bool {
        var mutableDeviceID = deviceID
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
            &mutableDeviceID
        )
        return status == noErr
    }

    func startCapture() throws {
        guard !isCapturing else { return }

        // Tear down any existing engine before switching devices
        if let existingEngine = audioEngine {
            existingEngine.inputNode.removeTap(onBus: 0)
            existingEngine.stop()
            audioEngine = nil
        }

        // Create engine first, then set the input device directly on the audio unit
        // (NOT via system default, which triggers Bluetooth HFP switch)
        let engine = AVAudioEngine()
        engine.reset()

        let inputNode = engine.inputNode

        // Set the specific mic device on the audio unit — avoids changing system default
        setInputDeviceOnEngine(engine: engine)
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
