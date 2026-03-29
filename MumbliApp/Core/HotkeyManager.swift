import Cocoa
import Carbon

/// Manages Fn key detection for dictation activation.
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

    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?

    private var fnDownTime: Date?
    private var holdTimer: Timer?
    private var lastTapTime: Date?
    private var isHolding = false
    private var isHandsFreeActive = false

    private let holdThreshold: TimeInterval = 0.3
    private let doubleTapWindow: TimeInterval = 0.5

    func start() {
        let eventMask: CGEventMask = (1 << CGEventType.flagsChanged.rawValue)

        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: eventMask,
            callback: { proxy, type, event, refcon -> Unmanaged<CGEvent>? in
                guard let refcon = refcon else {
                    return Unmanaged.passRetained(event)
                }
                let manager = Unmanaged<HotkeyManager>.fromOpaque(refcon).takeUnretainedValue()
                manager.handleEvent(type: type, event: event)
                return Unmanaged.passRetained(event)
            },
            userInfo: Unmanaged.passUnretained(self).toOpaque()
        ) else {
            print("[HotkeyManager] Failed to create event tap. Accessibility permission required.")
            return
        }

        eventTap = tap
        runLoopSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), runLoopSource, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
    }

    func stop() {
        if let tap = eventTap {
            CGEvent.tapEnable(tap: tap, enable: false)
        }
        if let source = runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes)
        }
        holdTimer?.invalidate()
        holdTimer = nil
        eventTap = nil
        runLoopSource = nil
    }

    private func handleEvent(type: CGEventType, event: CGEvent) {
        guard type == .flagsChanged else { return }

        let flags = event.flags
        let fnPressed = flags.contains(.maskSecondaryFn)

        if fnPressed {
            handleFnDown()
        } else {
            handleFnUp()
        }
    }

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
            // Was holding — stop hold mode
            isHolding = false
            DispatchQueue.main.async { [weak self] in
                self?.onHoldStop?()
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

    deinit {
        stop()
    }
}
