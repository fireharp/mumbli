import Cocoa
import SwiftUI
import AVFoundation

/// App delegate that wires together all core and UI components.
/// Connects: HotkeyManager -> AudioCapture + OverlayController -> TranscriptionClient -> TextInjector + HistoryManager
/// Handles first-launch flow, menu bar setup, and UI test launch arguments.
@MainActor
class AppDelegate: NSObject, NSApplicationDelegate {
    // Core
    private let hotkeyManager = HotkeyManager()
    private let audioCaptureManager = AudioCaptureManager()
    private let textInjector = TextInjector()
    private var transcriptionClient: TranscriptionClient?
    private var currentMode: ActivationMode?

    // UI
    private let historyManager = HistoryManager()
    private var menuBarController: MenuBarController?
    private let overlayController = OverlayController()
    private var firstLaunchWindow: NSWindow?

    // Test mode flags
    private var isUITesting: Bool {
        CommandLine.arguments.contains("--ui-testing")
    }

    // Backend URL — configurable via UserDefaults or environment
    private var backendURL: URL {
        if let urlString = UserDefaults.standard.string(forKey: "backendURL"),
           let url = URL(string: urlString) {
            return url
        }
        return URL(string: "ws://localhost:8000")!
    }

    // Auth token — will be provided by auth flow
    private var authToken: String {
        return UserDefaults.standard.string(forKey: "authToken") ?? ""
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
        transcriptionClient?.disconnect()
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
            // Show overlay as if dictation is active
            overlayController.show()
        }

        if args.contains("--simulate-dictation-complete") {
            // Show overlay briefly, then dismiss (simulates completed dictation)
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
            // Show static preview of the component
            showPreviewWindow(
                title: "Overlay Preview",
                view: ListeningIndicatorView(),
                size: NSSize(width: 200, height: 80),
                darkBackground: true
            )
            // Wire hotkey manager to overlay-only flow (no audio/transcription)
            // so real Fn presses trigger show/dismiss on the floating overlay
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

    /// Wire the hotkey manager to only show/dismiss the overlay — no audio, no transcription.
    /// Used by --preview-overlay for interactive e2e testing of the overlay animation.
    /// Note: startApp() already called hotkeyManager.start(), so we just override the callbacks.
    private func setupOverlayPreviewHotkeys() {
        hotkeyManager.onHoldStart = { [weak self] in
            NSLog("[Preview] Hold start — showing overlay")
            self?.overlayController.show()
        }
        hotkeyManager.onHoldStop = { [weak self] in
            NSLog("[Preview] Hold stop — dismissing overlay")
            self?.overlayController.dismiss(afterDelay: 0.3)
        }
        hotkeyManager.onHandsFreeToggle = { [weak self] in
            NSLog("[Preview] Hands-free toggle — showing overlay")
            self?.overlayController.show()
        }
        hotkeyManager.onHandsFreeStop = { [weak self] in
            NSLog("[Preview] Hands-free stop — dismissing overlay")
            self?.overlayController.dismiss(afterDelay: 0.3)
        }
    }

    // MARK: - Synthetic Fn Key Simulation

    /// Simulate Fn hold: DOWN → wait 500ms → UP. Uses HotkeyManager's internal path directly.
    private func simulateFnHold() {
        hotkeyManager.resetState()
        NSLog("[AppDelegate] simulateFnHold: sending Fn DOWN")
        hotkeyManager.simulateFnState(fnDown: true)

        // Hold for 500ms (well past the 300ms hold threshold), then release
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
            NSLog("[AppDelegate] simulateFnHold: sending Fn UP")
            self?.hotkeyManager.simulateFnState(fnDown: false)
        }
    }

    /// Simulate Fn double-tap: tap, wait 200ms, tap. Each tap is DOWN then UP with a short press.
    private func simulateFnDoubleTap() {
        hotkeyManager.resetState()
        NSLog("[AppDelegate] simulateFnDoubleTap: sending first tap DOWN")
        hotkeyManager.simulateFnState(fnDown: true)

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { [weak self] in
            NSLog("[AppDelegate] simulateFnDoubleTap: sending first tap UP")
            self?.hotkeyManager.simulateFnState(fnDown: false)

            // Wait 200ms between taps (within the 500ms double-tap window)
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
            guard let client = self?.transcriptionClient else { return }
            Task {
                try? await client.sendAudio(data: data)
            }
        }
    }

    // MARK: - Dictation Flow

    private func startDictation(mode: ActivationMode) {
        currentMode = mode

        // Show overlay
        overlayController.show()

        // Notify UI
        NotificationCenter.default.post(name: .mumbliDictationStarted, object: nil)

        let client = TranscriptionClient(baseURL: backendURL)
        transcriptionClient = client

        client.onListening = {
            print("[Dictation] Server is listening")
        }

        client.onFinal = { [weak self] text in
            self?.handleFinalText(text)
        }

        client.onError = { [weak self] error in
            NSLog("[Dictation] Error: %@", "\(error)")
            NotificationCenter.default.post(
                name: .mumbliDictationError,
                object: nil,
                userInfo: ["error": error]
            )
            // Don't dismiss overlay on error — let the Fn key release handle it
            self?.transcriptionClient?.disconnect()
            self?.transcriptionClient = nil
        }

        Task {
            do {
                try await client.connect(authToken: authToken)
                try await client.sendStart()
                try audioCaptureManager.startCapture()
                NSLog("[Dictation] Started successfully")
            } catch {
                NSLog("[Dictation] Failed to start: %@", "\(error)")
                // Don't dismiss overlay — it stays until Fn is released
                transcriptionClient?.disconnect()
                transcriptionClient = nil
            }
        }
    }

    private func stopDictation() {
        NSLog("[Dictation] stopDictation called")
        audioCaptureManager.stopCapture()
        NotificationCenter.default.post(name: .mumbliDictationStopped, object: nil)

        // Dismiss overlay immediately on stop
        overlayController.dismiss(afterDelay: 0.3)

        Task {
            try? await transcriptionClient?.sendStop()
            // cleanup after stop completes
            transcriptionClient?.disconnect()
            transcriptionClient = nil
            currentMode = nil
        }
    }

    private func handleFinalText(_ text: String) {
        guard !text.isEmpty else {
            cleanupDictation()
            return
        }

        // Inject text into focused field
        textInjector.inject(text: text)

        // Save to history
        historyManager.addEntry(text: text)

        // Post notification
        NotificationCenter.default.post(
            name: .mumbliDictationCompleted,
            object: nil,
            userInfo: ["text": text, "timestamp": Date()]
        )

        cleanupDictation()
    }

    private func cleanupDictation() {
        transcriptionClient?.disconnect()
        transcriptionClient = nil
        currentMode = nil

        // Dismiss overlay with brief delay for visual feedback
        overlayController.dismiss(afterDelay: 0.3)
    }
}

// MARK: - Notification Names

extension Notification.Name {
    static let mumbliDictationCompleted = Notification.Name("mumbliDictationCompleted")
    static let mumbliDictationStarted = Notification.Name("mumbliDictationStarted")
    static let mumbliDictationStopped = Notification.Name("mumbliDictationStopped")
    static let mumbliDictationError = Notification.Name("mumbliDictationError")
}
