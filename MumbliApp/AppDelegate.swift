import Cocoa
import SwiftUI
import AVFoundation

/// App delegate that wires together all core and UI components.
/// Connects: HotkeyManager -> AudioCapture -> ElevenLabs STT -> OpenAI Polish -> TextInjector + HistoryManager
/// Handles first-launch flow, menu bar setup, and UI test launch arguments.
@MainActor
class AppDelegate: NSObject, NSApplicationDelegate {
    // Core
    private let hotkeyManager = HotkeyManager()
    private let audioCaptureManager = AudioCaptureManager()
    private let textInjector = TextInjector()
    private var currentMode: ActivationMode?

    // Services (direct API)
    private let sttService = ElevenLabsSTTService()
    private let groqSTTService = GroqWhisperSTTService()
    private let polishingService = OpenAIPolishingService()
    private let groqPolishingService = GroqPolishingService()

    // Audio accumulation buffer
    private var audioBuffer = Data()

    // UI
    private let historyManager = HistoryManager()
    private var menuBarController: MenuBarController?
    private let overlayController = OverlayController()
    private var firstLaunchWindow: NSWindow?

    // Test mode flags
    private var isUITesting: Bool {
        CommandLine.arguments.contains("--ui-testing")
    }

    // MARK: - App Lifecycle

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSLog("[AppDelegate] applicationDidFinishLaunching")

        if isUITesting {
            NSApp.setActivationPolicy(.regular)
            NSApp.activate(ignoringOtherApps: true)
        }

        handleLaunchArguments()
        setupMenuBar()
        NSLog("[AppDelegate] shouldShowFirstLaunch = %d", shouldShowFirstLaunch())

        if shouldShowFirstLaunch() {
            showFirstLaunchFlow()
        } else {
            startApp()
        }

        handleTestSimulations()
    }

    func applicationWillTerminate(_ notification: Notification) {
        hotkeyManager.stop()
        audioCaptureManager.stopCapture()
    }

    // MARK: - Launch Arguments (UI Testing Support)

    private func handleLaunchArguments() {
        let args = CommandLine.arguments

        if args.contains("--reset-first-launch") {
            UserDefaults.standard.removeObject(forKey: "hasCompletedFirstLaunch")
        }

        if args.contains("--seed-history") {
            seedHistoryForTesting()
        }

        if args.contains("--save-recordings") {
            UserDefaults.standard.set(true, forKey: "debugSaveRecordings")
            NSLog("[AppDelegate] --save-recordings: will save audio to ~/Library/Application Support/Mumbli/recordings/")
        }
    }

    private func handleTestSimulations() {
        let args = CommandLine.arguments

        if args.contains("--simulate-dictation") {
            overlayController.show()
        }

        if args.contains("--simulate-dictation-complete") {
            overlayController.show()
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [weak self] in
                self?.overlayController.dismiss()
            }
        }

        if args.contains("--simulate-dictation-handsfree") {
            overlayController.show(mode: .handsFree)
        }

        if args.contains("--simulate-dictation-processing") {
            overlayController.show()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
                self?.overlayController.showProcessing()
            }
        }

        if args.contains("--test-fn-hold") {
            NSLog("[AppDelegate] --test-fn-hold: will simulate Fn hold in 3s")
            DispatchQueue.main.asyncAfter(deadline: .now() + 3.0) { [weak self] in
                self?.simulateFnHold()
            }
        }

        if args.contains("--test-fn-doubletap") {
            NSLog("[AppDelegate] --test-fn-doubletap: will simulate Fn double-tap in 3s")
            DispatchQueue.main.asyncAfter(deadline: .now() + 3.0) { [weak self] in
                self?.simulateFnDoubleTap()
            }
        }

        if args.contains("--test-inject") {
            NSLog("[AppDelegate] --test-inject: will inject test text in 3s (no mic, no API)")
            DispatchQueue.main.asyncAfter(deadline: .now() + 3.0) { [weak self] in
                guard let self = self else { return }
                let target = TextInjector.captureFocusedTarget()
                NSLog("[AppDelegate] --test-inject: captured target = %@", target?.description ?? "nil")
                let result = self.textInjector.inject(text: "Hello from Mumbli!", target: target)
                NSLog("[AppDelegate] --test-inject: result = %@", "\(result)")
            }
        }

        if args.contains("--test-full") {
            NSLog("[AppDelegate] --test-full: simulating full flow in 3s (no mic, no API)")
            DispatchQueue.main.asyncAfter(deadline: .now() + 3.0) { [weak self] in
                guard let self = self else { return }
                let target = TextInjector.captureFocusedTarget()
                NSLog("[AppDelegate] --test-full: captured target = %@", target?.description ?? "nil")
                self.overlayController.show()
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [weak self] in
                    guard let self = self else { return }
                    let testText = "Test dictation text"
                    let result = self.textInjector.inject(text: testText, target: target)
                    NSLog("[AppDelegate] --test-full: inject result = %@", "\(result)")
                    self.historyManager.addEntry(text: testText)
                    NSLog("[AppDelegate] --test-full: saved to history")
                    self.overlayController.dismiss(afterDelay: 0.3)
                }
            }
        }

        if args.contains("--preview-overlay") {
            showPreviewWindow(
                title: "Overlay Preview",
                view: ListeningIndicatorView(audioLevelProvider: AudioLevelProvider(), mode: .hold),
                size: NSSize(width: 200, height: 80),
                darkBackground: true
            )
            setupOverlayPreviewHotkeys()
            NSLog("[AppDelegate] --preview-overlay: Fn key wired to overlay show/dismiss")
        }

        if args.contains("--preview-settings") {
            showPreviewWindow(
                title: "Settings Preview",
                view: SettingsView(),
                size: NSSize(width: 460, height: 480),
                darkBackground: false
            )
        }
    }

    // MARK: - Component Preview Windows

    private func showPreviewWindow<V: View>(title: String, view: V, size: NSSize, darkBackground: Bool) {
        let controller = NSHostingController(rootView: view)
        let window = NSWindow(contentViewController: controller)
        window.title = title
        window.styleMask = [.titled, .closable, .resizable]
        window.setContentSize(size)
        if darkBackground {
            window.backgroundColor = .black
        }
        window.center()
        window.makeKeyAndOrderFront(nil)
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
    }

    private func setupOverlayPreviewHotkeys() {
        hotkeyManager.onHoldStart = { [weak self] in
            guard let self = self else { return }
            NSLog("[Preview] Hold start — showing overlay with audio")
            try? self.audioCaptureManager.startCapture()
            self.overlayController.show(audioCaptureManager: self.audioCaptureManager)
        }
        hotkeyManager.onHoldStop = { [weak self] in
            guard let self = self else { return }
            NSLog("[Preview] Hold stop — dismissing overlay")
            self.audioCaptureManager.stopCapture()
            self.overlayController.dismiss(afterDelay: 0.3)
        }
        hotkeyManager.onHandsFreeToggle = { [weak self] in
            guard let self = self else { return }
            NSLog("[Preview] Hands-free toggle — showing overlay with audio")
            try? self.audioCaptureManager.startCapture()
            self.overlayController.show(audioCaptureManager: self.audioCaptureManager)
        }
        hotkeyManager.onHandsFreeStop = { [weak self] in
            guard let self = self else { return }
            NSLog("[Preview] Hands-free stop — dismissing overlay")
            self.audioCaptureManager.stopCapture()
            self.overlayController.dismiss(afterDelay: 0.3)
        }
    }

    // MARK: - Synthetic Fn Key Simulation

    private func simulateFnHold() {
        hotkeyManager.resetState()
        NSLog("[AppDelegate] simulateFnHold: sending Fn DOWN")
        hotkeyManager.simulateFnState(fnDown: true)

        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) { [weak self] in
            NSLog("[AppDelegate] simulateFnHold: sending Fn UP")
            self?.hotkeyManager.simulateFnState(fnDown: false)
        }
    }

    private func simulateFnDoubleTap() {
        hotkeyManager.resetState()
        NSLog("[AppDelegate] simulateFnDoubleTap: sending first tap DOWN")
        hotkeyManager.simulateFnState(fnDown: true)

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { [weak self] in
            NSLog("[AppDelegate] simulateFnDoubleTap: sending first tap UP")
            self?.hotkeyManager.simulateFnState(fnDown: false)

            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { [weak self] in
                NSLog("[AppDelegate] simulateFnDoubleTap: sending second tap DOWN")
                self?.hotkeyManager.simulateFnState(fnDown: true)

                DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { [weak self] in
                    NSLog("[AppDelegate] simulateFnDoubleTap: sending second tap UP")
                    self?.hotkeyManager.simulateFnState(fnDown: false)
                }
            }
        }
    }

    private func seedHistoryForTesting() {
        historyManager.addEntry(text: "This is a test dictation entry for UI testing purposes.")
        historyManager.addEntry(text: "Here is another example of dictated text that was polished by the LLM.")
        historyManager.addEntry(text: "Quick voice note from earlier today.")
    }

    // MARK: - First Launch

    private func shouldShowFirstLaunch() -> Bool {
        if isUITesting && !CommandLine.arguments.contains("--reset-first-launch") {
            return false
        }
        if CommandLine.arguments.contains("--reset-first-launch") {
            return true
        }
        return !UserDefaults.standard.bool(forKey: "hasCompletedFirstLaunch")
    }

    private func showFirstLaunchFlow() {
        let firstLaunchView = FirstLaunchView(onComplete: { [weak self] in
            self?.dismissFirstLaunch()
            self?.startApp()
        })

        let controller = NSHostingController(rootView: firstLaunchView)
        let window = NSWindow(contentViewController: controller)
        window.title = "Welcome to Mumbli"
        window.styleMask = [.titled, .closable]
        window.setContentSize(NSSize(width: 400, height: 350))
        window.setAccessibilityIdentifier("mumbli-first-launch")
        window.center()
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)

        self.firstLaunchWindow = window
    }

    private func dismissFirstLaunch() {
        firstLaunchWindow?.orderOut(nil)
        firstLaunchWindow = nil
    }

    // MARK: - App Startup (post first-launch)

    private func startApp() {
        log.log("[AppDelegate] startApp() called")
        if !isUITesting {
            requestPermissions()
            checkGlobeKeySetting()
        }
        setupHotkeyManager()
        setupAudioCallbacks()
        setupRetryObserver()
        log.log("[AppDelegate] startApp() completed — hotkey manager running")
    }

    // MARK: - Menu Bar

    private func setupMenuBar() {
        let controller = MenuBarController(historyManager: historyManager)
        controller.setup()
        menuBarController = controller
    }

    // MARK: - Permissions

    private func requestPermissions() {
        AudioCaptureManager.requestPermission { granted in
            if !granted {
                print("[AppDelegate] Microphone permission denied")
            }
        }

        let trusted = AXIsProcessTrustedWithOptions(
            [kAXTrustedCheckOptionPrompt.takeUnretainedValue(): true] as CFDictionary
        )
        if !trusted {
            print("[AppDelegate] Accessibility permission not yet granted")
        }
    }

    // MARK: - Globe Key Setting Check

    private func checkGlobeKeySetting() {
        // The "Press Globe key to" setting is stored in com.apple.HIToolbox.
        // When set to "Do Nothing", the value is either absent or a specific int.
        // When set to anything else (e.g., "Show Emoji & Symbols", "Start Dictation",
        // "Change Input Source"), macOS intercepts the Fn/Globe key before our event tap.
        //
        // We read the AppleFnUsageType from HIToolbox prefs:
        //   0 = Do Nothing
        //   1 = Change Input Source
        //   2 = Show Emoji & Symbols
        //   3 = Start Dictation (macOS built-in)
        // If not 0, warn the user.

        let hiToolboxDefaults = UserDefaults(suiteName: "com.apple.HIToolbox")
        let fnType = hiToolboxDefaults?.integer(forKey: "AppleFnUsageType") ?? -1

        log.log("[AppDelegate] Globe key setting check: AppleFnUsageType = \(fnType)")

        // fnType == 0 means "Do Nothing" which is what we need.
        // fnType == -1 means the key wasn't found (default behavior, usually "Change Input Source").
        // Any non-zero value means the Globe key is mapped to something that will
        // intercept it before our event tap sees it.
        if fnType != 0 {
            log.log("[AppDelegate] Globe key is NOT set to 'Do Nothing' — showing guidance alert")
            showGlobeKeyAlert()
        } else {
            log.log("[AppDelegate] Globe key is set to 'Do Nothing' — good")
        }
    }

    private func showGlobeKeyAlert() {
        let alert = NSAlert()
        alert.messageText = "Globe Key Setup Required"
        alert.informativeText = """
            Mumbli uses the Globe (🌐) key for dictation, but macOS currently intercepts it.

            To fix this:
            1. Open System Settings → Keyboard
            2. Set "Press 🌐 key to" → "Do Nothing"

            Without this change, the Globe key will trigger the macOS input switcher instead of Mumbli.
            """
        alert.alertStyle = .warning
        alert.addButton(withTitle: "Open Keyboard Settings")
        alert.addButton(withTitle: "Later")

        let response = alert.runModal()
        if response == .alertFirstButtonReturn {
            // Open System Settings → Keyboard
            if let url = URL(string: "x-apple.systempreferences:com.apple.Keyboard-Settings.extension") {
                NSWorkspace.shared.open(url)
            }
        }
    }

    // MARK: - Hotkey Setup

    private func setupHotkeyManager() {
        hotkeyManager.onHoldStart = { [weak self] in
            self?.startDictation(mode: .hold)
        }

        hotkeyManager.onHoldStop = { [weak self] in
            self?.stopDictation()
        }

        hotkeyManager.onHandsFreeToggle = { [weak self] in
            self?.startDictation(mode: .handsFree)
        }

        hotkeyManager.onHandsFreeStop = { [weak self] in
            self?.stopDictation()
        }

        hotkeyManager.start()
    }

    // MARK: - Audio Callbacks

    private func setupAudioCallbacks() {
        audioCaptureManager.onAudioChunk = { [weak self] data in
            self?.audioBuffer.append(data)
        }
    }

    // MARK: - Retry Failed Dictation

    private func setupRetryObserver() {
        NotificationCenter.default.addObserver(
            forName: .mumbliRetryDictation,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard let self = self,
                  let info = notification.userInfo,
                  let entryIDStr = info["entryID"] as? String,
                  let entryID = UUID(uuidString: entryIDStr),
                  let filename = info["recordingFilename"] as? String,
                  !filename.isEmpty else { return }
            Task { @MainActor in
                await self.retryDictation(entryID: entryID, recordingFilename: filename)
            }
        }
    }

    private func retryDictation(entryID: UUID, recordingFilename: String) async {
        let fileURL = HistoryManager.recordingURL(for: recordingFilename)
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            log.log("[Retry] Recording file not found: \(recordingFilename)")
            return
        }

        log.log("[Retry] Reprocessing \(recordingFilename)")

        do {
            // Read the WAV file and strip the 44-byte header to get raw PCM
            let wavData = try Data(contentsOf: fileURL)
            let pcmData = wavData.count > 44 ? wavData.dropFirst(44) : wavData

            // Transcribe
            let engineRaw = UserDefaults.standard.string(forKey: "dictationEngine") ?? DictationEngine.standard.rawValue
            let engine = DictationEngine(rawValue: engineRaw) ?? .standard
            let transcription: String
            if engine.usesGroq {
                transcription = try await groqSTTService.transcribe(audioData: Data(pcmData))
            } else {
                transcription = try await sttService.transcribe(audioData: Data(pcmData))
            }

            guard !transcription.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                log.log("[Retry] Empty transcription for \(recordingFilename)")
                return
            }

            // Polish
            let polishingEnabled = UserDefaults.standard.object(forKey: "polishingEnabled") as? Bool ?? true
            let finalText: String
            if polishingEnabled {
                let prompt = OpenAIPolishingService.resolvedPrompt()
                let polished: String
                if engine.usesGroq {
                    polished = try await groqPolishingService.polish(text: transcription, prompt: prompt)
                } else {
                    let model = OpenAIPolishingService.resolvedModel()
                    polished = try await polishingService.polish(text: transcription, model: model, prompt: prompt)
                }
                finalText = polished.isEmpty ? transcription : polished
            } else {
                finalText = transcription
            }

            // Save transcription file
            RecordingManager.shared.saveTranscription(transcription, for: fileURL)

            // Update the failed entry
            historyManager.resolveEntry(id: entryID, text: finalText)
            log.log("[Retry] Successfully reprocessed \(recordingFilename): \(finalText.prefix(80))...")

        } catch {
            log.log("[Retry] Failed to reprocess \(recordingFilename): \(error)")
        }
    }

    // MARK: - Dictation Flow

    private let log = FileLogger.shared

    private func startDictation(mode: ActivationMode) {
        currentMode = mode
        audioBuffer = Data()

        log.log("[Dictation] startDictation mode=\(mode)")

        overlayController.show(audioCaptureManager: audioCaptureManager, mode: mode)
        NotificationCenter.default.post(name: .mumbliDictationStarted, object: nil)

        do {
            try audioCaptureManager.startCapture()
            log.log("[Dictation] Started capturing audio")
        } catch {
            log.log("[Dictation] Failed to start capture: \(error)")
            NotificationCenter.default.post(
                name: .mumbliDictationError,
                object: nil,
                userInfo: ["error": error.localizedDescription]
            )
        }
    }

    private func stopDictation() {
        log.log("[Dictation] stopDictation called")
        audioCaptureManager.stopCapture()
        NotificationCenter.default.post(name: .mumbliDictationStopped, object: nil)

        let capturedAudio = audioBuffer
        audioBuffer = Data()
        currentMode = nil

        guard !capturedAudio.isEmpty else {
            log.log("[Dictation] No audio captured")
            overlayController.dismiss(afterDelay: 0.3)
            return
        }

        // Capture the focused element and frontmost app BEFORE async processing,
        // since focus will likely shift during transcription + polishing (~1s).
        let capturedTarget = TextInjector.captureFocusedTarget()
        log.log("[Dictation] Captured target before async: \(capturedTarget?.description ?? "nil")")

        // Log current frontmost app at capture time
        let frontApp = NSWorkspace.shared.frontmostApplication
        log.log("[Dictation] Frontmost app at capture: \(frontApp?.bundleIdentifier ?? "nil") pid=\(frontApp?.processIdentifier ?? -1)")

        // Switch overlay to processing state (keeps it visible during transcription + polishing)
        overlayController.showProcessing()

        // Always save recording (needed for retry on failure; useful for benchmarking)
        let savedURL = RecordingManager.shared.saveRecording(pcmData: capturedAudio)
        let recordingFilename = savedURL.lastPathComponent
        log.log("[Dictation] Saved recording: \(recordingFilename)")

        let timer = PipelineTimer()
        let audioDurationSec = Double(capturedAudio.count) / (16000.0 * 2.0)

        Task {
            do {
                // Step 1: Transcribe audio
                let engineRaw = UserDefaults.standard.string(forKey: "dictationEngine") ?? DictationEngine.standard.rawValue
                let engine = DictationEngine(rawValue: engineRaw) ?? .standard
                log.log("[Dictation] Engine: \(engine.displayName) — Sending \(capturedAudio.count) bytes")
                timer.mark("stt_start")
                let transcription: String
                if engine.usesGroq {
                    transcription = try await groqSTTService.transcribe(audioData: capturedAudio)
                } else {
                    transcription = try await sttService.transcribe(audioData: capturedAudio)
                }
                timer.mark("stt_end")

                guard !transcription.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                    log.log("[Dictation] Empty transcription received")
                    overlayController.dismiss(afterDelay: 0.3)
                    return
                }

                log.log("[Dictation] Transcription result: \(transcription)")

                // Save ground-truth transcription alongside recording
                RecordingManager.shared.saveTranscription(transcription, for: savedURL)

                // Step 2: Polish (if enabled)
                let polishingEnabled = UserDefaults.standard.object(forKey: "polishingEnabled") as? Bool ?? true
                let finalText: String
                let polishModel: String
                if polishingEnabled {
                    let prompt = OpenAIPolishingService.resolvedPrompt()
                    let wrappedInput = OpenAIPolishingService.wrapForPolishing(transcription)
                    timer.mark("polish_start")
                    let polished: String
                    if engine.usesGroq {
                        polishModel = "groq-llama-3.1-8b"
                        log.log("[Dictation] Sending transcription to Groq for polishing")
                        polished = try await groqPolishingService.polish(text: wrappedInput, prompt: prompt)
                    } else {
                        let model = OpenAIPolishingService.resolvedModel()
                        polishModel = model
                        log.log("[Dictation] Sending transcription to OpenAI for polishing (model=\(model))")
                        polished = try await polishingService.polish(text: wrappedInput, model: model, prompt: prompt)
                    }
                    timer.mark("polish_end")
                    log.log("[Dictation] Polished result: \(polished)")

                    // Safety guard: detect hallucination, length explosion, tag leakage
                    let guardResult = RepetitionGuard.check(polished: polished, raw: transcription)
                    if guardResult.didIntervene && engine.usesGroq {
                        // Groq failed — retry with GPT-5.4 Nano as fallback
                        log.log("[Dictation] RepetitionGuard intervened: \(guardResult.reason ?? "unknown") — retrying with gpt-5.4-nano")
                        timer.mark("polish_retry_start")
                        let retryPolished = try await polishingService.polish(
                            text: wrappedInput,
                            model: PolishingModel.gpt5_4_nano.rawValue,
                            prompt: prompt
                        )
                        timer.mark("polish_retry_end")
                        log.log("[Dictation] Retry polished result: \(retryPolished)")
                        let retryGuard = RepetitionGuard.check(polished: retryPolished, raw: transcription)
                        if retryGuard.didIntervene {
                            log.log("[Dictation] Retry also failed (\(retryGuard.reason ?? "unknown")) — falling back to raw transcription")
                            finalText = transcription
                        } else {
                            finalText = retryPolished.isEmpty ? transcription : retryPolished
                        }
                    } else if guardResult.didIntervene {
                        log.log("[Dictation] RepetitionGuard intervened: \(guardResult.reason ?? "unknown") — falling back to raw transcription")
                        finalText = guardResult.text.isEmpty ? transcription : guardResult.text
                    } else {
                        finalText = polished.isEmpty ? transcription : polished
                    }
                } else {
                    log.log("[Dictation] Polishing disabled, using raw transcription")
                    polishModel = "none"
                    timer.mark("polish_start")
                    timer.mark("polish_end")
                    finalText = transcription
                }
                log.log("[Dictation] Final text to inject: \(finalText)")

                // Log state just before injection
                let preInjectFrontApp = NSWorkspace.shared.frontmostApplication
                log.log("[Dictation] Pre-inject frontmost app: \(preInjectFrontApp?.bundleIdentifier ?? "nil") pid=\(preInjectFrontApp?.processIdentifier ?? -1)")
                log.log("[Dictation] Captured target still valid? element=\(capturedTarget != nil)")

                // Step 3: Inject into the pre-captured target and save
                log.log("[Dictation] Calling textInjector.inject()")
                timer.mark("inject_start")
                let result = textInjector.inject(text: finalText, target: capturedTarget)
                timer.mark("inject_end")
                log.log("[Dictation] TextInjector result: \(result)")
                historyManager.addEntry(text: finalText, recordingFilename: recordingFilename)
                log.log("[Dictation] Saved to history")

                // Log pipeline metrics
                let metrics = timer.buildMetrics(
                    audioBytes: capturedAudio.count,
                    audioDurationSec: audioDurationSec,
                    sttProvider: engine.usesGroq ? "Groq-Whisper" : "ElevenLabs",
                    polishModel: polishModel
                )
                log.log(metrics.jsonLine)

                NotificationCenter.default.post(
                    name: .mumbliDictationCompleted,
                    object: nil,
                    userInfo: ["text": finalText, "timestamp": Date()]
                )
            } catch {
                log.log("[Dictation] Error in async flow: \(error)")
                log.log("[METRICS] {\"error\":\"\(error.localizedDescription)\",\"total_ms\":\(String(format: "%.1f", timer.totalElapsed()))}")

                // Save a failed entry so the user can retry from history
                historyManager.addFailedEntry(recordingFilename: recordingFilename)
                log.log("[Dictation] Saved failed entry for: \(recordingFilename)")

                NotificationCenter.default.post(
                    name: .mumbliDictationError,
                    object: nil,
                    userInfo: ["error": error.localizedDescription]
                )

                // Show error on overlay (auto-dismisses after 2.5s)
                overlayController.showError(message: error.localizedDescription)
                return
            }

            // Dismiss overlay after successful processing
            overlayController.dismiss(afterDelay: 0.3)
        }
    }
}

// MARK: - Notification Names

extension Notification.Name {
    static let mumbliDictationCompleted = Notification.Name("mumbliDictationCompleted")
    static let mumbliDictationStarted = Notification.Name("mumbliDictationStarted")
    static let mumbliDictationStopped = Notification.Name("mumbliDictationStopped")
    static let mumbliDictationError = Notification.Name("mumbliDictationError")
    static let mumbliRetryDictation = Notification.Name("mumbliRetryDictation")
}
