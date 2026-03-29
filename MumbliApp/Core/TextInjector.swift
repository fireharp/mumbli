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
    private func injectViaAccessibility(text: String) -> Bool {
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

        let axElement = element as! AXUIElement
        NSLog("[TextInjector] AX: Found focused element")

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
    private func injectViaClipboard(text: String) -> Bool {
        NSLog("[TextInjector] Clipboard: Starting clipboard fallback")
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
