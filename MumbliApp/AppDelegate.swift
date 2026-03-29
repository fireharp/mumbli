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
        // When running UI tests, force the app into foreground mode.
        // LSUIElement=true keeps the app backgrounded, which prevents
        // XCUITest's automation server from connecting.
        if isUITesting {
            NSApp.setActivationPolicy(.regular)
            NSApp.activate(ignoringOtherApps: true)
        }

        handleLaunchArguments()
        setupMenuBar()

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
    }

    private func seedHistoryForTesting() {
        historyManager.addEntry(text: "This is a test dictation entry for UI testing purposes.")
        historyManager.addEntry(text: "Here is another example of dictated text that was polished by the LLM.")
        historyManager.addEntry(text: "Quick voice note from earlier today.")
    }

    // MARK: - First Launch

    private func shouldShowFirstLaunch() -> Bool {
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
        if !isUITesting {
            requestPermissions()
        }
        setupHotkeyManager()
        setupAudioCallbacks()
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
            print("[Dictation] Error: \(error)")
            NotificationCenter.default.post(
                name: .mumbliDictationError,
                object: nil,
                userInfo: ["error": error]
            )
            self?.cleanupDictation()
        }

        Task {
            do {
                try await client.connect(authToken: authToken)
                try await client.sendStart()
                try audioCaptureManager.startCapture()
            } catch {
                print("[Dictation] Failed to start: \(error)")
                cleanupDictation()
            }
        }
    }

    private func stopDictation() {
        audioCaptureManager.stopCapture()
        NotificationCenter.default.post(name: .mumbliDictationStopped, object: nil)

        Task {
            try? await transcriptionClient?.sendStop()
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
