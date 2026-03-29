import Cocoa
import ApplicationServices

/// Injects text into the currently focused text field.
/// Primary: Accessibility API (AXUIElement) to insert at cursor.
/// Fallback: NSPasteboard + simulated Cmd+V via CGEvent.
final class TextInjector {

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

        var description: String {
            "CapturedTarget(app=\(appBundleID ?? "nil"), pid=\(appPID.map(String.init) ?? "nil"))"
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
            NSLog("[TextInjector] captureFocusedTarget: No focused element (error: %d)", focusResult.rawValue)
            return nil
        }

        let axElement = element as! AXUIElement

        // Log element role for diagnostics
        var role: AnyObject?
        AXUIElementCopyAttributeValue(axElement, kAXRoleAttribute as CFString, &role)
        NSLog("[TextInjector] captureFocusedTarget: element role = %@", (role as? String) ?? "unknown")

        // Check if the element is settable
        var isSettable: DarwinBoolean = false
        AXUIElementIsAttributeSettable(axElement, kAXSelectedTextAttribute as CFString, &isSettable)
        NSLog("[TextInjector] captureFocusedTarget: selectedText settable = %d", isSettable.boolValue)

        // Capture the frontmost app
        let frontApp = NSWorkspace.shared.frontmostApplication
        let bundleID = frontApp?.bundleIdentifier
        let pid = frontApp?.processIdentifier
        NSLog("[TextInjector] captureFocusedTarget: frontApp = %@ (pid %d)", bundleID ?? "nil", pid ?? -1)

        return CapturedTarget(element: axElement, appBundleID: bundleID, appPID: pid)
    }

    /// Inject text into a previously captured target element. Returns which method was used.
    @discardableResult
    func inject(text: String, target: CapturedTarget?) -> InjectionResult {
        NSLog("[TextInjector] inject() called with text: %@, target: %@", text, target?.description ?? "nil")

        // Try the captured element first
        if let target = target {
            if injectViaAccessibility(text: text, element: target.element) {
                NSLog("[TextInjector] SUCCESS via Accessibility API (captured target)")
                return .accessibilityAPI
            }
            NSLog("[TextInjector] Captured target AX injection failed, trying clipboard with app reactivation")
            if injectViaClipboard(text: text, target: target) {
                NSLog("[TextInjector] SUCCESS via clipboard fallback (captured target)")
                return .clipboardFallback
            }
        }

        // Fall through: try current focused element (legacy path)
        NSLog("[TextInjector] Captured target failed or nil, falling back to current focus")
        return inject(text: text)
    }

    /// Inject text into the focused element. Returns which method was used.
    @discardableResult
    func inject(text: String) -> InjectionResult {
        NSLog("[TextInjector] inject() called with text: %@", text)
        if injectViaAccessibility(text: text) {
            NSLog("[TextInjector] SUCCESS via Accessibility API")
            return .accessibilityAPI
        }
        NSLog("[TextInjector] Accessibility API failed, trying clipboard fallback")
        if injectViaClipboard(text: text) {
            NSLog("[TextInjector] SUCCESS via clipboard fallback")
            return .clipboardFallback
        }
        NSLog("[TextInjector] FAILED — no method worked")
        return .failed("No focused text field found")
    }

    /// Try inserting text via AXUIElement at the focused element's cursor position.
    /// If `element` is provided, use it directly instead of querying the current focus.
    private func injectViaAccessibility(text: String, element providedElement: AXUIElement? = nil) -> Bool {
        let axElement: AXUIElement

        if let provided = providedElement {
            NSLog("[TextInjector] AX: Using pre-captured element")
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
                NSLog("[TextInjector] AX: No focused element found (error: %d)", focusResult.rawValue)
                return false
            }

            axElement = element as! AXUIElement
            NSLog("[TextInjector] AX: Found focused element")
        }

        // Try inserting at the selected text range (replaces selection or inserts at cursor)
        var selectedRange: AnyObject?
        let rangeResult = AXUIElementCopyAttributeValue(
            axElement,
            kAXSelectedTextRangeAttribute as CFString,
            &selectedRange
        )

        if rangeResult == .success {
            NSLog("[TextInjector] AX: Has selected text range, setting selected text")
            let setResult = AXUIElementSetAttributeValue(
                axElement,
                kAXSelectedTextAttribute as CFString,
                text as CFTypeRef
            )
            if setResult == .success {
                NSLog("[TextInjector] AX: Set selected text succeeded")
                return true
            }
            NSLog("[TextInjector] AX: Set selected text failed (error: %d)", setResult.rawValue)
        } else {
            NSLog("[TextInjector] AX: No selected text range (error: %d)", rangeResult.rawValue)
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
            NSLog("[TextInjector] AX: Appending to existing value (len %d -> %d)", current.count, newValue.count)
            let setResult = AXUIElementSetAttributeValue(
                axElement,
                kAXValueAttribute as CFString,
                newValue as CFTypeRef
            )
            if setResult == .success {
                NSLog("[TextInjector] AX: Set full value succeeded")
            } else {
                NSLog("[TextInjector] AX: Set full value failed (error: %d)", setResult.rawValue)
            }
            return setResult == .success
        }

        NSLog("[TextInjector] AX: Could not get current value (error: %d)", valueResult.rawValue)
        return false
    }

    /// Fallback: copy text to pasteboard and simulate Cmd+V.
    /// If a captured target is provided, re-activate the original app before pasting.
    private func injectViaClipboard(text: String, target: CapturedTarget? = nil) -> Bool {
        NSLog("[TextInjector] Clipboard: Starting clipboard fallback")

        // Re-activate the original app if we have a captured target
        if let target = target, let pid = target.appPID {
            if let app = NSRunningApplication(processIdentifier: pid) {
                NSLog("[TextInjector] Clipboard: Re-activating app %@ (pid %d)", target.appBundleID ?? "nil", pid)
                app.activate(options: [.activateIgnoringOtherApps])
                // Brief pause to let the app come to front
                Thread.sleep(forTimeInterval: 0.1)
            } else {
                NSLog("[TextInjector] Clipboard: Could not find running app for pid %d", pid)
            }
        }

        // Save current pasteboard contents
        let pasteboard = NSPasteboard.general
        let previousContents = pasteboard.string(forType: .string)

        // Set our text
        pasteboard.clearContents()
        let setOk = pasteboard.setString(text, forType: .string)
        NSLog("[TextInjector] Clipboard: Set pasteboard string = %d", setOk)

        // Simulate Cmd+V
        let success = simulateCmdV()
        NSLog("[TextInjector] Clipboard: simulateCmdV = %d", success)

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
            NSLog("[TextInjector] Clipboard: Failed to create CGEvent for Cmd+V")
            return false
        }

        keyDown.flags = .maskCommand
        keyUp.flags = .maskCommand

        keyDown.post(tap: .cghidEventTap)
        keyUp.post(tap: .cghidEventTap)
        NSLog("[TextInjector] Clipboard: Posted Cmd+V key events")

        return true
    }
}
