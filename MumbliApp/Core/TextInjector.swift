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
        if injectViaAccessibility(text: text) {
            return .accessibilityAPI
        }
        if injectViaClipboard(text: text) {
            return .clipboardFallback
        }
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
            return false
        }

        let axElement = element as! AXUIElement

        // Try inserting at the selected text range (replaces selection or inserts at cursor)
        var selectedRange: AnyObject?
        let rangeResult = AXUIElementCopyAttributeValue(
            axElement,
            kAXSelectedTextRangeAttribute as CFString,
            &selectedRange
        )

        if rangeResult == .success {
            let setResult = AXUIElementSetAttributeValue(
                axElement,
                kAXSelectedTextAttribute as CFString,
                text as CFTypeRef
            )
            if setResult == .success {
                return true
            }
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
            let setResult = AXUIElementSetAttributeValue(
                axElement,
                kAXValueAttribute as CFString,
                newValue as CFTypeRef
            )
            return setResult == .success
        }

        return false
    }

    /// Fallback: copy text to pasteboard and simulate Cmd+V.
    private func injectViaClipboard(text: String) -> Bool {
        // Save current pasteboard contents
        let pasteboard = NSPasteboard.general
        let previousContents = pasteboard.string(forType: .string)

        // Set our text
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)

        // Simulate Cmd+V
        let success = simulateCmdV()

        // Restore previous pasteboard contents after a short delay
        if let previous = previousContents {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
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
            return false
        }

        keyDown.flags = .maskCommand
        keyUp.flags = .maskCommand

        keyDown.post(tap: .cghidEventTap)
        keyUp.post(tap: .cghidEventTap)

        return true
    }
}
