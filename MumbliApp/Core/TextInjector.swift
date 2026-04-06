import Cocoa
import ApplicationServices

/// Injects text into the currently focused text field.
/// Primary: Accessibility API (AXUIElement) to insert at cursor.
/// Fallback: NSPasteboard + simulated Cmd+V via CGEvent.
final class TextInjector {

    private let log = FileLogger.shared

    enum InjectionResult {
        case accessibilityAPI
        case clipboardFallback
        case failed(String)
    }

    /// Snapshot of the target text field and app captured at dictation start,
    /// before async transcription/polishing shifts focus.
    struct CapturedTarget {
        let element: AXUIElement
        let appBundleID: String?
        let appPID: pid_t?
        let selectedTextSettable: Bool

        var description: String {
            "CapturedTarget(app=\(appBundleID ?? "nil"), pid=\(appPID.map(String.init) ?? "nil"), settable=\(selectedTextSettable))"
        }
    }

    /// Capture the currently focused AXUIElement and the frontmost app.
    /// Call this BEFORE starting any async work so the target is preserved.
    static func captureFocusedTarget() -> CapturedTarget? {
        let systemWide = AXUIElementCreateSystemWide()

        var focusedElement: AnyObject?
        let focusResult = AXUIElementCopyAttributeValue(
            systemWide,
            kAXFocusedUIElementAttribute as CFString,
            &focusedElement
        )

        guard focusResult == .success, let element = focusedElement else {
            FileLogger.shared.log("[TextInjector] captureFocusedTarget: No focused element (error: \(focusResult.rawValue))")
            return nil
        }

        let axElement = element as! AXUIElement

        // Log element role for diagnostics
        var role: AnyObject?
        AXUIElementCopyAttributeValue(axElement, kAXRoleAttribute as CFString, &role)
        FileLogger.shared.log("[TextInjector] captureFocusedTarget: element role = \((role as? String) ?? "unknown")")

        // Check if the element is settable
        var isSettable: DarwinBoolean = false
        AXUIElementIsAttributeSettable(axElement, kAXSelectedTextAttribute as CFString, &isSettable)
        FileLogger.shared.log("[TextInjector] captureFocusedTarget: selectedText settable = \(isSettable.boolValue)")

        // Capture the frontmost app
        let frontApp = NSWorkspace.shared.frontmostApplication
        let bundleID = frontApp?.bundleIdentifier
        let pid = frontApp?.processIdentifier
        FileLogger.shared.log("[TextInjector] captureFocusedTarget: frontApp = \(bundleID ?? "nil") (pid \(pid ?? -1))")

        return CapturedTarget(element: axElement, appBundleID: bundleID, appPID: pid, selectedTextSettable: isSettable.boolValue)
    }

    /// Inject text into a previously captured target element. Returns which method was used.
    @discardableResult
    func inject(text: String, target: CapturedTarget?) -> InjectionResult {
        log.log("[TextInjector] inject(target:) called with text: \(text), target: \(target?.description ?? "nil")")

        // Try the captured element first
        if let target = target {
            if target.selectedTextSettable {
                log.log("[TextInjector] Attempting AX injection with captured target")
                if injectViaAccessibility(text: text, element: target.element) {
                    log.log("[TextInjector] SUCCESS via Accessibility API (captured target)")
                    return .accessibilityAPI
                }
                log.log("[TextInjector] Captured target AX injection failed, trying clipboard with app reactivation")
            } else {
                log.log("[TextInjector] Skipping AX injection — selectedText not settable, going straight to clipboard")
            }
            if injectViaClipboard(text: text, target: target) {
                log.log("[TextInjector] SUCCESS via clipboard fallback (captured target)")
                return .clipboardFallback
            }
        }

        // Fall through: try current focused element (legacy path)
        log.log("[TextInjector] Captured target failed or nil, falling back to current focus")
        return inject(text: text)
    }

    /// Inject text into the focused element. Returns which method was used.
    @discardableResult
    func inject(text: String) -> InjectionResult {
        log.log("[TextInjector] inject() called with text: \(text)")
        if injectViaAccessibility(text: text) {
            log.log("[TextInjector] SUCCESS via Accessibility API")
            return .accessibilityAPI
        }
        log.log("[TextInjector] Accessibility API failed, trying clipboard fallback")
        if injectViaClipboard(text: text) {
            log.log("[TextInjector] SUCCESS via clipboard fallback")
            return .clipboardFallback
        }
        log.log("[TextInjector] FAILED — no method worked")
        return .failed("No focused text field found")
    }

    /// Try inserting text via AXUIElement at the focused element's cursor position.
    /// If `element` is provided, use it directly instead of querying the current focus.
    private func injectViaAccessibility(text: String, element providedElement: AXUIElement? = nil) -> Bool {
        let axElement: AXUIElement

        if let provided = providedElement {
            log.log("[TextInjector] AX: Using pre-captured element")
            axElement = provided
        } else {
            let systemWide = AXUIElementCreateSystemWide()

            var focusedElement: AnyObject?
            let focusResult = AXUIElementCopyAttributeValue(
                systemWide,
                kAXFocusedUIElementAttribute as CFString,
                &focusedElement
            )

            guard focusResult == .success, let element = focusedElement else {
                log.log("[TextInjector] AX: No focused element found (error: \(focusResult.rawValue))")
                return false
            }

            axElement = element as! AXUIElement
            log.log("[TextInjector] AX: Found focused element")
        }

        // Log element role and pid for diagnostics
        var role: AnyObject?
        AXUIElementCopyAttributeValue(axElement, kAXRoleAttribute as CFString, &role)
        var pid: pid_t = 0
        AXUIElementGetPid(axElement, &pid)
        log.log("[TextInjector] AX: element role=\((role as? String) ?? "unknown") pid=\(pid)")

        // Try inserting at the selected text range (replaces selection or inserts at cursor)
        var selectedRange: AnyObject?
        let rangeResult = AXUIElementCopyAttributeValue(
            axElement,
            kAXSelectedTextRangeAttribute as CFString,
            &selectedRange
        )

        if rangeResult == .success {
            log.log("[TextInjector] AX: Has selected text range, setting selected text")
            let setResult = AXUIElementSetAttributeValue(
                axElement,
                kAXSelectedTextAttribute as CFString,
                text as CFTypeRef
            )
            if setResult == .success {
                // Verify the write actually took effect — some apps report success but ignore the write
                var verifyValue: AnyObject?
                let verifyResult = AXUIElementCopyAttributeValue(
                    axElement,
                    kAXValueAttribute as CFString,
                    &verifyValue
                )
                if verifyResult == .success, let currentValue = verifyValue as? String, currentValue.contains(text) {
                    log.log("[TextInjector] AX: Set selected text succeeded (verified)")
                    return true
                }
                log.log("[TextInjector] AX: Set selected text returned success but verification failed — text not found in element value, falling through")
            } else {
                log.log("[TextInjector] AX: Set selected text failed (error: \(setResult.rawValue))")
            }
        } else {
            log.log("[TextInjector] AX: No selected text range (error: \(rangeResult.rawValue))")
        }

        // Fallback: try setting the entire value (appending)
        var currentValue: AnyObject?
        let valueResult = AXUIElementCopyAttributeValue(
            axElement,
            kAXValueAttribute as CFString,
            &currentValue
        )

        if valueResult == .success, let current = currentValue as? String {
            let newValue = current + text
            log.log("[TextInjector] AX: Appending to existing value (len \(current.count) -> \(newValue.count))")
            let setResult = AXUIElementSetAttributeValue(
                axElement,
                kAXValueAttribute as CFString,
                newValue as CFTypeRef
            )
            if setResult == .success {
                // Verify the write actually took effect
                var verifyValue: AnyObject?
                let verifyResult = AXUIElementCopyAttributeValue(
                    axElement,
                    kAXValueAttribute as CFString,
                    &verifyValue
                )
                if verifyResult == .success, let verified = verifyValue as? String, verified.contains(text) {
                    log.log("[TextInjector] AX: Set full value succeeded (verified)")
                    return true
                }
                log.log("[TextInjector] AX: Set full value returned success but verification failed, falling through")
            } else {
                log.log("[TextInjector] AX: Set full value failed (error: \(setResult.rawValue))")
            }
            return false
        }

        log.log("[TextInjector] AX: Could not get current value (error: \(valueResult.rawValue))")
        return false
    }

    /// Fallback: copy text to pasteboard and simulate Cmd+V.
    /// If a captured target is provided, re-activate the original app before pasting.
    private func injectViaClipboard(text: String, target: CapturedTarget? = nil) -> Bool {
        log.log("[TextInjector] Clipboard: Starting clipboard fallback")

        // Re-activate the original app if we have a captured target
        if let target = target, let pid = target.appPID {
            if let app = NSRunningApplication(processIdentifier: pid) {
                log.log("[TextInjector] Clipboard: Re-activating app \(target.appBundleID ?? "nil") (pid \(pid))")
                app.activate(options: [.activateIgnoringOtherApps])
                // Brief pause to let the app come to front
                Thread.sleep(forTimeInterval: 0.1)
                log.log("[TextInjector] Clipboard: App re-activated, isActive=\(app.isActive)")
            } else {
                log.log("[TextInjector] Clipboard: Could not find running app for pid \(pid)")
            }
        }

        // Save current pasteboard contents
        let pasteboard = NSPasteboard.general
        let previousContents = pasteboard.string(forType: .string)

        // Set our text
        pasteboard.clearContents()
        let setOk = pasteboard.setString(text, forType: .string)
        log.log("[TextInjector] Clipboard: Set pasteboard string = \(setOk)")

        // Simulate Cmd+V
        let success = simulateCmdV()
        log.log("[TextInjector] Clipboard: simulateCmdV = \(success)")

        // Restore previous pasteboard contents after a short delay
        if let previous = previousContents {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                pasteboard.clearContents()
                pasteboard.setString(previous, forType: .string)
            }
        }

        return success
    }

    /// Simulate a Cmd+V keypress using CGEvent.
    private func simulateCmdV() -> Bool {
        let source = CGEventSource(stateID: .hidSystemState)

        // Key code for 'V' is 9
        guard let keyDown = CGEvent(keyboardEventSource: source, virtualKey: 9, keyDown: true),
              let keyUp = CGEvent(keyboardEventSource: source, virtualKey: 9, keyDown: false) else {
            log.log("[TextInjector] Clipboard: Failed to create CGEvent for Cmd+V")
            return false
        }

        keyDown.flags = .maskCommand
        keyUp.flags = .maskCommand

        keyDown.post(tap: .cghidEventTap)
        keyUp.post(tap: .cghidEventTap)
        log.log("[TextInjector] Clipboard: Posted Cmd+V key events")

        return true
    }
}
