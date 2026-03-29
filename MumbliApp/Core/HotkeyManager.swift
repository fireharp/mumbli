import Cocoa
import os.log

private let logger = Logger(subsystem: "com.mumbli.app", category: "HotkeyManager")

/// Manages Fn key detection for dictation activation.
/// Uses BOTH NSEvent global monitor AND CGEvent tap for maximum reliability.
/// The Fn/Globe key on macOS generates flagsChanged events with the .function
/// modifier flag (NSEvent) or maskSecondaryFn (CGEvent).
///
/// Detects hold (300ms) for hold mode and double-tap (500ms window) for hands-free mode.
final class HotkeyManager {
    /// Called when hold mode should start (Fn held for 300ms+).
    var onHoldStart: (() -> Void)?
    /// Called when hold mode should stop (Fn released after hold).
    var onHoldStop: (() -> Void)?
    /// Called when hands-free mode is toggled on via double-tap.
    var onHandsFreeToggle: (() -> Void)?
    /// Called when hands-free mode should stop (single Fn press while active).
    var onHandsFreeStop: (() -> Void)?

    // NSEvent monitors
    private var globalMonitor: Any?
    private var localMonitor: Any?

    // CGEvent tap (backup approach)
    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?

    // State
    private var fnDownTime: Date?
    private var holdTimer: Timer?
    private var holdReleaseDebounceTimer: Timer?
    private var lastTapTime: Date?
    private var isHolding = false
    private var isHandsFreeActive = false
    private var fnWasDown = false

    private let holdThreshold: TimeInterval = 0.3
    private let doubleTapWindow: TimeInterval = 0.5
    private let holdReleaseDebounce: TimeInterval = 0.15

    func start() {
        // Approach 1: NSEvent global + local monitors
        globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: .flagsChanged) { [weak self] event in
            self?.handleNSEvent(event)
        }
        localMonitor = NSEvent.addLocalMonitorForEvents(matching: .flagsChanged) { [weak self] event in
            self?.handleNSEvent(event)
            return event
        }

        // Approach 2: CGEvent tap as backup (catches events NSEvent might miss)
        let eventMask: CGEventMask = (1 << CGEventType.flagsChanged.rawValue)
        if let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .listenOnly,
            eventsOfInterest: eventMask,
            callback: { _, type, cgEvent, refcon -> Unmanaged<CGEvent>? in
                guard let refcon = refcon, type == .flagsChanged else {
                    return Unmanaged.passUnretained(cgEvent)
                }
                let manager = Unmanaged<HotkeyManager>.fromOpaque(refcon).takeUnretainedValue()
                let fnDown = cgEvent.flags.contains(.maskSecondaryFn)
                DispatchQueue.main.async {
                    manager.handleFnState(fnDown: fnDown, source: "CGEvent")
                }
                return Unmanaged.passUnretained(cgEvent)
            },
            userInfo: Unmanaged.passUnretained(self).toOpaque()
        ) {
            eventTap = tap
            runLoopSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
            CFRunLoopAddSource(CFRunLoopGetMain(), runLoopSource, .commonModes)
            CGEvent.tapEnable(tap: tap, enable: true)
            NSLog("[HotkeyManager] CGEvent tap created successfully")
        } else {
            NSLog("[HotkeyManager] CGEvent tap failed — using NSEvent monitors only")
        }

        NSLog("[HotkeyManager] Started — listening for Fn key")
    }

    func stop() {
        if let globalMonitor {
            NSEvent.removeMonitor(globalMonitor)
        }
        if let localMonitor {
            NSEvent.removeMonitor(localMonitor)
        }
        globalMonitor = nil
        localMonitor = nil

        if let tap = eventTap {
            CGEvent.tapEnable(tap: tap, enable: false)
        }
        if let source = runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes)
        }
        eventTap = nil
        runLoopSource = nil

        holdTimer?.invalidate()
        holdTimer = nil
        holdReleaseDebounceTimer?.invalidate()
        holdReleaseDebounceTimer = nil
    }

    // MARK: - NSEvent handler

    private func handleNSEvent(_ event: NSEvent) {
        let fnDown = event.modifierFlags.contains(.function)
        handleFnState(fnDown: fnDown, source: "NSEvent")
    }

    // MARK: - Unified Fn state handler

    private func handleFnState(fnDown: Bool, source: String) {
        if fnDown && !fnWasDown {
            NSLog("[HotkeyManager] Fn DOWN (\(source))")
            fnWasDown = true
            // Cancel any pending hold-release debounce since Fn is back down
            holdReleaseDebounceTimer?.invalidate()
            holdReleaseDebounceTimer = nil
            handleFnDown()
        } else if !fnDown && fnWasDown {
            NSLog("[HotkeyManager] Fn UP (\(source))")
            fnWasDown = false
            handleFnUp()
        }
    }

    // MARK: - Hold / double-tap logic

    private func handleFnDown() {
        fnDownTime = Date()

        // If hands-free mode is active, a Fn press stops it
        if isHandsFreeActive {
            isHandsFreeActive = false
            DispatchQueue.main.async { [weak self] in
                self?.onHandsFreeStop?()
            }
            return
        }

        // Start hold timer — if Fn is still down after threshold, it's a hold
        holdTimer?.invalidate()
        holdTimer = Timer.scheduledTimer(withTimeInterval: holdThreshold, repeats: false) { [weak self] _ in
            guard let self = self else { return }
            self.isHolding = true
            DispatchQueue.main.async {
                self.onHoldStart?()
            }
        }
    }

    private func handleFnUp() {
        holdTimer?.invalidate()
        holdTimer = nil

        if isHolding {
            // Debounce: wait before confirming release to avoid spurious Fn flag toggles.
            // If Fn comes back down within the debounce window, the timer is cancelled
            // in handleFnState and hold mode continues uninterrupted.
            NSLog("[HotkeyManager] Hold release debounce started (%.0fms)", holdReleaseDebounce * 1000)
            holdReleaseDebounceTimer?.invalidate()
            holdReleaseDebounceTimer = Timer.scheduledTimer(withTimeInterval: holdReleaseDebounce, repeats: false) { [weak self] _ in
                guard let self = self else { return }
                NSLog("[HotkeyManager] Hold release confirmed — stopping hold mode")
                self.isHolding = false
                self.holdReleaseDebounceTimer = nil
                DispatchQueue.main.async {
                    self.onHoldStop?()
                }
            }
            return
        }

        // It was a quick tap (released before hold threshold)
        let now = Date()
        if let lastTap = lastTapTime, now.timeIntervalSince(lastTap) < doubleTapWindow {
            // Double-tap detected — activate hands-free mode
            lastTapTime = nil
            isHandsFreeActive = true
            DispatchQueue.main.async { [weak self] in
                self?.onHandsFreeToggle?()
            }
        } else {
            // First tap — record time, wait for potential second tap
            lastTapTime = now
        }
    }

    // MARK: - Test support

    /// Inject a synthetic Fn state change for testing. Calls the same code path as real events.
    func simulateFnState(fnDown: Bool) {
        handleFnState(fnDown: fnDown, source: "Simulated")
    }

    /// Reset all internal state to idle. Used before running test simulations to avoid contamination from prior events.
    func resetState() {
        holdTimer?.invalidate()
        holdTimer = nil
        holdReleaseDebounceTimer?.invalidate()
        holdReleaseDebounceTimer = nil
        fnDownTime = nil
        lastTapTime = nil
        isHolding = false
        isHandsFreeActive = false
        fnWasDown = false
        NSLog("[HotkeyManager] State reset for testing")
    }

    deinit {
        stop()
    }
}
