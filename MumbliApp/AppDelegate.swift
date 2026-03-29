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
    private let polishingService = OpenAIPolishingService()

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

        if args.contains("--preview-overlay") {
            showPreviewWindow(
                title: "Overlay Preview",
                view: ListeningIndicatorView(audioLevelProvider: AudioLevelProvider()),
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
        NSLog("[AppDelegate] startApp() called")
        if !isUITesting {
            requestPermissions()
        }
        setupHotkeyManager()
        setupAudioCallbacks()
        NSLog("[AppDelegate] startApp() completed — hotkey manager running")
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

    // MARK: - Dictation Flow

    private func startDictation(mode: ActivationMode) {
        currentMode = mode
        audioBuffer = Data()

        overlayController.show(audioCaptureManager: audioCaptureManager)
        NotificationCenter.default.post(name: .mumbliDictationStarted, object: nil)

        do {
            try audioCaptureManager.startCapture()
            NSLog("[Dictation] Started capturing audio")
        } catch {
            NSLog("[Dictation] Failed to start capture: %@", "\(error)")
            NotificationCenter.default.post(
                name: .mumbliDictationError,
                object: nil,
                userInfo: ["error": error.localizedDescription]
            )
        }
    }

    private func stopDictation() {
        NSLog("[Dictation] stopDictation called")
        audioCaptureManager.stopCapture()
        NotificationCenter.default.post(name: .mumbliDictationStopped, object: nil)

        let capturedAudio = audioBuffer
        audioBuffer = Data()
        currentMode = nil

        guard !capturedAudio.isEmpty else {
            NSLog("[Dictation] No audio captured")
            overlayController.dismiss(afterDelay: 0.3)
            return
        }

        Task {
            do {
                // Step 1: Transcribe audio via ElevenLabs
                NSLog("[Dictation] Sending %d bytes to ElevenLabs STT", capturedAudio.count)
                let transcription = try await sttService.transcribe(audioData: capturedAudio)

                guard !transcription.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                    NSLog("[Dictation] Empty transcription received")
                    overlayController.dismiss(afterDelay: 0.3)
                    return
                }

                NSLog("[Dictation] Transcription: %@", transcription)

                // Step 2: Polish via OpenAI
                let polished = try await polishingService.polish(text: transcription)
                NSLog("[Dictation] Polished: %@", polished)

                let finalText = polished.isEmpty ? transcription : polished

                // Step 3: Inject and save
                let result = textInjector.inject(text: finalText)
                NSLog("[Dictation] TextInjector result: %@", "\(result)")
                historyManager.addEntry(text: finalText)

                NotificationCenter.default.post(
                    name: .mumbliDictationCompleted,
                    object: nil,
                    userInfo: ["text": finalText, "timestamp": Date()]
                )
            } catch {
                NSLog("[Dictation] Error: %@", "\(error)")
                NotificationCenter.default.post(
                    name: .mumbliDictationError,
                    object: nil,
                    userInfo: ["error": error.localizedDescription]
                )
            }

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
}
